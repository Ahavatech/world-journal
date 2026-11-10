#!/usr/bin/env bash
# Negative tests for scripts/check-live-config.py: a good config passes, and each unsafe change must FAIL.
#   scripts/test-check-live-config.sh        exit 0 only if the good config passes and every mutation is caught
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp:?}"' EXIT
C=(python3 -I "$root/scripts/check-live-config.py")
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }

cat >"$tmp/good.inc.php" <<'CFG'
; <?php exit; // DO NOT DELETE?>
[general]
installed = On
app_key = "base64:abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGH"
base_url = "https://journal.example.org"
restful_urls = On
allowed_hosts = '["journal.example.org"]'
time_zone = "UTC"
[database]
username = worj
password = Zk4vQm9TnR2xLp7WcB5sYd8e
name = worj
[files]
files_dir = /var/lib/worj/files
[security]
force_ssl = On
force_login_ssl = On
salt = "k3Jf9sLx02QpVbn7TzR4wYhA81mCdEuGq9Ws5Xe7"
api_key_secret = "Vn3Tq8Lm0Rz5Xc2Bw7Yd4Hs9Je6Pk1Af8Ug3Ny5"
[schedule]
task_runner = Off
[queues]
process_jobs_at_task_scheduler = On
[debug]
show_stacktrace = Off
display_errors = Off
CFG
chmod 640 "$tmp/good.inc.php"
ARGS=(--host journal.example.org --web-root /var/www/worj)

out="$("${C[@]}" "$tmp/good.inc.php" "${ARGS[@]}" 2>&1)"; rc=$?
if [ "$rc" = 0 ]; then ok "good config passes (exit 0)"; else bad "good config failed"; echo "$out"; fi
if grep -qF -e "k3Jf9sLx02QpVbn7" -e "Vn3Tq8Lm0Rz5Xc2B" -e "Zk4vQm9TnR2xLp7W" <<<"$out"; then bad "a secret value was printed"; else ok "no secret value in the output"; fi

mutate() { # name sed-expression expected-key [extra args...]
  local name="$1" expr="$2" key="$3"; shift 3
  cp "$tmp/good.inc.php" "$tmp/m.inc.php"; chmod 640 "$tmp/m.inc.php"
  sed -i -E "$expr" "$tmp/m.inc.php"
  local o rc
  o="$("${C[@]}" "$tmp/m.inc.php" "${ARGS[@]}" "$@" 2>&1)"; rc=$?
  if [ "$rc" = 1 ] && grep -q "FAIL  $key" <<<"$o"; then ok "$name -> FAIL $key"; else bad "$name (exit $rc, wanted FAIL $key)"; echo "$o" | sed -n '1,4p'; fi
}

mutate "the shipped default salt (installer state)" 's/^salt = .*/salt = "YouMustSetASecretKeyHere!!"/' "security.salt"
mutate "a short salt" 's/^salt = .*/salt = "short"/' "security.salt"
mutate "an empty api_key_secret (installer state)" 's/^api_key_secret = .*/api_key_secret = ""/' "security.api_key_secret"
mutate "allowed_hosts rewritten to [\"\"] (installer state)" "s/^allowed_hosts = .*/allowed_hosts = '[\"\"]'/" "general.allowed_hosts"
mutate "allowed_hosts empty" "s/^allowed_hosts = .*/allowed_hosts = ''/" "general.allowed_hosts"
mutate "allowed_hosts without the production host" "s/^allowed_hosts = .*/allowed_hosts = '[\"other.example\"]'/" "general.allowed_hosts includes the host"
mutate "blank time_zone (installer state)" 's/^time_zone = .*/time_zone =/' "general.time_zone"
mutate "installed Off" 's/^installed = On/installed = Off/' "general.installed"
mutate "empty app_key" 's/^app_key = .*/app_key =/' "general.app_key"
mutate "force_ssl Off" 's/^force_ssl = On/force_ssl = Off/' "security.force_ssl"
mutate "plain http base_url" 's#^base_url = .*#base_url = "http://journal.example.org"#' "general.base_url"
mutate "the web task runner left On (quiet sites miss daily tasks)" 's/^task_runner = Off/task_runner = On/' "schedule.task_runner"
mutate "queued jobs not processed by the scheduler" 's/^process_jobs_at_task_scheduler = On/process_jobs_at_task_scheduler = Off/' "queues.process_jobs_at_task_scheduler"
mutate "restful_urls Off" 's/^restful_urls = On/restful_urls = Off/' "general.restful_urls"
mutate "show_stacktrace On" 's/^show_stacktrace = Off/show_stacktrace = On/' "debug.show_stacktrace"
mutate "files_dir inside the web root" 's#^files_dir = .*#files_dir = /var/www/worj/files#' "files.files_dir"
mutate "relative files_dir (shipped default)" 's#^files_dir = .*#files_dir = files#' "files.files_dir"
mutate "the shipped database password" 's/^password = .*/password = ojs/' "database.password"
mutate "a leftover token" 's/^name = worj/name = @@DB_NAME@@/' "no leftover tokens"

cp "$tmp/good.inc.php" "$tmp/m.inc.php"; chmod 644 "$tmp/m.inc.php"
o="$("${C[@]}" "$tmp/m.inc.php" "${ARGS[@]}" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -q "FAIL  file mode" <<<"$o"; then ok "a world-readable config (mode 644) -> FAIL file mode"; else bad "mode 644 not caught"; fi

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "$fail FAILED"; fi
exit "$fail"
