import json
from concurrent.futures import ThreadPoolExecutor

import psycopg2

import video_analysis
import video_storage

# 小規模なローカルDocker運用を想定した簡易な非同期実行。将来AWS化する際は
# submit_job() の中身をSQSへのsend_messageに、_run_job()の処理をLambda側の
# ハンドラに置き換える想定（create_job/get_job/DBスキーマはそのまま使える）。
_executor = ThreadPoolExecutor(max_workers=2)


def _get_connection():
    # database.py が本モジュールをインポートするため、循環importを避けて
    # 呼び出し時に遅延importする。
    from database import DB_CONFIG

    return psycopg2.connect(**DB_CONFIG)


def create_job(video_ref):
    conn = _get_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO video_analysis_jobs (status, video_ref) VALUES ('pending', %s) RETURNING id;",
            (video_ref,),
        )
        job_id = cur.fetchone()[0]
        conn.commit()
        cur.close()
        return job_id
    finally:
        conn.close()


def submit_job(job_id, video_ref):
    _executor.submit(_run_job, job_id, video_ref)


def _update_status(conn, job_id, **fields):
    set_clause = ", ".join(f"{key} = %s" for key in fields)
    values = list(fields.values()) + [job_id]
    cur = conn.cursor()
    cur.execute(
        f"UPDATE video_analysis_jobs SET {set_clause}, updated_at = CURRENT_TIMESTAMP WHERE id = %s;",
        values,
    )
    conn.commit()
    cur.close()


def _run_job(job_id, video_ref):
    # バックグラウンドスレッドは自前のDBコネクションを持つ（psycopg2のコネクションは
    # スレッド間で共有しない）。
    conn = _get_connection()
    try:
        _update_status(conn, job_id, status="processing")
        video_path = video_storage.resolve_upload_path(video_ref)
        output_dir = video_storage.highlight_output_dir(job_id)

        result = video_analysis.analyze(video_path, output_dir)
        result["highlight_refs"] = video_storage.list_highlight_refs(
            job_id, result.pop("highlight_filenames")
        )

        _update_status(conn, job_id, status="done", result=json.dumps(result))
    except Exception as e:
        _update_status(conn, job_id, status="error", error_message=str(e))
    finally:
        conn.close()


def get_job(job_id):
    conn = _get_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT id, status, result, error_message, created_at, updated_at "
            "FROM video_analysis_jobs WHERE id = %s;",
            (job_id,),
        )
        row = cur.fetchone()
        cur.close()
        if row is None:
            return None
        return {
            "job_id": row[0],
            "status": row[1],
            "result": row[2],
            "error_message": row[3],
            "created_at": row[4].isoformat(),
            "updated_at": row[5].isoformat(),
        }
    finally:
        conn.close()
