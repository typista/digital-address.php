#!/bin/sh
set -eu

# バインド先とホスト側アクセス用URL
BIND_HOST="${BIND_HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
PUBLIC_HOST="${PUBLIC_HOST:-127.0.0.1}"
PUBLIC_PORT="${PUBLIC_PORT:-$PORT}"

export BIND_HOST
export PORT
export PUBLIC_HOST
export PUBLIC_PORT

LISTEN_URL="http://${BIND_HOST}:${PORT}"
ACCESS_URL="http://${PUBLIC_HOST}:${PUBLIC_PORT}"

echo "[php-proxy] Listening inside container on ${LISTEN_URL}"
echo "[php-proxy] Access from host via ${ACCESS_URL}/"
echo "[php-proxy] Quick check: ${ACCESS_URL}/api?search_code=1000001"

LOG_PIPE=$(mktemp -u "/tmp/php-server-log.XXXXXX")
mkfifo "$LOG_PIPE"

cleanup_pipe() {
    rm -f "$LOG_PIPE"
}
trap cleanup_pipe EXIT

php -S "${BIND_HOST}:${PORT}" -t /app/php /app/php/index.php >"$LOG_PIPE" 2>&1 &
PHP_PID=$!

sed -u '/ Accepted$/d; / Closing$/d' <"$LOG_PIPE" &
FILTER_PID=$!

terminate_children() {
    kill "$PHP_PID" "$FILTER_PID" 2>/dev/null || true
}
trap terminate_children INT TERM

wait "$PHP_PID"
PHP_STATUS=$?
wait "$FILTER_PID" 2>/dev/null || true
exit "$PHP_STATUS"
