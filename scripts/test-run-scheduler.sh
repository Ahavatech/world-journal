#!/usr/bin/env bash
# Tests for infra/shared-hosting/run-scheduler.sh with a stand-in php (no OJS needed).
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/infra/shared-hosting/run-scheduler.sh"
tmp="$(mktemp -d)"; trap 'rm -rf -- "${tmp:?}"' EXIT
fail=0; pass=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
no() { local name="$1"; shift; if "$@"; then bad "$name"; else ok "$name"; fi; }
base="$tmp/home/domains/journal.example.org"; mkdir -p "$base/worj-ops" "$base/public_html/lib/pkp/tools"
cp "$script" "$base/worj-ops/run-scheduler.sh"
cat >"$tmp/php" <<'PHP'
#!/usr/bin/env bash
printf 'cwd=%s args=%s\n' "$PWD" "$*" >>"${PHP_LOG:?}"
[ -z "${PHP_SLEEP:-}" ] || sleep "$PHP_SLEEP"
echo "scheduler output line"
exit "${PHP_RC:-0}"
PHP
chmod +x "$tmp/php"
run() { PHP_BIN="$tmp/php" PHP_LOG="$tmp/php.log" "$@" bash "$base/worj-ops/run-scheduler.sh"; }
log="$base/worj-logs/scheduler.log"

(cd / && run env); rc=$?
yes "a run exits 0 (exit $rc)" test "$rc" = 0
yes "php ran INSIDE the web root with 'lib/pkp/tools/scheduler.php run'" grep -qx "cwd=$base/public_html args=lib/pkp/tools/scheduler.php run" "$tmp/php.log"
yes "the log has a start line, the output and an end line with the exit code" bash -c "grep -q ' start$' '$log' && grep -q 'scheduler output line' '$log' && grep -q ' end exit=0$' '$log'"
(run env PHP_RC=3); rc=$?
yes "a failing scheduler: the exit code is passed on (exit $rc)" test "$rc" = 3
yes "...and logged" grep -q ' end exit=3$' "$log"

echo "=== one run at a time"
(run env PHP_SLEEP=3 &) ; sleep 1
(run env); rc=$?
yes "a second run while one is going exits 0 (exit $rc)" test "$rc" = 0
yes "...says it skipped" grep -q 'skipped: the previous run is still going' "$log"
yes "...and did not start php a second time" bash -c "[ \$(grep -c 'cwd=' '$tmp/php.log') -eq 3 ]"
sleep 3

echo "=== the log stays small"
head -c 3000 /dev/zero | tr '\0' 'x' >>"$log"; for i in $(seq 1 400); do echo "old line $i" >>"$log"; done
WORJ_LOG_MAX_BYTES=2000 run env >/dev/null
yes "a log over the limit is cut to its last lines" test "$(wc -l <"$log")" -le 210
yes "...and the newest lines are kept" grep -q ' end exit=0$' "$log"

echo "=== failures"
mv "$base/public_html" "$base/public_html.gone"
run env >/dev/null; rc=$?
yes "a missing web root fails with exit 1 and a log line (exit $rc)" test "$rc" = 1
yes "...logged" grep -q 'FAILED: cannot enter' "$log"
mv "$base/public_html.gone" "$base/public_html"

echo "=== mutation proof"
# shellcheck disable=SC2016  # literal script text
sed 's#tail -n 200 "$log" >"$log.tmp" \&\& mv -f "$log.tmp" "$log"#true#' "$script" >"$base/worj-ops/mut.sh"; chmod +x "$base/worj-ops/mut.sh"
head -c 3000 /dev/zero | tr '\0' 'x' >>"$log"
PHP_BIN="$tmp/php" PHP_LOG="$tmp/php.log" WORJ_LOG_MAX_BYTES=2000 bash "$base/worj-ops/mut.sh" >/dev/null
yes "mutation: without the truncation the log stays large" test "$(stat -c %s "$log")" -gt 2000
sed '/flock -n 9/d' "$script" >"$base/worj-ops/mut2.sh"
(PHP_BIN="$tmp/php" PHP_LOG="$tmp/php2.log" PHP_SLEEP=2 bash "$base/worj-ops/mut2.sh" >/dev/null &) ; sleep 0.5
PHP_BIN="$tmp/php" PHP_LOG="$tmp/php2.log" bash "$base/worj-ops/mut2.sh" >/dev/null; sleep 2
yes "mutation: without the lock two runs overlap" test "$(grep -c 'cwd=' "$tmp/php2.log")" = 2

echo "$pass PASS, $fail FAIL"
exit "$fail"
