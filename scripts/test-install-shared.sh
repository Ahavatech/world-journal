#!/usr/bin/env bash
# End to end on this machine: release -> deploy -> scripts/install-shared.sh, with a stand-in ssh that runs the "remote"
# commands locally, a scratch MariaDB database and the real OJS CLI installer. Needs root (mariadb socket), php, rsync
# and ojs-core (make setup). It proves the script logic and the installer's behaviour; it does NOT prove the host.
# UNVERIFIED (not run on the host).
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$(id -u)" = 0 ] || { echo "run as root (needs the sandbox MariaDB)"; exit 2; }
[ -f "$root/ojs-core/index.php" ] || { echo "ojs-core missing (make setup)"; exit 2; }
command -v mariadb >/dev/null || { echo "mariadb client missing"; exit 2; }
tmp="$(mktemp -d)"; chmod 755 "$tmp"
dbn="worj_shared_t$$"; dbu="worj_sh_u$$"; dbp="$(openssl rand -hex 12)"
cleanup() { mariadb -e "DROP DATABASE IF EXISTS \`$dbn\`; DROP USER IF EXISTS '$dbu'@'localhost';" 2>/dev/null; rm -rf -- "${tmp:?}"; }
trap cleanup EXIT
fail=0; pass=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
no() { local name="$1"; shift; if "$@"; then bad "$name"; else ok "$name"; fi; }

mariadb -e "CREATE DATABASE \`$dbn\` CHARACTER SET utf8mb4; CREATE USER '$dbu'@'localhost' IDENTIFIED BY '$dbp'; GRANT ALL ON \`$dbn\`.* TO '$dbu'@'localhost';" || { echo "cannot create the scratch database"; exit 2; }
cat >"$tmp/ssh" <<'STUB'
#!/usr/bin/env bash
# stand-in for ssh: drop the options and the host, run the remote command locally (a single string goes through sh -c)
while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do case "$1" in -p|-i|-o) shift 2 ;; *) shift ;; esac; done
shift
if [ "$#" -eq 1 ]; then exec sh -c "$1"; else exec "$@"; fi
STUB
chmod +x "$tmp/ssh"
H=journal.example.org
R="$tmp/home/domains/$H"; mkdir -p "$R/public_html"
"$root/scripts/build-release.sh" --host "$H" --robots-mode closed --out "$tmp/rel" >/dev/null || { echo "build failed"; exit 2; }
WORJ_SSH="$tmp/ssh" "$root/scripts/deploy-shared.sh" --release "$tmp/rel" --target "fake:$R/public_html" >/dev/null || { echo "deploy failed"; exit 2; }
ADMINPW="Correct-Horse-9xQ"
mkenv() { # file
  cat >"$1" <<ENV
HOST=$H
TIME_ZONE=Africa/Lagos
SSH_TARGET=fake
SSH_PORT=22
SSH_KEY=
REMOTE_ROOT=$R
DB_NAME=$dbn
DB_USER=$dbu
DB_PASSWORD=$dbp
ADMIN_USERNAME=worjadmin
ADMIN_EMAIL=admin@example.invalid
ADMIN_PASSWORD=$ADMINPW
SMTP_SERVER=smtp.example.invalid
SMTP_PORT=465
SMTP_AUTH=ssl
SMTP_USERNAME=editorial@example.invalid
SMTP_PASSWORD=smtp-secret-$$
ENV
  chmod 600 "$1"
}
mkenv "$tmp/env"
I() { WORJ_SSH="$tmp/ssh" "$root/scripts/install-shared.sh" "$@"; }
cfg="$R/public_html/config.inc.php"

echo "=== refusals before anything is touched"
mkenv "$tmp/env644"; chmod 644 "$tmp/env644"
no "an env file readable by others is refused" I --env "$tmp/env644" --check
sed 's/^DB_NAME=.*/DB_NAME=REPLACE_DB_NAME/' "$tmp/env" >"$tmp/envrep"; chmod 600 "$tmp/envrep"
no "an env file with a REPLACE_ placeholder is refused" I --env "$tmp/envrep" --check
sed 's/^ADMIN_PASSWORD=.*/ADMIN_PASSWORD=short/' "$tmp/env" >"$tmp/envshort"; chmod 600 "$tmp/envshort"
no "an administrator password under 12 characters is refused" I --env "$tmp/envshort"
sed 's/^TIME_ZONE=.*/TIME_ZONE=Mars\/Base/' "$tmp/env" >"$tmp/envtz"; chmod 600 "$tmp/envtz"
no "a time zone that is not IANA is refused" I --env "$tmp/envtz" --check
sed "s#^REMOTE_ROOT=.*#REMOTE_ROOT=/tmp/a b#" "$tmp/env" >"$tmp/envpath"; chmod 600 "$tmp/envpath"
no "a remote path with a space is refused" I --env "$tmp/envpath" --check
no "a missing env file is refused" I --env "$tmp/nope"
yes "nothing was created by the refusals" test ! -e "$R/worj-files" -a ! -e "$cfg"

echo "=== --check"
I --env "$tmp/env" --check >"$tmp/check.txt" 2>&1; rc=$?
yes "--check exits 0 (exit $rc)" test "$rc" = 0
yes "--check prints WOULD lines" grep -q '^WOULD: ' "$tmp/check.txt"
yes "--check changed nothing (no files dir, no config)" test ! -e "$R/worj-files" -a ! -e "$cfg" -a ! -e "$R/public_html/cache"
yes "--check printed no secret" bash -c "! grep -qE '$dbp|$ADMINPW|smtp-secret' '$tmp/check.txt'"

echo "=== a failing installer: wrong database password"
sed "s/^DB_PASSWORD=.*/DB_PASSWORD=wrong-$dbp/" "$tmp/env" >"$tmp/envbad"; chmod 600 "$tmp/envbad"
I --env "$tmp/envbad" >"$tmp/bad.txt" 2>&1; rc=$?
yes "the install fails (exit $rc)" test "$rc" != 0
yes "...and the output holds neither password" bash -c "! grep -qE 'wrong-$dbp|$ADMINPW' '$tmp/bad.txt'"
rm -f "$cfg"

echo "=== install"
I --env "$tmp/env" >"$tmp/install.txt" 2>&1; rc=$?
yes "the install succeeds (exit $rc)" test "$rc" = 0
[ "$rc" = 0 ] || sed 's/^/      /' "$tmp/install.txt" | tail -15
yes "the output holds none of the secrets" bash -c "! grep -qE '$dbp|$ADMINPW|smtp-secret' '$tmp/install.txt'"
yes "config.inc.php exists with mode 600" test "$(stat -c %a "$cfg")" = 600
yes "installed = On" grep -q '^installed = On' "$cfg"
yes "the files directory is above the web root, mode 700" test -d "$R/worj-files" -a "$(stat -c %a "$R/worj-files")" = 700
yes "the installer created the database tables" test "$(mariadb -N "$dbn" -e "select count(*) from users where username='worjadmin'")" = 1
yes "the administrator must change the initial password" test "$(mariadb -N "$dbn" -e "select must_change_password from users where username='worjadmin'")" = 1
yes "the salt is not the public default and is long" bash -c "s=\$(sed -n 's/^salt *= *\"\\(.*\\)\"/\\1/p' '$cfg'); [ \${#s} -ge 32 ] && [ \"\$s\" != 'YouMustSetASecretKeyHere!!' ]"
yes "allowed_hosts names the host" grep -q "^allowed_hosts = '\[\"$H\"\]'" "$cfg"
yes "time_zone is set" grep -q '^time_zone = "Africa/Lagos"' "$cfg"
yes "check-live-config.py passes on the result" python3 -I "$root/scripts/check-live-config.py" "$cfg" --host "$H" --web-root "$R/public_html"
yes "ADMIN_PASSWORD was removed from the env file" bash -c "! grep -q '^ADMIN_PASSWORD=' '$tmp/env'"
yes "the env file is still mode 600" test "$(stat -c %a "$tmp/env")" = 600

echo "=== re-run is idempotent"
sum1="$(sha256sum "$cfg" | cut -d' ' -f1)"
I --env "$tmp/env" >"$tmp/again.txt" 2>&1; rc=$?
yes "the second run succeeds (exit $rc)" test "$rc" = 0
yes "it says OJS is already installed" grep -q 'already installed' "$tmp/again.txt"
yes "config.inc.php is byte for byte unchanged" test "$sum1" = "$(sha256sum "$cfg" | cut -d' ' -f1)"
yes "the second run needs no ADMIN_PASSWORD" bash -c "! grep -q '^ADMIN_PASSWORD=' '$tmp/env'"

echo "=== the installer's weak defaults are repaired"
sed -i 's/^salt = .*/salt = "YouMustSetASecretKeyHere!!"/; s/^allowed_hosts = .*/allowed_hosts = '"'"'[""]'"'"'/' "$cfg"
I --env "$tmp/env" >/dev/null 2>&1
yes "a default salt and an empty allowed_hosts are repaired on the next run" python3 -I "$root/scripts/check-live-config.py" "$cfg" --host "$H" --web-root "$R/public_html"

echo "$pass PASS, $fail FAIL"
exit "$fail"
