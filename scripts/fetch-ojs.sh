#!/usr/bin/env bash
# Fetch the pinned OJS release into ojs-core/ and verify its checksum.
# Usage: scripts/fetch-ojs.sh [--check]
#   --check  print what would happen; change nothing.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/ojs-version.env
source "$root/scripts/ojs-version.env"

dry=0
case "${1:-}" in
  --check) dry=1 ;;
  "") ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

if [ -z "${OJS_SHA256:-}" ]; then
  echo "ERROR: OJS_SHA256 is empty in scripts/ojs-version.env." >&2
  echo "Refusing to download without a checksum. Ask the human for one." >&2
  exit 1
fi

dest="$root/ojs-core"
if [ -f "$dest/.worj-ojs-version" ] && [ "$(cat "$dest/.worj-ojs-version")" = "$OJS_VERSION" ]; then
  echo "ojs-core/ already at $OJS_VERSION; nothing to do."
  exit 0
fi

if [ "$dry" -eq 1 ]; then
  echo "would download $OJS_URL"
  echo "would verify sha256 $OJS_SHA256"
  echo "would extract to $dest (an existing ojs-core/ is moved aside, not deleted)"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp:?}"' EXIT
echo "Downloading $OJS_URL"
curl -fsSL --retry 3 -o "$tmp/ojs.tar.gz" "$OJS_URL"
echo "$OJS_SHA256  $tmp/ojs.tar.gz" | sha256sum -c - || {
  echo "ERROR: checksum mismatch; not extracting." >&2
  exit 1
}
mkdir -p "$tmp/x"
tar -xzf "$tmp/ojs.tar.gz" -C "$tmp/x" --strip-components=1
if [ -e "$dest" ]; then
  old="$dest.old.$(date +%s)"
  mv "$dest" "$old"
  echo "Existing ojs-core/ moved to $old (delete it when no longer needed)."
fi
mv "$tmp/x" "$dest"
echo "$OJS_VERSION" > "$dest/.worj-ojs-version"
echo "OJS $OJS_VERSION extracted to ojs-core/"
