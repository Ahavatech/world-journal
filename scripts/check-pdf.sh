#!/usr/bin/env bash
# Check that an article's PDF is readable by a crawler (Task 6.2).
# Usage: scripts/check-pdf.sh <article-page-url>            take citation_pdf_url, title and authors from the page
#        scripts/check-pdf.sh --pdf <url|file> --title T [--author A]...   check one PDF against given values
# Exit: 0 all FAIL-level checks pass, 1 any FAIL, 2 usage or fetch error.
#
# FAIL: no citation_pdf_url; the URL the tag gives (NOT the galley viewer page) redirects to a login page, answers
#       401/403/404 or another content type, when requested WITHOUT cookies; the file is not a PDF; no extractable
#       text (pdftotext); 5 MB or more; the title or an author is missing from page 1.
# INFO: a Set-Cookie header on the download (OJS may set a session cookie; Google needs access, not a cookie-free
#       response); the PDF URL is the same as the HTML viewer page (it never is at 3.5.0-6; reported if it happens).
# Title and author matching is in scripts/lib/pdf_match.py (case, whitespace, ligatures, line-end hyphens).
# The server-side denial of private submission files is covered by scripts/test-nginx-harness.sh; here the public
# URL is only checked to be a different kind of path (not /api/, /submission/ or a files directory).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
max_bytes=$((5 * 1024 * 1024))

mode=page; src=""; title=""; authors=()
while [ $# -gt 0 ]; do
  case "$1" in
    --pdf) mode=pdf; src="${2:-}"; shift 2 || true ;;
    --title) title="${2:-}"; shift 2 || true ;;
    --author) authors+=("${2:-}"); shift 2 || true ;;
    -*) echo "ERROR: unknown option $1" >&2; sed -n '2,5p' "$0" >&2; exit 2 ;;
    *) src="$1"; shift ;;
  esac
done
[ -n "$src" ] || { sed -n '2,5p' "$0" >&2; exit 2; }
command -v pdftotext >/dev/null || { echo "ERROR: pdftotext not installed (apt-get install poppler-utils)" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp:?}"' EXIT
fails=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }
info() { echo "INFO  $1"; }
is_url() { case "$1" in http://* | https://*) return 0 ;; *) return 1 ;; esac; }

pdf_ref="$src"
if [ "$mode" = page ]; then
  is_url "$src" || { echo "ERROR: page mode needs an http(s) URL" >&2; exit 2; }
  curl -fsSL -m 30 -o "$tmp/page.html" "$src" || { echo "ERROR: cannot fetch $src" >&2; exit 2; }
  meta() { grep -o "<meta name=\"$1\"[^>]*content=\"[^\"]*\"" "$tmp/page.html" | sed 's/.*content="//; s/"$//'; }
  unesc() { python3 -I -c 'import html,sys; print(html.unescape(sys.stdin.read().rstrip("\n")))'; }
  pdf_ref="$(meta citation_pdf_url | head -n1)"
  title="$(meta citation_title | head -n1 | unesc)"
  while IFS= read -r a; do [ -z "$a" ] || authors+=("$a"); done < <(meta citation_author | unesc)
  if [ -z "$pdf_ref" ]; then fail "citation_pdf_url missing or empty on the page"; echo "RESULT: FAIL ($fails)"; exit 1; fi
  pass "citation_pdf_url = $pdf_ref"
  [ "$pdf_ref" != "$src" ] || info "citation_pdf_url is the article page itself"
fi

# --- get the PDF the way a crawler does: no cookies sent, redirects followed
pdf="$tmp/file.pdf"
if is_url "$pdf_ref"; then
  out="$(curl -sS -m 60 -L --max-redirs 5 -D "$tmp/headers" -o "$pdf" -w '%{http_code} %{content_type} %{url_effective}' "$pdf_ref")" \
    || { echo "ERROR: cannot fetch $pdf_ref" >&2; exit 2; }
  code="${out%% *}"; rest="${out#* }"; ctype="${rest%% *}"; final="${rest#* }"
  if [ "$final" != "$pdf_ref" ] && grep -qiE '/login([/?]|$)|/user/(register|lostPassword)' <<<"$final"; then
    fail "the PDF URL redirects to a login page ($final)"
  elif [ "$code" = 401 ] || [ "$code" = 403 ] || [ "$code" -ge 400 ] 2>/dev/null; then
    fail "the PDF URL answers HTTP $code without cookies ($pdf_ref)"
  elif ! grep -qi '^application/pdf' <<<"$ctype"; then
    fail "the PDF URL answers content type '$ctype', not application/pdf ($pdf_ref)"
  else
    pass "no-cookie request returns HTTP $code application/pdf"
  fi
  if grep -qi '^set-cookie:' "$tmp/headers"; then info "the download sets a cookie (allowed: access does not depend on it)"; fi
  path="$(python3 -I -c 'import sys,urllib.parse; print(urllib.parse.urlsplit(sys.argv[1]).path)' "$pdf_ref")"
  # shellcheck disable=SC2016  # the pattern is literal, not a shell expansion
  if grep -qiE '/api/|/submission/|/files/|/\$\$\$call\$\$\$' <<<"$path"; then fail "the PDF URL path looks like a private or API route ($path)"; else pass "the PDF URL is a public route ($path)"; fi
else
  [ -f "$pdf_ref" ] || { echo "ERROR: no such file: $pdf_ref" >&2; exit 2; }
  cp "$pdf_ref" "$pdf"
fi

if [ "$(head -c 5 "$pdf")" != "%PDF-" ]; then
  fail "the file is not a PDF"
else
  pass "file starts with %PDF-"
  size="$(stat -c %s "$pdf")"
  if [ "$size" -lt "$max_bytes" ]; then pass "size $size bytes (under 5 MB)"; else fail "size $size bytes is 5 MB or more"; fi
  if pdftotext -l 1 "$pdf" "$tmp/p1.txt" 2>/dev/null && [ "$(tr -d '[:space:]' <"$tmp/p1.txt" | wc -c)" -gt 20 ]; then
    pass "page 1 has selectable text"
    if [ -n "$title" ]; then
      if python3 -I "$here/lib/pdf_match.py" "$tmp/p1.txt" "$title" >/dev/null; then pass "title on page 1"; else fail "title not found on page 1: $title"; fi
    else echo "SKIPPED  title (none given)"; fi
    for a in "${authors[@]+"${authors[@]}"}"; do
      if python3 -I "$here/lib/pdf_match.py" "$tmp/p1.txt" "$a" >/dev/null; then pass "author on page 1: $a"; else fail "author not found on page 1: $a"; fi
    done
  else
    fail "no extractable text on page 1 (scanned or image-only PDF?)"
  fi
fi

if [ "$fails" -eq 0 ]; then echo "RESULT: PASS"; exit 0; fi
echo "RESULT: FAIL ($fails)"
exit 1
