#!/usr/bin/env python3
"""Pre-flight checks for an OJS XML import (called by scripts/import-ojs-xml.sh).

  python3 -I scripts/import-precheck.py --kind users|native --file FILE --base-url URL [--manifest FILE]

Exit 0 ok, 2 the file is not well-formed XML, 3 REFUSED: the target is not localhost and
the file holds fake data (a `.invalid` address, or a title or author the manifest marks
sample=true). It never prints an email address, only counts.
"""
import argparse
import json
import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path

LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1", "[::1]"}
EMAIL = re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}")
INVALID = re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]*\.invalid\b", re.I)
GENERIC_SAMPLE = ["sample article", "sample issue", "not a real publication", "placeholder author", "placeholder editor"]


def is_local(base_url):
    return (urllib.parse.urlparse(base_url).hostname or "").lower() in LOCAL_HOSTS


def sample_terms(manifest):
    terms = set(GENERIC_SAMPLE)
    if manifest and Path(manifest).exists():
        for rec in json.loads(Path(manifest).read_text()).get("records", []):
            if rec.get("sample"):
                for key in ("title", "author"):
                    if rec.get(key):
                        terms.add(rec[key].lower())
    return terms


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kind", required=True, choices=["users", "native"])
    ap.add_argument("--file", required=True)
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--manifest")
    a = ap.parse_args()

    raw = Path(a.file).read_text(encoding="utf-8", errors="replace")
    try:
        root = ET.fromstring(raw)
    except ET.ParseError as e:
        print(f"REFUSED: the file is not well-formed XML ({e.msg}, line {e.position[0]})")
        return 2
    local = lambda t: t.rsplit("}", 1)[-1]
    items = sum(1 for el in root.iter() if local(el.tag) == ("user" if a.kind == "users" else "article"))
    emails = len(EMAIL.findall(raw))
    invalid = len(INVALID.findall(raw))
    low = raw.lower()
    samples = sorted(t for t in sample_terms(a.manifest) if t in low)
    print(f"precheck: root <{local(root.tag)}>, {items} {'user' if a.kind == 'users' else 'article'} element(s), "
          f"{emails} email address(es) ({invalid} on a .invalid domain), {len(samples)} sample marker(s) found")
    if not is_local(a.base_url) and (invalid or samples):
        print("REFUSED: this target is not localhost and the file contains fake data "
              f"({invalid} .invalid address(es); sample markers: {', '.join(samples) if samples else 'none'}). "
              "Fake articles and fake users must never reach production.")
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
