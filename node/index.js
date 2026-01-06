const express = require("express");
const fs = require("fs");
const path = require("path");

const ROOT_DIR = path.join(__dirname, "..");
const SHARED_DIR = path.join(ROOT_DIR, "shared");
const FRONTEND_DIR = path.join(SHARED_DIR, "frontend");
const FRONTEND_HTML = path.join(FRONTEND_DIR, "index.html");
const RUNTIME_DIR = path.join(SHARED_DIR, "runtime");
const CONFIG_DIR = path.join(SHARED_DIR, "config");

const TOKEN_FILE = path.join(RUNTIME_DIR, "access_token.json");
const CREDENTIALS_FILE = path.join(CONFIG_DIR, "credentials.json");

const app = express();
const HOST = process.env.HOST ?? "0.0.0.0";
const PORT = Number(process.env.PORT ?? 8000);

// 静的ファイル（shared/frontend）を配信
app.use(express.static(FRONTEND_DIR));

// CORS（必要なら。index.htmlと同一オリジンなら本来不要ですが、残してもOK）
app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "*");
  res.setHeader("Access-Control-Allow-Headers", "*");
  next();
});

// GET以外は204（PHP互換）
app.use((req, res, next) => {
  if (req.method !== "GET") return res.status(204).end();
  next();
});

// /api をAPIとして扱う
app.get("/api", async (req, res) => {
  const searchCode = req.query.search_code ?? "";

  // token読み込み
  let token = null;
  if (fs.existsSync(TOKEN_FILE)) {
    try {
      const obj = JSON.parse(fs.readFileSync(TOKEN_FILE, "utf8"));
      const mtimeSec = Math.floor(fs.statSync(TOKEN_FILE).mtimeMs / 1000);
      if (Math.floor(Date.now() / 1000) < mtimeSec + obj.expires_in) {
        token = obj.token;
      }
    } catch {}
  }

  // tokenなければ取得
  if (!token) {
    if (!fs.existsSync(CREDENTIALS_FILE)) {
      res.status(500).json({ error: "credentials.json not found" });
      return;
    }

    const credentials = fs.readFileSync(CREDENTIALS_FILE, "utf8");
    const tResp = await fetch("https://api.da.pf.japanpost.jp/api/v1/j/token", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-forwarded-for": "127.0.0.1"
      },
      body: credentials
    });

    const tText = await tResp.text();
    if (tResp.status !== 200) {
      res.status(tResp.status).type("application/json").send(tText);
      return;
    }

    fs.mkdirSync(RUNTIME_DIR, { recursive: true });
    fs.writeFileSync(TOKEN_FILE, tText, "utf8");
    token = JSON.parse(tText).token;
  }

  res.type("application/json");

  // PHPの正規表現意図（安全に）：数字(3〜7桁) or 英数字7文字
  const isZipOrCode = /^(\d{3,7})$/.test(searchCode) || /^(\w{7})$/.test(searchCode);

  try {
    if (isZipOrCode) {
      const apiResp = await fetch(
        `https://api.da.pf.japanpost.jp/api/v1/searchcode/${encodeURIComponent(searchCode)}`,
        { headers: { Authorization: `Bearer ${token}` } }
      );
      const body = await apiResp.text();
      res.status(apiResp.status).send(body);
    } else {
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
    }
  } catch (e) {
    res.status(500).json({ error: "internal_error", message: String(e) });
  }
});

// ルートに来たら index.html を返す
app.get("/", (req, res) => {
  res.sendFile(FRONTEND_HTML);
});

app.listen(PORT, HOST, () => {
  const displayHost = HOST === "0.0.0.0" ? "127.0.0.1" : HOST;
  console.log(`HTML: http://${displayHost}:${PORT}/index.html`);
  console.log(`API : http://${displayHost}:${PORT}/api?search_code=1020082`);
});

