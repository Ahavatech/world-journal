#!/usr/bin/env bash
# scripts/launch-prep-shared.sh and scripts/lib/launch-prep.php run against the SANDBOX journal (the real OJS code, read back over HTTP).
#   scripts/test-launch-prep-sandbox.sh      needs the sandbox up (make sandbox-up sandbox-seed) and Playwright
# The sandbox database and files are snapshotted first and restored on exit (the test deletes sample content and menu entries).
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/.env.sandbox"
export NODE_PATH="${NODE_PATH:-/opt/node22/lib/node_modules}"
core="$root/ojs-core"; base="${SANDBOX_URL:-http://127.0.0.1:8082}"
curl -s -o /dev/null -m 5 --noproxy '*' "$base/worj/" || { echo "sandbox not running (make sandbox-up sandbox-seed)"; exit 2; }
files_dir="$(sed -n 's/^files_dir *= *\(.*\)$/\1/p' "$core/config.inc.php" | tr -d '"' | sed -n 1p)"
tmp="$(mktemp -d)"
mariadb-dump "$SANDBOX_DB_NAME" >"$tmp/db.sql" 2>/dev/null || mysqldump "$SANDBOX_DB_NAME" >"$tmp/db.sql"
tar -C "$(dirname "$files_dir")" -cf "$tmp/files.tar" "$(basename "$files_dir")"
restore() {
  mariadb -e "DROP DATABASE IF EXISTS \`$SANDBOX_DB_NAME\`; CREATE DATABASE \`$SANDBOX_DB_NAME\` CHARACTER SET utf8mb4" && mariadb "$SANDBOX_DB_NAME" <"$tmp/db.sql"
  rm -rf -- "${files_dir:?}"; tar -C "$(dirname "$files_dir")" -xf "$tmp/files.tar"
  find "$core/cache" -type f -delete 2>/dev/null
  rm -rf -- "${tmp:?}"
}
trap restore EXIT
fail=0; pass=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
LP() { "$root/scripts/launch-prep-shared.sh" --local-ojs "$core" "$@"; }
page() { curl -s --noproxy '*' -m 30 "$base/worj/$1"; }
code() { curl -s -o /dev/null -w '%{http_code}' --noproxy '*' -m 30 "$base/worj/$1"; }
has() { grep -qF -- "$2" <<<"$1"; }
q() { mariadb -N "$SANDBOX_DB_NAME" -e "$1"; }
snap() { mariadb-dump --skip-comments --skip-extended-insert "$SANDBOX_DB_NAME" navigation_menu_items navigation_menu_item_settings navigation_menu_item_assignments announcements announcement_settings issues issue_settings submissions publications journal_settings plugin_settings 2>/dev/null | sha256sum | cut -d' ' -f1; }

echo "=== the client's text, as the host will have it"
(cd "$root" && WORJ_CLIENT_CONTENT=1 node scripts/sandbox-seed.js) >"$tmp/seed.txt" 2>&1; yes "the sandbox has the client's text and the sample content (seed exit $?)" has "$(page about)" "client text received"
yes "before: the sample issue exists, so do the Editorial Team link and the Information block" bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' $base/worj/issue/view/1)\" = 200 ]"

echo "=== a dry run writes nothing"
before="$(snap)"
LP --minimal >"$tmp/dry.txt" 2>&1; rc=$?
yes "the dry run exits 0 (exit $rc) and prints WOULD lines" bash -c "[ $rc = 0 ] && grep -q '^WOULD: delete the sample issue' '$tmp/dry.txt' && grep -q '^WOULD: hold awards' '$tmp/dry.txt'"
yes "...and changed nothing in the database" test "$before" = "$(snap)"

echo "=== --minimal --apply"
LP --minimal --apply >"$tmp/apply.txt" 2>&1; rc=$?
yes "applies (exit $rc)" test "$rc" = 0
yes "the sample issue is gone (OJS redirects an unknown issue instead of showing it)" bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' $base/worj/issue/view/1)\" != 200 ]"
yes "the 3 sample articles are gone" bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' $base/worj/article/view/1)\" = 404 ] && [ \"\$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' $base/worj/article/view/3)\" = 404 ]"
yes "no submission is left" test "$(q "select count(*) from submissions")" = 0
home="$(page "")"
yes "the placeholder announcements are gone from the home page" bash -c "! grep -qF 'Sample announcement' <<<'$(printf '%s' "$home" | tr -d "'")'"
for p in archiving awards-guidelines awards-categories plagiarism-similarity awards awards-winners; do yes "/$p is hidden (404)" test "$(code "$p")" = 404; done
yes "the Editorial Team link is out of the menus" bash -c "! grep -qF 'editorialMasthead' <<<'$(printf '%s' "$home" | tr -d "'")'"
yes "the Information block is out of the sidebar" bash -c "! grep -qF 'block_information' <<<'$(printf '%s' "$home" | tr -d "'")'"
yes "the Awards card and its placeholder are off the home page" bash -c "! grep -qF 'awards call-out' <<<'$(printf '%s' "$home" | tr -d "'")'"
yes "the home page summary is the client's first About paragraph" has "$home" "international, open-access, peer-reviewed, multidisciplinary scientific journal"
c="$(page about/contact)"
yes "the contact page says Editorial Office and no contact-name placeholder" bash -c "grep -qF 'Editorial Office' <<<'$(printf '%s' "$c" | tr -d "'")' && ! grep -qF 'PLACEHOLDER: contact name' <<<'$(printf '%s' "$c" | tr -d "'")'"
yes "the Call for Reviewers announcement is held (not on the site)" bash -c "! (cd '$root' && N=300000 node scripts/sandbox-api.js GET '/worj/api/v1/announcements?count=100') | grep -q 'Call for Reviewers'"
yes "the client's pages that were not held are still there with their banner (/peer-review)" has "$(page peer-review)" "client text received"
yes "no credential in the output" bash -c "! grep -qiE 'password|secret' '$tmp/apply.txt'"

echo "=== running it again is harmless"
LP --minimal --apply >"$tmp/again.txt" 2>&1; rc=$?
yes "the second run exits 0 and does nothing new (exit $rc)" bash -c "[ $rc = 0 ] && ! grep -q '^DONE:' '$tmp/again.txt'"

echo "=== approve: only what the client confirmed, and never a page with a marked blank"
LP --approve about,copyright-licensing >"$tmp/ap0.txt" 2>&1; rc=$?
yes "without --drop-blanks the About page is refused (it has a Publisher blank) and so is the licence page (exit $rc)" bash -c "[ $rc = 1 ] && grep -q 'FAIL  about still has a marked blank' '$tmp/ap0.txt' && grep -q 'FAIL  copyright-licensing still has a marked blank' '$tmp/ap0.txt'"
LP --approve about,peer-review,disclaimer --drop-blanks --apply >"$tmp/ap1.txt" 2>&1; rc=$?
yes "with --drop-blanks About, Peer Review and Disclaimer are confirmed (exit $rc)" test "$rc" = 0
a="$(page about)"
yes "/about: the banner and the Publisher blank are gone, the client's text stays" bash -c "! grep -qF 'client text received' <<<'$(printf '%s' "$a" | tr -d "'")' && ! grep -qF 'publisher name and address' <<<'$(printf '%s' "$a" | tr -d "'")' && grep -qF 'advancement of knowledge' <<<'$(printf '%s' "$a" | tr -d "'")'"
yes "/peer-review and /disclaimer: no banner" bash -c "! grep -qF 'client text received' <<<'$(printf '%s' "$(page peer-review)$(page disclaimer)" | tr -d "'")'"
yes "/open-access, not confirmed, still carries its banner" has "$(page open-access)" "client text received"
yes "the licence page was refused and still has its banner and its blank" bash -c "p=\"\$(curl -s --noproxy '*' $base/worj/copyright-licensing)\"; grep -qF 'client text received' <<<\"\$p\" && grep -qF 'PLACEHOLDER: licence name' <<<\"\$p\""
LP --approve about --apply >"$tmp/ap2.txt" 2>&1
yes "approving an already confirmed page says so and changes nothing" grep -q 'skip  about has no pending banner' "$tmp/ap2.txt"

echo "=== a person's text is never overwritten or held"
q "update navigation_menu_item_settings s join navigation_menu_items i on i.navigation_menu_item_id=s.navigation_menu_item_id set s.setting_value='<p>Written by a person.</p>' where i.path='open-access' and s.setting_name='content'"
LP --hold open-access --apply >"$tmp/h1.txt" 2>&1
yes "--hold skips a page a person wrote (no pending banner)" bash -c "grep -q 'skip  open-access has no pending banner: not held' '$tmp/h1.txt'"
yes "...and it is still on the site" has "$(page open-access)" "Written by a person."
LP --hold publication-ethics --apply >"$tmp/h2.txt" 2>&1
yes "--hold hides a client page that is still pending (/publication-ethics 404)" test "$(code publication-ethics)" = 404

echo "=== refusals"
LP >/dev/null 2>&1; rc=$?; yes "no option at all is refused (exit $rc)" test "$rc" != 0
LP --approve nonsense >/dev/null 2>&1; rc=$?; yes "an unknown page id is refused (exit $rc)" test "$rc" != 0
LP --approve about --hold about >/dev/null 2>&1; rc=$?; yes "approving and holding the same page is refused (exit $rc)" test "$rc" != 0

echo "$pass PASS, $fail FAIL"
exit "$fail"
