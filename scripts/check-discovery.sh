#!/usr/bin/env bash
# Can search engines and harvesters find and read the journal? (Tasks 6.3 and 6.5)
# Usage: scripts/check-discovery.sh --robots-mode production|staging [--launch] [--curl-arg ARG]... BASE_URL
#   BASE_URL     the site root, for example https://journal.example.org (no journal path: it is found from /index/sitemap)
#   --robots-mode  REQUIRED, no default. production: the site must be crawlable (FAIL if the whole site is disallowed or
#                  noindex is sent). staging: the site must be closed (FAIL if it is crawlable).
#                A missing Sitemap line in robots.txt is ALWAYS a FAIL in production mode and with --launch (there is no way to turn it into a warning).
#   --launch     also FAIL if the sitemap or OAI-PMH ListRecords carry a placeholder marker (the same pattern as
#                scripts/check-placeholders-url.py: "Sample Article", "Placeholder Author", ...) or if the OAI repository
#                identifier is not the site's own host. Fake records in OAI get harvested by third parties and cannot be recalled.
#   --curl-arg   extra curl argument (repeatable), for example -k or --resolve host:port:127.0.0.1
# Exit: 0 no FAIL, 1 any FAIL, 2 usage or fetch error. Every FAIL is counted; the exit status never hides one.
# INFO and WARN never fail: they are client decisions (the OAI adminEmail, the missing canonical tag).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mode=""; launch=0; curl_args=(); base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --robots-mode) mode="${2:-}"; shift 2 || true ;;
    --launch) launch=1; shift ;;
    --curl-arg) curl_args+=("${2:-}"); shift 2 || true ;;
    -*) echo "ERROR: unknown option $1" >&2; sed -n '2,5p' "$0" >&2; exit 2 ;;
    *) base="${1%/}"; shift ;;
  esac
done
case "$mode" in production | staging) ;; *) echo "ERROR: --robots-mode production|staging is required (no default)" >&2; exit 2 ;; esac
if [ "$launch" = 1 ] && [ "$mode" != production ]; then echo "ERROR: --launch is the production gate: use it with --robots-mode production" >&2; exit 2; fi
case "$base" in http://* | https://*) ;; *) echo "ERROR: BASE_URL must be an http(s) URL" >&2; exit 2 ;; esac
tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp:?}"' EXIT
fails=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }
info() { echo "INFO  $1"; }
warn() { echo "WARN  $1"; }
check() { local ok="$1" bad="$2"; shift 2; if "$@"; then pass "$ok"; else fail "$bad"; fi; } # check OK-TEXT FAIL-TEXT command...
py() { python3 -I "$here/lib/discovery.py" "$@"; }
# fetch URL OUTFILE [HEADERFILE]: no cookies, no redirects followed (a redirect is itself a finding). Prints the HTTP status.
fetch() { curl -sS -m 60 "${curl_args[@]+"${curl_args[@]}"}" -o "$2" -D "${3:-$tmp/h.last}" -w '%{http_code}' "$1" 2>/dev/null || echo 000; }
hostof() { python3 -I -c 'import sys,urllib.parse as u; print(u.urlsplit(sys.argv[1]).netloc)' "$1"; }
basehost="$(hostof "$base")"

# ---------------------------------------------------------------- sitemap index and journal sitemap
code="$(fetch "$base/index/sitemap" "$tmp/index.xml")"
if [ "$code" != 200 ]; then echo "ERROR: $base/index/sitemap answers HTTP $code" >&2; exit 2; fi
if ! py sitemap "$tmp/index.xml" >"$tmp/index.txt"; then fail "/index/sitemap is not a valid sitemap: $(head -n1 "$tmp/index.txt")"; echo "RESULT: FAIL ($fails)"; exit 1; fi
if command -v xmllint >/dev/null && ! xmllint --noout "$tmp/index.xml" 2>/dev/null; then fail "/index/sitemap is not well-formed XML"; else pass "/index/sitemap is a sitemap index"; fi
jsitemap="$(sed -n 's/^sitemapindex //p' "$tmp/index.txt" | sed -n 1p)"
[ -n "$jsitemap" ] || { fail "the sitemap index lists no journal sitemap"; echo "RESULT: FAIL ($fails)"; exit 1; }
code="$(fetch "$jsitemap" "$tmp/sitemap.xml")"
if [ "$code" != 200 ]; then fail "the journal sitemap $jsitemap answers HTTP $code (a redirect or error)"; echo "RESULT: FAIL ($fails)"; exit 1; fi
py sitemap "$tmp/sitemap.xml" >"$tmp/sitemap.txt" || { fail "the journal sitemap is not valid: $(head -n1 "$tmp/sitemap.txt")"; echo "RESULT: FAIL ($fails)"; exit 1; }
if command -v xmllint >/dev/null && ! xmllint --noout "$tmp/sitemap.xml" 2>/dev/null; then fail "the journal sitemap is not well-formed XML"; else pass "journal sitemap is valid XML ($jsitemap)"; fi
journal_base="${jsitemap%/sitemap}"
echo "      sitemap contents by kind: $(cut -d' ' -f1 "$tmp/sitemap.txt" | sort | uniq -c | sort -rn | awk '{printf "%s %s; ", $2, $1}')"
sed 's/^/        /' "$tmp/sitemap.txt"
for k in issue article; do
  if grep -q "^$k " "$tmp/sitemap.txt"; then pass "the sitemap lists $k pages ($(grep -c "^$k " "$tmp/sitemap.txt"))"; else fail "the sitemap lists no $k pages"; fi
done
wrong="$(awk '{print $2}' "$tmp/sitemap.txt" | while read -r u; do [ "$(hostof "$u")" = "$basehost" ] || echo "$u"; done | sed -n 1p)"
if [ -n "$wrong" ]; then fail "the sitemap names another host than $basehost (base_url wrong?): $wrong"; else pass "every sitemap URL uses the site's own host ($basehost)"; fi

# ---------------------------------------------------------------- pages a crawler must reach
article="$(sed -n 's/^article //p' "$tmp/sitemap.txt" | sed -n 1p)"
issue="$(sed -n 's/^issue //p' "$tmp/sitemap.txt" | sed -n 1p)"
asset=""; pdf=""
if [ -n "$article" ]; then
  code="$(fetch "$article" "$tmp/article.html")"
  check "article page answers 200 ($article)" "article page answers HTTP $code ($article)" test "$code" = 200
  pdf="$(grep -o '<meta name="citation_pdf_url"[^>]*content="[^"]*"' "$tmp/article.html" | sed 's/.*content="//; s/"$//' | sed -n 1p || true)"
fi
code="$(fetch "$journal_base/" "$tmp/home.html" "$tmp/home.headers")"
asset="$(grep -o '/plugins/themes/[^"'\'' ]*\.\(css\|js\)' "$tmp/home.html" | sed -n 1p || true)"
[ -z "$asset" ] || asset="$base$asset"
oai="$journal_base/oai"

# ---------------------------------------------------------------- robots.txt and noindex
code="$(fetch "$base/robots.txt" "$tmp/robots.txt" "$tmp/robots.headers")"
if [ "$code" != 200 ]; then fail "robots.txt answers HTTP $code"; else pass "robots.txt answers 200"; fi
noindex_header=0
if grep -qiE '^x-robots-tag:.*noindex' "$tmp/robots.headers" "$tmp/home.headers" 2>/dev/null; then noindex_header=1; fi
noindex_meta=0
if [ -f "$tmp/article.html" ] && grep -qiE '<meta[^>]+name="robots"[^>]+noindex' "$tmp/article.html"; then noindex_meta=1; fi
if [ "$mode" = production ]; then
  if py robots-closed "$tmp/robots.txt"; then fail "production: robots.txt disallows the whole site"; else pass "production: robots.txt does not close the site"; fi
  check "production: no X-Robots-Tag noindex" "production: X-Robots-Tag noindex is sent (a staging setting left on?)" test "$noindex_header" = 0
  check "production: no noindex meta tag on the article page" "production: the article page carries a noindex meta tag" test "$noindex_meta" = 0
  targets=("$journal_base/" "$base/index/sitemap" "$jsitemap" "$oai")
  [ -z "$article" ] || targets+=("$article"); [ -z "$issue" ] || targets+=("$issue")
  [ -z "$pdf" ] || targets+=("$pdf"); [ -z "$asset" ] || targets+=("$asset")
  for agent in '*' Googlebot; do
    if py robots-can "$tmp/robots.txt" "$agent" "${targets[@]}" >"$tmp/can.txt"; then
      pass "robots.txt lets $agent fetch: home, sitemaps, OAI, article, galley download, issue, theme CSS/JS ($(wc -l <"$tmp/can.txt") URLs)"
    else
      fail "robots.txt blocks $agent from: $(sed -n 's/^BLOCKED //p' "$tmp/can.txt" | tr '\n' ' ')"
    fi
  done
  if [ -n "$(py robots-sitemaps "$tmp/robots.txt")" ]; then pass "robots.txt names the sitemap ($(py robots-sitemaps "$tmp/robots.txt" | sed -n 1p))"; else fail "robots.txt has no Sitemap: line"; fi
else
  if py robots-closed "$tmp/robots.txt"; then pass "staging: robots.txt closes the site to * and Googlebot"; else fail "staging: robots.txt leaves the site crawlable"; fi
  check "staging: X-Robots-Tag noindex is sent" "staging: no X-Robots-Tag noindex header (the site is crawlable)" test "$noindex_header" = 1
fi

# ---------------------------------------------------------------- OAI-PMH
oai_get() { # verb-and-args -> sets code; output parsed into $tmp/oai.kv
  code="$(fetch "$oai?$1" "$tmp/oai.xml")"
  [ "$code" = 200 ] || { fail "OAI $1 answers HTTP $code"; return 1; }
  py oai "$tmp/oai.xml" >"$tmp/oai.kv" || { fail "OAI $1 is not well-formed XML"; return 1; }
  [ "$(sed -n 's/^root=//p' "$tmp/oai.kv")" = "OAI-PMH" ] || { fail "OAI $1: root element is not OAI-PMH"; return 1; }
  if [ -n "$(sed -n 's/^error=//p' "$tmp/oai.kv")" ]; then fail "OAI $1 returned an error: $(sed -n 's/^error=//p' "$tmp/oai.kv")"; return 1; fi
  return 0
}
kv() { sed -n "s/^$1=//p" "$tmp/oai.kv" | sed -n 1p; }
if oai_get "verb=Identify"; then
  pass "OAI Identify is valid"
  admin="$(kv adminEmail)"; echo "      OAI adminEmail (PUBLIC): ${admin:-<empty>}   repositoryName: $(kv repositoryName)   baseURL: $(kv baseURL)"
  case "$admin" in
    "" ) warn "OAI Identify exposes an EMPTY adminEmail (journal contact email unset)" ;;
    *@gmail.* | *@yahoo.* | *@hotmail.* | *@outlook.* | *@proton* | *@icloud.* | *@example.* | *@localhost* | *.invalid | *.local) warn "OAI adminEmail '$admin' looks personal or placeholder: it is public; use a role address the client controls (decision table)" ;;
    *) info "OAI adminEmail '$admin' is public: confirm it is a role address, not a person's (decision table)" ;;
  esac
  check "OAI baseURL uses the site's own host" "OAI baseURL host ($(kv baseURL)) differs from $basehost" test "$(hostof "$(kv baseURL)")" = "$basehost"
fi
if oai_get "verb=ListMetadataFormats"; then
  check "OAI ListMetadataFormats includes oai_dc" "OAI ListMetadataFormats lacks oai_dc" grep -q oai_dc <<<"$(kv formats)"
fi
rid=""
if oai_get "verb=ListIdentifiers&metadataPrefix=oai_dc"; then
  first="$(kv identifiers | cut -d, -f1)"
  if [ -n "$first" ]; then pass "OAI ListIdentifiers returns identifiers (first: $first)"; else fail "OAI ListIdentifiers returned no identifier"; fi
  rid="$(cut -d: -f2 <<<"$first")"
  if [ -n "$first" ] && oai_get "verb=GetRecord&metadataPrefix=oai_dc&identifier=$first"; then
    if [ "$(kv records)" -ge 1 ]; then pass "OAI GetRecord returns the record (identifier taken from ListIdentifiers)"; else fail "OAI GetRecord returned no record"; fi
  fi
fi
if [ -n "$rid" ]; then
  if [ "$rid" = "${basehost%%:*}" ]; then pass "OAI repository identifier is the site's host ($rid)"
  elif [ "$launch" = 1 ]; then fail "OAI repository identifier '$rid' is not the site's host '${basehost%%:*}' (identifiers must never change after harvesting; set [oai] repository_id before launch)"
  else info "OAI repository identifier is '$rid' (launch needs the production host '${basehost%%:*}')"; fi
fi
: >"$tmp/records.xml"
if oai_get "verb=ListRecords&metadataPrefix=oai_dc"; then
  cat "$tmp/oai.xml" >>"$tmp/records.xml"
  if [ "$(kv records)" -ge 1 ]; then pass "OAI ListRecords returns records ($(kv records) on the first page)"; else fail "OAI ListRecords returned no record"; fi
  tok="$(kv token)"; pages=1
  while [ -n "$tok" ] && [ "$pages" -lt 50 ]; do
    oai_get "verb=ListRecords&resumptionToken=$(python3 -I -c 'import sys,urllib.parse as u; print(u.quote(sys.argv[1]))' "$tok")" || break
    cat "$tmp/oai.xml" >>"$tmp/records.xml"; tok="$(kv token)"; pages=$((pages + 1))
  done
fi

# ---------------------------------------------------------------- launch gate: sample content must not be harvestable
if [ "$launch" = 1 ]; then
  if py markers "$tmp/sitemap.xml" "$tmp/records.xml" >"$tmp/markers.txt"; then pass "launch: no placeholder marker in the sitemap or OAI ListRecords"; else fail "launch: placeholder content is discoverable: $(tr '\n' ' ' <"$tmp/markers.txt")"; fi
fi

# ---------------------------------------------------------------- canonical (6.5): INFO only, never a failure
if [ -f "$tmp/article.html" ]; then
  canon="$(grep -io '<link[^>]*rel="canonical"[^>]*' "$tmp/article.html" | sed -n 1p || true)"
  if [ -z "$canon" ]; then
    info "no canonical tag on article pages at 3.5.0-6, decision pending"
  else
    info "canonical tag present: $(sed -n 's/.*href="\([^"]*\)".*/\1/p' <<<"$canon")"
  fi
  case "$basehost" in 127.0.0.1* | localhost*) info "canonical: a localhost base_url is a weak test (OJS builds URLs from base_url); recheck on staging with the real domain and HTTPS" ;; esac
fi

if [ "$fails" -eq 0 ]; then echo "RESULT: PASS"; exit 0; fi
echo "RESULT: FAIL ($fails)"
exit 1
