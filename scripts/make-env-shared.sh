#!/usr/bin/env bash
# Ask for the settings of scripts/install-shared.sh one by one and write .env.shared (mode 600). Passwords are typed
# hidden and never echoed, printed or put on a command line. Nothing is written until every answer is in.
#
#   scripts/make-env-shared.sh [--out FILE]        default: .env.shared (refuses to overwrite an existing file)
#
# Fixed answers for this project (host, SSH login, SMTP server) are filled in; you give the rest.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/.env.shared"
[ "${1:-}" != "--out" ] || { out="${2:?}"; }
[ ! -e "$out" ] || { echo "REFUSED: $out already exists (delete or rename it first)" >&2; exit 1; }
umask 077
ask() { # var prompt [default]  (visible)
  local v="$1" p="$2" d="${3:-}" a=""
  while :; do
    if [ -n "$d" ]; then read -r -p "$p [$d]: " a; a="${a:-$d}"; else read -r -p "$p: " a; fi
    [ -n "$a" ] || { echo "  (required)"; continue; }
    case "$a" in *[[:space:]]*) echo "  (no spaces)"; continue ;; esac
    printf -v "$v" '%s' "$a"; return
  done
}
askpw() { # var prompt [minlen]  (hidden, typed twice)
  local v="$1" p="$2" min="${3:-1}" a="" b=""
  while :; do
    read -r -s -p "$p (hidden): " a; echo
    [ "${#a}" -ge "$min" ] || { echo "  (at least $min characters)"; continue; }
    case "$a" in *[[:space:]]* | *\'* | *\"*) echo "  (no spaces or quotes)"; continue ;; esac
    read -r -s -p "  again: " b; echo
    [ "$a" = "$b" ] || { echo "  (they differ)"; continue; }
    printf -v "$v" '%s' "$a"; return
  done
}
echo "Writing $out. Press Ctrl+C to stop; nothing is saved until the end."
ask HOST "Site host" worldopenresearchjournal.com
ask TIME_ZONE "Time zone (IANA name)" Europe/London
ask SSH_TARGET "SSH login" u896415912@145.14.152.95
ask SSH_PORT "SSH port" 65002
ask SSH_KEY "Path of your private SSH key" "$HOME/.ssh/key"
ask REMOTE_ROOT "Domain folder on the host" /home/u896415912/domains/worldopenresearchjournal.com
ask DB_NAME "Database name (full, with the u896415912_ prefix, from hPanel)"
ask DB_USER "Database user (full, from hPanel)"
askpw DB_PASSWORD "Database password"
ask ADMIN_USERNAME "First administrator username (not 'admin')"
ask ADMIN_EMAIL "Administrator email (an address you control)"
askpw ADMIN_PASSWORD "Administrator password" 12
ask SMTP_SERVER "SMTP server" smtp.hostinger.com
ask SMTP_PORT "SMTP port" 465
ask SMTP_AUTH "SMTP encryption (ssl or tls)" ssl
ask SMTP_USERNAME "Mailbox address" editorial@worldopenresearchjournal.com
askpw SMTP_PASSWORD "Mailbox password"
{
  for k in HOST TIME_ZONE SSH_TARGET SSH_PORT SSH_KEY REMOTE_ROOT DB_NAME DB_USER DB_PASSWORD ADMIN_USERNAME ADMIN_EMAIL ADMIN_PASSWORD SMTP_SERVER SMTP_PORT SMTP_AUTH SMTP_USERNAME SMTP_PASSWORD; do
    printf '%s=%s\n' "$k" "${!k}"
  done
} >"$out"
chmod 600 "$out"
echo "Written: $out (mode 600). Secrets are in it: never commit it or paste it anywhere."
