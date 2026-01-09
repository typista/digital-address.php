<?php
/**
 * php/index.php
 *
 * - /api に来たリクエストを Japan Post Digital Address API へプロキシする
 * - それ以外は shared/frontend/index.html を返す（画面表示）
 *
 * 前提となるファイル／ディレクトリ：
 * - shared/frontend/index.html
 * - shared/config/credentials.json（ユーザーが配置）
 * - shared/runtime/access_token.json（自動生成）
 */

define('BASE_DIR', dirname(__DIR__));
define('SHARED_DIR', BASE_DIR . '/shared');
define('FRONTEND_HTML', SHARED_DIR . '/frontend/index.html');
define('CONFIG_DIR', SHARED_DIR . '/config');
define('RUNTIME_DIR', SHARED_DIR . '/runtime');
define('TOKEN_FILE', RUNTIME_DIR . '/access_token.json');
define('CREDENTIALS_FILE', CONFIG_DIR . '/credentials.json');

/* ========= ルーティング ========= */
function logRequest(int $status): void {
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    $uri = $_SERVER['REQUEST_URI'] ?? '/';
    if ($uri === '') {
        $uri = '/';
    }
    $host = getenv('PUBLIC_HOST');
    if ($host === false || $host === '') {
        $host = $_SERVER['HTTP_HOST'] ?? '127.0.0.1';
    }
    $port = getenv('PUBLIC_PORT');
    if ($port === false || $port === '') {
        $port = $_SERVER['SERVER_PORT'] ?? '';
    }
    $scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
    $base = $scheme . '://' . $host;
    if ($port !== '' && strpos($host, ':') === false) {
        $base .= ':' . $port;
    }
    error_log(sprintf('[php-proxy] %s %s%s -> %d', $method, $base, $uri, $status));
}

$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

if ($path === '/api' || str_starts_with($path ?? '', '/api/')) {
    handleApiRequest();
    exit;
}

serveIndexHtml();
exit;


/* ========= 画面返却 ========= */
function serveIndexHtml(): void {
    header('Content-Type: text/html; charset=utf-8');

    if (file_exists(FRONTEND_HTML)) {
        http_response_code(200);
        readfile(FRONTEND_HTML);
        logRequest(http_response_code());
        return;
    }

    http_response_code(404);
    echo 'shared/frontend/index.html not found';
    logRequest(404);
}


/* ========= API処理 ========= */
function handleApiRequest(): void {
    // CORS（API用）
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: *');
    header('Access-Control-Allow-Headers: *');

    // GET以外は 204（元処理と同等）
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'GET') {
        http_response_code(204);
        logRequest(204);
        return;
    }

    // search_code の取得（元処理を踏襲）
    $search_code = getSearchCode();

    // Token確保（キャッシュ→なければ取得）
    $token_result = getAccessTokenOrFetch();
    if (!($token_result['ok'] ?? false)) {
        $status = (int) ($token_result['status'] ?? 500);
        http_response_code($status);
        header('Content-Type: application/json');
        echo $token_result['body'] ?? '';
        logRequest($status);
        return;
    }

    // Japan Post APIへプロキシして、そのまま返却
    proxyJapanPostApi($token_result['token'], $search_code);
}


/* ========= search_code 取得 ========= */
function getSearchCode(): string {
    // クエリ優先
    if (isset($_GET['search_code'])) {
        return (string)$_GET['search_code'];
    }

    // クエリが無い場合は /api/{code} の末尾を利用
    $path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?? '';
    if (str_starts_with($path, '/api/')) {
        $fallback = substr($path, strlen('/api/'));
        return (string)rawurldecode($fallback);
    }

    return '';
}


/* ========= アクセストークン取得 ========= */
function getAccessTokenOrFetch(): array {
    // キャッシュがあれば利用
    $cached = loadCachedToken(TOKEN_FILE);
    if ($cached !== null) {
        return [
            'ok'    => true,
            'token' => $cached,
        ];
    }

    // 無ければ取得
    $result = fetchNewToken();
    if ($result['ok'] === false) {
        return $result;
    }

    // runtime ディレクトリが無い場合は作成
    ensureRuntimeDir();

    // 保存して返す
    file_put_contents(TOKEN_FILE, $result['body']);
    $obj = json_decode($result['body']);
    if (!$obj || !isset($obj->token)) {
        return [
            'ok'     => false,
            'status' => 500,
            'body'   => json_encode(
                ['error' => 'invalid_token_response', 'message' => 'token missing'],
                JSON_UNESCAPED_UNICODE
            ),
        ];
    }

    return [
        'ok'    => true,
        'token' => (string)$obj->token,
    ];
}


/* ========= トークンキャッシュ読み込み ========= */
function loadCachedToken(string $token_filename): ?string {
    if (!file_exists($token_filename)) {
        return null;
    }

    $json = file_get_contents($token_filename);
    if ($json === false) {
        return null;
    }

    $obj = json_decode($json);
    if (!$obj || !isset($obj->expires_in, $obj->token)) {
        return null;
    }

    // PHP元処理： time() < filemtime + expires_in
    $expiresAt = filemtime($token_filename) + (int)$obj->expires_in;
    if (time() < $expiresAt) {
        return (string)$obj->token;
    }

    return null;
}


/* ========= 新規トークン取得 ========= */
function fetchNewToken(): array {
    if (!file_exists(CREDENTIALS_FILE)) {
        return [
            'ok'     => false,
            'status' => 500,
            'body'   => json_encode(['error' => 'credentials.json not found'], JSON_UNESCAPED_UNICODE),
        ];
    }

    $ch = curl_init('https://api.da.pf.japanpost.jp/api/v1/j/token');
    curl_setopt($ch, CURLOPT_USERAGENT, 'curl/' . curl_version()['version']);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Content-Type: application/json',
        'x-forwarded-for: 127.0.0.1',
    ]);
    curl_setopt($ch, CURLOPT_POSTFIELDS, file_get_contents(CREDENTIALS_FILE));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);

    $body = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);

    return [
        'ok'     => (int)$code === 200,
        'status' => (int)$code,
        'body'   => $body === false ? '' : $body,
    ];
}


/* ========= JapanPost APIへプロキシ ========= */
function proxyJapanPostApi(string $token, string $search_code): void {
    header('Content-Type: application/json');

    if (isZipOrCode($search_code)) {
        // GET /searchcode/{search_code}
        $url = "https://api.da.pf.japanpost.jp/api/v1/searchcode/" . rawurlencode($search_code);

        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_USERAGENT, 'curl/' . curl_version()['version']);
        curl_setopt($ch, CURLOPT_HTTPHEADER, ["Authorization: Bearer $token"]);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);

        $body = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        curl_close($ch);

        $status = (int)$code;
        http_response_code($status);
        echo $body === false ? '' : $body;
        logRequest($status);
        return;
    }

    // POST /addresszip
    $ch = curl_init('https://api.da.pf.japanpost.jp/api/v1/addresszip');
    curl_setopt($ch, CURLOPT_USERAGENT, 'curl/' . curl_version()['version']);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        "Authorization: Bearer $token",
        'Content-Type: application/json',
    ]);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode(['freeword' => $search_code], JSON_UNESCAPED_UNICODE));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);

    $body = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);

    $status = (int)$code;
    http_response_code($status);
    echo $body === false ? '' : $body;
    logRequest($status);
}


/* ========= search_code 種別判定 ========= */
function isZipOrCode(string $search_code): bool {
    return preg_match('/^\d{3,7}$/', $search_code) === 1
        || preg_match('/^\w{7}$/', $search_code) === 1;
}


/* ========= 補助 ========= */
function ensureRuntimeDir(): void {
    if (!is_dir(RUNTIME_DIR)) {
        mkdir(RUNTIME_DIR, 0775, true);
    }
}

