#!/usr/bin/env bash
# The client's own text loaded into the SANDBOX journal and read back over HTTP: what replaces a placeholder, what must stay a
# placeholder, that a person's edit is never overwritten, and that the sandbox is put back afterwards.
#   scripts/test-client-content-sandbox.sh      needs the sandbox up (make sandbox-up sandbox-seed) and Playwright
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/.env.sandbox"
export NODE_PATH="${NODE_PATH:-/opt/node22/lib/node_modules}"
base="${SANDBOX_URL:-http://127.0.0.1:8082}"
curl -s -o /dev/null -m 5 --noproxy '*' "$base/worj/" || { echo "sandbox not running (make sandbox-up sandbox-seed)"; exit 2; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "${tmp:?}"' EXIT
fail=0; pass=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
page() { curl -s --noproxy '*' -m 30 "$base/worj/$1"; }
has() { grep -qF -- "$2" <<<"$1"; }
ann() { (cd "$root" && N=300000 node scripts/sandbox-api.js GET '/worj/api/v1/announcements?count=100') | sed 's/^[0-9]* //'; }
seed() { (cd "$root" && env "$@" node scripts/sandbox-seed.js) >"$tmp/seed.txt" 2>&1; }
restore() { # put the sandbox journal back to placeholders only
  for id in $(ann | python3 -I -c "import json,sys; d=json.load(sys.stdin); print(' '.join(str(i['id']) for i in d['items'] if (i.get('title') or {}).get('en')=='Call for Reviewers'))"); do
    (cd "$root" && node scripts/sandbox-api.js DELETE "/worj/api/v1/announcements/$id") >/dev/null 2>&1
  done
  mariadb "$SANDBOX_DB_NAME" -e "DELETE s FROM navigation_menu_item_settings s JOIN navigation_menu_items i ON i.navigation_menu_item_id = s.navigation_menu_item_id WHERE i.path='disclaimer'; DELETE FROM navigation_menu_items WHERE path='disclaimer'"
  seed SANDBOX_RESET_CONTENT=1
  # the default seed creates missing pages only; replacing the client's pages with placeholders again is the local --force-sandbox mode
  (cd "$root" && php scripts/import-pages.php --journal=worj --force-sandbox) >/dev/null 2>&1
}
PH='[PLACEHOLDER: replace with client-approved text]'
CB='[PLACEHOLDER: client text received 2026-11-11'

echo "=== baseline: placeholders only"
restore; yes "the sandbox is restored to placeholders (default seed exit status 0)" test "$?" = 0
yes "/about is the placeholder" has "$(page about)" "$PH"
yes "/disclaimer exists as a placeholder page" has "$(page disclaimer)" "$PH"
yes "no client announcement yet" bash -c "! grep -q 'Call for Reviewers' <<<'$(ann | tr -d "'")'"

echo "=== the client's text"
seed WORJ_CLIENT_CONTENT=1; rc=$?; yes "the seed with the client's text succeeds (exit $rc)" test "$rc" = 0
a="$(page about)"
yes "/about: the client's About text" has "$a" "international, open-access, peer-reviewed, multidisciplinary scientific journal"
yes "/about: carries its pending banner" has "$a" "$CB"
yes "/about: the publisher stays a placeholder" has "$a" "publisher name and address"
yes "/aims-and-scope: the groups" has "$(page aims-and-scope)" "Digital Humanities and Emerging Technologies"
yes "/about/privacy: the client's privacy text" has "$(page about/privacy)" "respects and protects the privacy of its authors, reviewers, editors, and readers"
yes "/about/submissions: the client's guidelines" has "$(page about/submissions)" "Manuscript Preparation"
yes "/disclaimer: the client's text" has "$(page disclaimer)" "solely those of the respective authors"
yes "/open-access: the access and APC policy" has "$(page open-access)" "Access and Article Processing Charge (APC) Policy"
yes "/peer-review: the client's policy" has "$(page peer-review)" "Initial Editorial Screening"
yes "/publication-ethics: the client's policy" has "$(page publication-ethics)" "Similarity Threshold"
c="$(page copyright-licensing)"
yes "/copyright-licensing: the client's terms with the blank licence left as a placeholder" bash -c "grep -qF 'Under this licence' <<<'$(printf '%s' "$c" | tr -d "'")' && grep -qF 'PLACEHOLDER: licence name' <<<'$(printf '%s' "$c" | tr -d "'")'"
yes "/awards: the client's criteria" has "$(page awards)" "Recognizing Excellence. Advancing Knowledge. Inspiring Innovation."
w="$(page awards-winners)"
yes "/awards-winners: no 'have been recognized' claim, a placeholder instead" bash -c "! grep -qF 'have been recognized' <<<'$(printf '%s' "$w" | tr -d "'")' && grep -qF 'PLACEHOLDER: names, affiliations' <<<'$(printf '%s' "$w" | tr -d "'")'"
yes "the pages the client did not supply stay placeholders (/archiving)" has "$(page archiving)" "$PH"
yes "...and the editorial team (no names, no consent)" bash -c "page_out=\"\$(curl -s --noproxy '*' '$base/worj/about/editorialMasthead')\"; grep -qF '$PH' <<<\"\$page_out\" && ! grep -qiE 'Paul John|Aramide|Kaushik' <<<\"\$page_out\""
yes "...and the contact page keeps its placeholder" has "$(page about/contact)" "PLACEHOLDER: contact"
yes "the client's announcement exists" test "$(ann | grep -o '"title":{"en":"Call for Reviewers"' | wc -l)" -ge 1

echo "=== a second run changes nothing and creates no duplicate"
n1="$(ann | grep -o '"title":{"en":"Call for Reviewers"' | wc -l)"
seed WORJ_CLIENT_CONTENT=1; rc=$?
yes "the second run succeeds (exit $rc)" test "$rc" = 0
yes "...says the announcement exists" grep -q 'exists; create-only' "$tmp/seed.txt"
yes "...and there is still exactly one (was $n1)" test "$(ann | grep -o '"title":{"en":"Call for Reviewers"' | wc -l)" = "$n1"

echo "=== a person's edit is never overwritten"
(cd "$root" && node scripts/sandbox-api.js PUT /worj/api/v1/contexts/1 '{"about":{"en":"<p>Edited by a person, no banner.</p>"}}') >/dev/null 2>&1
mariadb "$SANDBOX_DB_NAME" -e "UPDATE navigation_menu_item_settings s JOIN navigation_menu_items i ON i.navigation_menu_item_id = s.navigation_menu_item_id SET s.setting_value='<p>Page edited by a person, no banner.</p>' WHERE i.path='disclaimer' AND s.setting_name='content'"
seed WORJ_CLIENT_CONTENT=1
yes "the edited setting text (/about) is left alone" has "$(page about)" "Edited by a person"
yes "the edited custom page (/disclaimer) is left alone" has "$(page disclaimer)" "Page edited by a person"

echo "=== the sandbox is put back"
restore; rc=$?
yes "restoring succeeds (exit $rc)" test "$rc" = 0
yes "/about is the placeholder again" has "$(page about)" "$PH"
yes "/disclaimer is the placeholder again" has "$(page disclaimer)" "$PH"
yes "/peer-review is the placeholder again" has "$(page peer-review)" "$PH"
yes "the client's announcement is gone" bash -c "! grep -q 'Call for Reviewers' <<<'$(ann | tr -d "'")'"

echo "$pass PASS, $fail FAIL"
exit "$fail"
