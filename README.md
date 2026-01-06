# 郵便番号・デジタルアドレス API プロキシ

Japan Post Digital Address API に対する簡易プロキシサーバーです。  
PHP と Node.js の 2 つの実装を同梱し、どちらも次のような役割を担います。

- `/api` への GET リクエストを受け取り、アクセストークンをキャッシュしながら Japan Post API に代理アクセスする
- それ以外のパスにはフロントエンドの `index.html` を返却する
- 住所検索フォームからのリクエストを扱いやすくするため、CORS ヘッダーや簡易ルーティングを提供する

## 主なファイル

- `index.html` – 郵便番号から住所を取得するフォーム。`/api?search_code=XXXXXXX` に fetch し、取得結果をフォームに反映する。
- `index.php` – PHP 版のプロキシ。cURL でトークン取得 (`/api/v1/j/token`) と住所検索 (`/api/v1/searchcode` or `/api/v1/addresszip`) を呼び出す。
- `index.js` – Node.js 版のプロキシ。Express と `node-fetch` を使用して PHP 版と同等の挙動を提供する。
- `credentials.json` – API クライアント資格情報（リポジトリには含まれていないため、利用者が用意する）。
- `access_token.json` – 取得したアクセストークンをキャッシュするためのファイル。初回リクエスト時や期限切れ時に自動で更新される。
- `server.php.sh` / `server.nodejs.sh` – ローカル開発用の起動スクリプト。

## 必要要件

- PHP 8.1 以降 (PHP 版を使用する場合)
- Node.js 18 以降 (Node.js 版を使用する場合)
- Japan Post Digital Address API のクライアント資格情報

## セットアップ

### 1. 資格情報ファイルの準備

`credentials.json` をプロジェクト直下、または任意の安全な場所に作成します。公開ディレクトリに配置しないことを推奨します。  
ローカル以外のパスに置く場合は、PHP/Node.js それぞれのソースで参照先を変更してください。

```json
{
  "grant_type": "client_credentials",
  "client_id": "your-client_id",
  "secret_key": "your-secret_key"
}
```

### 2. IP アドレス登録

Japan Post 側で 127.0.0.1 を許可 IP として登録しておくとローカル開発が容易です。

### 3. ローカル実行 (PHP 版)

```bash
# 必要に応じて PHP の PATH を調整してください
./server.php.sh           # ブラウザが自動で起動します

# 手動で起動する場合
php -S 127.0.0.1:8000

# 動作確認例
curl "http://127.0.0.1:8000/api?search_code=1000001"
```

- PHP 組み込みサーバーが `/api` 以外のパスを `index.html` にフォールバックします。
- `/api` では GET 以外のメソッドを 204 で返却し、CORS ヘッダーを許可しています。

### 4. ローカル実行 (Node.js 版)

```bash
npm install
./server.nodejs.sh        # npm start をラップしています

# 直接起動
npm start

# 動作確認例
curl "http://127.0.0.1:8000/api?search_code=1000001"
```

- `index.js` の `PORT` は既定で 8000、`express.static` で同階層の静的ファイルを配信します。
- トークンキャッシュは PHP 版と同じファイル (`access_token.json`) を利用します。

## API 挙動

1. `/api` に `search_code` をクエリで指定して GET を送信します。
2. サーバーは `access_token.json` を参照し、有効期限内のトークンがあれば再利用します。無い場合は `credentials.json` を使って `POST /api/v1/j/token` を呼び出し、新しいトークンを保存します。
3. `search_code` が数字 3〜7 桁または英数字 7 文字の場合は `GET /api/v1/searchcode/{code}` に転送します。それ以外は `POST /api/v1/addresszip` に `{"freeword": search_code}` を送ります。
4. Japan Post API から返った JSON をそのままレスポンスとして返却します。

## フロントエンド (`index.html`)

- シンプルなフォームで郵便番号を入力し、`fetch` で `/api?search_code=...` を呼び出します。
- レスポンス内の住所データをフォームの都道府県・市区町村・町名欄に反映します。
- ブラウザのオートコンプリートを抑制するため、`autocomplete="off"` などの属性を設定しています。

## 運用上の注意

- `credentials.json` と `access_token.json` は機微情報を含むため、公開ディレクトリの外に置くか、アクセス制御を施してください。
- 認証情報や IP 制限の設定は本番環境に合わせて調整する必要があります。
- プロキシ先 API のステータスコードとレスポンスボディはそのままクライアントへ返されます。必要に応じてエラーハンドリングを追加してください。

## ライセンス

MIT License
