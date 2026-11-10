#!/usr/bin/env bash
# Syntax and value checks for infra/php and infra/mariadb, run against the real tools in this sandbox.
#   scripts/test-infra-config.sh        needs php, php-fpm8.3 and mariadbd (not run by `make lint`; see `make infra-test`)
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
db_pid=""
cleanup() {
  [ -z "$db_pid" ] || { kill "$db_pid" 2>/dev/null; wait "$db_pid" 2>/dev/null; }
  rm -rf -- "${tmp:?}"
}
trap cleanup EXIT
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
eq() { [ "$1" = "$2" ]; }

# ---------- PHP ini
printf 'TIME_ZONE=UTC\n' | python3 -I "$root/scripts/render-template.py" "$root/infra/php/99-worj.ini.template" "$tmp/99-worj.ini" --mode 644 >/dev/null
warn="$(php -n -c "$tmp/99-worj.ini" -r 'echo "";' 2>&1)"
yes "php loads 99-worj.ini with no warning" eq "$warn" ""
for kv in memory_limit=256M upload_max_filesize=64M post_max_size=66M expose_php= display_errors= session.cookie_secure=1 session.cookie_httponly=1 date.timezone=UTC opcache.revalidate_freq=60; do
  k="${kv%%=*}"; v="${kv#*=}"
  got="$(php -n -c "$tmp/99-worj.ini" -d zend_extension=opcache -r "echo ini_get('$k');")"
  yes "ini $k = '$v'" eq "$got" "$v"
done
if printf '' | python3 -I "$root/scripts/render-template.py" "$root/infra/php/99-worj.ini.template" "$tmp/x.ini" >/dev/null 2>&1; then bad "template renders without a time zone"; else ok "the time zone is required (never assumed)"; fi

# ---------- PHP-FPM pool
if command -v php-fpm8.3 >/dev/null; then
  cat >"$tmp/fpm.conf" <<CFG
[global]
pid = $tmp/fpm.pid
error_log = $tmp/fpm.log
include = $root/infra/php/worj-pool.conf
CFG
  out="$(php-fpm8.3 -t -y "$tmp/fpm.conf" 2>&1)"; rc=$?
  yes "php-fpm8.3 -t accepts the worj pool (exit $rc)" eq "$rc" 0
  yes "php-fpm says: configuration test is successful" grep -q "test is successful" <<<"$out"
  printf '[worj]\nuser = nosuchuserxyz\ngroup = www-data\nlisten = /tmp/x.sock\npm = nonsense\n' >"$tmp/bad-pool.conf"
  sed -i "s#^include = .*#include = $tmp/bad-pool.conf#" "$tmp/fpm.conf"
  php-fpm8.3 -t -y "$tmp/fpm.conf" >/dev/null 2>&1; rc=$?
  yes "a broken pool is rejected by the same check (exit $rc)" test "$rc" != 0
else
  echo "SKIP  php-fpm8.3 not installed"
fi

# ---------- MariaDB: load the cnf in a throwaway server and read the variables back
if command -v mariadbd >/dev/null && command -v mariadb-install-db >/dev/null; then
  data="$tmp/data"; mkdir -p "$data" "$tmp/log"
  chown -R mysql:mysql "$tmp" 2>/dev/null; chmod 755 "$tmp"
  sed -e "s#/var/log/mysql/worj-slow.log#$tmp/log/slow.log#" "$root/infra/mariadb/60-worj.cnf" >"$tmp/60-worj.cnf"
  cat >"$tmp/my.cnf" <<CFG
!include $tmp/60-worj.cnf
[mysqld]
datadir = $data
socket = $tmp/db.sock
pid-file = $tmp/db.pid
port = 33991
bind-address = 127.0.0.1
log-error = $tmp/log/error.log
innodb_buffer_pool_size = 1G
CFG
  mariadb-install-db --no-defaults --user=mysql --datadir="$data" --auth-root-authentication-method=normal >"$tmp/log/install.log" 2>&1
  mariadbd --defaults-file="$tmp/my.cnf" --user=mysql >"$tmp/log/run.log" 2>&1 &
  db_pid=$!
  up=0; for _ in $(seq 1 40); do mariadb --no-defaults -uroot -S "$tmp/db.sock" -e 'select 1' >/dev/null 2>&1 && { up=1; break; }; sleep 0.5; done
  if [ "$up" = 1 ]; then
    q() { mariadb --no-defaults -uroot -S "$tmp/db.sock" -N -e "select @@$1"; }
    yes "mariadbd started with 60-worj.cnf" true
    yes "character_set_server = utf8mb4" eq "$(q character_set_server)" utf8mb4
    yes "collation_server = utf8mb4_unicode_ci" eq "$(q collation_server)" utf8mb4_unicode_ci
    yes "innodb_log_file_size = 256M" eq "$(q innodb_log_file_size)" 268435456
    yes "max_connections = 60" eq "$(q max_connections)" 60
    yes "local_infile = 0" eq "$(q local_infile)" 0
    yes "skip_name_resolve on" eq "$(q skip_name_resolve)" 1
    yes "bind_address = 127.0.0.1" eq "$(q bind_address)" 127.0.0.1
    yes "slow_query_log = 1" eq "$(q slow_query_log)" 1
  else
    bad "mariadbd did not start (see below)"; tail -5 "$tmp/log/error.log" 2>/dev/null; tail -3 "$tmp/log/run.log" 2>/dev/null
  fi
else
  echo "SKIP  mariadbd not installed"
fi

# ---------- Nginx: render the templates and let nginx -t judge them
if command -v nginx >/dev/null; then
  ng="$tmp/nginx"; mkdir -p "$ng/errors" "$ng/acme" "$ng/web" "$ng/tmp"
  cp "$root/infra/nginx/errors/404.html" "$root/infra/nginx/errors/404.css" "$ng/errors/"
  : >"$ng/realip.conf"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$ng/key.pem" -out "$ng/cert.pem" -days 1 -subj "/CN=journal.example.org" >/dev/null 2>&1
  vals="HOST=journal.example.org
ALT_HOST=www.journal.example.org
WEBROOT=$ng/web
CERT_FULLCHAIN=$ng/cert.pem
CERT_KEY=$ng/key.pem
PHP_SOCK=$ng/php.sock
SNIPPETS=$ng/out/snippets
ERRORS_ROOT=$ng/errors
ACME_ROOT=$ng/acme
REALIP_CONF=$ng/realip.conf
HTTP_PORT=18080
HTTPS_PORT=18443
HSTS_MAX_AGE=300"
  printf '%s\n' "$vals" | "$root/scripts/render-nginx.sh" "$ng/out" >/dev/null
  cat >"$ng/nginx.conf" <<CFG
pid $ng/nginx.pid;
error_log $ng/error.log;
events {}
http {
  access_log off;
  include /etc/nginx/mime.types;
  client_body_temp_path $ng/tmp/body;
  fastcgi_temp_path $ng/tmp/fcgi;
  proxy_temp_path $ng/tmp/proxy;
  uwsgi_temp_path $ng/tmp/uwsgi;
  scgi_temp_path $ng/tmp/scgi;
  include $ng/out/worj.conf;
}
CFG
  out="$(nginx -t -c "$ng/nginx.conf" 2>&1)"; rc=$?
  yes "nginx -t accepts the rendered site (exit $rc)" eq "$rc" 0
  [ "$rc" = 0 ] || echo "$out" | head -4
  yes "nginx says the configuration test is successful" grep -q "test is successful" <<<"$out"
  # the same check must reject a broken snippet
  cp -r "$ng/out" "$ng/broken"; echo 'this_directive_does_not_exist on;' >>"$ng/broken/snippets/worj-errors.conf"
  sed -i "s#$ng/out/#$ng/broken/#g" "$ng/broken/worj.conf" "$ng"/broken/snippets/*.conf
  sed "s#$ng/out/#$ng/broken/#" "$ng/nginx.conf" >"$ng/nginx-broken.conf"
  nginx -t -c "$ng/nginx-broken.conf" >/dev/null 2>&1; rc=$?
  yes "a broken snippet is rejected by the same check (exit $rc)" test "$rc" != 0
  # rules the templates must keep
  yes "the site refuses unknown hosts (444 and ssl_reject_handshake)" grep -q "return 444" "$ng/out/worj.conf"
  yes "no location in the templates uses add_header (headers would be lost)" bash -c "! grep -hE '^[[:space:]]+add_header' '$ng'/out/snippets/worj-ojs-locations.conf '$ng'/out/snippets/worj-errors.conf '$ng'/out/snippets/worj-fastcgi.conf"
  yes "exactly one FastCGI pass, in the shared snippet" eq "$(grep -hc 'fastcgi_pass' "$ng"/out/snippets/worj-fastcgi.conf)" 1
  yes "any other .php path is a 404" grep -qF 'location ~ \.php(/|$) { return 404; }' "$ng/out/snippets/worj-ojs-locations.conf"
  api_block="$(sed -n '/index\\.php\/\[^\/\]+\/api/,/^}/p' "$ng/out/snippets/worj-ojs-locations.conf")"
  yes "the API location exists" grep -q 'fastcgi.conf\|worj-fastcgi' <<<"$api_block"
  no_intercept() { ! grep -v '^[[:space:]]*#' <<<"$api_block" | grep -q fastcgi_intercept_errors; }
  yes "the API location does not intercept errors" no_intercept
  yes "CSP is report-only, never enforcing" bash -c "grep -q 'Content-Security-Policy-Report-Only' '$ng'/out/snippets/worj-security-headers.conf && ! grep -hq 'add_header Content-Security-Policy ' '$ng'/out/snippets/*.conf '$ng'/out/worj.conf"
  yes "HSTS has no preload and no includeSubDomains" bash -c "grep -v '^#' '$ng'/out/snippets/worj-security-headers.conf | grep -qiE 'preload|includeSubDomains' && exit 1 || exit 0"
else
  echo "SKIP  nginx not installed"
fi

# ---------- the static 404 page
page="$root/infra/nginx/errors/404.html"
yes "404 page has lang" grep -q '<html lang="en">' "$page"
yes "404 page has a title" grep -q '<title>.\+</title>' "$page"
yes "404 page has header, main and footer landmarks" bash -c "grep -q '<header>' '$page' && grep -q '<main' '$page' && grep -q '<footer>' '$page'"
yes "404 page has exactly one h1" eq "$(grep -c '<h1>' "$page")" 1
yes "404 page has no script, inline style or remote asset" bash -c "! grep -qiE '<script|<style|style=|https?://' '$page'"
yes "404 stylesheet has no remote url" bash -c "! grep -qiE 'url\\(|@import|https?://' '$root/infra/nginx/errors/404.css'"

# ---------- cron and logrotate templates
printf 'INSTALL_DIR=/usr/local/sbin\nREALIP_CONF=/etc/nginx/worj-cloudflare-realip.conf\n' | python3 -I "$root/scripts/render-template.py" "$root/infra/cron.d/worj.template" "$tmp/worj.cron" --mode 644 >/dev/null
yes "cron file has no unfilled token" bash -c "! grep -q '@@' '$tmp/worj.cron'"
yes "cron lines have 5 time fields, a user and a command" bash -c "grep -vE '^(#|$|[A-Z]+=)' '$tmp/worj.cron' | awk 'NF < 7 { bad=1 } END { exit bad }'"
yes "the backup runs nightly as root" grep -qE '^17 2 \* \* \* root /usr/local/sbin/worj-backup --env /etc/worj/backup.env' "$tmp/worj.cron"
yes "no cron line carries a password or key" bash -c "! grep -qiE 'password|secret|AGE-SECRET' '$tmp/worj.cron'"
yes "backup.env.example has no private key and no password" bash -c "! grep -qE 'AGE-SECRET-KEY|^WORJ_.*PASSWORD' '$root/infra/backup.env.example'"

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "$fail FAILED"; fi
exit "$fail"
