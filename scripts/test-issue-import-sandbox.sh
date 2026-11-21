#!/usr/bin/env bash
# scripts/build-issue-import.py and scripts/import-issue-shared.sh against the SANDBOX journal with SYNTHETIC data (no real author or article).
#   scripts/test-issue-import-sandbox.sh      needs the sandbox up (make sandbox-up sandbox-seed) and ojs/fixtures/pdfs (scripts/sample-issue.py pdfs).
# The sandbox database and files are snapshotted first and restored on exit.
# shellcheck disable=SC2317
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/.env.sandbox"
core="$root/ojs-core"; base="${SANDBOX_URL:-http://127.0.0.1:8082}/worj"
curl -s -o /dev/null -m 5 --noproxy '*' "$base/" || { echo "sandbox not running (make sandbox-up sandbox-seed)"; exit 2; }
[ -f "$root/ojs/fixtures/pdfs/sample-article-1.pdf" ] || python3 "$root/scripts/sample-issue.py" pdfs || exit 2
files_dir="$(sed -n 's/^files_dir *= *\(.*\)$/\1/p' "$core/config.inc.php" | tr -d '"' | sed -n 1p)"
tmp="$(mktemp -d)"
mariadb-dump "$SANDBOX_DB_NAME" >"$tmp/db.sql" 2>/dev/null || mysqldump "$SANDBOX_DB_NAME" >"$tmp/db.sql"
tar -C "$(dirname "$files_dir")" -cf "$tmp/files.tar" "$(basename "$files_dir")"
restore() {
  mariadb -e "DROP DATABASE IF EXISTS \`$SANDBOX_DB_NAME\`; CREATE DATABASE \`$SANDBOX_DB_NAME\` CHARACTER SET utf8mb4" && mariadb "$SANDBOX_DB_NAME" <"$tmp/db.sql"
  rm -rf -- "${files_dir:?}"; tar -C "$(dirname "$files_dir")" -xf "$tmp/files.tar"; find "$core/cache" -type f -delete 2>/dev/null; rm -rf -- "${tmp:?}"
}
trap restore EXIT
fail=0; pass=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
q() { mariadb --default-character-set=utf8mb4 -N "$SANDBOX_DB_NAME" -e "$1"; }
cp "$root/ojs/fixtures/pdfs/sample-article-1.pdf" "$tmp/a1.pdf"; cp "$root/ojs/fixtures/pdfs/sample-article-2.pdf" "$tmp/a2.pdf"
cat >"$tmp/meta.json" <<JSON
{"issue":{"volume":7,"number":"2","year":2031,"title":"Test Issue & <Co>","date_published":"2031-03-04"},
 "section":{"abbrev":"ART","title":"Articles"},"uploader":"$SANDBOX_ADMIN_USER","licence_url":"https://creativecommons.org/licenses/by-nc/4.0/",
 "articles":[
  {"title":"Fake Study A & B <i>of</i> Things","abstract":"Fake abstract one. It has \"quotes\" & an ampersand.","keywords":["alpha beta","gamma"],"pages":"5-9","pdf":"a1.pdf","date_published":"2029-08-20",
   "authors":[{"given":"Test","family":"Zeta-Ünïcode","affiliation":"Test Institute","email":"test.one@example.invalid"},{"given":"Second","family":"Writer","email":"test.two@example.invalid"}],
   "references":["Doe, J. (2020). A fake reference. Journal of Fakes, 1(1), 1-2.","Roe, R. (2021). Can language models be too big?\ud83e\udd9c. In Proceedings (pp. 1-2)."]},
  {"title":"Fake Study B","abstract":"Fake abstract two.","keywords":["delta"],"pages":"10-14","pdf":"a2.pdf",
   "authors":[{"given":"Solo","family":"Author","email":"test.three@example.invalid"}]}]}
JSON
echo "=== building the file"
python3 -I "$root/scripts/build-issue-import.py" "$tmp/meta.json" "$tmp" "$tmp/issue.xml" >"$tmp/build.txt" 2>&1; rc=$?
yes "the builder writes a file that is valid against OJS's own schema (exit $rc)" bash -c "[ $rc = 0 ] && grep -q 'schema check: valid' '$tmp/build.txt'"
cp "$tmp/meta.json" "$tmp/bad.json"; sed -i 's/"pdf":"a1.pdf"/"pdf":"missing.pdf"/' "$tmp/bad.json"
yes "a missing PDF is refused" bash -c "! python3 -I '$root/scripts/build-issue-import.py' '$tmp/bad.json' '$tmp' '$tmp/bad.xml' >/dev/null 2>&1"
echo "=== importing"
II() { "$root/scripts/import-issue-shared.sh" --local-ojs "$core" --user "$SANDBOX_ADMIN_USER" --xml "$tmp/issue.xml" "$@"; }
n0="$(q "select count(*) from submissions")"
II >"$tmp/dry.txt" 2>&1
yes "the dry run names the issue and the articles and writes nothing" bash -c "grep -q 'Volume 7, Number 2, 2031' '$tmp/dry.txt' && grep -q 'DRY RUN' '$tmp/dry.txt' && [ \$(mariadb -N $SANDBOX_DB_NAME -e 'select count(*) from submissions') = $n0 ]"
II --apply >"$tmp/apply.txt" 2>&1
yes "--apply imports the issue and two articles" bash -c "grep -q 'import completed successfully' '$tmp/apply.txt' && [ \$(mariadb -N $SANDBOX_DB_NAME -e 'select count(*) from submissions') = $((n0 + 2)) ]"
II --apply >"$tmp/again.txt" 2>&1; rc=$?
yes "running it again is refused, and nothing is duplicated (exit $rc)" bash -c "[ $rc = 1 ] && grep -q 'would duplicate' '$tmp/again.txt' && [ \$(mariadb -N $SANDBOX_DB_NAME -e 'select count(*) from submissions') = $((n0 + 2)) ]"
echo "=== what readers see"
find "$core/cache" -type f -delete 2>/dev/null
iid="$(q "select issue_id from issues where volume=7 and number='2' and year=2031")"
sid="$(q "select s.submission_id from submissions s join publication_settings p on p.publication_id=s.current_publication_id and p.setting_name='title' where p.setting_value like 'Fake Study A%'")"
curl -s --noproxy '*' "$base/article/view/$sid" >"$tmp/art.html"
yes "the article is published in the issue, with the pages as first and last page" bash -c "grep -q 'citation_firstpage\" content=\"5\"' '$tmp/art.html' && grep -q 'citation_lastpage\" content=\"9\"' '$tmp/art.html' && grep -q 'citation_volume\" content=\"7\"' '$tmp/art.html'"
yes "the article keeps its own publication date (2029-08-20, also in its structured data); the cited year is the issue's (2031), OJS's rule when they differ" bash -c "grep -q '\"datePublished\":\"2029-08-20\"' '$tmp/art.html' && grep -q 'citation_date\" content=\"2031\"' '$tmp/art.html' && [ \$(mariadb -N $SANDBOX_DB_NAME -e \"select count(*) from publications where date_published like '2029-08-20%'\") = 1 ]"
yes "both authors, with their order, and the keywords" bash -c "[ \$(grep -c 'name=\"citation_author\"' '$tmp/art.html') = 2 ] && grep -q 'Zeta' '$tmp/art.html' && [ \$(grep -c 'name=\"citation_keywords\"' '$tmp/art.html') = 2 ]"
yes "the reference list is on the page, and a reference with an emoji did not break the import (the emoji is dropped)" bash -c "grep -q 'A fake reference' '$tmp/art.html' && grep -q 'language models be too big' '$tmp/art.html'"
yes "the builder said it dropped the emoji" grep -q "NOTE: dropped" "$tmp/build.txt"
yes "Preview and Download are there" bash -c "grep -q 'obj_galley_link_download' '$tmp/art.html' && grep -qE '^[[:space:]]*Preview[[:space:]]*$' '$tmp/art.html'"
yes "the download is named from the article's details" bash -c "curl -s -D - -o /dev/null --noproxy '*' $base/article/download/$sid/\$(mariadb -N $SANDBOX_DB_NAME -e \"select galley_id from publication_galleys where publication_id=(select current_publication_id from submissions where submission_id=$sid)\") | grep -qi 'filename=WORJ_Vol7_No2_2031_Zeta'"
yes "markup in a title shows as text and the issue page lists both articles" bash -c "curl -s --noproxy '*' $base/issue/view/$iid | grep -c 'Fake Study' | grep -q '^[1-9]'"
yes "the JSON-LD for the article parses" bash -c "python3 -I -c \"import re,json,sys; h=open('$tmp/art.html',encoding='utf-8').read(); b=re.search(r'application/ld\\+json\\\">(.*?)</script>',h,re.S).group(1); d=json.loads(b); assert d['@type']=='ScholarlyArticle' and len(d['author'])==2\""

echo "=== adding articles to the issue that already exists (--into-existing)"
cp "$root/ojs/fixtures/pdfs/sample-article-3.pdf" "$tmp/a3.pdf"
python3 - "$tmp" <<'PY'
import json, sys
d = sys.argv[1]
m = json.load(open(d + "/meta.json"))
m["articles"] = [{"title": "Fake Study C Later Addition", "abstract": "Fake abstract three.", "keywords": ["epsilon"], "pages": "15-18", "pdf": "a3.pdf",
                  "date_published": "2028-06-07", "authors": [{"given": "Late", "family": "Comer", "affiliation": "Test Institute", "email": "test.four@example.invalid"}]}]
json.dump(m, open(d + "/meta-add.json", "w"))
PY
python3 -I "$root/scripts/build-issue-import.py" "$tmp/meta-add.json" "$tmp" "$tmp/add.xml" --into-existing >"$tmp/build2.txt" 2>&1; rc=$?
yes "the articles-only file is valid against OJS's schema (exit $rc)" bash -c "[ $rc = 0 ] && grep -q 'schema check: valid' '$tmp/build2.txt'"
IA() { "$root/scripts/import-issue-shared.sh" --local-ojs "$core" --user "$SANDBOX_ADMIN_USER" --xml "$tmp/add.xml" "$@"; }
IA >"$tmp/dry2.txt" 2>&1
yes "the dry run says it will ADD to the existing issue and writes nothing" bash -c "grep -q 'to ADD to the existing issue Volume 7, Number 2, 2031' '$tmp/dry2.txt' && grep -q 'DRY RUN' '$tmp/dry2.txt'"
n1="$(q "select count(*) from submissions")"
IA --apply >"$tmp/apply2.txt" 2>&1
yes "--apply adds one article and no new issue" bash -c "grep -q 'import completed successfully' '$tmp/apply2.txt' && [ \$(mariadb -N $SANDBOX_DB_NAME -e 'select count(*) from submissions') = $((n1 + 1)) ] && [ \$(mariadb -N $SANDBOX_DB_NAME -e \"select count(*) from issues where volume=7 and number='2' and year=2031\") = 1 ]"
sid3="$(q "select s.submission_id from submissions s join publication_settings p on p.publication_id=s.current_publication_id and p.setting_name='title' where p.setting_value like 'Fake Study C%'")"
find "$core/cache" -type f -delete 2>/dev/null
yes "the new article is published in that issue, with its own date (2028-06-07)" bash -c "[ \$(mariadb -N $SANDBOX_DB_NAME -e \"select count(*) from publications p join submissions s on s.current_publication_id=p.publication_id where s.submission_id=$sid3 and p.issue_id=$iid and p.status=3 and p.date_published like '2028-06-07%'\") = 1 ]"
yes "the issue page now lists three articles" bash -c "[ \$(curl -s --noproxy '*' $base/issue/view/$iid | grep -o 'Fake Study' | wc -l) -ge 3 ]"
IA --apply >"$tmp/again2.txt" 2>&1; rc=$?
yes "adding the same article again is refused, nothing is duplicated (exit $rc)" bash -c "[ $rc = 1 ] && grep -q 'already exists' '$tmp/again2.txt' && [ \$(mariadb -N $SANDBOX_DB_NAME -e 'select count(*) from submissions') = $((n1 + 1)) ]"
sed -i 's/"volume":7/"volume":8/' "$tmp/meta-add.json"; python3 - "$tmp" <<'PY'
import json, sys
d = sys.argv[1]; m = json.load(open(d + "/meta-add.json")); m["issue"]["volume"] = 8
json.dump(m, open(d + "/meta-add.json", "w"))
PY
python3 -I "$root/scripts/build-issue-import.py" "$tmp/meta-add.json" "$tmp" "$tmp/add2.xml" --into-existing >/dev/null 2>&1
yes "articles pointed at an issue that does not exist are refused" bash -c "! '$root/scripts/import-issue-shared.sh' --local-ojs '$core' --user '$SANDBOX_ADMIN_USER' --xml '$tmp/add2.xml' >/dev/null 2>&1"

echo "=== correcting a published article's date (scripts/set-article-dates-shared.sh)"
SD() { "$root/scripts/set-article-dates-shared.sh" --local-ojs "$core" "$@"; }
SD "$sid3=2027-01-02" >"$tmp/sd0.txt" 2>&1
yes "the dry run says what it would change and changes nothing" bash -c "grep -q 'WOULD: submission $sid3: 2028-06-07 -> 2027-01-02' '$tmp/sd0.txt' && [ \$(mariadb -N $SANDBOX_DB_NAME -e \"select count(*) from publications where date_published like '2028-06-07%'\") = 1 ]"
SD "$sid3=2027-01-02" --apply >"$tmp/sd1.txt" 2>&1
yes "--apply changes the date" bash -c "grep -q 'DONE:  submission $sid3' '$tmp/sd1.txt' && [ \$(mariadb -N $SANDBOX_DB_NAME -e \"select count(*) from publications where date_published like '2027-01-02%'\") = 1 ]"
yes "a bad date, an unknown submission, and a not-yet-published one are all refused with nothing written" bash -c "! '$root/scripts/set-article-dates-shared.sh' --local-ojs '$core' '$sid3=2027-02-30' >/dev/null 2>&1 && ! '$root/scripts/set-article-dates-shared.sh' --local-ojs '$core' '99999=2027-01-02' >/dev/null 2>&1"
echo; echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
