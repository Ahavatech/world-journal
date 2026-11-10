#!/usr/bin/env bash
# Syntax and value checks for infra/php and infra/mariadb, run against the real tools in this sandbox.
#   scripts/test-infra-config.sh        needs php, php-fpm8.3 and mariadbd (not run by `make lint`; see `make infra-test`)
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
db_pid=""
cleanup() {
  [ -z "$db_pid" ] || { kill "$db_pid" 2>/dev/null; wait "$db_pid" 2>/dev/null; }
  rm -rf -- "${tmp:?}"
}
trap cleanup EXIT
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
eq() { [ "$1" = "$2" ]; }

# ---------- PHP ini
printf 'TIME_ZONE=UTC\n' | python3 -I "$root/scripts/render-template.py" "$root/infra/php/99-worj.ini.template" "$tmp/99-worj.ini" --mode 644 >/dev/null
warn="$(php -n -c "$tmp/99-worj.ini" -r 'echo "";' 2>&1)"
yes "php loads 99-worj.ini with no warning" eq "$warn" ""
for kv in memory_limit=256M upload_max_filesize=64M post_max_size=66M expose_php= display_errors= session.cookie_secure=1 session.cookie_httponly=1 date.timezone=UTC opcache.revalidate_freq=60; do
  k="${kv%%=*}"; v="${kv#*=}"
  got="$(php -n -c "$tmp/99-worj.ini" -d zend_extension=opcache -r "echo ini_get('$k');")"
  yes "ini $k = '$v'" eq "$got" "$v"
done
if printf '' | python3 -I "$root/scripts/render-template.py" "$root/infra/php/99-worj.ini.template" "$tmp/x.ini" >/dev/null 2>&1; then bad "template renders without a time zone"; else ok "the time zone is required (never assumed)"; fi

# ---------- PHP-FPM pool
if command -v php-fpm8.3 >/dev/null; then
  cat >"$tmp/fpm.conf" <<CFG
[global]
pid = $tmp/fpm.pid
error_log = $tmp/fpm.log
include = $root/infra/php/worj-pool.conf
CFG
  out="$(php-fpm8.3 -t -y "$tmp/fpm.conf" 2>&1)"; rc=$?
  yes "php-fpm8.3 -t accepts the worj pool (exit $rc)" eq "$rc" 0
  yes "php-fpm says: configuration test is successful" grep -q "test is successful" <<<"$out"
  printf '[worj]\nuser = nosuchuserxyz\ngroup = www-data\nlisten = /tmp/x.sock\npm = nonsense\n' >"$tmp/bad-pool.conf"
  sed -i "s#^include = .*#include = $tmp/bad-pool.conf#" "$tmp/fpm.conf"
  php-fpm8.3 -t -y "$tmp/fpm.conf" >/dev/null 2>&1; rc=$?
  yes "a broken pool is rejected by the same check (exit $rc)" test "$rc" != 0
else
  echo "SKIP  php-fpm8.3 not installed"
fi

# ---------- MariaDB: load the cnf in a throwaway server and read the variables back
if command -v mariadbd >/dev/null && command -v mariadb-install-db >/dev/null; then
  data="$tmp/data"; mkdir -p "$data" "$tmp/log"
  chown -R mysql:mysql "$tmp" 2>/dev/null; chmod 755 "$tmp"
  sed -e "s#/var/log/mysql/worj-slow.log#$tmp/log/slow.log#" "$root/infra/mariadb/60-worj.cnf" >"$tmp/60-worj.cnf"
  cat >"$tmp/my.cnf" <<CFG
!include $tmp/60-worj.cnf
[mysqld]
datadir = $data
socket = $tmp/db.sock
pid-file = $tmp/db.pid
port = 33991
bind-address = 127.0.0.1
log-error = $tmp/log/error.log
innodb_buffer_pool_size = 1G
CFG
  mariadb-install-db --no-defaults --user=mysql --datadir="$data" --auth-root-authentication-method=normal >"$tmp/log/install.log" 2>&1
  mariadbd --defaults-file="$tmp/my.cnf" --user=mysql >"$tmp/log/run.log" 2>&1 &
  db_pid=$!
  up=0; for _ in $(seq 1 40); do mariadb --no-defaults -uroot -S "$tmp/db.sock" -e 'select 1' >/dev/null 2>&1 && { up=1; break; }; sleep 0.5; done
  if [ "$up" = 1 ]; then
    q() { mariadb --no-defaults -uroot -S "$tmp/db.sock" -N -e "select @@$1"; }
    yes "mariadbd started with 60-worj.cnf" true
    yes "character_set_server = utf8mb4" eq "$(q character_set_server)" utf8mb4
    yes "collation_server = utf8mb4_unicode_ci" eq "$(q collation_server)" utf8mb4_unicode_ci
    yes "innodb_log_file_size = 256M" eq "$(q innodb_log_file_size)" 268435456
    yes "max_connections = 60" eq "$(q max_connections)" 60
    yes "local_infile = 0" eq "$(q local_infile)" 0
    yes "skip_name_resolve on" eq "$(q skip_name_resolve)" 1
    yes "bind_address = 127.0.0.1" eq "$(q bind_address)" 127.0.0.1
    yes "slow_query_log = 1" eq "$(q slow_query_log)" 1
  else
    bad "mariadbd did not start (see below)"; tail -5 "$tmp/log/error.log" 2>/dev/null; tail -3 "$tmp/log/run.log" 2>/dev/null
  fi
else
  echo "SKIP  mariadbd not installed"
fi

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "$fail FAILED"; fi
exit "$fail"
