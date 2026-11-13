#!/usr/bin/env bash
# Tests for scripts/check-client-content.py: it passes on the real client content and FAILS on each kind of tampering.
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf -- "${tmp:?}"' EXIT
fail=0; pass=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
no() { local name="$1"; shift; if "$@"; then bad "$name"; else ok "$name"; fi; }
C() { python3 -I "$root/scripts/check-client-content.py" "$@" >"$tmp/out.txt" 2>&1; }
fresh() { rm -rf "$tmp/cc"; cp -r "$root/ojs/client-content" "$tmp/cc"; }

yes "the client content passes (every block is a passage of the source)" C
fresh
sed -i 's/<p>We look forward to welcoming you to our team of reviewers.<\/p>/<p>We look forward to welcoming you to our team of reviewers and we guarantee a decision in 3 days.<\/p>/' "$tmp/cc/announcement-call-for-reviewers.html"
no "an invented sentence appended to the client's text is caught" C --dir "$tmp/cc"
yes "...and named" grep -q "not a passage of the client's text" "$tmp/out.txt"
fresh
sed -i 's/APC) of USD 50-100 per accepted/APC) of USD 25-100 per accepted/' "$tmp/cc/pages/author-guidelines.html"
no "a changed figure (the APC) is caught" C --dir "$tmp/cc"
fresh
sed -i '1d' "$tmp/cc/pages/about.html"
no "a page without its pending banner is caught" C --dir "$tmp/cc"
fresh
printf '<p>Invented paragraph with no source.</p>\n' >>"$tmp/cc/awards/winners.html"
no "an added paragraph is caught" C --dir "$tmp/cc"
fresh
printf '<p><a href="mailto:x@y.org">x@y.org</a></p>\n' >>"$tmp/cc/awards/winners.html"
no "an email address in a page is caught" C --dir "$tmp/cc"
fresh
sed -i 's/privacy@worldopenresearchjournal.com\./privacy@gmail.com./' "$tmp/cc/pages/privacy.html"
no "an outside address even inside an addendum span is caught" C --dir "$tmp/cc"
yes "...and named" grep -q "not one of the journal's own addresses" "$tmp/out.txt"
fresh
yes "the journal's own privacy alias inside an addendum span is accepted" grep -q 'privacy@worldopenresearchjournal.com' "$tmp/cc/pages/privacy.html"
fresh
python3 -I -c "
import json,sys
p='$tmp/cc/map.json'; d=json.load(open(p)); d['pages'].append({'id':'not-a-page','file':'pages/about.html'}); json.dump(d,open(p,'w'))"
no "a page id that does not exist on the site is caught" C --dir "$tmp/cc"
fresh
rm "$tmp/cc/pages/privacy.html"
no "a missing file is caught" C --dir "$tmp/cc"
yes "no reviewer's personal email address is in the client content (no consent to publish it)" bash -c "! grep -rqiE 'gmail|nayangoel|REDACTED' '$root/ojs/client-content/editorial-team.html' '$root/ojs/client-content/pages' '$root/ojs/client-content/awards'"
fresh
sed -i 's/<span class="worj-add">Assistant Editor<\/span>/<span class="worj-add">Deputy Chief Editor<\/span>/' "$tmp/cc/editorial-team.html"
no "a role that is not in the addendum is caught" C --dir "$tmp/cc"
yes "...and named" grep -q "not a passage of the addendum" "$tmp/out.txt"
fresh
sed -i 's/Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)/Creative Commons Attribution 4.0 International (CC BY 4.0)/' "$tmp/cc/pages/copyright-licensing.html"
no "a licence other than the one the addendum records is caught" C --dir "$tmp/cc"
fresh
sed -i 's/<li><strong>Sirma Angelova<\/strong><br>Chief Assistant/<li><strong>Sirma Angelova<\/strong><br>Professor and Chief Assistant/' "$tmp/cc/editorial-team.html"
no "an invented affiliation for a reviewer is caught" C --dir "$tmp/cc"
echo "$pass PASS, $fail FAIL"
exit "$fail"
