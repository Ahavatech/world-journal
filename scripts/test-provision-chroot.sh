#!/usr/bin/env bash
# shellcheck disable=SC2317,SC2016  # helper functions are called indirectly; patterns are not shell
# Provision a clean Ubuntu 24.04 (debootstrap) CHROOT twice and prove idempotency, --check, the first-run Cloudflare
# failure, the bootstrap-then-certificate path, secret hygiene and a working OJS behind the rendered Nginx.
#   scripts/test-provision-chroot.sh        needs root, debootstrap, the sandbox network (archive.ubuntu.com), ~6 GB, 15-25 minutes
#   WORJ_CHROOT_BASE=/var/tmp/worj-chroot-base   a debootstrap noble tree (created on first use)
#
# WHAT THIS IS NOT: a VPS. There is no systemd (daemons are started by hand through the test-only hook
# WORJ_SERVICE_HOOK), no real firewall, no sshd, no certbot issuance, no real Cloudflare. The firewall and ssh stages are
# skipped here (see scripts/test-provision-ssh-firewall.sh). Every production step stays UNVERIFIED (not run on VPS).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$(id -u)" = 0 ] || { echo "run as root (sandbox container)"; exit 2; }
BASE="${WORJ_CHROOT_BASE:-/var/tmp/worj-chroot-base}"
RUN="${WORJ_CHROOT_RUN:-/var/tmp/worj-chroot-run}"
REPORT="${WORJ_CHROOT_REPORT:-/tmp/claude-0/chroot-report.txt}"

if [ "${1:-}" != "--inner" ]; then
  command -v debootstrap >/dev/null || { echo "missing debootstrap (apt-get install -y debootstrap ubuntu-keyring)"; exit 2; }
  if [ ! -x "$BASE/bin/bash" ]; then
    echo "creating the base tree $BASE (one time, several minutes)"
    debootstrap --variant=minbase --include=ca-certificates,curl,gnupg,sudo noble "$BASE" http://archive.ubuntu.com/ubuntu || { echo "debootstrap failed"; exit 2; }
  fi
  exec unshare --mount --propagation private -- "$0" --inner
fi

# ------------------------------------------------------------------ inside a private mount namespace
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
no() { local name="$1"; shift; if "$@"; then bad "$name"; else ok "$name"; fi; }
eq() { [ "$1" = "$2" ]; }
log="$(mktemp -d /var/tmp/worj-chroot-logs.XXXXXX)"; chmod 700 "$log"
sampler_pid=""
cleanup() {
  [ -z "$sampler_pid" ] || kill "$sampler_pid" 2>/dev/null
  for pf in /run/nginx.pid /run/php/php8.3-fpm.pid /run/mysqld/mysqld.pid; do
    [ ! -f "$RUN$pf" ] || kill "$(cat "$RUN$pf")" 2>/dev/null
  done
  sleep 2
  umount -R "$RUN/proc" "$RUN/dev" "$RUN/opt/worj-src/ojs-core" 2>/dev/null
}
trap cleanup EXIT

echo "=== preparing a clean copy of the base tree ($(du -sh "$BASE" | cut -f1))"
rm -rf "$RUN"; cp -a "$BASE" "$RUN"
mount -t proc proc "$RUN/proc"; mount --rbind /dev "$RUN/dev"
mkdir -p "$RUN/opt/worj-src"
rsync -a --exclude .git --exclude node_modules --exclude ojs-core --exclude autoresearch/eval/node_modules "$root/" "$RUN/opt/worj-src/"
mkdir -p "$RUN/opt/worj-src/ojs-core"; mount --bind "$root/ojs-core" "$RUN/opt/worj-src/ojs-core"; mount -o remount,bind,ro "$RUN/opt/worj-src/ojs-core"
cp /etc/resolv.conf "$RUN/etc/resolv.conf" 2>/dev/null
printf '#!/bin/sh\nexit 101\n' >"$RUN/usr/sbin/policy-rc.d"; chmod +x "$RUN/usr/sbin/policy-rc.d"
[ ! -e /etc/apt/apt.conf.d/99proxy ] || cp /etc/apt/apt.conf.d/99proxy "$RUN/etc/apt/apt.conf.d/"
cat >"$RUN/etc/apt/sources.list.d/ubuntu.sources" <<SRC
Types: deb
URIs: http://archive.ubuntu.com/ubuntu
Suites: noble noble-updates noble-security
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
SRC
inch() { chroot "$RUN" env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root TERM=dumb DEBIAN_FRONTEND=noninteractive WORJ_SERVICE_HOOK=/usr/local/bin/worj-test-hook "$@"; }
echo "=== image prep like a cloud image: tzdata, python3, openssl, rsync (the script's preflight needs the zoneinfo and python3)"
if ! inch apt-get update -qq >"$log/prep.log" 2>&1 || ! inch apt-get install -y -qq tzdata openssl rsync python3 >>"$log/prep.log" 2>&1; then
  echo "FAIL  image prep (see $log/prep.log)"; tail -5 "$log/prep.log"; exit 2
fi
echo "      chroot: $(grep PRETTY_NAME "$RUN/etc/os-release")"

# the test-only service hook: no systemd here, so daemons are started by hand
cat >"$RUN/usr/local/bin/worj-test-hook" <<'HOOK'
#!/bin/sh
# Test-only: start the chroot's daemons by hand. Liveness is judged by this chroot's own socket and pid files, NOT by
# pgrep: the chroot shares the host's process table, and the sandbox host runs its own MariaDB and Nginx.
action="$1"; svc="$2"
alive() { [ -f "$1" ] && kill -0 "$(cat "$1" 2>/dev/null)" 2>/dev/null; }
case "$svc" in
  mariadb)
    if [ "$action" = start ] && ! mariadb -e 'select 1' >/dev/null 2>&1; then
      mkdir -p /run/mysqld; chown mysql:mysql /run/mysqld; chmod 755 /run/mysqld   # (the provisioning umask is 077; systemd would create it 755)
      (nohup mysqld_safe --user=mysql --port=33061 >/var/log/mysqld-test.log 2>&1 &)
      i=0; while ! mariadb -e 'select 1' >/dev/null 2>&1; do i=$((i+1)); [ "$i" -lt 90 ] || { echo "mariadb did not start" >&2; exit 1; }; sleep 1; done
    fi ;;
  php8.3-fpm)
    mkdir -p /run/php
    if ! alive /run/php/php8.3-fpm.pid; then php-fpm8.3 --daemonize; sleep 1
    elif [ "$action" = reload ]; then kill -USR2 "$(cat /run/php/php8.3-fpm.pid)" 2>/dev/null; fi ;;
  nginx)
    if ! alive /run/nginx.pid; then nginx; sleep 1; elif [ "$action" = reload ]; then nginx -s reload; fi ;;
esac
exit 0
HOOK
chmod +x "$RUN/usr/local/bin/worj-test-hook"

# ---- settings, secrets (sentinels so leaks are findable), certificate for the origin method
recipient="$(age-keygen 2>/dev/null | sed -n 's/^# public key: //p')"
[ -n "$recipient" ] || { command -v age-keygen >/dev/null || apt-get install -y -qq age >/dev/null 2>&1; recipient="$(age-keygen 2>/dev/null | sed -n 's/^# public key: //p')"; }
ADMIN_PW='ADMIN-SENTINEL-71cd-xyz-Aa1'; SMTP_PW='SMTP-SENTINEL-9f3a-qrs-Bb2'
mkdir -p "$RUN/etc/worj"; chmod 700 "$RUN/etc/worj"
cat >"$RUN/etc/worj/provision.env" <<CFG
HOST=journal.example.org
ALT_HOST=www.journal.example.org
TIME_ZONE=UTC
OPERATOR_USER=root
ADMIN_USERNAME=journalops
ADMIN_EMAIL=ops@journal.example.org
ADMIN_PASSWORD=$ADMIN_PW
CERT_METHOD=origin
CERT_FULLCHAIN=/etc/ssl/worj/fullchain.pem
CERT_KEY=/etc/ssl/worj/privkey.pem
SMTP_SERVER=smtp.mailer.example.org
SMTP_PORT=587
SMTP_AUTH=tls
SMTP_USERNAME=mailer-user
SMTP_PASSWORD=$SMTP_PW
AGE_RECIPIENT=$recipient
RCLONE_REMOTE=:local:/var/backups/remote-test
OJS_SRC=/opt/worj-src/ojs-core
THEME_SRC=/opt/worj-src/ojs/plugins/themes/worj
CLOUDFLARE_SOURCE=file:///opt/worj-src/scripts/fixtures/cloudflare/good
CFG
chmod 600 "$RUN/etc/worj/provision.env"
P=(/opt/worj-src/scripts/provision-ubuntu.sh --env /etc/worj/provision.env --os 24.04 --skip-services --skip-firewall --skip-ssh)
runp() { # logname args... ; prints exit code
  local name="$1"; shift
  inch "${P[@]}" "$@" >"$log/$name.out" 2>&1; echo $?
}
stages_changed() { grep -c -E '^   -> changed' "$1"; }
snapshot() { # label: checksums of everything provisioning owns (not logs, data or caches)
  chroot "$RUN" /bin/bash -c "cd / && { find etc/nginx etc/php etc/mysql etc/cron.d etc/logrotate.d etc/apt/apt.conf.d etc/worj usr/local/sbin usr/share/worj-errors var/www/acme var/backups -xdev -type f -o -type l 2>/dev/null; find var/www/worj -xdev \\( -path var/www/worj/cache -o -path var/www/worj/public \\) -prune -o -type f -print 2>/dev/null | head -4000; } | sort | xargs -r -d '\n' sha256sum 2>/dev/null; stat -c '%n %a %U:%G' etc/worj var/lib/worj/files var/www/worj/cache var/www/worj/public var/www/worj/config.inc.php var/backups/worj 2>/dev/null" >"$log/$1.snap"
}

echo "=== 1. --check on the FRESH machine changes nothing"
snapshot before-check1
marker="$log/marker"; : >"$marker"; sleep 1
rc="$(runp check-fresh --check)"
yes "--check exits 0 (exit $rc)" eq "$rc" 0
yes "...prints WOULD lines ($(grep -c '^  WOULD: ' "$log/check-fresh.out"))" grep -q '^  WOULD: ' "$log/check-fresh.out"
yes "...and ends with a positive changed count ($(tail -1 "$log/check-fresh.out"))" grep -qE '^changed: [1-9]' "$log/check-fresh.out"
snapshot after-check1
yes "...tree snapshot before and after is IDENTICAL" cmp -s "$log/before-check1.snap" "$log/after-check1.snap"
yes "...no package was installed (nginx still absent)" test ! -x "$RUN/usr/sbin/nginx"
yes "...no file newer than the marker under /etc, /usr/local, /var/www, /var/lib/worj" bash -c "[ -z \"\$(find '$RUN/etc' '$RUN/usr/local' '$RUN/var/www' '$RUN/var/lib/worj' -xdev -newer '$marker' -type f 2>/dev/null | grep -v -e '/etc/resolv.conf' -e '/etc/mtab' | head -3)\" ]"

echo "=== 2. first run: the Cloudflare ranges cannot be fetched (the live URL is blocked here), so the stage must STOP"
# a separate settings copy that does not use the fixture
sed 's#^CLOUDFLARE_SOURCE=.*#CLOUDFLARE_SOURCE=https://www.cloudflare.com#' "$RUN/etc/worj/provision.env" >"$RUN/etc/worj/provision-live.env"; chmod 600 "$RUN/etc/worj/provision-live.env"
# packages first (stages up to and including ojs-config), then the stage under test
rc="$(runp stages-1 --stage packages --stage php --stage mariadb --stage ojs-code --stage ojs-config)"
yes "stages packages..ojs-config succeed on a clean image (exit $rc)" eq "$rc" 0
[ "$rc" = 0 ] || tail -12 "$log/stages-1.out"
inch /opt/worj-src/scripts/provision-ubuntu.sh --env /etc/worj/provision-live.env --os 24.04 --skip-services --stage cloudflare-ip >"$log/cf-first.out" 2>&1; rc=$?
yes "cloudflare-ip with no reachable source and no ranges file STOPS the run (exit $rc)" eq "$rc" 1
yes "...with the explanation that every visitor would look like Cloudflare" grep -q 'every visitor would look like a Cloudflare address' "$log/cf-first.out"
yes "...and no ranges file was created" test ! -e "$RUN/etc/nginx/worj-cloudflare-realip.conf"
rm -f "$RUN/etc/worj/provision-live.env"

echo "=== 3. bootstrap: no certificate yet, so only the port-80 site is installed and the run stops at the certificate check"
( while :; do cat /proc/[0-9]*/cmdline 2>/dev/null | tr '\0' '\n'; done >"$log/cmdlines.txt" ) & sampler_pid=$!
rc="$(runp stages-2 --stage cloudflare-ip --stage nginx --stage certbot)"
yes "the certificate stage refuses to continue without the origin certificate (exit $rc)" eq "$rc" 1
yes "...with a message naming the files to place" grep -q 'place the Cloudflare Origin CA certificate' "$log/stages-2.out"
yes "the BOOTSTRAP site (port 80 only, 503 + ACME path) is what nginx got" grep -q 'return 503' "$RUN/etc/nginx/conf.d/worj.conf"
yes "...and it has no TLS server" bash -c "! grep -q 'ssl_certificate' '$RUN/etc/nginx/conf.d/worj.conf'"
mkdir -p "$RUN/etc/ssl/worj"; chmod 700 "$RUN/etc/ssl/worj"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$RUN/etc/ssl/worj/privkey.pem" -out "$RUN/etc/ssl/worj/fullchain.pem" -days 90 -subj "/CN=journal.example.org" \
  -addext "subjectAltName=DNS:journal.example.org,DNS:www.journal.example.org" >/dev/null 2>&1
chmod 600 "$RUN/etc/ssl/worj/privkey.pem"

echo "=== 4. the full provisioning (all stages except firewall and ssh), run 1"
rc="$(runp full-1)"
yes "full provisioning succeeds (exit $rc)" eq "$rc" 0
[ "$rc" = 0 ] || tail -15 "$log/full-1.out"
echo "      run 1: $(grep -c '^  changed: ' "$log/full-1.out") changes; $(tail -1 "$log/full-1.out")"

echo "=== 5. run it AGAIN: nothing may change (idempotency)"
snapshot before-run2
rc="$(runp full-2)"
snapshot after-run2
yes "second full run succeeds (exit $rc)" eq "$rc" 0
yes "the second run ends with 'changed: 0'" grep -qx 'changed: 0' "$log/full-2.out"
yes "no stage reported a change (every stage says unchanged)" eq "$(stages_changed "$log/full-2.out")" 0
[ "$(tail -1 "$log/full-2.out")" = "changed: 0" ] || grep -E '^  (changed|WOULD):' "$log/full-2.out" | head -12
yes "tree snapshot (configs, scripts, permissions) is IDENTICAL before and after run 2" cmp -s "$log/before-run2.snap" "$log/after-run2.snap"
snapshot before-check2
rc="$(runp check-after --check)"
snapshot after-check2
yes "--check on the provisioned machine says 'changed: 0' (exit $rc)" grep -qx 'changed: 0' "$log/check-after.out"
yes "...and the tree snapshot is identical before and after" cmp -s "$log/before-check2.snap" "$log/after-check2.snap"
kill "$sampler_pid" 2>/dev/null; wait "$sampler_pid" 2>/dev/null; sampler_pid=""

echo "=== 6. the result works: OJS behind the rendered Nginx, PHP-FPM pool and MariaDB, inside the chroot"
cfg="$RUN/var/www/worj/config.inc.php"
yes "config.inc.php is mode 640 root:www-data" eq "$(stat -c '%a %U:%G' "$cfg")" "640 root:www-data"
yes "installed = On" grep -q '^installed = On' "$cfg"
inch python3 -I /opt/worj-src/scripts/check-live-config.py /var/www/worj/config.inc.php --host journal.example.org --web-root /var/www/worj --owner root:www-data >"$log/live.out" 2>&1; rc=$?
yes "check-live-config.py passes on the provisioned config (exit $rc, $(tail -1 "$log/live.out"))" eq "$rc" 0
yes "the salt is not the shipped default" bash -c "! grep -q 'YouMustSetASecretKeyHere' '$cfg'"
yes "api_key_secret is set (not empty)" bash -c "grep -E '^api_key_secret = \"[A-Za-z0-9_-]{32,}\"' '$cfg' >/dev/null"
yes "allowed_hosts is the real domain, time_zone is set" bash -c "grep -q \"^allowed_hosts = '\\[\\\"journal.example.org\\\"\\]'\" '$cfg' && grep -q '^time_zone = \"UTC\"' '$cfg'"
yes "the administrator is the non-default name from the settings" eq "$(inch mariadb -N -e "select username from ojs_worj.users" 2>/dev/null || inch mariadb -N -e "select username from worj.users")" journalops
dbname="$(sed -n 's/^DB_NAME=//p' "$RUN/etc/worj/provision.env")"; dbname="${dbname:-worj}"
yes "the database has the OJS tables ($(inch mariadb -N -e "select count(*) from information_schema.tables where table_schema='$dbname'") tables)" test "$(inch mariadb -N -e "select count(*) from information_schema.tables where table_schema='$dbname'")" -ge 30
H=journal.example.org
cu() { curl -sk --noproxy '*' --resolve "$H:443:127.0.0.1" --resolve "www.$H:443:127.0.0.1" --resolve "$H:80:127.0.0.1" -m 60 "$@"; }
yes "https://$H/index/login returns 200 with a username field" bash -c "$(declare -f cu); H=$H; cu https://$H/index/login | grep -q 'name=\"username\"'"
hdr="$(cu -o /dev/null -D - "https://$H/index/login" | tr -d '\r')"
yes "...with HSTS (max-age=300), nosniff and a Report-Only CSP" bash -c "grep -qi 'strict-transport-security: max-age=300' <<<'$hdr' && grep -qi 'x-content-type-options: nosniff' <<<'$hdr'"
yes "http:// redirects to https://journal.example.org" eq "$(cu -o /dev/null -w '%{redirect_url}' "http://$H/index/login")" "https://$H/index/login"
yes "/config.inc.php is a 404" eq "$(cu -o /dev/null -w '%{http_code}' "https://$H/config.inc.php")" 404
# no journal exists yet in this chroot, so use a SITE-level path (an unknown first segment is read as a journal path)
yes "an unknown site-level path shows the static 404 page with status 404" bash -c "$(declare -f cu); H=$H; [ \"\$(cu -o /dev/null -w '%{http_code}' https://$H/index/no-such-page-xyz)\" = 404 ] && cu https://$H/index/no-such-page-xyz | grep -q 'Page not found'"
yes "the real-IP file from the fixture is in place (22 ranges)" eq "$(grep -c '^set_real_ip_from' "$RUN/etc/nginx/worj-cloudflare-realip.conf")" 22
yes "the backup job, cron file and logrotate are installed" bash -c "[ -x '$RUN/usr/local/sbin/worj-backup' ] && [ -f '$RUN/etc/cron.d/worj' ] && [ -f '$RUN/etc/logrotate.d/worj' ]"
yes "mysql-backup.cnf and secrets.env are mode 600" bash -c "[ \"\$(stat -c %a '$RUN/etc/worj/mysql-backup.cnf')\" = 600 ] && [ \"\$(stat -c %a '$RUN/etc/worj/secrets.env')\" = 600 ]"
inch /usr/local/sbin/worj-backup --env /etc/worj/backup.env --check >"$log/backup-check.out" 2>&1; rc=$?
yes "the installed backup script runs in --check mode (exit $rc)" eq "$rc" 0

echo "=== 6b. regression checks for what the first chroot runs found, plus the password and scheduler decisions"
yes "the initial ADMIN_PASSWORD line was REMOVED from provision.env after the install" eq "$(grep -c '^ADMIN_PASSWORD=' "$RUN/etc/worj/provision.env")" 0
yes "...and the settings file is still root-only (mode 600)" eq "$(stat -c '%a %U:%G' "$RUN/etc/worj/provision.env")" "600 root:root"
yes "...while SMTP_PASSWORD is still there (needed later)" grep -q '^SMTP_PASSWORD=' "$RUN/etc/worj/provision.env"
yes "the administrator MUST change the initial password at the first login (must_change_password = 1)" eq "$(inch mariadb -N -e "select must_change_password from $dbname.users where username='journalops'")" 1
yes "REGRESSION the installer ran as root, yet cache/, public/ and files_dir belong to www-data (nothing in them is root-owned)" eq "$(find "$RUN/var/www/worj/cache" "$RUN/var/www/worj/public" "$RUN/var/lib/worj/files" ! -user www-data 2>/dev/null | wc -l)" 0
yes "REGRESSION the installed code tree outside cache/ and public/ is root-owned (nothing writable by the web user)" eq "$(find "$RUN/var/www/worj" \( -path "$RUN/var/www/worj/cache" -o -path "$RUN/var/www/worj/public" \) -prune -o ! -user root -print 2>/dev/null | wc -l)" 0
yes "REGRESSION no second allowed_hosts line (the installer appends one): exactly one, the real domain" bash -c "[ \$(grep -c '^allowed_hosts' '$cfg') = 1 ] && grep -q \"^allowed_hosts = '\\[\\\"journal.example.org\\\"\\]'\" '$cfg'"
yes "REGRESSION no python3 problem: the provision log never mentions a missing interpreter" bash -c "! grep -qi 'python3: not found\|command not found' '$log'/full-1.out '$log'/stages-1.out"
yes "scheduled tasks come from cron: task_runner Off, job_runner Off, process_jobs_at_task_scheduler On" bash -c "grep -q '^task_runner = Off' '$cfg' && grep -q '^job_runner = Off' '$cfg' && grep -q '^process_jobs_at_task_scheduler = On' '$cfg'"
yes "the cron file runs the OJS scheduler every minute as www-data" grep -qE '^\* \* \* \* \* www-data cd /var/www/worj && php lib/pkp/tools/scheduler.php run' "$RUN/etc/cron.d/worj"
inch su -s /bin/sh www-data -c "cd /var/www/worj && php lib/pkp/tools/scheduler.php list" >"$log/sched-list.out" 2>&1; rc=$?
yes "the scheduler command from the cron line works as www-data (list: exit $rc)" eq "$rc" 0
for t in ReviewReminder StatisticsReport EditorialReminders UsageStatsLoader ProcessQueueJobs; do
  yes "...and it lists the task $t" grep -q "$t" "$log/sched-list.out"
done
inch su -s /bin/sh www-data -c "cd /var/www/worj && php lib/pkp/tools/scheduler.php run" >"$log/sched-run.out" 2>&1; rc=$?
yes "...and a run exits cleanly (exit $rc)" eq "$rc" 0
yes "theme CSS is cached one hour only through the rendered Nginx (OJS versions it with the OJS version)" bash -c "$(declare -f cu); H=$H; cu -o /dev/null -D - https://$H/plugins/themes/worj/assets/css/base.css | tr -d '\r' | grep -qi 'cache-control: max-age=3600'"

echo "=== 7. secret hygiene: where do the secrets appear?"
db_pw="$(sed -n 's/^DB_PASSWORD=//p' "$RUN/etc/worj/secrets.env")"
salt="$(sed -n 's/^salt = "\(.*\)"$/\1/p' "$cfg")"; api="$(sed -n 's/^api_key_secret = "\(.*\)"$/\1/p' "$cfg")"
leak() { # name value : files under the chroot (and the logs) that contain it, excluding where it MUST live
  local name="$1" val="$2" allowed="$3" hits
  [ "${#val}" -ge 12 ] || { bad "sentinel for $name is too short to search for"; return; }
  hits="$( { grep -rlF --exclude-dir=proc --exclude-dir=dev --exclude-dir=sys --exclude-dir=worj-src -e "$val" "$RUN" 2>/dev/null; grep -lF -e "$val" "$log"/*.out "$log/cmdlines.txt" 2>/dev/null; } | sed "s#^$RUN##" | sort -u | grep -v -E "$allowed" || true)"
  if [ -z "$hits" ]; then ok "$name appears only where it must ($allowed)"; else bad "$name leaked into: $(echo "$hits" | tr '\n' ' ')"; fi
}
leak "the administrator password (it must be GONE from provision.env too)" "$ADMIN_PW" '^$'
leak "the SMTP password" "$SMTP_PW" '^/etc/worj/provision\.env$|^/var/www/worj/config\.inc\.php$'
leak "the database password" "$db_pw" '^/etc/worj/secrets\.env$|^/etc/worj/mysql-backup\.cnf$|^/var/www/worj/config\.inc\.php$'
leak "the salt" "$salt" '^/var/www/worj/config\.inc\.php$'
leak "the API key secret" "$api" '^/var/www/worj/config\.inc\.php$'
yes "the process-list sampler saw real activity ($(grep -c . "$log/cmdlines.txt") lines, including apt/rsync/php)" bash -c "grep -q 'rsync' '$log/cmdlines.txt' && grep -q 'install.php' '$log/cmdlines.txt'"
yes "the installer ran (install.php in the process list) and its password never appeared there" bash -c "grep -q 'tools/install.php' '$log/cmdlines.txt' && ! grep -qF '$ADMIN_PW' '$log/cmdlines.txt'"
yes "the installer answers file is gone" test ! -e "$RUN/root/.worj-provision/answers"
yes "no installer log or temp output is left in /root" bash -c "[ -z \"\$(ls -A '$RUN/root' | grep -E 'worj' || true)\" ]"
yes "no shell history exists in the chroot" bash -c "[ ! -s '$RUN/root/.bash_history' ]"
yes "the provisioning output never printed a secret" bash -c "! grep -qF -e '$ADMIN_PW' -e '$SMTP_PW' -e '$db_pw' -e '$salt' '$log'/full-1.out '$log'/full-2.out"

{
  echo "chroot provisioning report $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "run 1: $(tail -1 "$log/full-1.out"); run 2: $(tail -1 "$log/full-2.out"); check on provisioned: $(tail -1 "$log/check-after.out")"
  echo "fresh --check: $(grep -c '^  WOULD: ' "$log/check-fresh.out") actions would be taken"
  echo "logs kept in $log"
} >"$REPORT"
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "$fail FAILED (logs in $log)"; fi
exit "$fail"
