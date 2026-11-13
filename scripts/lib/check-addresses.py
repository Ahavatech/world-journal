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
used = {a: [] for a in sorted(allowed)}
privacy_found = None
doi_found = None
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
        if v in used and name in ("smtp_username", "default_envelope_sender"):
            used[v].append(f"config {name}")
    elif kind in ("journal", "site") or (kind == "user" and name == admin_user):
        ok = v in allowed
        print(("ok    " if ok else "FAIL  ") + f"{kind} {name} = {shown}")
        bad += 0 if ok else 1
        if v in used:
            used[v].append(f"{kind} {name}")
    elif kind == "text":
        privacy_found = (privacy_found or []) + [x for x in v.split(",") if x]
        print(f"INFO  {name} mentions: {shown}")
    elif kind == "plugin":
        doi_found = (doi_found or []) + [v]
        print(f"INFO  {name} = {shown}")
    elif kind == "user":
        if v not in allowed:
            print(f"WARN  user {name} has an outside address ({shown}): a person, not the site")
        else:
            print(f"ok    user {name} = {v}")
    elif kind == "authors":
        print(f"INFO  authors on file with distinct addresses: {v}")
# where each of the journal's five addresses is used (an alias that is used nowhere is a NOTE, not a failure: it may belong to a setting that does not exist yet)
for a in sorted(allowed):
    where = list(used[a])
    if a.startswith("privacy@") and privacy_found and a in privacy_found:
        where.append("the privacy statement")
    if a.startswith("doi@") and doi_found and a in doi_found:
        where.append("the Crossref depositor email")
    if where:
        print(f"USED  {a}: " + "; ".join(where))
    elif a.startswith("privacy@"):
        print(f"NOTE  {a}: not used yet (the privacy statement does not mention it; the client picks the privacy text)")
    elif a.startswith("doi@"):
        print(f"NOTE  {a}: not used yet (the Crossref depositor email is not set; DOIs are not set up, docs/DOI-SETUP.md)")
    else:
        print(f"NOTE  {a}: not used by any setting the site has")
if bad:
    print(f"RESULT: FAIL ({bad} address(es) outside the journal's own)")
    sys.exit(1)
print("RESULT: PASS")
