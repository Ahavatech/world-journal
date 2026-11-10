#!/usr/bin/env bash
# `make eval`: the QA scorer (autoresearch/EVAL-SPEC.md). Read-only: it never
# changes the theme or the sandbox. Needs the sandbox running and seeded:
#   make sandbox-up sandbox-seed        (default sidebar state: blocks)
# Last three lines of stdout: COMPONENT ..., GATES: PASS|FAIL ..., SCORE: <0..100>
# Exit 0 only when every hard gate passes.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
base="${SANDBOX_URL:-http://127.0.0.1:8082}"
cd "$here" || exit 2

if ! curl -fsS -m 10 -o /dev/null "$base/worj/"; then
  echo "GATES: FAIL sandbox not reachable at $base (run: make sandbox-up sandbox-seed)"
  echo "SCORE: 0.0"
  exit 1
fi
if [ ! -d node_modules/@axe-core ]; then
  echo "GATES: FAIL eval dependencies missing (run: cd autoresearch/eval && npm ci)"
  echo "SCORE: 0.0"
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp:?}"' EXIT
start=$(date +%s)

# Lighthouse (accessibility, SEO, best-practices) runs alongside the gates.
node checks/lighthouse.js --out "$tmp/lh.json" >"$tmp/lh.log" 2>&1 &
lh_pid=$!

echo "== gate 1: citation tags on the sample articles"
articles=$(python3 -I -c "import json;print(sum(1 for r in json.load(open('$root/ojs/fixtures/manifest.json'))['records'] if r['type']=='article'))")
failing=()
for n in $(seq 1 "$articles"); do
  # --placeholder-issn: the journal has no real ISSN yet. Phase 8.3 removes this flag.
  if out=$("$root/scripts/check-citation-meta.sh" --placeholder-issn "$base/worj/article/view/$n" 2>&1); then
    echo "PASS  article $n"
  else
    echo "FAIL  article $n"; echo "$out" | grep '^FAIL' | sed 's/^/      /'
    failing+=("article $n")
  fi
done
python3 -I - "$tmp/citation.json" "$articles" "${#failing[@]}" "${failing[*]:-}" <<'PY'
import json, sys
out, total, bad = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
json.dump({"ok": bad == 0, "completeness": (total - bad) / total if total else 0, "failing": sys.argv[4].split(", ") if bad else []}, open(out, "w"))
PY

echo "== gate 4: axe (WCAG 2.0/2.1/2.2 A and AA) on every page at 320 and 1280 px"
node checks/axe.js --wcag-only --out "$tmp/axe.json" | grep -E '^axe |^WCAG violations|^core-owned'

echo "== gates 2, 3, 5, 6, 7 and responsiveness"
node checks/gates.js --out "$tmp/gates.json"
gates_rc=$?
if [ ! -s "$tmp/gates.json" ]; then
  echo "GATES: FAIL gate runner crashed (exit $gates_rc)"; echo "SCORE: 0.0"; exit 1
fi

wait "$lh_pid"
echo "== lighthouse (accessibility, SEO, best-practices; one run per page)"
cat "$tmp/lh.log"
[ -s "$tmp/lh.json" ] || echo '{"skipped": true, "reason": "lighthouse produced no result"}' > "$tmp/lh.json"

echo "(eval took $(( $(date +%s) - start )) s)"
node checks/score.js "$tmp"
