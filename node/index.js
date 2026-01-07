/**
 * node/index.js
 *
 * - /api に来たリクエストを Japan Post Digital Address API へプロキシする
 * - それ以外は shared/frontend/index.html を返す（画面表示）
 *
 * 前提となるファイル／ディレクトリ：
 * - shared/frontend/index.html
 * - shared/config/credentials.json（ユーザーが配置）
 * - shared/runtime/access_token.json（自動生成）
 */

const express = require("express");
const fs = require("fs");
const path = require("path");

const ROOT_DIR = path.join(__dirname, "..");
const SHARED_DIR = path.join(ROOT_DIR, "shared");
const FRONTEND_DIR = path.join(SHARED_DIR, "frontend");
const FRONTEND_HTML = path.join(FRONTEND_DIR, "index.html");
const CONFIG_DIR = path.join(SHARED_DIR, "config");
const RUNTIME_DIR = path.join(SHARED_DIR, "runtime");
const CREDENTIALS_FILE = path.join(CONFIG_DIR, "credentials.json");
const TOKEN_FILE = path.join(RUNTIME_DIR, "access_token.json");

const BIND_HOST = process.env.BIND_HOST ?? process.env.HOST ?? "127.0.0.1";
const PORT = Number(process.env.PORT ?? 8000);
const PUBLIC_HOST =
  process.env.PUBLIC_HOST ?? (BIND_HOST === "0.0.0.0" ? "127.0.0.1" : BIND_HOST);
const PUBLIC_PORT = Number(process.env.PUBLIC_PORT ?? PORT);
const LISTEN_URL = `http://${BIND_HOST}:${PORT}`;
const ACCESS_URL = `http://${PUBLIC_HOST}:${PUBLIC_PORT}`;

const app = express();

/* ========= ミドルウェア ========= */

app.use(express.static(FRONTEND_DIR));

app.use((req, res, next) => {
    const path = req.originalUrl || req.url || "/";
    res.on("finish", () => {
        console.log(`[node-proxy] ${req.method} ${path} -> ${res.statusCode}`);
    });
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "*");
    res.setHeader("Access-Control-Allow-Headers", "*");
    if (req.method !== "GET") {
        res.status(204).end();
        return;
    }
    next();
});

/* ========= ルーティング ========= */

app.get("/api", handleApiRequest);
app.get("/api/*", handleApiRequest);
app.get("*", serveIndexHtml);

app.listen(PORT, BIND_HOST, () => {
  console.log(`[node-proxy] Listening inside container on ${LISTEN_URL}`);
  console.log(`[node-proxy] Access from host via ${ACCESS_URL}/`);
  console.log(
    `[node-proxy] Quick check: ${ACCESS_URL}/api?search_code=1020082`,
  );
});

/* ========= 画面返却 ========= */

function serveIndexHtml(_req, res) {
  res.sendFile(FRONTEND_HTML);
}

/* ========= API処理 ========= */

async function handleApiRequest(req, res) {
  res.type("application/json");

  const searchCode = getSearchCode(req);

  try {
    const tokenResult = await getAccessTokenOrFetch();
    if (!tokenResult.ok) {
      res
        .status(tokenResult.status)
        .type("application/json")
        .send(tokenResult.body);
      return;
    }

    await proxyJapanPostApi(res, tokenResult.token, searchCode);
  } catch (error) {
    res.status(500).json({ error: "internal_error", message: String(error) });
  }
}

function getSearchCode(req) {
  if (typeof req.query.search_code === "string") {
    return req.query.search_code;
  }

  const remainder = typeof req.params?.[0] === "string" ? req.params[0] : "";
  return remainder.length > 0 ? decodeURIComponent(remainder.replace(/^\/?/, "")) : "";
}

async function getAccessTokenOrFetch() {
  const cached = loadCachedToken();
  if (cached !== null) {
    return { ok: true, token: cached };
  }

  const fetched = await fetchNewToken();
  if (!fetched.ok) {
    return fetched;
  }

  ensureRuntimeDir();
  fs.writeFileSync(TOKEN_FILE, fetched.body, "utf8");

  try {
    const token = JSON.parse(fetched.body).token;
    return { ok: true, token };
  } catch (error) {
    return {
      ok: false,
      status: 500,
      body: JSON.stringify({ error: "invalid_token_response", message: String(error) })
    };
  }
}

function loadCachedToken() {
  if (!fs.existsSync(TOKEN_FILE)) {
    return null;
  }

  try {
    const data = JSON.parse(fs.readFileSync(TOKEN_FILE, "utf8"));
    if (
      typeof data.token !== "string" ||
      typeof data.expires_in !== "number" ||
      !Number.isFinite(data.expires_in)
    ) {
      return null;
    }

    const expiresAt =
      Math.floor(fs.statSync(TOKEN_FILE).mtimeMs / 1000) + data.expires_in;
    if (Math.floor(Date.now() / 1000) < expiresAt) {
      return data.token;
    }
  } catch {
    return null;
  }

  return null;
}

async function fetchNewToken() {
  if (!fs.existsSync(CREDENTIALS_FILE)) {
    return {
      ok: false,
      status: 500,
      body: JSON.stringify({ error: "credentials.json not found" })
    };
  }

  const credentials = fs.readFileSync(CREDENTIALS_FILE, "utf8");
  const response = await fetch("https://api.da.pf.japanpost.jp/api/v1/j/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-forwarded-for": "127.0.0.1"
    },
    body: credentials
  });

  const body = await response.text();
  if (!response.ok) {
    return { ok: false, status: response.status, body };
  }

  return { ok: true, status: response.status, body };
}

async function proxyJapanPostApi(res, token, searchCode) {
  if (isZipOrCode(searchCode)) {
    const apiResp = await fetch(
      `https://api.da.pf.japanpost.jp/api/v1/searchcode/${encodeURIComponent(searchCode)}`,
      { headers: { Authorization: `Bearer ${token}` } }
    );
    const body = await apiResp.text();
    res.status(apiResp.status).type("application/json").send(body);
    return;
  }

  const apiResp = await fetch("https://api.da.pf.japanpost.jp/api/v1/addresszip", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ freeword: searchCode })
  });
  const body = await apiResp.text();
  res.status(apiResp.status).type("application/json").send(body);
}

function isZipOrCode(value) {
  return /^\d{3,7}$/.test(value) || /^\w{7}$/.test(value);
}

function ensureRuntimeDir() {
  fs.mkdirSync(RUNTIME_DIR, { recursive: true });
}

