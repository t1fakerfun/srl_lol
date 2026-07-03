FROM python:3.11-slim

WORKDIR /app

# システム依存ライブラリのインストール
# FFmpeg: 動画処理に必要
# libglib2.0-0, libsm6, libxext6: OpenCVのGUI機能（表示用）に必要
# libxrender-dev: 高速な描画に必要
RUN apt-get update && apt-get install -y \
    ffmpeg \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 5. アプリケーションのコードをコンテナ内にコピー
# （docker-compose.yml側で .:/app をバインドマウントするため開発時はこちらは上書きされるが、
# 　イメージ単体でも動くように揃えておく）
COPY . .

# 6. アップロード動画とハイライト出力を置くためのフォルダを作成
RUN mkdir -p /app/uploads /app/highlights

# 7. コンテナ起動時に実行されるコマンド
# 動画解析はAPI経由でアップロードの都度動的に起動されるため、常駐するのはFlaskアプリ本体
CMD ["python", "database.py"]