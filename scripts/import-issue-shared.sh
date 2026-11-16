#!/usr/bin/env bash
# Import one issue with its articles (a file made by scripts/build-issue-import.py) into the journal on the shared host, as the administrator.
#
#   scripts/import-issue-shared.sh --xml FILE [--apply] [--user NAME] [--env FILE] [--local-ojs DIR  (tests)]
#
# Dry run unless --apply: it checks the file and says what it would import. OJS's importer is NOT repeatable (a second run duplicates the issue), so
# the script refuses when the host already has an issue with the same volume, number and year. The file is copied to the host's ops folder
# (outside the web root), used once and deleted. It holds the authors' details: keep your copy private. UNVERIFIED on the host until you run it.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
envfile="$root/.env.shared"; xml=""; apply=false; user="administrator"; localojs=""
while [ $# -gt 0 ]; do
  case "$1" in
    --xml) xml="${2:-}"; shift 2 ;;
    --apply) apply=true; shift ;;
    --user) user="${2:-}"; shift 2 ;;
    --env) envfile="${2:-}"; shift 2 ;;
    --local-ojs) localojs="${2:-}"; shift 2 ;;
    *) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  esac
done
die() { echo "FAIL  $*" >&2; exit 1; }
[ -f "$xml" ] || die "give the file with --xml"
[[ "$user" =~ ^[A-Za-z0-9_.-]+$ ]] || die "--user must be a plain username"
xmllint --noout "$xml" || die "the file is not well-formed XML"
summary="$(python3 -I - "$xml" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = {"p": "http://pkp.sfu.ca"}
r = ET.parse(sys.argv[1]).getroot()
i = r.find("p:issue", ns)
idn = i.find("p:issue_identification", ns)
v, n, y = (idn.findtext(f"p:{k}", namespaces=ns) for k in ("volume", "number", "year"))
t = idn.findtext("p:title", namespaces=ns)
arts = i.findall("p:articles/p:article", ns)
print(f"{v}|{n}|{y}|{t}|{len(arts)}")
for a in arts:
    print("A|" + a.find("p:publication/p:title", ns).text)
PY
)" || die "could not read the issue from the file"
head="$(printf '%s\n' "$summary" | head -1)"; IFS='|' read -r vol num year title count <<<"$head"
echo "FILE  Volume $vol, Number $num, $year: $title ($count article(s))"
printf '%s\n' "$summary" | sed -n 's/^A|/      - /p'
exist() { grep -E "^issue\|[0-9]+\|vol $vol no $num $year\|" || true; }
q() { printf '%q' "$1"; }
if [ -n "$localojs" ]; then
  found="$(cd "$localojs" && php -- list <"$root/scripts/lib/accounts.php" | exist)"
else
  [ -f "$envfile" ] || die "env file not found: $envfile"
  fm="$(stat -c '%a' "$envfile")"; [ $((8#$fm & 8#077)) -eq 0 ] || die "$envfile is readable by others (mode $fm): chmod 600 it"
  get() { sed -n "s/^$1=//p" "$envfile" | sed -n 1p; }
  for v in SSH_TARGET SSH_PORT REMOTE_ROOT; do val="$(get "$v")"; [ -n "$val" ] || die "$v is empty in $envfile"; printf -v "$v" '%s' "$val"; done
  SSH_KEY="$(get SSH_KEY)"; [[ "$REMOTE_ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "REMOTE_ROOT must be an absolute path of plain characters"
  webroot="$REMOTE_ROOT/public_html"; ops="$REMOTE_ROOT/worj-ops"
  sshbase=("${WORJ_SSH:-ssh}" -p "$SSH_PORT" -o BatchMode=yes); [ -z "$SSH_KEY" ] || sshbase+=(-i "$SSH_KEY")
  found="$("${sshbase[@]}" "$SSH_TARGET" "cd $(q "$webroot") && php -- list" <"$root/scripts/lib/accounts.php" | exist)"
fi
[ -z "$found" ] || die "the journal already has an issue Volume $vol, Number $num, $year: importing again would duplicate it"
if [ "$apply" != true ]; then echo "WOULD: import the file as $user. DRY RUN: nothing was changed (add --apply)"; exit 0; fi
if [ -n "$localojs" ]; then
  (cd "$localojs" && php tools/importExport.php NativeImportExportPlugin import "$(readlink -f "$xml")" worj "$user" 2>&1 | grep -v "tempnam" | tail -12)
else
  rsh=""; for a in "${sshbase[@]}"; do rsh="$rsh '$a'"; done
  "${sshbase[@]}" "$SSH_TARGET" "mkdir -p $(q "$ops")"
  rsync -a -e "$rsh" "$xml" "$SSH_TARGET:$ops/issue-import.xml"
  "${sshbase[@]}" "$SSH_TARGET" "cd $(q "$webroot") && php tools/importExport.php NativeImportExportPlugin import $(q "$ops/issue-import.xml") worj $(q "$user") 2>&1 | grep -v tempnam | tail -12; rm -f $(q "$ops/issue-import.xml")"
fi
echo "done. Check the issue page and both article pages."
