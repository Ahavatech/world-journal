#!/usr/bin/env bash
# Send ONE test message from the host, through the SMTP settings OJS uses (config.inc.php), to an inbox you control.
#
#   scripts/test-smtp-shared.sh --to ADDRESS [--env FILE] [--check]
#
# It reads nothing secret here: the host reads its own config.inc.php and prints only `OK ...` or `FAILED <reason>` (the
# password is masked). Then LOOK at the inbox: arrival, spam folder, the From address, the Reply-To. A message the server
# accepted can still be dropped or spam-filtered later: this proves the credentials and the connection, not delivery.
# Needs ssh access as in install-shared.sh. UNVERIFIED (not run on the host) until you run it.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
envfile="$root/.env.shared"; to=""; check=0
while [ $# -gt 0 ]; do
  case "$1" in
    --env) envfile="${2:-}"; shift 2 ;;
    --to) to="${2:-}"; shift 2 ;;
    --check) check=1; shift ;;
    *) echo "usage: $0 --to ADDRESS [--env FILE] [--check]" >&2; exit 2 ;;
  esac
done
die() { echo "FAIL  $*" >&2; exit 1; }
[[ "$to" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || die "--to needs one plain email address (an inbox you control)"
[ -f "$envfile" ] || die "env file not found: $envfile"
mode="$(stat -c '%a' "$envfile")"; [ $((8#$mode & 8#077)) -eq 0 ] || die "$envfile is readable by others (mode $mode): chmod 600 it"
get() { sed -n "s/^$1=//p" "$envfile" | sed -n 1p; }
for v in SSH_TARGET SSH_PORT REMOTE_ROOT; do val="$(get "$v")"; [ -n "$val" ] || die "$v is empty in $envfile"; printf -v "$v" '%s' "$val"; done
SSH_KEY="$(get SSH_KEY)"
[[ "$REMOTE_ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "REMOTE_ROOT must be an absolute path of plain characters"
webroot="$REMOTE_ROOT/public_html"
sshbase=("${WORJ_SSH:-ssh}" -p "$SSH_PORT" -o BatchMode=yes)
[ -z "$SSH_KEY" ] || sshbase+=(-i "$SSH_KEY")
if [ "$check" = 1 ]; then echo "WOULD: ask the host to send one test message to $to through the SMTP settings in $webroot/config.inc.php"; exit 0; fi
out="$("${sshbase[@]}" "$SSH_TARGET" "cd $(printf '%q' "$webroot") && php -- $(printf '%q' "$to")" <"$root/scripts/lib/test-smtp.php" 2>&1)" || { printf '%s\n' "$out" | sed 's/^/      /' >&2; die "the test message was not sent"; }
echo "$out"
echo "Now check the inbox of $to (and its spam folder): did it arrive, and from which address?"
