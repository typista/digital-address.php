#!/bin/zsh
set -e

PORT=${1:-8000}
HOST=127.0.0.1
URL="http://$HOST:$PORT/?search_code=1000001"
INDEX="http://$HOST:$PORT/index.html"

PATH="/opt/homebrew/opt/php@8.4/bin:$PATH"
PATH="/opt/homebrew/opt/php@8.4/sbin:$PATH"

servephp() {
  local port=${1:-8000}
  php -S 127.0.0.1:$port
}

# サーバ停止処理（Ctrl+C / kill / 終了時に必ず呼ばれる）
cleanup() {
  echo "\n[server.sh] Stopping PHP server..."
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID"
    wait "$SERVER_PID" 2>/dev/null || true
    echo "[server.sh] Stopped. (pid=$SERVER_PID)"
  fi
}

# EXIT / INT(Ctrl+C) / TERM を捕捉して cleanup を実行
trap cleanup EXIT INT TERM

echo "[server.sh] Starting PHP server on $URL ..."

# servephp はフォアグラウンドで動くので、バックグラウンドで起動
servephp "$PORT" >/dev/null 2>&1 &
SERVER_PID=$!

# サーバが立ち上がるのを軽く待つ（早すぎるopen対策）
sleep 0.3

echo "[server.sh] Opening browser..."
open "$INDEX"

echo "[server.sh] PHP server is running (pid=$SERVER_PID)."
echo "[server.sh] Press Ctrl+C to stop."

# サーバが終わるまで待つ（これがあるのでスクリプトが即終了しない）
wait "$SERVER_PID"

