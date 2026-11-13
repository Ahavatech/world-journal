#!/usr/bin/env bash
# The theme option omitIssnLine, read back from the sandbox footer: by default a journal with no ISSN shows the visible placeholder;
# with the option on the line is left out; an ISSN, once entered, is always shown. The sandbox is restored by trap.
#   scripts/test-theme-issn-option.sh      needs the sandbox up (make sandbox-up sandbox-seed)
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/.env.sandbox"
base="${SANDBOX_URL:-http://127.0.0.1:8082}"
curl -s -o /dev/null -m 5 --noproxy '*' "$base/worj/" || { echo "sandbox not running (make sandbox-up sandbox-seed)"; exit 2; }
q() { mariadb "$SANDBOX_DB_NAME" -e "$1"; }
cleanup() { q "DELETE FROM plugin_settings WHERE plugin_name='worjthemeplugin' AND setting_name IN ('omitIssnLine','omitPublisherLine'); DELETE FROM journal_settings WHERE setting_name IN ('onlineIssn','publisherInstitution') AND journal_id=1"; }
trap cleanup EXIT
fail=0; pass=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
home() { curl -s --noproxy '*' "$base/worj/"; }
has() { grep -qF -- "$2" <<<"$1"; }
cleanup
yes "default: no ISSN shows the visible placeholder in the footer" has "$(home)" "[PLACEHOLDER: ISSN, pending]"
q "INSERT INTO plugin_settings (plugin_name, context_id, setting_name, setting_value, setting_type) VALUES ('worjthemeplugin', 1, 'omitIssnLine', '1', 'bool')"
h="$(home)"
yes "option on: the ISSN placeholder is gone" bash -c "! grep -qF '[PLACEHOLDER: ISSN, pending]' <<<'$(printf '%s' "$h" | tr -d "'")'"
yes "...and the other footer lines are still there (the licence placeholder is untouched)" has "$h" "[PLACEHOLDER: licence"
yes "...and no empty ISSN paragraph is left" bash -c "! grep -qE 'worj-footer__about.*ISSN' <<<'$(printf '%s' "$h" | tr -d "'" | tr -d '\n')'"
q "INSERT INTO journal_settings (journal_id, locale, setting_name, setting_value) VALUES (1, '', 'onlineIssn', '1234-5679')"
yes "an entered ISSN is shown even with the option on" has "$(home)" "eISSN 1234-5679"
q "DELETE FROM journal_settings WHERE setting_name='onlineIssn' AND journal_id=1; UPDATE plugin_settings SET setting_value='0' WHERE plugin_name='worjthemeplugin' AND setting_name='omitIssnLine'"
yes "option off again: the placeholder is back" has "$(home)" "[PLACEHOLDER: ISSN, pending]"
echo "=== the publisher line (same rule)"
yes "default: no publisher name shows the visible placeholder" has "$(home)" "[PLACEHOLDER: publisher name]"
q "INSERT INTO plugin_settings (plugin_name, context_id, setting_name, setting_value, setting_type) VALUES ('worjthemeplugin', 1, 'omitPublisherLine', '1', 'bool')"
hp="$(home)"
yes "option on: the publisher placeholder is gone" bash -c "! grep -qF '[PLACEHOLDER: publisher name]' <<<'$(printf '%s' "$hp" | tr -d "'")'"
yes "...and the licence placeholder is untouched" has "$hp" "[PLACEHOLDER: licence"
q "INSERT INTO journal_settings (journal_id, locale, setting_name, setting_value) VALUES (1, '', 'publisherInstitution', 'Example Press')"
yes "an entered publisher name is shown even with the option on" has "$(home)" "Example Press"
echo "$pass PASS, $fail FAIL"
exit "$fail"
