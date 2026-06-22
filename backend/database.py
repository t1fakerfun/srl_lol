import psycopg2
import quantificate
from flask import Flask, request, jsonify
from flask_cors import CORS  # ★CORSを追加

app = Flask(__name__)
CORS(app)  # ★Flutter Webからのアクセスを許可

DB_CONFIG = {
    "host": "db",
    "database": "srl_database",
    "user": "srl_user",
    "password": "srl_password"
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
    conn.commit()
    cur.close()
    conn.close()

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

    srl_score = quantificate.ai_analysis(lesson)
    THRESHOLD = 3.0
    
    if srl_score >= THRESHOLD:
        conn = psycopg2.connect(**DB_CONFIG)
        cur = conn.cursor()
        # カラム名と変数を修正
        cur.execute("""
            INSERT INTO approved_reflections (target_type, routine_score, judgment_logic, lesson_learned, srl_score)
            VALUES (%s, %s, %s, %s, %s);
                    """, (target_type, routine_score, judgment_logic, lesson, srl_score))
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
    cur.execute("SELECT id, target_type, routine_score, judgment_logic, lesson_learned, srl_score, created_at FROM approved_reflections ORDER BY created_at DESC;")
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
            "date": row[6].isoformat()   # ref['date'] にマッピング
        }
        reflections.append(reflection)

    return jsonify(reflections), 200

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5001)