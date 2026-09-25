import psycopg2
import quantificate
import riot_api
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
    # 振り返り履歴をRiot ID単位で絞り込めるようにする。既存行はNULLのままになるが、
    # 誰のものか特定できない以上フィルタ時に出てこないのは想定通りの挙動。
    cur.execute("""
                ALTER TABLE approved_reflections
                    ADD COLUMN IF NOT EXISTS riot_id TEXT;
                """)
    cur.execute("""
                CREATE TABLE IF NOT EXISTS players (
                    id SERIAL PRIMARY KEY,
                    puuid TEXT UNIQUE NOT NULL,
                    game_name TEXT NOT NULL,
                    tag_line TEXT NOT NULL,
                    region TEXT NOT NULL,
                    target_tier TEXT,
                    target_division TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                """)
    cur.execute("""
                CREATE TABLE IF NOT EXISTS rank_snapshots (
                    id SERIAL PRIMARY KEY,
                    player_id INTEGER REFERENCES players(id),
                    queue_type TEXT NOT NULL,
                    tier TEXT NOT NULL,
                    division TEXT,
                    lp INTEGER NOT NULL,
                    wins INTEGER NOT NULL,
                    losses INTEGER NOT NULL,
                    fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                """)
    cur.execute("""
                    ALTER TABLE approved_reflections
                        ADD COLUMN IF NOT EXISTS player_id INTEGER REFERENCES players(id);
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

    if data is None:
        return jsonify({"message": "No JSON data received"}), 400

    player_id = data.get('playerId')
    # Flutter(SRLReflection.toMap)はcamelCaseの'lessonLearned'で送ってくる
    lesson = data.get('lessonLearned', '')
    # Flutterのキー名（キャメルケース: targetType等）に合わせて受け取る
    target_type = data.get('targetType', '未設定')
    routine_score = data.get('routineScore', 0.0)
    judgment_logic = data.get('judgementLogic', '')
    # 動画解析ジョブ（あれば）と紐付ける。動画解析結果はsrl_scoreの採点基準には使わず、
    # 別指標として保存するだけ。
    video_job_id = data.get('videoJobId')
    # User_config画面で設定されたRiot ID。振り返り履歴を本人のものだけに絞り込むためのキー。
    riot_id = (data.get('riotId') or '').strip() or None

    # AI側の失敗は「基準未達(400)」と区別して返す。区別しないとスコア0点扱いになり、
    # 利用者には「内容が薄い」と誤って伝わってしまう。
    try:
        analysis = quantificate.ai_analysis(lesson)
    except quantificate.AnalysisError as e:
        return jsonify({"message": e.message, "error_type": e.kind}), e.status_code
    srl_score = analysis["score"]
    THRESHOLD = 3.0

    if srl_score >= THRESHOLD:
        conn = psycopg2.connect(**DB_CONFIG)
        cur = conn.cursor()
        # カラム名と変数を修正
        cur.execute("""
            INSERT INTO approved_reflections (target_type, routine_score, judgment_logic, lesson_learned, srl_score, video_job_id, riot_id, player_id)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s);
                    """, (target_type, routine_score, judgment_logic, lesson, srl_score, video_job_id, riot_id, player_id))
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({
            "message": "基準をクリアした反省文がデータベースに保存されました。",
            "score": srl_score,
            "good": analysis["good"],
            "questions": analysis["questions"],
        }), 200
    else:
        return jsonify({
            "message": "基準をクリアしなかったため、データベースには保存されませんでした。もう一度壁打ちをしましょう。",
            "score": srl_score,
            "good": analysis["good"],
            "questions": analysis["questions"],
        }), 400
    
@app.route('/api/keyword_analysis', methods=['GET'])
def handle_keyword_analysis():
    quantificate.keyword_analysis()
    return jsonify({"message": "初心者反省文の頻出単語トップ20をコンソールに出力しました。"}), 200

@app.route('/api/srl_score', methods=['POST'])
def handle_srl_score():
    data = request.get_json()
    lesson = data.get('lesson_learned', '')
    try:
        analysis = quantificate.ai_analysis(lesson)
    except quantificate.AnalysisError as e:
        return jsonify({"message": e.message, "error_type": e.kind}), e.status_code
    return jsonify({
        "srl_score": analysis["score"],
        "good": analysis["good"],
        "questions": analysis["questions"],
    }), 200

@app.route('/api/reflections', methods=['GET'])
def get_reflections():
    # player_idを指定すれば本人の振り返りだけに絞り込める。指定なしなら従来通り全件
    # （他人の振り返りも意図的に閲覧できる、という仕様を残すためのフォールバック）。
    player_id = request.args.get('player_id', type=int)

    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    # id も合わせて取得するように変更
    player_id = request.args.get('player_id', type=int)
    if player_id is not None:
        cur.execute("""
            SELECT ar.id, ar.target_type, ar.routine_score, ar.judgment_logic, ar.lesson_learned,
                ar.srl_score, ar.created_at, vj.status, vj.result, ar.player_id,
                p.game_name || '#' || p.tag_line AS author
            FROM approved_reflections ar
            LEFT JOIN video_analysis_jobs vj ON vj.id = ar.video_job_id
            LEFT JOIN players p              ON p.id  = ar.player_id
            WHERE ar.player_id = %s
            ORDER BY ar.created_at DESC;
        """, (player_id,))
    else:
        cur.execute("""
            SELECT ar.id, ar.target_type, ar.routine_score, ar.judgment_logic, ar.lesson_learned,
                    ar.srl_score, ar.created_at, vj.status, vj.result, ar.player_id,
                    p.game_name || '#' || p.tag_line AS author
            FROM approved_reflections ar
            LEFT JOIN video_analysis_jobs vj ON vj.id = ar.video_job_id
            LEFT JOIN players p              ON p.id  = ar.player_id
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
            "player_id": row[9],# 振り返りの作成者ID
            "topic": row[1],             # ref['topic'] にマッピング
            "routine_score": row[2],
            "judgment_logic": row[3],
            "content": row[4],           # ref['content'] にマッピング
            "srl_score": row[5],
            "date": row[6].isoformat(),  # ref['date'] にマッピング
            "video_status": row[7],      # 動画未添付ならNULL
            "video_result": row[8],# 動画未添付ならNULL
            "author": row[10],           # ref['author'] にマッピング
        }
        reflections.append(reflection)

    return jsonify(reflections), 200

@app.route('/api/riot/matches', methods=['GET'])
def handle_riot_matches():
    game_name = request.args.get('gameName')
    tag_line = request.args.get('tagLine')
    region = request.args.get('region')
    count = request.args.get('count', default=10, type=int)

    if not game_name or not tag_line or not region:
        return jsonify({"message": "gameName, tagLine, regionは必須です"}), 400

    try:
        matches = riot_api.get_recent_matches(game_name, tag_line, region, count=count)
        return jsonify(matches), 200
    except riot_api.RiotApiError as e:
        return jsonify({"message": e.message}), e.status_code

@app.route('/api/riot/matches/<match_id>', methods=['GET'])
def handle_riot_match_detail(match_id):
    puuid = request.args.get('puuid')
    region = request.args.get('region')

    if not puuid or not region:
        return jsonify({"message": "puuid, regionは必須です"}), 400

    try:
        result = riot_api.get_match_full(match_id, region, puuid)
        return jsonify(result), 200
    except riot_api.RiotApiError as e:
        return jsonify({"message": e.message}), e.status_code

# TODO(ユーザー実装): POST /api/players/login
#   リクエスト: {"gameName", "tagLine", "region"}
#   Riot APIでPUUIDが見つかればplayersにupsertし、以下を返す:
#     200 {"id", "puuid", "game_name", "tag_line", "region", "target_tier", "target_division"}
#   見つからない等はRiotApiErrorをそのまま {"message"} + e.status_code で返す。

@app.route('/api/players/login', methods=['POST'])
def handle_player_login():
    data = request.get_json()
    game_name = data.get('gameName')
    tag_line = data.get('tagLine')
    region = data.get('region')

    if not game_name or not tag_line or not region:
        return jsonify({"message": "gameName, tagLine, regionは必須です"}), 400

    try:
        puuid = riot_api.get_puuid(game_name, tag_line, region)
        conn = psycopg2.connect(**DB_CONFIG)
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO players (puuid, game_name, tag_line, region)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (puuid) DO UPDATE SET game_name = EXCLUDED.game_name,
                                              tag_line = EXCLUDED.tag_line,
                                              region = EXCLUDED.region
            RETURNING id, puuid, game_name, tag_line, region, target_tier, target_division;
        """, (puuid, game_name, tag_line, region))
        player = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({
            "id": player[0],
            "puuid": player[1],
            "game_name": player[2],
            "tag_line": player[3],
            "region": player[4],
            "target_tier": player[5],
            "target_division": player[6]
        }), 200
    except riot_api.RiotApiError as e:
        return jsonify({"message": e.message}), e.status_code

TIERS = ["IRON", "BRONZE", "SILVER", "GOLD", "PLATINUM", "EMERALD", "DIAMOND",
         "MASTER", "GRANDMASTER", "CHALLENGER"]
DIVISIONS = ["IV", "III", "II", "I"]
APEX_TIERS = {"MASTER", "GRANDMASTER", "CHALLENGER"}


@app.route('/api/players/<int:player_id>/stats', methods=['GET'])
def handle_player_stats(player_id):
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT puuid, region, target_tier, target_division FROM players WHERE id = %s;
        """, (player_id,))
        row = cur.fetchone()
        if row is None:
            return jsonify({"message": "プレイヤーが見つかりません"}), 404
        puuid, region, target_tier, target_division = row

        # 現在ランクの取得に失敗しても、保存済みのランク推移と目標ランクは返す
        ranks = None
        ranks_error = None
        try:
            ranks = riot_api.get_ranked_entries(puuid, region)
        except riot_api.RiotApiError as e:
            ranks_error = e.message

        # 前回と変化があった時だけスナップショットを積む（統計を開くたびに行が増えないように）
        for entry in ranks or []:
            cur.execute("""
                SELECT tier, division, lp FROM rank_snapshots
                WHERE player_id = %s AND queue_type = %s
                ORDER BY fetched_at DESC LIMIT 1;
            """, (player_id, entry["queue_type"]))
            last = cur.fetchone()
            if last != (entry["tier"], entry["division"], entry["lp"]):
                cur.execute("""
                    INSERT INTO rank_snapshots (player_id, queue_type, tier, division, lp, wins, losses)
                    VALUES (%s, %s, %s, %s, %s, %s, %s);
                """, (player_id, entry["queue_type"], entry["tier"], entry["division"],
                      entry["lp"], entry["wins"], entry["losses"]))
        conn.commit()

        cur.execute("""
            SELECT tier, division, lp, fetched_at FROM rank_snapshots
            WHERE player_id = %s AND queue_type = 'RANKED_SOLO_5x5'
            ORDER BY fetched_at ASC;
        """, (player_id,))
        rank_history = [
            {"tier": r[0], "division": r[1], "lp": r[2], "fetched_at": r[3].isoformat()}
            for r in cur.fetchall()
        ]
    finally:
        cur.close()
        conn.close()

    return jsonify({
        "ranks": ranks,
        "ranks_error": ranks_error,
        "rank_history": rank_history,
        "target_tier": target_tier,
        "target_division": target_division,
    }), 200


@app.route('/api/players/<int:player_id>/target_rank', methods=['PUT'])
def handle_target_rank(player_id):
    data = request.get_json() or {}
    tier = data.get('tier')
    # MASTER以上はディビジョンが無いのでNULLで持つ
    division = None if tier in APEX_TIERS else data.get('division')

    if tier not in TIERS or (tier not in APEX_TIERS and division not in DIVISIONS):
        return jsonify({"message": "tier/divisionの値が不正です"}), 400

    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    cur.execute("""
        UPDATE players SET target_tier = %s, target_division = %s WHERE id = %s;
    """, (tier, division, player_id))
    updated = cur.rowcount
    conn.commit()
    cur.close()
    conn.close()

    if updated == 0:
        return jsonify({"message": "プレイヤーが見つかりません"}), 404
    return jsonify({"target_tier": tier, "target_division": division}), 200


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