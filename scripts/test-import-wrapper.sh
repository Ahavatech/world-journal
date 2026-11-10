#!/usr/bin/env bash
# shellcheck disable=SC2317  # helper functions are called indirectly (trap, expect, refute)
# Tests scripts/import-ojs-xml.sh and scripts/import-precheck.py against a STUB OJS directory
# (a fake tools/importExport.php that records its arguments), so nothing real is imported.
#   scripts/test-import-wrapper.sh        exit 0 only if every case passes
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
w="$root/scripts/import-ojs-xml.sh"
tmp="$(mktemp -d)"; imp="$root/ojs/import"; mkdir -p "$imp"
made=()
# shellcheck disable=SC2317  # called by the EXIT trap
cleanup() { rm -rf -- "${tmp:?}"; for f in "${made[@]}"; do rm -f -- "$f"; done; rm -f -- "$imp"/.done/*.users "$imp"/.done/*.native 2>/dev/null; }
trap cleanup EXIT
fail=0
check() { # name expected_exit actual_exit
  if [ "$2" = "$3" ]; then echo "PASS  $1 (exit $3)"; else echo "FAIL  $1 (expected exit $2, got $3)"; fail=$((fail + 1)); fi
}
expect() { # name command... : PASS if the command succeeds
  local name="$1"; shift
  if "$@"; then echo "PASS  $name"; else echo "FAIL  $name"; fail=$((fail + 1)); fi
}
refute() { # name command... : PASS if the command fails
  local name="$1"; shift
  if "$@"; then echo "FAIL  $name"; fail=$((fail + 1)); else echo "PASS  $name"; fi
}
has_email() { grep -qE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$1"; }
tool_not_called() { [ ! -s "$tmp/argv.txt" ]; }
mkstub() { # dir base_url stub_exit
  mkdir -p "$1/tools"
  printf 'base_url = "%s"\n' "$2" >"$1/config.inc.php"
  cat >"$1/tools/importExport.php" <<PHP
<?php
file_put_contents('$tmp/argv.txt', implode(' ', array_slice(\$argv, 1)) . "\n", FILE_APPEND);
echo "Imported 1 item for alice@example.com\n";
exit($3);
PHP
}
mkstub "$tmp/local" "http://127.0.0.1:8082" 0
mkstub "$tmp/prod" "https://journal.example.com" 0
mkstub "$tmp/localfail" "http://localhost" 3

xml_users() { cat <<X
<?xml version="1.0"?><PKPUsers xmlns="http://pkp.sfu.ca"><users><user><email>$1</email><username>u_$2</username></user></users></PKPUsers>
X
}
mk() { local f="$imp/test-$1.xml"; made+=("$f"); cat >"$f"; echo "$f"; }

invalid="$(xml_users bob@example.invalid a | mk invalid)"
real1="$(xml_users carol@example.com b | mk real1)"
sample="$(printf '<issue xmlns="http://pkp.sfu.ca"><title>Sample Issue (not a real publication)</title><article><title>Sample Article 1</title></article></issue>' | mk sample)"
outside="$tmp/outside.xml"; xml_users dan@example.com c >"$outside"
bad="$(printf '<PKPUsers><user>' | mk bad)"

p() { "$@" >"$tmp/out.txt" 2>&1; echo $?; }
F=(--i-have-a-backup --i-understand-users-are-emailed)

check "non-localhost + .invalid address is refused" 3 "$(p "$w" users "$invalid" --journal=j --ojs="$tmp/prod" "${F[@]}")"
expect "refusal message printed" grep -q "REFUSED" "$tmp/out.txt"
check "non-localhost + sample=true record is refused" 3 "$(p "$w" native "$sample" --journal=j --user-name=u --ojs="$tmp/prod" --i-have-a-backup)"
check "non-localhost without --i-have-a-backup is refused" 3 "$(p "$w" users "$real1" --journal=j --ojs="$tmp/prod" --i-understand-users-are-emailed)"
check "non-localhost users import without the emailed acknowledgement is refused" 3 "$(p "$w" users "$real1" --journal=j --ojs="$tmp/prod" --i-have-a-backup)"
check "non-localhost file outside ojs/import/ is refused" 3 "$(p "$w" users "$outside" --journal=j --ojs="$tmp/prod" "${F[@]}")"
check "malformed XML is refused" 2 "$(p "$w" users "$bad" --journal=j --ojs="$tmp/local")"
check "--check imports nothing" 0 "$(p "$w" users "$real1" --journal=j --ojs="$tmp/local" --check)"
expect "--check did not call the import tool" tool_not_called

check "non-localhost clean file imports once (with both flags)" 0 "$(p "$w" users "$real1" --journal=j --ojs="$tmp/prod" "${F[@]}")"
refute "no email address in the output" has_email "$tmp/out.txt"
expect "tool output was redacted" grep -q "email redacted" "$tmp/out.txt"
check "second run of the same file is refused (once only)" 3 "$(p "$w" users "$real1" --journal=j --ojs="$tmp/prod" "${F[@]}")"
check "--again on a non-localhost target is refused" 3 "$(p "$w" users "$real1" --journal=j --ojs="$tmp/prod" "${F[@]}" --again)"
check "--again on localhost is allowed" 0 "$(p "$w" users "$real1" --journal=j --ojs="$tmp/local" --again)"

check "a failing tool exit is reported and not recorded" 1 "$(p "$w" users "$(xml_users erin@example.com d | mk real2)" --journal=j --ojs="$tmp/localfail")"
check "after the failure the same file can be tried again" 1 "$(p "$w" users "$imp/test-real2.xml" --journal=j --ojs="$tmp/localfail")"

: >"$tmp/argv.txt"
nat="$(printf '<articles xmlns="http://pkp.sfu.ca"><article><title>Real Title</title></article></articles>' | mk nat)"
check "native import on localhost" 0 "$(p "$w" native "$nat" --journal=worj --user-name=admin --issue-id=2 --section-abbrev=ART --ojs="$tmp/local")"
want="NativeImportExportPlugin import $nat worj admin issue_id 2 section_abbrev ART"
expect "tool called with the documented argument order" grep -qxF "$want" "$tmp/argv.txt"

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "$fail FAILED"; fi
exit "$fail"
