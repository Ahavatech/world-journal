#!/usr/bin/env bash
# List every remaining placeholder (Task 3.5). Must print nothing at launch.
#
#   scripts/check-placeholders.sh                  scan the repository (git-tracked files under ojs/ and infra/)
#   scripts/check-placeholders.sh --url BASE       scan the RENDERED site instead (the launch gate that matters)
#                                                   BASE is the journal URL, for example http://127.0.0.1:8082/worj
#
# Patterns: [PLACEHOLDER, Sample Article, Placeholder Author, Placeholder Editor,
# example.org, example.invalid, lorem (case-insensitive). Prints file:line: text.
# Exit 1 if anything is found, so CI keeps it warn-only until Phase 8.
#
# Allowlist (scripts/placeholder-allowlist.txt): the theme templates contain
# fallback markers that render only while a journal setting is empty. Each entry is
# an EXACT file path and an EXACT fixed string, tab-separated; never a directory or
# a wildcard. An entry whose file is missing or that matches no line is STALE and
# fails the run. The allowlist is not used with --url: rendered pages must be empty.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"

if [ "${1:-}" = "--url" ]; then
  [ -n "${2:-}" ] || { echo "usage: $0 --url BASE" >&2; exit 2; }
  exec python3 -I "$here/check-placeholders-url.py" "$2"
fi
[ $# -eq 0 ] || { sed -n '2,16p' "$0" >&2; exit 2; }

cd "$root" || exit 2
allow="$here/placeholder-allowlist.txt"
pattern='\[PLACEHOLDER|Sample Article|Placeholder Author|Placeholder Editor|example\.org|example\.invalid|lorem'

# every allowlist entry must name an existing file
status=0
if [ -f "$allow" ]; then
  while IFS=$'\t' read -r file _; do
    case "$file" in '' | '#'*) continue ;; esac
    if [ ! -f "$file" ]; then echo "placeholder-allowlist.txt: stale entry, no such file: $file"; status=1; fi
    case "$file" in *'*'* | */) echo "placeholder-allowlist.txt: wildcards and directories are not allowed: $file"; status=1 ;; esac
  done < "$allow"
fi

# shellcheck disable=SC2046
findings=$(git ls-files ojs infra | xargs grep -n -I -i -E "$pattern" 2>/dev/null | awk -F'\t' -v allowfile="$allow" '
  BEGIN {
    while ((getline line < allowfile) > 0) {
      if (line == "" || substr(line, 1, 1) == "#") continue
      n = split(line, p, "\t"); if (n != 2) continue
      k++; afile[k] = p[1]; atext[k] = p[2]
    }
  }
  {
    split($0, h, ":"); f = h[1]; ln = h[2]
    text = substr($0, length(f) + length(ln) + 3)
    ok = 0
    for (i = 1; i <= k; i++) if (afile[i] == f && index(text, atext[i]) > 0) { ok = 1; used[i] = 1 }
    if (ok) allowed++; else print f ":" ln ": " text
  }
  END {
    for (i = 1; i <= k; i++) if (!used[i]) print "STALE ALLOWLIST ENTRY (matches nothing): " afile[i] "\t" atext[i]
    print "ALLOWED_COUNT=" allowed + 0 > "/dev/stderr"
  }' 2>"${TMPDIR:-/tmp}/worj-allowed.$$")
allowed=$(sed -n 's/^ALLOWED_COUNT=//p' "${TMPDIR:-/tmp}/worj-allowed.$$")
rm -f -- "${TMPDIR:-/tmp}/worj-allowed.$$"

if [ -n "$findings" ]; then echo "$findings"; status=1; fi
total=$(printf '%s' "$findings" | grep -c . || true)
files=$(printf '%s\n' "$findings" | grep -v '^STALE' | cut -d: -f1 | sort -u | grep -c . || true)
echo "check-placeholders (repository): $total line(s) in $files file(s); $allowed theme fallback line(s) excused by the exact-entry allowlist"
[ "$status" -eq 0 ] && echo "empty: nothing left to replace in the repository"
exit "$status"
