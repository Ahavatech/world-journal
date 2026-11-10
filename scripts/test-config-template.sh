#!/usr/bin/env bash
# Negative tests for scripts/check-config-template.py: each mutation of a copy of the template must fail.
#   scripts/test-config-template.sh        exit 0 only if the clean template passes and every mutation is caught
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tpl="$root/ojs/config/config.inc.php.template"
tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp:?}"' EXIT
fail=0
run() { python3 -I "$root/scripts/check-config-template.py" --template "$1" "${@:2}"; }

mutate() { # name sed-expression expected-substring
  cp "$tpl" "$tmp/t"
  sed -i -E "$2" "$tmp/t"
  out="$(run "$tmp/t" 2>&1)"; rc=$?
  if [ "$rc" = 1 ] && grep -q "$3" <<<"$out"; then echo "PASS  $1 -> exit 1"; grep "FAIL" <<<"$out" | head -2 | sed 's/^/        /'
  else
    echo "FAIL  $1 (exit $rc)"
    while IFS= read -r l; do echo "        $l"; done <<<"$out"
    fail=$((fail + 1))
  fi
}

out="$(run "$tpl" 2>&1)"; rc=$?
if [ "$rc" = 0 ]; then echo "PASS  clean template -> exit 0 ($(tail -1 <<<"$out"))"; else echo "FAIL  clean template (exit $rc)"; echo "$out"; fail=$((fail + 1)); fi

mutate "bogus key" 's/^(session_cookie_name = .*)$/\1\nsession_cookie_nmae = typo/' "unknown key"
mutate "bogus key in a new section" 's/^\[queues\]$/[queues]\nmade_up_setting = On/' "unknown key"
mutate "real-looking secret in the salt" 's/^salt = .*/salt = "k3Jf9sLx02QpVbn7TzR4wYhA81mCdEuG"/' "must be empty or an @@TOKEN@@"
mutate "the shipped default salt" 's/^salt = .*/salt = "YouMustSetASecretKeyHere!!"/' "must be empty or an @@TOKEN@@"
mutate "a literal database password" 's/^password = @@DB_PASSWORD@@/password = hunter2hunter2/' "database.password"
mutate "a literal mail password" 's/^smtp_password = .*/smtp_password = Zq8vLm2Xc9Rt4NbJ/' "smtp_password"
mutate "a pasted application key" 's/^app_key =.*/app_key = "base64:F7RsXQqaB\/ELOr8fCyeFtiTJYMcRjkpF9+\/6bvgvWG8="/' "app_key"
mutate "a secret hidden in an ordinary key" 's/^session_cookie_name = .*/session_cookie_name = a1B2c3D4e5F6g7H8i9J0kLmNoP/' "real-looking secret"
mutate "missing required key (installed removed)" '/^installed = /d' "missing required key"
mutate "missing required key (files_dir removed)" '/^files_dir = /d' "missing required key"
mutate "installed set On" 's/^installed = Off/installed = On/' "must be Off"
mutate "wrong OJS version in the header" 's/config.inc.php template for OJS [0-9.\-]+/config.inc.php template for OJS 3.4.0-1/' "re-run scripts/make-config-template.py"

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "$fail FAILED"; fi
exit "$fail"
