#!/usr/bin/env bash
# Check the Google Scholar citation_* tags on an article landing page (Task 6.1).
# Usage: scripts/check-citation-meta.sh [--placeholder-issn] <url|file>
#   --placeholder-issn  the journal has no real ISSN yet: a missing
#                       citation_issn is reported as EXPECTED-MISSING, not FAIL.
#                       Never use this flag at launch.
# Exit: 0 all required checks pass, 1 any FAIL, 2 usage or fetch error.
#
# Rules (spec 01-SPEC.md section 7, adjusted to what OJS 3.5.0-6's
# googleScholar plugin emits):
#  - required, non-empty: citation_title, citation_author, citation_journal_title,
#    citation_volume, citation_issue, citation_firstpage, citation_lastpage,
#    citation_pdf_url, citation_issn
#  - date: citation_publication_date or citation_date (OJS emits citation_date;
#    Google Scholar accepts either), format YYYY/MM/DD
#  - one citation_author per author (compared with DC.Creator.PersonalName)
#  - citation_pdf_url must return a PDF (checked for URL input only)
#  - citation_doi is optional (only when a DOI is assigned)
set -uo pipefail

placeholder_issn=0
if [ "${1:-}" = "--placeholder-issn" ]; then placeholder_issn=1; shift; fi
[ $# -eq 1 ] || { sed -n '2,8p' "$0" >&2; exit 2; }
src="$1"

tmp="$(mktemp)"
trap 'rm -f -- "${tmp:?}"' EXIT
is_url=0
case "$src" in
  http://* | https://*) is_url=1; curl -fsSL -m 30 -o "$tmp" "$src" || { echo "ERROR: cannot fetch $src" >&2; exit 2; } ;;
  *) [ -f "$src" ] || { echo "ERROR: no such file: $src" >&2; exit 2; }; cp "$src" "$tmp" ;;
esac

fails=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }

# All content values of a meta tag, one per line.
values() {
  grep -o "<meta name=\"$1\"[^>]*content=\"[^\"]*\"" "$tmp" | sed 's/.*content="//; s/"$//'
}
first() { values "$1" | head -n1; }
count() { values "$1" | grep -c . || true; }

require() {
  local v
  v="$(first "$1")"
  if [ -n "$v" ]; then pass "$1 = $v"; else fail "$1 missing or empty"; fi
}

for t in citation_title citation_journal_title citation_volume citation_issue \
  citation_firstpage citation_lastpage; do
  require "$t"
done

# authors: one tag per author, none empty
authors="$(count citation_author)"
creators="$(count DC.Creator.PersonalName)"
if [ "$authors" -lt 1 ]; then
  fail "citation_author missing"
elif values citation_author | grep -qx ''; then
  fail "citation_author has an empty value"
elif [ "$creators" -gt 0 ] && [ "$authors" -ne "$creators" ]; then
  fail "citation_author count ($authors) differs from author count ($creators)"
else
  pass "citation_author x$authors (one per author)"
fi

# date
date="$(first citation_publication_date)"
[ -n "$date" ] || date="$(first citation_date)"
if [ -z "$date" ]; then
  fail "citation_publication_date / citation_date missing"
elif echo "$date" | grep -Eq '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'; then
  pass "publication date = $date (YYYY/MM/DD)"
else
  fail "publication date '$date' is not YYYY/MM/DD"
fi

# ISSN
issn="$(first citation_issn)"
if [ -n "$issn" ]; then
  pass "citation_issn = $issn"
elif [ "$placeholder_issn" -eq 1 ]; then
  echo "EXPECTED-MISSING  citation_issn (journal ISSN is a placeholder; must be set before launch)"
else
  fail "citation_issn missing"
fi

# PDF
pdf="$(first citation_pdf_url)"
if [ -z "$pdf" ]; then
  fail "citation_pdf_url missing or empty"
elif [ "$is_url" -eq 0 ]; then
  pass "citation_pdf_url = $pdf"
  echo "SKIPPED  citation_pdf_url fetch (file input)"
else
  head="$(curl -fsSL -m 30 -r 0-4 "$pdf" 2>/dev/null | head -c 5)"
  if [ "$head" = "%PDF-" ]; then pass "citation_pdf_url returns a PDF ($pdf)"; else fail "citation_pdf_url does not return a PDF ($pdf)"; fi
fi

doi="$(first citation_doi)"
if [ -n "$doi" ]; then echo "INFO  citation_doi = $doi"; fi

if [ "$fails" -eq 0 ]; then echo "RESULT: PASS"; exit 0; fi
echo "RESULT: FAIL ($fails)"
exit 1
