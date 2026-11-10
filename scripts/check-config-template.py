#!/usr/bin/env python3
"""Lint ojs/config/config.inc.php.template against the shipped OJS config.

  python3 -I scripts/check-config-template.py [--template FILE] [--keys FILE] [--pin VERSION]

Fails (exit 1) on:
  unknown key       a key that the shipped config.TEMPLATE.inc.php does not have (typo, or removed by an OJS upgrade)
  missing key       an ACTIVE key of the shipped template that our template lacks
  salt, api secret  `security.salt` and `security.api_key_secret` must be the @@TOKEN@@ (never empty: provisioning generates them)
  secret            a secret-bearing key (app_key, salt, api_key_secret, database password, smtp_password,
                    recaptcha_private_key, altcha_hmackey) holding anything but an empty value or an @@TOKEN@@,
                    or ANY active value that looks like a real secret (long random string, base64: key)
  installed         `installed` is not Off (it stays Off until the install has run)
  pin               the template was generated for a different OJS version than scripts/ojs-version.env
                    (re-run scripts/make-config-template.py after every pin change)
The shipped key list is scripts/ojs-config-keys.txt (generated from ojs-core, so this runs in CI without it).
"""
import argparse
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SECTION = re.compile(r"^\[(\w+)\]")
ACTIVE = re.compile(r"^([A-Za-z_][\w.\[\]]*)\s*=\s*(.*)$")
COMMENTED = re.compile(r"^;\s*([a-z][a-z0-9_]*)\s*=\s*(.*)$")
TOKEN = re.compile(r"^[\"']?@@[A-Z0-9_]+@@[\"']?$|^'\[\"@@[A-Z0-9_]+@@\"\]'$")
SECRET_KEYS = {"general.app_key", "security.salt", "security.api_key_secret", "database.password",
               "email.smtp_password", "captcha.recaptcha_private_key", "captcha.altcha_hmackey"}
MUST_BE_TOKEN = {"security.salt", "security.api_key_secret"}
KNOWN_PLACEHOLDER = re.compile(r"your_(public|private)_key|Example key|YouMustSetASecretKeyHere", re.I)


def entropy(s):
    return -sum(s.count(c) / len(s) * math.log2(s.count(c) / len(s)) for c in set(s)) if s else 0


def looks_secret(value):
    v = value.strip().strip("\"'")
    if v.startswith("base64:") and len(v) > 20:
        return True
    # lists such as allowed_html contain , [ | and are not secrets
    return len(v) >= 20 and not v.startswith(("/", "http", "[", "@@")) and not any(c in v for c in " ,[|") and entropy(v) > 3.5


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--template", default=str(ROOT / "ojs/config/config.inc.php.template"))
    ap.add_argument("--keys", default=str(ROOT / "scripts/ojs-config-keys.txt"))
    ap.add_argument("--pin")
    a = ap.parse_args()
    template, keysfile = Path(a.template), Path(a.keys)
    if not template.exists() or not keysfile.exists():
        print(f"missing file: {template if not template.exists() else keysfile}")
        return 1
    shipped_active, shipped_all = set(), set()
    for line in keysfile.read_text().splitlines():
        if line and not line.startswith("#"):
            k, kind = line.split("\t")
            shipped_all.add(k)
            if kind == "active":
                shipped_active.add(k)
    pin = a.pin
    if pin is None:
        for line in (ROOT / "scripts/ojs-version.env").read_text().splitlines():
            if line.startswith("OJS_VERSION="):
                pin = line.split("=", 1)[1].strip().strip('"')
    problems, present, section = [], {}, ""
    lines = template.read_text().splitlines()
    for n, line in enumerate(lines, 1):
        m = SECTION.match(line)
        if m:
            section = m.group(1)
            continue
        ac, co = ACTIVE.match(line), COMMENTED.match(line)
        if ac:
            key, value = f"{section}.{ac.group(1)}", ac.group(2).strip()
            present[key] = (n, value)
            if key not in shipped_all:
                problems.append(f"line {n}: unknown key `{key}` (not in the shipped config template)")
        elif co and f"{section}.{co.group(1)}" not in shipped_all:
            problems.append(f"line {n}: unknown commented key `{section}.{co.group(1)}`")
    for key in sorted(shipped_active):
        if key not in present:
            problems.append(f"missing required key `{key}` (active in the shipped template)")
    for key, (n, value) in present.items():
        bare = value.strip().strip("\"'")
        if key in MUST_BE_TOKEN and not TOKEN.match(value):
            problems.append(f"line {n}: `{key}` must be the @@TOKEN@@ that provisioning replaces with a generated value (empty or literal is not allowed: the installer leaves the shipped default salt and an empty API secret)")
        elif key in SECRET_KEYS:
            if bare and not TOKEN.match(value) or KNOWN_PLACEHOLDER.search(value):
                problems.append(f"line {n}: `{key}` must be empty or an @@TOKEN@@ filled at provisioning, not a literal value")
        elif looks_secret(value) and not TOKEN.match(value):
            problems.append(f"line {n}: `{key}` has a real-looking secret value (use an @@TOKEN@@ filled at provisioning)")
    inst = present.get("general.installed")
    if inst is None or inst[1].strip().lower() != "off":
        problems.append("`general.installed` must be Off in the template (the installer sets On)")
    head = "\n".join(lines[:12])
    mver = re.search(r"for OJS ([0-9][\w.\-]*)", head)
    if not mver or mver.group(1) != pin:
        problems.append(f"template was generated for OJS {mver.group(1) if mver else '?'} but the pin is {pin}: re-run scripts/make-config-template.py and review the diff")
    if not lines or "<?php exit;" not in lines[0]:
        problems.append("the first line must be the shipped `; <?php exit; // DO NOT DELETE?>` guard")
    for p in problems:
        print("FAIL  " + p)
    print(f"config template lint: {len(present)} active keys checked, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
