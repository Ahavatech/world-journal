#!/usr/bin/env python3
"""Evaluate the output of scripts/lib/email-addresses.php (`kind|name|value` lines on stdin).

  python3 -I scripts/lib/check-addresses.py HOST ADMIN_USERNAME < audit-output

Exit 0 only if every address the SITE uses is one of the journal's own (editorial, support, privacy, doi, admin at HOST) and the
mail settings in config.inc.php force the mailbox as sender. Ordinary users with outside addresses are warned about, not failed.
"""
import sys

host, admin_user = sys.argv[1], sys.argv[2]
allowed = {f"{n}@{host}" for n in ("editorial", "support", "privacy", "doi", "admin")}
bad = 0
for line in sys.stdin.read().splitlines():
    kind, name, value = (line.split("|", 2) + ["", ""])[:3]
    v = value.strip()
    shown = v if v else "(empty)"
    if kind == "config":
        if name in ("smtp_username", "default_envelope_sender"):
            ok = v in allowed
        elif name in ("force_default_envelope_sender", "force_dmarc_compliant_from"):
            ok = v.lower() == "on"
        else:
            ok = True
        print(("ok    " if ok else "FAIL  ") + f"config {name} = {shown}")
        bad += 0 if ok else 1
    elif kind in ("journal", "site") or (kind == "user" and name == admin_user):
        ok = v in allowed
        print(("ok    " if ok else "FAIL  ") + f"{kind} {name} = {shown}")
        bad += 0 if ok else 1
    elif kind == "user":
        if v not in allowed:
            print(f"WARN  user {name} has an outside address ({shown}): a person, not the site")
        else:
            print(f"ok    user {name} = {v}")
    elif kind == "authors":
        print(f"INFO  authors on file with distinct addresses: {v}")
if bad:
    print(f"RESULT: FAIL ({bad} address(es) outside the journal's own)")
    sys.exit(1)
print("RESULT: PASS")
