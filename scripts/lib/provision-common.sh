# Helpers for scripts/provision-ubuntu.sh. Sourced, not executed.
# Rules: no helper ever takes a secret as an argument or prints a value; every change goes through chg/ensure_*,
# which in --check mode only print `WOULD: ...`; every ensure_* is idempotent (it compares before it writes).
# shellcheck shell=bash

CHECK=0
TOTAL_CHANGED=0
STAGE_CHANGED=0
VALUES=""   # non-secret NAME=VALUE lines for the templates (host names, paths, ports)

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
ok() { say "  ok: $*"; }
chg() { # description: record a change (or, in --check, a change that would happen)
  STAGE_CHANGED=$((STAGE_CHANGED + 1)); TOTAL_CHANGED=$((TOTAL_CHANGED + 1))
  if [ "$CHECK" = 1 ]; then say "  WOULD: $*"; else say "  changed: $*"; fi
}

# KEY=VALUE file reader that never executes anything and never prints a value
load_env() { # file
  local line k v
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '' | '#'*) continue ;; esac
    k="${line%%=*}"; v="${line#*=}"
    [[ "$k" =~ ^[A-Z][A-Z0-9_]*$ ]] || die "bad line in $1 (names are UPPER_CASE): ${k:0:20}"
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    printf -v "$k" '%s' "$v"
  done <"$1"
}
add_value() { VALUES+="$1=$2"$'\n'; }

gen_secret() { # bytes -> hex string on stdout (no pipe, so pipefail cannot trip)
  openssl rand -hex "$1"
}

ensure_dir() { # path mode owner:group
  local p="$1" m="$2" og="$3"
  if [ -d "$p" ] && [ "$(stat -c '%a %U:%G' "$p")" = "$m $og" ]; then return 0; fi
  chg "directory $p ($m $og)"
  [ "$CHECK" = 1 ] || { mkdir -p "$p"; chown "$og" "$p"; chmod "$m" "$p"; }
}

ensure_packages() { # package...
  local missing=() p
  for p in "$@"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
  [ "${#missing[@]}" -gt 0 ] || { ok "packages present"; return 0; }
  chg "install packages: ${missing[*]}"
  if [ "$CHECK" = 0 ]; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
  fi
}

# Render a template with $VALUES (plus extra NAME=VALUE lines on stdin of the caller via $2...) to a destination.
# Keeps one backup of a file it replaces: DEST.worj-bak (rollback: move it back).
ensure_rendered() { # template dest mode owner:group
  local tpl="$1" dest="$2" mode="$3" og="$4" res
  res="$(printf '%s' "$VALUES" | python3 -I "$ROOT/scripts/render-template.py" "$tpl" "$dest" --mode "$mode" --allow-unused --dry-run)" || die "could not render $tpl"
  if [ "$res" = unchanged ] && [ "$(stat -c '%U:%G' "$dest" 2>/dev/null)" = "$og" ]; then return 0; fi
  chg "write $dest"
  if [ "$CHECK" = 0 ]; then
    [ ! -f "$dest" ] || cp -p "$dest" "$dest.worj-bak"
    printf '%s' "$VALUES" | python3 -I "$ROOT/scripts/render-template.py" "$tpl" "$dest" --mode "$mode" --owner "${og%%:*}" --group "${og##*:}" --allow-unused >/dev/null
  fi
}

ensure_copy() { # source dest mode owner:group
  local src="$1" dest="$2" mode="$3" og="$4"
  if [ -f "$dest" ] && cmp -s "$src" "$dest" && [ "$(stat -c '%a %U:%G' "$dest")" = "$mode $og" ]; then return 0; fi
  chg "install $dest"
  if [ "$CHECK" = 0 ]; then
    [ ! -f "$dest" ] || cp -p "$dest" "$dest.worj-bak"
    install -m "$mode" -o "${og%%:*}" -g "${og##*:}" "$src" "$dest"
  fi
}

ensure_content() { # dest mode owner:group  (content on stdin)
  local dest="$1" mode="$2" og="$3" tmpf
  tmpf="$(mktemp)"; cat >"$tmpf"
  if [ -f "$dest" ] && cmp -s "$tmpf" "$dest" && [ "$(stat -c '%a %U:%G' "$dest")" = "$mode $og" ]; then rm -f "$tmpf"; return 0; fi
  chg "write $dest"
  if [ "$CHECK" = 0 ]; then
    [ ! -f "$dest" ] || cp -p "$dest" "$dest.worj-bak"
    install -m "$mode" -o "${og%%:*}" -g "${og##*:}" "$tmpf" "$dest"
  fi
  rm -f "$tmpf"
}

ensure_absent() { # path
  [ -e "$1" ] || [ -L "$1" ] || return 0
  chg "remove $1"
  [ "$CHECK" = 1 ] || rm -f "$1"
}

# services: real systemd normally; with --skip-services (chroot test) a test-only hook starts the daemon by hand
svc_ensure() { # name  (enable and start)
  if [ "${SKIP_SERVICES:-0}" = 1 ]; then
    say "  skipped (--skip-services): service $1"
    [ -z "${WORJ_SERVICE_HOOK:-}" ] || { [ "$CHECK" = 1 ] || "$WORJ_SERVICE_HOOK" start "$1"; }
    return 0
  fi
  if systemctl is-enabled --quiet "$1" 2>/dev/null && systemctl is-active --quiet "$1" 2>/dev/null; then return 0; fi
  chg "enable and start $1"
  [ "$CHECK" = 1 ] || systemctl enable --now "$1"
}
svc_reload() { # name
  [ "$STAGE_CHANGED" -gt 0 ] || return 0
  if [ "${SKIP_SERVICES:-0}" = 1 ]; then
    [ -z "${WORJ_SERVICE_HOOK:-}" ] || { [ "$CHECK" = 1 ] || "$WORJ_SERVICE_HOOK" reload "$1"; }
    return 0
  fi
  [ "$CHECK" = 1 ] || systemctl reload "$1" 2>/dev/null || systemctl restart "$1"
}
