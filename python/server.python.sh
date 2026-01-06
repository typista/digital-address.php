#!/bin/zsh
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
SHARED_FRONTEND="$PROJECT_ROOT/shared/frontend"
VENV_DIR="$SCRIPT_DIR/.venv"

DEFAULT_PORT=8003
DEFAULT_BIND_HOST="127.0.0.1"
DEFAULT_PUBLIC_HOST="127.0.0.1"
BIND_HOST="${BIND_HOST:-$DEFAULT_BIND_HOST}"
PORT="${1:-${PORT:-$DEFAULT_PORT}}"
PUBLIC_HOST="${PUBLIC_HOST:-$DEFAULT_PUBLIC_HOST}"
PUBLIC_PORT="${PUBLIC_PORT:-$PORT}"
BASE_URL="http://${PUBLIC_HOST}:${PUBLIC_PORT}"
INDEX_URL="${BASE_URL}/index.html"
API_URL="${BASE_URL}/api?search_code=1000001"

SCRIPT_NAME="[server.python.sh]"
SERVER_PID=""

print_start_message() {
  echo "${SCRIPT_NAME} Starting Python proxy on ${BASE_URL}"
  echo "${SCRIPT_NAME} Quick check: ${API_URL}"
}

warn_missing_frontend() {
  if [[ ! -f "$SHARED_FRONTEND/index.html" ]]; then
    echo "${SCRIPT_NAME} Warning: $SHARED_FRONTEND/index.html が見つかりません。"
  fi
}

prepare_environment() {
  mkdir -p "$PROJECT_ROOT/shared/runtime"

  if [[ ! -d "$VENV_DIR" ]]; then
    echo "${SCRIPT_NAME} Creating virtualenv..."
    python3 -m venv "$VENV_DIR"
  fi

  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip >/dev/null
  pip install -r "$SCRIPT_DIR/requirements.txt" >/dev/null
  deactivate
}

start_server() {
  source "$VENV_DIR/bin/activate"
  HOST="$BIND_HOST" PORT="$PORT" python "$SCRIPT_DIR/index.py" &
  SERVER_PID=$!
  deactivate
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
  printf "\n${SCRIPT_NAME} Stopping Python server...\n"
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

echo "${SCRIPT_NAME} Python server is running (pid=$SERVER_PID). Press Ctrl+C to stop."

wait "$SERVER_PID"
