#!/usr/bin/env bash
# Every email address the site itself uses must be one of the journal's own: editorial@, support@, privacy@, doi@ and admin@ on the
# journal's domain. This lists them, flags any other, and with --apply sets the ones the site sends from:
#   journal contact    editorial@HOST      journal technical support  support@HOST
#   site contact       admin@HOST          the administrator's own address  admin@HOST
#
#   scripts/emails-shared.sh [--audit | --apply] [--env FILE] [--admin-mailbox NAME]
#
# --audit (default) is read-only. Exit 0 only if every address the SITE uses is allowed (the mail sender in config.inc.php, the
# journal and site contacts, the administrator). Ordinary user accounts and authors with outside addresses are only counted and
# warned about: those are people, not the site. UNVERIFIED (not run on the host) until you run it.
# Note: an editor's own address is never the From header: config.inc.php makes OJS send every message from the mailbox and put
# the editor's address in Reply-To (email.force_dmarc_compliant_from). The Reply-To of a message an editor sends is that editor's address.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
envfile="$root/.env.shared"; mode="audit"; adminbox="admin"
while [ $# -gt 0 ]; do
  case "$1" in
    --audit) mode=audit; shift ;;
    --apply) mode=apply; shift ;;
    --env) envfile="${2:-}"; shift 2 ;;
    --admin-mailbox) adminbox="${2:-}"; shift 2 ;;
    *) echo "usage: $0 [--audit | --apply] [--env FILE] [--admin-mailbox NAME]" >&2; exit 2 ;;
  esac
done
die() { echo "FAIL  $*" >&2; exit 1; }
[[ "$adminbox" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "--admin-mailbox must be a plain lower-case name"
[ -f "$envfile" ] || die "env file not found: $envfile"
fmode="$(stat -c '%a' "$envfile")"; [ $((8#$fmode & 8#077)) -eq 0 ] || die "$envfile is readable by others (mode $fmode): chmod 600 it"
get() { sed -n "s/^$1=//p" "$envfile" | sed -n 1p; }
for v in HOST SSH_TARGET SSH_PORT REMOTE_ROOT ADMIN_USERNAME; do val="$(get "$v")"; [ -n "$val" ] || die "$v is empty in $envfile"; printf -v "$v" '%s' "$val"; done
SSH_KEY="$(get SSH_KEY)"
[[ "$HOST" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || die "HOST must be a plain lower-case host name"
[[ "$REMOTE_ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "REMOTE_ROOT must be an absolute path of plain characters"
[[ "$ADMIN_USERNAME" =~ ^[A-Za-z0-9_.-]+$ ]] || die "ADMIN_USERNAME may hold only letters, digits, _ . -"
webroot="$REMOTE_ROOT/public_html"
sshbase=("${WORJ_SSH:-ssh}" -p "$SSH_PORT" -o BatchMode=yes)
[ -z "$SSH_KEY" ] || sshbase+=(-i "$SSH_KEY")
remote_php() { "${sshbase[@]}" "$SSH_TARGET" "cd $(printf '%q' "$webroot") && php -- $*" <"$root/scripts/lib/email-addresses.php"; }
q() { printf '%q' "$1"; }
if [ "$mode" = apply ]; then
  echo "Setting: journal contact editorial@$HOST, support support@$HOST, site contact $adminbox@$HOST, administrator $ADMIN_USERNAME -> $adminbox@$HOST"
  remote_php "apply $(q "editorial@$HOST") $(q "support@$HOST") $(q "$adminbox@$HOST") $(q "$ADMIN_USERNAME") $(q "$adminbox@$HOST")" || die "could not set the addresses"
  echo "---"
fi
out="$(remote_php audit)" || die "could not read the addresses from the host"
printf '%s\n' "$out" | python3 -I "$root/scripts/lib/check-addresses.py" "$HOST" "$ADMIN_USERNAME"
