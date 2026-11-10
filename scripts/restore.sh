#!/usr/bin/env bash
# Restore rehearsal: decrypt a backup, load it into a SCRATCH database, serve a throwaway copy of the site on localhost
# and confirm that the login page loads. Run by the OPERATOR, with the private age key: the server cannot decrypt its
# own backups, so this is normally run on a staging machine or the operator's own machine, never with the key left on
# the production server.
#
#   scripts/restore.sh --bundle FILE.tar.age --identity KEYFILE --code-dir OJSDIR --live-config FILE \
#                      --scratch-db NAME --db-defaults FILE [--port 18199] [--keep] [--check]
#
#   --bundle FILE        the encrypted backup (worj-<time>.tar.age)
#   --identity KEYFILE   the age private key (a path; its content is never printed)
#   --code-dir DIR       an OJS code tree to serve (it is copied, hard-linked where possible; never modified)
#   --live-config FILE   the PRODUCTION config.inc.php: only used to read the production database name and host for
#                        the safety guard below
#   --scratch-db NAME    name of the scratch database to create and drop (must contain "restore")
#   --db-defaults FILE   mysql defaults file (mode 600) for a user that may create and drop the scratch database
#   --keep               keep the scratch database and the served copy after the check (default: remove both)
#   --check              print what would happen, run only the safety guard
#
# SAFETY GUARD (runs before anything is touched): the script REFUSES if the scratch database name equals the
# production database name from the live config, if the scratch name does not contain "restore", or if the scratch
# connection target (host and database) equals the production one.
# The temporary config holds the database password: it lives in a mode-700 directory and is removed on exit.
set -euo pipefail
umask 077

bundle="" identity="" code_dir="" live_config="" scratch="" db_defaults="" port=18199 keep=0 check=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle) bundle="${2:?}"; shift 2 ;;
    --identity) identity="${2:?}"; shift 2 ;;
    --code-dir) code_dir="${2:?}"; shift 2 ;;
    --live-config) live_config="${2:?}"; shift 2 ;;
    --scratch-db) scratch="${2:?}"; shift 2 ;;
    --db-defaults) db_defaults="${2:?}"; shift 2 ;;
    --port) port="${2:?}"; shift 2 ;;
    --keep) keep=1; shift ;;
    --check) check=1; shift ;;
    -h | --help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for v in bundle identity code_dir live_config scratch db_defaults; do
  [ -n "${!v}" ] || { echo "ERROR: --${v//_/-} is required" >&2; exit 2; }
done

# ---- safety guard, before anything is touched -------------------------------------------------
read_cfg() { python3 -I - "$live_config" "$1" <<'PY'
import re, sys
cfg, want = sys.argv[1], sys.argv[2]
section = ""
for line in open(cfg, encoding="utf-8"):
    m = re.match(r"^\[(\w+)\]", line)
    if m:
        section = m.group(1); continue
    a = re.match(r"^([A-Za-z_]\w*)\s*=\s*(.*)$", line.rstrip("\n"))
    if a and f"{section}.{a.group(1)}" == want:
        print(a.group(2).strip().strip("\"'")); break
PY
}
read_defaults() { python3 -I - "$db_defaults" "$1" <<'PY'
import configparser, sys
c = configparser.ConfigParser(interpolation=None, allow_no_value=True)
c.read(sys.argv[1])
print((c["client"].get(sys.argv[2]) or "").strip().strip("\"'") if "client" in c else "")
PY
}
[ -f "$live_config" ] || { echo "REFUSED: --live-config not found: $live_config (the guard needs the production database name)" >&2; exit 3; }
prod_db="$(read_cfg database.name)"; prod_host="$(read_cfg database.host)"; prod_host="${prod_host:-localhost}"
dd_host="$(read_defaults host)"; dd_host="${dd_host:-localhost}"
[ -n "$prod_db" ] || { echo "REFUSED: could not read database.name from the live config" >&2; exit 3; }
case "$scratch" in *[!A-Za-z0-9_]*) echo "REFUSED: the scratch database name may contain only letters, digits and underscores" >&2; exit 3 ;; esac
case "$scratch" in *restore*) ;; *) echo "REFUSED: the scratch database name must contain \"restore\" (got a name that does not): a restore must never target a name that could be a live database" >&2; exit 3 ;; esac
if [ "$scratch" = "$prod_db" ]; then
  echo "REFUSED: the scratch database name equals the production database name ($prod_db). Nothing was touched." >&2; exit 3
fi
if [ "$scratch" = "$prod_db" ] && [ "$dd_host" = "$prod_host" ]; then
  echo "REFUSED: the scratch connection target equals the production one. Nothing was touched." >&2; exit 3
fi
echo "guard ok: scratch database '$scratch' differs from production '$prod_db'"

if [ "$check" = 1 ]; then
  echo "WOULD: decrypt $bundle with the private key, verify the manifest"
  echo "WOULD: create scratch database '$scratch', load the dump"
  echo "WOULD: copy the code tree, extract files_dir and public/, write a temporary config pointing at the scratch database"
  echo "WOULD: serve it on 127.0.0.1:$port and require HTTP 200 and a username field on the login page"
  echo "WOULD: drop the scratch database and remove the temporary files (unless --keep)"
  exit 0
fi

for f in "$bundle" "$identity" "$db_defaults"; do [ -f "$f" ] || { echo "ERROR: file not found: $f" >&2; exit 2; }; done
[ -d "$code_dir" ] || { echo "ERROR: code dir not found: $code_dir" >&2; exit 2; }
dperm="$(stat -c '%a' "$db_defaults")"; case "$dperm" in 600 | 400) ;; *) echo "ERROR: $db_defaults must be mode 600 (it holds a password)" >&2; exit 2 ;; esac
my() { mariadb --defaults-extra-file="$db_defaults" "$@"; }

work="$(mktemp -d)"; chmod 700 "$work"
php_pid=""; created=0
# shellcheck disable=SC2317  # called by the EXIT trap
cleanup() {
  [ -z "$php_pid" ] || kill "$php_pid" 2>/dev/null || true
  if [ "$keep" = 0 ]; then
    [ "$created" = 0 ] || my -e "DROP DATABASE IF EXISTS \`$scratch\`" 2>/dev/null || true
    rm -rf -- "$work"
  else
    echo "kept: scratch database '$scratch' and $work (remove them by hand; the config there holds the database password)"
  fi
}
trap cleanup EXIT
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }

age -d -i "$identity" -o "$work/bundle.tar" "$bundle" 2>"$work/age.err" || { echo "FAIL  decryption failed: $(head -c 160 "$work/age.err" | tr '\n' ' ')" >&2; exit 1; }
ok "backup decrypted with the private key"
mkdir "$work/parts"; tar -xf "$work/bundle.tar" -C "$work/parts"
(cd "$work/parts" && sha256sum -c --quiet MANIFEST.sha256) || { echo "FAIL  the manifest does not match: the backup is corrupt" >&2; exit 1; }
ok "SHA-256 manifest matches (db.sql.gz, data.tar.gz, config.inc.php, INFO)"

my -e "DROP DATABASE IF EXISTS \`$scratch\`; CREATE DATABASE \`$scratch\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"; created=1
gzip -dc "$work/parts/db.sql.gz" | my "$scratch"
tables="$(my -N -e "select count(*) from information_schema.tables where table_schema='$scratch'")"
users="$(my -N -e "select count(*) from \`$scratch\`.users")"
if [ "$tables" -ge 30 ]; then ok "scratch database loaded: $tables tables, $users user(s)"; else bad "scratch database has only $tables tables"; fi
[ "$users" -ge 1 ] || bad "no users in the restored database"

files_dir="$(sed -n 's/^files_dir: //p' "$work/parts/INFO")"; public_dir="$(sed -n 's/^public_dir: //p' "$work/parts/INFO")"
mkdir "$work/data"; tar -xzf "$work/parts/data.tar.gz" -C "$work/data"
if [ -d "$work/data/${files_dir#/}" ]; then ok "files_dir restored ($(find "$work/data/${files_dir#/}" -type f | wc -l) files)"; else bad "files_dir missing from the archive"; fi

site="$work/site"
cp -al "$code_dir" "$site" 2>/dev/null || { rm -rf "$site"; cp -a "$code_dir" "$site"; }
rm -f "$site/config.inc.php"          # unlink only our copy: the original stays untouched
rm -rf "$site/public"
cp -a "$work/data/${public_dir#/}" "$site/public"
install -m 600 "$work/parts/config.inc.php" "$site/config.inc.php"
db_user="$(read_defaults user)"; db_pass="$(read_defaults password)"; db_host="$(read_defaults host)"; db_host="${db_host:-localhost}"
printf '%s\n' "database.name=$scratch" "database.host=$db_host" "database.username=$db_user" "database.password=$db_pass" \
  "general.base_url=\"http://127.0.0.1:$port\"" "general.allowed_hosts='[\"127.0.0.1\"]'" "general.restful_urls=Off" \
  "security.force_ssl=Off" "security.force_login_ssl=Off" "email.default=log" "files.files_dir=$work/data/${files_dir#/}" |
  python3 -I "$root/scripts/set-ojs-config.py" "$site/config.inc.php" >/dev/null
if [ "$(stat -c '%a' "$site/config.inc.php")" = 600 ]; then ok "temporary config is mode 600 (removed on exit)"; else bad "temporary config is not mode 600"; fi

journal="$(my -N -e "select path from \`$scratch\`.journals order by journal_id limit 1")"
php -S "127.0.0.1:$port" -t "$site" >"$work/php.log" 2>&1 & php_pid=$!
for _ in $(seq 1 30); do curl -s -o /dev/null --noproxy '*' "http://127.0.0.1:$port/" && break; sleep 0.5; done
page="$(curl -s --noproxy '*' -m 60 -w '\n%{http_code}' "http://127.0.0.1:$port/index.php/$journal/login")"
code="${page##*$'\n'}"
if [ "$code" = 200 ]; then ok "login page /index.php/$journal/login returned 200"; else bad "login page returned $code"; fi
if grep -q 'name="username"' <<<"$page"; then ok "login page has the username field"; else bad "login page has no username field"; fi
if [ "$fail" = 0 ]; then echo "RESTORE REHEARSAL OK"; else echo "RESTORE REHEARSAL FAILED ($fail)"; fi
exit "$fail"
