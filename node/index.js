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

const app = express();
const HOST = process.env.HOST ?? "0.0.0.0";
const PORT = Number(process.env.PORT ?? 8000);

/* ========= ミドルウェア ========= */

// 静的ファイル（shared/frontend）を配信
app.use(express.static(FRONTEND_DIR));

// CORS（API用）
app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "*");
  res.setHeader("Access-Control-Allow-Headers", "*");
  next();
});

// GET以外は 204（元処理と同等）
app.use((req, res, next) => {
  if (req.method !== "GET") {
    res.status(204).end();
    return;
  }
  next();
});

/* ========= API処理 ========= */

app.get("/api", async (req, res) => {
  const searchCode = req.query.search_code ?? "";

  // Token確保（キャッシュ→なければ取得）
  let token = null;
  if (fs.existsSync(TOKEN_FILE)) {
    // キャッシュがあれば利用
    try {
      const obj = JSON.parse(fs.readFileSync(TOKEN_FILE, "utf8"));
      const mtimeSec = Math.floor(fs.statSync(TOKEN_FILE).mtimeMs / 1000);
      if (Math.floor(Date.now() / 1000) < mtimeSec + obj.expires_in) {
        token = obj.token;
      }
    } catch {
      token = null;
    }
  }

  if (!token) {
    if (!fs.existsSync(CREDENTIALS_FILE)) {
      res.status(500).json({ error: "credentials.json not found" });
      return;
    }

    const credentials = fs.readFileSync(CREDENTIALS_FILE, "utf8");
    const tokenResp = await fetch("https://api.da.pf.japanpost.jp/api/v1/j/token", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-forwarded-for": "127.0.0.1"
      },
      body: credentials
    });

    const bodyText = await tokenResp.text();
    if (tokenResp.status !== 200) {
      res.status(tokenResp.status).type("application/json").send(bodyText);
      return;
    }

    fs.mkdirSync(RUNTIME_DIR, { recursive: true });
    fs.writeFileSync(TOKEN_FILE, bodyText, "utf8");
    token = JSON.parse(bodyText).token;
  }

  res.type("application/json");

  // 元コードの正規表現を関数化して判定
  const isZipOrCode = /^(\d{3,7})$/.test(searchCode) || /^(\w{7})$/.test(searchCode);

  try {
    if (isZipOrCode) {
      // GET /searchcode/{search_code}
      const apiResp = await fetch(
        `https://api.da.pf.japanpost.jp/api/v1/searchcode/${encodeURIComponent(searchCode)}`,
        { headers: { Authorization: `Bearer ${token}` } }
      );
      const body = await apiResp.text();
      res.status(apiResp.status).send(body);
      return;
    }

    // POST /addresszip
    const apiResp = await fetch("https://api.da.pf.japanpost.jp/api/v1/addresszip", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ freeword: searchCode })
    });
    const body = await apiResp.text();
    res.status(apiResp.status).send(body);
  } catch (error) {
    res.status(500).json({ error: "internal_error", message: String(error) });
  }
});

/* ========= 画面返却 ========= */

// /api 以外は index.html を返す
app.get("*", (req, res) => {
  res.sendFile(FRONTEND_HTML);
});

app.listen(PORT, HOST, () => {
  const displayHost = HOST === "0.0.0.0" ? "127.0.0.1" : HOST;
  console.log(`HTML: http://${displayHost}:${PORT}/index.html`);
  console.log(`API : http://${displayHost}:${PORT}/api?search_code=1020082`);
});

