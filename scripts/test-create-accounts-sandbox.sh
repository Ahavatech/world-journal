#!/usr/bin/env bash
# scripts/create-accounts-shared.sh and scripts/lib/create-accounts.php, and the theme's first-login welcome box, against the SANDBOX journal.
#   scripts/test-create-accounts-sandbox.sh      needs the sandbox up (make sandbox-up sandbox-seed)
# The sandbox database is snapshotted first and restored on exit.
# shellcheck disable=SC2317
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/.env.sandbox"
core="$root/ojs-core"; base="${SANDBOX_URL:-http://127.0.0.1:8082}"
curl -s -o /dev/null -m 5 --noproxy '*' "$base/worj/" || { echo "sandbox not running (make sandbox-up sandbox-seed)"; exit 2; }
tmp="$(mktemp -d)"
mariadb-dump "$SANDBOX_DB_NAME" >"$tmp/db.sql" 2>/dev/null || mysqldump "$SANDBOX_DB_NAME" >"$tmp/db.sql"
restore() {
  mariadb -e "DROP DATABASE IF EXISTS \`$SANDBOX_DB_NAME\`; CREATE DATABASE \`$SANDBOX_DB_NAME\` CHARACTER SET utf8mb4" && mariadb "$SANDBOX_DB_NAME" <"$tmp/db.sql"
  find "$core/cache" -type f -delete 2>/dev/null
  rm -rf -- "${tmp:?}"
}
trap restore EXIT
fail=0; pass=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
CA() { "$root/scripts/create-accounts-shared.sh" --local-ojs "$core" "$@"; }
q() { mariadb -N "$SANDBOX_DB_NAME" -e "$1"; }
has() { grep -qF -- "$2" <<<"$1"; }
users() { q "select count(*) from users"; }

echo "=== dry run"
n0="$(users)"
CA >"$tmp/dry.txt" 2>&1; rc=$?
yes "exits 0 and prints WOULD lines, no password (exit $rc)" bash -c "[ $rc = 0 ] && grep -q '^WOULD: create johnpaul' '$tmp/dry.txt' && grep -q '^WOULD: create danwilliams' '$tmp/dry.txt' && ! grep -qi 'TEMPORARY PASSWORDS' '$tmp/dry.txt'"
yes "wrote nothing" test "$n0" = "$(users)"

echo "=== apply"
CA --apply >"$tmp/apply.txt" 2>&1; rc=$?
yes "exits 0 (exit $rc)" test "$rc" = 0
yes "two users were added" test "$(users)" = "$((n0 + 2))"
yes "Journal editor role on johnpaul" test "$(q "select s.setting_value from users u join user_user_groups x using(user_id) join user_group_settings s on s.user_group_id=x.user_group_id and s.setting_name='name' and s.locale='en' where u.username='johnpaul'")" = "Journal editor"
yes "Section editor role on danwilliams" test "$(q "select s.setting_value from users u join user_user_groups x using(user_id) join user_group_settings s on s.user_group_id=x.user_group_id and s.setting_name='name' and s.locale='en' where u.username='danwilliams'")" = "Section editor"
yes "danwilliams is assigned to the section(s)" test "$(q "select count(*) from subeditor_submission_group g join users u using(user_id) where u.username='danwilliams'")" -ge 1
yes "both must change their password at first login" test "$(q "select count(*) from users where username in ('johnpaul','danwilliams') and must_change_password=1")" = 2
yes "both are enabled" test "$(q "select count(*) from users where username in ('johnpaul','danwilliams') and disabled=0")" = 2
pwj="$(sed -n 's/^  johnpaul  *//p' "$tmp/apply.txt")"; pwd2="$(sed -n 's/^  danwilliams  *//p' "$tmp/apply.txt")"
yes "each temporary password is shown once, is long enough (>=16) and differs" bash -c "[ ${#pwj} -ge 16 ] && [ ${#pwd2} -ge 16 ] && [ '$pwj' != '$pwd2' ]"
yes "the database stores a hash, not the password" bash -c "! mariadb -N $SANDBOX_DB_NAME -e 'select password from users' | grep -qF -- '$pwj'"

echo "=== forced change at the first login (real HTTP login)"
login() { # user password -> prints the Location header of the sign-in
  local jar="$tmp/jar.$1"; rm -f "$jar"
  local tok; tok="$(curl -s --noproxy '*' -c "$jar" "$base/worj/login" | sed -n 's/.*name="csrfToken" value="\([^"]*\)".*/\1/p' | sed -n 1p)"
  curl -s --noproxy '*' -b "$jar" -c "$jar" -D - -o /dev/null --data-urlencode "username=$1" --data-urlencode "password=$2" --data-urlencode "csrfToken=$tok" "$base/worj/login/signIn" | tr -d '\r' | sed -n 's/^[Ll]ocation: //p'
}
yes "johnpaul with the temporary password is sent to the change-password page" has "$(login johnpaul "$pwj")" "changePassword"
yes "danwilliams likewise" has "$(login danwilliams "$pwd2")" "changePassword"
yes "a wrong password is not sent there" bash -c "! grep -q changePassword <<<'$(login johnpaul wrong-password-123)'"

echo "=== the welcome box"
q "update users set must_change_password=0 where username='johnpaul'"
find "$core/cache" -type f -delete 2>/dev/null
login johnpaul "$pwj" >/dev/null
home="$(curl -s --noproxy '*' -b "$tmp/jar.johnpaul" "$base/worj/")"
yes "a new editor sees the welcome box with the editor line" bash -c "grep -qF 'Four quick steps' <<<'$(printf '%s' "$home" | tr -d "'")' && grep -qF 'Editors: your dashboard' <<<'$(printf '%s' "$home" | tr -d "'")'"
yes "a visitor who is not logged in does not" bash -c "! curl -s --noproxy '*' $base/worj/ | grep -qF 'Four quick steps'"
q "update users set date_registered='2020-01-01 00:00:00' where username='johnpaul'"
home="$(curl -s --noproxy '*' -b "$tmp/jar.johnpaul" "$base/worj/")"
yes "after 14 days it is gone" bash -c "! grep -qF 'Four quick steps' <<<'$(printf '%s' "$home" | tr -d "'")'"

echo "=== refusals"
n1="$(users)"
CA --apply >"$tmp/again.txt" 2>&1; rc=$?
yes "running it again is refused (exit $rc), and nothing is written" bash -c "[ $rc = 1 ] && grep -q 'already has an account' '$tmp/again.txt' && [ '$n1' = '$(users)' ]"
CA --apply --account "newone,newone@example.org,A,B,No Such Role" >"$tmp/role.txt" 2>&1; rc=$?
yes "an unknown role is refused" bash -c "[ $rc = 1 ] && grep -q \"no role named\" '$tmp/role.txt' && [ '$n1' = '$(users)' ]"
CA --apply --account "good1,good1@example.org,A,B,Journal editor" --account "johnpaul,x@example.org,A,B,Journal editor" >"$tmp/mix.txt" 2>&1; rc=$?
yes "one bad entry stops the good one too (all or nothing)" bash -c "[ $rc = 1 ] && [ '$n1' = '$(users)' ]"
CA --account "short,not-an-email,A,B,Journal editor" >"$tmp/em.txt" 2>&1; rc=$?
yes "a bad email is refused" test "$rc" = 1

echo "=== --tidy-admin"
aid="$(q "select user_id from users order by user_id limit 1")"; adun="$(q "select username from users where user_id=$aid")"
q "insert into user_user_groups (user_id,user_group_id,date_start) select $aid, user_group_id, now() from user_groups where user_group_id in (14,16)"
CA --tidy-admin --admin-username "$adun" --account "tidy1,tidy1@example.org,T,Idy,Journal editor" >"$tmp/t1.txt" 2>&1
yes "the dry run names the roles it would remove and removes none" bash -c "grep -q 'WOULD: remove the Author role' '$tmp/t1.txt' && [ \$(mariadb -N $SANDBOX_DB_NAME -e 'select count(*) from user_user_groups where user_id=$aid and user_group_id in (14,16)') = 2 ]"
CA --apply --tidy-admin --admin-username "$adun" --account "tidy1,tidy1@example.org,T,Idy,Journal editor" >"$tmp/t2.txt" 2>&1
yes "--apply removes Author and Reviewer from the administrator and keeps Site administrator" bash -c "[ \$(mariadb -N $SANDBOX_DB_NAME -e 'select count(*) from user_user_groups where user_id=$aid and user_group_id in (14,16)') = 0 ] && [ \$(mariadb -N $SANDBOX_DB_NAME -e 'select count(*) from user_user_groups where user_id=$aid and user_group_id=1') = 1 ]"

echo "=== no password leaks into the log lines"
yes "the output other than the password block has no password" bash -c "! sed '/TEMPORARY PASSWORDS/,\$d' '$tmp/apply.txt' | grep -qF -- '$pwj'"
echo; echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
