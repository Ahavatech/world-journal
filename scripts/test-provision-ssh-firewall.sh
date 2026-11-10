#!/usr/bin/env bash
# Tests the firewall and ssh stages of scripts/provision-ubuntu.sh with the REAL ufw (rules only, never enabled),
# the REAL sshd -t / sshd -T, and stubs for systemd and `ufw enable`. It also proves the 00- ordering.
#   scripts/test-provision-ssh-firewall.sh        needs root, openssh-server and ufw (apt-get install -y openssh-server ufw)
# NOT tested here (UNVERIFIED, not run on VPS): a real ufw enable, a real sshd reload, a real second login, systemd timers.
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 2; }
for t in sshd ufw ssh-keygen age-keygen useradd; do command -v "$t" >/dev/null || { echo "missing tool: $t"; exit 2; }; done
P="$root/scripts/provision-ubuntu.sh"
tmp="$(mktemp -d)"; chmod 755 "$tmp"; mkdir -p "$tmp/bin" "$tmp/state"
user="worjop$$"
made_hostkeys=0; [ -e /etc/ssh/ssh_host_ed25519_key ] || made_hostkeys=1
cp -p /etc/default/ufw "$tmp/ufw.default"
cleanup() {
  ufw --force reset >/dev/null 2>&1; cp -p "$tmp/ufw.default" /etc/default/ufw
  rm -f /etc/ssh/sshd_config.d/00-worj.conf* /etc/ssh/sshd_config.d/50-test-cloud-init.conf /etc/ssh/sshd_config.d/99-bad.conf
  [ "$made_hostkeys" = 0 ] || rm -f /etc/ssh/ssh_host_*
  userdel -r "$user" >/dev/null 2>&1
  rm -rf -- "${tmp:?}"
}
trap cleanup EXIT
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
no() { local name="$1"; shift; if "$@"; then bad "$name"; else ok "$name"; fi; }
eq() { [ "$1" = "$2" ]; }

# ---- stubs: systemctl, systemd-run, `ufw enable|disable` (everything else is the real ufw)
cat >"$tmp/bin/systemctl" <<STUB
#!/bin/sh
echo "systemctl \$*" >>"$tmp/state/systemctl.log"; exit 0
STUB
real_ufw="$(command -v ufw)"
cat >"$tmp/bin/ufw" <<STUB
#!/bin/sh
case "\$*" in
  *enable*) echo "ufw \$*" >>"$tmp/state/ufw-calls.log"; echo active >"$tmp/state/ufw-status"; exit 0 ;;
  *disable*) echo "ufw \$*" >>"$tmp/state/ufw-calls.log"; echo inactive >"$tmp/state/ufw-status"; exit 0 ;;
  status) if [ "\$(cat "$tmp/state/ufw-status" 2>/dev/null)" = active ]; then echo "Status: active"; else echo "Status: inactive"; fi; exit 0 ;;
esac
exec "$real_ufw" "\$@"
STUB
cat >"$tmp/deadman.sh" <<STUB
#!/bin/sh
echo "\$*" >>"$tmp/state/deadman.log"
case "\$1" in
  schedule) touch "$tmp/state/pending-\$2"; echo "\$4" >"$tmp/state/revert-\$2" ;;
  cancel) rm -f "$tmp/state/pending-\$2" ;;
  pending) [ -e "$tmp/state/pending-\$2" ] ;;
esac
STUB
chmod +x "$tmp/bin/"* "$tmp/deadman.sh"
export PATH="$tmp/bin:$PATH"
echo inactive >"$tmp/state/ufw-status"

# ---- an operator account with a real key
useradd -m -s /bin/bash -G sudo "$user"
install -d -m 700 -o "$user" -g "$user" "/home/$user/.ssh"
ssh-keygen -q -t ed25519 -N "" -f "$tmp/op_key" -C "worj-test-operator" >/dev/null
install -m 600 -o "$user" -g "$user" "$tmp/op_key.pub" "/home/$user/.ssh/authorized_keys"
mkdir -p /run/sshd; ssh-keygen -A >/dev/null 2>&1
printf 'Nov 10 09:00:00 host sshd[1]: Accepted publickey for %s from 203.0.113.5 port 5555 ssh2: ED25519 SHA256:abc\n' "$user" >"$tmp/auth-key.log"
printf 'Nov 10 09:00:00 host sshd[1]: Accepted password for %s from 203.0.113.5 port 5555 ssh2\n' "$user" >"$tmp/auth-password.log"

recipient="$(age-keygen 2>/dev/null | sed -n 's/^# public key: //p')"
printf 'ID=ubuntu\nVERSION_ID="24.04"\nVERSION="24.04.5 LTS (Noble Numbat)"\n' >"$tmp/os-release"
mkenv() { # extra NAME=VALUE overrides
  local f="$tmp/p.env"
  cat >"$f" <<CFG
HOST=journal.example.org
ALT_HOST=www.journal.example.org
TIME_ZONE=UTC
OPERATOR_USER=$user
ADMIN_USERNAME=journalops
ADMIN_EMAIL=ops@journal.example.org
ADMIN_PASSWORD=ADMIN-SENTINEL-71cd-xyz
CERT_METHOD=origin
SMTP_SERVER=smtp.mailer.example.org
SMTP_PORT=587
SMTP_AUTH=tls
SMTP_USERNAME=mailer-user
SMTP_PASSWORD=SMTP-SENTINEL-9f3a-qrs
AGE_RECIPIENT=$recipient
RCLONE_REMOTE=:local:$tmp/remote
WEBROOT=/var/www/worj-provision-test
FILES_DIR=/var/lib/worj-provision-test/files
CFG
  local kv k
  for kv in "$@"; do k="${kv%%=*}"; sed -i "/^$k=/d" "$f"; printf '%s\n' "$kv" >>"$f"; done
  chmod 600 "$f"
}
# run STAGE [env-vars for the run...] -- extra args
run() { # stage; uses $RUN_ENV (array) for extra environment
  env WORJ_OS_RELEASE="$tmp/os-release" WORJ_DEADMAN_HOOK="$tmp/deadman.sh" "${RUN_ENV[@]}" "$P" --env "$tmp/p.env" --os 24.04 --stage "$1" "${@:2}" >"$tmp/out.txt" 2>&1; echo $?
}
RUN_ENV=()
ssh_env() { RUN_ENV=(SUDO_USER="$user" WORJ_TEST_SSH_SESSION=1 WORJ_TEST_SSH_PORT=22 WORJ_AUTHLOG="$tmp/auth-key.log"); }
added() { ufw show added | grep '^ufw ' || true; }
mkenv

echo "=== firewall"
ssh_env
rc="$(run firewall --check)"
yes "--check exits 0 (exit $rc)" eq "$rc" 0
yes "--check prints the rules it WOULD add" grep -q 'WOULD: ufw allow 22/tcp' "$tmp/out.txt"
yes "--check added nothing" eq "$(added)" ""
rc="$(run firewall)"
yes "firewall stage runs (exit $rc)" eq "$rc" 0
yes "SSH is the FIRST rule added" eq "$(added | head -1)" "ufw allow 22/tcp"
yes "then 80 and 443" bash -c "ufw show added | grep -qx 'ufw allow 80/tcp' && ufw show added | grep -qx 'ufw allow 443/tcp'"
yes "ONLY ports 22, 80 and 443 are allowed (3 rules)" eq "$(added | wc -l)" 3
yes "default: deny incoming, allow outgoing" bash -c "grep -q 'DEFAULT_INPUT_POLICY=\"DROP\"' /etc/default/ufw && grep -q 'DEFAULT_OUTPUT_POLICY=\"ACCEPT\"' /etc/default/ufw"
yes "a $(grep -c . "$tmp/state/deadman.log")-entry safety timer was scheduled before enabling (10 minutes, disable command)" bash -c "grep -q '^schedule worj-firewall-revert 10 ' '$tmp/state/deadman.log' && grep -q 'ufw --force disable' '$tmp/state/revert-worj-firewall-revert'"
yes "the firewall was enabled (through the stub)" grep -q 'enable' "$tmp/state/ufw-calls.log"
yes "the output tells the operator to log in again and confirm" grep -q -- '--confirm-ssh' "$tmp/out.txt"
: >"$tmp/state/deadman.log"
rc="$(run firewall)"
yes "second run changes nothing (exit $rc)" bash -c "grep -q '^   -> unchanged' '$tmp/out.txt'"
yes "...and schedules no new timer" eq "$(grep -c schedule "$tmp/state/deadman.log")" 0
mkenv SSH_PORT=2222
ufw --force reset >/dev/null 2>&1; echo inactive >"$tmp/state/ufw-status"; : >"$tmp/state/ufw-calls.log"
rc="$(run firewall)"
yes "SSH_PORT differing from this session's port is REFUSED (exit $rc)" eq "$rc" 1
yes "...with a message about the port" grep -q 'this session is on port 22 but SSH_PORT is 2222' "$tmp/out.txt"
yes "...and the firewall was NOT enabled" test ! -s "$tmp/state/ufw-calls.log"
mkenv; ufw --force reset >/dev/null 2>&1; echo inactive >"$tmp/state/ufw-status"
mkenv FIREWALL_CLOUDFLARE_ONLY=yes; rm -f /etc/nginx/worj-cloudflare-realip.conf.test 2>/dev/null
cf=/etc/nginx/worj-cloudflare-realip.conf; had_cf=0; [ ! -e "$cf" ] || { had_cf=1; cp -p "$cf" "$tmp/cf.orig"; }
rm -f "$cf"
rc="$(run firewall)"
yes "FIREWALL_CLOUDFLARE_ONLY without the ranges file is REFUSED (exit $rc)" eq "$rc" 1
mkdir -p /etc/nginx
"$root/scripts/update-cloudflare-ips.sh" --out "$cf" --source "file://$root/scripts/fixtures/cloudflare/good" --test-cmd true --no-reload >/dev/null
mkenv; run firewall >/dev/null; mkenv FIREWALL_CLOUDFLARE_ONLY=yes
rc="$(run firewall)"
yes "switching to Cloudflare-only works (exit $rc)" eq "$rc" 0
yes "the open 80 and 443 rules were removed" bash -c "! ufw show added | grep -qxE 'ufw allow (80|443)/tcp'"
yes "80 and 443 are allowed only from Cloudflare ranges (IPv4 only: 15 ranges x 2 ports = 30 rules) and SSH stays open (22/tcp)" bash -c "[ \$(ufw show added | grep -c ' from ') = 30 ] && ufw show added | grep -qx 'ufw allow 22/tcp'"
if [ "$had_cf" = 1 ]; then cp -p "$tmp/cf.orig" "$cf"; else rm -f "$cf"; fi
mkenv; ufw --force reset >/dev/null 2>&1; echo inactive >"$tmp/state/ufw-status"

echo "=== ssh: preconditions are checked BEFORE any change"
dropin=/etc/ssh/sshd_config.d/00-worj.conf
refuse_ssh() { # name text
  local rc; rc="$(run ssh)"
  if [ "$rc" = 1 ] && grep -q -- "$2" "$tmp/out.txt" && [ ! -e "$dropin" ]; then ok "$1 -> refused, nothing written"; else bad "$1 (exit $rc, drop-in exists: $([ -e "$dropin" ] && echo yes || echo no))"; sed -n '1,3p' "$tmp/out.txt"; fi
}
ssh_env; RUN_ENV=(SUDO_USER="$user" WORJ_TEST_SSH_SESSION=1 WORJ_AUTHLOG="$tmp/auth-password.log")
refuse_ssh "only a PASSWORD login in the log" "Accepted publickey"
ssh_env; RUN_ENV=(SUDO_USER=someoneelse WORJ_TEST_SSH_SESSION=1 WORJ_AUTHLOG="$tmp/auth-key.log")
refuse_ssh "run by a different user" "through sudo"
RUN_ENV=(SUDO_USER="$user" WORJ_AUTHLOG="$tmp/auth-key.log")
refuse_ssh "not inside an ssh session" "not an ssh login session"
ssh_env
cp "/home/$user/.ssh/authorized_keys" "$tmp/keys.bak"; : >"/home/$user/.ssh/authorized_keys"
refuse_ssh "an EMPTY authorized_keys" "does not exist or is empty"
printf 'this is not a key\n' >"/home/$user/.ssh/authorized_keys"
refuse_ssh "authorized_keys without a valid key" "no valid public key"
install -m 600 -o "$user" -g "$user" "$tmp/keys.bak" "/home/$user/.ssh/authorized_keys"
chmod 777 "/home/$user/.ssh"
refuse_ssh "a world-writable .ssh directory" "must not be group or world writable"
chmod 700 "/home/$user/.ssh"
gpasswd -d "$user" sudo >/dev/null 2>&1
refuse_ssh "an operator without sudo (root login is about to be disabled)" "not in the sudo group"
usermod -aG sudo "$user"

echo "=== ssh: the change itself"
ssh_env
rc="$(run ssh --check)"
yes "--check exits 0 and writes nothing (exit $rc)" bash -c "[ '$rc' = 0 ] && [ ! -e $dropin ]"
printf 'PasswordAuthentication yes\nPermitRootLogin yes\n' >/etc/ssh/sshd_config.d/50-test-cloud-init.conf
: >"$tmp/state/deadman.log"
rc="$(run ssh)"
yes "the stage succeeds (exit $rc)" eq "$rc" 0
yes "the drop-in is named 00-worj.conf" test -f "$dropin"
eff="$(sshd -T 2>/dev/null)"
yes "sshd -t accepts it, and the EFFECTIVE setting is passwordauthentication no" grep -qx 'passwordauthentication no' <<<"$eff"
yes "...despite a later 50-*.conf that says PasswordAuthentication yes (the 00- prefix wins)" grep -qx 'permitrootlogin no' <<<"$eff"
yes "...keyboard-interactive off and publickey only" bash -c "grep -qx 'kbdinteractiveauthentication no' <<<'$eff' && grep -qx 'authenticationmethods publickey' <<<'$eff'"
mv "$dropin" /etc/ssh/sshd_config.d/99-worj.conf
yes "CONTROL: named 99- instead, the 50- file WINS and passwords stay on" bash -c "sshd -T 2>/dev/null | grep -qx 'passwordauthentication yes'"
mv /etc/ssh/sshd_config.d/99-worj.conf "$dropin"
yes "a 10-minute revert timer was scheduled before the reload" grep -q '^schedule worj-ssh-revert 10 ' "$tmp/state/deadman.log"
yes "the revert command removes the drop-in" grep -q "rm -f $dropin" "$tmp/state/revert-worj-ssh-revert"
yes "ssh was RELOADED, not restarted" bash -c "grep -q 'reload ssh' '$tmp/state/systemctl.log' && ! grep -q 'restart ssh' '$tmp/state/systemctl.log'"
yes "the output says: open a second terminal, then --confirm-ssh" grep -q 'SECOND terminal' "$tmp/out.txt"
rc="$(run ssh)"
yes "rerun while unconfirmed says PENDING and changes nothing (exit $rc)" bash -c "grep -q 'PENDING' '$tmp/out.txt' && grep -q '^   -> unchanged' '$tmp/out.txt'"

echo "      revert drill: the timer's command is executed as it would be after 10 minutes"
sh -c "$(cat "$tmp/state/revert-worj-ssh-revert")" >/dev/null 2>&1
yes "after the revert the drop-in is gone" test ! -e "$dropin"
yes "...and the remaining sshd configuration is still valid (sshd -t)" sshd -t
rc="$(run ssh)"; rm -f "$tmp/state/pending-worj-ssh-revert"
yes "after a revert the stage can apply again (exit $rc)" test -f "$dropin"

echo "=== --confirm-ssh"
: >"$tmp/state/deadman.log"
env WORJ_OS_RELEASE="$tmp/os-release" WORJ_DEADMAN_HOOK="$tmp/deadman.sh" "$P" --env "$tmp/p.env" --os 24.04 --confirm-ssh >"$tmp/out.txt" 2>&1; rc=$?
yes "--confirm-ssh succeeds (exit $rc)" eq "$rc" 0
yes "...and cancels BOTH safety timers" bash -c "grep -q 'cancel worj-ssh-revert' '$tmp/state/deadman.log' && grep -q 'cancel worj-firewall-revert' '$tmp/state/deadman.log'"
rc="$(run ssh)"
yes "afterwards the stage reports ssh already key-only and confirmed (exit $rc)" grep -q 'already key-only and confirmed' "$tmp/out.txt"

echo "=== a configuration sshd rejects is rolled back"
rm -f "$dropin"; rm -f "$tmp/state/pending-worj-ssh-revert"
printf 'NoSuchDirectoryXyz yes\n' >/etc/ssh/sshd_config.d/99-bad.conf
rc="$(run ssh)"
yes "sshd -t failure makes the stage fail (exit $rc)" eq "$rc" 1
yes "...the drop-in was removed again" test ! -e "$dropin"
yes "...and no safety timer was left pending" test ! -e "$tmp/state/pending-worj-ssh-revert"
rm -f /etc/ssh/sshd_config.d/99-bad.conf

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "$fail FAILED"; fi
exit "$fail"
