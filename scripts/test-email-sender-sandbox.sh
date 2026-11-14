#!/usr/bin/env bash
# What OJS itself really sends, read back from a fake SMTP server: with the mail settings of config.inc.php.template, a message OJS
# sends (the password-reset email) leaves from the journal's mailbox, with the envelope sender the mailbox, and the contact address
# of the journal (here an outside Gmail address, to prove it cannot leak into From) only in Reply-To. Without the settings it does not.
#   scripts/test-email-sender-sandbox.sh      needs the sandbox up (make sandbox-up sandbox-seed)
# The sandbox config and journal contact are changed for the run and restored by trap.
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/.env.sandbox"
core="$root/ojs-core"; cfg="$core/config.inc.php"
base="${SANDBOX_URL:-http://127.0.0.1:8082}"
curl -s -o /dev/null -m 5 --noproxy '*' "$base/worj/" || { echo "sandbox not running (make sandbox-up sandbox-seed)"; exit 2; }
tmp="$(mktemp -d)"
cp "$cfg" "$tmp/config.keep"
old_contact="$(mariadb -N "$SANDBOX_DB_NAME" -e "select setting_value from journal_settings where setting_name='contactEmail' limit 1")"
old_site="$(mariadb -N "$SANDBOX_DB_NAME" -e "select setting_value from site_settings where setting_name='contactEmail' limit 1")"
cleanup() {
  mariadb "$SANDBOX_DB_NAME" -e "DELETE FROM users WHERE username LIKE 'regtest_%'" 2>/dev/null
  [ -z "${fake:-}" ] || kill "$fake" 2>/dev/null
  cp "$tmp/config.keep" "$cfg"
  mariadb "$SANDBOX_DB_NAME" -e "update journal_settings set setting_value='$old_contact' where setting_name='contactEmail'; update site_settings set setting_value='$old_site' where setting_name='contactEmail'"
  rm -rf -- "${tmp:?}"
}
trap cleanup EXIT
fail=0; pass=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

MAILBOX=editorial@test.example.org
# the contacts are outside addresses on purpose: the password-reset email is sent in the name of the SITE contact
mariadb "$SANDBOX_DB_NAME" -e "update journal_settings set setting_value='outside.person@gmail.com' where setting_name='contactEmail'; update site_settings set setting_value='outside.person@gmail.com' where setting_name='contactEmail'"
python3 -I "$root/scripts/lib/fake-smtp.py" 2525 "$tmp/cap.jsonl" & fake=$!
sleep 1
reset_mail() { # dmarc forced? envelope forced?  -> sends one password-reset email, prints the captured message as JSON line
  rm -f "$tmp/cap.jsonl"
  printf 'email.default=smtp\nemail.smtp_server=127.0.0.1\nemail.smtp_port=2525\nemail.smtp_auth=\nemail.smtp_username=%s\nemail.smtp_password=secretpw\nemail.default_envelope_sender=%s\nemail.force_default_envelope_sender=%s\nemail.force_dmarc_compliant_from=%s\nemail.dmarc_compliant_from_displayname=%s\n' \
    "$MAILBOX" "$MAILBOX" "$1" "$2" "'%s'" | python3 -I "$root/scripts/set-ojs-config.py" "$cfg" >/dev/null
  local jar="$tmp/jar" page tok
  rm -f "$jar"
  page="$(curl -s --noproxy '*' -c "$jar" -b "$jar" "$base/worj/login/lostPassword")"
  tok="$(grep -o 'name="csrfToken" value="[^"]*"' <<<"$page" | head -1 | sed 's/.*value="//;s/"//')"
  curl -s --noproxy '*' -c "$jar" -b "$jar" -o /dev/null -d "csrfToken=$tok" --data-urlencode "email=admin@example.invalid" "$base/worj/login/requestResetPassword"
  for _ in 1 2 3 4 5; do [ -s "$tmp/cap.jsonl" ] && break; (cd "$core" && php lib/pkp/tools/jobs.php run >/dev/null 2>&1); sleep 1; done
}
show() { python3 -I -c "
import json,sys
d=[json.loads(l) for l in open('$tmp/cap.jsonl')][-1]
head=d['data'].split('\r\n\r\n')[0].replace('\r\n ',' ')
hs={l.split(':',1)[0].lower():l.split(':',1)[1].strip() for l in head.split('\r\n') if ':' in l}
print(json.dumps({'envelope':d['from'],'to':d['to'],'from':hs.get('from',''),'reply-to':hs.get('reply-to',''),'subject':hs.get('subject','')}))
"; }
# has JSON-LINE FIELD SUBSTRING / lacks JSON-LINE FIELD SUBSTRING (the message is passed in the environment, never through shell quoting)
has() { M="$1" python3 -I -c "import json,os,sys; v=json.loads(os.environ['M']).get(sys.argv[1],''); v=' '.join(v) if isinstance(v,list) else v; sys.exit(0 if sys.argv[2] in v else 1)" "$2" "$3"; }
lacks() { ! has "$1" "$2" "$3"; }
ph() { grep -qF -- "$2" <<<"$1"; }  # text contains a string

echo "=== the settings from the template: On / On"
reset_mail On On
yes "a password-reset email was sent through the fake SMTP server" test -s "$tmp/cap.jsonl"
m="$(show 2>/dev/null)"
yes "From is the mailbox" has "$m" from "$MAILBOX"
yes "the envelope sender is the mailbox" has "$m" envelope "$MAILBOX"
yes "the outside contact address is NOT in the From" lacks "$m" from gmail
yes "...it moved to Reply-To" has "$m" reply-to outside.person@gmail.com
yes "the message goes to the person who asked (the administrator)" has "$m" to admin@example.invalid

echo "=== mutation: without the settings the outside address becomes the From"
reset_mail Off Off
m2="$(show 2>/dev/null)"
yes "with both settings Off the From is the outside contact address" has "$m2" from outside.person@gmail.com
reset_mail On Off
m3="$(show 2>/dev/null)"
yes "with only the envelope forced the From is still the outside address (the DMARC setting is what moves it)" has "$m3" from outside.person@gmail.com
yes "...while the envelope sender is the mailbox" has "$m3" envelope "$MAILBOX"

echo "=== registration with email validation on (the journal's setting): the page and the message tell people to check spam"
printf 'email.require_validation=On\nemail.default_envelope_sender=%s\nemail.force_default_envelope_sender=On\nemail.force_dmarc_compliant_from=On\n' "$MAILBOX" | python3 -I "$root/scripts/set-ojs-config.py" "$cfg" >/dev/null
rm -f "$tmp/cap.jsonl"
form="$(curl -s --noproxy '*' -c "$tmp/jar2" -b "$tmp/jar2" "$base/worj/user/register")"
yes "the registration page tells people the email may land in spam (before they register)" ph "$form" "may land in your spam folder"
tok="$(grep -o 'name="csrfToken" value="[^"]*"' <<<"$form" | head -1 | sed 's/.*value="//;s/"//')"
user="regtest_$$"
reply="$(curl -s --noproxy '*' -c "$tmp/jar2" -b "$tmp/jar2" -d "csrfToken=$tok" -d givenName=Reg -d familyName=Tester -d affiliation=Test -d country=GB --data-urlencode "email=$user@example.invalid" -d "username=$user" -d "password=Correct-Horse-9xQ" -d "password2=Correct-Horse-9xQ" -d privacyConsent=1 "$base/worj/user/register")"
yes "after registering OJS itself says to check the spam folder" ph "$reply" "spam folder"
for _ in 1 2 3 4 5; do [ -s "$tmp/cap.jsonl" ] && break; (cd "$core" && php lib/pkp/tools/jobs.php run >/dev/null 2>&1); sleep 1; done
yes "a validation email was sent" test -s "$tmp/cap.jsonl"
mv2="$(show 2>/dev/null)"
yes "...to the person who registered" has "$mv2" to "$user@example.invalid"
yes "...with the From being the mailbox (not an outside address)" has "$mv2" from "$MAILBOX"
yes "...and the envelope sender the mailbox" has "$mv2" envelope "$MAILBOX"
yes "...and a subject about validating the account" bash -c "python3 -I -c \"import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if 'alidat' in d.get('subject','') else 1)\" '$mv2'"
yes "the new account cannot log in until the link is clicked" bash -c "[ \"\$(mariadb -N '$SANDBOX_DB_NAME' -e \"select disabled from users where username='$user'\")\" = 1 ]"

echo "$pass PASS, $fail FAIL"
exit "$fail"
