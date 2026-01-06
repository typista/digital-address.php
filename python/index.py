import json
import os
import re
import time
from pathlib import Path
from typing import Dict, Optional
from urllib.parse import unquote

import requests
from flask import Flask, Response, request, send_file

# =========================
#  python/index.py
# -------------------------
# - /api に来たリクエストを Japan Post Digital Address API へプロキシする
# - それ以外は shared/frontend/index.html を返す（画面表示）
#
# 必要なファイル／ディレクトリ：
# - shared/frontend/index.html
# - shared/config/credentials.json（ユーザーが配置）
# - shared/runtime/access_token.json（自動生成）
# =========================

ROOT_DIR = Path(__file__).resolve().parent.parent
SHARED_DIR = ROOT_DIR / "shared"
FRONTEND_DIR = SHARED_DIR / "frontend"
FRONTEND_HTML = FRONTEND_DIR / "index.html"
CONFIG_DIR = SHARED_DIR / "config"
RUNTIME_DIR = SHARED_DIR / "runtime"
TOKEN_FILE = RUNTIME_DIR / "access_token.json"
CREDENTIALS_FILE = CONFIG_DIR / "credentials.json"

BIND_HOST = os.environ.get("BIND_HOST", os.environ.get("HOST", "127.0.0.1"))
PUBLIC_HOST = os.environ.get("PUBLIC_HOST", "127.0.0.1")
PORT = int(os.environ.get("PORT", "8003"))
PUBLIC_PORT = int(os.environ.get("PUBLIC_PORT", PORT))

app = Flask(__name__)


# ========= ミドルウェア =========

@app.after_request
def addCorsHeaders(response: Response) -> Response:
    if request.path.startswith("/api"):
        response.headers["Access-Control-Allow-Origin"] = "*"
        response.headers["Access-Control-Allow-Methods"] = "*"
        response.headers["Access-Control-Allow-Headers"] = "*"
    return response


@app.before_request
def enforceGetForApi() -> Optional[Response]:
    if request.path.startswith("/api") and request.method != "GET":
        return Response(status=204)
    return None


# ========= ルーティング =========

@app.route("/api", defaults={"fallback": ""})
@app.route("/api/<path:fallback>")
def apiRoute(fallback: str) -> Response:
    return handleApiRequest(fallback)


@app.route("/", defaults={"path": ""})
@app.route("/<path:path>")
def indexRoute(path: str) -> Response:  # type: ignore[unused-argument]
    return serveIndexHtml()


# ========= ハンドラー =========

def serveIndexHtml() -> Response:
    if FRONTEND_HTML.exists():
        return send_file(FRONTEND_HTML)
    return Response(
        "shared/frontend/index.html not found",
        status=404,
        mimetype="text/plain",
    )


def handleApiRequest(fallback: str) -> Response:
    search_code = getSearchCode(fallback)

    token_result = getAccessTokenOrFetch()
    if not token_result["ok"]:
        return Response(
            token_result["body"],
            status=token_result["status"],
            mimetype="application/json",
        )

    return proxyJapanPostApi(token_result["token"], search_code)


def getSearchCode(fallback: str) -> str:
    if "search_code" in request.args:
        return str(request.args.get("search_code", ""))
    return unquote(fallback) if fallback else ""


def getAccessTokenOrFetch() -> Dict[str, object]:
    cached = loadCachedToken()
    if cached:
        return {"ok": True, "token": cached}

    fetched = fetchNewToken()
    if not fetched["ok"]:
        return fetched

    ensureRuntimeDir()
    TOKEN_FILE.write_text(fetched["body"], encoding="utf-8")

    try:
        data = json.loads(fetched["body"])
        token = data["token"]
        return {"ok": True, "token": token}
    except Exception as exc:  # noqa: BLE001
        return {
            "ok": False,
            "status": 500,
            "body": json.dumps(
                {"error": "invalid_token_response", "message": str(exc)},
                ensure_ascii=False,
            ),
        }


def loadCachedToken() -> Optional[str]:
    if not TOKEN_FILE.exists():
        return None

    try:
        data = json.loads(TOKEN_FILE.read_text(encoding="utf-8"))
        expires_in = int(data["expires_in"])
        token = str(data["token"])

        expires_at = int(TOKEN_FILE.stat().st_mtime) + expires_in
        if int(time.time()) < expires_at:
            return token
    except Exception:  # noqa: BLE001
        return None

    return None


def fetchNewToken() -> Dict[str, object]:
    if not CREDENTIALS_FILE.exists():
        return {
            "ok": False,
            "status": 500,
            "body": json.dumps({"error": "credentials.json not found"}),
        }

    credentials = CREDENTIALS_FILE.read_text(encoding="utf-8")

    response = requests.post(
        "https://api.da.pf.japanpost.jp/api/v1/j/token",
        headers={
            "Content-Type": "application/json",
            "x-forwarded-for": "127.0.0.1",
        },
        data=credentials,
        timeout=30,
    )

    return {
        "ok": response.status_code == 200,
        "status": response.status_code,
        "body": response.text or "",
    }


def proxyJapanPostApi(token: str, search_code: str) -> Response:
    if isZipOrCode(search_code):
        response = requests.get(
            f"https://api.da.pf.japanpost.jp/api/v1/searchcode/{requests.utils.quote(search_code)}",
            headers={"Authorization": f"Bearer {token}"},
            timeout=30,
        )
    else:
        response = requests.post(
            "https://api.da.pf.japanpost.jp/api/v1/addresszip",
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            json={"freeword": search_code},
            timeout=30,
        )

    return Response(
        response.text,
        status=response.status_code,
        mimetype="application/json",
    )


def isZipOrCode(value: str) -> bool:
    return bool(re.match(r"^\d{3,7}$", value) or re.match(r"^\w{7}$", value))


def ensureRuntimeDir() -> None:
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)


if __name__ == "__main__":
    app.run(host=HOST, port=PORT, debug=False)
