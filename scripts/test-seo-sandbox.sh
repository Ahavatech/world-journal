#!/usr/bin/env bash
# The theme's search engine metadata (canonical, description, Open Graph, JSON-LD, keywords) against the SANDBOX journal, over HTTP.
#   scripts/test-seo-sandbox.sh      needs the sandbox up (make sandbox-up sandbox-seed). The database is snapshotted and restored.
# shellcheck disable=SC2317
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/.env.sandbox"
core="$root/ojs-core"; base="${SANDBOX_URL:-http://127.0.0.1:8082}/worj"
curl -s -o /dev/null -m 5 --noproxy '*' "$base/" || { echo "sandbox not running (make sandbox-up sandbox-seed)"; exit 2; }
tmp="$(mktemp -d)"
mariadb-dump "$SANDBOX_DB_NAME" >"$tmp/db.sql" 2>/dev/null || mysqldump "$SANDBOX_DB_NAME" >"$tmp/db.sql"
restore() { mariadb -e "DROP DATABASE IF EXISTS \`$SANDBOX_DB_NAME\`; CREATE DATABASE \`$SANDBOX_DB_NAME\` CHARACTER SET utf8mb4" && mariadb "$SANDBOX_DB_NAME" <"$tmp/db.sql"; find "$core/cache" -type f -delete 2>/dev/null; rm -rf -- "${tmp:?}"; }
trap restore EXIT
fail=0; pass=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
q() { mariadb -N "$SANDBOX_DB_NAME" -e "$1"; }
get() { find "$core/cache" -type f -delete 2>/dev/null; curl -s --noproxy '*' "$base/$1" >"$tmp/page.html"; }
# python helper: print one thing about the page in $tmp/page.html
py() { python3 -I - "$tmp/page.html" "$@" <<'PY'
import json, re, sys
h = open(sys.argv[1], encoding="utf-8").read()
what = sys.argv[2]
head = h.split("</head>")[0]
if what == "ld":
    blocks = re.findall(r'<script type="application/ld\+json">(.*?)</script>', head, re.S)
    out = [json.loads(b) for b in blocks]          # raises (and the check fails) when the JSON is broken
    print(json.dumps(out))
elif what == "count":
    print(len(re.findall(sys.argv[3], head)))
PY
}
count() { py count "$1"; }

echo "=== article page"
get article/view/1
yes "one canonical link, the article's own address" test "$(count '<link rel="canonical" href="[^"]*/worj/article/view/1"/>')" = 1
yes "a description made from the abstract" test "$(count '<meta name="description" content="[^"]*sample abstract 1')" = 1
yes "the article's own keywords are meta keywords" test "$(count '<meta name="keywords" content="sample, placeholder"/>')" = 1
yes "Open Graph type article, title and image" test "$(count 'og:type" content="article"')$(count 'og:title" content="Sample Article 1"')$(count 'og:image" content="[^"]*logo-lockup')" = 111
yes "a Twitter card" test "$(count 'twitter:card')" = 1
yes "one tag per keyword for article:tag" test "$(count 'article:tag')" = 2
yes "Google Scholar's citation_keywords are still there (OJS's own plugin)" test "$(count 'name="citation_keywords"')" = 2
yes "the JSON-LD is valid JSON and a ScholarlyArticle with the headline, author, keywords and open access" bash -c "$(declare -f py); tmp='$tmp'; py ld | python3 -I -c \"import json,sys; d=json.load(sys.stdin)[0]; assert d['@type']=='ScholarlyArticle' and d['headline']=='Sample Article 1' and d['author'][0]['name'] and d['keywords']=='sample, placeholder' and d['isAccessibleForFree'] is True and d['isPartOf']['@type']=='PublicationIssue'\""
yes "no ISSN or DOI is printed when the journal has none" bash -c "! grep -q '\"issn\"\|\"DOI\"' '$tmp/page.html'"
yes "each keyword on the page is a link to a search for it" bash -c "[ \$(grep -o 'class=\"worj-keyword\" href=\"[^\"]*search/search?query=' '$tmp/page.html' | wc -l) = 2 ]"

echo "=== a keyword with spaces: the link is encoded once and the search box shows plain words"
q "update controlled_vocab_entry_settings set setting_value='Digital financial technology' where controlled_vocab_entry_id=3 and setting_name='name'"
get article/view/1
kwurl="$(grep -o 'class="worj-keyword" href="[^"]*Digital[^"]*"' "$tmp/page.html" | sed 's/.*href="//; s/"$//; s/&amp;/\&/g')"
yes "the link has the spaces encoded once (%20), not twice (%2520)" bash -c "[[ '$kwurl' == *'query=Digital%20financial%20technology' ]] && [[ '$kwurl' != *'%25'* ]]"
yes "the search page opened from it shows the words with plain spaces in the search box" bash -c "curl -s --noproxy '*' '$kwurl' | grep -q 'name=\"query\" value=\"Digital financial technology\"'"

echo "=== an ISSN, once there is one"
q "insert into journal_settings (journal_id, locale, setting_name, setting_value) values (1, '', 'onlineIssn', '1234-5678') on duplicate key update setting_value='1234-5678'"
get article/view/1
yes "the real ISSN appears in the article's JSON-LD" grep -q '"issn":"1234-5678"' "$tmp/page.html"
q "update journal_settings set setting_value='[PLACEHOLDER: ISSN]' where journal_id=1 and setting_name='onlineIssn'"
get article/view/1
yes "a placeholder ISSN is never printed" bash -c "! grep -q '\"issn\"' '$tmp/page.html'"

echo "=== a hostile title cannot break out of the script tag"
q "update publication_settings set setting_value='Evil </script><script>alert(1)</script> & \"q\" title' where publication_id=1 and setting_name='title' and locale='en'"
get article/view/1
yes "the head still has exactly one JSON-LD block, and it parses" bash -c "$(declare -f py); tmp='$tmp'; [ \"\$(py ld | python3 -I -c 'import json,sys; print(len(json.load(sys.stdin)))')\" = 1 ]"
yes "no raw '</script><script>' reaches the page head" bash -c "! sed '/<\/head>/q' '$tmp/page.html' | grep -q '</script><script>alert'"
yes "the headline round-trips as text" bash -c "$(declare -f py); tmp='$tmp'; py ld | python3 -I -c \"import json,sys; assert 'alert(1)' in json.load(sys.stdin)[0]['headline']\""

echo "=== issue, home and other pages"
get issue/view/1
yes "the issue page: canonical, description and a PublicationIssue" bash -c "$(declare -f py); tmp='$tmp'; [ \"\$(py count '<link rel=\"canonical\" href=\"[^\"]*/issue/view/1\"/>')\" = 1 ] && py ld | python3 -I -c \"import json,sys; assert json.load(sys.stdin)[0]['@type']=='PublicationIssue'\""
get ""
yes "the home page: a Periodical and a WebSite with a search action" bash -c "$(declare -f py); tmp='$tmp'; py ld | python3 -I -c \"import json,sys; g=json.load(sys.stdin)[0]['@graph']; t=[x['@type'] for x in g]; assert 'Periodical' in t and 'WebSite' in t; w=[x for x in g if x['@type']=='WebSite'][0]; assert 'search_term_string' in w['potentialAction']['target']\""
get about
yes "an ordinary page has a canonical but no shared description (no duplicates)" bash -c "$(declare -f py); tmp='$tmp'; [ \"\$(py count '<link rel=\"canonical\"')\" = 1 ] && [ \"\$(py count 'name=\"description\"')\" = 0 ]"
get "search/search?query=sample&x=1"
yes "a search page's canonical drops the query string" bash -c "grep -q 'rel=\"canonical\" href=\"[^\"?]*\"' '$tmp/page.html'"

echo "=== crawl files"
yes "the sitemap lists the article" bash -c "curl -s --noproxy '*' $base/sitemap | grep -q '/worj/article/view/1<'"
yes "the production robots file names the sitemap" grep -q '^Sitemap: https://@@HOST@@/index/sitemap' "$root/infra/robots/robots-production.txt.template"
echo; echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
