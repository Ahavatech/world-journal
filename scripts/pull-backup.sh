#!/usr/bin/env bash
# Pull-based encrypted backup of the shared-host journal, run on YOUR machine (or the client's), never on the host.
#
#   scripts/pull-backup.sh [--env FILE] [--check] [--no-upload]
#
# The host holds no key and needs no extra tool: the database dump and the files stream OUT over ssh and are encrypted HERE
# with age, to the client's PUBLIC key. The bundle has the same layout as scripts/backup.sh (db.sql.gz, data.tar.gz,
# config.inc.php, INFO, MANIFEST.sha256 inside one age file), so scripts/restore.sh restores it unchanged.
# Settings come from .env.shared (infra/shared-hosting/install.env.example) plus, in the same file:
#   BACKUP_AGE_RECIPIENT=age1...       the client's PUBLIC key (a private AGE-SECRET-KEY- is refused)
#   BACKUP_DIR=/path                   where bundles are kept here (default ~/worj-backups, mode 700)
#   BACKUP_RCLONE_REMOTE=remote:bucket optional: `rclone copy` (never sync) of the bundle, verified by size
#   BACKUP_KEEP=12                     bundles kept locally
# The database password never leaves the host and never appears on a command line: the dump runs there with a defaults file
# built on the fly from config.inc.php and read through a pipe. Before anything is encrypted the same sanity checks as
# backup.sh run (gzip, size, tables, users rows, mysqldump's completion line): an empty backup that "succeeds" is the usual failure.
# Any failure writes BACKUP_DIR/FAILED and exits non-zero. RECOVERY POINT: only as fresh as the last time YOU run this; the
# host's own daily backups (7 days, held by Hostinger, not encrypted to your key) are the other line. docs/DEPLOY-SHARED.md.
# UNVERIFIED (not run on the host): needs mysqldump and tar on the host (Day-0 shows).
set -euo pipefail
umask 077
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
envfile="$root/.env.shared"; check=0; upload=1
while [ $# -gt 0 ]; do
  case "$1" in
    --env) envfile="${2:-}"; shift 2 ;;
    --check) check=1; shift ;;
    --no-upload) upload=0; shift ;;
    *) echo "usage: $0 [--env FILE] [--check] [--no-upload]" >&2; exit 2 ;;
  esac
done
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
step="start"; fail_msg=""; work=""; bdir=""
die() { fail_msg="$1"; echo "ERROR: $1" >&2; exit 1; }
on_exit() {
  rc=$?
  [ -z "$work" ] || rm -rf -- "$work"
  if [ "$rc" != 0 ] && [ "$check" = 0 ] && [ -n "$bdir" ] && [ -d "$bdir" ]; then
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${fail_msg:-failed during step: $step}" >"$bdir/FAILED" || true
    echo "BACKUP FAILED: ${fail_msg:-failed during step: $step}" >&2
  fi
  exit "$rc"
}
trap on_exit EXIT
[ -f "$envfile" ] || die "env file not found: $envfile"
mode="$(stat -c '%a' "$envfile")"; [ $((8#$mode & 8#077)) -eq 0 ] || die "$envfile is readable by others (mode $mode): chmod 600 it"
get() { sed -n "s/^$1=//p" "$envfile" | sed -n 1p; }
for v in SSH_TARGET SSH_PORT REMOTE_ROOT BACKUP_AGE_RECIPIENT; do
  val="$(get "$v")"; [ -n "$val" ] || die "$v is empty in $envfile"
  case "$val" in *REPLACE*) die "$v still has a REPLACE_ placeholder" ;; esac
  printf -v "$v" '%s' "$val"
done
SSH_KEY="$(get SSH_KEY)"; bdir="$(get BACKUP_DIR)"; bdir="${bdir:-$HOME/worj-backups}"
keep="$(get BACKUP_KEEP)"; keep="${keep:-12}"; rclone_remote="$(get BACKUP_RCLONE_REMOTE)"
{ [[ "$keep" =~ ^[0-9]+$ ]] && [ "$keep" -ge 1 ]; } || die "BACKUP_KEEP must be a positive number"
[[ "$REMOTE_ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "REMOTE_ROOT must be an absolute path of plain characters"
case "$BACKUP_AGE_RECIPIENT" in
  AGE-SECRET-KEY-*) die "REFUSED: a PRIVATE age key is configured. Put only the public key (age1...) here; the client keeps the private key." ;;
  age1*) ;;
  *) die "BACKUP_AGE_RECIPIENT must be an age public key (age1...)" ;;
esac
for t in age ssh tar gzip python3; do command -v "$t" >/dev/null || die "missing tool here: $t"; done
[ -z "$rclone_remote" ] || [ "$upload" = 0 ] || command -v rclone >/dev/null || die "BACKUP_RCLONE_REMOTE is set but rclone is not installed here"
webroot="$REMOTE_ROOT/public_html"; files_dir="$REMOTE_ROOT/worj-files"; cfg="$webroot/config.inc.php"
sshbase=("${WORJ_SSH:-ssh}" -p "$SSH_PORT" -o BatchMode=yes)
[ -z "$SSH_KEY" ] || sshbase+=(-i "$SSH_KEY")
remote() { "${sshbase[@]}" "$SSH_TARGET" "$@"; }
q() { printf '%q' "$1"; }
stamp="$(date -u +%Y%m%dT%H%M%SZ)"; name="worj-$stamp.tar.age"

if [ "$check" = 1 ]; then
  echo "WOULD: dump the database over ssh with a defaults file built on the host from $cfg (password never on a command line)"
  echo "WOULD: check the dump (gzip, completion line, size, tables, users rows) and fail otherwise"
  echo "WOULD: stream $files_dir and $webroot/public over ssh as a tar archive, copy config.inc.php"
  echo "WOULD: build the bundle, encrypt it HERE to the age public key, write $bdir/$name (mode 600) with a sha256 file"
  [ -z "$rclone_remote" ] || echo "WOULD: rclone copy to $rclone_remote and verify the size"
  echo "WOULD: keep the newest $keep bundles in $bdir"
  exit 0
fi
mkdir -p "$bdir"; chmod 700 "$bdir"
exec 9>"$bdir/.lock"; flock -n 9 || die "another backup is already running"
work="$(mktemp -d "$bdir/.work.XXXXXX")"; chmod 700 "$work"

step="dump"
# The remote script: a defaults file from config.inc.php through a pipe (process substitution), then mysqldump. php prints
# the credentials into the pipe; nothing secret is on any command line or in a file on the host.
# The script goes to the host on ssh's standard input (no quoting puzzles, nothing secret in it).
remote "bash -s -- $(q "$webroot")" 2>"$work/dump.err" >"$work/db.sql" <<'EOS' || die "the dump failed on the host ($(head -c 200 "$work/dump.err" | tr '\n' ' '))"
cd "$1" || { echo "cannot enter the web root" >&2; exit 1; }
command -v mysqldump >/dev/null || { echo "mysqldump is not installed on the host" >&2; exit 1; }
creds="$(cat <<'PHP'
$c = parse_ini_file("config.inc.php", true, INI_SCANNER_RAW);
$d = $c["database"];
$e = function ($v) { return addcslashes(trim($v, "\""), "\\\""); };
echo "[client]\nuser=\"" . $e($d["username"]) . "\"\npassword=\"" . $e($d["password"]) . "\"\nhost=\"" . $e($d["host"]) . "\"\n";
PHP
)"
dbname="$(php -r '$c = parse_ini_file("config.inc.php", true, INI_SCANNER_RAW); echo trim($c["database"]["name"], "\"");')"
mysqldump --defaults-extra-file=<(php -r "$creds") --single-transaction --quick --routines --triggers --no-tablespaces \
  --default-character-set=utf8mb4 "$dbname"
EOS
gzip -c "$work/db.sql" >"$work/db.sql.gz" && rm -f "$work/db.sql"
step="sanity checks (database dump)"
gzip -t "$work/db.sql.gz" 2>/dev/null || die "the database dump is not valid gzip (empty or truncated; mysqldump missing on the host? see $work/dump.err: $(head -c 200 "$work/dump.err" | tr '\n' ' '))"
min_bytes="${WORJ_MIN_DUMP_BYTES:-20000}"; min_tables="${WORJ_MIN_TABLES:-30}"
dump_bytes="$(gzip -dc "$work/db.sql.gz" | wc -c)"
[ "$dump_bytes" -ge "$min_bytes" ] || die "the database dump is only $dump_bytes bytes (minimum $min_bytes): refusing an implausibly small backup"
tables="$(gzip -dc "$work/db.sql.gz" | grep -c '^CREATE TABLE' || true)"
[ "$tables" -ge "$min_tables" ] || die "the database dump has $tables CREATE TABLE statements (minimum $min_tables)"
gzip -dc "$work/db.sql.gz" | grep '^CREATE TABLE .users. ' >/dev/null || die "the database dump has no users table"
gzip -dc "$work/db.sql.gz" | grep '^INSERT INTO .users. ' >/dev/null || die "the users table in the dump has no rows"
gzip -dc "$work/db.sql.gz" | tail -n 3 | grep -q '^-- Dump completed' || die "the database dump does not end with mysqldump's completion line (truncated)"
log "dump ok: $dump_bytes bytes, $tables tables"

step="archive files"
remote "tar --warning=no-file-changed -czf - -C / -- $(q "${files_dir#/}") $(q "${webroot#/}/public")" >"$work/data.tar.gz" || [ "$?" = 1 ] || die "tar failed on the host"
tar -tzf "$work/data.tar.gz" >/dev/null 2>&1 || die "the data archive is unreadable"
[ "$(tar -tzf "$work/data.tar.gz" | wc -l)" -ge 1 ] || die "the data archive is empty"
remote "cat $(q "$cfg")" >"$work/config.inc.php" || die "could not read config.inc.php"
grep -q '^installed = On' "$work/config.inc.php" || die "the config copy is not an installed OJS config"

step="bundle"
{
  echo "worj backup $stamp (pulled over ssh)"
  echo "database: $(sed -n 's/^name *= *//p' "$work/config.inc.php" | sed -n 1p | tr -d '"')"
  echo "dump_bytes: $dump_bytes tables: $tables"
  echo "files_dir: $files_dir"
  echo "public_dir: $webroot/public"
} >"$work/INFO"
(cd "$work" && sha256sum db.sql.gz data.tar.gz config.inc.php INFO >MANIFEST.sha256)
tar -cf "$work/bundle.tar" -C "$work" db.sql.gz data.tar.gz config.inc.php INFO MANIFEST.sha256
step="encrypt"
age -r "$BACKUP_AGE_RECIPIENT" -o "$work/$name" "$work/bundle.tar" || die "age encryption failed"
head -c 22 "$work/$name" | grep -q 'age-encryption.org/v1' || die "the encrypted file does not look like an age file"
size="$(wc -c <"$work/$name")"
if [ -f "$bdir/last-size" ]; then
  last="$(cat "$bdir/last-size")"
  [ "$last" -le 0 ] || [ $((size * 100)) -ge $((last * 20)) ] || die "the new backup ($size bytes) is under 20% of the last successful one ($last bytes)"
fi
step="store"
install -m 600 "$work/$name" "$bdir/$name"
(cd "$bdir" && sha256sum "$name" >"$name.sha256" && chmod 600 "$name.sha256")
if [ -n "$rclone_remote" ] && [ "$upload" = 1 ]; then
  step="upload"
  rclone copy "$bdir/$name" "${rclone_remote%/}/" --log-level ERROR --retries 3 --checksum || die "rclone copy failed"
  rclone copy "$bdir/$name.sha256" "${rclone_remote%/}/" --log-level ERROR --retries 3 || die "rclone copy of the checksum failed"
  rsize="$(rclone lsjson "${rclone_remote%/}/$name" --log-level ERROR 2>/dev/null | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["Size"] if d else -1)' 2>/dev/null || echo -1)"
  [ "$rsize" = "$size" ] || die "the remote object has size $rsize, expected $size"
  log "uploaded $name to $rclone_remote"
fi
step="rotate"
while IFS= read -r f; do rm -f -- "$bdir/$f" "$bdir/$f.sha256"; log "rotated out $f"; done < <(find "$bdir" -maxdepth 1 -type f -name 'worj-*.tar.age' -printf '%f\n' | sort | head -n "-$keep")
rm -f "$bdir/FAILED"; printf '%s\n' "$stamp" >"$bdir/last-success"; printf '%s\n' "$size" >"$bdir/last-size"
log "backup $name done ($size bytes)"
