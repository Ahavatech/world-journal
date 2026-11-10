#!/usr/bin/env bash
# Install OJS on the shared host from YOUR machine, after scripts/deploy-shared.sh has sent the release.
#
#   scripts/install-shared.sh [--env FILE] [--check] [--finish]       default env file: .env.shared (see infra/shared-hosting/install.env.example)
#
# What it does, in order (each step is skipped when already done, so it can be re-run):
#   1. preflight over ssh: PHP >= 8.2 and the extensions OJS needs, on the SAME php the installer will use
#   2. create the private files directory ABOVE the web root, and cache/ and public/ inside it
#   3. render config.inc.php here (salt and API secret generated here, never printed) and upload it, mode 600
#   4. run `php tools/install.php` on the host; every answer travels on ssh's standard input, never on a command line
#   5. fix what the installer leaves weak (salt, api_key_secret, allowed_hosts, time_zone) and verify with check-live-config.py
# Then, after scripts/seed-shared.sh (which logs in with the initial password):
#   scripts/install-shared.sh --finish     make the administrator change the initial password at the first login, and
#                                          remove ADMIN_PASSWORD from the env file
# --check prints WOULD: lines and changes nothing (it does read the host: php version, whether OJS is installed).
# Nothing secret is printed or put on a command line. UNVERIFIED (not run on the host): see docs/DEPLOY-SHARED.md.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
envfile="$root/.env.shared"; check=0; finish=0
while [ $# -gt 0 ]; do
  case "$1" in
    --env) envfile="${2:-}"; shift 2 ;;
    --check) check=1; shift ;;
    --finish) finish=1; shift ;;
    *) echo "usage: $0 [--env FILE] [--check] [--finish]" >&2; exit 2 ;;
  esac
done
die() { echo "FAIL  $*" >&2; exit 1; }
ok() { echo "ok    $*"; }
chg() { if [ "$check" = 1 ]; then echo "WOULD: $*"; else echo "DO    $*"; fi; }
[ -f "$envfile" ] || die "env file not found: $envfile (copy infra/shared-hosting/install.env.example to .env.shared and fill it in)"
mode="$(stat -c '%a' "$envfile")"; [ $((8#$mode & 8#077)) -eq 0 ] || die "$envfile is readable by others (mode $mode): chmod 600 it"
get() { sed -n "s/^$1=//p" "$envfile" | sed -n 1p; }
for v in HOST TIME_ZONE SSH_TARGET REMOTE_ROOT DB_NAME DB_USER DB_PASSWORD ADMIN_USERNAME ADMIN_EMAIL SMTP_SERVER SMTP_PORT SMTP_AUTH SMTP_USERNAME SMTP_PASSWORD SSH_PORT; do
  val="$(get "$v")"; [ -n "$val" ] || die "$v is empty in $envfile"
  case "$val" in *REPLACE*) die "$v still has a REPLACE_ placeholder in $envfile" ;; esac
  printf -v "$v" '%s' "$val"
done
SSH_KEY="$(get SSH_KEY)"; ADMIN_PASSWORD="$(get ADMIN_PASSWORD)"
case "$ADMIN_PASSWORD" in *REPLACE*) ADMIN_PASSWORD="" ;; esac
[[ "$HOST" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || die "HOST must be a plain lower-case host name"
[[ "$REMOTE_ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "REMOTE_ROOT must be an absolute path of plain characters"
[[ "$DB_NAME$DB_USER$ADMIN_USERNAME" =~ ^[A-Za-z0-9_.-]+$ ]] || die "DB_NAME, DB_USER and ADMIN_USERNAME may hold only letters, digits, _ . -"
python3 -c 'import sys,zoneinfo; zoneinfo.ZoneInfo(sys.argv[1])' "$TIME_ZONE" 2>/dev/null || die "TIME_ZONE '$TIME_ZONE' is not an IANA zone"
webroot="$REMOTE_ROOT/public_html"; files_dir="$REMOTE_ROOT/worj-files"; cfg="$webroot/config.inc.php"

sshbase=("${WORJ_SSH:-ssh}" -p "$SSH_PORT" -o BatchMode=yes)
[ -z "$SSH_KEY" ] || sshbase+=(-i "$SSH_KEY")
remote() { "${sshbase[@]}" "$SSH_TARGET" "$@"; }

tmp="$(mktemp -d)"; chmod 700 "$tmp"
trap 'rm -rf -- "${tmp:?}"' EXIT

# 1. preflight
php_v="$(remote 'php -r "echo PHP_VERSION;"' 2>"$tmp/ssh.err")" || { sed 's/^/      /' "$tmp/ssh.err" >&2; die "cannot run php over ssh (is SSH on in hPanel, and the key added?)"; }
printf '%s' "$php_v" | python3 -c 'import sys; v=tuple(int(x) for x in sys.stdin.read().split(".")[:2]); sys.exit(0 if v>=(8,2) else 1)' || die "the host's CLI PHP is $php_v; OJS 3.5 needs 8.2 or newer (hPanel > PHP Configuration; the CLI follows the same setting only if Day-0 showed it)"
ok "PHP $php_v on the command line"
need="bcmath ctype curl dom fileinfo filter ftp gd hash intl json libxml mbstring mysqli openssl pcre phar session simplexml spl tokenizer xml xmlwriter zip zlib"
have="$(remote 'php -m' | tr '[:upper:]' '[:lower:]')"
missing=""; for e in $need; do grep -qxF "$e" <<<"$have" || missing="$missing $e"; done
[ -z "$missing" ] || die "PHP extensions missing on the command line:$missing (hPanel > PHP Configuration > PHP extensions)"
ok "all required PHP extensions are present"

installed=0
if remote "test -f $(printf '%q' "$cfg") && grep -q '^installed = On' $(printf '%q' "$cfg")" 2>/dev/null; then installed=1; ok "OJS is already installed (config.inc.php says installed = On)"; fi

if [ "$installed" = 0 ]; then
  [ -n "$ADMIN_PASSWORD" ] || die "ADMIN_PASSWORD is empty in $envfile and OJS is not installed yet"
  [ "${#ADMIN_PASSWORD}" -ge 12 ] || die "the administrator password must have at least 12 characters"
fi
# 2. directories
chg "create $files_dir (mode 700), $webroot/cache and $webroot/public"
if [ "$check" = 0 ]; then remote "mkdir -p $(printf '%q' "$files_dir") $(printf '%q' "$webroot/cache") $(printf '%q' "$webroot/public") && chmod 700 $(printf '%q' "$files_dir") && chmod 755 $(printf '%q' "$webroot/cache") $(printf '%q' "$webroot/public")"; fi

if [ "$installed" = 0 ]; then
  chg "render config.inc.php here (salt and API secret generated here), upload it with mode 600"
  chg "run php tools/install.php on the host (answers on ssh's standard input)"
  if [ "$check" = 0 ]; then
    remote "test ! -e $(printf '%q' "$cfg")" 2>/dev/null || ok "an unfinished config.inc.php exists on the host: it will be replaced"
    salt="$(openssl rand -hex 24)"; apisecret="$(openssl rand -hex 24)"
    {
      printf 'BASE_URL=https://%s\nHOSTNAME=%s\nDB_USER=%s\nDB_PASSWORD=%s\nDB_NAME=%s\nFILES_DIR=%s\n' "$HOST" "$HOST" "$DB_USER" "$DB_PASSWORD" "$DB_NAME" "$files_dir"
      printf 'SALT=%s\nAPI_KEY_SECRET=%s\n' "$salt" "$apisecret"
      printf 'SMTP_SERVER=%s\nSMTP_PORT=%s\nSMTP_AUTH=%s\nSMTP_USERNAME=%s\nSMTP_PASSWORD=%s\nOAI_REPOSITORY_ID=%s\n' "$SMTP_SERVER" "$SMTP_PORT" "$SMTP_AUTH" "$SMTP_USERNAME" "$SMTP_PASSWORD" "$HOST"
    } | python3 -I "$root/scripts/render-template.py" "$root/ojs/config/config.inc.php.template" "$tmp/config.inc.php" --mode 600 --allow-unused >/dev/null
    remote "umask 077 && cat > $(printf '%q' "$cfg") && chmod 600 $(printf '%q' "$cfg")" <"$tmp/config.inc.php"
    printf '%s\n' en "" "$files_dir" "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "$ADMIN_PASSWORD" "$ADMIN_EMAIL" mysqli localhost "$DB_USER" "$DB_PASSWORD" "$DB_NAME" "$HOST" n y >"$tmp/answers"
    if ! remote "cd $(printf '%q' "$webroot") && php tools/install.php" <"$tmp/answers" >"$tmp/install.log" 2>&1; then
      log="$(tail -n 20 "$tmp/install.log")"; for s in "$DB_PASSWORD" "$ADMIN_PASSWORD" "$SMTP_PASSWORD"; do log="${log//"$s"/***}"; done
      printf '%s\n' "$log" | sed 's/^/      /' >&2; die "the OJS installer failed (last lines above, secrets masked)"
    fi
    rm -f "$tmp/answers"
    ok "the OJS installer finished"
  fi
else
  chg "nothing to install"
fi

# 5. fix what the installer leaves weak, then verify (the live config is pulled to a private temp file, edited here, pushed back)
if [ "$check" = 0 ]; then
  remote "cat $(printf '%q' "$cfg")" >"$tmp/live.inc.php"; chmod 600 "$tmp/live.inc.php"
  printf 'general.allowed_hosts=%s\ngeneral.time_zone="%s"\n' "'[\"$HOST\"]'" "$TIME_ZONE" |
    python3 -I "$root/scripts/set-ojs-config.py" "$tmp/live.inc.php" --generate-if-weak security.salt --generate-if-weak security.api_key_secret >"$tmp/set.txt" 2>&1 || { cat "$tmp/set.txt" >&2; die "set-ojs-config.py failed"; }
  if grep -qE '^(changed|generated)' "$tmp/set.txt"; then
    chg "re-applied allowed_hosts, time_zone, salt, API secret after the installer"
    remote "umask 077 && cat > $(printf '%q' "$cfg") && chmod 600 $(printf '%q' "$cfg")" <"$tmp/live.inc.php"
  else ok "allowed_hosts, time_zone, salt and API secret are already right"; fi
  python3 -I "$root/scripts/check-live-config.py" "$tmp/live.inc.php" --host "$HOST" --web-root "$webroot" || die "the live config check failed (above): fix before continuing"
else
  chg "pull config.inc.php, re-apply allowed_hosts / time_zone / salt / API secret if weak, run check-live-config.py"
fi
# 6. finish: from now on the initial password is only a hash in the database, and the administrator must replace it
if [ "$finish" = 1 ]; then
  [ "$installed" = 1 ] || die "--finish needs an installed OJS (run the install first)"
  chg "set must_change_password for $ADMIN_USERNAME"
  if [ "$check" = 0 ]; then
    # the first login must change the initial password: the installer's own tables hold the user, set the flag from PHP
    remote "cd $(printf '%q' "$webroot") && php -r '\$c=parse_ini_file(\"config.inc.php\",true,INI_SCANNER_RAW); \$d=\$c[\"database\"]; \$m=new mysqli(trim(\$d[\"host\"],\"\\\"\"),trim(\$d[\"username\"],\"\\\"\"),trim(\$d[\"password\"],\"\\\"\"),trim(\$d[\"name\"],\"\\\"\")); \$s=\$m->prepare(\"UPDATE users SET must_change_password=1 WHERE username=?\"); \$u=\$argv[1]; \$s->bind_param(\"s\",\$u); \$s->execute(); echo \$s->affected_rows;' $(printf '%q' "$ADMIN_USERNAME")" >"$tmp/mcp.txt" || die "could not set must_change_password"
    [ "$(cat "$tmp/mcp.txt")" -ge 0 ] 2>/dev/null && ok "the administrator must change the initial password at the first login"
    if grep -q '^ADMIN_PASSWORD=' "$envfile"; then
      chg "remove the initial ADMIN_PASSWORD line from $envfile"
      keep="$(mktemp "$envfile.XXXXXX")"; grep -v '^ADMIN_PASSWORD=' "$envfile" >"$keep" || true; chmod 600 "$keep"; mv -f "$keep" "$envfile"
    fi
  fi
fi
echo "done."
