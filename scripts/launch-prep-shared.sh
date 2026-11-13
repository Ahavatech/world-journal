#!/usr/bin/env bash
# Launch preparation, from YOUR machine, in one safe pass: delete the fake sample content, hide what has no client text, and confirm or
# hold each of the client's pages. Without --apply it only prints WOULD: lines.
#
#   scripts/launch-prep-shared.sh [--env FILE] [--apply] [--minimal]
#        [--delete-sample] [--hide-unsupplied] [--hide-editorial-team] [--summary-from-about] [--contact-office] [--launch-without-issn]
#        [--licence-from-document] [--launch-without-publisher] [--drop-default-checklist]
#        [--approve ID,ID...] [--hold ID,ID...] [--drop-blanks] [--local-ojs DIR]
#
#   --delete-sample          the 3 placeholder announcements, the sample issue and its 3 fake articles (matched by their exact fake titles)
#   --hide-unsupplied        pages the client sent no text for: awards guidelines and categories, archiving, plagiarism-similarity, the
#                            three Information pages and sidebar block, the Awards card
#   --hide-editorial-team    the Editorial Team (menu entry and text), for a journal that has not supplied one
#   --licence-from-document  the journal licence = the one the addendum (ojs/client-content/addendum-*.txt) records; the footer links to it
#   --summary-from-about     the home page summary = the first paragraph of the client's About text (verbatim)
#   --contact-office         contact name "Editorial Office" (a role, not a person); the mailing address left empty
#   --launch-without-issn    the footer leaves the ISSN line out while the journal has none (theme option omitIssnLine)
#   --approve IDS            the client CONFIRMED these pages: take the pending banner off (refused while a marked blank is left)
#   --hold IDS               the client has NOT confirmed these: hide them until they do
#   --drop-blanks            with --approve: remove a paragraph that is only a marked blank (and the heading before it)
#   --launch-without-publisher  the footer leaves the publisher line out while the journal has no publisher name (theme option omitPublisherLine)
#   --drop-default-checklist OJS's shipped submission checklist (not the client's text) is emptied while it is still the shipped wording
#   --minimal                --delete-sample --hide-unsupplied --drop-default-checklist --summary-from-about --contact-office and --hold awards,awards-winners,announcement
#   --local-ojs DIR          run against an OJS tree on this machine instead of the host (tests)
# Client page ids: about editorial-team aims-and-scope privacy author-guidelines disclaimer open-access peer-review publication-ethics copyright-licensing
#   awards awards-winners announcement.
# A page or setting is touched ONLY while it still carries a placeholder: text a person wrote is never overwritten. Approving is YOUR
# statement that the client confirmed the page. UNVERIFIED (not run on the host) until you run it; run it without --apply first.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
envfile="$root/.env.shared"; apply=0; local_ojs=""
delete_sample=0; hide_unsupplied=0; hide_team=0; licence=0; nopub=0; dropcl=0; summary=0; contact=0; noissn=0; drop=0; approve=""; hold=""
while [ $# -gt 0 ]; do
  case "$1" in
    --env) envfile="${2:-}"; shift 2 ;;
    --apply) apply=1; shift ;;
    --minimal) delete_sample=1; hide_unsupplied=1; dropcl=1; summary=1; contact=1; hold="${hold:+$hold,}awards,awards-winners,announcement"; shift ;;
    --delete-sample) delete_sample=1; shift ;;
    --hide-unsupplied) hide_unsupplied=1; shift ;;
    --hide-editorial-team) hide_team=1; shift ;;
    --licence-from-document) licence=1; shift ;;
    --summary-from-about) summary=1; shift ;;
    --contact-office) contact=1; shift ;;
    --launch-without-issn) noissn=1; shift ;;
    --launch-without-publisher) nopub=1; shift ;;
    --drop-default-checklist) dropcl=1; shift ;;
    --approve) approve="${2:-}"; shift 2 ;;
    --hold) hold="${hold:+$hold,}${2:-}"; shift 2 ;;
    --drop-blanks) drop=1; shift ;;
    --local-ojs) local_ojs="${2:-}"; shift 2 ;;
    *) sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  esac
done
die() { echo "FAIL  $*" >&2; exit 1; }
ids_ok() { local l="$1" i; [ -z "$l" ] && return 0; for i in ${l//,/ }; do case "$i" in about|editorial-team|aims-and-scope|privacy|author-guidelines|disclaimer|open-access|peer-review|publication-ethics|copyright-licensing|awards|awards-winners|announcement) ;; *) die "'$i' is not one of the client's pages"; esac; done; }
ids_ok "$approve"; ids_ok "$hold"
for i in ${approve//,/ }; do case ",$hold," in *",$i,"*) die "'$i' is both approved and held" ;; esac; done
[ "$delete_sample$hide_unsupplied$hide_team$licence$summary$contact$noissn$nopub$dropcl" != "000000000" ] || [ -n "$approve$hold" ] || die "nothing to do: give --minimal, or any of the options (--help lists them)"

opts="$(python3 -I - "$root" "$apply" "$delete_sample" "$hide_unsupplied" "$summary" "$contact" "$noissn" "$drop" "$approve" "$hold" "$hide_team" "$licence" "$nopub" "$dropcl" <<'PY'
import base64, html, json, re, sys
root, apply, delete_sample, hide, summary, contact, noissn, drop, approve, hold, hide_team, licence, nopub, dropcl = sys.argv[1:15]
pages_json = json.load(open(f"{root}/ojs/content/pages.json"))["pages"]
cmap = json.load(open(f"{root}/ojs/client-content/map.json"))
by_id = {p["id"]: p for p in pages_json}
pages = {}
for c in cmap["pages"]:
    p = by_id[c["id"]]
    pages[c["id"]] = {"kind": "setting", "key": p["setting"]} if p["mechanism"] == "setting" else {"kind": "custom", "path": p["path"]}
pages["announcement"] = {"kind": "announcement", "title": cmap["announcement"]["title"]}
about = open(f"{root}/ojs/client-content/pages/about.html", encoding="utf-8").read()
first = next(re.finditer(r"<h2>About the Journal</h2>\s*<p>(.*?)</p>", about, re.S)).group(1)
licence_url = ""
if licence == "1":
    import glob
    add = open(sorted(glob.glob(f"{root}/ojs/client-content/addendum-*.txt"))[-1], encoding="utf-8").read()
    m = re.search(r"https://creativecommons\.org/licenses/[a-z-]+/[0-9.]+/", add)
    if not m:
        sys.exit("the addendum records no licence web address")
    licence_url = m.group(0)
o = {
    "journal": "worj", "apply": apply == "1", "pages": pages,
    "delete_sample": delete_sample == "1",
    "hide_pages": ["awards-guidelines", "awards-categories", "archiving", "plagiarism-similarity"] if hide == "1" else [],
    "hide_masthead": hide_team == "1", "hide_info": hide == "1", "awards_card_off": hide == "1",
    "licence_url": licence_url, "omit_publisher": nopub == "1", "drop_default_checklist": dropcl == "1",
    "default_wording": [l.strip() for l in open(f"{root}/scripts/ojs-default-wording.txt", encoding="utf-8") if l.strip() and not l.startswith("#")],
    "summary": ("<p>" + first + "</p>") if summary == "1" else "",
    "contact_office": contact == "1", "omit_issn": noissn == "1", "drop_blanks": drop == "1",
    "approve": [x for x in approve.split(",") if x], "hold": [x for x in hold.split(",") if x],
}
print(base64.b64encode(json.dumps(o).encode()).decode())
PY
)"
if [ -n "$local_ojs" ]; then
  [ -f "$local_ojs/tools/bootstrap.php" ] || die "no OJS at $local_ojs"
  (cd "$local_ojs" && php -- "$opts" <"$root/scripts/lib/launch-prep.php")
  exit $?
fi
[ -f "$envfile" ] || die "env file not found: $envfile"
mode="$(stat -c '%a' "$envfile")"; [ $((8#$mode & 8#077)) -eq 0 ] || die "$envfile is readable by others (mode $mode): chmod 600 it"
get() { sed -n "s/^$1=//p" "$envfile" | sed -n 1p; }
for v in SSH_TARGET SSH_PORT REMOTE_ROOT; do val="$(get "$v")"; [ -n "$val" ] || die "$v is empty in $envfile"; printf -v "$v" '%s' "$val"; done
SSH_KEY="$(get SSH_KEY)"
[[ "$REMOTE_ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "REMOTE_ROOT must be an absolute path of plain characters"
webroot="$REMOTE_ROOT/public_html"
sshbase=("${WORJ_SSH:-ssh}" -p "$SSH_PORT" -o BatchMode=yes)
[ -z "$SSH_KEY" ] || sshbase+=(-i "$SSH_KEY")
[ "$apply" = 1 ] && echo "APPLYING to the host" || echo "DRY RUN (nothing is written; add --apply to do it)"
"${sshbase[@]}" "$SSH_TARGET" "cd $(printf '%q' "$webroot") && php -- $(printf '%q' "$opts")" <"$root/scripts/lib/launch-prep.php"
