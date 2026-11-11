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
if [ "$#" -eq 1 ] && [ -n "${STUB_SOCKET_STDIN:-}" ]; then
  # the input arrives over a socket, as it does over ssh (PHP then reports end-of-file as soon as the last line is read)
  exec python3 -c 'import socket,subprocess,sys
d=sys.stdin.buffer.read()
a,b=socket.socketpair()
a.sendall(d); a.shutdown(socket.SHUT_WR)
sys.exit(subprocess.call(["sh","-c",sys.argv[1]],stdin=b))' "$1"
elif [ "$#" -eq 1 ]; then
  if [ -n "${STUB_CUT:-}" ]; then sh -c "$1" | head -c "$STUB_CUT"; else exec sh -c "$1"; fi
else exec "$@"; fi
STUB
chmod +x "$tmp/ssh"
# the real host disables shell_exec and shows no errors: the OJS installer (stty in backticks) dies silently there
mkdir -p "$tmp/bin"; realphp="$(command -v php)"
printf '#!/usr/bin/env bash\nexec %s -d display_errors=0 -d disable_functions=shell_exec "$@"\n' "$realphp" >"$tmp/bin/php"; chmod +x "$tmp/bin/php"
export PATH="$tmp/bin:$PATH"
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
I() { STUB_SOCKET_STDIN=1 WORJ_SSH="$tmp/ssh" "$root/scripts/install-shared.sh" "$@" </dev/null; }
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
yes "the scheduler wrapper is on the host above the web root, executable" test -x "$R/worj-ops/run-scheduler.sh"
bash "$R/worj-ops/run-scheduler.sh"; rc=$?
yes "the REAL OJS scheduler runs through the wrapper against the installed site (exit $rc)" test "$rc" = 0
yes "...and the log shows start and end" bash -c "grep -q ' start$' '$R/worj-logs/scheduler.log' && grep -q ' end exit=0$' '$R/worj-logs/scheduler.log'"
yes "the installer created the database tables" test "$(mariadb -N "$dbn" -e "select count(*) from users where username='worjadmin'")" = 1
yes "before --finish the initial password is still usable (seeding logs in with it)" test "$(mariadb -N "$dbn" -e "select coalesce(must_change_password,0) from users where username='worjadmin'")" = 0
yes "the salt is not the public default and is long" bash -c "s=\$(sed -n 's/^salt *= *\"\\(.*\\)\"/\\1/p' '$cfg'); [ \${#s} -ge 32 ] && [ \"\$s\" != 'YouMustSetASecretKeyHere!!' ]"
yes "allowed_hosts names the host" grep -q "^allowed_hosts = '\[\"$H\"\]'" "$cfg"
yes "time_zone is set" grep -q '^time_zone = "Africa/Lagos"' "$cfg"
yes "check-live-config.py passes on the result" python3 -I "$root/scripts/check-live-config.py" "$cfg" --host "$H" --web-root "$R/public_html"
yes "...and ADMIN_PASSWORD is still in the env file until --finish" grep -q '^ADMIN_PASSWORD=' "$tmp/env"

echo "=== pull-backup.sh: encrypted bundle pulled over ssh"
for t in age age-keygen rclone mysqldump; do command -v "$t" >/dev/null || { echo "missing tool: $t (apt-get install -y age rclone)"; exit 2; }; done
age-keygen -o "$tmp/id.txt" >/dev/null 2>&1; recip="$(age-keygen -y "$tmp/id.txt")"
mkdir -p "$R/worj-files/submissions" "$R/public_html/public/site"; printf 'a private submission' >"$R/worj-files/submissions/note.txt"; printf 'a public image' >"$R/public_html/public/site/x.jpg"
{ cat "$tmp/env"; printf 'BACKUP_AGE_RECIPIENT=%s\nBACKUP_DIR=%s\nBACKUP_RCLONE_REMOTE=%s\nBACKUP_KEEP=2\n' "$recip" "$tmp/bk" "$tmp/rcl"; } >"$tmp/envbk"; chmod 600 "$tmp/envbk"
BK() { WORJ_SSH="$tmp/ssh" "$root/scripts/pull-backup.sh" "$@"; }
BK --env "$tmp/envbk" --check >"$tmp/bkc.txt" 2>&1; rc=$?
yes "pull-backup --check exits 0 and writes nothing (exit $rc)" test "$rc" = 0 -a ! -e "$tmp/bk"
yes "--check prints WOULD lines" grep -q '^WOULD: ' "$tmp/bkc.txt"
sed "s#^BACKUP_AGE_RECIPIENT=.*#BACKUP_AGE_RECIPIENT=$(grep -m1 AGE-SECRET-KEY "$tmp/id.txt")#" "$tmp/envbk" >"$tmp/envpriv"; chmod 600 "$tmp/envpriv"
BK --env "$tmp/envpriv" >"$tmp/bkpriv.txt" 2>&1
yes "a PRIVATE age key in the env file is refused, for that reason" grep -q 'REFUSED: a PRIVATE age key' "$tmp/bkpriv.txt"
yes "...and its value is not printed" bash -c "! grep -q 'AGE-SECRET-KEY-[A-Z0-9]' '$tmp/bkpriv.txt'"
grep -v '^BACKUP_AGE_RECIPIENT=' "$tmp/envbk" >"$tmp/envnokey"; chmod 600 "$tmp/envnokey"
no "a missing public key is refused" BK --env "$tmp/envnokey"
cp "$tmp/envbk" "$tmp/envbk644"; chmod 644 "$tmp/envbk644"
no "an env file readable by others is refused" BK --env "$tmp/envbk644"
BK --env "$tmp/envbk" >"$tmp/bk1.txt" 2>&1; rc=$?
yes "a backup succeeds (exit $rc)" test "$rc" = 0
[ "$rc" = 0 ] || sed 's/^/      /' "$tmp/bk1.txt" | tail -8
bundle="$(find "$tmp/bk" -maxdepth 1 -name 'worj-*.tar.age' | sort | tail -1)"
yes "the bundle exists, mode 600, with a sha256 file" bash -c "[ -f '$bundle' ] && [ \"\$(stat -c %a '$bundle')\" = 600 ] && [ -f '$bundle.sha256' ]"
yes "the output holds none of the secrets" bash -c "! grep -qE '$dbp|$ADMINPW|smtp-secret' '$tmp/bk1.txt'"
yes "the bundle is encrypted (no table name, user name or path in clear)" bash -c "! grep -qaE 'CREATE TABLE|worjadmin|worj-files' '$bundle'"
mkdir "$tmp/bkx"; age -d -i "$tmp/id.txt" -o "$tmp/bkx/bundle.tar" "$bundle" && tar -xf "$tmp/bkx/bundle.tar" -C "$tmp/bkx"
yes "the private key decrypts it, and the manifest matches" bash -c "cd '$tmp/bkx' && sha256sum --quiet -c MANIFEST.sha256"
yes "the bundle has the layout scripts/restore.sh reads" bash -c "cd '$tmp/bkx' && ls db.sql.gz data.tar.gz config.inc.php INFO MANIFEST.sha256 >/dev/null"
yes "the dump holds the users table and the administrator" bash -c "gzip -dc '$tmp/bkx/db.sql.gz' | grep -q 'worjadmin'"
yes "the archive holds the private file and the public image" bash -c "t=\$(tar -tzf '$tmp/bkx/data.tar.gz'); grep -q 'worj-files/submissions/note.txt' <<<\"\$t\" && grep -q 'public/site/x.jpg' <<<\"\$t\""
yes "the config copy is the installed config" grep -q '^installed = On' "$tmp/bkx/config.inc.php"
mariadb -e "GRANT ALL ON \`${dbn//_/\\_}\\_restore%\`.* TO '$dbu'@'localhost'"
printf '[client]\nuser=%s\npassword=%s\n' "$dbu" "$dbp" >"$tmp/rootdefaults.cnf"; chmod 600 "$tmp/rootdefaults.cnf"
"$root/scripts/restore.sh" --bundle "$bundle" --identity "$tmp/id.txt" --code-dir "$R/public_html" --live-config "$cfg" \
  --scratch-db "${dbn}_restore_rehearsal" --db-defaults "$tmp/rootdefaults.cnf" --port 18199 >"$tmp/restore.txt" 2>&1; rc=$?
# This install has no journal yet (creating one needs a browser, see seed-shared.sh), so restore.sh's last check, the journal's
# login page, cannot pass here: that part is NOT covered. Everything before it is asserted.
for want in "backup decrypted with the private key" "SHA-256 manifest matches" "scratch database loaded" "files_dir restored" "temporary config is mode 600"; do
  yes "scripts/restore.sh on the PULLED bundle: $want" grep -q "PASS  $want" "$tmp/restore.txt"
done
yes "...and removed its scratch database afterwards" test "$(mariadb -N -e "show databases like '${dbn}_restore_rehearsal'" | wc -l)" = 0
mariadb -e "CREATE DATABASE \`${dbn}_restore\`"
gzip -dc "$tmp/bkx/db.sql.gz" | mariadb "${dbn}_restore"
yes "the dump RESTORES into a scratch database (administrator row back)" test "$(mariadb -N "${dbn}_restore" -e "select count(*) from users where username='worjadmin'")" = 1
mariadb -e "DROP DATABASE \`${dbn}_restore\`"
yes "rclone copied the bundle with the same size" test "$(stat -c %s "$tmp/rcl/$(basename "$bundle")")" = "$(stat -c %s "$bundle")"
yes "last-success is written and no FAILED marker" test -f "$tmp/bk/last-success" -a ! -e "$tmp/bk/FAILED"
sleep 1; BK --env "$tmp/envbk" --no-upload >/dev/null 2>&1; sleep 1; BK --env "$tmp/envbk" --no-upload >/dev/null 2>&1
yes "retention keeps only BACKUP_KEEP=2 bundles" test "$(find "$tmp/bk" -maxdepth 1 -name 'worj-*.tar.age' | wc -l)" = 2
dump_n="$(grep -o 'dump ok: [0-9]*' "$tmp/bk1.txt" | grep -o '[0-9]*$')"
STUB_CUT=3000 BK --env "$tmp/envbk" --no-upload >"$tmp/bkf.txt" 2>&1; rc=$?
yes "a cut-off dump fails (exit $rc)" test "$rc" != 0
yes "...writes the FAILED marker" test -f "$tmp/bk/FAILED"
rm -f "$tmp/bk/FAILED"
STUB_CUT=$((dump_n - 200)) BK --env "$tmp/envbk" --no-upload >"$tmp/bkf2.txt" 2>&1; rc=$?
yes "a dump cut just before its end (valid gzip, enough tables) fails (exit $rc)" test "$rc" != 0
yes "...because mysqldump's completion line is missing" grep -q "completion line" "$tmp/bkf2.txt"
rm -f "$tmp/bk/FAILED"
sed '/completion line/d' "$root/scripts/pull-backup.sh" >"$tmp/pull-mut.sh"; chmod +x "$tmp/pull-mut.sh"
STUB_CUT=$((dump_n - 200)) WORJ_SSH="$tmp/ssh" "$tmp/pull-mut.sh" --env "$tmp/envbk" --no-upload >/dev/null 2>&1; rc=$?
yes "mutation: without the completion-line check the truncated dump is accepted (exit $rc)" test "$rc" = 0
rm -f "$tmp/bk/FAILED"

echo "=== enable-block-plugin.php (the step seeding needs on a fresh journal)"
yes "without a journal it reports 'no journal' and writes nothing" bash -c "[ \"\$(STUB_SOCKET_STDIN=1 '$tmp/ssh' x \"cd '$R/public_html' && php\" <'$root/scripts/lib/enable-block-plugin.php')\" = 'no journal' ]"
mariadb "$dbn" -e "INSERT INTO journals (path, seq, primary_locale, enabled) VALUES ('worj', 1, 'en', 1)"
out1="$(STUB_SOCKET_STDIN=1 "$tmp/ssh" x "cd '$R/public_html' && php" <"$root/scripts/lib/enable-block-plugin.php")"
yes "with a journal it enables the plugin for the site and the journal" bash -c "grep -q 'enabled makesubmissionblockplugin site' <<<'$out1' && grep -q 'enabled makesubmissionblockplugin journal' <<<'$out1'"
yes "the database holds the two enabled rows" test "$(mariadb -N "$dbn" -e "select count(*) from plugin_settings where plugin_name='makesubmissionblockplugin' and setting_name='enabled' and setting_value='1'")" = 2
out2="$(STUB_SOCKET_STDIN=1 "$tmp/ssh" x "cd '$R/public_html' && php" <"$root/scripts/lib/enable-block-plugin.php")"
yes "running it again changes nothing (idempotent)" bash -c "! grep -q '^enabled' <<<'$out2' && [ \"\$(mariadb -N '$dbn' -e \"select count(*) from plugin_settings where plugin_name='makesubmissionblockplugin'\")\" = 2 ]"
mariadb "$dbn" -e "DELETE FROM plugin_settings WHERE plugin_name='makesubmissionblockplugin'; DELETE FROM journals WHERE path='worj'"

echo "=== count-issues.php (keeps the sample issue from being imported twice)"
yes "an installed OJS with no issue prints 0" bash -c "[ \"\$(STUB_SOCKET_STDIN=1 '$tmp/ssh' x \"cd '$R/public_html' && php\" <'$root/scripts/lib/count-issues.php')\" = 0 ]"

echo "=== seed-shared.sh --check (the REST part needs Playwright and a real https site: NOT run here)"
S() { WORJ_SSH="$tmp/ssh" "$root/scripts/seed-shared.sh" "$@"; }
S --env "$tmp/env" --check --with-sample-issue >"$tmp/seed.txt" 2>&1; rc=$?
yes "seed --check exits 0 (exit $rc)" test "$rc" = 0
yes "seed --check prints WOULD lines for the journal, the pages and the sample issue" bash -c "grep -c '^WOULD: ' '$tmp/seed.txt' | grep -qx 3"
yes "...and says the sample issue is only imported if there is none" grep -q 'only if the journal has no issue yet' "$tmp/seed.txt"
yes "seed --check created nothing on the host" test ! -e "$R/worj-ops/scripts" -a ! -e "$R/worj-ops/ojs"
yes "seed --check printed no secret" bash -c "! grep -qE '$dbp|$ADMINPW|smtp-secret' '$tmp/seed.txt'"
no "seed refuses an env file readable by others" S --env "$tmp/env644" --check

echo "=== mutation: without php -d disable_functions= the installer dies on a host that disables shell_exec"
sed 's/php -d disable_functions= tools/php tools/' "$root/scripts/install-shared.sh" >"$tmp/install-mut.sh"; chmod +x "$tmp/install-mut.sh"
mariadb -e "DROP DATABASE \`$dbn\`; CREATE DATABASE \`$dbn\` CHARACTER SET utf8mb4; GRANT ALL ON \`$dbn\`.* TO '$dbu'@'localhost'"
cp "$cfg" "$tmp/cfg.keep"; sed -i 's/^installed = On/installed = Off/' "$cfg"
mkenv "$tmp/envmut"; sed -i "s#^ADMIN_PASSWORD=.*#ADMIN_PASSWORD=$ADMINPW#" "$tmp/envmut"
no "mutation: the installer without the flag fails (silently) when shell_exec is disabled" env STUB_SOCKET_STDIN=1 WORJ_SSH="$tmp/ssh" "$tmp/install-mut.sh" --env "$tmp/envmut" </dev/null
grep -v 'for _ in 1 2 3 4 5 6 7 8' "$root/scripts/install-shared.sh" >"$tmp/install-mut2.sh"; chmod +x "$tmp/install-mut2.sh"
cmp -s "$tmp/install-mut2.sh" "$root/scripts/install-shared.sh" && bad "mutation padding: the padding line was not found"
no "mutation: without the blank-line padding the installer quits early over a socket, and the script notices" env STUB_SOCKET_STDIN=1 WORJ_SSH="$tmp/ssh" "$tmp/install-mut2.sh" --env "$tmp/envmut" </dev/null
I --env "$tmp/envmut" >/dev/null 2>&1; rc=$?
yes "with the flag the installer succeeds on the same host settings (exit $rc)" test "$rc" = 0
cp "$tmp/cfg.keep" "$cfg"

echo "=== --finish"
I --env "$tmp/env" --finish --check >"$tmp/fcheck.txt" 2>&1
yes "--finish --check changes nothing" bash -c "grep -q '^ADMIN_PASSWORD=' '$tmp/env' && [ \"\$(mariadb -N '$dbn' -e \"select coalesce(must_change_password,0) from users where username='worjadmin'\")\" = 0 ]"
I --env "$tmp/env" --finish >"$tmp/finish.txt" 2>&1; rc=$?
yes "--finish succeeds (exit $rc)" test "$rc" = 0
yes "the administrator must change the initial password" test "$(mariadb -N "$dbn" -e "select must_change_password from users where username='worjadmin'")" = 1
yes "ADMIN_PASSWORD was removed from the env file" bash -c "! grep -q '^ADMIN_PASSWORD=' '$tmp/env'"
yes "the env file is still mode 600" test "$(stat -c %a "$tmp/env")" = 600
yes "--finish printed no secret" bash -c "! grep -qE '$dbp|$ADMINPW|smtp-secret' '$tmp/finish.txt'"

echo "=== --launch-check (the launch gate)"
I --env "$tmp/env" --launch-check >"$tmp/launch.txt" 2>&1; rc=$?
yes "--launch-check FAILS on a placeholder host (journal.example.org; exit $rc)" test "$rc" = 1
yes "...naming the placeholder host rule" grep -qi 'placeholder host' "$tmp/launch.txt"
yes "--launch-check printed no secret" bash -c "! grep -qE '$dbp|$ADMINPW|smtp-secret' '$tmp/launch.txt'"

echo "=== re-run is idempotent"
sum1="$(sha256sum "$cfg" | cut -d' ' -f1)"
I --env "$tmp/env" >"$tmp/again.txt" 2>&1; rc=$?
yes "the second run succeeds (exit $rc)" test "$rc" = 0
yes "it says OJS is already installed" grep -q 'already installed' "$tmp/again.txt"
yes "config.inc.php is byte for byte unchanged" test "$sum1" = "$(sha256sum "$cfg" | cut -d' ' -f1)"

echo "=== the installer's weak defaults are repaired"
sed -i 's/^salt = .*/salt = "YouMustSetASecretKeyHere!!"/; s/^allowed_hosts = .*/allowed_hosts = '"'"'[""]'"'"'/' "$cfg"
I --env "$tmp/env" >/dev/null 2>&1
yes "a default salt and an empty allowed_hosts are repaired on the next run" python3 -I "$root/scripts/check-live-config.py" "$cfg" --host "$H" --web-root "$R/public_html"

echo "=== after --finish the seed is refused (the initial password is gone)"
no "seed-shared.sh refuses without ADMIN_PASSWORD" S --env "$tmp/env" --check

echo "$pass PASS, $fail FAIL"
exit "$fail"
