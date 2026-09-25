#定量化を行う
# マルチLLMでアンサンブルを行う
# 運、噛み合い　とかは低評価
# ミニオン、視界　とかは高評価

from collections import Counter
import collections
import os
import re
from flask import Flask, request, jsonify
from dotenv import load_dotenv
from janome.tokenizer import Tokenizer
from google import genai
from google.genai import errors as genai_errors
from flask_cors import CORS


load_dotenv()


def keyword_analysis():
    # 1. テキストファイルの読み込み
    with open('data/beginner.txt', 'r', encoding='utf-8') as f:
        text = f.read()

    # 2. 形態素解析の実行
    t = Tokenizer()
    words = []
    for token in t.tokenize(text):
        # 名詞、動詞、形容詞を抽出（単なる助詞などは除外）
        part_of_speech = token.part_of_speech.split(',')[0]
        if part_of_speech in ['名詞', '動詞', '形容詞']:
            words.append(token.base_form) # 単語の基本形を保存

    # 3. 頻出単語のカウント
    counter = Counter(words)
    print("■ 初心者反省文の頻出単語トップ20")
    for word, count in counter.most_common(20):
        print(f"{word}: {count}回")


class AnalysisError(Exception):
    """AI採点の失敗。kindで「どこで失敗したか」を区別する。

    - EMPTY_INPUT:  採点対象の文章が空（リクエストのキー名ずれ等、呼び出し側のバグを疑う）
    - RATE_LIMITED: Gemini APIの429（レート制限・無料枠の上限）
    - AI_ERROR:     Gemini API側のその他のエラー、または応答が空だった
    - PARSE_ERROR:  Geminiは応答したが、出力フォーマットからSCOREを切り出せなかった
    """

    def __init__(self, kind, message, status_code):
        super().__init__(message)
        self.kind = kind
        self.message = message
        self.status_code = status_code


def _log(message):
    # gunicorn配下ではstdoutがバッファされてログに出ないことがあるため、毎回flushする
    print(f"[ai_analysis] {message}", flush=True)


# 箇条書きの記号ゆれ（"-", "*", "・", "1." 等）を吸収する
_BULLET_RE = re.compile(r'^(?:[-*・•]|\d+[.)])\s*')
_NUMBER_RE = re.compile(r'-?\d+(?:\.\d+)?')


def parse_analysis(raw_text):
    """Geminiの出力からGOOD/QUESTIONS/SCOREを切り出す。SCOREが取れなければPARSE_ERROR。"""
    good = ""
    questions = []
    score = None
    in_questions = False
    for raw_line in raw_text.strip().split('\n'):
        # "**GOOD:**" のようなMarkdown強調や見出し記号が付いても拾えるようにする
        line = raw_line.replace('**', '').strip().lstrip('#').strip()
        if line.startswith('GOOD:'):
            in_questions = False
            good = line[len('GOOD:'):].strip()
        elif line.startswith('QUESTIONS:'):
            in_questions = True
            rest = _BULLET_RE.sub('', line[len('QUESTIONS:'):].strip())
            if rest:
                questions.append(rest)
        elif line.startswith('SCORE:'):
            in_questions = False
            # "3.5/5.0" や "3.5点" のような余計な表記が付いても最初の数値を採用する
            match = _NUMBER_RE.search(line[len('SCORE:'):])
            if match:
                score = min(max(float(match.group()), 0.0), 5.0)
        elif in_questions and _BULLET_RE.match(line):
            q = _BULLET_RE.sub('', line)
            if q:
                questions.append(q)

    if score is None:
        raise AnalysisError(
            "PARSE_ERROR",
            "AIの応答からスコアを読み取れませんでした。もう一度送信してください。",
            502,
        )
    return {"score": score, "good": good, "questions": questions}


def ai_analysis(text):
    if not text or not text.strip():
        raise AnalysisError(
            "EMPTY_INPUT",
            "採点する教訓の文章が空です。「獲得した教訓」を入力してください。",
            400,
        )

    API_KEY = os.getenv("API_KEY")

    client = genai.Client(api_key=API_KEY)

    prompt = f"""
    # Identity
    あなたはリーグ・オブ・レジェンドのプレイヤーの振り返り(反省文)を評価する優秀なコーチです。
    ただし正解を教えるコーチではなく、本人が書いた文章の曖昧な部分に的確な問いを重ねることで、
    本人自身に「なぜそうなったのか」「その時何を考えていたのか」「次はどう判断するか」を
    言語化させるソクラテス式のコーチです。

    # Task
    プレイヤーが入力した振り返りの内容を、以下の観点で評価してください。
    1. 運や噛み合い、チームメイトのせいにする記述に偏っていないか
    2. 「次にどうするか」について、具体的で実行可能な対策や判断基準の見直しが書かれているか
    3. 曖昧な表現が多く、具体的な行動や思考が言語化されていない箇所がないか

    text: {text}

    # Constraints
    - 出力はすべて日本語で書くこと
    - QUESTIONSは一般論のアドバイスではなく、振り返り文中の具体的な一節を引用または
      言い換えたうえで、そこに対して「なぜ」「具体的に何を」「その時何を考えていたか」を
      問うツッコミにすること（例:「"警戒が足りなかった"とあるが、具体的に何を見ていれば
      気づけた？」）
    - QUESTIONSは曖昧・抽象的な記述1箇所につき1個、最大3個まで。書くことが本当になければ
      QUESTIONSの行自体を出力しなくてよい
    - GOODは1〜2文に収め、減点の指摘だけでなく良い点があれば必ず拾うこと

    # Output Format
    必ず以下のフォーマットのみで出力してください。他の文章・空行は含めないこと。
    GOOD: (この振り返りの中で評価できる点。特になければ「特になし」と書く)
    QUESTIONS:
    - (曖昧な一節へのツッコミ質問。1個目)
    - (同上。2個目、なければ省略)
    - (同上。3個目、なければ省略)
    SCORE: (0.0から5.0の範囲の数値のみ。運や噛み合いへの言及が多く具体的な対策がないほど低く、判断基準の見直しなど具体的な対策が書かれているほど高くする)
"""
    try:
        response = client.models.generate_content(
            model = "gemini-2.5-flash",
            contents = prompt
        )
    except genai_errors.APIError as e:
        _log(f"Gemini APIエラー: code={e.code} status={e.status} message={e.message}")
        if e.code == 429:
            raise AnalysisError(
                "RATE_LIMITED",
                "AIの利用回数の上限に達しました。1分ほど待ってから再度送信してください。",
                429,
            )
        raise AnalysisError("AI_ERROR", f"AIの呼び出しに失敗しました（{e.code}）。", 502)
    except Exception as e:
        # 通信断・タイムアウト等、APIErrorにならない失敗
        _log(f"Gemini呼び出し中の予期しないエラー: {e!r}")
        raise AnalysisError("AI_ERROR", "AIの呼び出しに失敗しました。", 502)

    raw_text = response.text
    if not raw_text:
        # セーフティフィルタ等でテキストが返らなかったケース
        finish_reason = response.candidates[0].finish_reason if response.candidates else None
        _log(f"Geminiの応答が空でした: finish_reason={finish_reason}")
        raise AnalysisError("AI_ERROR", "AIから応答が返りませんでした。もう一度送信してください。", 502)

    try:
        result = parse_analysis(raw_text)
    except AnalysisError:
        _log(f"出力フォーマットの切り出しに失敗。生の応答:\n{raw_text}")
        raise

    if not result["questions"]:
        # プロンプト上「書くことがなければQUESTIONSを省略可」なので正常系の可能性もある。
        # 切り出しミスかどうかを見分けられるよう、生の応答を残しておく。
        _log(f"QUESTIONSが0件でした（Geminiが省略したのか切り出しミスかは以下で確認）:\n{raw_text}")
    return result
