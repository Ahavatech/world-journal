#!/usr/bin/env bash
# Provision a fresh Ubuntu 24.04 LTS VPS for the journal. Idempotent: a second run changes nothing.
#
#   sudo scripts/provision-ubuntu.sh --env /etc/worj/provision.env --os 24.04 [--check] [--stage NAME ...]
#
#   --env FILE        settings (root-owned, mode 600; see infra/provision.env.example)
#   --os VERSION      the OS version you believe this machine runs. REQUIRED: the script refuses anything but
#                     Ubuntu 24.04 LTS, and refuses when your answer and the machine disagree
#   --check           print every action as `WOULD: ...` and change NOTHING
#   --stage NAME      run only this stage (repeatable); --list-stages shows the order
#   --skip-services   do not touch systemd (chroot tests); --skip-firewall, --skip-ssh skip those stages
#   --confirm-ssh     after logging in again with your key in a SECOND terminal: cancel the safety timer
#
# Secrets: generated here (salt, API key secret, database password) or read from the root-only env file (admin
# password, SMTP password); they never appear on a command line, in a log or on screen, xtrace is refused, the
# installer's answers file is removed on exit even on failure.
# Nothing here has been run on a VPS: UNVERIFIED (not run on VPS). See docs/ENV-REPORT.md and docs/DEPLOY.md.
set -euo pipefail
umask 077
case $- in *x*) echo "ERROR: refusing to run with xtrace on (it would print secrets)" >&2; exit 2 ;; esac
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/scripts/lib/provision-common.sh"

ENV_FILE="/etc/worj/provision.env" OS_ANSWER="" STAGES=() SKIP_SERVICES=0 SKIP_FIREWALL=0 SKIP_SSH=0 CONFIRM_SSH=0 LIST=0
ALL_STAGES=(preflight packages php mariadb ojs-code ojs-config cloudflare-ip nginx certbot nginx-final unattended backup-cron firewall ssh)
while [ "$#" -gt 0 ]; do
  case "$1" in
    --env) ENV_FILE="${2:?}"; shift 2 ;;
    --os) OS_ANSWER="${2:?}"; shift 2 ;;
    --check) CHECK=1; shift ;;
    --stage) STAGES+=("${2:?}"); shift 2 ;;
    --skip-services) SKIP_SERVICES=1; shift ;;
    --skip-firewall) SKIP_FIREWALL=1; shift ;;
    --skip-ssh) SKIP_SSH=1; shift ;;
    --confirm-ssh) CONFIRM_SSH=1; shift ;;
    --list-stages) LIST=1; shift ;;
    -h | --help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (secrets are never taken from the command line)" >&2; exit 2 ;;
  esac
done
if [ "$LIST" = 1 ]; then printf '%s\n' "${ALL_STAGES[@]}"; exit 0; fi
export SKIP_SERVICES
OS_RELEASE="${WORJ_OS_RELEASE:-/etc/os-release}"   # a test-only override

# --------------------------------------------------------------------------------------------------------------
stage_preflight() {
  [ "$(id -u)" = 0 ] || die "run as root (sudo)"
  [ -f "$OS_RELEASE" ] || die "cannot read $OS_RELEASE"
  local id ver lts
  id="$(sed -n 's/^ID=//p' "$OS_RELEASE" | tr -d '"')"; ver="$(sed -n 's/^VERSION_ID=//p' "$OS_RELEASE" | tr -d '"')"
  lts="$(sed -n 's/^VERSION=//p' "$OS_RELEASE")"
  [ "$id" = ubuntu ] || die "REFUSED: this is '$id'; only Ubuntu 24.04 LTS is supported"
  [ "$ver" = 24.04 ] || die "REFUSED: this is Ubuntu $ver; only Ubuntu 24.04 LTS is supported"
  case "$lts" in *LTS*) ;; *) die "REFUSED: this Ubuntu release is not marked LTS" ;; esac
  [ -n "$OS_ANSWER" ] || die "REFUSED: say which OS version you intend to provision: --os 24.04 (this machine reports Ubuntu $ver)"
  [ "$OS_ANSWER" = "$ver" ] || die "REFUSED: you said --os $OS_ANSWER but this machine is Ubuntu $ver"
  ok "Ubuntu $ver LTS, matches --os $OS_ANSWER"
  [ -f "$ENV_FILE" ] || die "settings file not found: $ENV_FILE (copy infra/provision.env.example, mode 600)"
  local perm; perm="$(stat -c '%a %U' "$ENV_FILE")"
  [ "$perm" = "600 root" ] || die "$ENV_FILE must be mode 600 and owned by root (is $perm): it holds secrets"
  load_env "$ENV_FILE"
  local v
  for v in HOST ALT_HOST TIME_ZONE OPERATOR_USER ADMIN_USERNAME ADMIN_EMAIL SMTP_SERVER SMTP_PORT SMTP_AUTH SMTP_USERNAME SMTP_PASSWORD AGE_RECIPIENT RCLONE_REMOTE CERT_METHOD; do
    [ -n "${!v:-}" ] || die "$v is required in $ENV_FILE"
    case "${!v}" in *REPLACE*) die "$v still holds a REPLACE placeholder in $ENV_FILE" ;; esac
  done
  DB_NAME="${DB_NAME:-worj}" DB_USER="${DB_USER:-worj}" WEBROOT="${WEBROOT:-/var/www/worj}" FILES_DIR="${FILES_DIR:-/var/lib/worj/files}"
  OJS_SRC="${OJS_SRC:-$ROOT/ojs-core}" THEME_SRC="${THEME_SRC:-$ROOT/ojs/plugins/themes/worj}" HSTS_MAX_AGE="${HSTS_MAX_AGE:-300}"
  SSH_PORT="${SSH_PORT:-22}" FIREWALL_CLOUDFLARE_ONLY="${FIREWALL_CLOUDFLARE_ONLY:-no}"
  CLOUDFLARE_SOURCE="${CLOUDFLARE_SOURCE:-https://www.cloudflare.com}"
  [[ "$HOST" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$ ]] || die "HOST is not a valid host name"
  [[ "$ALT_HOST" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$ ]] || die "ALT_HOST is not a valid host name"
  [ "$HOST" != "$ALT_HOST" ] || die "HOST and ALT_HOST must differ (one redirects to the other)"
  [[ "$DB_NAME$DB_USER" =~ ^[A-Za-z0-9_]+$ ]] || die "DB_NAME and DB_USER may contain only letters, digits and underscores"
  [ -f "/usr/share/zoneinfo/$TIME_ZONE" ] || die "TIME_ZONE '$TIME_ZONE' is not an IANA zone (no default is assumed)"
  case "$ADMIN_USERNAME" in admin | administrator | root | ojs | webmaster | test | user | demo) die "REFUSED: '$ADMIN_USERNAME' is a default administrator name; choose another" ;; esac
  [[ "$ADMIN_USERNAME" =~ ^[A-Za-z0-9._-]{4,}$ ]] || die "ADMIN_USERNAME must be 4+ characters of letters, digits . _ -"
  case "$ADMIN_EMAIL$SMTP_USERNAME" in *.invalid*) die "REFUSED: an .invalid address is fake data and must not reach a server" ;; esac
  case "$AGE_RECIPIENT" in AGE-SECRET-KEY-*) die "REFUSED: AGE_RECIPIENT is a PRIVATE key; the server must hold only the public key" ;; age1*) ;; *) die "AGE_RECIPIENT must be an age public key (age1...)" ;; esac
  case "$CERT_METHOD" in origin | certbot) ;; *) die "CERT_METHOD must be origin or certbot" ;; esac
  if [ "$CERT_METHOD" = certbot ]; then
    [ -n "${CERTBOT_EMAIL:-}" ] || die "CERTBOT_EMAIL is required with CERT_METHOD=certbot"
    CERT_FULLCHAIN="/etc/letsencrypt/live/$HOST/fullchain.pem"; CERT_KEY="/etc/letsencrypt/live/$HOST/privkey.pem"
  else
    CERT_FULLCHAIN="${CERT_FULLCHAIN:-/etc/ssl/worj/fullchain.pem}"; CERT_KEY="${CERT_KEY:-/etc/ssl/worj/privkey.pem}"
  fi
  case "$WEBROOT$FILES_DIR" in *[!A-Za-z0-9/_.-]*) die "WEBROOT and FILES_DIR may contain only letters, digits and / _ . -" ;; esac
  case "$FILES_DIR/" in "$WEBROOT"/*) die "FILES_DIR must be OUTSIDE the web root" ;; esac
  # non-secret template values
  VALUES=""
  add_value HOST "$HOST"; add_value ALT_HOST "$ALT_HOST"; add_value WEBROOT "$WEBROOT"; add_value CERT_FULLCHAIN "$CERT_FULLCHAIN"; add_value CERT_KEY "$CERT_KEY"
  add_value PHP_SOCK /run/php/worj-fpm.sock; add_value SNIPPETS /etc/nginx/snippets/worj; add_value ERRORS_ROOT /usr/share/worj-errors; add_value ACME_ROOT /var/www/acme
  add_value REALIP_CONF /etc/nginx/worj-cloudflare-realip.conf; add_value HTTP_PORT 80; add_value HTTPS_PORT 443; add_value HSTS_MAX_AGE "$HSTS_MAX_AGE"
  add_value TIME_ZONE "$TIME_ZONE"; add_value INSTALL_DIR /usr/local/sbin
  ok "settings valid; no secret printed"
}

stage_packages() {
  ensure_packages nginx php8.3-fpm php8.3-cli php8.3-mysql php8.3-mbstring php8.3-xml php8.3-intl php8.3-curl php8.3-gd php8.3-zip php8.3-bcmath \
    mariadb-server certbot ufw unattended-upgrades openssl age rclone curl ca-certificates rsync logrotate
}

stage_php() {
  ensure_rendered "$ROOT/infra/php/99-worj.ini.template" /etc/php/8.3/fpm/conf.d/99-worj.ini 644 root:root
  ensure_rendered "$ROOT/infra/php/99-worj.ini.template" /etc/php/8.3/cli/conf.d/99-worj.ini 644 root:root
  ensure_copy "$ROOT/infra/php/worj-pool.conf" /etc/php/8.3/fpm/pool.d/worj.conf 644 root:root
  if [ -f /etc/php/8.3/fpm/pool.d/www.conf ]; then chg "disable the default pool www.conf"; [ "$CHECK" = 1 ] || mv /etc/php/8.3/fpm/pool.d/www.conf /etc/php/8.3/fpm/pool.d/www.conf.disabled; fi
  if [ "$STAGE_CHANGED" -gt 0 ] && [ "$CHECK" = 0 ]; then php-fpm8.3 -t >/dev/null 2>&1 || die "php-fpm configuration test failed (restore the .worj-bak files)"; fi
  svc_ensure php8.3-fpm; svc_reload php8.3-fpm
}

load_secrets() { # reads DB_PASSWORD from /etc/worj/secrets.env if it exists
  DB_PASSWORD=""; [ ! -f /etc/worj/secrets.env ] || load_env /etc/worj/secrets.env
}
stage_mariadb() {
  ensure_dir /etc/worj 700 root:root
  ensure_copy "$ROOT/infra/mariadb/60-worj.cnf" /etc/mysql/mariadb.conf.d/60-worj.cnf 644 root:root
  svc_ensure mariadb
  [ "$STAGE_CHANGED" -eq 0 ] || svc_reload mariadb
  load_secrets
  if [ -z "$DB_PASSWORD" ]; then
    chg "generate the database password into /etc/worj/secrets.env (mode 600; never printed)"
    if [ "$CHECK" = 0 ]; then DB_PASSWORD="$(gen_secret 24)"; printf 'DB_PASSWORD=%s\n' "$DB_PASSWORD" >/etc/worj/secrets.env; chmod 600 /etc/worj/secrets.env; fi
  else ok "database password already generated"; fi
  local have=""
  if [ "$CHECK" = 0 ] || mariadb -e 'select 1' >/dev/null 2>&1; then
    have="$(mariadb -N -e "select count(*) from mysql.user where user='$DB_USER' and host='localhost'" 2>/dev/null || echo 0)"
  fi
  if [ "${have:-0}" != 1 ]; then
    chg "create database $DB_NAME and user $DB_USER (password on standard input)"
    if [ "$CHECK" = 0 ]; then
      printf "CREATE DATABASE IF NOT EXISTS \`%s\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\nCREATE USER '%s'@'localhost' IDENTIFIED BY '%s';\nGRANT ALL PRIVILEGES ON \`%s\`.* TO '%s'@'localhost';\nFLUSH PRIVILEGES;\n" \
        "$DB_NAME" "$DB_USER" "$DB_PASSWORD" "$DB_NAME" "$DB_USER" | mariadb
    fi
  else ok "database user exists"; fi
}

stage_ojs_code() {
  [ -d "$OJS_SRC" ] || die "OJS_SRC not found: $OJS_SRC (run scripts/fetch-ojs.sh, then point OJS_SRC at ojs-core)"
  ensure_dir "$WEBROOT" 755 root:root
  ensure_dir "$FILES_DIR" 750 www-data:www-data
  local n=999
  if [ -d "$WEBROOT" ]; then n="$(rsync -a --delete --dry-run --itemize-changes --chown=root:root --exclude=/config.inc.php --exclude=/public/ --exclude=/cache/ --exclude=.git/ "$OJS_SRC/" "$WEBROOT/" | wc -l)"; fi
  if [ "$n" -gt 0 ]; then
    chg "sync the OJS code from $OJS_SRC to $WEBROOT ($n item(s))"
    [ "$CHECK" = 1 ] || rsync -a --delete --chown=root:root --exclude=/config.inc.php --exclude=/public/ --exclude=/cache/ --exclude=.git/ "$OJS_SRC/" "$WEBROOT/"
  else ok "OJS code in sync"; fi
  if [ -d "$THEME_SRC" ]; then
    n=999
    if [ -d "$WEBROOT/plugins/themes/worj" ]; then n="$(rsync -a --delete --dry-run --itemize-changes --chown=root:root "$THEME_SRC/" "$WEBROOT/plugins/themes/worj/" | wc -l)"; fi
    if [ "$n" -gt 0 ]; then chg "sync the worj theme ($n item(s))"; [ "$CHECK" = 1 ] || { mkdir -p "$WEBROOT/plugins/themes/worj"; rsync -a --delete --chown=root:root "$THEME_SRC/" "$WEBROOT/plugins/themes/worj/"; }; else ok "theme in sync"; fi
  fi
  ensure_dir "$WEBROOT/cache" 750 www-data:www-data
  ensure_dir "$WEBROOT/public" 750 www-data:www-data
}

ANSWERS_DIR="/root/.worj-provision"
cleanup_answers() { rm -rf -- "${ANSWERS_DIR:?}/answers" 2>/dev/null || true; }
trap cleanup_answers EXIT
stage_ojs_config() {
  local cfg="$WEBROOT/config.inc.php"
  load_secrets
  if [ "$CHECK" = 1 ]; then
    if [ -f "$cfg" ] && grep -q '^installed = On' "$cfg"; then
      ok "OJS is installed"
      if python3 -I "$ROOT/scripts/check-live-config.py" "$cfg" --host "$HOST" --web-root "$WEBROOT" --owner root:www-data >/dev/null 2>&1; then ok "live config check passes"; else chg "live config needs fixing (check-live-config.py lists what)"; fi
    else chg "render config.inc.php with generated secrets, run tools/install.php (answers file removed on exit), re-apply allowed_hosts and time_zone, verify with check-live-config.py"; fi
    return 0
  fi
  [ -n "$DB_PASSWORD" ] || die "no database password: run the mariadb stage first"
  if [ ! -f "$cfg" ]; then
    chg "render $cfg (secrets generated or read, never printed)"
    {
      printf '%s' "$VALUES"
      printf 'BASE_URL=https://%s\nHOSTNAME=%s\nDB_USER=%s\nDB_PASSWORD=%s\nDB_NAME=%s\nFILES_DIR=%s\n' "$HOST" "$HOST" "$DB_USER" "$DB_PASSWORD" "$DB_NAME" "$FILES_DIR"
      printf 'SALT=generate-me-at-provisioning\nAPI_KEY_SECRET=generate-me-at-provisioning\n'
      printf 'SMTP_SERVER=%s\nSMTP_PORT=%s\nSMTP_AUTH=%s\nSMTP_USERNAME=%s\nSMTP_PASSWORD=%s\nOAI_REPOSITORY_ID=%s\n' "$SMTP_SERVER" "$SMTP_PORT" "$SMTP_AUTH" "$SMTP_USERNAME" "$SMTP_PASSWORD" "$HOST"
    } | python3 -I "$ROOT/scripts/render-template.py" "$ROOT/ojs/config/config.inc.php.template" "$cfg" --mode 640 --owner root --group www-data --allow-unused >/dev/null
  fi
  if ! grep -q '^installed = On' "$cfg"; then
    chg "run the OJS CLI installer (answers file mode 600, deleted on exit; the admin password never reaches argv)"
    local pw="${ADMIN_PASSWORD:-}"
    if [ -z "$pw" ]; then
      [ -t 0 ] || die "no ADMIN_PASSWORD in $ENV_FILE and no terminal to prompt on"
      read -rsp "Initial administrator password (not shown): " pw; echo >&2
    fi
    [ "${#pw}" -ge 12 ] || die "the administrator password must have at least 12 characters"
    mkdir -p "$ANSWERS_DIR"; chmod 700 "$ANSWERS_DIR"
    # printf is a shell BUILTIN here: its arguments are not visible in /proc/*/cmdline
    printf '%s\n' en "" "$FILES_DIR" "$ADMIN_USERNAME" "$pw" "$pw" "$ADMIN_EMAIL" mysqli localhost "$DB_USER" "$DB_PASSWORD" "$DB_NAME" "$HOST" n y >"$ANSWERS_DIR/answers"
    pw=""
    if ! (cd "$WEBROOT" && php tools/install.php <"$ANSWERS_DIR/answers" >"$ANSWERS_DIR/install.log" 2>&1); then
      cleanup_answers; die "the OJS installer failed; its output is in $ANSWERS_DIR/install.log (mode 600, check it, then delete it)"
    fi
    cleanup_answers; rm -f "$ANSWERS_DIR/install.log"
    ok "installer finished; answers file removed"
  fi
  printf 'general.allowed_hosts=%s\ngeneral.time_zone="%s"\n' "'[\"$HOST\"]'" "$TIME_ZONE" |
    python3 -I "$ROOT/scripts/set-ojs-config.py" "$cfg" --generate-if-weak security.salt --generate-if-weak security.api_key_secret >"$ANSWERS_DIR.set.txt" 2>&1 || die "set-ojs-config.py failed"
  grep -q '^generated' "$ANSWERS_DIR.set.txt" && chg "generated salt / API key secret (never printed)"
  grep -q '^changed' "$ANSWERS_DIR.set.txt" && chg "re-applied allowed_hosts / time_zone after the installer"
  rm -f "$ANSWERS_DIR.set.txt"
  chown root:www-data "$cfg"; chmod 640 "$cfg"
  python3 -I "$ROOT/scripts/check-live-config.py" "$cfg" --host "$HOST" --web-root "$WEBROOT" --owner root:www-data || die "the live config check failed (above): fix before continuing"
}

stage_cloudflare_ip() {
  local out=/etc/nginx/worj-cloudflare-realip.conf rc=0
  local args=(--out "$out" --source "$CLOUDFLARE_SOURCE" --test-cmd "nginx -t" --no-reload)
  [ "$CHECK" = 0 ] || args+=(--check)
  local res
  res="$("$ROOT/scripts/update-cloudflare-ips.sh" "${args[@]}")" || rc=$?
  [ -z "$res" ] || say "  $res"
  case "$rc" in
    0) case "$res" in "would write"* | changed*) chg "Cloudflare ranges file $out" ;; esac ;;
    3) die "STOPPING: no Cloudflare IP ranges exist yet. Without them every visitor would look like a Cloudflare address (rate limits and logs would be useless). Fix the fetch and run this stage again." ;;
    *) die "the Cloudflare range refresh failed (exit $rc); the previous file, if any, was kept" ;;
  esac
}

stage_nginx() {
  ensure_dir /etc/nginx/snippets/worj 755 root:root
  ensure_dir /usr/share/worj-errors 755 root:root
  ensure_dir /var/www/acme 755 root:root
  ensure_copy "$ROOT/infra/nginx/errors/404.html" /usr/share/worj-errors/404.html 644 root:root
  ensure_copy "$ROOT/infra/nginx/errors/404.css" /usr/share/worj-errors/404.css 644 root:root
  local t
  if [ -f "$CERT_FULLCHAIN" ] && [ -f "$CERT_KEY" ]; then
    for t in "$ROOT"/infra/nginx/snippets/*.conf.template; do ensure_rendered "$t" "/etc/nginx/snippets/worj/$(basename "${t%.template}")" 644 root:root; done
    ensure_rendered "$ROOT/infra/nginx/worj.conf.template" /etc/nginx/conf.d/worj.conf 644 root:root
  else
    say "  certificate files not present yet: installing the port-80 bootstrap site only"
    ensure_rendered "$ROOT/infra/nginx/worj-bootstrap.conf.template" /etc/nginx/conf.d/worj.conf 644 root:root
  fi
  ensure_absent /etc/nginx/sites-enabled/default
  if [ "$STAGE_CHANGED" -gt 0 ] && [ "$CHECK" = 0 ]; then nginx -t >/dev/null 2>&1 || die "nginx -t failed: the previous files are kept as *.worj-bak next to each changed file; move them back to roll back"; fi
  svc_ensure nginx; svc_reload nginx
}

stage_certbot() {
  if [ "$CERT_METHOD" = origin ]; then
    if [ ! -f "$CERT_FULLCHAIN" ] || [ ! -f "$CERT_KEY" ]; then
      if [ "$CHECK" = 1 ]; then chg "REQUIRE the origin certificate and key at $CERT_FULLCHAIN and $CERT_KEY before the real run"; return 0; fi
      die "CERT_METHOD=origin: place the Cloudflare Origin CA certificate and key at $CERT_FULLCHAIN and $CERT_KEY (key mode 600), then run again"
    fi
    [ "$(stat -c '%a' "$CERT_KEY")" = 600 ] || die "$CERT_KEY must be mode 600"
    openssl x509 -in "$CERT_FULLCHAIN" -noout -checkend 2592000 >/dev/null || die "the certificate expires within 30 days or is unreadable"
    [ "$(openssl x509 -in "$CERT_FULLCHAIN" -noout -pubkey | openssl sha256)" = "$(openssl pkey -in "$CERT_KEY" -pubout | openssl sha256)" ] || die "the key does not match the certificate"
    ok "origin certificate present, valid for 30+ days, key matches"
    return 0
  fi
  if [ -f "$CERT_FULLCHAIN" ]; then ok "certificate present ($CERT_FULLCHAIN)"; return 0; fi
  chg "request a Let's Encrypt certificate for $HOST and $ALT_HOST (HTTP-01 webroot; needs DNS pointing here and the proxy set to DNS only)"
  [ "$CHECK" = 1 ] || certbot certonly --webroot -w /var/www/acme -d "$HOST" -d "$ALT_HOST" --email "$CERTBOT_EMAIL" --agree-tos --non-interactive --deploy-hook "systemctl reload nginx"
}

stage_unattended() {
  ensure_content /etc/apt/apt.conf.d/20auto-upgrades 644 root:root <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF
  ensure_content /etc/apt/apt.conf.d/52worj-unattended 644 root:root <<'CONF'
// Security updates only; no automatic reboot (a person schedules reboots).
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
CONF
  svc_ensure unattended-upgrades
}

stage_backup_cron() {
  load_secrets
  ensure_copy "$ROOT/scripts/backup.sh" /usr/local/sbin/worj-backup 755 root:root
  ensure_copy "$ROOT/scripts/update-cloudflare-ips.sh" /usr/local/sbin/worj-update-cloudflare-ips 755 root:root
  ensure_rendered "$ROOT/infra/cron.d/worj.template" /etc/cron.d/worj 644 root:root
  ensure_copy "$ROOT/infra/logrotate/worj" /etc/logrotate.d/worj 644 root:root
  ensure_dir /var/backups/worj 700 root:root
  ensure_content /etc/worj/backup.env 600 root:root <<CONF
WORJ_DB_NAME=$DB_NAME
WORJ_DB_DEFAULTS=/etc/worj/mysql-backup.cnf
WORJ_FILES_DIR=$FILES_DIR
WORJ_PUBLIC_DIR=$WEBROOT/public
WORJ_CONFIG=$WEBROOT/config.inc.php
WORJ_BACKUP_DIR=/var/backups/worj
WORJ_AGE_RECIPIENT=$AGE_RECIPIENT
WORJ_RCLONE_REMOTE=$RCLONE_REMOTE
WORJ_RETAIN_DAILY=14
WORJ_RETAIN_WEEKLY=8
CONF
  if [ -n "$DB_PASSWORD" ]; then
    printf '[client]\nuser=%s\npassword=%s\nhost=localhost\n' "$DB_USER" "$DB_PASSWORD" | ensure_content /etc/worj/mysql-backup.cnf 600 root:root
  elif [ "$CHECK" = 0 ]; then die "no database password to give the backup job: run the mariadb stage first"; fi
}

stage_firewall() { say "  not implemented in this commit (Phase 5 commit 10)"; }
stage_ssh() { say "  not implemented in this commit (Phase 5 commit 10; --confirm-ssh=$CONFIRM_SSH)"; }

# --------------------------------------------------------------------------------------------------------------
run_stage() { # name
  local fn="stage_${1//-/_}"
  [ "$1" != nginx-final ] || fn=stage_nginx
  [ "$1" != firewall ] || [ "$SKIP_FIREWALL" = 0 ] || { say "== stage: $1 (skipped: --skip-firewall)"; return 0; }
  [ "$1" != ssh ] || [ "$SKIP_SSH" = 0 ] || { say "== stage: $1 (skipped: --skip-ssh)"; return 0; }
  declare -F "$fn" >/dev/null || die "unknown stage: $1"
  STAGE_CHANGED=0
  say "== stage: $1"
  "$fn"
  say "   -> $([ "$STAGE_CHANGED" -eq 0 ] && echo unchanged || echo "changed: $STAGE_CHANGED")"
}

[ "${#STAGES[@]}" -gt 0 ] || STAGES=("${ALL_STAGES[@]}")
case " ${STAGES[*]} " in *" preflight "*) ;; *) STAGES=(preflight "${STAGES[@]}") ;; esac
[ "$CHECK" = 0 ] || say "CHECK MODE: nothing is changed; every action is printed as WOULD"
for st in "${STAGES[@]}"; do run_stage "$st"; done
say "changed: $TOTAL_CHANGED"
