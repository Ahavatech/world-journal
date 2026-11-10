#!/usr/bin/env bash
# Import users or articles into OJS with the pinned release's own import tool,
# behind safeguards. Wraps `php tools/importExport.php <Plugin> import ...`.
#
# Usage:
#   scripts/import-ojs-xml.sh users  FILE --journal=PATH [--check] [FLAGS]
#   scripts/import-ojs-xml.sh native FILE --journal=PATH --user-name=NAME
#                             [--issue-id=N (--section-abbrev=X | --section-name=X)] [--check] [FLAGS]
#
#   FILE                   XML in the OJS native format (users: PKPUsers; native: issue, article(s))
#   --journal=PATH         the journal's URL path (for example worj)
#   --user-name=NAME       OJS account that owns the imported articles (native)
#   --check                run the pre-flight checks only; import nothing
#   --ojs=DIR              OJS directory (default ojs-core)
#   --again                (localhost only) allow re-running a file that was already imported
#   --i-have-a-backup      REQUIRED for any target that is not localhost. It is a speed bump,
#                          NOT proof: nothing here checks that a backup exists or can be restored.
#                          Take and test a backup yourself first (docs/DEPLOY.md).
#   --i-understand-users-are-emailed
#                          REQUIRED for a users import to a non-localhost target: OJS emails every
#                          NEWLY created user (the "registration" message, with a password when the
#                          XML supplies one). Existing users are left alone, apart from group re-assignment.
#
# Safeguards: create-only in practice (a file is imported once: a record of its SHA-256 is kept in
# ojs/import/.done/); for a non-localhost target the file must live in ojs/import/ (gitignored: real
# data is personal data), and anything marked sample=true in ojs/fixtures/manifest.json or any
# address on a .invalid domain is REFUSED; email addresses are never printed (tool output is
# redacted). Run on production ONCE, after a backup.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

[ "$#" -ge 2 ] || { usage >&2; exit 2; }
kind="$1"; file="$2"; shift 2
case "$kind" in users) plugin="UserImportExportPlugin" ;; native) plugin="NativeImportExportPlugin" ;; *) usage >&2; exit 2 ;; esac

journal="" username="" issue_id="" section="" ojs="$root/ojs-core" check=0 again=0 backup=0 emailed=0
for arg in "$@"; do
  case "$arg" in
    --journal=*) journal="${arg#*=}" ;;
    --user-name=*) username="${arg#*=}" ;;
    --issue-id=*) issue_id="${arg#*=}" ;;
    --section-abbrev=*) section="section_abbrev ${arg#*=}" ;;
    --section-name=*) section="section_name ${arg#*=}" ;;
    --ojs=*) ojs="${arg#*=}" ;;
    --check) check=1 ;;
    --again) again=1 ;;
    --i-have-a-backup) backup=1 ;;
    --i-understand-users-are-emailed) emailed=1 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$journal" ] || { echo "ERROR: --journal=PATH is required" >&2; exit 2; }
[ -f "$file" ] || { echo "ERROR: file not found: $file" >&2; exit 2; }
[ -f "$ojs/config.inc.php" ] || { echo "ERROR: $ojs/config.inc.php not found (run make setup, or pass --ojs=DIR)" >&2; exit 2; }
if [ "$kind" = native ] && [ -z "$username" ]; then echo "ERROR: native import needs --user-name=NAME" >&2; exit 2; fi
file="$(realpath "$file")"

base_url="$(sed -n 's/^base_url *= *"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "$ojs/config.inc.php" | head -1)"
[ -n "$base_url" ] || { echo "ERROR: base_url not found in $ojs/config.inc.php" >&2; exit 2; }
host="$(printf '%s' "$base_url" | sed -E 's#^[a-z]+://##; s#[/:].*$##')"
local_target=0
case "$host" in localhost | 127.0.0.1 | "[::1]") local_target=1 ;; esac
echo "target: $base_url ($([ "$local_target" = 1 ] && echo localhost || echo NOT localhost)), journal: $journal, kind: $kind"

if [ "$local_target" = 0 ]; then
  case "$file" in "$root"/ojs/import/*) ;; *) echo "REFUSED: for a non-localhost target the file must be inside ojs/import/ (gitignored)." >&2; exit 3 ;; esac
  [ "$backup" = 1 ] || { echo "REFUSED: pass --i-have-a-backup for a non-localhost target (it is a speed bump, not proof: take and test a real backup first)." >&2; exit 3; }
  if [ "$kind" = users ] && [ "$emailed" != 1 ]; then echo "REFUSED: a users import emails every newly created user. Pass --i-understand-users-are-emailed to continue." >&2; exit 3; fi
  [ "$again" = 0 ] || { echo "REFUSED: --again is for localhost only; on a real target a file is imported once." >&2; exit 3; }
fi

set +e
python3 -I "$root/scripts/import-precheck.py" --kind "$kind" --file "$file" --base-url "$base_url" --manifest "$root/ojs/fixtures/manifest.json"
rc=$?
set -e
[ "$rc" = 0 ] || exit "$rc"
[ "$check" = 0 ] || { echo "check only: nothing imported."; exit 0; }

sha="$(sha256sum "$file" | cut -d' ' -f1)"
done_dir="$root/ojs/import/.done"
marker="$done_dir/$sha.$kind"
if [ -e "$marker" ] && [ "$again" = 0 ]; then
  echo "REFUSED: this exact file was already imported (record: ojs/import/.done/${sha:0:12}...). A file is imported once; use --again on localhost only." >&2
  exit 3
fi

args=("$plugin" import "$file" "$journal")
[ "$kind" = native ] && args+=("$username")
[ -z "$issue_id" ] || args+=(issue_id "$issue_id")
if [ -n "$section" ]; then read -r -a sec <<<"$section"; args+=("${sec[@]}"); fi

redact() { sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email redacted>/g'; }
out="$(mktemp)"
trap 'rm -f -- "${out:?}"' EXIT
set +e
(cd "$ojs" && php tools/importExport.php "${args[@]}") 2>&1 | grep -v 'tempnam()' | redact | tee "$out"
tool_rc="${PIPESTATUS[0]}"
set -e
if [ "$tool_rc" != 0 ] || grep -qE 'Exception|Fatal error' "$out"; then
  echo "IMPORT FAILED (tool exit $tool_rc). Nothing is recorded as done." >&2
  exit 1
fi
if grep -qE 'Connection to ".*" (has been closed|failed)|Unable to connect|could not (connect|authenticate)' "$out"; then
  echo "WARNING: the tool reported a mail problem. New users were created but their registration emails may NOT have been sent: check [email] in config.inc.php." >&2
fi
mkdir -p "$done_dir"
date -u +%Y-%m-%dT%H:%M:%SZ >"$marker"
echo "import finished; recorded ojs/import/.done/${sha:0:12}..."
