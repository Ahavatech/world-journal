#!/usr/bin/env bash
# Tests scripts/reset-ojs-admin-password.sh on the SANDBOX database: after the reset the NEW password logs in, the old
# one does not, the stored hash is bcrypt cost 12, and the original hash is restored afterwards.
#   scripts/test-reset-admin-password.sh        needs root and the sandbox up (make sandbox-up sandbox-seed)
# shellcheck disable=SC2317,SC2016  # helper functions are called indirectly; PHP and bcrypt prefixes are not shell
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 2; }
set -a; . "$root/.env.sandbox"; set +a
export NODE_PATH="${NODE_PATH:-/opt/node22/lib/node_modules}"
cfg="$root/ojs-core/config.inc.php"
Z="$root/scripts/reset-ojs-admin-password.sh"
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
no() { local name="$1"; shift; if "$@"; then bad "$name"; else ok "$name"; fi; }
sql() { mariadb -N -e "$1"; }
# keep the original row exactly (must_change_password may be NULL, which a concat would swallow)
orig_hash="$(sql "select password from $SANDBOX_DB_NAME.users where username='$SANDBOX_ADMIN_USER'")"
orig_must="$(sql "select ifnull(must_change_password,'NULL') from $SANDBOX_DB_NAME.users where username='$SANDBOX_ADMIN_USER'")"
if [ -z "$orig_hash" ] || [ "$orig_hash" = NULL ]; then echo "the admin row has no password hash: fix the sandbox first"; exit 2; fi
restore() { sql "update $SANDBOX_DB_NAME.users set password='$orig_hash', must_change_password=$orig_must where username='$SANDBOX_ADMIN_USER'"; }
trap restore EXIT
login() { # username password -> prints OK or FAIL
  node -e "
const { chromium } = require('playwright');
(async () => { const b = await chromium.launch(); const p = await b.newPage();
  await p.goto('http://127.0.0.1:8082/index/login');
  await p.fill('input[name=username]', process.argv[1]); await p.fill('input[name=password]', process.argv[2]);
  await Promise.all([p.waitForEvent('load'), p.click('button[type=submit]')]);
  const forced = /changePassword/.test(p.url()); const failed = !forced && !(await p.locator('a[href*=signOut]').count());
  console.log(failed ? 'FAIL' : forced ? 'OK' : 'OK'); await b.close(); })()" "$1" "$2"
}
NEWPW='Recovery-Test-Passw0rd-93x!'

yes "the original admin password still works before the test" test "$(login "$SANDBOX_ADMIN_USER" "$SANDBOX_ADMIN_PASSWORD")" = OK
out="$(printf '%s\n' "$NEWPW" | "$Z" --config "$cfg" --username "$SANDBOX_ADMIN_USER" 2>&1)"; rc=$?
yes "the reset succeeds (exit $rc)" test "$rc" = 0
no "the output never shows the password" grep -qF "$NEWPW" <<<"$out"
no "the output never shows a hash" grep -q '\$2y\$' <<<"$out"
hash="$(sql "select password from $SANDBOX_DB_NAME.users where username='$SANDBOX_ADMIN_USER'")"
yes "stored hash is bcrypt cost 12 (\$2y\$12\$...)" test "${hash:0:7}" = '$2y$12$'
yes "PHP password_verify (the function OJS uses) accepts the new password" test "$(printf '%s' "$NEWPW" | php -r '$h = $argv[1]; echo password_verify(stream_get_contents(STDIN), $h) ? "yes" : "no";' "$hash")" = yes
yes "...and rejects the old one" test "$(printf '%s' "$SANDBOX_ADMIN_PASSWORD" | php -r '$h = $argv[1]; echo password_verify(stream_get_contents(STDIN), $h) ? "yes" : "no";' "$hash")" = no
yes "must_change_password is set" test "$(sql "select must_change_password from $SANDBOX_DB_NAME.users where username='$SANDBOX_ADMIN_USER'")" = 1
yes "OJS itself: the NEW password logs in through the real login form" test "$(login "$SANDBOX_ADMIN_USER" "$NEWPW")" = OK
yes "OJS itself: the OLD password no longer logs in" test "$(login "$SANDBOX_ADMIN_USER" "$SANDBOX_ADMIN_PASSWORD")" = FAIL

printf 'short\n' | "$Z" --config "$cfg" --username "$SANDBOX_ADMIN_USER" >/dev/null 2>&1; rc=$?
yes "a short password is refused (exit $rc)" test "$rc" = 1
printf '%s\n' "$NEWPW" | "$Z" --config "$cfg" --username "no_such_user" >/dev/null 2>&1; rc=$?
yes "an unknown user is refused (exit $rc)" test "$rc" = 1
printf '%s\n' "$NEWPW" | "$Z" --config "$cfg" --username "x';drop table users;--" >/dev/null 2>&1; rc=$?
yes "a username with SQL characters is refused (exit $rc)" test "$rc" = 2
"$Z" --config "$cfg" --username "$SANDBOX_ADMIN_USER" "--password=$NEWPW" >/dev/null 2>&1; rc=$?
yes "a password on the command line is refused (exit $rc)" test "$rc" = 2
yes "the users table still exists after the injection attempt" test "$(sql "select count(*) from $SANDBOX_DB_NAME.users")" -ge 1

restore; trap - EXIT
yes "the original password works again after the test restore" test "$(login "$SANDBOX_ADMIN_USER" "$SANDBOX_ADMIN_PASSWORD")" = OK
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "$fail FAILED"; fi
exit "$fail"
