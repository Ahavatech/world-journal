#!/usr/bin/env bash
# Create the client's editorial accounts on the shared host: a random temporary password each, which OJS forces them to change at the first login.
#
#   scripts/create-accounts-shared.sh [--apply] [--account user,email,Given,Family,Role]... [--tidy-admin [--admin-username NAME]] [--env FILE] [--local-ojs DIR  (tests)]
#
# Default accounts (no --account given): johnpaul (Journal editor) and danwilliams (Section editor, assigned to every section).
# Dry run unless --apply. With --apply each temporary password is printed ONCE on your screen: copy it into a separate channel to the
# person (never the same message as the username), then clear the screen. Nothing is stored: not in a file, a log or git.
# --tidy-admin also removes the Author and Reviewer roles the test-account merge left on `administrator`.
# An account whose username or email already exists is refused and nothing is written. UNVERIFIED (not run on the host) until you run it.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
envfile="$root/.env.shared"; apply=false; tidy=false; accts=(); localojs=""; adminu="administrator"
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=true; shift ;;
    --account) accts+=("${2:-}"); shift 2 ;;
    --tidy-admin) tidy=true; shift ;;
    --admin-username) adminu="${2:-}"; shift 2 ;;
    --local-ojs) localojs="${2:-}"; shift 2 ;;
    --env) envfile="${2:-}"; shift 2 ;;
    *) sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  esac
done
die() { echo "FAIL  $*" >&2; exit 1; }
if [ -z "$localojs" ]; then
[ -f "$envfile" ] || die "env file not found: $envfile"
fm="$(stat -c '%a' "$envfile")"; [ $((8#$fm & 8#077)) -eq 0 ] || die "$envfile is readable by others (mode $fm): chmod 600 it"
get() { sed -n "s/^$1=//p" "$envfile" | sed -n 1p; }
for v in SSH_TARGET SSH_PORT REMOTE_ROOT; do val="$(get "$v")"; [ -n "$val" ] || die "$v is empty in $envfile"; printf -v "$v" '%s' "$val"; done
SSH_KEY="$(get SSH_KEY)"; journal="$(get JOURNAL_PATH)"; journal="${journal:-worj}"
[[ "$REMOTE_ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "REMOTE_ROOT must be an absolute path of plain characters"
fi
journal="${journal:-worj}"
if [ ${#accts[@]} -eq 0 ]; then
  accts=("johnpaul,johnpaul@worldopenresearchjournal.com,Paul,John,Journal editor" "danwilliams,danwilliams@worldopenresearchjournal.com,Dan,Williams,Section editor")
fi
if [ -z "$localojs" ]; then
sshbase=("${WORJ_SSH:-ssh}" -p "$SSH_PORT" -o BatchMode=yes)
[ -z "$SSH_KEY" ] || sshbase+=(-i "$SSH_KEY")
fi
json="$(ACCTS="$(printf '%s\n' "${accts[@]}")" J="$journal" A="$apply" T="$tidy" ADMINU="$adminu" python3 - <<'PY'
import base64, json, os, sys
rows = []
for line in os.environ["ACCTS"].splitlines():
    p = line.split(",")
    if len(p) != 5 or not all(x.strip() for x in p):
        sys.exit("bad --account (need user,email,Given,Family,Role): " + line)
    rows.append(dict(zip(["username", "email", "given", "family", "group"], [x.strip() for x in p])))
o = {"journal": os.environ["J"], "apply": os.environ["A"] == "true", "accounts": rows}
if os.environ["T"] == "true":
    o["drop_admin_roles"] = ["Author", "Reviewer"]
    o["admin"] = os.environ["ADMINU"]
print(base64.b64encode(json.dumps(o).encode()).decode())
PY
)" || die "could not build the request"
if [ -n "$localojs" ]; then
  out="$(cd "$localojs" && php -- "$json" <"$root/scripts/lib/create-accounts.php")" && rc=0 || rc=$?
else
  printf -v webroot '%q' "$REMOTE_ROOT/public_html"
  out="$("${sshbase[@]}" "$SSH_TARGET" "cd $webroot && php -- $json" <"$root/scripts/lib/create-accounts.php")" && rc=0 || rc=$?
fi
printf '%s\n' "$out" | grep -v '^PASSWORD|'
pw="$(printf '%s\n' "$out" | sed -n 's/^PASSWORD|//p')"
if [ -n "$pw" ]; then
  echo
  echo "TEMPORARY PASSWORDS (shown once, stored nowhere; send each by a DIFFERENT channel than the username):"
  printf '%s\n' "$pw" | while IFS='|' read -r u p; do printf '  %-14s %s\n' "$u" "$p"; done
  echo "Clear your screen after copying them. At the first login each person is sent to a change-password page."
fi
[ "$apply" = true ] || echo "DRY RUN: nothing was changed (add --apply)"
exit "$rc"
