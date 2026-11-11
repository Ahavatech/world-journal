#!/usr/bin/env bash
# Render the shared-hosting web root files from infra/shared-hosting into a directory. Values arrive on STDIN
# as NAME=VALUE lines (none is a secret):
#
#   scripts/render-htaccess.sh OUTDIR < values
#
# Required values: HOST (canonical host, for example worldopenresearchjournal.com), HSTS_MAX_AGE (seconds),
# ROBOTS_MODE (closed or production; no default: a forgotten closed site is invisible, a forgotten open one is indexed).
# OUTDIR gets .htaccess, robots.txt, _errors/404.html and _errors/404.css.
# Prints `changed` or `unchanged` per file. Used by scripts/build-release.sh and scripts/test-htaccess-harness.sh.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$#" -eq 1 ] || { echo "usage: $0 OUTDIR < values" >&2; exit 2; }
out="$1"
values="$(cat)"
get() { printf '%s\n' "$values" | sed -n "s/^$1=//p" | sed -n 1p; }
host="$(get HOST)"; hsts="$(get HSTS_MAX_AGE)"; mode="$(get ROBOTS_MODE)"
[ -n "$host" ] || { echo "FAIL  HOST is empty" >&2; exit 1; }
[[ "$host" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || { echo "FAIL  HOST is not a plain lower-case host name: $host" >&2; exit 1; }
[[ "$hsts" =~ ^[0-9]+$ ]] || { echo "FAIL  HSTS_MAX_AGE must be a number of seconds" >&2; exit 1; }
case "$mode" in
  closed) robots_tpl="$root/infra/robots/robots-staging.txt.template"
          robots_line='Header always set X-Robots-Tag "noindex, nofollow"' ;;
  production) robots_tpl="$root/infra/robots/robots-production.txt.template"
          robots_line='# (production: no X-Robots-Tag)' ;;
  *) echo "FAIL  ROBOTS_MODE must be closed or production" >&2; exit 1 ;;
esac
mkdir -p "$out/_errors"
render() { # template output
  printf 'HOST=%s\nHSTS_MAX_AGE=%s\nROBOTS_HEADER_LINE=%s\n' "$host" "$hsts" "$robots_line" |
    python3 -I "$root/scripts/render-template.py" "$1" "$2" --mode 644 --allow-unused | sed "s#^#${2#"$out"/}: #"
}
render "$root/infra/shared-hosting/htaccess.template" "$out/.htaccess"
render "$robots_tpl" "$out/robots.txt"
install -m 644 "$root/infra/shared-hosting/errors/404.html" "$out/_errors/404.html"
install -m 644 "$root/infra/shared-hosting/errors/404.css" "$out/_errors/404.css"
