#!/usr/bin/env python3
"""Parsing helpers for scripts/check-discovery.sh. Output is simple lines the shell reads; exit 1 = a finding.

  discovery.py robots-can FILE AGENT URL [URL ...]   urllib.robotparser: one `ALLOWED url` / `BLOCKED url` per URL, exit 1 if any blocked
  discovery.py robots-sitemaps FILE                  the Sitemap: lines
  discovery.py robots-closed FILE                    exit 0 if agent * and Googlebot may fetch nothing ("/")
  discovery.py sitemap FILE                          `kind url` lines (kind: home issue article galley announcement about other) or `sitemapindex url`; exit 2 if not a sitemap
  discovery.py oai FILE                              key=value lines: root, error, adminEmail, repositoryName, baseURL, formats, identifiers, records, token
  discovery.py markers FILE [FILE ...]               placeholder markers (the same pattern as scripts/check-placeholders-url.py); exit 1 if any
"""
import importlib.util
import os
import re
import sys
import urllib.robotparser
import xml.etree.ElementTree as ET


def robots(path):
    rp = urllib.robotparser.RobotFileParser()
    with open(path, encoding="utf-8", errors="replace") as fh:
        rp.parse(fh.read().splitlines())
    return rp


def kind(url):
    p = re.sub(r"^https?://[^/]+", "", url).split("?")[0].rstrip("/")
    parts = [x for x in p.split("/") if x]
    rest = parts[1:] if parts else []
    if len(parts) <= 1:
        return "home"
    if rest[:2] == ["issue", "view"]:
        return "issue"
    if rest[:1] == ["issue"]:
        return "issue-list"
    if rest[:2] == ["article", "view"]:
        return "galley" if len(rest) >= 4 else "article"
    if rest[:1] == ["announcement"]:
        return "announcement"
    if rest[:1] == ["about"]:
        return "about"
    return "other"


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    cmd, path = argv[1], argv[2]
    if cmd == "robots-can":
        rp, agent, bad = robots(path), argv[3], 0
        for u in argv[4:]:
            ok = rp.can_fetch(agent, u)
            print(("ALLOWED " if ok else "BLOCKED ") + u)
            bad += 0 if ok else 1
        return 1 if bad else 0
    if cmd == "robots-sitemaps":
        for s in robots(path).site_maps() or []:
            print(s)
        return 0
    if cmd == "robots-closed":
        rp = robots(path)
        return 0 if not rp.can_fetch("*", "https://x.invalid/") and not rp.can_fetch("Googlebot", "https://x.invalid/") else 1
    if cmd == "sitemap":
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError as e:
            print(f"not well-formed XML: {e}")
            return 2
        tag = root.tag.split("}")[-1]
        locs = [el.text.strip() for el in root.iter() if el.tag.split("}")[-1] == "loc" and el.text]
        if tag == "sitemapindex":
            for u in locs:
                print("sitemapindex " + u)
        elif tag == "urlset":
            for u in locs:
                print(f"{kind(u)} {u}")
        else:
            print(f"not a sitemap (root element {tag})")
            return 2
        return 0
    if cmd == "oai":
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError as e:
            print(f"error=not well-formed XML: {e}")
            return 2
        loc = lambda el: el.tag.split("}")[-1]
        out = {"root": loc(root), "error": "", "formats": [], "identifiers": [], "records": 0, "token": ""}
        for el in root.iter():
            t, v = loc(el), (el.text or "").strip()
            if t == "error":
                out["error"] = f"{el.get('code', '')} {v}".strip()
            elif t in ("adminEmail", "repositoryName", "baseURL") and t not in out:
                out[t] = v
            elif t == "metadataPrefix":
                out["formats"].append(v)
            elif t == "identifier" and v.startswith("oai:"):
                out["identifiers"].append(v)
            elif t == "record":
                out["records"] += 1
            elif t == "resumptionToken":
                out["token"] = v
        for k in ("root", "error", "adminEmail", "repositoryName", "baseURL"):
            print(f"{k}={out.get(k, '')}")
        print("formats=" + ",".join(out["formats"]))
        print("identifiers=" + ",".join(dict.fromkeys(out["identifiers"])))
        print(f"records={out['records']}")
        print(f"token={out['token']}")
        return 0
    if cmd == "markers":
        here = os.path.dirname(os.path.abspath(__file__))
        spec = importlib.util.spec_from_file_location("cpu", os.path.join(here, "..", "check-placeholders-url.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        found = 0
        for f in argv[2:]:
            with open(f, encoding="utf-8", errors="replace") as fh:
                for m in sorted({m.group(0) for m in mod.PATTERN.finditer(fh.read())}):
                    print(f"MARKER {m}")
                    found += 1
        return 1 if found else 0
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
