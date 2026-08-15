import os
import uuid

from werkzeug.utils import secure_filename

# ローカルディスク実装。将来AWS化する際はこのモジュールの中身だけをS3実装に
# 差し替えれば良いように、呼び出し側（video_jobs.py / database.py）には
# 常に不透明な参照文字列（video_ref / highlight filename）だけを渡す。
UPLOAD_DIR = os.environ.get("VIDEO_UPLOAD_DIR", "/app/uploads")
HIGHLIGHT_DIR = os.environ.get("VIDEO_HIGHLIGHT_DIR", "/app/highlights")


def save_upload(file_storage):
    os.makedirs(UPLOAD_DIR, exist_ok=True)
    filename = secure_filename(file_storage.filename)
    ref = f"{uuid.uuid4().hex}_{filename}"
    file_storage.save(os.path.join(UPLOAD_DIR, ref))
    return ref


def resolve_upload_path(video_ref):
    return os.path.join(UPLOAD_DIR, video_ref)


def highlight_output_dir(job_id):
    output_dir = os.path.join(HIGHLIGHT_DIR, str(job_id))
    os.makedirs(output_dir, exist_ok=True)
    return output_dir


def list_highlight_refs(job_id, filenames):
    return [f"{job_id}/{filename}" for filename in filenames]
