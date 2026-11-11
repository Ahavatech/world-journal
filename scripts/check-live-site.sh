#!/usr/bin/env bash
# The HTTP checks for the .htaccess behaviour, run against a LIVE site (the shared host over https), the same matrix that
# scripts/test-htaccess-harness.sh runs against a stand-in Apache. A pass on the host is what shows LiteSpeed honours the rules.
#
#   scripts/check-live-site.sh --robots-mode closed|production [--journal worj] [--www-host HOST] [--curl-arg ARG]... https://HOST
#
# Prints OK / FAIL / WARN per check and `RESULT: PASS` or `RESULT: FAIL`. Exit 0 pass, 1 fail, 2 usage or unreachable.
# Read-only: GET, HEAD and one POST of a wrong login to a URL that must not be redirected. Sends no credentials.
# --curl-arg passes one argument to every curl call (for the tests: -k, --resolve, --noproxy).
set -uo pipefail
mode="" journal="worj" www="" cargs=() base=""
usage() { echo "usage: $0 --robots-mode closed|production [--journal PATH] [--www-host HOST] [--curl-arg ARG]... https://HOST" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --robots-mode) mode="${2:-}"; shift 2 ;;
    --journal) journal="${2:-}"; shift 2 ;;
    --www-host) www="${2:-}"; shift 2 ;;
    --curl-arg) cargs+=("${2:-}"); shift 2 ;;
    -*) usage ;;
    *) base="$1"; shift ;;
  esac
done
case "$mode" in closed | production) ;; *) usage ;; esac
[[ "$base" =~ ^https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || usage
host="${base#https://}"; [ -n "$www" ] || www="www.$host"
cu() { curl -s --max-time 30 "${cargs[@]}" "$@"; }
status() { cu -o /dev/null -w '%{http_code}' "$@"; }
loc() { cu -o /dev/null -D - "$@" | tr -d '\r' | sed -n 's/^[Ll]ocation: //p' | sed -n 1p; }
hdr() { cu -o /dev/null -D - "$@" | tr -d '\r'; }
fail=0
ok() { echo "OK    $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
warn() { echo "WARN  $1"; }
eq() { local n="$1" got="$2" want="$3"; if [ "$got" = "$want" ]; then ok "$n"; else bad "$n (got '$got', want '$want')"; fi; }
has() { local n="$1" text="$2" needle="$3"; if grep -qiF -- "$needle" <<<"$text"; then ok "$n"; else bad "$n (missing: $needle)"; fi; }
lacks() { local n="$1" text="$2" needle="$3"; if grep -qiF -- "$needle" <<<"$text"; then bad "$n (found: $needle)"; else ok "$n"; fi; }

home_status="$(status "$base/$journal/")"
[ "$home_status" != "000" ] || { echo "FAIL  cannot reach $base"; exit 2; }
eq "journal home page answers 200" "$home_status" 200

# redirects
eq "http -> https, same path and query" "$(loc "http://$host/$journal/about?x=1")" "https://$host/$journal/about?x=1"
w="$(loc "https://$www/$journal/about")"
if [ -z "$w" ] && [ "$(status "https://$www/")" = 000 ]; then warn "$www does not answer (DNS record for www missing?)"; else eq "www redirects to the main host" "$w" "https://$host/$journal/about"; fi
eq "/index.php/$journal/about -> clean URL" "$(loc "$base/index.php/$journal/about")" "https://$host/$journal/about"
eq "/index.php/$journal/about?x=1 keeps the query" "$(loc "$base/index.php/$journal/about?x=1")" "https://$host/$journal/about?x=1"
post="$(status -X POST -d 'username=check&password=check' "$base/index.php/$journal/login/signIn")"
if [ "$post" != 301 ] && [ "$post" != 404 ] && [ "$post" != 000 ]; then ok "a POST to an index.php URL is not redirected (got $post)"; else bad "a POST to an index.php URL is redirected or refused (got $post)"; fi

# files that must never be served
# 404 is what our rules answer; 403 is the host's own firewall refusing first (seen on Hostinger for /config.inc.php, /.git/config and
# /.htaccess). Both mean the file is not served.
for p in /config.inc.php /config.TEMPLATE.inc.php /.git/config /.htaccess /tools/install.php /lib/pkp/tools/appKey.php /cache/ /registry/emailTemplates.xml /classes/ /locale/en/common.po /composer.json; do
  code="$(status --path-as-is "$base$p")"
  if [ "$code" = 404 ] || [ "$code" = 403 ]; then ok "GET $p is refused ($code)"; else bad "GET $p is served or broken (got '$code', want 404 or 403)"; fi
done
lacks "a directory is never listed (/public/)" "$(cu "$base/public/")" "Index of"
eq "the Day-0 kit is gone (/worj-day0/probe.php)" "$(status "$base/worj-day0/probe.php")" 404

# headers
h="$(hdr "$base/$journal/")"
for x in "Strict-Transport-Security: max-age=" "X-Content-Type-Options: nosniff" "X-Frame-Options: SAMEORIGIN" "Referrer-Policy: strict-origin-when-cross-origin" "Permissions-Policy:" "Content-Security-Policy-Report-Only:"; do has "home page sends $x" "$h" "$x"; done
# the host itself adds `Content-Security-Policy: upgrade-insecure-requests` (harmless: it only upgrades http links); anything else enforcing is a failure
if grep -iE '^Content-Security-Policy:' <<<"$h" | grep -viE '^Content-Security-Policy:[[:space:]]*upgrade-insecure-requests[[:space:]]*;?[[:space:]]*$' | grep -q .; then bad "home page sends an ENFORCING Content-Security-Policy"; else ok "home page sends no enforcing CSP (the host's upgrade-insecure-requests is allowed)"; fi
# Our report-only policy is meant to skip the backend and the API. LiteSpeed ignored that exemption on the real host (Day-0 t07), so there
# it is a WARN, not a failure: the policy is report-only, blocks nothing and nothing collects its reports.
for pth in "$journal/management/settings/website" "$journal/api/v1/submissions"; do
  if hdr "$base/$pth" | grep -qi '^Content-Security-Policy-Report-Only'; then warn "backend path /$pth sends the report-only CSP (LiteSpeed ignores the exemption; harmless)"; else ok "backend path /$pth sends no CSP"; fi
done
has "theme CSS is cached for one hour" "$(hdr "$base/plugins/themes/worj/assets/css/base.css")" "max-age=3600"
has "the static accessible 404 page answers a path our rules deny" "$(cu "$base/tools/install.php")" "<title>Page not found"

# robots mode
rb="$(cu "$base/robots.txt")"; rh="$(hdr "$base/robots.txt")"
if [ "$mode" = closed ]; then
  has "closed: robots.txt disallows everything" "$rb" "Disallow: /"
  has "closed: X-Robots-Tag noindex on robots.txt" "$rh" "X-Robots-Tag: noindex"
  has "closed: X-Robots-Tag noindex on the home page" "$h" "X-Robots-Tag: noindex"
else
  has "production: robots.txt names the sitemap index" "$rb" "Sitemap: https://$host/index/sitemap"
  if grep -qxF "Disallow: /" <<<"$rb"; then bad "production: robots.txt still closes the whole site"; else ok "production: robots.txt does not close the site"; fi
  lacks "production: no X-Robots-Tag on the home page" "$h" "x-robots-tag"
fi
if [ "$fail" = 0 ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL ($fail failed)"; exit 1; fi
