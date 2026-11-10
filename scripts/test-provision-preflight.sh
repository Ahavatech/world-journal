#!/usr/bin/env bash
# Stub tests for scripts/provision-ubuntu.sh: OS refusal, settings validation, secret handling and --check.
#   scripts/test-provision-preflight.sh        needs root (the script refuses otherwise); changes nothing outside a temp dir
# These tests do NOT provision anything. UNVERIFIED (not run on VPS).
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$(id -u)" = 0 ] || { echo "run as root (the provision script refuses otherwise)"; exit 2; }
command -v age-keygen >/dev/null || { echo "missing age (apt-get install -y age)"; exit 2; }
P="$root/scripts/provision-ubuntu.sh"
tmp="$(mktemp -d)"; chmod 700 "$tmp"
trap 'rm -rf -- "${tmp:?}"' EXIT
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
no() { local name="$1"; shift; if "$@"; then bad "$name"; else ok "$name"; fi; }
eq() { [ "$1" = "$2" ]; }

recipient="$(age-keygen 2>/dev/null | sed -n 's/^# public key: //p')"
ADMIN_SENTINEL='ADMIN-SENTINEL-71cd-xyz'; SMTP_SENTINEL='SMTP-SENTINEL-9f3a-qrs'
mkdir -p "$tmp/ojs-src/lib"; : >"$tmp/ojs-src/index.php"
mkenv() { # file [NAME=VALUE overrides...]
  local f="$1"; shift
  cat >"$f" <<CFG
HOST=journal.example.org
ALT_HOST=www.journal.example.org
TIME_ZONE=UTC
OPERATOR_USER=root
ADMIN_USERNAME=journalops
ADMIN_EMAIL=ops@journal.example.org
ADMIN_PASSWORD=$ADMIN_SENTINEL
DB_NAME=worj_t
DB_USER=worj_t
WEBROOT=/var/www/worj-provision-test
FILES_DIR=/var/lib/worj-provision-test/files
OJS_SRC=$tmp/ojs-src
CERT_METHOD=origin
CERT_FULLCHAIN=/etc/ssl/worj-test/fullchain.pem
CERT_KEY=/etc/ssl/worj-test/privkey.pem
SMTP_SERVER=smtp.mailer.example.org
SMTP_PORT=587
SMTP_AUTH=tls
SMTP_USERNAME=mailer-user
SMTP_PASSWORD=$SMTP_SENTINEL
AGE_RECIPIENT=$recipient
RCLONE_REMOTE=:local:$tmp/remote
CLOUDFLARE_SOURCE=file://$root/scripts/fixtures/cloudflare/good
CFG
  local kv k
  for kv in "$@"; do k="${kv%%=*}"; sed -i "/^$k=/d" "$f"; [ "${kv#*=}" = "__REMOVE__" ] || printf '%s\n' "$kv" >>"$f"; done
  chmod 600 "$f"
}
osrel() { # file id version version_text
  printf 'ID=%s\nVERSION_ID="%s"\nVERSION="%s"\n' "$2" "$3" "$4" >"$1"
}
run() { WORJ_OS_RELEASE="$1" "$P" "${@:2}" >"$tmp/out.txt" 2>&1; echo $?; }
UB="$tmp/os-ubuntu2404"; osrel "$UB" ubuntu 24.04 "24.04.5 LTS (Noble Numbat)"
mkenv "$tmp/good.env"

echo "=== OS refusal (before anything else)"
osrel "$tmp/os22" ubuntu 22.04 "22.04.4 LTS (Jammy Jellyfish)"; osrel "$tmp/os2410" ubuntu 24.10 "24.10 (Oracular Oriole)"
osrel "$tmp/osdeb" debian 12 "12 (bookworm)"; osrel "$tmp/osnolts" ubuntu 24.04 "24.04 (Noble)"
for f in os22:22.04 os2410:24.10 osdeb:12 osnolts:24.04; do
  rc="$(run "$tmp/${f%%:*}" --env "$tmp/good.env" --os "${f##*:}" --check)"
  yes "${f%%:*} is refused (exit $rc)" eq "$rc" 1
  yes "...with a REFUSED message" grep -q 'REFUSED' "$tmp/out.txt"
done
rc="$(run "$UB" --env "$tmp/good.env" --check)"
yes "no --os answer is refused (exit $rc)" eq "$rc" 1
yes "...and the message asks for --os" grep -q -- '--os 24.04' "$tmp/out.txt"
rc="$(run "$UB" --env "$tmp/good.env" --os 22.04 --check)"
yes "an answer that disagrees with the machine is refused (exit $rc)" eq "$rc" 1
yes "...the message names both versions" grep -q 'you said --os 22.04 but this machine is Ubuntu 24.04' "$tmp/out.txt"
rc="$(run "$UB" --env "$tmp/good.env" --os 24.04 --check --stage preflight)"
yes "Ubuntu 24.04 LTS with --os 24.04 passes preflight (exit $rc)" eq "$rc" 0

echo "=== settings validation"
refuse() { # name expected-text env-overrides...
  local name="$1" text="$2"; shift 2
  mkenv "$tmp/t.env" "$@"
  local rc; rc="$(run "$UB" --env "$tmp/t.env" --os 24.04 --check --stage preflight)"
  if [ "$rc" = 1 ] && grep -q -- "$text" "$tmp/out.txt"; then ok "$name -> refused"; else bad "$name (exit $rc)"; sed -n '1,3p' "$tmp/out.txt"; fi
}
refuse "the default administrator name 'admin'" "default administrator name" ADMIN_USERNAME=admin
refuse "an administrator name 'root'" "default administrator name" ADMIN_USERNAME=root
refuse "an .invalid administrator address" ".invalid" ADMIN_EMAIL=ops@example.invalid
refuse "a REPLACE placeholder left in place" "REPLACE" SMTP_SERVER=REPLACE
refuse "a PRIVATE age key as the recipient" "PRIVATE key" AGE_RECIPIENT=AGE-SECRET-KEY-1ABCDEF
refuse "files_dir inside the web root" "OUTSIDE the web root" FILES_DIR=/var/www/worj-provision-test/files
refuse "an unknown time zone" "not an IANA zone" TIME_ZONE=Mars/Olympus
refuse "a missing time zone (never assumed)" "TIME_ZONE is required" TIME_ZONE=__REMOVE__
refuse "HOST equal to ALT_HOST" "must differ" ALT_HOST=journal.example.org
refuse "an invalid host name" "valid host name" HOST=Not_A_Host
refuse "CERT_METHOD certbot without an email" "CERTBOT_EMAIL" CERT_METHOD=certbot
chmod 644 "$tmp/good.env"; rc="$(run "$UB" --env "$tmp/good.env" --os 24.04 --check --stage preflight)"
yes "a settings file that is not mode 600 is refused (exit $rc)" eq "$rc" 1
chmod 600 "$tmp/good.env"
rc="$(run "$UB" --env "$tmp/good.env" --os 24.04 --check --stage preflight "ADMIN_PASSWORD=oops")"
yes "a secret on the command line is refused (exit $rc)" eq "$rc" 2
rc="$(run "$UB" --env "$tmp/good.env" --os 24.04 --check --stage nosuchstage)"
yes "an unknown stage is refused (exit $rc)" eq "$rc" 1
bash -x "$P" --list-stages >/dev/null 2>"$tmp/x.txt"; rc=$?
yes "running under xtrace is refused (exit $rc)" bash -c "WORJ_OS_RELEASE='$UB' bash -x '$P' --env '$tmp/good.env' --os 24.04 --check --stage preflight >/dev/null 2>&1; [ \$? = 2 ]"

echo "=== --check on this machine changes nothing and leaks nothing"
marker="$tmp/marker"; : >"$marker"; sleep 1
rc="$(run "$UB" --env "$tmp/good.env" --os 24.04 --check)"
yes "--check exits 0 (exit $rc)" eq "$rc" 0
yes "--check says it is a check" grep -q '^CHECK MODE' "$tmp/out.txt"
yes "--check prints WOULD lines" grep -q '^  WOULD: ' "$tmp/out.txt"
yes "--check ends with a changed count" grep -q '^changed: [0-9]' "$tmp/out.txt"
echo "      $(grep -c '^  WOULD: ' "$tmp/out.txt") actions would be taken; $(tail -1 "$tmp/out.txt")"
no "no administrator password in the output" grep -qF "$ADMIN_SENTINEL" "$tmp/out.txt"
no "no SMTP password in the output" grep -qF "$SMTP_SENTINEL" "$tmp/out.txt"
changed_files="$(find /etc /usr/local /usr/share/worj-errors /var/www /var/backups /var/lib/worj-provision-test /root/.worj-provision -xdev -newer "$marker" -type f 2>/dev/null | grep -v '^/etc/mtab' | head -5)"
yes "no file under /etc, /usr/local, /var/www, /var/backups changed (tree snapshot)" eq "$changed_files" ""
yes "the web root was not created" test ! -e /var/www/worj-provision-test
yes "no answers file or installer log exists" test ! -e /root/.worj-provision/answers
rc="$(run "$UB" --env "$tmp/good.env" --os 24.04 --check --stage php)"
yes "a single stage can be checked (exit $rc)" eq "$rc" 0
yes "...and it lists the stages it ran (preflight is added)" bash -c "grep -q '== stage: preflight' '$tmp/out.txt' && grep -q '== stage: php' '$tmp/out.txt'"

echo "=== regression tests for bugs the chroot run found (each one must keep failing without its fix)"
# 1. a minimal image has no python3: preflight must say so instead of failing deep inside a stage
mkdir -p "$tmp/nopy"; ln -sf "$(command -v dirname)" "$tmp/nopy/dirname"; ln -sf "$(command -v id)" "$tmp/nopy/id"
WORJ_OS_RELEASE="$UB" env PATH="$tmp/nopy" /bin/bash "$P" --env "$tmp/good.env" --os 24.04 --check >"$tmp/out.txt" 2>&1; rc=$?
yes "REGRESSION no python3 on the image: refused with a clear message (exit $rc)" bash -c "[ '$rc' = 1 ] && grep -q 'python3 is required' '$tmp/out.txt'"
# 2. the dev OJS tree has a plugins/themes/worj symlink: it must not be copied, and the theme must be a real directory
mkdir -p "$tmp/src2/plugins/themes" "$tmp/theme2"; : >"$tmp/src2/index.php"; ln -s /nonexistent/dev/worj "$tmp/src2/plugins/themes/worj"; : >"$tmp/src2/config.inc.php"; echo "theme file" >"$tmp/theme2/version.xml"
mkenv "$tmp/rs.env" "OJS_SRC=$tmp/src2" "THEME_SRC=$tmp/theme2" "WEBROOT=$tmp/web2" "FILES_DIR=$tmp/files2"
rc="$(run "$UB" --env "$tmp/rs.env" --os 24.04 --stage ojs-code)"
yes "REGRESSION ojs-code with a dev theme symlink in the source succeeds (exit $rc)" eq "$rc" 0
yes "...the symlink was not copied: the theme is a real directory with its file" bash -c "[ ! -L '$tmp/web2/plugins/themes/worj' ] && [ -f '$tmp/web2/plugins/themes/worj/version.xml' ]"
yes "...the source's own config.inc.php was not copied" test ! -e "$tmp/web2/config.inc.php"
rc="$(run "$UB" --env "$tmp/rs.env" --os 24.04 --stage ojs-code)"
yes "...a second run changes nothing" grep -q '^   -> unchanged' "$tmp/out.txt"
yes "...cache/ and public/ belong to the web user (the installer runs as root, so this must be explicit elsewhere)" eq "$(stat -c '%U' "$tmp/web2/cache" "$tmp/web2/public" | sort -u | tr '\n' ' ')" "www-data "
# 3. the Cloudflare stage must not run `nginx -t` before our site includes the file (a stock default site can fail it)
mkdir -p "$tmp/stub"; printf '#!/bin/sh\necho "nginx stub: test failed" >&2\nexit 1\n' >"$tmp/stub/nginx"; chmod +x "$tmp/stub/nginx"
cf=/etc/nginx/worj-cloudflare-realip.conf; cfsite=/etc/nginx/conf.d/worj.conf
had_cf=0; [ ! -e "$cf" ] || { had_cf=1; cp -p "$cf" "$tmp/cf.orig"; }; had_site=0; [ ! -e "$cfsite" ] || { had_site=1; cp -p "$cfsite" "$tmp/site.orig"; }
mkdir -p /etc/nginx/conf.d; rm -f "$cf" "$cfsite"
mkenv "$tmp/cf.env" "CLOUDFLARE_SOURCE=file://$root/scripts/fixtures/cloudflare/good"
PATH="$tmp/stub:$PATH" rc="$(run "$UB" --env "$tmp/cf.env" --os 24.04 --stage cloudflare-ip)"
yes "REGRESSION first run: a failing 'nginx -t' (nothing includes the file yet) does not block the ranges file (exit $rc)" bash -c "[ '$rc' = 0 ] && [ -f $cf ]"
cp -p "$cf" "$tmp/cf.good"; printf '# real-ip from /etc/nginx/worj-cloudflare-realip.conf\n' >"$cfsite"
mkdir -p "$tmp/cfalt"; { cat "$root/scripts/fixtures/cloudflare/good/ips-v4"; echo 198.51.100.0/24; } >"$tmp/cfalt/ips-v4"
cp "$root/scripts/fixtures/cloudflare/good/ips-v6" "$tmp/cfalt/"
mkenv "$tmp/cf2.env" "CLOUDFLARE_SOURCE=file://$tmp/cfalt"
PATH="$tmp/stub:$PATH" rc="$(run "$UB" --env "$tmp/cf2.env" --os 24.04 --stage cloudflare-ip)"
yes "once our site includes the file, the config test IS run: a failing one stops the run (exit $rc)" eq "$rc" 1
yes "...and the previous ranges file is restored byte for byte" cmp -s "$cf" "$tmp/cf.good"
rm -f "$cf" "$cfsite"; [ "$had_cf" = 0 ] || cp -p "$tmp/cf.orig" "$cf"; [ "$had_site" = 0 ] || cp -p "$tmp/site.orig" "$cfsite"

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "$fail FAILED"; fi
exit "$fail"
