#!/bin/zsh
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
SHARED_FRONTEND="$PROJECT_ROOT/shared/frontend"

DEFAULT_PORT=8000
DEFAULT_BIND_HOST="127.0.0.1"
DEFAULT_PUBLIC_HOST="127.0.0.1"

BIND_HOST="${BIND_HOST:-$DEFAULT_BIND_HOST}"
PORT="${1:-${PORT:-$DEFAULT_PORT}}"
PUBLIC_HOST="${PUBLIC_HOST:-$DEFAULT_PUBLIC_HOST}"
PUBLIC_PORT="${PUBLIC_PORT:-$PORT}"
LISTEN_URL="http://${BIND_HOST}:${PORT}"
ACCESS_URL="http://${PUBLIC_HOST}:${PUBLIC_PORT}"
INDEX_URL="${ACCESS_URL}/index.html"
API_URL="${ACCESS_URL}/api?search_code=1000001"

SCRIPT_NAME="[server.php.sh]"
SERVER_PID=""

# Homebrew の PHP 8.4 を優先利用（必要ない場合は削除してください）
PATH="/opt/homebrew/opt/php@8.4/bin:$PATH"
PATH="/opt/homebrew/opt/php@8.4/sbin:$PATH"

print_start_message() {
  echo "${SCRIPT_NAME} Listening inside container on ${LISTEN_URL}"
  echo "${SCRIPT_NAME} Access from host via ${ACCESS_URL}/"
  echo "${SCRIPT_NAME} Quick check: ${API_URL}"
}

warn_missing_frontend() {
  if [[ ! -f "$SHARED_FRONTEND/index.html" ]]; then
    echo "${SCRIPT_NAME} Warning: $SHARED_FRONTEND/index.html が見つかりません。"
  fi
}

prepare_environment() {
  mkdir -p "$PROJECT_ROOT/shared/runtime"
}

start_server() {
  php -S "${BIND_HOST}:${PORT}" -t "$SCRIPT_DIR" "$SCRIPT_DIR/index.php" &
  SERVER_PID=$!
}

wait_for_server() {
  sleep 0.3
}

open_browser() {
  if command -v open >/dev/null 2>&1; then
    echo "${SCRIPT_NAME} Opening browser..."
    open "$INDEX_URL"
  else
    echo "${SCRIPT_NAME} Browser auto-open skipped (open command not found)"
  fi
}

cleanup() {
  printf "\n${SCRIPT_NAME} Stopping PHP server...\n"
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID"
    wait "$SERVER_PID" 2>/dev/null || true
    echo "${SCRIPT_NAME} Stopped. (pid=$SERVER_PID)"
  fi
}

trap cleanup EXIT INT TERM

print_start_message
warn_missing_frontend
prepare_environment
start_server
wait_for_server
open_browser

echo "${SCRIPT_NAME} PHP server is running (pid=$SERVER_PID). Press Ctrl+C to stop."

wait "$SERVER_PID"
