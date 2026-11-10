#!/usr/bin/env bash
# Render the Nginx templates in infra/nginx/ into a directory. Values arrive on STDIN as NAME=VALUE lines.
#
#   scripts/render-nginx.sh OUTDIR < values
#
# OUTDIR gets worj.conf (the site, for /etc/nginx/conf.d/) and snippets/*.conf (for the directory named by
# the SNIPPETS value). Required values: HOST ALT_HOST WEBROOT CERT_FULLCHAIN CERT_KEY PHP_SOCK SNIPPETS
# ERRORS_ROOT ACME_ROOT REALIP_CONF HTTP_PORT HTTPS_PORT HSTS_MAX_AGE. None of them is a secret.
# Prints `changed` or `unchanged` per file. Used by scripts/provision-ubuntu.sh and the tests.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$#" -eq 1 ] || { echo "usage: $0 OUTDIR < values" >&2; exit 2; }
out="$1"
values="$(cat)"
mkdir -p "$out/snippets"
# every value must be used by at least one template (a typo in a name must not pass silently)
templates=("$root/infra/nginx/worj.conf.template" "$root"/infra/nginx/snippets/*.conf.template)
used="$(grep -ho '@@[A-Z][A-Z0-9_]*@@' "${templates[@]}" | tr -d '@' | sort -u)"
given="$(printf '%s\n' "$values" | sed -n 's/^\([A-Z][A-Z0-9_]*\)=.*/\1/p' | sort -u)"
extra="$(comm -13 <(printf '%s\n' "$used") <(printf '%s\n' "$given") | tr '\n' ' ')"
if [ -n "${extra// /}" ]; then echo "FAIL  value(s) no Nginx template uses: $extra" >&2; exit 1; fi
render() { # template output
  printf '%s\n' "$values" | python3 -I "$root/scripts/render-template.py" "$1" "$2" --mode 644 --allow-unused | sed "s#^#$(basename "$2"): #"
}
render "$root/infra/nginx/worj.conf.template" "$out/worj.conf"
for t in "$root"/infra/nginx/snippets/*.conf.template; do
  render "$t" "$out/snippets/$(basename "${t%.template}")"
done
