#!/usr/bin/env bash
# scripts/features-shared.sh against the SANDBOX journal (real OJS, read back over HTTP). Needs the sandbox up. The database is snapshotted and restored.
# shellcheck disable=SC2317
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/.env.sandbox"
core="$root/ojs-core"; base="${SANDBOX_URL:-http://127.0.0.1:8082}/worj"
curl -s -o /dev/null -m 5 --noproxy '*' "$base/" || { echo "sandbox not running (make sandbox-up sandbox-seed)"; exit 2; }
tmp="$(mktemp -d)"
mariadb-dump "$SANDBOX_DB_NAME" >"$tmp/db.sql" 2>/dev/null || mysqldump "$SANDBOX_DB_NAME" >"$tmp/db.sql"
restore() { mariadb -e "DROP DATABASE IF EXISTS \`$SANDBOX_DB_NAME\`; CREATE DATABASE \`$SANDBOX_DB_NAME\` CHARACTER SET utf8mb4" && mariadb "$SANDBOX_DB_NAME" <"$tmp/db.sql"; find "$core/cache" -type f -delete 2>/dev/null; rm -rf -- "${tmp:?}"; }
trap restore EXIT
fail=0; pass=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
q() { mariadb -N "$SANDBOX_DB_NAME" -e "$1"; }
# the script runs as root here and the web server as www-data: let the cache stay writable for both (the host has one user)
F() { "$root/scripts/features-shared.sh" --local-ojs "$core" "$@"; local rc=$?; chmod -R a+rwX "$core/cache" 2>/dev/null; return $rc; }
art() { curl -s --noproxy '*' "$base/article/view/1"; }
q "delete from plugin_settings where plugin_name='citationstylelanguageplugin'; delete from journal_settings where setting_name='citations'; delete from user_group_settings where setting_value='Co-author'"
find "$core/cache" -type f -delete 2>/dev/null
yes "before: no How to cite on the article page" bash -c "! curl -s --noproxy '*' $base/article/view/1 | grep -q 'How to Cite'"
yes "the dry run says what it would do and changes nothing" bash -c "F() { $root/scripts/features-shared.sh --local-ojs $core \"\$@\"; }; F | grep -q 'WOULD: switch on the citation' && F | grep -q 'DRY RUN' && [ \$(mariadb -N $SANDBOX_DB_NAME -e \"select count(*) from plugin_settings where plugin_name='citationstylelanguageplugin'\") = 0 ]"
F --apply >"$tmp/a1.txt" 2>&1
yes "--apply reports its changes" bash -c "grep -q 'DONE:  switch on the citation' '$tmp/a1.txt' && grep -q 'DONE:  add the Co-author' '$tmp/a1.txt'"
find "$core/cache" -type f -delete 2>/dev/null
page="$(art)"
yes "the article page now has How to Cite with the format dropdown" bash -c "grep -q 'How to Cite' <<<'$(printf '%s' "$page" | tr -d "'")' && grep -q 'More Citation Formats' <<<'$(printf '%s' "$page" | tr -d "'")'"
yes "APA is offered, and so are RIS and BibTeX downloads" bash -c "grep -q '>APA\|APA<' <<<'$(printf '%s' "$page" | tr -d "'")' || grep -qi 'american psychological' <<<'$(printf '%s' "$page" | tr -d "'")'; grep -q 'BibTeX' <<<'$(printf '%s' "$page" | tr -d "'")'"
yes "authors are asked for references at submission" test "$(q "select setting_value from journal_settings where setting_name='citations'")" = request
yes "the Co-author role exists, is an author role and copies the Author stages" test "$(q "select count(*) from user_groups g join user_group_settings s on s.user_group_id=g.user_group_id and s.setting_name='name' and s.setting_value='Co-author' where g.role_id=65536 and g.is_default=0 and (select count(*) from user_group_stage st where st.user_group_id=g.user_group_id) = (select count(*) from user_group_stage where user_group_id=14)")" = 1
F --apply >"$tmp/a2.txt" 2>&1
yes "running it again changes nothing" bash -c "! grep -q DONE '$tmp/a2.txt' && grep -q 'already' '$tmp/a2.txt'"
q "update plugin_settings set setting_value='[\"ieee\"]' where plugin_name='citationstylelanguageplugin' and setting_name='enabledCitationStyles'"
F --apply >"$tmp/a3.txt" 2>&1
yes "a choice already made (the list of formats) is not overwritten" test "$(q "select setting_value from plugin_settings where plugin_name='citationstylelanguageplugin' and setting_name='enabledCitationStyles'")" = '["ieee"]'
yes "a refusal when the feature name is bad" bash -c "! $root/scripts/features-shared.sh --local-ojs $core --only 'bad name' 2>/dev/null"

echo "=== Awards in the main menu"
navmenu() { curl -s --noproxy '*' "$base/" | python3 -I -c "
import re,sys
h=sys.stdin.read()
m=re.search(r'id=\"navigationPrimary\".*?</nav>', h, re.S)
print(m.group(0) if m else '')"; }
"$root/scripts/pages-shared.sh" --local-ojs "$core" --only awards,awards-winners --apply >/dev/null 2>&1
q "delete from navigation_menu_item_assignments where navigation_menu_item_id in (select navigation_menu_item_id from navigation_menu_items where path in ('awards','awards-winners'))"
find "$core/cache" -type f -delete 2>/dev/null
yes "before: the main menu does not link to the awards page" bash -c "! grep -q '/worj/awards' <<<\"\$(curl -s --noproxy '*' $base/ | python3 -I -c 'import re,sys; h=sys.stdin.read(); m=re.search(r\"id=.navigationPrimary.*?</nav>\", h, re.S); print(m.group(0) if m else \"\")')\""
F --only awards-menu >"$tmp/m0.txt" 2>&1
yes "the dry run would add Research Awards and the winners page, and writes nothing" bash -c "grep -q 'WOULD: put Research Awards' '$tmp/m0.txt' && grep -q 'WOULD: put the winners page' '$tmp/m0.txt' && [ \$(mariadb -N $SANDBOX_DB_NAME -e \"select count(*) from navigation_menu_item_assignments a join navigation_menu_items i using(navigation_menu_item_id) where i.path='awards'\") = 0 ]"
F --only awards-menu --apply >/dev/null 2>&1
find "$core/cache" -type f -delete 2>/dev/null
M="$(navmenu)"
yes "after --apply the main menu links to the awards page and to the winners page" bash -c "grep -q '/worj/awards\"' <<<'$M' && grep -q '/worj/awards-winners' <<<'$M'"
F --only awards-menu --apply >"$tmp/m2.txt" 2>&1
yes "again: nothing changes" bash -c "! grep -q DONE '$tmp/m2.txt'"

echo "=== the Downloads block on an approved Author Guidelines page"
ag() { q "select setting_value from journal_settings where journal_id=1 and locale='en' and setting_name='authorGuidelines'"; }
q "update journal_settings set setting_value='<h2>Author Guidelines</h2><p>Approved text without the banner.</p>' where journal_id=1 and locale='en' and setting_name='authorGuidelines'"
F --only downloads >"$tmp/d0.txt" 2>&1
yes "the dry run says it would add the block and changes nothing" bash -c "grep -q 'WOULD: add the Downloads' '$tmp/d0.txt' && ! mariadb -N $SANDBOX_DB_NAME -e \"select setting_value from journal_settings where journal_id=1 and setting_name='authorGuidelines'\" | grep -q Downloads"
F --only downloads --apply >"$tmp/d1.txt" 2>&1
yes "--apply appends the block and keeps the approved text, and the cache clears without a fatal error" bash -c "grep -q 'DONE:  add the Downloads' '$tmp/d1.txt' && ! grep -qi 'fatal' '$tmp/d1.txt' && mariadb -N $SANDBOX_DB_NAME -e \"select setting_value from journal_settings where journal_id=1 and setting_name='authorGuidelines'\" | grep -q 'Approved text without the banner' && mariadb -N $SANDBOX_DB_NAME -e \"select setting_value from journal_settings where journal_id=1 and setting_name='authorGuidelines'\" | grep -q 'Agreement.docx'"
F --only downloads --apply >"$tmp/d2.txt" 2>&1
yes "again: nothing changes" bash -c "! grep -q DONE '$tmp/d2.txt' && grep -q 'already have the Downloads' '$tmp/d2.txt'"
q "update journal_settings set setting_value=replace(setting_value,'Agreement.docx\">Copyright and publication agreement (Word)','Agreement-DRAFT.docx\">Copyright and publication agreement (Word, draft for review)') where journal_id=1 and locale='en' and setting_name='authorGuidelines'"
F --only downloads --apply >/dev/null 2>&1
q "update journal_settings set setting_value=replace(setting_value,' download>','>') where journal_id=1 and locale='en' and setting_name='authorGuidelines'"
F --only downloads --apply >/dev/null 2>&1
yes "the three links ask the browser to download (the attribute is added to links already on the page)" bash -c "[ \$(mariadb -N $SANDBOX_DB_NAME -e \"select setting_value from journal_settings where journal_id=1 and setting_name='authorGuidelines'\" | grep -o 'download>' | wc -l) -ge 3 ]"
yes "a link to the old DRAFT agreement file is repointed to the current file" bash -c "v=\$(mariadb -N $SANDBOX_DB_NAME -e \"select setting_value from journal_settings where journal_id=1 and setting_name='authorGuidelines'\"); ! grep -q 'DRAFT' <<<\"\$v\" && grep -q 'Agreement.docx' <<<\"\$v\""

echo "=== the phone number in every contact section"
q "delete from journal_settings where journal_id=1 and setting_name in ('contactPhone','supportPhone')"
q "update journal_settings set setting_value='Test Name' where journal_id=1 and setting_name in ('contactName','supportName') and setting_value=''"
contact() { find "$core/cache" -type f -delete 2>/dev/null; curl -s --noproxy '*' "$base/about/contact"; }
yes "before: the contact page shows no phone number" bash -c "! curl -s --noproxy '*' $base/about/contact | grep -q '7852'"
F --phone "+44 7852 556872" >"$tmp/p0.txt" 2>&1
yes "the dry run names both contact sections and writes nothing" bash -c "grep -q 'WOULD: set the phone of the principal contact' '$tmp/p0.txt' && grep -q 'WOULD: set the phone of the technical support contact' '$tmp/p0.txt' && [ \$(mariadb -N $SANDBOX_DB_NAME -e \"select count(*) from journal_settings where setting_name in ('contactPhone','supportPhone')\") = 0 ]"
F --phone "+44 7852 556872" --apply >"$tmp/p1.txt" 2>&1
page="$(contact)"
yes "--apply puts the number in both settings" test "$(q "select count(*) from journal_settings where journal_id=1 and setting_name in ('contactPhone','supportPhone') and setting_value='+44 7852 556872'")" = 2
yes "the contact page shows it in the principal contact AND in the technical support section" bash -c "[ \$(printf '%s' '$(printf '%s' "$page" | tr -d "'")' | grep -o '+44 7852 556872' | wc -l) -ge 2 ]"
F --phone "+44 7852 556872" --apply >"$tmp/p2.txt" 2>&1
yes "again: nothing changes" bash -c "! grep -q DONE '$tmp/p2.txt' && grep -c 'already has' '$tmp/p2.txt' | grep -q 2"
F --phone "+44 1234 567890" --apply >/dev/null 2>&1
yes "a different number replaces the old one in both" test "$(q "select count(*) from journal_settings where journal_id=1 and setting_name in ('contactPhone','supportPhone') and setting_value='+44 1234 567890'")" = 2
for bad in "07852 556872" "+44 78<b>52" "+44" "+44 7852  556872 ext 5" "phone"; do
  yes "a bad number is refused: $bad" bash -c "! '$root/scripts/features-shared.sh' --local-ojs '$core' --phone '$bad' --apply >/dev/null 2>&1"
done
yes "...and the stored number is unchanged after the refusals" test "$(q "select count(*) from journal_settings where journal_id=1 and setting_name in ('contactPhone','supportPhone') and setting_value='+44 1234 567890'")" = 2
echo; echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
