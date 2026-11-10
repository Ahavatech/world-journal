#!/usr/bin/env bash
# Import the sample issue (3 fake articles) into the sandbox OJS. Idempotent:
# does nothing if the journal already has an issue. Sandbox only.
# Usage: scripts/sandbox-import-sample.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/.env.sandbox"

if [ "$(mariadb -N "$SANDBOX_DB_NAME" -e 'select count(*) from issues')" -gt 0 ]; then
  echo "sample issue already imported; nothing to do."
  exit 0
fi

[ -f "$root/ojs/fixtures/pdfs/sample-article-1.pdf" ] || python3 "$root/scripts/sample-issue.py" pdfs
tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp:?}"' EXIT
python3 "$root/scripts/sample-issue.py" xml "$tmp/issue.xml"
(cd "$root/ojs-core" && php tools/importExport.php NativeImportExportPlugin import "$tmp/issue.xml" worj "$SANDBOX_ADMIN_USER" 2>&1 | grep -v 'tempnam()')
