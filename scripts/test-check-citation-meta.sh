#!/usr/bin/env bash
# Tests for the citation_doi rule of scripts/check-citation-meta.sh (file input, no network):
# absent passes, a bare DOI passes, present-but-empty FAILS, a non-bare value is a WARN (still passes).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp:?}"' EXIT
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
base='<html><head>
<meta name="citation_title" content="A Real Title"/>
<meta name="citation_author" content="A. Author"/>
<meta name="DC.Creator.PersonalName" content="A. Author"/>
<meta name="citation_journal_title" content="World Open Research Journal"/>
<meta name="citation_volume" content="1"/><meta name="citation_issue" content="1"/>
<meta name="citation_firstpage" content="1"/><meta name="citation_lastpage" content="9"/>
<meta name="citation_date" content="2026/01/02"/>
<meta name="citation_issn" content="1234-5678"/>
<meta name="citation_pdf_url" content="https://x.invalid/a.pdf"/>'
case_() { # label want_exit want_text extra-head
  printf '%s\n%s\n</head></html>\n' "$base" "$4" >"$tmp/a.html"
  local out rc; out="$("$root/scripts/check-citation-meta.sh" "$tmp/a.html" 2>&1)"; rc=$?
  if [ "$rc" = "$2" ] && { [ -z "$3" ] || grep -qF -- "$3" <<<"$out"; }; then ok "$1"; else bad "$1 (exit $rc, wanted $2${3:+, text \"$3\"})"; printf '      %s\n' "${out//$'\n'/$'\n      '}"; fi
}
case_ "no citation_doi tag: passes (a DOI is optional)" 0 "RESULT: PASS" ''
case_ "a bare DOI passes with an INFO line" 0 "INFO  citation_doi = 10.12345/worj.2026.1" '<meta name="citation_doi" content="10.12345/worj.2026.1"/>'
case_ "citation_doi present with an empty value FAILS" 1 "citation_doi tag is present with an empty value" '<meta name="citation_doi" content=""/>'
case_ "a DOI given as a URL is a WARN, not a failure" 0 "WARN  citation_doi" '<meta name="citation_doi" content="https://doi.org/10.12345/abc"/>'
case_ "a malformed DOI is a WARN, not a failure" 0 "WARN  citation_doi" '<meta name="citation_doi" content="doi-pending"/>'
echo
if [ "$fail" -eq 0 ]; then echo "check-citation-meta tests: all passed"; else echo "check-citation-meta tests: $fail FAILED"; exit 1; fi
