#!/usr/bin/env bash
# See who has an account, what submissions and issues exist, and remove test accounts and test submissions safely.
#
#   scripts/accounts-shared.sh [--list]                                  read-only (default): accounts with roles, submissions, issues
#   scripts/accounts-shared.sh --merge-into KEEP --remove USER[,USER...] [--apply]
#   scripts/accounts-shared.sh --delete-submissions ID[,ID...] [--apply]   [--env FILE]
#
# --merge-into: each USER is merged into KEEP and then no longer exists (OJS's tools/mergeUsers.php). A user with the Site
# Administrator role is NEVER removed by this tool. --delete-submissions removes the submissions and their files for good
# (OJS's tools/deleteSubmissions.php). Both are a DRY RUN until you add --apply. A test issue is deleted in the admin screens
# (Issues > Back Issues or Future Issues > Delete). UNVERIFIED (not run on the host) until you run it.
# The list prints email addresses of real people: it goes to your own screen only; do not paste it anywhere public.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
envfile="$root/.env.shared"; mode=list; keep=""; remove=""; subs=""; apply=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list) mode=list; shift ;;
    --merge-into) mode=merge; keep="${2:-}"; shift 2 ;;
    --remove) remove="${2:-}"; shift 2 ;;
    --delete-submissions) mode=subs; subs="${2:-}"; shift 2 ;;
    --apply) apply=1; shift ;;
    --env) envfile="${2:-}"; shift 2 ;;
    *) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  esac
done
die() { echo "FAIL  $*" >&2; exit 1; }
[ -f "$envfile" ] || die "env file not found: $envfile"
fm="$(stat -c '%a' "$envfile")"; [ $((8#$fm & 8#077)) -eq 0 ] || die "$envfile is readable by others (mode $fm): chmod 600 it"
get() { sed -n "s/^$1=//p" "$envfile" | sed -n 1p; }
for v in SSH_TARGET SSH_PORT REMOTE_ROOT; do val="$(get "$v")"; [ -n "$val" ] || die "$v is empty in $envfile"; printf -v "$v" '%s' "$val"; done
SSH_KEY="$(get SSH_KEY)"
[[ "$REMOTE_ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "REMOTE_ROOT must be an absolute path of plain characters"
webroot="$REMOTE_ROOT/public_html"
sshbase=("${WORJ_SSH:-ssh}" -p "$SSH_PORT" -o BatchMode=yes)
[ -z "$SSH_KEY" ] || sshbase+=(-i "$SSH_KEY")
q() { printf '%q' "$1"; }
rphp() { "${sshbase[@]}" "$SSH_TARGET" "cd $(q "$webroot") && php -- $*" <"$root/scripts/lib/accounts.php"; }
rtool() { "${sshbase[@]}" "$SSH_TARGET" "cd $(q "$webroot") && php tools/$*"; }
words() { local l="$1" w out=""; for w in ${l//,/ }; do out="$out $(q "$w")"; done; printf '%s' "$out"; }

case "$mode" in
  list)
    out="$(rphp list)" || die "could not read the accounts from the host"
    echo "ACCOUNTS (id | username | email | registered | last login | state | roles)"; printf '%s\n' "$out" | sed -n 's/^user|//p' | sed 's/|/  |  /g'
    echo; echo "SUBMISSIONS (id | status | title)"; printf '%s\n' "$out" | sed -n 's/^submission|//p' | sed 's/|/  |  /g'
    echo; echo "ISSUES (id | volume | state | title)"; printf '%s\n' "$out" | sed -n 's/^issue|//p' | sed 's/|/  |  /g'
    ;;
  merge)
    [[ "$keep" =~ ^[A-Za-z0-9_.@-]+$ ]] || die "--merge-into needs one plain username"
    [ -n "$remove" ] || die "--remove needs at least one username"
    for u in ${remove//,/ }; do [[ "$u" =~ ^[A-Za-z0-9_.@-]+$ ]] || die "'$u' is not a plain username"; done
    # shellcheck disable=SC2046
    chk="$(rphp check-remove "$(q "$keep")" $(words "$remove"))" || { printf '%s\n' "$chk" | sed 's/^FAIL|/FAIL  /'; die "refusing: fix the list above first"; }
    printf '%s\n' "$chk" | sed 's/^OK|/WOULD remove  /'
    echo "...each merged into $keep, which stays."
    if [ "$apply" = 1 ]; then
      # shellcheck disable=SC2046
      rtool "mergeUsers.php $(q "$keep") $(words "$remove")"
    else echo "DRY RUN: nothing was changed (add --apply)"; fi
    ;;
  subs)
    for i in ${subs//,/ }; do [[ "$i" =~ ^[0-9]+$ ]] || die "'$i' is not a submission number"; done
    # shellcheck disable=SC2046
    chk="$(rphp submissions $(words "$subs"))" || { printf '%s\n' "$chk" | sed 's/^FAIL|/FAIL  /'; die "refusing: fix the list above first"; }
    printf '%s\n' "$chk" | sed 's/^OK|/WOULD delete submission  /; s/|/: /'
    if [ "$apply" = 1 ]; then
      # shellcheck disable=SC2046
      rtool "deleteSubmissions.php $(words "$subs")"
      echo "deleted."
    else echo "DRY RUN: nothing was changed (add --apply). This deletes the submissions and their files for good."; fi
    ;;
esac
