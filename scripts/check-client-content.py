#!/usr/bin/env python3
"""Check the client's own text in ojs/client-content/ (received 2026-11-11) before it is loaded on the site.

  python3 -I scripts/check-client-content.py [--dir ojs/client-content]

What it guarantees (exit 1 and a line per problem otherwise):
  - map.json lists files that exist, with unique ids, and every id (except the announcement) is a page in ojs/content/pages.json
  - every file starts with ONE pending banner, `[PLACEHOLDER: client text received 2026-11-11, pending confirmation: ...]`, so the
    launch gate (scripts/check-placeholders.sh) stays red until a person resolves it
  - NOTHING IS INVENTED: every paragraph, list item and heading of every file is a passage of source-v1.txt (the client's text as
    sent), apart from the banner, text inside `<span class="worj-ph">` (a marked blank), text inside `<span class="worj-add">`
    (which must be a passage of the addendum, the recorded decisions of 2026-11-13) and the few headings of our own listed in
    OUR_HEADINGS. Spelling and wording are the client's: this checks that we did not add or change a sentence
  - no email address (except one of the journal's own aliases inside a marked blank), no REDACTED marker, no example host in any file
"""
import argparse
import json
import os
import re
import sys
from html.parser import HTMLParser

OWN_ALIAS = re.compile(r"^(editorial|support|privacy|doi|admin)@worldopenresearchjournal\.com$")
OUR_HEADINGS = {"publisher"}  # headings we add ourselves (the publisher is blank in the document and stays a placeholder)
BANNER = re.compile(r'^<p class="worj-placeholder">\[PLACEHOLDER: client text received 2026-11-11, pending confirmation: [^\]<]+\]</p>$')


def norm(t):
    t = t.replace("’", "'").replace("‘", "'").replace("“", '"').replace("”", '"').replace("\xa0", " ")
    return re.sub(r"\s+", " ", t).strip().lower()


class Blocks(HTMLParser):
    """Collect the text of p, li, h1-h4, skipping the banner paragraph and worj-ph spans."""

    def __init__(self):
        super().__init__()
        self.blocks, self.cur, self.depth_skip, self.in_block, self.skip_banner, self.add_depth = [], [], 0, None, False, 0

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = a.get("class", "")
        if tag in ("p", "li", "h1", "h2", "h3", "h4") and self.in_block is None:
            self.in_block, self.cur, self.skip_banner = tag, [], "worj-placeholder" in cls
        if tag == "span" and "worj-add" in cls and self.in_block and not self.depth_skip:
            self.add_depth += 1
            if self.add_depth == 1:
                self.cur.append("\x01")  # text from the addendum: checked against the addendum, not the source
        elif tag == "span" and self.add_depth:
            self.add_depth += 1
        if tag == "span" and "worj-ph" in cls:
            if self.in_block and not self.depth_skip:
                self.cur.append("\x00")  # a marked blank splits the block: each part must be a passage of the source
            self.depth_skip += 1
        elif self.depth_skip and tag == "span":
            self.depth_skip += 1

    def handle_endtag(self, tag):
        if tag == "span" and self.add_depth:
            self.add_depth -= 1
            if self.add_depth == 0:
                self.cur.append("\x02")
        elif tag == "span" and self.depth_skip:
            self.depth_skip -= 1
        if tag == self.in_block:
            text = "".join(self.cur)
            if not self.skip_banner and norm(text):
                self.blocks.append((tag, text))
            self.in_block, self.cur = None, []

    def handle_data(self, data):
        if self.in_block and not self.depth_skip:
            self.cur.append(data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ojs", "client-content"))
    ap.add_argument("--pages-json", default=None)
    a = ap.parse_args()
    d = a.dir
    pages_json = a.pages_json or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ojs", "content", "pages.json")
    problems = []
    cmap = json.load(open(os.path.join(d, "map.json"), encoding="utf-8"))
    known = {p["id"] for p in json.load(open(pages_json, encoding="utf-8"))["pages"]}
    src = open(os.path.join(d, cmap["source"]), encoding="utf-8").read()
    src = src.split("=" * 20, 1)[1] if "=" * 20 in src else src
    src_n = norm(src)
    add_text = ""
    if cmap.get("addendum"):
        add_text = open(os.path.join(d, cmap["addendum"]), encoding="utf-8").read()
        add_text = add_text.split("=" * 20, 1)[1] if "=" * 20 in add_text else add_text
    add_n = norm(add_text)
    files, seen = [], set()
    for p in cmap["pages"]:
        if p["id"] in seen:
            problems.append(f"map.json: duplicate id {p['id']}")
        seen.add(p["id"])
        if p["id"] not in known:
            problems.append(f"map.json: {p['id']} is not a page in ojs/content/pages.json")
        files.append(p["file"])
    files.append(cmap["announcement"]["file"])
    short = cmap["announcement"]["short"]
    if norm(short) not in src_n:
        problems.append("map.json: the announcement's short text is not a passage of the source")
    checked = 0
    for f in files:
        path = os.path.join(d, f)
        if not os.path.isfile(path):
            problems.append(f"{f}: file missing")
            continue
        text = open(path, encoding="utf-8").read()
        lines = text.split("\n")
        if not BANNER.match(lines[0]):
            problems.append(f"{f}: the first line is not the pending banner")
        if text.count("[PLACEHOLDER: client text") != 1:
            problems.append(f"{f}: there must be exactly one pending banner")
        # an email address is allowed only inside a marked blank or an addendum span (`worj-ph`, `worj-add`) and only as one of the journal's own aliases
        outside = re.sub(r'<span class="worj-(?:ph|add)">.*?</span>', "", text, flags=re.S)
        if re.search(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+|REDACTED|example\.(org|invalid)", outside):
            problems.append(f"{f}: an email address, a REDACTED marker or an example host")
        for span in re.findall(r'<span class="worj-(?:ph|add)">(.*?)</span>', text, flags=re.S):
            for addr in re.findall(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+", span):
                if not OWN_ALIAS.match(addr):
                    problems.append(f"{f}: {addr} is not one of the journal's own addresses")
        pr = Blocks()
        pr.feed(text)
        for tag, t in pr.blocks:
            checked += 1
            if tag.startswith("h") and norm(t) in OUR_HEADINGS:
                continue
            # text between \x01 and \x02 comes from the addendum; the rest (split at marked blanks) from the client's document
            pieces = re.split(r"(\x01.*?\x02)", t, flags=re.S)
            for piece in pieces:
                if piece.startswith("\x01"):
                    inner = piece[1:-1]
                    if norm(inner) and norm(inner) not in add_n:
                        problems.append(f"{f}: not a passage of the addendum: {inner.strip()[:90]!r}")
                    continue
                for part in piece.split("\x00"):
                    if norm(part) and norm(part) not in src_n:
                        problems.append(f"{f}: not a passage of the client's text: {part.strip()[:90]!r}")
    for p in problems:
        print("FAIL  " + p)
    print(f"client content: {len(files)} files, {checked} text blocks checked against the source, {len(problems)} problem(s)")
    return 1 if problems else 0


sys.exit(main())
