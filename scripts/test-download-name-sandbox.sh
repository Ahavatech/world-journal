#!/usr/bin/env bash
# The theme's rule for the name of a downloaded article file (WORJ_Vol_No_Year_Surname_Short-Title.pdf) against the SANDBOX journal, over HTTP.
#   scripts/test-download-name-sandbox.sh      needs the sandbox up (make sandbox-up sandbox-seed). The database is snapshotted and restored.
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
q() { mariadb --default-character-set=utf8mb4 -N "$SANDBOX_DB_NAME" -e "$1"; }
disp() { find "$core/cache" -type f -delete 2>/dev/null; curl -s -D - -o "$tmp/body.bin" --noproxy '*' "$base/article/download/$1/$1" | tr -d '\r' | sed -n 's/^[Cc]ontent-[Dd]isposition: //p'; }
fname() { disp "$1" | sed -n 's/^attachment;filename=\([^;]*\);.*/\1/p'; }

echo "=== the rule"
yes "a normal article: WORJ_Vol_No_Year_Surname_Title.pdf" test "$(fname 1)" = "WORJ_Vol1_No1_2000_Author_Sample-Article-1.pdf"
yes "another article gets its own name" test "$(fname 2)" = "WORJ_Vol1_No1_2000_Author_Sample-Article-2.pdf"
yes "the download is still the real PDF" bash -c "head -c 4 '$tmp/body.bin' | grep -q '%PDF'"
q "update publication_settings set setting_value='Évaluation de la sécurité: étude \"exploratoire\" <b>des</b> réseaux & systèmes d''information critiques pour les infrastructures numériques mondiales' where publication_id=1 and setting_name='title' and locale='en'"
n="$(fname 1)"
yes "accents are folded and markup and punctuation dropped (got $n)" bash -c "[[ '$n' == WORJ_Vol1_No1_2000_Author_Evaluation-de-la-securite-etude-exploratoire-des-reseaux* ]]"
yes "and the title part is cut at a word, so the name stays short" test "${#n}" -lt 110
q "update publication_settings set setting_value=concat('Bad', char(13), char(10), 'Set-Cookie: x=1 \";evil/../name') where publication_id=2 and setting_name='title' and locale='en'"
h="$(disp 2)"; n2="$(fname 2)"
yes "a hostile title (line break, header text, quote, slash) becomes plain letters and hyphens only" bash -c "[[ '$n2' =~ ^[A-Za-z0-9._-]+\\.pdf\$ ]]"
yes "and the response still has exactly one Content-Disposition line and no Set-Cookie" bash -c "[ \$(printf '%s\n' \"\$(cat <<'H'
$h
H
)\" | grep -c -i '^attachment') = 1 ] && ! curl -s -D - -o /dev/null --noproxy '*' $base/article/download/2/2 | grep -qi 'set-cookie: x=1'"
echo "=== things the rule must leave alone"
cat >"$tmp/fmt.php" <<'PHP'
<?php require 'tools/bootstrap.php';
echo app()->get('file')->formatFilename('journals/1/articles/1/abc123.pdf', 'My own file name'), "\n";
PHP
yes "outside a reader's download (no article download in progress) OJS names it as before" bash -c "cd '$core' && [ \"\$(php '$tmp/fmt.php' 2>/dev/null | tail -1)\" = 'My own file name.pdf' ]"
yes "the Preview link (the PDF viewer page) still works" test "$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' "$base/article/view/1/1")" = 200
echo; echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
