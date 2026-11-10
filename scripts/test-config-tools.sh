#!/usr/bin/env bash
# shellcheck disable=SC2317  # helper functions are called indirectly (through yes and no)
# Tests for scripts/render-template.py and scripts/set-ojs-config.py (secret-safe config tools).
#   scripts/test-config-tools.sh        exit 0 only if every case passes
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp:?}"' EXIT
R=(python3 -I "$root/scripts/render-template.py")
S=(python3 -I "$root/scripts/set-ojs-config.py")
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
expect_rc() { # name expected actual
  if [ "$2" = "$3" ]; then ok "$1 (exit $3)"; else bad "$1 (expected exit $2, got $3)"; fi
}
yes() { # name command... : PASS if the command succeeds
  local name="$1"; shift
  if "$@"; then ok "$name"; else bad "$name"; fi
}
no() { # name command... : PASS if the command fails
  local name="$1"; shift
  if "$@"; then bad "$name"; else ok "$name"; fi
}
mode_of() { stat -c '%a' "$1"; }

has_line() { grep -qxF -- "$1" "$2"; }
mode_is() { [ "$(stat -c '%a' "$2")" = "$1" ]; }
content_is() { [ "$(cat "$2")" = "$1" ]; }
len_ge() { [ "${#1}" -ge "$2" ]; }
strong_distinct() { [ "${#1}" -ge 32 ] && [ "$1" != "YouMustSetASecretKeyHere!!" ]; }
differ() { [ "$1" != "$2" ]; }
no_tmp_left() { ! compgen -G "$tmp/.render-*" >/dev/null; }
not_exists() { [ ! -e "$1" ]; }

# ---------- render-template.py
printf 'host = @@HOST@@\nsecret = "@@SALT@@"\n; a comment\n' >"$tmp/t.tpl"
printf 'HOST=journal.example.com\nSALT=ab=cd/ef+gh\n' | "${R[@]}" "$tmp/t.tpl" "$tmp/out.conf" --mode 640 >"$tmp/r1.txt" 2>&1; rc=$?
expect_rc "render fills every token" 0 "$rc"
yes "values containing = and / survive" has_line 'secret = "ab=cd/ef+gh"' "$tmp/out.conf"
yes "output mode is 640" mode_is 640 "$tmp/out.conf"
no "no value in the tool's output" grep -q "ab=cd" "$tmp/r1.txt"
yes "first run says changed" content_is changed "$tmp/r1.txt"
printf 'HOST=journal.example.com\nSALT=ab=cd/ef+gh\n' | "${R[@]}" "$tmp/t.tpl" "$tmp/out.conf" --mode 640 >"$tmp/r2.txt" 2>&1
yes "second run says unchanged (idempotent)" content_is unchanged "$tmp/r2.txt"

printf 'HOST=x\n' | "${R[@]}" "$tmp/t.tpl" "$tmp/out2.conf" >"$tmp/r3.txt" 2>&1; rc=$?
expect_rc "an unfilled token fails" 1 "$rc"
yes "nothing is written when a token is unfilled" not_exists "$tmp/out2.conf"
yes "the message names the missing token" grep -q "SALT" "$tmp/r3.txt"
printf 'HOST=x\nSALT=y\nTYPO=z\n' | "${R[@]}" "$tmp/t.tpl" "$tmp/out3.conf" >"$tmp/r4.txt" 2>&1; rc=$?
expect_rc "a value for a token the template does not use fails" 1 "$rc"
printf '' | "${R[@]}" "$tmp/t.tpl" "$tmp/out4.conf" 'SALT=oops-on-argv' >"$tmp/r5.txt" 2>&1; rc=$?
expect_rc "values on the command line are refused" 2 "$rc"
yes "no temporary file left behind" no_tmp_left

# ---------- set-ojs-config.py
cat >"$tmp/config.inc.php" <<'CFG'
; <?php exit; // DO NOT DELETE?>
[general]
; keep this comment
installed = On
allowed_hosts = '[""]'
time_zone =
[security]
salt = "YouMustSetASecretKeyHere!!"
api_key_secret = ""
; trailing comment
CFG
chmod 640 "$tmp/config.inc.php"
cp "$tmp/config.inc.php" "$tmp/config.before"
printf 'general.allowed_hosts=%s\ngeneral.time_zone="UTC"\n' "'[\"journal.example.com\"]'" |
  "${S[@]}" "$tmp/config.inc.php" --generate-if-weak security.salt --generate-if-weak security.api_key_secret >"$tmp/s1.txt" 2>&1; rc=$?
expect_rc "set and generate" 0 "$rc"
yes "allowed_hosts set to the real domain" has_line "allowed_hosts = '[\"journal.example.com\"]'" "$tmp/config.inc.php"
yes "time_zone set" has_line 'time_zone = "UTC"' "$tmp/config.inc.php"
salt="$(sed -n 's/^salt = "\(.*\)"$/\1/p' "$tmp/config.inc.php")"
api="$(sed -n 's/^api_key_secret = "\(.*\)"$/\1/p' "$tmp/config.inc.php")"
yes "salt generated (${#salt} chars, not the shipped default)" strong_distinct "$salt"
yes "api_key_secret generated (${#api} chars)" len_ge "$api" 32
yes "salt and api_key_secret differ" differ "$salt" "$api"
if grep -qF -e "$salt" -e "$api" "$tmp/s1.txt"; then bad "a generated secret was printed"; else ok "no secret in the tool's output"; fi
yes "file mode kept (640)" mode_is 640 "$tmp/config.inc.php"
yes "comment kept" has_line "; keep this comment" "$tmp/config.inc.php"
yes "trailing comment kept" has_line "; trailing comment" "$tmp/config.inc.php"
yes "guard line kept" has_line "; <?php exit; // DO NOT DELETE?>" "$tmp/config.inc.php"
changed_lines="$(diff "$tmp/config.before" "$tmp/config.inc.php" | grep -c '^>')"
yes "exactly the 4 intended lines changed" content_is 4 <(echo "$changed_lines")

cp "$tmp/config.inc.php" "$tmp/config.run1"
printf 'general.allowed_hosts=%s\ngeneral.time_zone="UTC"\n' "'[\"journal.example.com\"]'" |
  "${S[@]}" "$tmp/config.inc.php" --generate-if-weak security.salt --generate-if-weak security.api_key_secret >"$tmp/s2.txt" 2>&1
yes "a second run changes nothing: strong secrets are never rotated" cmp -s "$tmp/config.run1" "$tmp/config.inc.php"
yes "second run reports the secrets as kept" grep -q "already strong" "$tmp/s2.txt"

printf '' | "${S[@]}" "$tmp/config.inc.php" --generate-if-weak security.nonexistent >"$tmp/s3.txt" 2>&1; rc=$?
expect_rc "a missing key fails" 1 "$rc"
printf 'nosection.key=1\n' | "${S[@]}" "$tmp/config.inc.php" >"$tmp/s4.txt" 2>&1; rc=$?
expect_rc "a missing section fails" 1 "$rc"
printf 'general.time_zone=x\n' | "${S[@]}" "$tmp/config.inc.php" "SECRET=oops" >"$tmp/s5.txt" 2>&1; rc=$?
yes "an extra argument is refused" differ "$rc" 0

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "$fail FAILED"; fi
exit "$fail"
