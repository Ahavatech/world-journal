<?php
// WORJ Day-0 probe. Prints only non-secret facts. Delete after use. See README.txt.
header('Content-Type: application/json');
header('Cache-Control: no-store');
function worj_mask($s) { return preg_replace('#/home/u[0-9]+#', '/home/uXXXXXXXXX', (string) $s); }
$doc = rtrim((string) ($_SERVER['DOCUMENT_ROOT'] ?? ''), '/');
$writable = [];
foreach ([1, 2] as $levels) {
    $dir = $doc;
    for ($i = 0; $i < $levels; $i++) { $dir = dirname($dir); }
    $file = $dir . '/.worj-day0-write-test-' . bin2hex(random_bytes(4));
    $ok = @file_put_contents($file, 'x') !== false;
    if ($ok) { @unlink($file); }
    $writable[] = ['levels_above_web_root' => $levels, 'writable' => $ok, 'path' => worj_mask($dir)];
}
$ext = get_loaded_extensions();
sort($ext, SORT_NATURAL | SORT_FLAG_CASE);
$ini = [];
foreach (['memory_limit', 'upload_max_filesize', 'post_max_size', 'max_execution_time', 'max_input_time', 'max_file_uploads',
          'open_basedir', 'disable_functions', 'allow_url_fopen', 'date.timezone', 'opcache.enable', 'default_charset'] as $k) {
    $ini[$k] = worj_mask(ini_get($k));
}
echo json_encode([
    'php_version' => PHP_VERSION,
    'sapi' => PHP_SAPI,
    'server_software' => $_SERVER['SERVER_SOFTWARE'] ?? '',
    'https' => !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off',
    'document_root' => worj_mask($doc),
    'extensions' => array_map('strtolower', $ext),
    'ini' => $ini,
    'write_test_above_web_root' => $writable,
    'proxy_headers_present' => ['x_forwarded_for' => isset($_SERVER['HTTP_X_FORWARDED_FOR']), 'cf_connecting_ip' => isset($_SERVER['HTTP_CF_CONNECTING_IP'])],
], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
