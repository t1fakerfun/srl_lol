import psycopg2
import quantificate
import video_jobs
import video_storage
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS  # ★CORSを追加
import os
app = Flask(__name__)
CORS(app)  # ★Flutter Webからのアクセスを許可

DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "db"),
    "database": os.environ.get("DB_NAME", "srl_database"),
    "user": os.environ.get("DB_USER", "srl_user"),
    "password": os.environ.get("DB_PASSWORD", "srl_password"),
}

def init_db():
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    # テーブル名を approved_reflections に統一。カラム名も routine_score に統一
    cur.execute("""
                CREATE TABLE IF NOT EXISTS approved_reflections (
                    id SERIAL PRIMARY KEY,
                    target_type TEXT NOT NULL,
                    routine_score REAL,
                    judgment_logic TEXT, 
                
                    lesson_learned TEXT,
                    srl_score REAL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                """)
    cur.execute("""
                CREATE TABLE IF NOT EXISTS video_analysis_jobs (
                    id SERIAL PRIMARY KEY,
                    status TEXT NOT NULL DEFAULT 'pending',
                    video_ref TEXT NOT NULL,
                    result JSONB,
                    error_message TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                """)
    # approved_reflections は既に存在している可能性があるため、CREATE TABLE IF NOT EXISTS
    # では新カラムが追加されない。ADD COLUMN IF NOT EXISTS で既存DBにも反映させる。
    cur.execute("""
                ALTER TABLE approved_reflections
                    ADD COLUMN IF NOT EXISTS video_job_id INTEGER REFERENCES video_analysis_jobs(id);
                """)
    conn.commit()
    cur.close()
    conn.close()

# gunicorn配下では `if __name__ == '__main__'` を通らずこのモジュールがimportされるだけなので、
# ここでinit_db()を呼んでおかないと本番環境でテーブルが作られない。
init_db()

# ALBのターゲットグループ用ヘルスチェック。DBには触らず、プロセスが生きていることだけを返す。
@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "ok"}), 200

@app.route('/api/reflection', methods=['POST'])
def handle_reflection():
    data = request.get_json()

    print("Received data:", data)

    if data is None:
        return jsonify({"message": "No JSON data received"}), 400

    lesson = data.get('lesson_learned', '')
    # Flutterのキー名（キャメルケース: targetType等）に合わせて受け取る
    target_type = data.get('targetType', '未設定')
    routine_score = data.get('routineScore', 0.0)
    judgment_logic = data.get('judgementLogic', '')
    # 動画解析ジョブ（あれば）と紐付ける。動画解析結果はsrl_scoreの採点基準には使わず、
    # 別指標として保存するだけ。
    video_job_id = data.get('videoJobId')

    srl_score = quantificate.ai_analysis(lesson)
    THRESHOLD = 3.0

    if srl_score >= THRESHOLD:
        conn = psycopg2.connect(**DB_CONFIG)
        cur = conn.cursor()
        # カラム名と変数を修正
        cur.execute("""
            INSERT INTO approved_reflections (target_type, routine_score, judgment_logic, lesson_learned, srl_score, video_job_id)
            VALUES (%s, %s, %s, %s, %s, %s);
                    """, (target_type, routine_score, judgment_logic, lesson, srl_score, video_job_id))
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({"message": "基準をクリアした反省文がデータベースに保存されました。", "score": srl_score}), 200
    else:
        return jsonify({"message": "基準をクリアしなかったため、データベースには保存されませんでした。もう一度壁打ちをしましょう。", "score": srl_score}), 400
    
@app.route('/api/keyword_analysis', methods=['GET'])
def handle_keyword_analysis():
    quantificate.keyword_analysis()
    return jsonify({"message": "初心者反省文の頻出単語トップ20をコンソールに出力しました。"}), 200

@app.route('/api/srl_score', methods=['POST'])
def handle_srl_score():
    data = request.get_json()
    lesson = data.get('lesson_learned', '')
    srl_score = quantificate.ai_analysis(lesson)
    return jsonify({"srl_score": srl_score}), 200

@app.route('/api/reflections', methods=['GET'])
def get_reflections():
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    # id も合わせて取得するように変更
    cur.execute("""
        SELECT ar.id, ar.target_type, ar.routine_score, ar.judgment_logic, ar.lesson_learned,
               ar.srl_score, ar.created_at, vj.status, vj.result
        FROM approved_reflections ar
        LEFT JOIN video_analysis_jobs vj ON vj.id = ar.video_job_id
        ORDER BY ar.created_at DESC;
    """)
    rows = cur.fetchall()
    cur.close()
    conn.close()

    reflections = []
    for row in rows:
        # Report_dbWidget のキー名（'topic', 'content', 'date'）に合わせて辞書を作る
        reflection = {
            "id": row[0],
            "topic": row[1],             # ref['topic'] にマッピング
            "routine_score": row[2],
            "judgment_logic": row[3],
            "content": row[4],           # ref['content'] にマッピング
            "srl_score": row[5],
            "date": row[6].isoformat(),  # ref['date'] にマッピング
            "video_status": row[7],      # 動画未添付ならNULL
            "video_result": row[8],
        }
        reflections.append(reflection)

    return jsonify(reflections), 200

@app.route('/api/video_analysis', methods=['POST'])
def handle_video_upload():
    if 'video' not in request.files or request.files['video'].filename == '':
        return jsonify({"error": "動画ファイルが送信されていません"}), 400

    video_file = request.files['video']
    video_ref = video_storage.save_upload(video_file)
    job_id = video_jobs.create_job(video_ref)
    video_jobs.submit_job(job_id, video_ref)

    return jsonify({"job_id": job_id, "status": "pending"}), 202

@app.route('/api/video_analysis/<int:job_id>', methods=['GET'])
def handle_video_status(job_id):
    job = video_jobs.get_job(job_id)
    if job is None:
        return jsonify({"error": "指定されたジョブが見つかりません"}), 404
    return jsonify(job), 200

# 動画ストリーミング
@app.route('/api/video_analysis/highlights/<path:highlight_ref>', methods=['GET'])
def stream_highlights(highlight_ref):
    job_id , filename = os.path.split(highlight_ref)
    job_id = int(job_id)
    job = video_jobs.get_job(job_id)

    if job is None or job['status'] != 'done' or job['result'] is None:
        return jsonify({"error": "ジョブが見つからないか、処理が完了していません"}), 404
    
    return send_from_directory(os.path.join(video_storage.HIGHLIGHT_DIR, str(job_id)), filename)



if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, threaded=True)