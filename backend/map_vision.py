import cv2
import numpy as np

video_path = "/app/input/match.mp4"
cap = cv2.VideoCapture(video_path)

minimap_roi = {"x": 1075, "y": 516, "w": 202, "h": 192}

frame_count = 0
fps = cap.get(cv2.CAP_PROP_FPS)

# 時系列比較用の変数
prev_near_red_pixels = 0 

print("カメラ追跡・自キャラ判定付きの解析を開始します...")

while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        break
        
    frame_count += 1
    current_time_sec = frame_count / fps
    
    if frame_count % 5 != 0:
        continue

    mx, my, mw, mh = minimap_roi["x"], minimap_roi["y"], minimap_roi["w"], minimap_roi["h"]
    minimap_crop = frame[my:my+mh, mx:mx+mw]
    hsv_minimap = cv2.cvtColor(minimap_crop, cv2.COLOR_BGR2HSV)
    
    # ------------------------------------------
    # 1. カメラ枠（白色）の検出（条件を大幅に緩和）
    # ------------------------------------------
    # 明度下限を 180 -> 120 に下げて、グレーがかった枠も拾う
    lower_white = np.array([0, 0, 120])     
    upper_white = np.array([180, 50, 255])  
    white_mask = cv2.inRange(hsv_minimap, lower_white, upper_white)
    
    contours, _ = cv2.findContours(white_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cam_x, cam_y = None, None
    max_area = 0
    for contour in contours:
        area = cv2.contourArea(contour)
        # 枠の一部だけでも拾えるように最小面積を 30 -> 15 に
        if area > 15 and area > max_area:
            max_area = area
            M = cv2.moments(contour)
            if M["m00"] != 0:
                cam_x = int(M["m10"] / M["m00"])
                cam_y = int(M["m01"] / M["m00"])

    # デバッグ用：そもそもカメラ枠が見つかっていない場合のログ
    if cam_x is None:
        # print(f"DEBUG: [{current_time_sec:.2f}秒] カメラ枠（白）自体が見つかりません")
        pass

    # ------------------------------------------
    # 2. カメラ枠の中に「自分（青/水色/緑）」がいるかの判定（範囲と色を拡大）
    # ------------------------------------------
    is_me_in_camera = False
    my_x, my_y = None, None

    if cam_x is not None and cam_y is not None:
        # 青〜水色〜少し緑っぽさまでカバーできるように Hueの範囲を 90-130 -> 35-140 に超拡大
        lower_blue = np.array([35, 40, 40])
        upper_blue = np.array([140, 255, 255])
        blue_mask = cv2.inRange(hsv_minimap, lower_blue, upper_blue)
        
        # 探索範囲を 30 -> 60 ピクセルに広げてカメラ枠のほぼ全域を探す
        h, w = blue_mask.shape
        roi_x1 = max(0, cam_x - 60)
        roi_x2 = min(w, cam_x + 60)
        roi_y1 = max(0, cam_y - 60)
        roi_y2 = min(h, cam_y + 60)
        
        near_blue_pixels = cv2.countNonZero(blue_mask[roi_y1:roi_y2, roi_x1:roi_x2])
        
        # 判定ピクセル数を 5 -> 1 に（1画素でも青・緑があれば自分とみなす）
        if near_blue_pixels >= 1: 
            is_me_in_camera = True
            my_x, my_y = cam_x, cam_y 
        else:
            # カメラ枠は見つかるのに自分を見失っている場合のログ（ここが多ければ色設定の調整が必要）
            # print(f"DEBUG: [{current_time_sec:.2f}秒] 枠はあったが、中に自キャラ（青/緑）が見つかりません (近傍ピクセル数: {near_blue_pixels})")
            pass

    # ------------------------------------------
    # 3. 自分の周囲への「敵の登場（差分）」を検知（登場の基準も少し緩く）
    # ------------------------------------------
    if is_me_in_camera and my_x is not None and my_y is not None:
        lower_red1 = np.array([0, 150, 150]) # 彩度・明度を 180 -> 150 に少し緩めて赤を拾いやすく
        upper_red1 = np.array([10, 255, 255])
        lower_red2 = np.array([170, 150, 150])
        upper_red2 = np.array([180, 255, 255])
        red_mask = cv2.inRange(hsv_minimap, lower_red1, upper_red1) + cv2.inRange(hsv_minimap, lower_red2, upper_red2)
        
        circle_mask = np.zeros_like(red_mask)
        cv2.circle(circle_mask, (my_x, my_y), 60, 255, -1) # 索敵半径を 50 -> 60 に少し拡大
        near_red_mask = cv2.bitwise_and(red_mask, circle_mask)
        
        near_red_pixels = cv2.countNonZero(near_red_mask)
        
        # 登場検知の基準を +50 -> +20 ピクセルに緩く
        if near_red_pixels > prev_near_red_pixels + 20:
            print(f"🚨🚨 [{current_time_sec:.2f}秒] 【警告】自分の周囲に敵が突如出現！ (赤ピクセル: {near_red_pixels})")
            
        prev_near_red_pixels = near_red_pixels
    else:
        prev_near_red_pixels = 0

cap.release()
cv2.destroyAllWindows()
print("解析が完了しました。")