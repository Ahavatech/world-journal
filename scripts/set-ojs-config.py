#!/usr/bin/env python3
"""Edit keys of a live OJS config.inc.php in place, keeping comments, without leaking secrets.

  python3 -I scripts/set-ojs-config.py CONFIG [--generate-if-weak section.key ...] < settings

Settings arrive on STANDARD INPUT as `section.key=RAW VALUE` lines (the raw text goes after the
`=` exactly as it must appear in the file, quotes included), never on the command line.

  --generate-if-weak section.key   If the current value is empty, a @@TOKEN@@, the shipped public default
                                   salt, or shorter than 32 characters, replace it with a new random value
                                   from `secrets` (48 URL-safe characters). A value that is already strong is
                                   NEVER replaced: rotating api_key_secret would invalidate issued API tokens.

Why: the OJS CLI installer leaves `salt` at the public default `YouMustSetASecretKeyHere!!`, leaves
`api_key_secret` empty, rewrites `allowed_hosts` to [""] and blanks `time_zone` (found in Phase 4).
Output is one line per key: `ok` / `changed` / `generated`, key NAMES only, never a value.
The file is replaced atomically and keeps its mode and owner. Exit 1 on a missing section or key.
"""
import argparse
import os
import re
import secrets
import sys
import tempfile

SECTION = re.compile(r"^\[(\w+)\]\s*$")
DEFAULT_SALT = "YouMustSetASecretKeyHere!!"


def bare(value):
    return value.strip().strip("\"'")


def weak(value):
    v = bare(value)
    return v == "" or v.startswith("@@") or v == DEFAULT_SALT or len(v) < 32


def find(lines, section, key):
    cur = ""
    last_in_section = None
    for i, line in enumerate(lines):
        m = SECTION.match(line)
        if m:
            cur = m.group(1)
            if cur == section:
                last_in_section = i
            continue
        if cur == section:
            last_in_section = i
            if re.match(rf"^{re.escape(key)}\s*=", line):
                return i, last_in_section
    return None, last_in_section


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("config")
    ap.add_argument("--generate-if-weak", action="append", default=[])
    try:
        a = ap.parse_args()
    except SystemExit:
        return 2
    wanted = {}
    for n, line in enumerate(sys.stdin.read().splitlines(), 1):
        if not line.strip():
            continue
        if "=" not in line or "." not in line.split("=", 1)[0]:
            print(f"standard input line {n}: expected section.key=VALUE", file=sys.stderr)
            return 2
        k, v = line.split("=", 1)
        wanted[k.strip()] = v
    st = os.stat(a.config)
    lines = open(a.config, encoding="utf-8").read().split("\n")
    report, changed_any = [], False
    plan = [(k, v, False) for k, v in wanted.items()] + [(k, None, True) for k in a.generate_if_weak]
    for dotted, raw, gen in plan:
        section, key = dotted.split(".", 1)
        idx, last = find(lines, section, key)
        if gen:
            if idx is None:
                print(f"FAIL  {dotted}: key not found in the config", file=sys.stderr)
                return 1
            current = lines[idx].split("=", 1)[1]
            if not weak(current):
                report.append(f"ok         {dotted} (already strong, kept)")
                continue
            lines[idx] = f'{key} = "{secrets.token_urlsafe(48)}"'
            report.append(f"generated  {dotted}")
            changed_any = True
            continue
        new = f"{key} = {raw}"
        if idx is None:
            if last is None:
                print(f"FAIL  section [{section}] not found", file=sys.stderr)
                return 1
            lines.insert(last + 1, new)
            report.append(f"changed    {dotted} (added)")
            changed_any = True
        elif lines[idx].strip() == new.strip() or re.sub(r"\s+", "", lines[idx]) == re.sub(r"\s+", "", new):
            report.append(f"ok         {dotted}")
        else:
            lines[idx] = new
            report.append(f"changed    {dotted}")
            changed_any = True
    if changed_any:
        directory = os.path.dirname(os.path.abspath(a.config))
        fd, tmp = tempfile.mkstemp(dir=directory, prefix=".setcfg-")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write("\n".join(lines))
                f.flush()
                os.fsync(f.fileno())
            os.chown(tmp, st.st_uid, st.st_gid) if os.geteuid() == 0 else None
            os.chmod(tmp, st.st_mode & 0o7777)
            os.replace(tmp, a.config)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
    print("\n".join(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
