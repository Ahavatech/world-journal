#!/usr/bin/env bash
# Backup and restore round trip against the SANDBOX database, with age and an rclone local remote.
#   scripts/test-backup-restore.sh        needs root, the sandbox up (make sandbox-up sandbox-seed), age, rclone, mysqldump
# Nothing here touches a real server: UNVERIFIED (not run on VPS).
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$(id -u)" = 0 ] || { echo "run as root (sandbox container)"; exit 2; }
for t in age age-keygen rclone mysqldump mariadb php; do command -v "$t" >/dev/null || { echo "missing tool: $t (apt-get install -y age rclone)"; exit 2; }; done
set -a; . "$root/.env.sandbox"; set +a
tmp="$(mktemp -d)"; chmod 755 "$tmp"
sampler_pid=""
trap '[ -z "$sampler_pid" ] || kill "$sampler_pid" 2>/dev/null; rm -rf -- "${tmp:?}"' EXIT
B="$root/scripts/backup.sh"; R="$root/scripts/restore.sh"
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
no() { local name="$1"; shift; if "$@"; then bad "$name"; else ok "$name"; fi; }
eq() { [ "$1" = "$2" ]; }
sql() { mariadb -N -e "$1"; }

# ---- fixtures: keys, defaults files, settings
age-keygen -o "$tmp/id.txt" >/dev/null 2>&1
age-keygen -o "$tmp/other-id.txt" >/dev/null 2>&1
recipient="$(age-keygen -y "$tmp/id.txt")"
printf '[client]\nuser=%s\npassword=%s\nhost=localhost\n' "$SANDBOX_DB_USER" "$SANDBOX_DB_PASSWORD" >"$tmp/dump.cnf"; chmod 600 "$tmp/dump.cnf"
printf '[client]\nuser=root\nhost=localhost\n' >"$tmp/restore.cnf"; chmod 600 "$tmp/restore.cnf"
mkdir -p "$tmp/backups" "$tmp/remote"
write_env() { # file [extra lines...]
  local f="$1"; shift
  {
    echo "WORJ_DB_NAME=$SANDBOX_DB_NAME"
    echo "WORJ_DB_DEFAULTS=$tmp/dump.cnf"
    echo "WORJ_FILES_DIR=/var/www/worj-sandbox-files"
    echo "WORJ_PUBLIC_DIR=$root/ojs-core/public"
    echo "WORJ_CONFIG=$root/ojs-core/config.inc.php"
    echo "WORJ_BACKUP_DIR=$tmp/backups"
    echo "WORJ_AGE_RECIPIENT=$recipient"
    echo "WORJ_RCLONE_REMOTE=:local:$tmp/remote"
    echo "WORJ_ALERT_CMD='cat >>$tmp/alerts.txt'"
    echo "WORJ_MIN_TABLES=30"
    printf '%s\n' "$@"
  } >"$f"; chmod 600 "$f"
}
write_env "$tmp/backup.env"
users_before="$(sql "select count(*) from $SANDBOX_DB_NAME.users")"
config_sum="$(sha256sum "$root/ojs-core/config.inc.php" | cut -d' ' -f1)"

echo "=== backup.sh --check changes nothing"
out="$("$B" --env "$tmp/backup.env" --check 2>&1)"; rc=$?
yes "--check exits 0" eq "$rc" 0
yes "--check prints WOULD lines" grep -q '^WOULD: ' <<<"$out"
yes "--check created no backup" test ! -e "$tmp/backups/daily"
yes "--check printed no password" bash -c "! grep -qF '$SANDBOX_DB_PASSWORD' <<<'$out'"

echo "=== a real backup (weekly day, so the weekly copy is made too)"
( while :; do cat /proc/[0-9]*/cmdline 2>/dev/null | tr '\0' '\n'; done >"$tmp/cmdlines.txt" ) & sampler_pid=$!
"$B" --env "$tmp/backup.env" --now 2026-11-08T02:17:00Z >"$tmp/backup.log" 2>&1; rc=$?
kill "$sampler_pid" 2>/dev/null; wait "$sampler_pid" 2>/dev/null; sampler_pid=""
yes "backup succeeds (exit $rc)" eq "$rc" 0
bk="$tmp/backups/daily/worj-20261108T021700Z.tar.age"
yes "encrypted file exists in daily/" test -f "$bk"
yes "...mode 600" eq "$(stat -c '%a' "$bk")" 600
yes "...in a mode 700 directory" eq "$(stat -c '%a' "$tmp/backups/daily")" 700
yes "...is an age file" bash -c "head -c 22 '$bk' | grep -q 'age-encryption.org/v1'"
yes "...with a matching SHA-256 sidecar" bash -c "cd '$tmp/backups/daily' && sha256sum -c --quiet worj-20261108T021700Z.tar.age.sha256"
yes "Sunday: a weekly copy exists" test -f "$tmp/backups/weekly/worj-20261108T021700Z.tar.age"
yes "off-box copy exists (rclone local remote)" test -f "$tmp/remote/daily/worj-20261108T021700Z.tar.age"
yes "off-box weekly copy exists" test -f "$tmp/remote/weekly/worj-20261108T021700Z.tar.age"
yes "off-box copy is byte-identical to the local ciphertext" cmp -s "$bk" "$tmp/remote/daily/worj-20261108T021700Z.tar.age"
yes "last-success is written, no FAILED marker" bash -c "test -f '$tmp/backups/last-success' && test ! -e '$tmp/backups/FAILED'"
no "the work directory (plaintext) is gone" bash -c "ls -A '$tmp/backups' | grep -q '^.work'"
no "the server cannot decrypt it: age -d without the key fails" bash -c "age -d '$bk' >/dev/null 2>&1"
no "...nor with a different key" bash -c "age -d -i '$tmp/other-id.txt' '$bk' >/dev/null 2>&1"
no "the ciphertext holds no plaintext SQL" bash -c "grep -aq 'CREATE TABLE' '$bk'"
no "the ciphertext holds no database password" bash -c "grep -aqF '$SANDBOX_DB_PASSWORD' '$bk'"
no "the log holds no database password" grep -qF "$SANDBOX_DB_PASSWORD" "$tmp/backup.log"
no "no process command line held the database password during the run" grep -qF "$SANDBOX_DB_PASSWORD" "$tmp/cmdlines.txt"
yes "the sampler really saw the processes (mysqldump ran)" grep -q 'mysqldump\|mariadb-dump' "$tmp/cmdlines.txt"
no "no private key anywhere in the log or process list" bash -c "grep -q 'AGE-SECRET-KEY' '$tmp/backup.log' '$tmp/cmdlines.txt'"
echo "      log: $(grep -c . "$tmp/backup.log") lines; $(grep 'dump ok' "$tmp/backup.log" | sed 's/^[^ ]* //')"

echo "=== failures must alert and must not upload"
remote_count() { find "$tmp/remote" -type f | wc -l; }
local_count() { find "$tmp/backups/daily" -type f -name '*.tar.age' | wc -l; }
before_r="$(remote_count)"; before_l="$(local_count)"
mkdir -p "$tmp/stubs"
printf '#!/bin/sh\nexit 0\n' >"$tmp/stubs/empty.sh"
printf '#!/bin/sh\necho "-- Dump completed on 2026-11-09"\n' >"$tmp/stubs/tiny.sh"
printf '#!/bin/sh\nmysqldump "$@" | head -n -3\n' >"$tmp/stubs/truncated.sh"
printf '#!/bin/sh\necho boom >&2\nexit 2\n' >"$tmp/stubs/fails.sh"
chmod +x "$tmp/stubs/"*.sh
for kind in empty tiny truncated fails; do
  write_env "$tmp/fail.env" "WORJ_MYSQLDUMP=$tmp/stubs/$kind.sh"
  rm -f "$tmp/alerts.txt" "$tmp/backups/FAILED"
  "$B" --env "$tmp/fail.env" --now "2026-11-09T02:17:00Z" >"$tmp/fail.log" 2>&1; rc=$?
  yes "dump '$kind' -> backup fails (exit $rc)" test "$rc" != 0
  yes "...FAILED marker written" test -f "$tmp/backups/FAILED"
  yes "...alert command received a message" grep -q 'worj backup FAILED' "$tmp/alerts.txt"
  yes "...nothing new uploaded or stored" bash -c "[ '$(remote_count)' = '$before_r' ] && [ '$(local_count)' = '$before_l' ]"
done
echo "      example alert: $(head -c 140 "$tmp/alerts.txt")"
printf '%s\n' 99999999 >"$tmp/backups/last-size"
write_env "$tmp/shrink.env"; rm -f "$tmp/backups/FAILED"
"$B" --env "$tmp/shrink.env" --now "2026-11-09T02:17:00Z" >"$tmp/shrink.log" 2>&1; rc=$?
yes "a backup far smaller than the last one fails (exit $rc)" test "$rc" != 0
yes "...the message says why" grep -q 'under 20%' "$tmp/shrink.log"
wc -c <"$tmp/backups/daily/worj-20261108T021700Z.tar.age" >"$tmp/backups/last-size"; rm -f "$tmp/backups/FAILED"
echo "=== settings that must be refused"
write_env "$tmp/priv.env" "WORJ_AGE_RECIPIENT=$(grep AGE-SECRET-KEY "$tmp/id.txt")"
"$B" --env "$tmp/priv.env" --check >"$tmp/priv.log" 2>&1; rc=$?
yes "a PRIVATE age key in the settings is refused (exit $rc)" eq "$rc" 2
no "...and the key is not echoed" grep -q 'AGE-SECRET-KEY-' "$tmp/priv.log"
cp "$tmp/backup.env" "$tmp/ww.env"; chmod 666 "$tmp/ww.env"
"$B" --env "$tmp/ww.env" --check >/dev/null 2>&1; rc=$?
yes "a world-writable settings file is refused (exit $rc)" eq "$rc" 2
chmod 644 "$tmp/dump.cnf"
write_env "$tmp/b.env"; "$B" --env "$tmp/b.env" --now 2026-11-09T02:17:00Z >/dev/null 2>&1; rc=$?
yes "a database defaults file that is not mode 600 is refused (exit $rc)" test "$rc" != 0
chmod 600 "$tmp/dump.cnf"; rm -f "$tmp/backups/FAILED"

echo "=== retention (14 daily, 8 weekly) and remote pruning"
rd="$tmp/rot/daily"; rw="$tmp/rot/weekly"; mkdir -p "$rd" "$rw"
for i in $(seq 1 20); do d="$(printf '202610%02d' "$i")"; : >"$rd/worj-${d}T021700Z.tar.age"; : >"$rd/worj-${d}T021700Z.tar.age.sha256"; done
for i in $(seq 1 12); do d="$(printf '2026%02d01' "$i")"; : >"$rw/worj-${d}T021700Z.tar.age"; done
write_env "$tmp/rot.env" "WORJ_BACKUP_DIR=$tmp/rot"
"$B" --env "$tmp/rot.env" --rotate-only >/dev/null 2>&1
yes "daily keeps exactly 14" eq "$(find "$rd" -name '*.tar.age' | wc -l)" 14
yes "daily keeps the NEWEST (20261020 present, 20261006 gone, 20261007 present)" bash -c "test -f '$rd/worj-20261020T021700Z.tar.age' && test ! -e '$rd/worj-20261006T021700Z.tar.age' && test -f '$rd/worj-20261007T021700Z.tar.age'"
yes "sidecar of a rotated file is gone too" test ! -e "$rd/worj-20261001T021700Z.tar.age.sha256"
yes "weekly keeps exactly 8" eq "$(find "$rw" -name '*.tar.age' | wc -l)" 8
yes "weekly keeps the newest (20261201 present, 20260401 gone)" bash -c "test -f '$rw/worj-20261201T021700Z.tar.age' && test ! -e '$rw/worj-20260401T021700Z.tar.age'"
mkdir -p "$tmp/remote2/daily" "$tmp/remote2/weekly"
: >"$tmp/remote2/daily/worj-old.tar.age"; touch -d '20 days ago' "$tmp/remote2/daily/worj-old.tar.age"
: >"$tmp/remote2/daily/worj-new.tar.age"; touch -d '2 days ago' "$tmp/remote2/daily/worj-new.tar.age"
: >"$tmp/remote2/weekly/worj-old.tar.age"; touch -d '70 days ago' "$tmp/remote2/weekly/worj-old.tar.age"
: >"$tmp/remote2/weekly/worj-mid.tar.age"; touch -d '40 days ago' "$tmp/remote2/weekly/worj-mid.tar.age"
write_env "$tmp/prune.env" "WORJ_RCLONE_REMOTE=:local:$tmp/remote2"
"$B" --env "$tmp/prune.env" --prune-remote-only >/dev/null 2>&1
yes "remote daily older than 15 days deleted, newer kept" bash -c "test ! -e '$tmp/remote2/daily/worj-old.tar.age' && test -e '$tmp/remote2/daily/worj-new.tar.age'"
yes "remote weekly older than 57 days deleted, 40-day-old kept" bash -c "test ! -e '$tmp/remote2/weekly/worj-old.tar.age' && test -e '$tmp/remote2/weekly/worj-mid.tar.age'"

echo "=== restore rehearsal (operator, with the private key)"
live="$tmp/live.inc.php"
printf '[database]\nhost = localhost\nname = %s\n' "$SANDBOX_DB_NAME" >"$live"
scratch="worj_restore_test_$$"
code_before="$(find "$root/ojs-core" -maxdepth 1 -type f | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)"
"$R" --bundle "$bk" --identity "$tmp/id.txt" --code-dir "$root/ojs-core" --live-config "$live" --scratch-db "$scratch" --db-defaults "$tmp/restore.cnf" --port 18199 >"$tmp/restore.log" 2>&1; rc=$?
yes "restore rehearsal succeeds (exit $rc)" eq "$rc" 0
sed 's/^/      /' "$tmp/restore.log"
yes "login page loaded from the restored copy" grep -q 'login page .* returned 200' "$tmp/restore.log"
yes "scratch database was dropped" eq "$(sql "select count(*) from information_schema.schemata where schema_name='$scratch'")" 0
yes "the sandbox database was not touched (users: $users_before)" eq "$(sql "select count(*) from $SANDBOX_DB_NAME.users")" "$users_before"
yes "the original config.inc.php is unchanged" eq "$(sha256sum "$root/ojs-core/config.inc.php" | cut -d' ' -f1)" "$config_sum"
yes "the code tree's top-level files are unchanged" eq "$(find "$root/ojs-core" -maxdepth 1 -type f | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)" "$code_before"
no "the restore log holds no database password or private key" bash -c "grep -qE 'AGE-SECRET-KEY|$SANDBOX_DB_PASSWORD' '$tmp/restore.log'"
no "the throwaway web server is stopped (port 18199 closed)" bash -c "curl -s --noproxy '*' -m 2 http://127.0.0.1:18199/ >/dev/null"

"$R" --bundle "$bk" --identity "$tmp/other-id.txt" --code-dir "$root/ojs-core" --live-config "$live" --scratch-db "${scratch}_b" --db-defaults "$tmp/restore.cnf" >"$tmp/r2.log" 2>&1; rc=$?
yes "a WRONG private key fails to decrypt (exit $rc)" test "$rc" != 0
yes "...and no scratch database was left" eq "$(sql "select count(*) from information_schema.schemata where schema_name like 'worj_restore_test_%'")" 0
cp "$bk" "$tmp/corrupt.tar.age"; printf '\xff' | dd of="$tmp/corrupt.tar.age" bs=1 seek=400 conv=notrunc status=none
"$R" --bundle "$tmp/corrupt.tar.age" --identity "$tmp/id.txt" --code-dir "$root/ojs-core" --live-config "$live" --scratch-db "${scratch}_c" --db-defaults "$tmp/restore.cnf" >"$tmp/r3.log" 2>&1; rc=$?
yes "a corrupted bundle is rejected (exit $rc)" test "$rc" != 0

echo "=== restore.sh SAFETY GUARD: deliberate collisions"
"$R" --bundle "$bk" --identity "$tmp/id.txt" --code-dir "$root/ojs-core" --live-config "$live" --scratch-db "$SANDBOX_DB_NAME" --db-defaults "$tmp/restore.cnf" >"$tmp/g1.log" 2>&1; rc=$?
yes "scratch name = the production database name ($SANDBOX_DB_NAME) is REFUSED (exit $rc)" eq "$rc" 3
yes "...the message says so and nothing was touched" grep -q 'REFUSED' "$tmp/g1.log"
yes "...the production database still has its $users_before user(s)" eq "$(sql "select count(*) from $SANDBOX_DB_NAME.users")" "$users_before"
printf '[database]\nhost = localhost\nname = %s\n' "worj_restore_collide" >"$tmp/live2.inc.php"
"$R" --bundle "$bk" --identity "$tmp/id.txt" --code-dir "$root/ojs-core" --live-config "$tmp/live2.inc.php" --scratch-db "worj_restore_collide" --db-defaults "$tmp/restore.cnf" >"$tmp/g2.log" 2>&1; rc=$?
yes "production named like a scratch db: same name still REFUSED (exit $rc)" eq "$rc" 3
yes "...refused for the right reason (the names are EQUAL)" grep -q 'equals the production database name' "$tmp/g2.log"
yes "...and the first collision (the real sandbox name) was refused by the restore-name rule" grep -q 'must contain "restore"' "$tmp/g1.log"
"$R" --bundle "$bk" --identity "$tmp/id.txt" --code-dir "$root/ojs-core" --live-config "$live" --scratch-db "somename" --db-defaults "$tmp/restore.cnf" >"$tmp/g3.log" 2>&1; rc=$?
yes "a scratch name without \"restore\" is REFUSED (exit $rc)" eq "$rc" 3
"$R" --bundle "$bk" --identity "$tmp/id.txt" --code-dir "$root/ojs-core" --live-config "$tmp/does-not-exist" --scratch-db "$scratch" --db-defaults "$tmp/restore.cnf" >"$tmp/g4.log" 2>&1; rc=$?
yes "a missing live config is REFUSED (no way to compare) (exit $rc)" eq "$rc" 3
"$R" --bundle "$bk" --identity "$tmp/id.txt" --code-dir "$root/ojs-core" --live-config "$live" --scratch-db 'x";drop database y;--restore' --db-defaults "$tmp/restore.cnf" >"$tmp/g5.log" 2>&1; rc=$?
yes "a scratch name with SQL characters is REFUSED (exit $rc)" eq "$rc" 3
"$R" --bundle "$bk" --identity "$tmp/id.txt" --code-dir "$root/ojs-core" --live-config "$live" --scratch-db "$scratch" --db-defaults "$tmp/restore.cnf" --check >"$tmp/g6.log" 2>&1; rc=$?
yes "restore.sh --check runs only the guard (exit $rc)" eq "$rc" 0
yes "...and says WOULD, creating nothing" bash -c "grep -q '^WOULD: ' '$tmp/g6.log' && [ \"\$(mariadb -N -e \"select count(*) from information_schema.schemata where schema_name='$scratch'\")\" = 0 ]"

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "$fail FAILED"; fi
exit "$fail"
