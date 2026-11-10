#!/usr/bin/env python3
"""Render a template that holds @@TOKEN@@ placeholders into a file, without leaking values.

  python3 -I scripts/render-template.py TEMPLATE OUTPUT [--mode 640] [--owner USER] [--group GROUP] < values

Values arrive on STANDARD INPUT as `NAME=VALUE` lines (the value is everything after the first `=`),
never on the command line: anything on argv is visible to every user in /proc/*/cmdline and ps. The
script prints only `changed` or `unchanged` and token NAMES (never values).

  - Fails (exit 1) if the template still has a token with no value, or if stdin names a token the
    template does not use (a typo would otherwise be silently ignored). Nothing is written then.
  - Writes atomically: a temporary file created with mode 600 in the destination directory, fsynced,
    chmod/chown, then os.replace. The output is never readable by others, even briefly.
  - If the output already has the same content and mode, it is left alone (`unchanged`).
Exit 2 for a usage error.
"""
import argparse
import grp
import os
import pwd
import re
import stat
import sys
import tempfile

TOKEN = re.compile(r"@@([A-Z][A-Z0-9_]*)@@")


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("template")
    ap.add_argument("output")
    ap.add_argument("--mode", default="640")
    ap.add_argument("--owner")
    ap.add_argument("--group")
    try:
        a = ap.parse_args()
    except SystemExit:
        return 2
    if "=" in a.template or "=" in a.output:
        print("usage: values go on standard input, not on the command line", file=sys.stderr)
        return 2
    values = {}
    for n, line in enumerate(sys.stdin.read().splitlines(), 1):
        if not line.strip():
            continue
        if "=" not in line:
            print(f"standard input line {n}: expected NAME=VALUE", file=sys.stderr)
            return 2
        name, value = line.split("=", 1)
        if not re.fullmatch(r"[A-Z][A-Z0-9_]*", name):
            print(f"standard input line {n}: bad token name", file=sys.stderr)
            return 2
        values[name] = value
    text = open(a.template, encoding="utf-8").read()
    used = set(TOKEN.findall(text))
    missing = sorted(used - set(values))
    unknown = sorted(set(values) - used)
    if missing or unknown:
        if missing:
            print("FAIL  no value for token(s): " + ", ".join(missing), file=sys.stderr)
        if unknown:
            print("FAIL  value given for token(s) the template does not use: " + ", ".join(unknown), file=sys.stderr)
        return 1
    out = TOKEN.sub(lambda m: values[m.group(1)], text)
    mode = int(a.mode, 8)
    same = False
    if os.path.exists(a.output):
        st = os.stat(a.output)
        with open(a.output, encoding="utf-8") as f:
            same = f.read() == out and stat.S_IMODE(st.st_mode) == mode
    if same and not (a.owner or a.group):
        print("unchanged")
        return 0
    directory = os.path.dirname(os.path.abspath(a.output))
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".render-")  # created with mode 600
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(out)
            f.flush()
            os.fsync(f.fileno())
        if a.owner or a.group:
            uid = pwd.getpwnam(a.owner).pw_uid if a.owner else -1
            gid = grp.getgrnam(a.group).gr_gid if a.group else -1
            os.chown(tmp, uid, gid)
        os.chmod(tmp, mode)
        os.replace(tmp, a.output)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    print("unchanged" if same else "changed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
