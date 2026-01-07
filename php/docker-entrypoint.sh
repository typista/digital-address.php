#!/bin/sh
set -eu

# バインド先とホスト側アクセス用URL
BIND_HOST="${BIND_HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
PUBLIC_HOST="${PUBLIC_HOST:-127.0.0.1}"
PUBLIC_PORT="${PUBLIC_PORT:-$PORT}"

LISTEN_URL="http://${BIND_HOST}:${PORT}"
ACCESS_URL="http://${PUBLIC_HOST}:${PUBLIC_PORT}"

echo "[php-proxy] Listening inside container on ${LISTEN_URL}"
echo "[php-proxy] Access from host via ${ACCESS_URL}/"
echo "[php-proxy] Quick check: ${ACCESS_URL}/api?search_code=1000001"

exec php -S "${BIND_HOST}:${PORT}" -t /app/php /app/php/index.php
