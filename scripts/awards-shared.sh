#!/usr/bin/env bash
# Install and switch on the Research Awards plugin on the shared host (after a deploy that carries plugins/generic/worjAwards).
#
#   scripts/awards-shared.sh [--apply] [--env FILE] [--local-ojs DIR  (tests)]
#
# Dry run unless --apply. Two steps: create the plugin's two tables (OJS's installPluginVersion tool; safe to repeat) and enable it for the journal.
# Nothing is public until you also open nominations on /worj/awards-manage and approve the awards pages (scripts/launch-prep-shared.sh --approve).
# UNVERIFIED (not run on the host) until you run it.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
envfile="$root/.env.shared"; apply=false; localojs=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=true; shift ;;
    --env) envfile="${2:-}"; shift 2 ;;
    --local-ojs) localojs="${2:-}"; shift 2 ;;
    *) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  esac
done
die() { echo "FAIL  $*" >&2; exit 1; }
journal="worj"
if [ -z "$localojs" ]; then
  [ -f "$envfile" ] || die "env file not found: $envfile"
  fm="$(stat -c '%a' "$envfile")"; [ $((8#$fm & 8#077)) -eq 0 ] || die "$envfile is readable by others (mode $fm): chmod 600 it"
  get() { sed -n "s/^$1=//p" "$envfile" | sed -n 1p; }
  for v in SSH_TARGET SSH_PORT REMOTE_ROOT; do val="$(get "$v")"; [ -n "$val" ] || die "$v is empty in $envfile"; printf -v "$v" '%s' "$val"; done
  SSH_KEY="$(get SSH_KEY)"; jp="$(get JOURNAL_PATH)"; journal="${jp:-worj}"
  [[ "$REMOTE_ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "REMOTE_ROOT must be an absolute path of plain characters"
  sshbase=("${WORJ_SSH:-ssh}" -p "$SSH_PORT" -o BatchMode=yes); [ -z "$SSH_KEY" ] || sshbase+=(-i "$SSH_KEY")
  printf -v webroot '%q' "$REMOTE_ROOT/public_html"
fi
json="$(printf '{"journal":"%s","apply":%s}' "$journal" "$apply" | base64 -w0)"
run() { if [ -n "$localojs" ]; then (cd "$localojs" && "$@"); else "${sshbase[@]}" "$SSH_TARGET" "cd $webroot && $*"; fi; }
if [ "$apply" = true ]; then
  run php lib/pkp/tools/installPluginVersion.php plugins/generic/worjAwards/version.xml >/dev/null || die "could not install the plugin's tables (was the release with the plugin deployed?)"
  echo "ok    the plugin's tables are installed"
else
  echo "WOULD: install the plugin's tables (installPluginVersion), then enable it"
fi
if [ -n "$localojs" ]; then
  (cd "$localojs" && php -- "$json" <"$root/scripts/lib/awards-enable.php") || true
elif [ "$apply" = true ]; then
  "${sshbase[@]}" "$SSH_TARGET" "cd $webroot && php -- $json" <"$root/scripts/lib/awards-enable.php"
else
  echo "(the dry run stops here: the second step needs the tables, which exist only after --apply)"
fi
[ "$apply" = true ] || echo "DRY RUN: nothing was changed (add --apply)"
