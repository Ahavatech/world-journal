#!/usr/bin/env bash
# The shared-hosting .htaccess (infra/shared-hosting) in front of the sandbox OJS, on a stand-in Apache.
#   scripts/test-htaccess-harness.sh     needs the sandbox up (make sandbox-up sandbox-seed), apache2 and root
# HONEST LIMIT: this proves Apache semantics, not LiteSpeed's. The Day-0 kit and the same checks on the real host
# decide that. UNVERIFIED (not run on the host). The sandbox config.inc.php and web root files are changed for the
# run and restored by trap.
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$(id -u)" = 0 ] || { echo "run as root (sandbox container)"; exit 2; }
command -v apache2 >/dev/null || { echo "apache2 missing (apt-get install -y apache2)"; exit 2; }
core="$root/ojs-core"
cfg="$core/config.inc.php"
tmp="$(mktemp -d)"
SOCK="${PHP_SOCK:-/run/php/php8.3-fpm.sock}"
files_dir="$(sed -n 's/^files_dir *= *\(.*\)$/\1/p' "$cfg" | tr -d '"' | sed -n 1p)"
cp "$cfg" "$tmp/config.orig"; cp "$core/robots.txt" "$tmp/robots.orig"
touched=(.htaccess plugins/themes/.htaccess _errors public/worj-harness-upload.php public/worj-harness.sql.bak)
cleanup() {
  [ ! -f "$tmp/apache.pid" ] || kill "$(cat "$tmp/apache.pid")" 2>/dev/null
  cp "$tmp/config.orig" "$cfg"; cp "$tmp/robots.orig" "$core/robots.txt"
  for f in "${touched[@]}"; do rm -rf -- "${core:?}/$f"; done
  rm -f -- "$files_dir/worj-harness-private.txt"
  rm -rf -- "${tmp:?}"
}
trap cleanup EXIT
curl -s -o /dev/null -m 5 --noproxy '*' "http://127.0.0.1:8082/worj/" || { echo "sandbox not running (make sandbox-up sandbox-seed)"; exit 2; }
for p in 80 443; do ss -ltn | grep -q ":$p " && { echo "port $p is busy; stop what listens there"; exit 2; }; done
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
eq() { [ "$1" = "$2" ]; }
has() { grep -qiF -- "$2" <<<"$1"; }
lacks() { ! grep -qiF -- "$2" <<<"$1"; }
lacksline() { ! grep -qxF -- "$2" <<<"$1"; }

H=journal.example.org
sed -i -E "s#^base_url = .*#base_url = \"https://$H\"#; s#^allowed_hosts = .*#allowed_hosts = '[\"$H\",\"127.0.0.1\"]'#" "$cfg"

install_web() { # robots mode
  printf 'HOST=%s\nHSTS_MAX_AGE=300\nROBOTS_MODE=%s\n' "$H" "$1" | "$root/scripts/render-htaccess.sh" "$core" >/dev/null || return 1
}
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -days 1 \
  -subj "/CN=$H" -addext "subjectAltName=DNS:$H,DNS:www.$H" >/dev/null 2>&1
mkdir -p "$tmp/run" "$tmp/log"
cat >"$tmp/apache.conf" <<CFG
ServerRoot "$tmp"
PidFile "$tmp/apache.pid"
ErrorLog "$tmp/log/error.log"
LogLevel warn
Listen 127.0.0.1:80
Listen 127.0.0.1:443
$(for m in mpm_event authz_core dir mime alias rewrite headers expires setenvif autoindex proxy proxy_fcgi ssl socache_shmcb env; do echo "LoadModule ${m}_module /usr/lib/apache2/modules/mod_${m}.so"; done)
User www-data
Group www-data
TypesConfig /etc/mime.types
DocumentRoot "$core"
ServerName $H
<Directory "/">
    AllowOverride None
    Require all denied
</Directory>
<Directory "$core">
    AllowOverride All
    Options FollowSymLinks
    Require all granted
</Directory>
<FilesMatch "\.php\$">
    SetHandler "proxy:unix:$SOCK|fcgi://localhost"
</FilesMatch>
<VirtualHost 127.0.0.1:80>
</VirtualHost>
<VirtualHost 127.0.0.1:443>
    SSLEngine on
    SSLCertificateFile "$tmp/cert.pem"
    SSLCertificateKeyFile "$tmp/key.pem"
</VirtualHost>
CFG
chmod 755 "$tmp"
start_apache() {
  [ ! -f "$tmp/apache.pid" ] || { kill "$(cat "$tmp/apache.pid")" 2>/dev/null; sleep 1; }
  apache2 -f "$tmp/apache.conf" || return 1
  for _ in $(seq 40); do [ -f "$tmp/apache.pid" ] && curl -sk --noproxy '*' -o /dev/null --resolve "$H:443:127.0.0.1" "https://$H/robots.txt" && return 0; sleep 0.25; done
  return 1
}
install_web production || { echo "render failed"; exit 2; }
start_apache || { echo "apache did not start"; cat "$tmp/log/error.log"; exit 2; }

cu() { curl -sk --noproxy "*" --resolve "$H:443:127.0.0.1" --resolve "www.$H:443:127.0.0.1" --resolve "$H:80:127.0.0.1" --resolve "www.$H:80:127.0.0.1" -m 30 "$@"; }
S="https://$H"
status() { cu -o /dev/null -w '%{http_code}' "$@"; }
loc() { cu -o /dev/null -D - "$@" | tr -d '\r' | sed -n 's/^[Ll]ocation: //p'; }
hdr() { cu -o /dev/null -D - "$@" | tr -d '\r'; }

echo "=== redirects (one canonical form per URL)"
yes "http -> 301" eq "$(status "http://$H/worj/about?x=1")" 301
yes "http://$H/worj/about?x=1 -> https, query kept" eq "$(loc "http://$H/worj/about?x=1")" "https://$H/worj/about?x=1"
yes "http://www... -> https main host" eq "$(loc "http://www.$H/worj/about")" "https://$H/worj/about"
yes "https://www... -> main host" eq "$(loc "https://www.$H/worj/about")" "https://$H/worj/about"
yes "GET /index.php/worj/about -> /worj/about" eq "$(loc "$S/index.php/worj/about")" "https://$H/worj/about"
yes "GET /index.php/worj/about?x=1 keeps the query" eq "$(loc "$S/index.php/worj/about?x=1")" "https://$H/worj/about?x=1"
yes "GET /index.php -> /" eq "$(loc "$S/index.php")" "https://$H/"
yes "HEAD /index.php/worj/about -> 301" eq "$(cu -I -o /dev/null -w '%{http_code}' "$S/index.php/worj/about")" 301
post_status="$(status -X POST -d 'username=a&password=b' "$S/index.php/worj/login/signIn")"
yes "POST to an index.php URL is NOT redirected (got $post_status)" test "$post_status" != 301 -a "$post_status" != 404
post2="$(status -X POST -d 'username=a&password=b' "$S/worj/login/signIn")"
yes "POST to the clean URL reaches OJS (got $post2)" test "$post2" != 301 -a "$post2" != 404
yes "the clean home page is served (200)" eq "$(status "$S/worj/")" 200
yes "an article page is served (200)" eq "$(status "$S/worj/article/view/1")" 200
yes "the site root / is served (200 or an OJS redirect, got $(status "$S/"))" test "$(status "$S/")" != 404 -a "$(status "$S/")" != 500

echo "=== files that must never be served"
printf 'secret-backup' >"$core/public/worj-harness.sql.bak"
for p in /config.inc.php /config.TEMPLATE.inc.php /.git/config /.env /.htaccess /tools/install.php /lib/pkp/tools/appKey.php \
         /cache/ /registry/emailTemplates.xml /classes/ /locale/en/common.po /public/worj-harness.sql.bak /composer.json /index.php.bak; do
  st="$(status --path-as-is "$S$p")"
  yes "GET $p -> 404 (got $st)" eq "$st" 404
done
printf '<?php echo "EXECUTED"; ?>' >"$core/public/worj-harness-upload.php"
body="$(cu "$S/public/worj-harness-upload.php")"; st="$(status "$S/public/worj-harness-upload.php")"
yes "an uploaded .php in public/ is not executed (status $st)" eq "$st" 404
yes "...and its code is not shown either" bash -c "! grep -qE 'EXECUTED|<\\?php' <<<'$body'"
yes "...also with path info (public/x.php/y)" eq "$(status "$S/public/worj-harness-upload.php/y")" 404
for ext in php5 phtml phar; do
  printf '<?php echo "EXECUTED"; ?>' >"$core/public/worj-harness-upload.$ext"
  yes "an uploaded .$ext in public/ is a 404 (got $(status "$S/public/worj-harness-upload.$ext"))" eq "$(status "$S/public/worj-harness-upload.$ext")" 404
  rm -f "$core/public/worj-harness-upload.$ext"
done
yes "/lib/pkp/lib/vendor assets for the admin UI are not denied as a directory (tinymce reachable)" test "$(status "$S/lib/pkp/lib/vendor/tinymce/tinymce/tinymce.min.js")" = 200
mkdir -p "$files_dir"; printf 'private submission' >"$files_dir/worj-harness-private.txt"
yes "files_dir content is not reachable by URL" eq "$(status "$S/worj-harness-private.txt")" 404
yes "...nor through traversal" test "$(status --path-as-is "$S/../../../..$files_dir/worj-harness-private.txt")" != 200
yes "a directory is never listed (/public/ gives no index of files)" lacks "$(cu "$S/public/")" "Index of"
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
for h in "Strict-Transport-Security: max-age=300" "X-Content-Type-Options: nosniff"; do yes "static file has $h" has "$css_h" "$h"; done
yes "THEME files are cached for one hour only" has "$css_h" "max-age=3600"
yes "OJS core static files are cached for 7 days" has "$(hdr "$S/lib/pkp/styles/fontawesome/fontawesome.css")" "max-age=604800"
yes "theme images are also one hour" has "$(hdr "$S/plugins/themes/worj/assets/img/logo-header.jpg")" "max-age=3600"
yes "the HTML page has no 7-day Cache-Control" lacks "$(grep -i '^cache-control:' <<<"$home_h")" "max-age=604800"
yes "public page sends CSP Report-Only" has "$home_h" "Content-Security-Policy-Report-Only:"
yes "public page never sends an ENFORCING CSP" bash -c "! grep -qiE '^Content-Security-Policy:' <<<'$home_h'"
yes "backend path (management) sends no CSP" lacks "$(hdr "$S/worj/management/settings/website")" "Content-Security-Policy"
yes "API path sends no CSP" lacks "$(hdr "$S/worj/api/v1/submissions")" "Content-Security-Policy"
yes "a \$\$\$call\$\$\$ grid request sends no CSP" lacks "$(hdr "$S/worj/\$\$\$call\$\$\$/grid/x")" "Content-Security-Policy"
yes "headers are present on a 404 too" has "$(hdr "$S/worj/no-such-page")" "X-Content-Type-Options: nosniff"

echo "=== 404 pages (shared hosting: only server-generated 404s get the static page)"
yes "a denied path shows the static accessible page (lang)" has "$(cu "$S/config.inc.php")" '<html lang="en">'
yes "...title" has "$(cu "$S/config.inc.php")" "<title>Page not found"
yes "...its stylesheet is served" eq "$(status "$S/_errors/404.css")" 200
nf_status="$(status "$S/worj/this-page-does-not-exist")"
yes "an unknown OJS route keeps status 404 (got $nf_status; OJS prints its own body, a known difference from the Nginx design)" eq "$nf_status" 404
api_h="$(hdr "$S/worj/api/v1/nonexistent")"
yes "API 404 is still JSON" has "$api_h" "application/json"

echo "=== discovery: production robots.txt, sitemap and OAI-PMH"
rb_h="$(hdr "$S/robots.txt")"; rb_body="$(cu "$S/robots.txt")"
yes "robots.txt is served (200, text/plain)" has "$rb_h" "content-type: text/plain"
yes "production robots.txt names the sitemap index" has "$rb_body" "Sitemap: https://$H/index/sitemap"
yes "production robots.txt does not close the site" lacksline "$rb_body" "Disallow: /"
yes "production sends no X-Robots-Tag" lacks "$home_h" "x-robots-tag"
for u in "/robots.txt" "/index/sitemap" "/worj/sitemap" "/worj/oai?verb=Identify"; do
  yes "http://$u -> 301 to https://$H$u" eq "$(loc "http://$H$u")" "https://$H$u"
done
yes "GET /index.php/worj/oai?verb=Identify -> clean URL, query kept" eq "$(loc "$S/index.php/worj/oai?verb=Identify")" "https://$H/worj/oai?verb=Identify"
yes "OAI Identify answers 200 XML" has "$(hdr "$S/worj/oai?verb=Identify")" "xml"
oai_post="$(status -X POST -d 'verb=Identify' "$S/worj/oai")"
yes "a POST to the clean OAI URL answers 200 (got $oai_post)" eq "$oai_post" 200
CD=("$root/scripts/check-discovery.sh" --curl-arg -k --curl-arg --noproxy --curl-arg '*' --curl-arg --resolve --curl-arg "$H:443:127.0.0.1")
"${CD[@]}" --robots-mode production "$S" >"$tmp/cd-prod.txt" 2>&1; cd_rc=$?
yes "check-discovery in production mode passes (exit $cd_rc)" eq "$cd_rc" 0
[ "$cd_rc" = 0 ] || sed 's/^/      /' "$tmp/cd-prod.txt"
"${CD[@]}" --robots-mode staging "$S" >/dev/null 2>&1; cd_rc=$?
yes "check-discovery in STAGING mode fails on the open render (exit $cd_rc)" eq "$cd_rc" 1

echo "=== closed render (ROBOTS_MODE=closed): robots.txt closes the site and noindex is sent"
install_web closed || bad "render closed"
yes "closed robots.txt is 'Disallow: /'" has "$(cu "$S/robots.txt")" "Disallow: /"
yes "closed robots.txt has no Sitemap line" lacks "$(cu "$S/robots.txt")" "Sitemap:"
yes "closed: X-Robots-Tag noindex on robots.txt" has "$(hdr "$S/robots.txt")" "X-Robots-Tag: noindex, nofollow"
yes "closed: X-Robots-Tag noindex on a page" has "$(hdr "$S/worj/")" "X-Robots-Tag: noindex, nofollow"
yes "closed: X-Robots-Tag noindex on a 404" has "$(hdr "$S/worj/no-such-page")" "X-Robots-Tag: noindex, nofollow"
python3 -I "$root/scripts/lib/discovery.py" robots-closed <(cu "$S/robots.txt"); yes "robotparser agrees: nothing may be fetched" eq "$?" 0
"${CD[@]}" --robots-mode staging "$S" >/dev/null 2>&1; cd_rc=$?
yes "check-discovery in staging (closed) mode passes on the closed render (exit $cd_rc)" eq "$cd_rc" 0

echo "=== login page works behind the rules"
yes "the login page has a username field" has "$(cu "$S/worj/login")" 'name="username"'

echo "=== mutation proof: remove each rule and the matching check must fail"
install_web production
mutate() { # name sed-delete-pattern probe...
  local name="$1" pat="$2" target="$core/.htaccess"; shift 2
  cp "$target" "$tmp/htaccess.good"
  [ -n "$pat" ] || rm -f "$core/plugins/themes/.htaccess"
  local one; local IFS=$'\n'
  for one in $pat; do
    grep -qF -- "$one" "$target" || { bad "mutation $name: pattern not found in .htaccess: $one"; return; }
    grep -vF -- "$one" "$target" >"$tmp/htaccess.mut"; cat "$tmp/htaccess.mut" >"$target"
  done
  if "$@"; then bad "mutation $name: the check still passes without the rule"; else ok "mutation $name: the check fails without the rule"; fi
  cp "$tmp/htaccess.good" "$target"
  install_web production
}
p_https() { test "$(loc "http://$H/worj/about")" = "https://$H/worj/about"; }
p_clean() { test "$(loc "$S/index.php/worj/about")" = "https://$H/worj/about"; }
p_dot() { test "$(status "$S/public/.worj-harness-dot")" = 404; }
p_noexec() { test "$(status "$S/public/worj-harness-upload.php")" = 404; }
p_noexec5() { printf '<?php echo 1;' >"$core/public/worj-harness-upload.phtml"; local r; r="$(status "$S/public/worj-harness-upload.phtml")"; rm -f "$core/public/worj-harness-upload.phtml"; test "$r" = 404; }
p_config() { test "$(status "$S/config.inc.php")" = 404; }
p_ext() { test "$(status "$S/public/worj-harness.sql.bak")" = 404; }
p_composer() { test "$(status "$S/public/composer.json")" = 404; }
p_dirs() { test "$(status "$S/registry/emailTemplates.xml")" = 404; }
p_libpkp() { test "$(status "$S/lib/pkp/registry/$libreg")" = 404; }
p_route() { test "$(status "$S/worj/")" = 200; }
p_hsts() { has "$(hdr "$S/worj/")" "Strict-Transport-Security"; }
p_nosniff() { has "$(hdr "$S/worj/")" "X-Content-Type-Options: nosniff"; }
p_csp() { has "$(hdr "$S/worj/")" "Content-Security-Policy-Report-Only"; }
p_csp_exempt() { lacks "$(hdr "$S/worj/management/settings/website")" "Content-Security-Policy"; }
p_csp_call() { lacks "$(hdr "$S/worj/\$\$\$call\$\$\$/grid/x")" "Content-Security-Policy"; }
p_expire7() { has "$(hdr "$S/lib/pkp/styles/fontawesome/fontawesome.css")" "max-age=604800"; }
p_theme1h() { has "$(hdr "$S$css")" "max-age=3600"; }
p_404page() { has "$(cu "$S/config.inc.php")" '<html lang="en">'; }
p_noindex_listing() { lacks "$(cu "$S/public/")" "Index of"; }
printf '<?php echo "EXECUTED"; ?>' >"$core/public/worj-harness-upload.php"
printf 'secret-backup' >"$core/public/worj-harness.sql.bak"
printf 'hidden' >"$core/public/.worj-harness-dot"; printf '{}' >"$core/public/composer.json"; touched+=(public/.worj-harness-dot public/composer.json)
libreg="$(find "$core/lib/pkp/registry" -maxdepth 1 -type f -name "*.txt" -printf "%f\n" | sort | sed -n 1p)"
mutate "https and canonical host" 'RewriteRule ^ https://' p_https
mutate "index.php to clean URL" 'RewriteRule ^index\.php(?:/(.*))?$' p_clean
mutate "dotfiles" 'RewriteRule (^|/)\.(?!well-known/)' p_dot
mutate "only index.php runs PHP" 'RewriteRule \.(php[0-9]?|phtml|pht|phar)' p_noexec
mutate "other PHP extensions" 'RewriteRule \.(php[0-9]?|phtml|pht|phar)' p_noexec5
# config.inc.php is also caught by the .php rule (two layers): both layers are removed together
mutate "config.inc.php (both layers)" 'config(\.TEMPLATE)?\.inc\.php
RewriteRule \.(php[0-9]?|phtml|pht|phar)' p_config
mutate "source-like extensions" '\.(tpl|inc|bak' p_ext
mutate "composer.json" '(composer\.json|composer\.lock' p_composer
mutate "code directories" 'RewriteRule ^(cache|tools|dbscripts' p_dirs
mutate "lib/pkp code directories" 'RewriteRule ^lib/pkp/(classes' p_libpkp
# shellcheck disable=SC2016  # the pattern is literal text, not an expansion
mutate "OJS clean-URL routing" 'RewriteRule ^(.*)$ index.php/$1' p_route
mutate "HSTS" 'Strict-Transport-Security' p_hsts
mutate "nosniff" 'X-Content-Type-Options' p_nosniff
mutate "CSP report-only" 'Header always set Content-Security-Policy-Report-Only' p_csp
mutate "CSP exemption for backend paths" 'management|workflow' p_csp_exempt
mutate "CSP exemption for \$\$\$call\$\$\$" 'call\$\$\$" NO_CSP' p_csp_call
mutate "7-day cache" 'ExpiresDefault "access plus 7 days"' p_expire7
mutate "theme one-hour cache" "" p_theme1h
mutate "static 404 page" 'ErrorDocument 404' p_404page

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "$fail FAILED"; fi
exit "$fail"
