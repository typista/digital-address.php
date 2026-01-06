# 郵便番号・デジタルアドレス API プロキシ

Japan Post Digital Address API（郵便番号・デジタルアドレス for Biz）に対する簡易プロキシサーバーです。  
利用には日本郵便が提供するビジネス向けポータルへの登録が必要で、次の準備を済ませてから本プロキシを動かしてください [^jp-api].

1. ゆうIDを取得し、郵便番号・デジタルアドレス for Biz にログインする。
2. 開発したいシステムをダッシュボードの「システムリスト」に登録する。このリポジトリをローカルで動かす場合は `127.0.0.1` を接続元 IP として登録しておく。
3. API用のクライアント資格情報（`client_id` と `secret_key`）を取得する。

PHP / Node.js / Ruby / Python の 4 つの実装を同梱し、いずれも次のような役割を担います。

- `/api` への GET リクエストを受け取り、アクセストークンをキャッシュしながら Japan Post API に代理アクセスする
- それ以外のパスにはフロントエンドの `index.html` を返却する
- 住所検索フォームからのリクエストを扱いやすくするため、CORS ヘッダーや簡易ルーティングを提供する

## ディレクトリ構成

```
jp-digital-address-proxy/
├── shared/
│   ├── frontend/              # 共通フロントエンド（index.html など）
│   ├── config/                # 資格情報など（ユーザーが配置）
│   └── runtime/               # 実行時生成ファイル（アクセストークン等）
├── php/                       # PHP 実装
│   ├── index.php
│   └── server.php.sh          # PHP 内蔵サーバー起動用スクリプト
├── node/                      # Node.js 実装
│   ├── index.js
│   ├── package.json
│   └── server.nodejs.sh       # npm start ラッパースクリプト
├── ruby/                      # Ruby (Sinatra) 実装・Docker
│   ├── index.rb
│   ├── Gemfile / Gemfile.lock
│   ├── Dockerfile
│   └── server.ruby.sh
└── python/                    # Python (Flask) 実装・Docker
    ├── index.py
    ├── requirements.txt
    ├── Dockerfile
    └── server.python.sh
```

## 主なファイル

- `shared/frontend/index.html` – 郵便番号から住所を取得するフォーム。`/api?search_code=XXXXXXX` に fetch し、取得結果をフォームに反映する。
- `php/index.php` – PHP 版のプロキシ。cURL でトークン取得 (`/api/v1/j/token`) と住所検索 (`/api/v1/searchcode` or `/api/v1/addresszip`) を呼び出す。
- `node/index.js` – Node.js 版のプロキシ。Express を使用して PHP 版と同等の挙動を提供する。
- `ruby/index.rb` – Ruby (Sinatra) 版のプロキシ。Rack/Sinatra 上で PHP/Node と揃えたルーティングを提供する。
- `python/index.py` – Python (Flask) 版のプロキシ。requests を用いて API コールとトークンキャッシュを行う。
- `shared/config/credentials.json` – API クライアント資格情報（ユーザーが配置する）。
- `shared/runtime/access_token.json` – 取得したアクセストークンをキャッシュするためのファイル。初回リクエスト時や期限切れ時に自動で更新される。
- `php/server.php.sh` / `node/server.nodejs.sh` / `ruby/server.ruby.sh` / `python/server.python.sh` – 各言語版のローカル開発用起動スクリプト。

## 必要要件

- PHP 8.1 以降 (PHP 版を使用する場合)
- Node.js 18 以降 (Node.js 版を使用する場合)
- Ruby 3.1 以降 (Ruby 版を使用する場合)
- Python 3.10 以降 (Python 版を使用する場合)
- Japan Post Digital Address API のクライアント資格情報

## セットアップ

### 1. 資格情報ファイルの準備

`shared/config/credentials.json` を作成します。公開ディレクトリに配置しないことを推奨します。  
別場所に置く場合は、PHP/Node.js それぞれのソースで参照先を変更してください。

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
./php/server.php.sh           # ブラウザが自動で起動します
./php/server.php.sh 9000      # 引数または PORT=9000 でポート上書き

# 手動で起動する場合（ドキュメントルート: php）
php -S 127.0.0.1:8000 -t php php/index.php

# 動作確認例
curl "http://127.0.0.1:8000/api?search_code=1000001"
```

- PHP 組み込みサーバーが `/api` 以外のパスを `index.html` にフォールバックします。
- `/api` では GET 以外のメソッドを 204 で返却し、CORS ヘッダーを許可しています。
### 4. ローカル実行 (Node.js 版)

```bash
./node/server.nodejs.sh       # 初回は自動で npm install を実行
PORT=9000 ./node/server.nodejs.sh  # 環境変数または引数でポート上書き

# 直接起動（依存関係は別途 npm install）
cd node && npm start

# 動作確認例
curl "http://127.0.0.1:8000/api?search_code=1000001"
```

- 旧構成で生成されていたリポジトリ直下の `node_modules/` や `package-lock.json` は不要になったため削除し、`node/` 配下で再生成してください。
- `node/index.js` は `PORT`（既定 8000）と `HOST` を環境変数で受け取り、`shared/frontend` を静的配信します。
- トークンキャッシュは PHP 版と同じファイル (`shared/runtime/access_token.json`) を利用します。
- PHP ファイルは `.php-cs-fixer.php` のルールに従って整形できます。関数の波括弧は同じ行に配置する方針です。
### 5. ローカル実行 (Ruby 版)

```bash
./ruby/server.ruby.sh             # 初回は自動で bundle install を実行
PORT=9000 ./ruby/server.ruby.sh   # 環境変数または引数でポート上書き

# 直接起動（Bundler を手動で実行する場合）
cd ruby
bundle install --path vendor/bundle
HOST=127.0.0.1 PORT=8000 bundle exec ruby index.rb

# 動作確認例
curl "http://127.0.0.1:8000/api?search_code=1000001"
```

- `server.ruby.sh` は `bundle install` 実行後に `bundle exec ruby index.rb` を起動します。依存ライブラリは `ruby/vendor/` にインストールされ、`.gitignore` で除外しています。
- `index.rb` は Sinatra を利用し、PHP/Node 版と同じルーティング・トークンキャッシュの挙動を提供します。
### 6. ローカル実行 (Python 版)

```bash
./python/server.python.sh         # 仮想環境と依存関係を自動セットアップ
PORT=9000 ./python/server.python.sh   # 環境変数または引数でポート上書き

# 直接起動（手動で仮想環境を作成する場合）
cd python
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
HOST=127.0.0.1 PORT=8000 python index.py

# 動作確認例
curl "http://127.0.0.1:8000/api?search_code=1000001"
```

- `server.python.sh` はローカルに `.venv/` を作成して `Flask` / `requests` をインストールします。`.venv/` は `.gitignore` / `.dockerignore` 済みです。
- `index.py` は Flask で `/api` を提供し、各言語版と同じトークン管理・ルーティングを実装しています。
## Docker での開発

Docker と Docker Compose v2 が利用可能な環境では、コンテナ経由で各言語実装を起動できます。事前に `shared/config/credentials.json` を用意してから以下を実行してください。

```bash
# すべてのサービス (Node / PHP / Ruby / Python) を同時に起動
docker compose up

# 個別に起動
docker compose up node
docker compose up php
docker compose up ruby
docker compose up python
```

- Node サービスは `http://127.0.0.1:8000/`、PHP サービスは `http://127.0.0.1:8001/`、Ruby サービスは `http://127.0.0.1:8002/`、Python サービスは `http://127.0.0.1:8003/` でアクセスできます。
- 共有リソース（`shared/frontend` や `shared/config` など）はボリュームとしてマウントされるため、ホスト側の変更が即座に反映されます。
- 初回起動時は Node コンテナ内で `npm install` が走るため、準備完了まで少し時間がかかる場合があります。
- 各サービスのホスト側ポートは上記のとおり固定です。変更したい場合は `docker-compose.yml` を編集してください。

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

- `credentials.json` と `access_token.json` は機微情報を含むため、公開ディレクトリの外に置くか、アクセス制御を施してください。`shared/config` と `shared/runtime` を秘密裏に扱うか、 `.gitignore` などで除外することを検討してください。
- 認証情報や IP 制限の設定は本番環境に合わせて調整する必要があります。
- プロキシ先 API のステータスコードとレスポンスボディはそのままクライアントへ返されます。必要に応じてエラーハンドリングを追加してください。

## ライセンス

MIT License

[^jp-api]: 「郵便番号・デジタルアドレス for Biz」公式サイト https://guide-biz.da.pf.japanpost.jp/api/
