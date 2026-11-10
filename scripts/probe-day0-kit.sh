#!/usr/bin/env bash
# Probe the WORJ Day-0 kit uploaded to a site that is not yet public, and report what the host honours.
# Usage: scripts/probe-day0-kit.sh [--curl-arg ARG]... BASE_URL        BASE_URL = https://HOST (no path)
#   --curl-arg   extra curl argument (repeatable). For a password-protected site use a netrc file:
#                --curl-arg --netrc-file --curl-arg /path/to/netrc     NEVER put a password on the command line.
# Output: one line per check, `OK`, `FAIL`, `WARN` or `INFO`, then `RESULT`. Exit 0 no FAIL, 1 any FAIL, 2 usage or no connection.
# FAIL means the host does not honour something the deployment design relies on. This is information, not an error:
# the result is written into docs/DEPLOY-SHARED.md ("Day-0 results") and decides the next steps.
# Run it only before launch, then delete the kit. The kit lives at BASE_URL/worj-day0/ (infra/shared-hosting/day0-kit/worj-day0/).
set -uo pipefail
base=""; curl_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --curl-arg) curl_args+=("${2:-}"); shift 2 || true ;;
    -*) echo "ERROR: unknown option $1" >&2; sed -n '2,6p' "$0" >&2; exit 2 ;;
    *) base="${1%/}"; shift ;;
  esac
done
case "$base" in http://* | https://*) ;; *) echo "ERROR: BASE_URL must be an http(s) URL" >&2; sed -n '2,6p' "$0" >&2; exit 2 ;; esac
kit="$base/worj-day0"
tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp:?}"' EXIT
fails=0
ok() { echo "OK    $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }
warn() { echo "WARN  $1"; }
info() { echo "INFO  $1"; }

# req METHOD URL [curl args]: sets $code; headers in $tmp/h, body in $tmp/b. Redirects are NOT followed.
req() {
  local m="$1" u="$2"; shift 2
  local extra=(); [ "$m" = HEAD ] && extra=(-I)
  [ "$m" = POST ] && extra=(-X POST -d day0=1)
  : >"$tmp/b"; : >"$tmp/h"
  code="$(curl -sS -m 40 "${curl_args[@]+"${curl_args[@]}"}" "${extra[@]+"${extra[@]}"}" "$@" -D "$tmp/h" -o "$tmp/b" -w '%{http_code}' "$u" 2>/dev/null)" || code=000
}
hdr() { grep -i "^$1:" "$tmp/h" | tail -n1 | sed -E 's/^[^:]*:[[:space:]]*//; s/\r$//'; }
body_has() { grep -qF -- "$1" "$tmp/b"; }

# ---- probe: reachable, and the PHP facts
req GET "$kit/probe.php"
case "$code" in
  000) echo "ERROR: cannot connect to $base" >&2; exit 2 ;;
  401 | 403) fail "probe: cannot read $kit/probe.php: HTTP $code (a login is needed: use a netrc file; or the kit is not uploaded)"; echo "RESULT: FAIL ($fails)"; exit 1 ;;
  200) ;;
  *) fail "probe: $kit/probe.php answers HTTP $code (is the folder named exactly worj-day0 at the web root?)"; echo "RESULT: FAIL ($fails)"; exit 1 ;;
esac
cp "$tmp/b" "$tmp/probe.json"
if ! python3 -I - "$tmp/probe.json" <<'PY'
import json, re, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("FAIL  probe: probe.php did not return JSON (is PHP running there?): %s" % e); sys.exit(1)
need = "bcmath ctype curl dom fileinfo filter ftp gd hash intl json libxml mbstring openssl pcre phar session simplexml spl tokenizer xml xmlwriter zip zlib mysqli".split()
have = set(d["extensions"]); bad = 0
def out(level, msg):
    print("%-5s %s" % (level, msg))
v = tuple(int(x) for x in re.match(r"(\d+)\.(\d+)", d["php_version"]).groups())
if v >= (8, 2): out("OK", "php/version: PHP %s (OJS 3.5 needs 8.2 or newer; sandbox tests ran 8.3)" % d["php_version"])
else: out("FAIL", "php/version: PHP %s is older than 8.2" % d["php_version"]); bad += 1
miss = [e for e in need if e not in have]
if miss: out("FAIL", "php/extensions: PHP extensions missing: %s (list from the OJS README, plus mysqli)" % ", ".join(miss)); bad += 1
else: out("OK", "php/extensions: every extension on the OJS README list, and mysqli, is loaded (%d extensions in all)" % len(have))
out("INFO", "php/server: server software: %s | SAPI: %s | https seen by PHP: %s" % (d["server_software"], d["sapi"], d["https"]))
def mb(s):
    m = re.match(r"^\s*(-?\d+)\s*([KMG]?)", str(s).upper() or "0")
    if not m: return 0
    n = int(m.group(1)); return n * {"": 1, "K": 1 << 10, "M": 1 << 20, "G": 1 << 30}[m.group(2)] / (1 << 20)
i = d["ini"]
for k, floor in (("memory_limit", 256), ("upload_max_filesize", 64), ("post_max_size", 66)):
    val = i.get(k, ""); size = mb(val)
    if val == "-1" or size >= floor: out("OK", "php/limits: %s = %s (comfortable for OJS from %d M)" % (k, val, floor))
    else: out("WARN", "php/limits: %s = %s is below the %d M the VPS design used; raise it in the dashboard's PHP options" % (k, val, floor))
out("INFO", "php/misc: max_execution_time=%s max_input_time=%s max_file_uploads=%s allow_url_fopen=%s date.timezone=%s opcache.enable=%s" % tuple(i.get(k, "") for k in ("max_execution_time", "max_input_time", "max_file_uploads", "allow_url_fopen", "date.timezone", "opcache.enable")))
out("INFO", "php/open_basedir: open_basedir = %s" % (i.get("open_basedir") or "(not set)"))
df = i.get("disable_functions") or "(none)"
out("INFO", "php/disable_functions: disable_functions = %s" % (df if len(df) < 220 else df[:220] + " ..."))
w = d["write_test_above_web_root"]; wr = [x for x in w if x["writable"]]
if wr: out("OK", "php/write-test: PHP can write %d level(s) above the web root, so a files folder can live there: %s" % (wr[0]["levels_above_web_root"], wr[0]["path"]))
else: out("FAIL", "php/write-test: PHP cannot write 1 or 2 levels above the web root (%s): the private files folder has nowhere to go" % w[0]["path"]); bad += 1
out("INFO", "php/webroot: web root as PHP sees it: %s | proxy headers present: %s" % (d["document_root"], json.dumps(d["proxy_headers_present"])))
sys.exit(1 if bad else 0)
PY
then fails=$((fails + 1)); fi

# ---- t01-redirect: 301 redirect
req GET "$kit/t01-redirect/go"
if [ "$code" = 301 ] && hdr location | grep -q 'landing.txt$'; then ok "t01-redirect: RewriteRule with [R=301,L] redirects ($(hdr location))"; else fail "t01-redirect: 301 redirect did not work (HTTP $code, Location: $(hdr location))"; fi

# ---- rewrite non-files to index.php (OJS clean URLs)
req GET "$kit/t02-rewrite/pretty/path/here"
if [ "$code" = 200 ] && body_has DAY0-REWRITE-OK && body_has 'pretty/path/here'; then ok "t02-rewrite: rewrite of a non-file to index.php works"; else fail "t02-rewrite: rewrite to index.php failed (HTTP $code)"; fi
req GET "$kit/t02-rewrite/real.txt"
if [ "$code" = 200 ] && body_has DAY0-REAL-FILE; then ok "t02-rewrite: an existing file is still served directly"; else fail "t02-rewrite: an existing file was not served (HTTP $code)"; fi

# ---- deny rules
req GET "$kit/t03-deny-files/a.secret"
if { [ "$code" = 403 ] || [ "$code" = 404 ]; } && ! body_has DAY0-SHOULD-NOT-BE-SERVED; then ok "t03-deny-files: <FilesMatch> with Require all denied blocks a file (HTTP $code)"; else fail "t03-deny-files: the denied file was served or the answer was HTTP $code"; fi
req GET "$kit/t04-deny-dotfiles/.hidden-test"
if { [ "$code" = 403 ] || [ "$code" = 404 ]; } && ! body_has DAY0-SHOULD-NOT-BE-SERVED; then ok "t04-deny-dotfiles: a dotfile is blocked (HTTP $code)"; else fail "t04-deny-dotfiles: the dotfile was served or the answer was HTTP $code"; fi
req GET "$kit/t05-deny-rewrite/blocked/x"
if [ "$code" = 403 ]; then ok "t05-deny-rewrite: RewriteRule [F] gives 403"; else fail "t05-deny-rewrite: RewriteRule [F] answered HTTP $code, not 403"; fi
req GET "$kit/t05-deny-rewrite/gone"
if [ "$code" = 404 ]; then ok "t05-deny-rewrite: RewriteRule [R=404] gives 404"; else fail "t05-deny-rewrite: RewriteRule [R=404] answered HTTP $code, not 404"; fi

# ---- headers
req GET "$kit/t06-headers/page.txt"
good=1
[ "$(hdr x-day0-test)" = ok ] || good=0
hdr strict-transport-security | grep -q 'max-age=300' || good=0
hdr content-security-policy-report-only | grep -qF "default-src 'self'" || good=0
if [ "$good" = 1 ]; then ok "t06-headers: Header always set works for a normal response (HSTS and a quoted CSP value intact)"; else fail "t06-headers: Header always set did not produce the expected headers (HTTP $code)"; fi
req GET "$kit/t06-headers/does-not-exist"
if [ "$code" = 404 ] && [ "$(hdr x-day0-test)" = ok ]; then ok "t06-headers: 'Header always set' also applies to a 404 response"; else fail "t06-headers: the header is missing on the 404 response (HTTP $code)"; fi
req GET "$kit/t07-csp-exempt/page.txt"; a="$(hdr content-security-policy-report-only)"
req GET "$kit/t07-csp-exempt/admin/page.txt"; b="$(hdr content-security-policy-report-only)"
if [ -n "$a" ] && [ -z "$b" ]; then ok "t07-csp-exempt: SetEnvIf with 'env=!VAR' exempts a path from a header"; else fail "t07-csp-exempt: conditional header failed (normal path has header: $([ -n "$a" ] && echo yes || echo no); admin path has header: $([ -n "$b" ] && echo yes || echo no))"; fi

# ---- ErrorDocument
req GET "$kit/t08-errordoc/no-such-file"
if [ "$code" = 404 ] && body_has DAY0-ERRORDOC; then ok "t08-errordoc: ErrorDocument shows a custom page, with status 404, for a server-generated error"; else fail "t08-errordoc: ErrorDocument did not work (HTTP $code)"; fi
req GET "$kit/t08-errordoc/php404.php"
if [ "$code" = 404 ] && body_has DAY0-PHP-OWN-404-BODY; then info "t08-errordoc: a 404 that PHP sends keeps PHP's own body (the static 404 page does NOT replace OJS's own 404, as the design assumes)";
elif [ "$code" = 404 ] && body_has DAY0-ERRORDOC; then info "t08-errordoc: ErrorDocument REPLACES a 404 that PHP sends (better than the design assumed: the accessible 404 page can cover OJS's own 404s)";
else warn "t08-errordoc: unexpected answer to a PHP-sent 404 (HTTP $code)"; fi

# ---- cache lifetimes
req GET "$kit/t09-cache/style.css"
if hdr cache-control | grep -q 'max-age=3600'; then ok "t09-cache: ExpiresByType gives CSS one hour ($(hdr cache-control))"; else fail "t09-cache: CSS did not get max-age=3600 (Cache-Control: $(hdr cache-control); Expires: $(hdr expires))"; fi
req GET "$kit/t09-cache/pixel.png"
if hdr cache-control | grep -q 'max-age=604800'; then ok "t09-cache: ExpiresByType gives a PNG one week"; else fail "t09-cache: PNG did not get max-age=604800 (Cache-Control: $(hdr cache-control))"; fi

# ---- GET and HEAD redirected, POST not
req GET "$kit/t10-methods/index.php/clean"
if [ "$code" = 301 ] && hdr location | grep -q '/worj-day0/t10-methods/clean$'; then ok "t10-methods: GET index.php/PATH redirects to /PATH (path-info reaches index.php)"; else fail "t10-methods: GET redirect failed (HTTP $code, Location: $(hdr location))"; fi
req HEAD "$kit/t10-methods/index.php/clean"
if [ "$code" = 301 ]; then ok "t10-methods: HEAD is redirected too"; else fail "t10-methods: HEAD answered HTTP $code, not 301"; fi
req POST "$kit/t10-methods/index.php/clean"
if [ "$code" = 200 ] && body_has DAY0-METHOD=POST; then ok "t10-methods: a POST is NOT redirected (forms and the admin API keep working)"; else fail "t10-methods: the POST was redirected or failed (HTTP $code)"; fi

# ---- no PHP where it must not run; no directory listing
req GET "$kit/t11-no-php-here/should-not-run.php"
if body_has DAY0-EXECUTED; then fail "t11-no-php-here: PHP EXECUTED in a folder where it must not (an uploaded .php would run)"; elif [ "$code" = 403 ] || [ "$code" = 404 ]; then ok "t11-no-php-here: a .php file is not executed in a protected folder (HTTP $code)"; else fail "t11-no-php-here: unexpected answer for the protected PHP file (HTTP $code)"; fi
req GET "$kit/t12-no-listing/listing/"
if ! { [ "$code" = 200 ] && body_has a.txt; }; then ok "t12-no-listing: 'Options -Indexes' prevents a directory listing (HTTP $code)"; else fail "t12-no-listing: the directory listing was shown"; fi

# ---- t13-php-settings: php_value in .htaccess (information only)
req GET "$kit/t13-php-settings/show.php"
if [ "$code" = 500 ]; then info "t13-php-settings: php_value in .htaccess is REFUSED here (HTTP 500): set PHP options in the dashboard instead";
elif [ "$code" = 200 ] && body_has memory_limit=123M; then info "t13-php-settings: php_value in .htaccess is honoured here";
elif [ "$code" = 200 ]; then info "t13-php-settings: php_value in .htaccess is accepted but ignored ($(head -n1 "$tmp/b"))";
else warn "t13-php-settings: unexpected answer (HTTP $code)"; fi

echo "INFO  Now DELETE the worj-day0 folder from the site, and write these results into docs/DEPLOY-SHARED.md."
if [ "$fails" -eq 0 ]; then echo "RESULT: PASS (no FAIL; read the INFO and WARN lines too)"; exit 0; fi
echo "RESULT: FAIL ($fails)"
exit 1
