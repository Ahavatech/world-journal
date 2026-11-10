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
  command -v python3 >/dev/null || die "python3 is required by this script (cloud images have it): sudo apt-get install -y python3"
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
  for v in HOST ALT_HOST TIME_ZONE ROBOTS_MODE OPERATOR_USER ADMIN_USERNAME ADMIN_EMAIL SMTP_SERVER SMTP_PORT SMTP_AUTH SMTP_USERNAME SMTP_PASSWORD AGE_RECIPIENT RCLONE_REMOTE CERT_METHOD; do
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
  case "$ROBOTS_MODE" in staging) ROBOTS_TAG="noindex, nofollow" ;; production) ROBOTS_TAG="" ;; *) die "ROBOTS_MODE must be staging or production (no default: a forgotten staging site gets indexed, a forgotten noindex hides the live one)" ;; esac
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
  add_value REALIP_CONF /etc/nginx/worj-cloudflare-realip.conf; add_value HTTP_PORT 80; add_value HTTPS_PORT 443; add_value HSTS_MAX_AGE "$HSTS_MAX_AGE"; add_value ROBOTS_TAG "$ROBOTS_TAG"
  add_value TIME_ZONE "$TIME_ZONE"; add_value INSTALL_DIR /usr/local/sbin
  ok "settings valid; no secret printed"
}

stage_packages() {
  ensure_packages python3 nginx php8.3-fpm php8.3-cli php8.3-mysql php8.3-mbstring php8.3-xml php8.3-intl php8.3-curl php8.3-gd php8.3-zip php8.3-bcmath \
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
  if [ -d "$WEBROOT" ]; then n="$(rsync -a --delete --dry-run --itemize-changes --chown=root:root --exclude=/config.inc.php --exclude=/public/ --exclude=/cache/ --exclude=.git/ --exclude=/plugins/themes/worj "$OJS_SRC/" "$WEBROOT/" | wc -l)"; fi
  if [ "$n" -gt 0 ]; then
    chg "sync the OJS code from $OJS_SRC to $WEBROOT ($n item(s))"
    [ "$CHECK" = 1 ] || rsync -a --delete --chown=root:root --exclude=/config.inc.php --exclude=/public/ --exclude=/cache/ --exclude=.git/ --exclude=/plugins/themes/worj "$OJS_SRC/" "$WEBROOT/"
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
cleanup_answers() { rm -rf -- "${ANSWERS_DIR:?}/answers" "${ANSWERS_DIR:?}/install.log" 2>/dev/null || true; rmdir "$ANSWERS_DIR" 2>/dev/null || true; }
trap cleanup_answers EXIT
stage_ojs_config() {
  local cfg="$WEBROOT/config.inc.php"
  load_secrets
  if [ "$CHECK" = 1 ]; then
    if [ -f "$cfg" ] && grep -q '^installed = On' "$cfg"; then
      ok "OJS is installed"
      if python3 -I "$ROOT/scripts/check-live-config.py" "$cfg" --host "$HOST" --web-root "$WEBROOT" --owner root:www-data >/dev/null 2>&1; then ok "live config check passes"; else chg "live config needs fixing (check-live-config.py lists what)"; fi
      if grep -q '^ADMIN_PASSWORD=' "$ENV_FILE"; then chg "remove the initial ADMIN_PASSWORD line from $ENV_FILE"; fi
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
      rm -f "$ANSWERS_DIR/answers"; die "the OJS installer failed; its output is in $ANSWERS_DIR/install.log (mode 600, check it, then delete the directory)"
    fi
    cleanup_answers
    # first login must change the initial password (OJS then redirects to the change-password form)
    printf "UPDATE \`%s\`.users SET must_change_password=1 WHERE username='%s';\n" "$DB_NAME" "$ADMIN_USERNAME" | mariadb
    chg "the administrator must change the initial password at the first login"
    # the installer ran as root: the web server's user must be able to write its cache and public files
    chown -R www-data:www-data "$WEBROOT/cache" "$WEBROOT/public" "$FILES_DIR"
    ok "installer finished; answers file removed"
  fi
  printf 'general.allowed_hosts=%s\ngeneral.time_zone="%s"\n' "'[\"$HOST\"]'" "$TIME_ZONE" |
    python3 -I "$ROOT/scripts/set-ojs-config.py" "$cfg" --generate-if-weak security.salt --generate-if-weak security.api_key_secret >"$ANSWERS_DIR.set.txt" 2>&1 || die "set-ojs-config.py failed"
  grep -q '^generated' "$ANSWERS_DIR.set.txt" && chg "generated salt / API key secret (never printed)"
  grep -q '^changed' "$ANSWERS_DIR.set.txt" && chg "re-applied allowed_hosts / time_zone after the installer"
  rm -f "$ANSWERS_DIR.set.txt"
  chown root:www-data "$cfg"; chmod 640 "$cfg"
  if grep -q '^ADMIN_PASSWORD=' "$ENV_FILE"; then
    chg "remove the initial ADMIN_PASSWORD line from $ENV_FILE (the password is now only a hash in the database)"
    local keep; keep="$(mktemp "$ENV_FILE.XXXXXX")"
    grep -v '^ADMIN_PASSWORD=' "$ENV_FILE" >"$keep" || true
    chown root:root "$keep"; chmod 600 "$keep"; mv -f "$keep" "$ENV_FILE"
  fi
  python3 -I "$ROOT/scripts/check-live-config.py" "$cfg" --host "$HOST" --web-root "$WEBROOT" --owner root:www-data || die "the live config check failed (above): fix before continuing"
}

stage_cloudflare_ip() {
  local out=/etc/nginx/worj-cloudflare-realip.conf rc=0
  # `nginx -t` is only a meaningful test once our site includes the file; on the first run nothing includes it yet
  # (and a stock Ubuntu default site can fail the test for unrelated reasons, for example no IPv6)
  local testcmd="true"
  if grep -qs 'worj-cloudflare-realip' /etc/nginx/conf.d/worj.conf; then testcmd="nginx -t"; fi
  local args=(--out "$out" --source "$CLOUDFLARE_SOURCE" --test-cmd "$testcmd" --no-reload)
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
  ensure_rendered "$ROOT/infra/robots/robots-$ROBOTS_MODE.txt.template" /usr/share/worj-errors/robots.txt 644 root:root
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
  # the cron job runs as www-data and appends here
  if [ ! -f /var/log/worj-scheduler.log ] || [ "$(stat -c '%U:%G %a' /var/log/worj-scheduler.log)" != "www-data:adm 640" ]; then
    chg "create /var/log/worj-scheduler.log (www-data:adm 640)"
    [ "$CHECK" = 1 ] || { touch /var/log/worj-scheduler.log; chown www-data:adm /var/log/worj-scheduler.log 2>/dev/null || chown www-data:www-data /var/log/worj-scheduler.log; chmod 640 /var/log/worj-scheduler.log; }
  fi
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

# ---- safety timers ("dead-man"): a change that could lock the operator out reverts itself after 10 minutes
# unless --confirm-ssh is run from a SECOND terminal that logged in successfully with the key.
DEADMAN_MINUTES=10
deadman() { # schedule NAME MINUTES COMMAND | cancel NAME | pending NAME
  if [ -n "${WORJ_DEADMAN_HOOK:-}" ]; then "$WORJ_DEADMAN_HOOK" "$@"; return; fi   # test-only: no systemd in the sandbox
  case "$1" in
    schedule) systemd-run --quiet --unit="$2" --on-active="${3}min" /bin/sh -c "$4" ;;
    cancel) systemctl stop "$2.timer" 2>/dev/null || true ;;
    pending) systemctl is-active --quiet "$2.timer" 2>/dev/null ;;
  esac
}
SSH_DROPIN=/etc/ssh/sshd_config.d/00-worj.conf

in_ssh_session() { # true if this process was started from an ssh login
  [ -z "${WORJ_TEST_SSH_SESSION:-}" ] || return 0
  local pid=$$ comm
  while [ "$pid" -gt 1 ]; do
    comm="$(cat "/proc/$pid/comm" 2>/dev/null || true)"
    case "$comm" in sshd*) return 0 ;; esac
    pid="$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null || echo 1)"
  done
  return 1
}
ssh_session_port() { # the local port of the current ssh connection, or empty
  [ -z "${WORJ_TEST_SSH_PORT:-}" ] || { echo "$WORJ_TEST_SSH_PORT"; return; }
  [ -z "${SSH_CONNECTION:-}" ] || { echo "$SSH_CONNECTION" | awk '{print $4}'; return; }
  echo ""
}
recent_key_login() { # user
  local u="$1" log="${WORJ_AUTHLOG:-}"
  if [ -n "$log" ]; then grep -q "Accepted publickey for $u " "$log" 2>/dev/null; return; fi
  { journalctl -u ssh -u sshd --since "7 days ago" --no-pager 2>/dev/null; cat /var/log/auth.log 2>/dev/null; } | grep -q "Accepted publickey for $u "
}

stage_firewall() {
  command -v ufw >/dev/null || { [ "$CHECK" = 1 ] && { chg "install ufw (package stage)"; return 0; }; die "ufw is not installed (run the packages stage)"; }
  local want=() line r
  want+=("ufw allow $SSH_PORT/tcp")
  if [ "$FIREWALL_CLOUDFLARE_ONLY" = yes ]; then
    local cf=/etc/nginx/worj-cloudflare-realip.conf
    [ -f "$cf" ] || die "FIREWALL_CLOUDFLARE_ONLY=yes needs $cf (run the cloudflare-ip stage first): without the ranges 80 and 443 would be closed to everyone"
    while IFS= read -r line; do
      # IPv4 only: the origin listens on IPv4 only (Cloudflare connects over IPv4), and ufw refuses IPv6 rules when IPv6 is off
      case "$line" in "set_real_ip_from "*:*) ;; "set_real_ip_from "*) r="${line#set_real_ip_from }"; r="${r%;}"; want+=("ufw allow from $r to any port 80 proto tcp" "ufw allow from $r to any port 443 proto tcp") ;; esac
    done <"$cf"
    [ "${#want[@]}" -gt 3 ] || die "no Cloudflare ranges found in $cf"
  else
    want+=("ufw allow 80/tcp" "ufw allow 443/tcp")
  fi
  local have; have="$(ufw show added 2>/dev/null | grep '^ufw ' || true)"
  # defaults: deny incoming, allow outgoing
  if ! grep -q '^DEFAULT_INPUT_POLICY="DROP"' /etc/default/ufw 2>/dev/null; then chg "ufw default deny incoming"; [ "$CHECK" = 1 ] || ufw default deny incoming >/dev/null; fi
  if ! grep -q '^DEFAULT_OUTPUT_POLICY="ACCEPT"' /etc/default/ufw 2>/dev/null; then chg "ufw default allow outgoing"; [ "$CHECK" = 1 ] || ufw default allow outgoing >/dev/null; fi
  # SSH rule FIRST, then the web rules (a half-applied run must never leave SSH closed)
  for r in "${want[@]}"; do
    if ! grep -qxF "$r" <<<"$have"; then chg "$r"; [ "$CHECK" = 1 ] || ${r} >/dev/null; fi
  done
  # rules this script manages but no longer wants (for example after switching FIREWALL_CLOUDFLARE_ONLY)
  local wanted; wanted="$(printf '%s\n' "${want[@]}")"   # here-string below: a pipe into grep -q would SIGPIPE under pipefail
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      "ufw allow 80/tcp" | "ufw allow 443/tcp" | "ufw allow from "*" port 80 proto tcp" | "ufw allow from "*" port 443 proto tcp")
        grep -qxF -- "$line" <<<"$wanted" || { chg "remove ${line#ufw allow }"; if [ "$CHECK" = 0 ]; then read -ra parts <<<"${line#ufw }"; ufw --force delete "${parts[@]}" >/dev/null; fi; } ;;
    esac
  done <<<"$have"
  if ufw status 2>/dev/null | head -1 | grep -q 'Status: active'; then ok "firewall active"; return 0; fi
  # about to enable: the SSH rule must exist and match the port of THIS session, or we could cut our own branch
  if [ "$CHECK" = 1 ]; then chg "enable the firewall with a $DEADMAN_MINUTES-minute revert timer (cancel with --confirm-ssh after a second login works)"; return 0; fi
  ufw show added | grep -qxF "ufw allow $SSH_PORT/tcp" || die "REFUSED to enable the firewall: no allow rule for SSH port $SSH_PORT"
  local sp; sp="$(ssh_session_port)"
  if [ -n "$sp" ] && [ "$sp" != "$SSH_PORT" ]; then die "REFUSED to enable the firewall: this session is on port $sp but SSH_PORT is $SSH_PORT"; fi
  deadman schedule worj-firewall-revert "$DEADMAN_MINUTES" "/usr/sbin/ufw --force disable"
  chg "enable the firewall (a $DEADMAN_MINUTES-minute timer will disable it again unless you run --confirm-ssh)"
  ufw --force enable >/dev/null
  say "  NOW: open a SECOND terminal, log in again (ssh), then run:  sudo $0 --env $ENV_FILE --os $OS_ANSWER --confirm-ssh"
}

stage_ssh() {
  local home keys fp n
  getent passwd "$OPERATOR_USER" >/dev/null || die "OPERATOR_USER '$OPERATOR_USER' does not exist"
  home="$(getent passwd "$OPERATOR_USER" | cut -d: -f6)"; keys="$home/.ssh/authorized_keys"
  if [ "$CHECK" = 1 ]; then
    chg "REQUIRE: $OPERATOR_USER exists, has sudo, valid keys in $keys, and this session is that user's ssh login with a recent 'Accepted publickey'"
    chg "write $SSH_DROPIN (no passwords, no root login, publickey only), run sshd -t, schedule a $DEADMAN_MINUTES-minute revert, reload ssh (not restart)"
    return 0
  fi
  # --- every precondition, before any change ---
  id -nG "$OPERATOR_USER" | tr ' ' '\n' | grep -qxE 'sudo|wheel' || die "REFUSED: $OPERATOR_USER is not in the sudo group (root login is about to be disabled)"
  [ -s "$keys" ] || die "REFUSED: $keys does not exist or is empty: key-only login would lock everyone out"
  if [ $((0$(stat -c '%a' "$home/.ssh") & 022)) -ne 0 ] || [ $((0$(stat -c '%a' "$keys") & 022)) -ne 0 ]; then die "REFUSED: $home/.ssh and $keys must not be group or world writable (sshd would ignore the keys)"; fi
  n=0
  while IFS= read -r line; do
    case "$line" in '' | '#'*) continue ;; esac
    fp="$(printf '%s\n' "$line" | ssh-keygen -l -f - 2>/dev/null || true)"
    [ -z "$fp" ] || n=$((n + 1))
  done <"$keys"
  [ "$n" -ge 1 ] || die "REFUSED: no valid public key found in $keys (ssh-keygen could not read one)"
  [ "${SUDO_USER:-}" = "$OPERATOR_USER" ] || die "REFUSED: run this as $OPERATOR_USER through sudo (SUDO_USER is '${SUDO_USER:-}')"
  in_ssh_session || die "REFUSED: this is not an ssh login session; run it from the ssh session you will keep open"
  recent_key_login "$OPERATOR_USER" || die "REFUSED: no recent 'Accepted publickey for $OPERATOR_USER' in the ssh log: log in once with your KEY first (a password login does not count)"
  ok "$OPERATOR_USER: sudo, $n valid key(s), a key login in the log, this is an ssh session"
  local want; want="$(printf '%s\n' "# World Open Research Journal: key-only SSH. The 00- prefix makes these values win over later files" \
    "# (sshd takes the FIRST value it reads; cloud images often ship 50-cloud-init.conf with PasswordAuthentication yes)." \
    "PasswordAuthentication no" "KbdInteractiveAuthentication no" "PermitRootLogin no" "PermitEmptyPasswords no" "PubkeyAuthentication yes" \
    "AuthenticationMethods publickey" "MaxAuthTries 3" "LoginGraceTime 30" "X11Forwarding no")"
  local cur=""; [ ! -f "$SSH_DROPIN" ] || cur="$(cat "$SSH_DROPIN")"
  if [ "$cur" = "$want" ]; then
    if deadman pending worj-ssh-revert; then say "  PENDING: the ssh change is waiting for --confirm-ssh (it will revert on its own otherwise)"; else ok "ssh already key-only and confirmed"; fi
  else
    chg "write $SSH_DROPIN"
    mkdir -p "$(dirname "$SSH_DROPIN")"
    [ ! -f "$SSH_DROPIN" ] || cp -p "$SSH_DROPIN" "$SSH_DROPIN.worj-bak"
    printf '%s\n' "$want" >"$SSH_DROPIN"; chmod 644 "$SSH_DROPIN"
    if ! sshd -t 2>"$ANSWERS_DIR.sshd.err"; then
      rm -f "$SSH_DROPIN"; [ ! -f "$SSH_DROPIN.worj-bak" ] || mv "$SSH_DROPIN.worj-bak" "$SSH_DROPIN"
      die "sshd -t rejected the new configuration; it was removed again: $(head -c 200 "$ANSWERS_DIR.sshd.err" | tr '\n' ' ')"
    fi
    rm -f "$ANSWERS_DIR.sshd.err"
    local eff; eff="$(sshd -T 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    for kv in "passwordauthentication no" "kbdinteractiveauthentication no" "permitrootlogin no" "authenticationmethods publickey"; do
      grep -qxF "$kv" <<<"$eff" || { rm -f "$SSH_DROPIN"; die "the effective sshd setting '$kv' is not in force (another file wins?): the change was removed again"; }
    done
    ok "sshd -t passed and the effective settings are key-only"
    deadman schedule worj-ssh-revert "$DEADMAN_MINUTES" "rm -f $SSH_DROPIN; systemctl reload ssh"
    if [ "${SKIP_SERVICES:-0}" = 1 ]; then say "  skipped (--skip-services): reload ssh"; else systemctl reload ssh || systemctl reload sshd; fi
    say "  NOW: open a SECOND terminal and log in with your KEY. If it works run:  sudo $0 --env $ENV_FILE --os $OS_ANSWER --confirm-ssh"
    say "  If it does not work, do nothing: in $DEADMAN_MINUTES minutes the change reverts by itself. (Out-of-band rescue: the provider's browser console.)"
  fi
}

stage_confirm() {
  deadman cancel worj-ssh-revert; deadman cancel worj-firewall-revert
  say "  confirmed: the ssh and firewall safety timers are cancelled"
}

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

if [ "$CONFIRM_SSH" = 1 ]; then
  stage_preflight >/dev/null
  say "== confirm"; stage_confirm; say "changed: 0"; exit 0
fi
[ "${#STAGES[@]}" -gt 0 ] || STAGES=("${ALL_STAGES[@]}")
case " ${STAGES[*]} " in *" preflight "*) ;; *) STAGES=(preflight "${STAGES[@]}") ;; esac
[ "$CHECK" = 0 ] || say "CHECK MODE: nothing is changed; every action is printed as WOULD"
for st in "${STAGES[@]}"; do run_stage "$st"; done
say "changed: $TOTAL_CHANGED"
