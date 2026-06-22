#定量化を行う
# マルチLLMでアンサンブルを行う
# 運、噛み合い　とかは低評価
# ミニオン、視界　とかは高評価

from collections import Counter
import collections
import os
from flask import Flask, request, jsonify
from dotenv import load_dotenv
from janome.tokenizer import Tokenizer
from google import genai
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


def ai_analysis(text):
    API_KEY = os.getenv("API_KEY")

    client = genai.Client(api_key=API_KEY)

    prompt = """
    # Identity
    あなたは優秀な分析官です。
    反省文の内容を分析し、以下の観点で評価してください。
    1. 運や噛み合いに関する記述の有無
    2. 具体的な対策の記述の有無

    # Constraints
    - 文章は日本語で書くこと

    # Task
    ユーザーが入力した反省文の内容を分析し、上記の観点で評価してください。
    text: {text}

    # Output Format
    -  分析結果の最後に必ず数値（0.0から5.0の範囲）のみを一行で出力してください。数値が高いほど、運や噛み合いに関する記述が少なく、具体的な対策が多いことを示します。
"""
    try:
        response = client.models.generate_content(
            model = "gemini-2.5-flash",
            contents = prompt
        )
        lines = response.text.strip().split('\n')
        score_text =  lines[-1].strip()  # 最後の行をスコアとする
        return float(score_text)
    except Exception as e:
        print(f"Error during AI analysis: {e}")
        return 0.0
    
    

