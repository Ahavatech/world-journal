#!/usr/bin/env bash
# Administrator recovery: set a new password for an OJS user directly in the database. Run as root on the server
# (or against any database you can reach). It is the LAST-RESORT path when no administrator can log in and no
# break-glass administrator exists; docs/DEPLOY.md describes who holds that credential.
#
#   scripts/reset-ojs-admin-password.sh --config /var/www/worj/config.inc.php --username NAME [--defaults-file FILE] [--keep-must-change-off]
#
# Facts taken from the pinned OJS 3.5.0-6 source (checked in lib/pkp/classes/security/Validation.php):
#   hash     password_hash($password, PASSWORD_BCRYPT, ['cost' => 12])   (encryptCredentials, non-legacy)
#   verify   password_verify($password, $hash)                            (verifyPassword)
#   table    `users`, column `password`; `must_change_password` forces a change at the next login
# The new password is read from standard input, or prompted twice when stdin is a terminal; it is never taken from
# the command line, never printed, never logged. The hash goes to the database on standard input too, and the
# database connection uses the mysql client's own socket login as root, or --defaults-file (mode 600).
# Exit 1 if the user does not exist or the update did not change exactly one row.
set -euo pipefail
umask 077

config="" username="" defaults="" must_change=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --config) config="${2:?}"; shift 2 ;;
    --username) username="${2:?}"; shift 2 ;;
    --defaults-file) defaults="${2:?}"; shift 2 ;;
    --keep-must-change-off) must_change=0; shift ;;
    -h | --help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (the password is never taken from the command line)" >&2; exit 2 ;;
  esac
done
if [ -z "$config" ] || [ -z "$username" ]; then echo "usage: $0 --config FILE --username NAME [--defaults-file FILE]" >&2; exit 2; fi
[ -f "$config" ] || { echo "ERROR: config not found: $config" >&2; exit 2; }
case "$username" in *[!A-Za-z0-9._@-]* | "") echo "ERROR: the username may contain only letters, digits and . _ @ -" >&2; exit 2 ;; esac
case $- in *x*) echo "ERROR: refusing to run with xtrace on (it would print the password)" >&2; exit 2 ;; esac

dbname="$(sed -n 's/^name *= *\(.*\)$/\1/p' "$config" | tr -d '"'"'" | head -1)"
[ -n "$dbname" ] || { echo "ERROR: could not read the database name from $config" >&2; exit 2; }
case "$dbname" in *[!A-Za-z0-9_]*) echo "ERROR: unexpected characters in the database name" >&2; exit 2 ;; esac
my() { if [ -n "$defaults" ]; then mariadb --defaults-extra-file="$defaults" "$@"; else mariadb "$@"; fi; }

if [ -t 0 ]; then
  read -rsp "New password for $username: " pw1; echo >&2
  read -rsp "Again: " pw2; echo >&2
  [ "$pw1" = "$pw2" ] || { echo "ERROR: the passwords differ" >&2; exit 1; }
  password="$pw1"
else
  IFS= read -r password
fi
[ "${#password}" -ge 12 ] || { echo "ERROR: use at least 12 characters (a password manager is expected)" >&2; exit 1; }

exists="$(my -N -e "select count(*) from \`$dbname\`.users where username='$username'")"
[ "$exists" = 1 ] || { echo "ERROR: user '$username' not found (or not unique) in database $dbname" >&2; exit 1; }

# shellcheck disable=SC2016  # PHP code, not shell
php_code='$p = stream_get_contents(STDIN); echo password_hash($p, PASSWORD_BCRYPT, ["cost" => 12]);'
hash="$(printf '%s' "$password" | php -r "$php_code")"
case "$hash" in \$2y\$12\$*) ;; *) echo "ERROR: hashing failed" >&2; exit 1 ;; esac
unset password pw1 pw2
# the hash (characters $ . / A-Z a-z 0-9) goes to the server on standard input
changed="$(printf "UPDATE \`%s\`.users SET password='%s', must_change_password=%s WHERE username='%s'; SELECT ROW_COUNT();\n" "$dbname" "$hash" "$must_change" "$username" | my -N)"
unset hash
[ "$changed" = 1 ] || { echo "ERROR: expected to change exactly 1 row, changed $changed" >&2; exit 1; }
echo "password for '$username' reset (bcrypt, cost 12); must_change_password=$must_change"
