#!/usr/bin/env bash
# Switch on small journal features on the shared host: How to cite (format dropdown), references at submission, a Co-author role, Awards in the menu, the Downloads block on the Author Guidelines.
#
#   scripts/features-shared.sh [--only citations,coauthor,awards-menu,downloads] [--apply] [--env FILE] [--local-ojs DIR  (tests)]
#
# Dry run unless --apply. Each feature is safe to repeat and never overwrites a choice a person made. UNVERIFIED (not run on the host) until you run it.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
envfile="$root/.env.shared"; only="citations,coauthor,awards-menu,downloads"; apply=false; localojs=""
while [ $# -gt 0 ]; do
  case "$1" in
    --only) only="${2:-}"; shift 2 ;;
    --apply) apply=true; shift ;;
    --env) envfile="${2:-}"; shift 2 ;;
    --local-ojs) localojs="${2:-}"; shift 2 ;;
    *) sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  esac
done
die() { echo "FAIL  $*" >&2; exit 1; }
[[ "$only" =~ ^[a-z,-]+$ ]] || die "--only needs feature names, for example --only citations,coauthor"
journal="worj"
json_for() { python3 - "$journal" "$apply" "$only" <<'PY'
import base64, json, sys
j, a, o = sys.argv[1:4]
print(base64.b64encode(json.dumps({"journal": j, "apply": a == "true", "ops": o.split(",")}).encode()).decode())
PY
}
if [ -n "$localojs" ]; then
  (cd "$localojs" && php -- "$(json_for)" <"$root/scripts/lib/features.php")
else
  [ -f "$envfile" ] || die "env file not found: $envfile"
  fm="$(stat -c '%a' "$envfile")"; [ $((8#$fm & 8#077)) -eq 0 ] || die "$envfile is readable by others (mode $fm): chmod 600 it"
  get() { sed -n "s/^$1=//p" "$envfile" | sed -n 1p; }
  for v in SSH_TARGET SSH_PORT REMOTE_ROOT; do val="$(get "$v")"; [ -n "$val" ] || die "$v is empty in $envfile"; printf -v "$v" '%s' "$val"; done
  SSH_KEY="$(get SSH_KEY)"; jp="$(get JOURNAL_PATH)"; journal="${jp:-worj}"
  [[ "$REMOTE_ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "REMOTE_ROOT must be an absolute path of plain characters"
  sshbase=("${WORJ_SSH:-ssh}" -p "$SSH_PORT" -o BatchMode=yes); [ -z "$SSH_KEY" ] || sshbase+=(-i "$SSH_KEY")
  printf -v webroot '%q' "$REMOTE_ROOT/public_html"
  "${sshbase[@]}" "$SSH_TARGET" "cd $webroot && php -- $(json_for)" <"$root/scripts/lib/features.php"
fi
[ "$apply" = true ] || echo "DRY RUN: nothing was changed (add --apply)"
