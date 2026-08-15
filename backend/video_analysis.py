import os

import cv2
import numpy as np
from moviepy.video.io.VideoFileClip import VideoFileClip

# 座標は /Users/admin/apps/movie_analyze/get_coords.py で
# League of Legends May 16 2026.mp4 (1280x720 @ 60fps) を基準に手動キャリブレーションされたもの。
# 別解像度・別HUDスケールの動画では意味を持たない値のため、EXPECTED_RESOLUTION でガードする。
HP_ROI = {"x": 516, "y": 700, "w": 186, "h": 3}
MINIMAP_ROI = {"x": 1075, "y": 516, "w": 202, "h": 192}
EXPECTED_RESOLUTION = (1280, 720)


class UnsupportedResolutionError(Exception):
    pass


def detect_events(video_path):
    cap = cv2.VideoCapture(video_path)
    try:
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        if (width, height) != EXPECTED_RESOLUTION:
            raise UnsupportedResolutionError(
                f"動画の解像度 {width}x{height} には対応していません。"
                f"現在は {EXPECTED_RESOLUTION[0]}x{EXPECTED_RESOLUTION[1]} のみ解析可能です"
                "（HPバー・ミニマップ座標がこの解像度用に手動調整されているため）。"
            )

        fps = cap.get(cv2.CAP_PROP_FPS)
        video_duration = cap.get(cv2.CAP_PROP_FRAME_COUNT) / fps

        frame_count = 0
        prev_hp_ratio = None
        prev_near_red_pixels = 0
        last_danger_time = -999.0
        last_death_time = -999.0
        detected_events = []

        mx, my, mw, mh = MINIMAP_ROI["x"], MINIMAP_ROI["y"], MINIMAP_ROI["w"], MINIMAP_ROI["h"]
        hx, hy, hw, hh = HP_ROI["x"], HP_ROI["y"], HP_ROI["w"], HP_ROI["h"]

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            frame_count += 1
            current_time_sec = frame_count / fps

            if frame_count % 3 != 0:
                continue

            # ミニマップ視界解析（カメラ枠＆敵登場）
            minimap_crop = frame[my:my + mh, mx:mx + mw]
            hsv_minimap = cv2.cvtColor(minimap_crop, cv2.COLOR_BGR2HSV)

            lower_white = np.array([0, 0, 120])
            upper_white = np.array([180, 50, 255])
            white_mask = cv2.inRange(hsv_minimap, lower_white, upper_white)
            contours, _ = cv2.findContours(white_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            cam_x, cam_y = None, None
            max_area = 0
            for contour in contours:
                area = cv2.contourArea(contour)
                if area > 15 and area > max_area:
                    max_area = area
                    m = cv2.moments(contour)
                    if m["m00"] != 0:
                        cam_x = int(m["m10"] / m["m00"])
                        cam_y = int(m["m01"] / m["m00"])

            is_me_in_camera = False
            if cam_x is not None and cam_y is not None:
                lower_blue = np.array([35, 40, 40])
                upper_blue = np.array([140, 255, 255])
                blue_mask = cv2.inRange(hsv_minimap, lower_blue, upper_blue)

                h, w = blue_mask.shape
                roi_x1, roi_x2 = max(0, cam_x - 60), min(w, cam_x + 60)
                roi_y1, roi_y2 = max(0, cam_y - 60), min(h, cam_y + 60)
                if cv2.countNonZero(blue_mask[roi_y1:roi_y2, roi_x1:roi_x2]) >= 1:
                    is_me_in_camera = True

            if is_me_in_camera:
                lower_red1 = np.array([0, 150, 150])
                upper_red1 = np.array([10, 255, 255])
                lower_red2 = np.array([170, 150, 150])
                upper_red2 = np.array([180, 255, 255])
                red_mask = cv2.inRange(hsv_minimap, lower_red1, upper_red1) + cv2.inRange(
                    hsv_minimap, lower_red2, upper_red2
                )

                circle_mask = np.zeros_like(red_mask)
                cv2.circle(circle_mask, (cam_x, cam_y), 60, 255, -1)
                near_red_mask = cv2.bitwise_and(red_mask, circle_mask)
                near_red_pixels = cv2.countNonZero(near_red_mask)

                if near_red_pixels > prev_near_red_pixels + 20:
                    last_danger_time = current_time_sec

                prev_near_red_pixels = near_red_pixels
            else:
                prev_near_red_pixels = 0

            # 自分の生命線（HPバー）解析
            roi = frame[hy:hy + hh, hx:hx + hw]
            hsv_roi = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)

            lower_green = np.array([35, 50, 50])
            upper_green = np.array([85, 255, 255])
            mask = cv2.inRange(hsv_roi, lower_green, upper_green)
            green_pixels = cv2.countNonZero(mask)
            hp_ratio = green_pixels / (hw * hh)

            if prev_hp_ratio is not None:
                if hp_ratio <= 0.02 and prev_hp_ratio > 0.02:
                    if current_time_sec - last_death_time > 20.0:
                        if current_time_sec - last_danger_time <= 15.0:
                            detected_events.append({"time": current_time_sec, "type": "IMPULSE_MISSED"})
                        else:
                            detected_events.append({"time": current_time_sec, "type": "NORMAL_DEATH"})
                        last_death_time = current_time_sec
            prev_hp_ratio = hp_ratio

        return detected_events, video_duration
    finally:
        cap.release()


def cut_highlights(video_path, events, video_duration, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    highlight_filenames = []

    with VideoFileClip(video_path) as video:
        for index, event in enumerate(events, start=1):
            event_time = event["time"]
            event_type = event["type"]
            start_time = max(0, event_time - 15)
            end_time = min(video_duration - 0.1, event_time + 5)

            output_filename = f"highlight_{index}_{event_type}_{int(event_time)}s.mp4"
            output_path = os.path.join(output_dir, output_filename)

            subclip = video.subclipped(start_time, end_time)
            subclip.write_videofile(
                output_path,
                codec="libx264",
                audio_codec="aac",
                logger=None,
            )
            highlight_filenames.append(output_filename)

    return highlight_filenames


def analyze(video_path, output_dir):
    events, video_duration = detect_events(video_path)

    death_count = len(events)
    impulse_missed_count = sum(1 for e in events if e["type"] == "IMPULSE_MISSED")
    normal_death_count = death_count - impulse_missed_count
    impulse_control_failure_ratio = (
        impulse_missed_count / death_count if death_count else 0.0
    )

    highlight_filenames = cut_highlights(video_path, events, video_duration, output_dir)

    return {
        "death_count": death_count,
        "impulse_missed_count": impulse_missed_count,
        "normal_death_count": normal_death_count,
        "impulse_control_failure_ratio": impulse_control_failure_ratio,
        "highlight_filenames": highlight_filenames,
    }
