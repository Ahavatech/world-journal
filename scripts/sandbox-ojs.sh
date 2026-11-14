#!/usr/bin/env bash
# Local OJS for development in a throwaway Ubuntu 24.04 container (no systemd).
# Installs PHP-FPM, MariaDB and nginx from apt, starts them by hand, and
# installs the pinned OJS from ojs-core/ into a scratch database.
#
# Usage: scripts/sandbox-ojs.sh [up|down|--check]
#   up       (default) install packages, start services, install OJS if needed
#   down     stop nginx, php-fpm and MariaDB
#   --check  print what would happen; change nothing
#
# Throwaway only: not a launch test, not for production. Credentials are
# generated into .env.sandbox (gitignored, mode 600) and never committed.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core="$root/ojs-core"
envfile="$root/.env.sandbox"
run="/run/worj-sandbox"
files_dir="/var/www/worj-sandbox-files"
port="${SANDBOX_PORT:-8082}"
pkgs=(php8.3-fpm php8.3-bcmath php8.3-mysql php8.3-mbstring php8.3-xml php8.3-intl
  php8.3-curl php8.3-gd php8.3-zip mariadb-server nginx)

mode="${1:-up}"
case "$mode" in up | down | --check) ;; *) echo "usage: $0 [up|down|--check]" >&2; exit 2 ;; esac

if [ "$mode" = "--check" ]; then
  echo "would apt-get install: ${pkgs[*]}"
  echo "would start mysqld_safe, php-fpm8.3 and nginx (own config in $run)"
  echo "would create database and user from $envfile (generated if absent)"
  echo "would write $core/config.inc.php settings and run tools/install.php"
  echo "would serve OJS at http://127.0.0.1:$port/"
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then echo "ERROR: run as root (container only)." >&2; exit 1; fi

if [ "$mode" = "down" ]; then
  if [ -f "$run/nginx.pid" ]; then nginx -c "$run/nginx.conf" -s stop 2>/dev/null || true; fi
  pkill -x php-fpm8.3 2>/dev/null || true
  mariadb-admin shutdown 2>/dev/null || true
  echo "sandbox stopped"
  exit 0
fi

if [ ! -f "$core/.worj-ojs-version" ]; then
  echo "ERROR: ojs-core/ missing; run 'make setup' first." >&2
  exit 1
fi

# --- packages
missing=()
for p in "${pkgs[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
if [ "${#missing[@]}" -gt 0 ]; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
fi

# --- credentials (generated once)
if [ ! -f "$envfile" ]; then
  umask 077
  {
    echo "SANDBOX_DB_NAME=ojs_sandbox"
    echo "SANDBOX_DB_USER=ojs_sandbox"
    echo "SANDBOX_DB_PASSWORD=$(openssl rand -hex 16)"
    echo "SANDBOX_ADMIN_USER=admin"
    echo "SANDBOX_ADMIN_PASSWORD=$(openssl rand -hex 10)"
    echo "SANDBOX_ADMIN_EMAIL=admin@example.invalid"
  } > "$envfile"
fi
# shellcheck source=/dev/null
source "$envfile"

# --- services
mkdir -p /run/mysqld "$run" /run/php "$files_dir"
chown mysql:mysql /run/mysqld
if ! mariadb -e 'select 1' >/dev/null 2>&1; then
  (nohup mysqld_safe --user=mysql >"$run/mysqld.log" 2>&1 &)
  for _ in $(seq 1 30); do mariadb -e 'select 1' >/dev/null 2>&1 && break; sleep 1; done
  mariadb -e 'select 1' >/dev/null
fi
pgrep -x php-fpm8.3 >/dev/null || php-fpm8.3 --daemonize

cat > "$run/nginx.conf" <<NGINX
user www-data;
pid $run/nginx.pid;
error_log $run/nginx-error.log;
events {}
http {
  access_log off;
  include /etc/nginx/mime.types;
  server {
    listen 127.0.0.1:$port;
    root $core;
    client_max_body_size 64m;
    index index.php;
    location ~ /\.(?!well-known) { deny all; }
    location ~ ^/(config\.inc\.php|config\.TEMPLATE\.inc\.php)\$ { deny all; }
    location / { try_files \$uri \$uri/ /index.php\$uri?\$query_string; }
    location ~ \.php(/|\$) {
      fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
      include /etc/nginx/fastcgi.conf;
      fastcgi_param PATH_INFO \$fastcgi_path_info;
      fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }
  }
}
NGINX
if [ -f "$run/nginx.pid" ] && kill -0 "$(cat "$run/nginx.pid")" 2>/dev/null; then
  nginx -c "$run/nginx.conf" -s reload
else
  nginx -c "$run/nginx.conf"
fi

# --- database
mariadb -e "CREATE DATABASE IF NOT EXISTS \`$SANDBOX_DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$SANDBOX_DB_USER'@'localhost' IDENTIFIED BY '$SANDBOX_DB_PASSWORD';
GRANT ALL ON \`$SANDBOX_DB_NAME\`.* TO '$SANDBOX_DB_USER'@'localhost';"

# --- OJS config and install
chown -R www-data:www-data "$files_dir"
if ! grep -q '^installed = On' "$core/config.inc.php"; then
  cp "$core/config.TEMPLATE.inc.php" "$core/config.inc.php"
  sed -i \
    -e "s#^base_url = .*#base_url = \"http://127.0.0.1:$port\"#" \
    -e 's#^restful_urls = .*#restful_urls = On#' \
    -e 's#^show_stacktrace = .*#show_stacktrace = On#' \
    "$core/config.inc.php"
  # Answers in the order tools/install.php prompts for them (verified in
  # ojs-core/lib/pkp/classes/cliTool/InstallTool.php for 3.5.0-6).
  printf '%s\n' \
    "en" "" "$files_dir" \
    "$SANDBOX_ADMIN_USER" "$SANDBOX_ADMIN_PASSWORD" "$SANDBOX_ADMIN_PASSWORD" "$SANDBOX_ADMIN_EMAIL" \
    "mysqli" "localhost" "$SANDBOX_DB_USER" "$SANDBOX_DB_PASSWORD" "$SANDBOX_DB_NAME" \
    "sandbox.invalid" "n" "y" \
    | php "$core/tools/install.php" | tail -5
fi
# The installer rewrites allowed_hosts to [""], which rejects every request.
sed -i "s#^allowed_hosts = .*#allowed_hosts = '[\"127.0.0.1\"]'#" "$core/config.inc.php"
# Register and enable the worj theme if its folder is linked into ojs-core/.
if [ -f "$core/plugins/themes/worj/version.xml" ]; then
  (cd "$core" && php lib/pkp/tools/installPluginVersion.php plugins/themes/worj/version.xml >/dev/null)
  mariadb "$SANDBOX_DB_NAME" -e "INSERT IGNORE INTO plugin_settings (plugin_name, context_id, setting_name, setting_value, setting_type) VALUES
    ('worjthemeplugin', NULL, 'enabled', '1', 'bool'), ('worjthemeplugin', 1, 'enabled', '1', 'bool');"
fi
# The Research Awards plugin: install its tables and enable it if its folder is linked into ojs-core/.
if [ -f "$core/plugins/generic/worjAwards/version.xml" ]; then
  (cd "$core" && php lib/pkp/tools/installPluginVersion.php plugins/generic/worjAwards/version.xml >/dev/null)
  mariadb "$SANDBOX_DB_NAME" -e "INSERT IGNORE INTO plugin_settings (plugin_name, context_id, setting_name, setting_value, setting_type) VALUES ('worjawardsplugin', 1, 'enabled', '1', 'bool');"
fi
# Fresh journals do not enable the Make a Submission block plugin; enable it so
# the sidebar states can be tested. (Task 4.1 covers this for the real journal.)
mariadb "$SANDBOX_DB_NAME" -e "INSERT IGNORE INTO plugin_settings (plugin_name, context_id, setting_name, setting_value, setting_type) VALUES
  ('makesubmissionblockplugin', NULL, 'enabled', '1', 'bool'), ('makesubmissionblockplugin', 1, 'enabled', '1', 'bool');"
mkdir -p "$core/cache" "$core/public"
chmod -R a+rwX "$core/cache" "$core/public"

echo "sandbox up: http://127.0.0.1:$port/  (admin credentials in .env.sandbox)"
echo "next: node scripts/sandbox-seed.js  (journal + theme; needs Playwright)"
