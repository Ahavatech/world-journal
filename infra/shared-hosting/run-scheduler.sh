#!/usr/bin/env bash
# World Open Research Journal: run the OJS scheduler once. Called by a hPanel cron job (Advanced > Cron Jobs), because the
# dashboard rejects shell redirections and long commands, so the redirection and the housekeeping live in this file.
#
# Cron job (custom command), every 5 minutes if the dashboard allows it, else the shortest it allows (the interval must
# divide 60 and include minute 0: OJS runs a daily or monthly task only in its exact minute; hPanel cron is UTC):
#   /bin/bash /home/uXXXX/domains/worldopenresearchjournal.com/worj-ops/run-scheduler.sh
# Layout it expects (written by scripts/install-shared.sh):  REMOTE_ROOT/worj-ops/run-scheduler.sh, REMOTE_ROOT/public_html,
# REMOTE_ROOT/worj-logs/scheduler.log. PHP_BIN overrides the php program (default `php`; on some hosts the cron PATH needs
# the full path, which Day-0 shows). UNVERIFIED (not run on the host): whether the dashboard runs this, and how often.
#
# What it does: one run at a time (a second call while one is running exits 0 and logs "skipped"); logs start and end with
# the exit code, never any value from config.inc.php; keeps the log under about 1 MB (no logrotate on shared hosting).
set -uo pipefail
ops="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
base="$(dirname "$ops")"
webroot="${WORJ_WEBROOT:-$base/public_html}"
logdir="${WORJ_LOGDIR:-$base/worj-logs}"
php_bin="${PHP_BIN:-php}"
log="$logdir/scheduler.log"
max_bytes="${WORJ_LOG_MAX_BYTES:-1000000}"
mkdir -p "$logdir"
stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
exec 9>"$logdir/scheduler.lock"
if ! flock -n 9; then printf '%s skipped: the previous run is still going\n' "$(stamp)" >>"$log"; exit 0; fi
if [ -f "$log" ] && [ "$(stat -c %s "$log")" -gt "$max_bytes" ]; then
  tail -n 200 "$log" >"$log.tmp" && mv -f "$log.tmp" "$log"
fi
printf '%s start\n' "$(stamp)" >>"$log"
cd "$webroot" || { printf '%s FAILED: cannot enter %s\n' "$(stamp)" "$webroot" >>"$log"; exit 1; }
"$php_bin" lib/pkp/tools/scheduler.php run >>"$log" 2>&1
rc=$?
printf '%s end exit=%s\n' "$(stamp)" "$rc" >>"$log"
exit "$rc"
