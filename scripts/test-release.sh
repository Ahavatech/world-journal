#!/usr/bin/env bash
# Tests for scripts/build-release.sh and scripts/deploy-shared.sh, on a tiny fake OJS tree (no network, no root).
# shellcheck disable=SC2317  # helper functions are called indirectly
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/ojs-version.env
source "$root/scripts/ojs-version.env"
tmp="$(mktemp -d)"; trap 'rm -rf -- "${tmp:?}"' EXIT
fail=0; pass=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
yes() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
no() { local name="$1"; shift; if "$@"; then bad "$name"; else ok "$name"; fi; }
has() { grep -qF -- "$2" <<<"$1"; }
lacks() { ! grep -qF -- "$2" <<<"$1"; }

ojs="$tmp/ojs"
mkdir -p "$ojs/lib/pkp/classes" "$ojs/cache/t" "$ojs/public/site" "$ojs/.github" "$ojs/plugins/themes/default" "$ojs/plugins/generic" "$ojs/tools"
echo "$OJS_VERSION" >"$ojs/.worj-ojs-version"
printf '<?php // front controller\n' >"$ojs/index.php"
printf 'secret' >"$ojs/config.inc.php"; printf 'x' >"$ojs/cache/t/c"; printf 'x' >"$ojs/public/site/u.jpg"; printf 'ci' >"$ojs/.github/ci.yml"
printf 'User-agent: *\nDisallow: /cache/\n' >"$ojs/robots.txt"; printf 'x' >"$ojs/lib/pkp/classes/a.php"; printf 'x' >"$ojs/plugins/themes/default/d.txt"
theme="$tmp/theme"; mkdir -p "$theme/assets"; printf 'theme' >"$theme/assets/a.css"
printf '<?xml version="1.0"?>\n<version>\n\t<release>9.9.9.0</release>\n</version>\n' >"$theme/version.xml"
ln -s "$theme" "$ojs/plugins/themes/worj"   # what make setup does
B() { "$root/scripts/build-release.sh" --ojs-dir "$ojs" --theme-dir "$theme" "$@"; }

echo "=== build"
B --host journal.example.org --robots-mode closed --out "$tmp/r1" >"$tmp/b1.txt" 2>&1; rc=$?
yes "the build succeeds (exit $rc)" test "$rc" = 0
p="$tmp/r1/public_html"
yes "the OJS front controller is in the package" test -f "$p/index.php"
yes "the theme is a real copy, not a symlink" test -f "$p/plugins/themes/worj/assets/a.css" -a ! -L "$p/plugins/themes/worj"
yes "config.inc.php is not in the package" test ! -e "$p/config.inc.php"
yes "public/ and cache/ are not in the package" test ! -e "$p/public" -a ! -e "$p/cache"
yes ".github (developer files) is not in the package" test ! -e "$p/.github"
yes "the .htaccess is rendered with the host and no token" bash -c "grep -q 'https://journal.example.org' '$p/.htaccess' && ! grep -q '@@' '$p/.htaccess'"
yes "robots.txt is the closed one" grep -qx 'Disallow: /' "$p/robots.txt"
yes "the static 404 page is in the package" test -f "$p/_errors/404.html"
yes "RELEASE.txt names OJS and theme versions" bash -c "grep -qx 'ojs_version=$OJS_VERSION' '$tmp/r1/RELEASE.txt' && grep -qx 'theme_version=9.9.9.0' '$tmp/r1/RELEASE.txt'"
yes "the manifest verifies" bash -c "cd '$p' && sha256sum --quiet -c '$tmp/r1/MANIFEST.sha256'"
B --host journal.example.org --robots-mode closed --out "$tmp/r1b" >/dev/null 2>&1
yes "building twice gives the same manifest" cmp -s "$tmp/r1/MANIFEST.sha256" "$tmp/r1b/MANIFEST.sha256"
B --host journal.example.org --robots-mode production --out "$tmp/r2" >/dev/null 2>&1
yes "production mode: robots.txt has the sitemap line" grep -q 'Sitemap: https://journal.example.org/index/sitemap' "$tmp/r2/public_html/robots.txt"

echo "=== refusals"
no "a non-empty output directory is refused" B --host journal.example.org --robots-mode closed --out "$tmp/r1"
echo wrong >"$tmp/ojs/.worj-ojs-version"
no "a tree that is not the pinned OJS version is refused" B --host journal.example.org --robots-mode closed --out "$tmp/r3"
echo "$OJS_VERSION" >"$tmp/ojs/.worj-ojs-version"
no "an unknown robots mode is refused (no default)" B --host journal.example.org --robots-mode staging --out "$tmp/r4"
no "a missing robots mode is refused" B --host journal.example.org --out "$tmp/r5"
no "a host with a path is refused" B --host 'journal.example.org/x' --robots-mode closed --out "$tmp/r6"
no "an upper-case or spaced host is refused" B --host 'Journal Example' --robots-mode closed --out "$tmp/r7"
printf 'KEY=1' >"$ojs/.env"
no "a .env file in the OJS tree is refused" B --host journal.example.org --robots-mode closed --out "$tmp/r8"
rm -f "$ojs/.env"
mkdir -p "$ojs/content"
no "a content/ directory in the package is refused" B --host journal.example.org --robots-mode closed --out "$tmp/r9"
rmdir "$ojs/content"

echo "=== deploy"
D() { "$root/scripts/deploy-shared.sh" "$@"; }
t="$tmp/host"; mkdir -p "$t/public/site" "$t/cache" "$t/.well-known" "$t/cgi-bin"
printf 'live secret' >"$t/config.inc.php"; printf 'upload' >"$t/public/site/u.jpg"; printf 'cc' >"$t/cache/c"; printf 'acme' >"$t/.well-known/x"; printf 'cgi' >"$t/cgi-bin/x"
printf 'stale' >"$t/old-ojs-file.php"
before="$(cd "$t" && find . -type f | LC_ALL=C sort | xargs sha256sum | sha256sum)"
D --release "$tmp/r1" --target "$t" --check >"$tmp/c1.txt" 2>&1; rc=$?
yes "--check exits 0 (exit $rc)" test "$rc" = 0
yes "--check prints WOULD lines" grep -q '^WOULD: ' "$tmp/c1.txt"
yes "--check changed nothing on the host" test "$before" = "$(cd "$t" && find . -type f | LC_ALL=C sort | xargs sha256sum | sha256sum)"
D --release "$tmp/r1" --target "$t" >"$tmp/d1.txt" 2>&1; rc=$?
yes "the deploy succeeds (exit $rc)" test "$rc" = 0
survive() { # a host that keeps what is the host's
  [ "$(cat "$t/config.inc.php")" = "live secret" ] && [ "$(cat "$t/public/site/u.jpg")" = upload ] && [ -f "$t/cache/c" ] && [ -f "$t/.well-known/x" ] && [ -f "$t/cgi-bin/x" ]
}
yes "config.inc.php, public/, cache/, .well-known/ and cgi-bin/ survive the deploy" survive
yes "the package arrived (index.php, theme, .htaccess)" test -f "$t/index.php" -a -f "$t/plugins/themes/worj/assets/a.css" -a -f "$t/.htaccess"
yes "a stale file from an earlier release is removed" test ! -e "$t/old-ojs-file.php"
D --release "$tmp/r1" --target "$t" --check >"$tmp/c2.txt" 2>&1
yes "a second --check shows nothing to change" grep -q '^WOULD: 0 item' "$tmp/c2.txt"
yes "no secret value reached the output" bash -c "! grep -q 'live secret' '$tmp/d1.txt' '$tmp/c1.txt'"

echo "=== deploy refusals"
cp -r "$tmp/r1" "$tmp/r1x"; printf 'tampered' >>"$tmp/r1x/public_html/index.php"
no "a package that does not match its manifest is refused" D --release "$tmp/r1x" --target "$tmp/host2"
yes "...and nothing was sent" test ! -e "$tmp/host2"
cp -r "$tmp/r1" "$tmp/r1y"; printf 'x' >"$tmp/r1y/public_html/config.inc.php"
no "a package containing config.inc.php is refused" D --release "$tmp/r1y" --target "$tmp/host3"
no "a directory that is not a package is refused" D --release "$tmp" --target "$tmp/host4"
no "no target is a usage error" D --release "$tmp/r1"

echo "=== deploy over a (stub) ssh"
cat >"$tmp/stub-ssh" <<'STUB'
#!/usr/bin/env bash
# a stand-in for ssh: records its options, drops the host and runs the remote command locally
printf '%s\n' "$@" >>"${STUB_LOG:?}"
while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do case "$1" in -p|-i|-o) shift 2 ;; *) shift ;; esac; done
shift
exec "$@"
STUB
chmod +x "$tmp/stub-ssh"
t2="$tmp/host5"; mkdir -p "$t2"
STUB_LOG="$tmp/ssh.log" WORJ_SSH="$tmp/stub-ssh" D --release "$tmp/r1" --target "fake.invalid:$t2" --ssh-arg -p --ssh-arg 2222 --ssh-arg -i --ssh-arg "$tmp/key with space" >"$tmp/d2.txt" 2>&1; rc=$?
yes "a deploy through ssh works (exit $rc)" test "$rc" = 0 -a -f "$t2/index.php" -a -f "$t2/.htaccess"
yes "the ssh options reached ssh (port, key path with a space)" bash -c "grep -qx 2222 '$tmp/ssh.log' && grep -qxF '$tmp/key with space' '$tmp/ssh.log'"

echo "=== mutation proof: the deploy excludes protect the host's files"
for ex in /config.inc.php /public/ /cache/ /.well-known/ /cgi-bin/; do
  sed "s# --exclude=${ex}##" "$root/scripts/deploy-shared.sh" >"$tmp/deploy-mut.sh"; chmod +x "$tmp/deploy-mut.sh"
  if cmp -s "$tmp/deploy-mut.sh" "$root/scripts/deploy-shared.sh"; then bad "mutation $ex: exclude not found in the script"; continue; fi
  t3="$tmp/host-mut"; rm -rf "$t3"; mkdir -p "$t3/public/site" "$t3/cache" "$t3/.well-known" "$t3/cgi-bin"
  printf 'live secret' >"$t3/config.inc.php"; printf 'upload' >"$t3/public/site/u.jpg"; printf 'cc' >"$t3/cache/c"; printf 'acme' >"$t3/.well-known/x"; printf 'cgi' >"$t3/cgi-bin/x"
  "$tmp/deploy-mut.sh" --release "$tmp/r1" --target "$t3" >/dev/null 2>&1
  case "$ex" in /config.inc.php) f="$t3/config.inc.php" ;; /public/) f="$t3/public/site/u.jpg" ;; /cache/) f="$t3/cache/c" ;; /.well-known/) f="$t3/.well-known/x" ;; *) f="$t3/cgi-bin/x" ;; esac
  if [ -f "$f" ]; then bad "mutation $ex: the host file survived without the exclude"; else ok "mutation $ex: without the exclude the host file is lost (so the exclude is what protects it)"; fi
done
# shellcheck disable=SC2016  # literal text to replace
sed 's#sha256sum --quiet -c "\$release/MANIFEST.sha256"#true#' "$root/scripts/deploy-shared.sh" >"$tmp/deploy-mut.sh"; chmod +x "$tmp/deploy-mut.sh"
yes "mutation manifest check: without it the tampered package is sent" bash -c "'$tmp/deploy-mut.sh' --release '$tmp/r1x' --target '$tmp/host6' >/dev/null 2>&1 && [ -f '$tmp/host6/index.php' ]"

echo "$pass PASS, $fail FAIL"
exit "$fail"
