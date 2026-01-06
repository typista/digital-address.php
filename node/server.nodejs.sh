#!/bin/zsh
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
SHARED_FRONTEND="$PROJECT_ROOT/shared/frontend"

DEFAULT_PORT=8000
HOST="${HOST:-127.0.0.1}"
PORT="${1:-${PORT:-$DEFAULT_PORT}}"
BASE_URL="http://${HOST}:${PORT}"
INDEX_URL="${BASE_URL}/index.html"
API_URL="${BASE_URL}/api?search_code=1000001"

SCRIPT_NAME="[server.nodejs.sh]"
SERVER_PID=""

print_start_message() {
  echo "${SCRIPT_NAME} Starting Node proxy on ${BASE_URL}"
  echo "${SCRIPT_NAME} Quick check: ${API_URL}"
}

warn_missing_frontend() {
  if [[ ! -f "$SHARED_FRONTEND/index.html" ]]; then
    echo "${SCRIPT_NAME} Warning: $SHARED_FRONTEND/index.html が見つかりません。"
  fi
}

prepare_environment() {
  mkdir -p "$PROJECT_ROOT/shared/runtime"

  if [[ ! -d "$SCRIPT_DIR/node_modules" ]]; then
    echo "${SCRIPT_NAME} Installing dependencies..."
    (cd "$SCRIPT_DIR" && npm install)
  fi
}

start_server() {
  local previous_dir
  previous_dir=$(pwd)
  cd "$SCRIPT_DIR"
  HOST="$HOST" PORT="$PORT" npm start &
  SERVER_PID=$!
  cd "$previous_dir"
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
  printf "\n${SCRIPT_NAME} Stopping Node server...\n"
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

echo "${SCRIPT_NAME} Node server is running (pid=$SERVER_PID). Press Ctrl+C to stop."

wait "$SERVER_PID"

