#!/usr/bin/env bash
# Nightly backup of the journal: database dump + files_dir + public/ + config.inc.php, encrypted with age.
#
#   scripts/backup.sh [--env FILE] [--check] [--now ISO8601] [--rotate-only] [--prune-remote-only]
#
#   --env FILE            settings file, root-owned and not group/world-writable (default /etc/worj/backup.env)
#   --check               print what would be done; change nothing
#   --now ISO8601         pretend it is this UTC time (tests of naming and rotation)
#   --rotate-only         only apply the local retention (14 daily, 8 weekly by default)
#   --prune-remote-only   only delete remote objects older than the retention (rclone delete --min-age)
#
# What it guarantees:
#   * EVERYTHING that leaves the work directory is encrypted with age, including the local copy. The server holds ONLY
#     the public key (WORJ_AGE_RECIPIENT, age1...). A private key (AGE-SECRET-KEY-...) in the settings file is refused.
#     The server cannot decrypt its own backups: decryption and the restore rehearsal are done by the operator with the
#     private key (scripts/restore.sh, docs/DEPLOY.md).
#   * the database password never appears on a command line, in a log or in the environment: mysqldump reads it from
#     a root-only defaults file (--defaults-extra-file).
#   * sanity checks before anything is encrypted: the dump is valid gzip, ends with mysqldump's completion line, is large
#     enough, has enough CREATE TABLE statements, contains the users table with rows; the data archive and the config copy
#     exist; the new backup is not suspiciously smaller than the last successful one. An empty backup that "succeeds"
#     is the usual failure, so any failed check is a failure.
#   * ANY failure raises an alert: a FAILED marker in the backup directory, a syslog error, and WORJ_ALERT_CMD (the
#     message arrives on its standard input). Success writes last-success; an external heartbeat can watch that file.
#   * the upload is `rclone copy` (never `sync`) and is verified by listing the remote object and comparing its size;
#     remote pruning only deletes objects older than the retention. A compromised server can still delete remote
#     objects, so enable bucket versioning or object lock at the remote (strongly recommended, docs/DEPLOY.md).
# Plaintext lives only in a mode-700 work directory under the backup directory and is removed on exit.
set -euo pipefail
umask 077

env_file="/etc/worj/backup.env" check=0 now="" mode="full"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --env) env_file="${2:?}"; shift 2 ;;
    --check) check=1; shift ;;
    --now) now="${2:?}"; shift 2 ;;
    --rotate-only) mode="rotate"; shift ;;
    --prune-remote-only) mode="prune"; shift ;;
    -h | --help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -f "$env_file" ] || { echo "ERROR: settings file not found: $env_file" >&2; exit 2; }
perm="$(stat -c '%a' "$env_file")"
case "$perm" in *[2367]? | *[2367]) echo "ERROR: $env_file must not be group or world writable (mode $perm)" >&2; exit 2 ;; esac
# shellcheck source=/dev/null
. "$env_file"

: "${WORJ_DB_NAME:?WORJ_DB_NAME is required}" "${WORJ_FILES_DIR:?WORJ_FILES_DIR is required}" "${WORJ_PUBLIC_DIR:?WORJ_PUBLIC_DIR is required}"
: "${WORJ_AGE_RECIPIENT:?WORJ_AGE_RECIPIENT (an age1... public key) is required}" "${WORJ_RCLONE_REMOTE:?WORJ_RCLONE_REMOTE is required}"
WORJ_DB_DEFAULTS="${WORJ_DB_DEFAULTS:-/etc/worj/mysql-backup.cnf}"
WORJ_CONFIG="${WORJ_CONFIG:-/var/www/worj/config.inc.php}"
WORJ_BACKUP_DIR="${WORJ_BACKUP_DIR:-/var/backups/worj}"
WORJ_RETAIN_DAILY="${WORJ_RETAIN_DAILY:-14}"
WORJ_RETAIN_WEEKLY="${WORJ_RETAIN_WEEKLY:-8}"
WORJ_MIN_DUMP_BYTES="${WORJ_MIN_DUMP_BYTES:-20000}"
WORJ_MIN_TABLES="${WORJ_MIN_TABLES:-30}"
WORJ_SHRINK_LIMIT_PERCENT="${WORJ_SHRINK_LIMIT_PERCENT:-20}"
WORJ_MYSQLDUMP="${WORJ_MYSQLDUMP:-mysqldump}"
WORJ_RCLONE="${WORJ_RCLONE:-rclone}"
WORJ_ALERT_CMD="${WORJ_ALERT_CMD:-}"

case "$WORJ_AGE_RECIPIENT" in
  AGE-SECRET-KEY-*) echo "REFUSED: a PRIVATE age key is configured. The server must hold only the public key; the client keeps the private key." >&2; exit 2 ;;
  age1*) ;;
  *) echo "ERROR: WORJ_AGE_RECIPIENT must be an age public key (age1...)" >&2; exit 2 ;;
esac

ts() { if [ -n "$now" ]; then date -u -d "$now" "$@"; else date -u "$@"; fi; }
stamp="$(ts +%Y%m%dT%H%M%SZ)"
weekday="$(ts +%u)"
name="worj-$stamp.tar.age"
remote="${WORJ_RCLONE_REMOTE%/}"
daily="$WORJ_BACKUP_DIR/daily" weekly="$WORJ_BACKUP_DIR/weekly"

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; logger -t worj-backup -- "$*" 2>/dev/null || true; }
step="start"; work=""; fail_msg=""
alert() { # message
  if mkdir -p "$WORJ_BACKUP_DIR"; then printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >"$WORJ_BACKUP_DIR/FAILED" || true; fi
  logger -p user.err -t worj-backup -- "BACKUP FAILED: $1" 2>/dev/null || true
  if [ -n "$WORJ_ALERT_CMD" ]; then printf 'worj backup FAILED: %s\n' "$1" | bash -c "$WORJ_ALERT_CMD" || true; fi
}
on_exit() {
  rc=$?
  [ -z "$work" ] || rm -rf -- "$work"
  if [ "$rc" != 0 ] && [ "$check" = 0 ]; then
    msg="${fail_msg:-failed during step: $step}"
    log "FAILED ($rc): $msg"
    alert "$msg"
  fi
  exit "$rc"
}
trap on_exit EXIT
die() { fail_msg="$1"; echo "ERROR: $1" >&2; exit 1; }
act() { # description command...
  local d="$1"; shift
  if [ "$check" = 1 ]; then echo "WOULD: $d"; else "$@"; fi
}

rotate_local() { # dir keep
  local dir="$1" keep="$2" f
  [ -d "$dir" ] || return 0
  # names sort chronologically (worj-YYYYmmddTHHMMSSZ.tar.age); keep the newest $keep
  while IFS= read -r f; do
    act "delete old backup $dir/$f" rm -f -- "$dir/$f" "$dir/$f.sha256"
    [ "$check" = 1 ] || log "rotated out $f"
  done < <(find "$dir" -maxdepth 1 -type f -name 'worj-*.tar.age' -printf '%f\n' | sort | head -n "-$keep")
}
prune_remote() {
  local dmin=$((WORJ_RETAIN_DAILY + 1)) wmin=$((WORJ_RETAIN_WEEKLY * 7 + 1))
  act "delete remote daily objects older than ${dmin}d (rclone delete, never sync)" "$WORJ_RCLONE" delete "$remote/daily" --min-age "${dmin}d" --include 'worj-*' --log-level ERROR
  act "delete remote weekly objects older than ${wmin}d" "$WORJ_RCLONE" delete "$remote/weekly" --min-age "${wmin}d" --include 'worj-*' --log-level ERROR
}

if [ "$mode" = rotate ]; then
  rotate_local "$daily" "$WORJ_RETAIN_DAILY"; rotate_local "$weekly" "$WORJ_RETAIN_WEEKLY"
  exit 0
fi
if [ "$mode" = prune ]; then prune_remote; exit 0; fi

step="lock"
if [ "$check" = 0 ]; then
  mkdir -p "$WORJ_BACKUP_DIR"; chmod 700 "$WORJ_BACKUP_DIR"
  exec 9>"$WORJ_BACKUP_DIR/.lock"
  flock -n 9 || die "another backup is already running"
fi

step="dump"
echo "backup $name: database $WORJ_DB_NAME, $WORJ_FILES_DIR, $WORJ_PUBLIC_DIR, $WORJ_CONFIG -> $remote"
if [ "$check" = 1 ]; then
  echo "WOULD: dump database $WORJ_DB_NAME with $WORJ_MYSQLDUMP --defaults-extra-file=<root-only file> --single-transaction"
  echo "WOULD: check the dump (gzip, completion line, >= $WORJ_MIN_DUMP_BYTES bytes, >= $WORJ_MIN_TABLES tables, users rows) and fail with an alert otherwise"
  echo "WOULD: archive files_dir and public/, copy config.inc.php, write a SHA-256 manifest"
  echo "WOULD: encrypt everything to the age public key and write $daily/$name (mode 600)"
  [ "$weekday" != 7 ] || echo "WOULD: also keep a weekly copy in $weekly"
  echo "WOULD: rclone copy to $remote/daily (and weekly), verify size, prune by age"
  echo "WOULD: keep the newest $WORJ_RETAIN_DAILY daily and $WORJ_RETAIN_WEEKLY weekly files locally"
  exit 0
fi
[ -f "$WORJ_DB_DEFAULTS" ] || die "database defaults file not found: $WORJ_DB_DEFAULTS"
dperm="$(stat -c '%a' "$WORJ_DB_DEFAULTS")"
case "$dperm" in 600 | 400) ;; *) die "$WORJ_DB_DEFAULTS must be mode 600 (is $dperm): it holds the database password" ;; esac
[ -d "$WORJ_FILES_DIR" ] || die "files_dir not found: $WORJ_FILES_DIR"
[ -d "$WORJ_PUBLIC_DIR" ] || die "public dir not found: $WORJ_PUBLIC_DIR"
[ -f "$WORJ_CONFIG" ] || die "config file not found: $WORJ_CONFIG"
mkdir -p "$daily" "$weekly"; chmod 700 "$daily" "$weekly"
work="$(mktemp -d "$WORJ_BACKUP_DIR/.work.XXXXXX")"; chmod 700 "$work"

"$WORJ_MYSQLDUMP" --defaults-extra-file="$WORJ_DB_DEFAULTS" --single-transaction --quick --routines --triggers --no-tablespaces \
  --default-character-set=utf8mb4 "$WORJ_DB_NAME" 2>"$work/dump.err" | gzip -c >"$work/db.sql.gz" || die "mysqldump failed ($(head -c 200 "$work/dump.err" | tr '\n' ' '))"
[ "$(wc -c <"$work/dump.err")" = 0 ] || log "mysqldump warnings: $(head -c 200 "$work/dump.err" | tr '\n' ' ')"

step="sanity checks (database dump)"
gzip -t "$work/db.sql.gz" 2>/dev/null || die "the database dump is not valid gzip (empty or truncated)"
dump_bytes="$(gzip -dc "$work/db.sql.gz" | wc -c)"
[ "$dump_bytes" -ge "$WORJ_MIN_DUMP_BYTES" ] || die "the database dump is only $dump_bytes bytes (minimum $WORJ_MIN_DUMP_BYTES): refusing an implausibly small backup"
tables="$(gzip -dc "$work/db.sql.gz" | grep -c '^CREATE TABLE' || true)"
[ "$tables" -ge "$WORJ_MIN_TABLES" ] || die "the database dump has $tables CREATE TABLE statements (minimum $WORJ_MIN_TABLES)"
# no `grep -q` after a pipe: an early exit would SIGPIPE gzip and trip pipefail
gzip -dc "$work/db.sql.gz" | grep '^CREATE TABLE .users. ' >/dev/null || die "the database dump has no users table"
gzip -dc "$work/db.sql.gz" | grep '^INSERT INTO .users. ' >/dev/null || die "the users table in the dump has no rows"
gzip -dc "$work/db.sql.gz" | tail -n 3 | grep -q '^-- Dump completed' || die "the database dump does not end with mysqldump's completion line (truncated)"
log "dump ok: $dump_bytes bytes, $tables tables"

step="archive files"
tar --warning=no-file-changed -czf "$work/data.tar.gz" -C / -- "${WORJ_FILES_DIR#/}" "${WORJ_PUBLIC_DIR#/}" || [ "$?" = 1 ] || die "tar failed"
tar -tzf "$work/data.tar.gz" >/dev/null 2>&1 || die "the data archive is unreadable"
[ "$(tar -tzf "$work/data.tar.gz" | wc -l)" -ge 1 ] || die "the data archive is empty"
install -m 600 "$WORJ_CONFIG" "$work/config.inc.php"

step="bundle"
{
  echo "worj backup $stamp"
  echo "database: $WORJ_DB_NAME"
  echo "dump_bytes: $dump_bytes tables: $tables"
  echo "files_dir: $WORJ_FILES_DIR"
  echo "public_dir: $WORJ_PUBLIC_DIR"
} >"$work/INFO"
(cd "$work" && sha256sum db.sql.gz data.tar.gz config.inc.php INFO >MANIFEST.sha256)
tar -cf "$work/bundle.tar" -C "$work" db.sql.gz data.tar.gz config.inc.php INFO MANIFEST.sha256

step="encrypt"
age -r "$WORJ_AGE_RECIPIENT" -o "$work/$name" "$work/bundle.tar" || die "age encryption failed"
head -c 22 "$work/$name" | grep -q 'age-encryption.org/v1' || die "the encrypted file does not look like an age file"
size="$(wc -c <"$work/$name")"
if [ -f "$WORJ_BACKUP_DIR/last-size" ]; then
  last="$(cat "$WORJ_BACKUP_DIR/last-size")"
  if [ "$last" -gt 0 ] && [ $((size * 100)) -lt $((last * WORJ_SHRINK_LIMIT_PERCENT)) ]; then
    die "the new backup ($size bytes) is under ${WORJ_SHRINK_LIMIT_PERCENT}% of the last successful one ($last bytes)"
  fi
fi

step="store"
install -m 600 "$work/$name" "$daily/$name"
(cd "$daily" && sha256sum "$name" >"$name.sha256" && chmod 600 "$name.sha256")
if [ "$weekday" = 7 ]; then install -m 600 "$work/$name" "$weekly/$name"; (cd "$weekly" && sha256sum "$name" >"$name.sha256" && chmod 600 "$name.sha256"); fi

step="upload"
upload() { # dir-name local-file
  "$WORJ_RCLONE" copy "$2" "$remote/$1/" --log-level ERROR --retries 3 --low-level-retries 5 --checksum || die "rclone copy to $remote/$1 failed"
  "$WORJ_RCLONE" copy "$2.sha256" "$remote/$1/" --log-level ERROR --retries 3 || die "rclone copy of the checksum file failed"
  remote_size="$("$WORJ_RCLONE" lsjson "$remote/$1/$(basename "$2")" --log-level ERROR 2>/dev/null | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["Size"] if d else -1)' 2>/dev/null || echo -1)"
  [ "$remote_size" = "$size" ] || die "the remote object $1/$(basename "$2") has size $remote_size, expected $size"
}
upload daily "$daily/$name"
[ "$weekday" != 7 ] || upload weekly "$weekly/$name"
log "uploaded $name ($size bytes) to $remote"

step="rotate"
rotate_local "$daily" "$WORJ_RETAIN_DAILY"; rotate_local "$weekly" "$WORJ_RETAIN_WEEKLY"
step="prune remote"
prune_remote || log "WARNING: remote pruning failed (the backup itself succeeded)"

step="finish"
rm -f "$WORJ_BACKUP_DIR/FAILED"
printf '%s\n' "$stamp" >"$WORJ_BACKUP_DIR/last-success"
printf '%s\n' "$size" >"$WORJ_BACKUP_DIR/last-size"
log "backup $name done"
