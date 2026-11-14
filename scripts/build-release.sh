#!/usr/bin/env bash
# Build the shared-hosting release package: pinned OJS + the worj theme + the rendered web root files.
#
#   scripts/build-release.sh --host HOST --robots-mode closed|production --out DIR [--hsts-max-age N] [--ojs-dir DIR] [--theme-dir DIR]
#
# DIR must not exist or must be empty. Result:
#   DIR/public_html/      what goes into the host's web root (never config.inc.php, public/, cache/, content or fixtures)
#   DIR/RELEASE.txt       OJS version, theme version, git commit, host, robots mode (no secrets, no timestamps)
#   DIR/MANIFEST.sha256   sha256 of every file in public_html/ (scripts/deploy-shared.sh verifies it before sending)
# Refuses: an OJS tree that is not the pinned version, an unfilled @@TOKEN@@ in a rendered file, a forbidden file in the package.
# Nothing here is a secret. See docs/DEPLOY-SHARED.md.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/ojs-version.env
source "$root/scripts/ojs-version.env"
host="" mode="" out="" hsts=300 ojs="$root/ojs-core" theme="$root/ojs/plugins/themes/worj"
usage() { echo "usage: $0 --host HOST --robots-mode closed|production --out DIR [--hsts-max-age N] [--ojs-dir DIR] [--theme-dir DIR]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --host) host="${2:-}"; shift 2 ;;
    --robots-mode) mode="${2:-}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    --hsts-max-age) hsts="${2:-}"; shift 2 ;;
    --ojs-dir) ojs="${2:-}"; shift 2 ;;
    --theme-dir) theme="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
{ [ -n "$host" ] && [ -n "$mode" ] && [ -n "$out" ]; } || usage
die() { echo "FAIL  $*" >&2; exit 1; }
[ -d "$ojs" ] || die "OJS directory not found: $ojs (run make setup)"
[ -d "$theme" ] || die "theme directory not found: $theme"
{ [ -f "$ojs/.worj-ojs-version" ] && [ "$(cat "$ojs/.worj-ojs-version")" = "$OJS_VERSION" ]; } || die "$ojs is not OJS $OJS_VERSION (the pinned version): run make setup"
if [ -e "$out" ]; then
  { [ -d "$out" ] && [ -z "$(find "$out" -mindepth 1 -print -quit)" ]; } || die "$out exists and is not empty (build into a new directory)"
fi
mkdir -p "$out/public_html"

# 1. OJS code. config.inc.php, cache/ and public/ belong to the host, never to the package. Developer-only files stay out.
rsync -a \
  --exclude=/config.inc.php --exclude=/cache/ --exclude=/public/ --exclude=/.git/ --exclude=/.github/ --exclude=/.husky/ \
  --exclude=/.eslintrc.cjs --exclude=/.php-cs-fixer.php --exclude=/.prettierignore --exclude=/cypress.config.js \
  --exclude=/cypress.travis.env.json --exclude=/vite.config.js --exclude=/vite.config.frontend.js --exclude=/jsconfig.json \
  --exclude=/phpdoc.dist.xml --exclude=/schemaspy.properties --exclude=/.worj-ojs-version \
  --exclude=/robots.txt --exclude=/plugins/themes/worj "$ojs/" "$out/public_html/"
# 2. the theme (a real copy, not the symlink make setup creates)
mkdir -p "$out/public_html/plugins/themes/worj"
rsync -a "$theme/" "$out/public_html/plugins/themes/worj/"
# 3. rendered .htaccess files, robots.txt and the static error pages
printf 'HOST=%s\nHSTS_MAX_AGE=%s\nROBOTS_MODE=%s\n' "$host" "$hsts" "$mode" | "$root/scripts/render-htaccess.sh" "$out/public_html" >/dev/null
# 4. checks on what we are about to hand over
bad="$(grep -rlE '@@[A-Z][A-Z0-9_]*@@' "$out/public_html/.htaccess" "$out/public_html/robots.txt" 2>/dev/null || true)"
[ -z "$bad" ] || die "unfilled @@TOKEN@@ in: $bad"
for forbidden in config.inc.php public cache ojs content fixtures .env .git; do
  [ ! -e "$out/public_html/$forbidden" ] || die "forbidden path in the package: $forbidden"
done
find "$out/public_html" \( -name '*.pem' -o -name '*.key' -o -name 'id_rsa*' -o -name '.env*' \) -not -path '*/lib/pkp/lib/vendor/*' -print -quit | grep -q . && die "a key or .env file is in the package"
theme_version="$(sed -n 's#.*<release>\(.*\)</release>.*#\1#p' "$theme/version.xml" | sed -n 1p)"
commit="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
git -C "$root" diff --quiet 2>/dev/null || commit="$commit-dirty"
printf 'ojs_version=%s\ntheme_version=%s\ngit_commit=%s\nhost=%s\nrobots_mode=%s\nhsts_max_age=%s\n' "$OJS_VERSION" "$theme_version" "$commit" "$host" "$mode" "$hsts" >"$out/RELEASE.txt"
(cd "$out/public_html" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) >"$out/MANIFEST.sha256"
echo "OK    release built in $out ($(wc -l <"$out/MANIFEST.sha256") files, OJS $OJS_VERSION, theme $theme_version, robots $mode, host $host)"
