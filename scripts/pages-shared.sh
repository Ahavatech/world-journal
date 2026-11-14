#!/usr/bin/env bash
# Put the client's pages (ojs/client-content) on the host for the listed page ids only: create a page that is missing (for example one that
# launch-prep held back) and refresh one that still carries its pending banner. A page a person has edited or approved is never touched.
#
#   scripts/pages-shared.sh --only ID[,ID...] [--apply] [--env FILE] [--local-ojs DIR  (tests)]
#
# Page ids: about editorial-team aims-and-scope privacy author-guidelines disclaimer open-access peer-review publication-ethics copyright-licensing awards awards-winners
# Dry run unless --apply. UNVERIFIED (not run on the host) until you run it.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
envfile="$root/.env.shared"; only=""; apply=false; localojs=""
while [ $# -gt 0 ]; do
  case "$1" in
    --only) only="${2:-}"; shift 2 ;;
    --apply) apply=true; shift ;;
    --env) envfile="${2:-}"; shift 2 ;;
    --local-ojs) localojs="${2:-}"; shift 2 ;;
    *) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  esac
done
die() { echo "FAIL  $*" >&2; exit 1; }
[[ "$only" =~ ^[a-z0-9,-]+$ ]] || die "--only needs page ids, for example --only awards,awards-winners"
flags=(--journal=worj --client-content "--only=$only"); [ "$apply" = true ] || flags+=(--check)
if [ -n "$localojs" ]; then
  php "$root/scripts/import-pages.php" "${flags[@]}" "--ojs=$localojs"
  exit 0
fi
[ -f "$envfile" ] || die "env file not found: $envfile"
fm="$(stat -c '%a' "$envfile")"; [ $((8#$fm & 8#077)) -eq 0 ] || die "$envfile is readable by others (mode $fm): chmod 600 it"
get() { sed -n "s/^$1=//p" "$envfile" | sed -n 1p; }
for v in SSH_TARGET SSH_PORT REMOTE_ROOT; do val="$(get "$v")"; [ -n "$val" ] || die "$v is empty in $envfile"; printf -v "$v" '%s' "$val"; done
SSH_KEY="$(get SSH_KEY)"
[[ "$REMOTE_ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "REMOTE_ROOT must be an absolute path of plain characters"
webroot="$REMOTE_ROOT/public_html"; ops="$REMOTE_ROOT/worj-ops"
sshbase=("${WORJ_SSH:-ssh}" -p "$SSH_PORT" -o BatchMode=yes); [ -z "$SSH_KEY" ] || sshbase+=(-i "$SSH_KEY")
rsh=""; for a in "${sshbase[@]}"; do rsh="$rsh '$a'"; done
q() { printf '%q' "$1"; }
"${sshbase[@]}" "$SSH_TARGET" "mkdir -p $(q "$ops/scripts") $(q "$ops/ojs")"
rsync -a -e "$rsh" "$root/scripts/import-pages.php" "$SSH_TARGET:$ops/scripts/"
rsync -a --delete -e "$rsh" "$root/ojs/content/" "$SSH_TARGET:$ops/ojs/content/"
rsync -a --delete --exclude=source-v1.txt -e "$rsh" "$root/ojs/client-content/" "$SSH_TARGET:$ops/ojs/client-content/"
"${sshbase[@]}" "$SSH_TARGET" "php $(q "$ops/scripts/import-pages.php") $(printf '%q ' "${flags[@]}") --ojs=$(q "$webroot")"
[ "$apply" = true ] || echo "DRY RUN: nothing was changed (add --apply)"
