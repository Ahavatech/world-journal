#!/usr/bin/env bash
# Test the Day-0 kit and scripts/probe-day0-kit.sh against a STAND-IN Apache (not LiteSpeed) in this sandbox.
#   scripts/test-day0-kit.sh        needs root, apache2 (apt-get install apache2) and php-fpm8.3 (the sandbox has it)
# What this proves: the kit files are valid Apache-style rules, and the probe tells a working host from a broken one:
# with every folder intact the probe passes; with one folder's .htaccess removed, the probe FAILS for exactly that feature.
# What it does NOT prove: that LiteSpeed on the real host behaves the same. That is what the probe is for, on staging.
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[@]}")/.." && pwd)"
[ "$(id -u)" = 0 ] || { echo "run as root (sandbox container)"; exit 2; }
command -v apache2 >/dev/null || { echo "missing apache2 (apt-get install -y apache2)"; exit 2; }
SOCK="${PHP_SOCK:-/run/php/php8.3-fpm.sock}"
if [ ! -S "$SOCK" ] || ! pgrep -x php-fpm8.3 >/dev/null; then php-fpm8.3 --daemonize 2>/dev/null; sleep 1; fi
[ -S "$SOCK" ] || { echo "no php-fpm socket at $SOCK"; exit 2; }
port=18090
tmp="$(mktemp -d)"
chmod 755 "$tmp"
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
cleanup() {
  [ ! -f "$tmp/apache.pid" ] || kill "$(cat "$tmp/apache.pid")" 2>/dev/null
  sleep 0.5
  rm -rf -- "${tmp:?}"
}
trap cleanup EXIT
web="$tmp/site/domain/public_html"   # two levels of parents above the web root, like /home/uXXX/domains/DOMAIN/public_html
mkdir -p "$web" "$tmp/run"
chmod 755 "$tmp/site" "$tmp/site/domain" "$web" "$tmp/run"
cat >"$tmp/apache2.conf" <<CFG
ServerRoot "$tmp"
ServerName localhost
Listen 127.0.0.1:$port
PidFile "$tmp/apache.pid"
DefaultRuntimeDir "$tmp/run"
ErrorLog "$tmp/error.log"
LogLevel warn
User www-data
Group www-data
$(for m in mpm_event authz_core dir mime alias rewrite headers expires setenvif autoindex proxy proxy_fcgi; do echo "LoadModule ${m}_module /usr/lib/apache2/modules/mod_${m}.so"; done)
TypesConfig /etc/mime.types
DocumentRoot "$web"
DirectoryIndex index.html
<Directory "$web">
    AllowOverride All
    Options +FollowSymLinks +Indexes
    Require all granted
</Directory>
<FilesMatch "\.php\$">
    SetHandler "proxy:unix:$SOCK|fcgi://localhost"
</FilesMatch>
CFG
apache2 -t -f "$tmp/apache2.conf" >"$tmp/syntax.txt" 2>&1 || { echo "apache config did not parse:"; cat "$tmp/syntax.txt"; exit 2; }
install_kit() { rm -rf "$web/worj-day0"; cp -r "$root/infra/shared-hosting/day0-kit/worj-day0" "$web/worj-day0"; chmod -R a+rX "$web"; }
install_kit
apache2 -f "$tmp/apache2.conf" -k start >"$tmp/start.txt" 2>&1 || { echo "apache did not start:"; cat "$tmp/start.txt"; exit 2; }
for _ in $(seq 40); do [ -f "$tmp/apache.pid" ] && curl -s -o /dev/null --noproxy '*' "http://127.0.0.1:$port/" && break; sleep 0.25; done
probe() { "$root/scripts/probe-day0-kit.sh" --curl-arg --noproxy --curl-arg '*' "http://127.0.0.1:$port" 2>&1; }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
out=""; rc=0
out_has() { grep -qE -- "$1" <<<"$out"; }
out_lacks() { ! grep -qE -- "$1" <<<"$out"; }
fails_only_for() { ! grep '^FAIL' <<<"$out" | grep -qv "^FAIL  $1"; }
rc_is() { [ "$rc" = "$1" ]; }
rc_is_and_has() { [ "$rc" = "$1" ] && grep -qE -- "$2" <<<"$out"; }

echo "=== the intact kit on a host that honours everything"
chmod 777 "$tmp/site/domain"   # PHP (www-data) may write one level above the web root
out="$(probe)"; rc=$?
yes "the probe passes (exit $rc)" rc_is 0
yes "...and says RESULT: PASS" out_has '^RESULT: PASS' 
for t in php/version php/extensions php/write-test t01-redirect t02-rewrite t03-deny-files t04-deny-dotfiles t05-deny-rewrite t06-headers t07-csp-exempt t08-errordoc t09-cache t10-methods t11-no-php-here t12-no-listing; do
  yes "$t reports OK" out_has "^OK    $t"
done
yes "the php_value test is information, and says it is refused (Apache without mod_php answers 500)" out_has '^INFO  t13-php-settings: php_value in .htaccess is REFUSED'
yes "a PHP-sent 404 keeps PHP's body (the design's assumption about the 404 page)" out_has 'INFO  t08-errordoc: .*keeps PHP'
yes "the probe never prints a home path with a real account id" out_lacks '/home/u[0-9]' 

echo "=== no folder above the web root is writable"
chmod 755 "$tmp/site/domain"
out="$(probe)"; rc=$?
yes "the probe FAILS (exit $rc)" rc_is 1
yes "...and names the write test" out_has '^FAIL  php/write-test' 
chmod 777 "$tmp/site/domain"

echo "=== break one folder at a time: the probe must FAIL for exactly that feature"
for t in t01-redirect t02-rewrite t03-deny-files t04-deny-dotfiles t05-deny-rewrite t06-headers t07-csp-exempt t08-errordoc t09-cache t10-methods t11-no-php-here t12-no-listing; do
  install_kit
  rm -f "$web/worj-day0/$t/.htaccess"
  out="$(probe)"; rc=$?
  yes "without $t/.htaccess the probe FAILS for $t (exit $rc)" rc_is_and_has 1 "^FAIL  $t"
  yes "...and every FAIL line is that folder's ($(grep -c '^FAIL' <<<"$out") FAIL lines)" fails_only_for "$t"
done
install_kit

echo "=== a kit that was not uploaded, and bad usage"
rm -rf "$web/worj-day0"
out="$(probe)"; rc=$?
yes "kit missing: FAIL with a clear message (exit $rc)" rc_is_and_has 1 'is the folder named exactly worj-day0' 
install_kit
"$root/scripts/probe-day0-kit.sh" >/dev/null 2>&1; yes "no BASE_URL is a usage error (exit 2)" test "$?" = 2
"$root/scripts/probe-day0-kit.sh" --curl-arg --noproxy --curl-arg '*' "http://127.0.0.1:1" >/dev/null 2>&1; yes "an unreachable site is exit 2" test "$?" = 2

echo
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "$fail FAILED"; fi
exit "$fail"
