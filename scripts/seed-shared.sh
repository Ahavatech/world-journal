#!/usr/bin/env bash
# Put the journal and its PLACEHOLDER content on the not-yet-public test site, from YOUR machine, after
# scripts/install-shared.sh. This is what lets you see the site structured as it will launch, with placeholders.
#
#   scripts/seed-shared.sh [--env FILE] [--check] [--with-sample-issue] [--no-client-content]
#
# What it does (each part is create-only: it never overwrites text a person has edited):
#   1. refuses unless https://HOST is still CLOSED to crawlers (robots.txt Disallow: / and X-Robots-Tag: noindex)
#   2. creates the journal `worj`, activates the worj theme, three placeholder announcements, the placeholder texts in the
#      journal settings (about, privacy, guidelines, information, contact) through the admin REST API (Playwright, here)
#   3. copies scripts/import-pages.php and ojs/content/ to $REMOTE_ROOT/worj-ops (ABOVE the web root) and creates the
#      placeholder custom pages with php over ssh
#   4. --with-sample-issue: also imports the 3 fake sample articles (scripts/sample-issue.py), clearly marked fake
# By default the CLIENT'S OWN TEXT (ojs/client-content, received 2026-11-11) replaces the placeholder text where the client supplied some;
# every such page keeps a pending banner naming what is unconfirmed. --no-client-content seeds placeholders only.
# It logs in with the initial administrator password from the env file, so run it BEFORE `install-shared.sh --finish`.
# Needs here: node with playwright (the Claude sandbox has it; otherwise npm i playwright), python3, rsync, ssh.
# None of this content may stay at launch: `make check-placeholders-url` must be empty then (docs/LAUNCH-GATES.md).
# UNVERIFIED (not run on the host).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
envfile="$root/.env.shared"; check=0; sample=0; client=1
while [ $# -gt 0 ]; do
  case "$1" in
    --env) envfile="${2:-}"; shift 2 ;;
    --check) check=1; shift ;;
    --with-sample-issue) sample=1; shift ;;
    --no-client-content) client=0; shift ;;
    *) echo "usage: $0 [--env FILE] [--check] [--with-sample-issue] [--no-client-content]" >&2; exit 2 ;;
  esac
done
die() { echo "FAIL  $*" >&2; exit 1; }
ok() { echo "ok    $*"; }
chg() { if [ "$check" = 1 ]; then echo "WOULD: $*"; else echo "DO    $*"; fi; }
[ -f "$envfile" ] || die "env file not found: $envfile"
mode="$(stat -c '%a' "$envfile")"; [ $((8#$mode & 8#077)) -eq 0 ] || die "$envfile is readable by others (mode $mode): chmod 600 it"
get() { sed -n "s/^$1=//p" "$envfile" | sed -n 1p; }
for v in HOST SSH_TARGET SSH_PORT REMOTE_ROOT ADMIN_USERNAME ADMIN_PASSWORD; do
  val="$(get "$v")"; [ -n "$val" ] || die "$v is empty in $envfile (ADMIN_PASSWORD is removed by install-shared.sh --finish: seed BEFORE it)"
  case "$val" in *REPLACE*) die "$v still has a REPLACE_ placeholder in $envfile" ;; esac
  printf -v "$v" '%s' "$val"
done
SSH_KEY="$(get SSH_KEY)"
[[ "$HOST" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || die "HOST must be a plain lower-case host name"
[[ "$REMOTE_ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "REMOTE_ROOT must be an absolute path of plain characters"
webroot="$REMOTE_ROOT/public_html"; ops="$REMOTE_ROOT/worj-ops"
sshbase=("${WORJ_SSH:-ssh}" -p "$SSH_PORT" -o BatchMode=yes)
[ -z "$SSH_KEY" ] || sshbase+=(-i "$SSH_KEY")
remote() { "${sshbase[@]}" "$SSH_TARGET" "$@"; }
rsh=""; for a in "${sshbase[@]}"; do rsh="$rsh '$a'"; done
tmp="$(mktemp -d)"; chmod 700 "$tmp"; trap 'rm -rf -- "${tmp:?}"' EXIT

remote "test -f $(printf '%q' "$webroot/config.inc.php") && grep -q '^installed = On' $(printf '%q' "$webroot/config.inc.php")" || die "OJS is not installed on the host yet (scripts/install-shared.sh)"
ok "OJS is installed on the host"

# 1 and 2: the REST part. Credentials go in the environment of the node process only (never argv).
if [ "$check" = 1 ]; then
  chg "check that https://$HOST is closed to crawlers, then create the journal worj, the theme, the announcements and the placeholder texts"
else
  command -v node >/dev/null || die "node is needed here (Playwright drives the admin interface)"
  seed_node() { WORJ_CLIENT_CONTENT="$client" WORJ_TARGET=remote WORJ_URL="https://$HOST" WORJ_ADMIN_USER="$ADMIN_USERNAME" WORJ_ADMIN_PASSWORD="$ADMIN_PASSWORD" node "$root/scripts/sandbox-seed.js"; }
fi
if [ "$check" = 1 ]; then
  chg "copy scripts/import-pages.php and ojs/content/ to $ops, enable the Make a Submission block, create the placeholder pages there (create-only), then a second pass that sets the sidebar and the Awards card"
else
  # pass 1 creates the journal; then what needs the journal in the database; pass 2 applies the sidebar and the Awards card,
  # which are only switched on once the block plugin is enabled and the awards pages exist. Every part is create-only.
  seed_node | tee "$tmp/seed1.txt" || die "the journal seeding failed (the site must be closed to crawlers and the initial password still valid)"
  remote "cd $(printf '%q' "$webroot") && php" <"$root/scripts/lib/enable-block-plugin.php" || die "could not enable the block plugin on the host"
  remote "mkdir -p $(printf '%q' "$ops/scripts") $(printf '%q' "$ops/ojs")"
  rsync -a -e "$rsh" "$root/scripts/import-pages.php" "$SSH_TARGET:$ops/scripts/"
  rsync -a --delete -e "$rsh" "$root/ojs/content/" "$SSH_TARGET:$ops/ojs/content/"
  rsync -a --delete --exclude=source-v1.txt -e "$rsh" "$root/ojs/client-content/" "$SSH_TARGET:$ops/ojs/client-content/"
  remote "php $(printf '%q' "$ops/scripts/import-pages.php") --journal=worj --ojs=$(printf '%q' "$webroot")$([ "$client" = 1 ] && printf ' --client-content')" | tail -3
  seed_node | tee "$tmp/seed2.txt" || die "the second seeding pass failed"
  ! grep -q '^SIDEBAR_PENDING' "$tmp/seed2.txt" || die "the sidebar block is still not available after enabling it"
fi

# 4: the sample issue
if [ "$sample" = 1 ]; then
  chg "import the 3 fake sample articles (clearly marked fake), only if the journal has no issue yet"
  if [ "$check" = 0 ]; then
    n_issues="$(remote "cd $(printf '%q' "$webroot") && php" <"$root/scripts/lib/count-issues.php")" || die "could not count the issues on the host"
    if [ "${n_issues:-0}" -gt 0 ] 2>/dev/null; then ok "the journal already has $n_issues issue(s): the sample issue is not imported again"; sample=0; fi
  fi
  if [ "$check" = 0 ] && [ "$sample" = 1 ]; then
    [ -f "$root/ojs/fixtures/pdfs/sample-article-1.pdf" ] || python3 "$root/scripts/sample-issue.py" pdfs
    python3 "$root/scripts/sample-issue.py" xml "$tmp/issue.xml"
    rsync -a -e "$rsh" "$tmp/issue.xml" "$SSH_TARGET:$ops/issue.xml"
    remote "cd $(printf '%q' "$webroot") && php tools/importExport.php NativeImportExportPlugin import $(printf '%q' "$ops/issue.xml") worj $(printf '%q' "$ADMIN_USERNAME")" 2>&1 | grep -v tempnam | tail -5
    remote "rm -f $(printf '%q' "$ops/issue.xml")"
  fi
fi
echo "done. Next: look at the site, then scripts/install-shared.sh --finish"
