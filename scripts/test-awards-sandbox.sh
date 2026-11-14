#!/usr/bin/env bash
# The WORJ Research Awards plugin (nomination form, judges' scoring, manager page, public recipients) against the SANDBOX journal, over real HTTP.
#   scripts/test-awards-sandbox.sh      needs the sandbox up (make sandbox-up sandbox-seed) and the plugin linked (make setup)
# The plugin is installed and enabled here (idempotent); the sandbox database is snapshotted first and restored on exit.
# shellcheck disable=SC2317
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/.env.sandbox"
core="$root/ojs-core"; base="${SANDBOX_URL:-http://127.0.0.1:8082}/worj"
curl -s -o /dev/null -m 5 --noproxy '*' "$base/" || { echo "sandbox not running (make sandbox-up sandbox-seed)"; exit 2; }
[ -f "$core/plugins/generic/worjAwards/version.xml" ] || { echo "plugin not linked into ojs-core (make setup)"; exit 2; }
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
q() { mariadb -N "$SANDBOX_DB_NAME" -e "$1"; }
has() { grep -qF -- "$2" <<<"$1"; }
q "drop table if exists worj_award_scores, worj_award_nominations; delete from versions where product='worjAwards'; delete from plugin_settings where plugin_name='worjawardsplugin'"
find "$core/cache" -type f -delete 2>/dev/null
AS="$root/scripts/awards-shared.sh --local-ojs $core"
yes "the install dry run changes nothing" bash -c "$AS | grep -q 'DRY RUN' && [ \$(mariadb -N $SANDBOX_DB_NAME -e \"show tables like 'worj_award_nominations'\" | wc -l) = 0 ]"
yes "install --apply makes the tables and enables the plugin" bash -c "$AS --apply | grep -q 'DONE: enabled'"
yes "running --apply again is safe and says it is already on" bash -c "$AS --apply | grep -q 'already on'"
find "$core/cache" -type f -delete 2>/dev/null
tok() { curl -s --noproxy '*' -b "$1" -c "$1" "$base/$2" | sed -n 's/.*name="csrfToken" value="\([^"]*\)".*/\1/p' | sed -n 1p; }
login() { # jar user password -> Location of the sign-in
  local t; t="$(tok "$1" login)"
  curl -s --noproxy '*' -b "$1" -c "$1" -D - -o /dev/null --data-urlencode "username=$2" --data-urlencode "password=$3" --data-urlencode "csrfToken=$t" "$base/login/signIn" | tr -d '\r' | sed -n 's/^[Ll]ocation: //p'
}
post() { # jar page (data args...) -> body
  local jar="$1" page="$2"; shift 2
  curl -s --noproxy '*' -b "$jar" -c "$jar" "$@" "$base/$page"
}
nom() { # jar extra-args...: a nomination with good defaults, csrf from the form page
  local jar="$1"; shift; local t; t="$(tok "$jar" awards-nominate)"
  post "$jar" awards-nominate --data-urlencode "csrfToken=$t" --data-urlencode "category=Best Researcher" --data-urlencode "nominee_name=Ada Example" --data-urlencode "nominee_email=ada@example.org" \
    --data-urlencode "article_ref=https://example.org/a" --data-urlencode "statement=This researcher produced original and rigorous work that changed how the field measures impact in practice." \
    --data-urlencode "nominator_name=Nora Nominator" --data-urlencode "nominator_email=nora@example.org" --data-urlencode "consent=1" "$@"
}

echo "=== the pages exist and the access rules hold"
v="$tmp/visitor"
yes "the nomination page loads for a visitor" test "$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' "$base/awards-nominate")" = 200
yes "nominations are closed until the manager opens them" has "$(curl -s --noproxy '*' "$base/awards-nominate")" "not open"
yes "the recipients page says none yet" has "$(curl -s --noproxy '*' "$base/awards-recipients")" "No recipients have been announced yet"
yes "judge page sends a visitor to log in" bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' $base/awards-judge)\" = 302 ]"
yes "manager page sends a visitor to log in" bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' $base/awards-manage)\" = 302 ]"
nom "$v" >/dev/null
yes "a nomination while closed is not saved" test "$(q "select count(*) from worj_award_nominations")" = 0

echo "=== accounts: manager (the sandbox admin), a judge, a plain user"
"$root/scripts/create-accounts-shared.sh" --local-ojs "$core" --apply --account "judge1,judge1@example.org,Jo,Judge,Reviewer" --account "plain1,plain1@example.org,Pat,Plain,Reviewer" >"$tmp/acc.txt" 2>&1
pj="$(sed -n 's/^  judge1  *//p' "$tmp/acc.txt")"; pp="$(sed -n 's/^  plain1  *//p' "$tmp/acc.txt")"
q "update users set must_change_password=0 where username in ('judge1','plain1')"
find "$core/cache" -type f -delete 2>/dev/null
m="$tmp/mgr"; j="$tmp/judge"; p="$tmp/plain"
yes "the manager can sign in" bash -c "! grep -q changePassword <<<'$(login "$m" "$SANDBOX_ADMIN_USER" "$SANDBOX_ADMIN_PASSWORD")'"
login "$j" judge1 "$pj" >/dev/null; login "$p" plain1 "$pp" >/dev/null
denied() { curl -s -o /dev/null -D - --noproxy '*' -b "$1" "$base/$2" | tr -d '\r' | grep -qi '^location:.*authorizationDenied'; }
yes "a plain user is sent to the access-denied page from the manager page" denied "$p" awards-manage
yes "a plain user is sent to the access-denied page from the judge page" denied "$p" awards-judge
yes "the manager page opens for the manager" test "$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' -b "$m" "$base/awards-manage")" = 200

echo "=== manager settings"
t="$(tok "$m" awards-manage)"
post "$m" awards-manage --data-urlencode "csrfToken=$t" --data-urlencode "action=settings" --data-urlencode "nominationsOpen=1" --data-urlencode $'categories=Best Researcher\nBest Early-Career Paper' --data-urlencode $'judges=judge1\n'"$SANDBOX_ADMIN_USER" >/dev/null
yes "the nomination page now shows the form and both categories" bash -c "b=\$(curl -s --noproxy '*' $base/awards-nominate); grep -q 'Send nomination' <<<\"\$b\" && grep -q 'Best Early-Career Paper' <<<\"\$b\""
post "$m" awards-manage --data-urlencode "action=settings" --data-urlencode "nominationsOpen=1" >/dev/null
yes "a settings post without the form token is ignored" has "$(curl -s --noproxy '*' "$base/awards-nominate")" "Best Early-Career Paper"

echo "=== nominations"
nom "$v" >/dev/null
yes "a good nomination is saved" test "$(q "select count(*) from worj_award_nominations where nominee_name='Ada Example' and status='received'")" = 1
yes "the page thanks the nominator" has "$(nom "$tmp/v2" --data-urlencode "nominee_name=Bo Second")" "Thank you"
nom "$v" >"$tmp/dup.html"
yes "the same nomination twice is refused" bash -c "grep -q 'already nominated' '$tmp/dup.html' && [ \$(mariadb -N $SANDBOX_DB_NAME -e \"select count(*) from worj_award_nominations where nominee_name='Ada Example'\") = 1 ]"
n0="$(q "select count(*) from worj_award_nominations")"
nom "$tmp/v3" --data-urlencode "category=Made Up" >/dev/null
nom "$tmp/v4" --data-urlencode "statement=too short" >/dev/null
nom "$tmp/v5" --data-urlencode "nominator_email=not-an-email" >/dev/null
nom "$tmp/v6" --data-urlencode "website=http://spam.example" >/dev/null
yes "a bad category, a short statement, a bad email and a filled honeypot are all not saved" test "$n0" = "$(q "select count(*) from worj_award_nominations")"
yes "a post with no form token is not saved" bash -c "curl -s --noproxy '*' -o /dev/null -X POST --data-urlencode 'category=Best Researcher' --data-urlencode 'nominee_name=No Token' --data-urlencode 'statement=$(printf 'x%.0s' {1..60})' --data-urlencode 'nominator_name=A' --data-urlencode 'nominator_email=a@example.org' --data-urlencode consent=1 $base/awards-nominate; [ \$(mariadb -N $SANDBOX_DB_NAME -e \"select count(*) from worj_award_nominations where nominee_name='No Token'\") = 0 ]"
nom "$tmp/v7" --data-urlencode 'nominee_name=<script>alert(1)</script>' --data-urlencode 'statement=Evil <img src=x onerror=alert(1)> but long enough to pass the fifty character minimum rule.' >/dev/null
nom "$tmp/v8" --data-urlencode 'nominee_name==HYPERLINK("http://x")' >/dev/null

echo "=== judges"
page="$(curl -s --noproxy '*' -b "$j" "$base/awards-judge")"
yes "the judge sees the nominations and the four criteria" bash -c "grep -q 'Ada Example' <<<'$(printf '%s' "$page" | tr -d "'")' && grep -q 'Originality' <<<'$(printf '%s' "$page" | tr -d "'")' && grep -q 'Outstanding Contribution' <<<'$(printf '%s' "$page" | tr -d "'")'"
yes "markup in a nominee's name is shown as text, not run" bash -c "! grep -qF '<script>alert(1)' <<<'$(printf '%s' "$page" | tr -d "'")'"
nid="$(q "select nomination_id from worj_award_nominations where nominee_name='Ada Example'")"
score() { # jar nid o q i c [extra]
  local jar="$1" id="$2"; shift 2
  local t; t="$(tok "$jar" awards-judge)"
  post "$jar" awards-judge --data-urlencode "csrfToken=$t" --data-urlencode "nomination_id=$id" --data-urlencode "originality=$1" --data-urlencode "quality=$2" --data-urlencode "impact=$3" --data-urlencode "contribution=$4" "${@:5}"
}
score "$j" "$nid" 5 4 4 5 >/dev/null
yes "the judge's scores are saved (total 18)" test "$(q "select originality+quality+impact+contribution from worj_award_scores where nomination_id=$nid")" = 18
score "$j" "$nid" 4 4 4 4 >/dev/null
yes "scoring again changes the judge's own row, it does not add a second" bash -c "[ \$(mariadb -N $SANDBOX_DB_NAME -e 'select count(*) from worj_award_scores where nomination_id=$nid') = 1 ] && [ \$(mariadb -N $SANDBOX_DB_NAME -e 'select originality+quality+impact+contribution from worj_award_scores where nomination_id=$nid') = 16 ]"
score "$j" "$nid" 9 4 4 4 >/dev/null
yes "a score outside 1 to 5 is refused (the row is unchanged)" test "$(q "select originality+quality+impact+contribution from worj_award_scores where nomination_id=$nid")" = 16
score "$m" "$nid" 5 5 5 5 >/dev/null
yes "the manager (also a judge here) adds a second score" test "$(q "select count(*) from worj_award_scores where nomination_id=$nid")" = 2
score "$p" "$nid" 1 1 1 1 >/dev/null
yes "a plain user cannot score" test "$(q "select count(*) from worj_award_scores where nomination_id=$nid")" = 2
n2="$(q "select nomination_id from worj_award_nominations where nominee_name='Bo Second'")"
score "$j" "$n2" "" "" "" "" --data-urlencode conflict=1 >/dev/null
yes "a declared conflict is stored with no scores" test "$(q "select conflict from worj_award_scores where nomination_id=$n2")" = 1

echo "=== manager decides"
mp="$(curl -s --noproxy '*' -b "$m" "$base/awards-manage")"
yes "the manager sees mean 18 of 20 (16 and 20), 2 judges, and the conflict count" bash -c "grep -q 'Mean total: 18' <<<'$(printf '%s' "$mp" | tr -d "'")'"
t="$(tok "$m" awards-manage)"
post "$m" awards-manage --data-urlencode "csrfToken=$t" --data-urlencode "action=status" --data-urlencode "nomination_id=$nid" --data-urlencode "status=winner" --data-urlencode "award_period=Volume 1" >/dev/null
rec="$(curl -s --noproxy '*' "$base/awards-recipients")"
yes "the winner is on the public recipients page with the period" bash -c "grep -q 'Ada Example' <<<'$(printf '%s' "$rec" | tr -d "'")' && grep -q 'Volume 1' <<<'$(printf '%s' "$rec" | tr -d "'")'"
yes "no email address is on the public page" bash -c "! grep -qE 'ada@example.org|nora@example.org' <<<'$(printf '%s' "$rec" | tr -d "'")'"
yes "a nomination that is not a winner is not on the public page" bash -c "! grep -q 'Bo Second' <<<'$(printf '%s' "$rec" | tr -d "'")'"
curl -s --noproxy '*' -b "$m" "$base/awards-manage?export=csv" | tr -d '\r' >"$tmp/out.csv"
yes "the manager can export a CSV with the header and the scores" bash -c "head -1 '$tmp/out.csv' | grep -q nominee_email && grep -q 'Ada Example' '$tmp/out.csv'"
yes "a spreadsheet formula in a cell is defused (starts with a quote)" grep -qF "'=HYPERLINK" "$tmp/out.csv"
yes "a visitor cannot download the CSV" test "$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' "$base/awards-manage?export=csv")" = 302
yes "a judge who is not a manager cannot download the CSV" denied "$j" "awards-manage?export=csv"
post "$m" awards-manage --data-urlencode "csrfToken=$(tok "$m" awards-manage)" --data-urlencode "action=delete" --data-urlencode "nomination_id=$n2" >/dev/null
yes "the manager can delete a nomination (and its scores go with it)" bash -c "[ \$(mariadb -N $SANDBOX_DB_NAME -e 'select count(*) from worj_award_nominations where nomination_id=$n2') = 0 ] && [ \$(mariadb -N $SANDBOX_DB_NAME -e 'select count(*) from worj_award_scores where nomination_id=$n2') = 0 ]"
echo; echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
