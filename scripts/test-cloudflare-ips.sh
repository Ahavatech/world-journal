#!/usr/bin/env bash
# Tests for scripts/update-cloudflare-ips.sh against local FIXTURES (the live URL is blocked in this sandbox).
#   scripts/test-cloudflare-ips.sh        exit 0 only if every case passes
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fx="$root/scripts/fixtures/cloudflare"
U="$root/scripts/update-cloudflare-ips.sh"
tmp="$(mktemp -d)"
srv_pid=""
trap '[ -z "$srv_pid" ] || kill "$srv_pid" 2>/dev/null; rm -rf -- "${tmp:?}"' EXIT
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
eq() { [ "$1" = "$2" ]; }
run() { "$U" "$@" >"$tmp/out.txt" 2>"$tmp/err.txt"; echo $?; }
OUT="$tmp/realip.conf"
COMMON=(--out "$OUT" --test-cmd true --no-reload)

rc="$(run "${COMMON[@]}" --source "file://$fx/good")"
yes "valid lists are written (exit $rc)" eq "$rc" 0
yes "output says changed" grep -q '^changed (15 IPv4 and 7 IPv6 ranges)' "$tmp/out.txt"
yes "one set_real_ip_from line per range (22)" eq "$(grep -c '^set_real_ip_from ' "$OUT")" 22
yes "real_ip_header CF-Connecting-IP is set" grep -qx 'real_ip_header CF-Connecting-IP;' "$OUT"
yes "an IPv6 range is present" grep -qx 'set_real_ip_from 2606:4700::/32;' "$OUT"
cp "$OUT" "$tmp/good.snapshot"
sleep 1
rc="$(run "${COMMON[@]}" --source "file://$fx/good")"
yes "a second run says unchanged (exit $rc)" eq "$rc" 0
yes "...and the file is byte-identical" cmp -s "$OUT" "$tmp/good.snapshot"

keep_check() { # name fixture-dir expected-exit
  local rc; rc="$(run "${COMMON[@]}" --source "file://$fx/$2")"
  yes "$1 -> exit $3 (got $rc)" eq "$rc" "$3"
  yes "$1: the previous file is kept intact" cmp -s "$OUT" "$tmp/good.snapshot"
}
keep_check "empty lists" empty 1
keep_check "an HTML error page instead of ranges" html-error 1
keep_check "an invalid address" bad-cidr 1
keep_check "too few ranges" too-few 1
keep_check "a /0 range (would trust everyone)" zero-prefix 1
yes "the message for a /0 range says why" bash -c "grep -q 'trust the whole internet\\|too wide' '$tmp/err.txt' || grep -q 'rejected' '$tmp/err.txt'"
rc="$(run "${COMMON[@]}" --source "file://$tmp/does-not-exist")"
yes "an unreachable source -> exit 1 and the file is kept (exit $rc)" eq "$rc" 1
yes "...kept intact" cmp -s "$OUT" "$tmp/good.snapshot"

# HTTP errors from a local server
mkdir -p "$tmp/web404" "$tmp/web500"
cp "$fx/good/ips-v4" "$tmp/web404/"            # no ips-v6: the server answers 404
cat >"$tmp/srv.py" <<'PY'
import http.server, sys, os
port, root, code = int(sys.argv[1]), sys.argv[2], int(sys.argv[3])
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=root, **k)
    def do_GET(self):
        if code != 200: self.send_response(code); self.end_headers(); self.wfile.write(b"error"); return
        super().do_GET()
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
PY
python3 -I "$tmp/srv.py" 18999 "$tmp/web404" 200 & srv_pid=$!
sleep 1
rc="$(run "${COMMON[@]}" --source "http://127.0.0.1:18999")"
yes "HTTP 404 on one list -> exit 1 (got $rc), file kept" eq "$rc" 1
yes "...kept intact" cmp -s "$OUT" "$tmp/good.snapshot"
kill "$srv_pid"; wait "$srv_pid" 2>/dev/null
python3 -I "$tmp/srv.py" 18999 "$tmp/web500" 500 & srv_pid=$!
sleep 1
rc="$(run "${COMMON[@]}" --source "http://127.0.0.1:18999")"
yes "HTTP 500 -> exit 1 (got $rc), file kept" eq "$rc" 1
yes "...kept intact" cmp -s "$OUT" "$tmp/good.snapshot"
kill "$srv_pid"; wait "$srv_pid" 2>/dev/null; srv_pid=""

# source guard
rc="$(run "${COMMON[@]}" --source "http://example.com")"
yes "a plain-http remote source is refused (exit $rc)" eq "$rc" 2
rc="$(run "${COMMON[@]}" --source "ftp://example.com")"
yes "an ftp source is refused (exit $rc)" eq "$rc" 2

# first run with no file: the provision stage must fail loudly
NEW="$tmp/first/realip.conf"
rc="$(run --out "$NEW" --test-cmd true --no-reload --source "file://$fx/empty")"
yes "FIRST RUN with a failing fetch -> exit 3 (got $rc)" eq "$rc" 3
yes "...no file was created" test ! -e "$NEW"
yes "...the message explains the consequence (every visitor would look like Cloudflare)" grep -q 'every visitor as a Cloudflare address' "$tmp/err.txt"
rc="$(run --out "$NEW" --test-cmd true --no-reload --source "file://$fx/good")"
yes "FIRST RUN with a good fetch creates the file (exit $rc)" eq "$rc" 0

# nginx -t (test command) failure restores the previous state
cp "$fx/good/ips-v4" "$tmp/changed-v4"; mkdir -p "$tmp/alt"; { cat "$fx/good/ips-v4"; echo 198.51.100.0/24; } >"$tmp/alt/ips-v4"; cp "$fx/good/ips-v6" "$tmp/alt/"
rc="$(run --out "$OUT" --test-cmd false --no-reload --source "file://$tmp/alt")"
yes "a failing config test restores the previous file (exit $rc)" eq "$rc" 1
yes "...byte-identical to before" cmp -s "$OUT" "$tmp/good.snapshot"
rc="$(run --out "$tmp/never/realip.conf" --test-cmd false --no-reload --source "file://$fx/good")"
yes "a failing config test on the first run -> exit 3 and no file (exit $rc)" eq "$rc" 3
yes "...no file left behind" test ! -e "$tmp/never/realip.conf"

# reload only after a changed, tested file
rm -f "$tmp/reloaded"
rc="$(run --out "$OUT" --test-cmd true --reload-cmd "touch $tmp/reloaded" --source "file://$tmp/alt")"
yes "a changed file triggers the reload (exit $rc)" test -e "$tmp/reloaded"
rm -f "$tmp/reloaded"
rc="$(run --out "$OUT" --test-cmd true --reload-cmd "touch $tmp/reloaded" --source "file://$tmp/alt")"
yes "an unchanged file does not reload (exit $rc)" test ! -e "$tmp/reloaded"

# --check writes nothing
rm -f "$tmp/chk.conf"
rc="$(run --out "$tmp/chk.conf" --check --source "file://$fx/good")"
yes "--check writes nothing (exit $rc)" test ! -e "$tmp/chk.conf"

# the rendered file is accepted by nginx itself
if command -v nginx >/dev/null; then
  printf 'pid %s/n.pid;\nerror_log %s/n.log;\nevents {}\nhttp { include %s; }\n' "$tmp" "$tmp" "$OUT" >"$tmp/n.conf"
  yes "nginx -t accepts the generated real-IP file" bash -c "nginx -t -c '$tmp/n.conf' 2>&1 | grep -q 'test is successful'"
fi

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "$fail FAILED"; fi
exit "$fail"
