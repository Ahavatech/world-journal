#!/usr/bin/env bash
# Local Nginx (rendered from infra/nginx) in front of the sandbox OJS: redirects, deny rules, headers, 404 pages.
#   scripts/test-nginx-harness.sh        needs the sandbox up (make sandbox-up sandbox-seed) and root
# Instance A is the PRODUCTION render (ports 18080/18443). The sandbox config.inc.php is changed for the run
# (base_url, allowed_hosts) and restored by trap. Nothing here touches a real server: UNVERIFIED (not run on VPS).
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$(id -u)" = 0 ] || { echo "run as root (sandbox container)"; exit 2; }
core="$root/ojs-core"
tmp="$(mktemp -d)"
cfg="$core/config.inc.php"
files_dir="$(sed -n 's/^files_dir *= *\(.*\)$/\1/p' "$cfg" | tr -d '"' | head -1)"
export NODE_PATH="${NODE_PATH:-/opt/node22/lib/node_modules}"
cp "$cfg" "$tmp/config.orig"
probes=("$core/public/worj-harness-upload.php" "$core/public/worj-harness.sql.bak" "$files_dir/worj-harness-private.txt")
cleanup() {
  [ ! -f "$tmp/nginxA.pid" ] || kill "$(cat "$tmp/nginxA.pid")" 2>/dev/null
  [ ! -f "$tmp/nginxB.pid" ] || kill "$(cat "$tmp/nginxB.pid")" 2>/dev/null
  cp "$tmp/config.orig" "$cfg"
  for f in "${probes[@]}"; do rm -f -- "$f"; done
  rm -rf -- "${tmp:?}"
}
[ -n "${HARNESS_DEBUG:-}" ] && echo "debug: tmp=$tmp (kept)" >&2
trap '[ -n "${HARNESS_DEBUG:-}" ] && { cp "$tmp"/error*.log /tmp/claude-0/ 2>/dev/null; }; cleanup' EXIT

curl -s -o /dev/null -m 5 "http://127.0.0.1:8082/worj/" || { echo "sandbox not running (make sandbox-up sandbox-seed)"; exit 2; }
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
eq() { [ "$1" = "$2" ]; }
has() { grep -qiF -- "$2" <<<"$1"; }
lacks() { ! grep -qiF -- "$2" <<<"$1"; }

# ---- sandbox config for the run: the harness host name and port, restored by trap
sed -i -E "s#^base_url = .*#base_url = \"https://journal.example.org:18443\"#; s#^allowed_hosts = .*#allowed_hosts = '[\"journal.example.org\",\"127.0.0.1\"]'#" "$cfg"

# ---- render and start instance A (the production render)
mkdir -p "$tmp/errors" "$tmp/acme" "$tmp/tmp"
chmod 755 "$tmp" "$tmp/errors" "$tmp/acme"   # the nginx worker (www-data) must read the error pages
cp "$root/infra/nginx/errors/404.html" "$root/infra/nginx/errors/404.css" "$tmp/errors/"
printf 'set_real_ip_from 127.0.0.1;\nreal_ip_header CF-Connecting-IP;\nreal_ip_recursive on;\n' >"$tmp/realip.conf"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -days 1 \
  -subj "/CN=journal.example.org" -addext "subjectAltName=DNS:journal.example.org,DNS:www.journal.example.org" >/dev/null 2>&1
render() { # outdir http_port https_port
  printf 'HOST=journal.example.org\nALT_HOST=www.journal.example.org\nWEBROOT=%s\nCERT_FULLCHAIN=%s\nCERT_KEY=%s\nPHP_SOCK=%s\nSNIPPETS=%s\nERRORS_ROOT=%s\nACME_ROOT=%s\nREALIP_CONF=%s\nHTTP_PORT=%s\nHTTPS_PORT=%s\nHSTS_MAX_AGE=300\n' \
    "$core" "$tmp/cert.pem" "$tmp/key.pem" "${PHP_SOCK:-/run/php/php8.3-fpm.sock}" "$1/snippets" "$tmp/errors" "$tmp/acme" "$tmp/realip.conf" "$2" "$3" |
    "$root/scripts/render-nginx.sh" "$1" >/dev/null
}
wrapper() { # outdir name
  cat >"$tmp/nginx$2.conf" <<CFG
user www-data;
pid $tmp/nginx$2.pid;
error_log $tmp/error$2.log info;
events {}
http {
  log_format worj '\$remote_addr \$status \$request_method \$request_uri';
  access_log $tmp/access$2.log worj;
  include /etc/nginx/mime.types;
  client_body_temp_path $tmp/tmp/body$2;
  fastcgi_temp_path $tmp/tmp/fcgi$2;
  proxy_temp_path $tmp/tmp/proxy$2;
  uwsgi_temp_path $tmp/tmp/uwsgi$2;
  scgi_temp_path $tmp/tmp/scgi$2;
  include $1/worj.conf;
}
CFG
}
render "$tmp/outA" 18080 18443
wrapper "$tmp/outA" A
nginx -c "$tmp/nginxA.conf" || { echo "nginx A did not start"; exit 2; }
sleep 1

H=journal.example.org
[ -z "${HARNESS_DEBUG:-}" ] || curl -skv --noproxy "*" -m 10 --resolve "$H:18443:127.0.0.1" "https://$H:18443/worj/" -o /dev/null 2>&1 | head -25 >&2
cu() { curl -sk --noproxy "*" --resolve "$H:18443:127.0.0.1" --resolve "www.$H:18443:127.0.0.1" --resolve "$H:18080:127.0.0.1" --resolve "www.$H:18080:127.0.0.1" -m 30 "$@"; }
S="https://$H:18443"
status() { cu -o /dev/null -w '%{http_code}' "$@"; }
loc() { cu -o /dev/null -D - "$@" | tr -d '\r' | sed -n 's/^[Ll]ocation: //p'; }
hdr() { cu -o /dev/null -D - "$@" | tr -d '\r'; }

echo "=== redirects (one canonical form per URL)"
yes "http -> 301" eq "$(status "http://$H:18080/worj/about?x=1")" 301
yes "http://journal... /worj/about?x=1 -> https://journal.example.org/worj/about?x=1" eq "$(loc "http://$H:18080/worj/about?x=1")" "https://$H/worj/about?x=1"
yes "http://www... -> https://journal.example.org (main host)" eq "$(loc "http://www.$H:18080/worj/about")" "https://$H/worj/about"
yes "https://www... -> https://journal.example.org (main host)" eq "$(loc "https://www.$H:18443/worj/about")" "https://$H/worj/about"
yes "GET /index.php/worj/about -> /worj/about" eq "$(loc "$S/index.php/worj/about")" "https://$H/worj/about"
yes "GET /index.php/worj/about?x=1 keeps the query" eq "$(loc "$S/index.php/worj/about?x=1")" "https://$H/worj/about?x=1"
yes "GET /index.php -> /" eq "$(loc "$S/index.php")" "https://$H/"
yes "HEAD /index.php/worj/about -> 301" eq "$(cu -I -o /dev/null -w '%{http_code}' "$S/index.php/worj/about")" 301
post_status="$(status -X POST -d 'username=a&password=b' "$S/index.php/worj/login/signIn")"
yes "POST to an index.php URL is NOT redirected (got $post_status)" test "$post_status" != 301
post2="$(status -X POST -d 'username=a&password=b' "$S/worj/login/signIn")"
yes "POST to the clean URL reaches OJS (got $post2)" test "$post2" != 301 -a "$post2" != 404
yes "the clean home page is served (200)" eq "$(status "$S/worj/")" 200
yes "an article page and its galley are separate URLs, no redirect between them (article $(status "$S/worj/article/view/1"), galley $(status "$S/worj/article/view/1/1"))" test "$(status "$S/worj/article/view/1")" = 200

echo "=== unknown hosts"
cu -o /dev/null -H 'Host: evil.example' "http://127.0.0.1:18080/"; rc=$?
yes "unknown Host on port 80: connection dropped (curl exit $rc, 52 = empty reply)" eq "$rc" 52
curl -sk --noproxy "*" -o /dev/null -m 10 --resolve evil.example:18443:127.0.0.1 "https://evil.example:18443/"; rc=$?
yes "unknown Host on 443: TLS handshake refused (curl exit $rc)" test "$rc" != 0

echo "=== files that must never be served"
for p in /config.inc.php /config.TEMPLATE.inc.php /.git/config /.env /.htaccess /tools/install.php /lib/pkp/tools/appKey.php \
         /cache/ /registry/emailTemplates.xml /classes/ /locale/en/common.po /public/worj-harness.sql.bak /composer.json /index.php.bak; do
  printf 'secret-backup' >"$core/public/worj-harness.sql.bak"
  st="$(status --path-as-is "$S$p")"
  yes "GET $p -> 404 (got $st)" eq "$st" 404
done
printf '<?php echo "EXECUTED"; ?>' >"$core/public/worj-harness-upload.php"
body="$(cu "$S/public/worj-harness-upload.php")"; st="$(status "$S/public/worj-harness-upload.php")"
yes "an uploaded .php in public/ is not executed (status $st)" eq "$st" 404
yes "...and its code is not shown either" bash -c "! grep -qE 'EXECUTED|<\\?php' <<<'$body'"
yes "...also with path info (public/x.php/y)" eq "$(status "$S/public/worj-harness-upload.php/y")" 404
mkdir -p "$files_dir"; printf 'private submission' >"$files_dir/worj-harness-private.txt"
yes "files_dir content is not reachable by URL (/worj-harness-private.txt)" eq "$(status "$S/worj-harness-private.txt")" 404
yes "...nor through traversal" test "$(status --path-as-is "$S/../../../..$files_dir/worj-harness-private.txt")" != 200
private_rel="$(cd "$files_dir" && find . -type f -name '*.pdf' | head -1 | sed 's#^\./##')"
if [ -n "$private_rel" ]; then
  yes "a real private submission file is not served by path ($private_rel)" test "$(status "$S/$private_rel")" != 200
else
  echo "SKIP  no PDF found under files_dir"
fi
pdf_head="$(cu "$S/worj/article/download/1/1" | head -c 4)"
yes "a public PDF galley still downloads through OJS (starts with %PDF)" eq "$pdf_head" "%PDF"

echo "=== security headers and caching"
home_h="$(hdr "$S/worj/")"
for h in "Strict-Transport-Security: max-age=300" "X-Content-Type-Options: nosniff" "X-Frame-Options: SAMEORIGIN" "Referrer-Policy: strict-origin-when-cross-origin" "Permissions-Policy:"; do
  yes "PHP page has $h" has "$home_h" "$h"
done
css="/plugins/themes/worj/assets/css/base.css"
css_h="$(hdr "$S$css")"
yes "the theme CSS is served (200)" has "$css_h" "200"
for h in "Strict-Transport-Security: max-age=300" "X-Content-Type-Options: nosniff" "X-Frame-Options: SAMEORIGIN"; do
  yes "static file has $h" has "$css_h" "$h"
done
yes "THEME files are cached for one hour only (OJS versions them with the OJS version, not the theme's)" has "$css_h" "max-age=3600"
core_h="$(hdr "$S/lib/pkp/styles/fontawesome/fontawesome.css")"
yes "OJS core static files are cached for 7 days (their ?v= changes on an OJS upgrade)" has "$core_h" "max-age=604800"
yes "theme images (no version at all) are also one hour" has "$(hdr "$S/plugins/themes/worj/assets/img/logo-header.jpg")" "max-age=3600"
yes "the HTML page has no 7-day Cache-Control (OJS sends: $(grep -i '^cache-control:' <<<"$home_h" | tr -d '\r'))" lacks "$(grep -i '^cache-control:' <<<"$home_h")" "max-age=604800"
yes "public page sends CSP Report-Only" has "$home_h" "Content-Security-Policy-Report-Only:"
yes "public page never sends an ENFORCING CSP" bash -c "! grep -qiE '^Content-Security-Policy:' <<<'$home_h'"
yes "backend path (management) sends no CSP" lacks "$(hdr "$S/worj/management/settings/website")" "Content-Security-Policy"
yes "API path sends no CSP" lacks "$(hdr "$S/worj/api/v1/submissions")" "Content-Security-Policy"
yes "headers are present on a 404 too" has "$(hdr "$S/worj/no-such-page")" "X-Content-Type-Options: nosniff"

echo "=== 404 pages"
nf_body="$(cu "$S/worj/this-page-does-not-exist")"; nf_status="$(status "$S/worj/this-page-does-not-exist")"
yes "unknown OJS route: status 404 (got $nf_status)" eq "$nf_status" 404
yes "...with the static page (lang)" has "$nf_body" '<html lang="en">'
yes "...title" has "$nf_body" "<title>Page not found"
yes "...main landmark" has "$nf_body" "<main"
yes "a denied path also shows the static page" has "$(cu "$S/config.inc.php")" "<title>Page not found"
api_h="$(hdr "$S/worj/api/v1/nonexistent")"
api_body="$(cu "$S/worj/api/v1/nonexistent")"
yes "API 404 keeps its status (404)" has "$api_h" "404"
yes "API 404 is still JSON (content-type)" has "$api_h" "application/json"
yes "API 404 body is not the HTML page" lacks "$api_body" "<html"
yes "/_errors/404.html is internal (direct request 404)" eq "$(status "$S/_errors/404.html")" 404
yes "/_errors/404.css is served" eq "$(status "$S/_errors/404.css")" 200

echo "=== real client address"
cu -o /dev/null -H 'CF-Connecting-IP: 203.0.113.9' "$S/worj/about" >/dev/null
sleep 1
yes "the address from CF-Connecting-IP (a trusted proxy sent it) is what Nginx logs" grep -q '^203.0.113.9 ' "$tmp/accessA.log"
cu -o /dev/null "$S/worj/login" >/dev/null; sleep 1
yes "without the header the peer address is logged" grep -q '^127.0.0.1 .* /worj/login' "$tmp/accessA.log"
yes "the login page has a username field" has "$(cu "$S/worj/login")" 'name="username"'

[ -z "${HARNESS_HOLD:-}" ] || { echo "HOLD: nginx A is up on 18443 for ${HARNESS_HOLD}s" >&2; sleep "$HARNESS_HOLD"; }
echo "=== browser checks (Playwright): axe on the 404 page, CSP violations"
if [ -d "$root/autoresearch/eval/node_modules/@axe-core" ]; then
  node "$root/scripts/test-nginx-browser.js" axe "https://$H:18443/worj/this-page-does-not-exist" || fail=$((fail + 1))
else
  echo "SKIP  autoresearch/eval dependencies missing (cd autoresearch/eval && npm ci)"
fi

if [ -d "$root/autoresearch/eval/node_modules/@axe-core" ]; then
  echo "=== every page and admin page loads all its assets through the production render"
  node "$root/scripts/test-nginx-browser.js" assets "https://$H:18443" "$root" || fail=$((fail + 1))
fi

if [ "${HARNESS_CSP:-1}" = 1 ] && [ -d "$root/autoresearch/eval/node_modules/@axe-core" ]; then
  # Instance B is TEST ONLY: the policy is ENFORCING and applies to every path, admin included, so violations show.
  sed -i -E "s#^base_url = .*#base_url = \"https://journal.example.org:18444\"#" "$cfg"
  render "$tmp/outB" 18081 18444
  sed -i 's/Content-Security-Policy-Report-Only/Content-Security-Policy/' "$tmp/outB/snippets/worj-security-headers.conf"
  python3 -I - "$tmp/outB/worj.conf" <<'PY'
import re, sys
p = sys.argv[1]
text = open(p).read()
# drop the three backend exemptions of the CSP map so the test policy applies to every path
text = "\n".join(l for l in text.split("\n") if not re.match(r'^\s+"~.*(management\|workflow|index/\(admin|call)', l) and '$$$call$$$' not in l.replace('\\', ''))
open(p, "w").write(text)
PY
  wrapper "$tmp/outB" B
  if nginx -c "$tmp/nginxB.conf"; then
    sleep 1
    node "$root/scripts/test-nginx-browser.js" csp "https://$H:18444" "$root" || fail=$((fail + 1))
  else
    bad "nginx B (test-only enforcing CSP) did not start"
  fi
fi

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "$fail FAILED"; fi
exit "$fail"
