require "json"
require "net/http"
require "uri"
require "fileutils"
require "sinatra"
require "cgi"

# =========================
#  ruby/index.rb
# -------------------------
# - /api に来たリクエストを Japan Post Digital Address API へプロキシする
# - それ以外は shared/frontend/index.html を返す（画面表示）
#
# 必要なファイル／ディレクトリ：
# - shared/frontend/index.html
# - shared/config/credentials.json（ユーザーが配置）
# - shared/runtime/access_token.json（自動生成）
# =========================

set :bind, ENV.fetch("BIND_HOST", ENV.fetch("HOST", "127.0.0.1"))
set :port, ENV.fetch("PORT", "8002").to_i

ROOT_DIR = File.expand_path("..", __dir__)
SHARED_DIR = File.join(ROOT_DIR, "shared")
FRONTEND_DIR = File.join(SHARED_DIR, "frontend")
FRONTEND_HTML = File.join(FRONTEND_DIR, "index.html")
CONFIG_DIR = File.join(SHARED_DIR, "config")
RUNTIME_DIR = File.join(SHARED_DIR, "runtime")
TOKEN_FILE = File.join(RUNTIME_DIR, "access_token.json")
CREDENTIALS_FILE = File.join(CONFIG_DIR, "credentials.json")

set :public_folder, FRONTEND_DIR
set :static, true

# ========= ミドルウェア =========

before do
  next unless request.path_info.start_with?("/api")

  applyCorsHeaders
  halt 204 unless request.request_method == "GET"
end

# ========= ルーティング =========

get "/api" do
  handleApiRequest("")
end

get "/api/*" do |fallback|
  handleApiRequest(fallback)
end

get "/*" do |_path|
  serveIndexHtml
end

# ========= ヘルパー =========

helpers do
  def applyCorsHeaders
    headers(
      "Access-Control-Allow-Origin" => "*",
      "Access-Control-Allow-Methods" => "*",
      "Access-Control-Allow-Headers" => "*"
    )
  end

  def serveIndexHtml
    if File.exist?(FRONTEND_HTML)
      content_type "text/html", charset: "utf-8"
      return send_file(FRONTEND_HTML)
    end

    halt 404, "shared/frontend/index.html not found"
  end

  def handleApiRequest(fallback)
    search_code = getSearchCode(fallback)

    token_result = getAccessTokenOrFetch
    unless token_result[:ok]
      content_type :json
      halt token_result[:status], token_result[:body]
    end

    proxyJapanPostApi(token_result[:token], search_code)
  end

  # ========= search_code 取得 =========

  def getSearchCode(fallback)
    query_value = params["search_code"]
    return query_value.to_s unless query_value.nil? || query_value.empty?

    CGI.unescape(fallback.to_s)
  end

  # ========= アクセストークン取得 =========

  def getAccessTokenOrFetch
    cached = loadCachedToken
    return { ok: true, token: cached } if cached

    fetched = fetchNewToken
    return fetched unless fetched[:ok]

    ensureRuntimeDir
    File.write(TOKEN_FILE, fetched[:body])

    begin
      payload = JSON.parse(fetched[:body])
      token = payload.fetch("token")
      { ok: true, token: token }
    rescue StandardError => e
      {
        ok: false,
        status: 500,
        body: { error: "invalid_token_response", message: e.message }.to_json
      }
    end
  end

  def loadCachedToken
    return nil unless File.exist?(TOKEN_FILE)

    begin
      payload = JSON.parse(File.read(TOKEN_FILE))
      expires_in = Integer(payload.fetch("expires_in"))
      token = payload.fetch("token")
      return token if Time.now.to_i < File.mtime(TOKEN_FILE).to_i + expires_in
    rescue StandardError
      return nil
    end

    nil
  end

  def fetchNewToken
    unless File.exist?(CREDENTIALS_FILE)
      return {
        ok: false,
        status: 500,
        body: { error: "credentials.json not found" }.to_json
      }
    end

    uri = URI.parse("https://api.da.pf.japanpost.jp/api/v1/j/token")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["x-forwarded-for"] = "127.0.0.1"
    request.body = File.read(CREDENTIALS_FILE)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    {
      ok: response.code == "200",
      status: response.code.to_i,
      body: response.body.to_s
    }
  end

  # ========= Japan Post API プロキシ =========

  def proxyJapanPostApi(token, search_code)
    response =
      if isZipOrCode(search_code)
        uri = URI.parse("https://api.da.pf.japanpost.jp/api/v1/searchcode/#{URI.encode_www_form_component(search_code)}")
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{token}"
        Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.request(request)
        end
      else
        uri = URI.parse("https://api.da.pf.japanpost.jp/api/v1/addresszip")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{token}"
        request["Content-Type"] = "application/json"
        request.body = { freeword: search_code }.to_json
        Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.request(request)
        end
      end

    status response.code.to_i
    content_type :json
    response.body.to_s
  end

  # ========= ユーティリティ =========

  def ensureRuntimeDir
    FileUtils.mkdir_p(RUNTIME_DIR)
  end

  def isZipOrCode(value)
    !!(value =~ /^\d{3,7}$/ || value =~ /^\w{7}$/)
  end
end
