#!/usr/bin/env bash
# Correct the publication date of published articles on the shared host.
#
#   scripts/set-article-dates-shared.sh 8=2025-02-13 9=2022-08-20 [--apply] [--env FILE] [--local-ojs DIR  (tests)]
#
# Each argument is SUBMISSION_NUMBER=YYYY-MM-DD (the numbers are in `scripts/accounts-shared.sh --list`). Dry run unless --apply. Only a published
# article is changed, and only its publication date. UNVERIFIED on the host until you run it.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
envfile="$root/.env.shared"; apply=false; localojs=""; pairs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=true; shift ;;
    --env) envfile="${2:-}"; shift 2 ;;
    --local-ojs) localojs="${2:-}"; shift 2 ;;
    [0-9]*=*) pairs+=("$1"); shift ;;
    *) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  esac
done
die() { echo "FAIL  $*" >&2; exit 1; }
[ ${#pairs[@]} -gt 0 ] || die "give at least one NUMBER=YYYY-MM-DD"
for p in "${pairs[@]}"; do [[ "$p" =~ ^[0-9]+=[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "'$p' is not NUMBER=YYYY-MM-DD"; done
json="$(A="$apply" P="${pairs[*]}" python3 -I - <<'PY'
import base64, json, os
d = dict(x.split("=") for x in os.environ["P"].split())
print(base64.b64encode(json.dumps({"journal": "worj", "apply": os.environ["A"] == "true", "dates": d}).encode()).decode())
PY
)"
if [ -n "$localojs" ]; then
  (cd "$localojs" && php -- "$json" <"$root/scripts/lib/set-article-dates.php")
else
  [ -f "$envfile" ] || die "env file not found: $envfile"
  fm="$(stat -c '%a' "$envfile")"; [ $((8#$fm & 8#077)) -eq 0 ] || die "$envfile is readable by others (mode $fm): chmod 600 it"
  get() { sed -n "s/^$1=//p" "$envfile" | sed -n 1p; }
  for v in SSH_TARGET SSH_PORT REMOTE_ROOT; do val="$(get "$v")"; [ -n "$val" ] || die "$v is empty in $envfile"; printf -v "$v" '%s' "$val"; done
  SSH_KEY="$(get SSH_KEY)"; [[ "$REMOTE_ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "REMOTE_ROOT must be an absolute path of plain characters"
  sshbase=("${WORJ_SSH:-ssh}" -p "$SSH_PORT" -o BatchMode=yes); [ -z "$SSH_KEY" ] || sshbase+=(-i "$SSH_KEY")
  printf -v webroot '%q' "$REMOTE_ROOT/public_html"
  "${sshbase[@]}" "$SSH_TARGET" "cd $webroot && php -- $json" <"$root/scripts/lib/set-article-dates.php"
fi
[ "$apply" = true ] || echo "DRY RUN: nothing was changed (add --apply)"
