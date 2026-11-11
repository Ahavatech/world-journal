#!/usr/bin/env bash
# Send a release package (scripts/build-release.sh) to the shared host's web root with rsync.
#
#   scripts/deploy-shared.sh --release DIR --target TARGET [--check] [--ssh-arg ARG]...
#
# TARGET is user@host:/path/to/public_html/ (rsync over SSH) or a local directory (used by the tests).
# --check prints what WOULD change and changes nothing. Nothing secret is ever put on a command line:
# SSH options go in with --ssh-arg (a key file path, a port), the key itself stays in your ssh-agent or ~/.ssh.
#
# Never touched on the host: config.inc.php, public/ (uploaded images), cache/, .well-known/ and cgi-bin/ (the host's own).
# Files that are no longer in the package (old OJS code) ARE removed, so a release replaces the previous one exactly.
# The .htaccess file is sent last, so the rules and the code they protect change together as closely as possible.
set -euo pipefail
release="" target="" check=0 sshargs=()
usage() { echo "usage: $0 --release DIR --target TARGET [--check] [--ssh-arg ARG]..." >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --release) release="${2:-}"; shift 2 ;;
    --target) target="${2:-}"; shift 2 ;;
    --check) check=1; shift ;;
    --ssh-arg) sshargs+=("${2:-}"); shift 2 ;;
    *) usage ;;
  esac
done
{ [ -n "$release" ] && [ -n "$target" ]; } || usage
die() { echo "FAIL  $*" >&2; exit 1; }
{ [ -d "$release/public_html" ] && [ -f "$release/RELEASE.txt" ] && [ -f "$release/MANIFEST.sha256" ]; } || die "$release is not a release package (scripts/build-release.sh makes one)"
[ -f "$release/public_html/.htaccess" ] || die "the package has no .htaccess: refusing (without it the site would be served unprotected)"
[ ! -e "$release/public_html/config.inc.php" ] || die "the package contains config.inc.php: refusing"
(cd "$release/public_html" && sha256sum --quiet -c "$release/MANIFEST.sha256") || die "the package does not match its MANIFEST.sha256 (corrupted or edited): refusing"
echo "OK    package verified: $(tr '\n' ' ' <"$release/RELEASE.txt")"
case "$target" in */) ;; *) target="$target/" ;; esac
opts=(-a --delete --exclude=/config.inc.php --exclude=/public/ --exclude=/cache/ --exclude=/.well-known/ --exclude=/cgi-bin/)
rshopts=()
if [ "${#sshargs[@]}" -gt 0 ] || [ -n "${WORJ_SSH:-}" ]; then
  # rsync splits -e on spaces and understands single quotes (not backslashes)
  rsh="${WORJ_SSH:-ssh}"
  for a in "${sshargs[@]}"; do
    case "$a" in *"'"*) die "an --ssh-arg may not contain a single quote" ;; esac
    rsh="$rsh '$a'"
  done
  rshopts=(-e "$rsh")
fi
if [ "$check" = 1 ]; then
  # directory time stamps alone (".d..t......") are noise: the .htaccess files are sent in a second pass
  plan="$(rsync "${opts[@]}" "${rshopts[@]}" --dry-run --itemize-changes "$release/public_html/" "$target" | grep -Ev '^\.d\.\.t\.{6} ' || true)"
  [ -z "$plan" ] || printf '%s\n' "$plan" | sed 's/^/WOULD: /'
  echo "WOULD: $(printf '%s' "$plan" | grep -c . || true) item(s) change; nothing was changed (--check)"
  exit 0
fi
rsync "${opts[@]}" "${rshopts[@]}" --exclude=/.htaccess "$release/public_html/" "$target"
rsync -a "${rshopts[@]}" "$release/public_html/.htaccess" "${target}.htaccess"
echo "OK    deployed to $target"
