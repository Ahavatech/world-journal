#!/usr/bin/env python3
"""Lint the placeholder content in ojs/content/ for invented claims.

IMPORTANT: this only catches KNOWN PATTERNS (the lists below). A pass is NOT a
guarantee that a file is free of invented claims, and human review of every
content file is still required before it is committed.

Rules, per file under ojs/content/**/*.html:
  banner      the first line must be the placeholder banner, exactly
  banned      banned words and patterns anywhere in the visible text (headings,
              prompts and [PLACEHOLDER: ...] markers): indexer and metric names,
              review-model words, licence names, promises and durations,
              currencies, URLs and email addresses
  digits      digits in RUNNING PROSE only: text inside <p> and <li>, outside the
              banner and outside [PLACEHOLDER: ...] markers. Headings, attribute
              values and markup are not checked for digits
  markup      no <script>, <style>, <img>, <iframe>, <form>; links must be
              relative (no scheme, host or leading "//"), so they keep working
              under any journal path

Anything else needs an EXACT entry in scripts/content-claims-allow.txt
(tab-separated: file, rule, the exact message as printed after the rule, for example: "Year" in: <the line text>). An entry that matches no finding is
stale and fails the lint, so the rule is never loosened by accident.

Exit 0 when clean, 1 on any finding or stale allowlist entry.
"""
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "ojs" / "content"
ALLOW = Path(__file__).resolve().parent / "content-claims-allow.txt"
BANNER = '<p class="worj-placeholder">[PLACEHOLDER: replace with client-approved text]</p>'

BANNED = [
    r"ISSN", r"eISSN", r"DOI", r"DOAJ", r"Scopus", r"Web of Science", r"Crossref", r"Clarivate",
    r"COPE", r"ICMJE", r"ORCID", r"impact factor", r"CiteScore", r"indexed", r"indexing",
    r"Creative Commons", r"CC[- ]BY", r"CC0", r"GPL", r"Apache", r"MIT licen[cs]e",
    r"blind", r"anonymous", r"anonymised", r"anonymized", r"single", r"double", r"triple", r"open review",
    r"guarantee[ds]?", r"always", r"never", r"within", r"days?", r"weeks?", r"months?", r"years?",
    r"USD", r"EUR", r"GBP", r"https?://", r"www\.", r"[\w.+-]+@[\w-]+\.[\w.-]+",
]
BANNED_RE = re.compile(r"(?<![A-Za-z])(?:" + "|".join(BANNED) + r")(?![A-Za-z])", re.IGNORECASE)
CURRENCY_RE = re.compile(r"[£$€]")
MARKER_RE = re.compile(r"\[PLACEHOLDER:[^\]]*\]")
FORBIDDEN_TAGS = {"script", "style", "img", "iframe", "form", "object", "embed"}


class Scan(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.findings = []  # (line, rule, text)

    def handle_starttag(self, tag, attrs):
        if tag in FORBIDDEN_TAGS:
            self.findings.append((self.getpos()[0], "markup", f"<{tag}> is not allowed"))
        if tag == "a":
            href = dict(attrs).get("href", "")
            if re.match(r"^([A-Za-z][A-Za-z0-9+.-]*:|//)", href) or not href:
                self.findings.append((self.getpos()[0], "markup", f'link href "{href}" must be relative (no scheme or host)'))
        if tag not in {"br", "hr", "img", "input", "meta", "link"}:
            self.stack.append((tag, dict(attrs).get("class", "")))

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, -1, -1):
            if self.stack[i][0] == tag:
                del self.stack[i:]
                break

    def handle_data(self, data):
        text = data.strip()
        if not text:
            return
        line = self.getpos()[0]
        is_banner = any("worj-placeholder" in cls for _, cls in self.stack) and text.startswith("[PLACEHOLDER: replace with")
        for m in BANNED_RE.finditer(data):
            self.findings.append((line, "banned", f'"{m.group(0)}" in: {text}'))
        if CURRENCY_RE.search(data):
            self.findings.append((line, "banned", f"currency symbol in: {text}"))
        in_prose = any(tag in {"p", "li"} for tag, _ in self.stack)
        if in_prose and not is_banner:
            prose = MARKER_RE.sub("", data)
            if re.search(r"\d", prose):
                self.findings.append((line, "digits", f"digit in running prose: {text}"))


def load_allow():
    entries = {}
    if ALLOW.exists():
        for n, raw in enumerate(ALLOW.read_text().splitlines(), 1):
            if not raw.strip() or raw.startswith("#"):
                continue
            parts = raw.split("\t")
            if len(parts) != 3:
                print(f"{ALLOW.name}:{n}: malformed entry (need file<TAB>rule<TAB>exact text)")
                sys.exit(1)
            entries[(parts[0], parts[1], parts[2])] = False
    return entries


def main():
    files = sorted(CONTENT.rglob("*.html"))
    if not files:
        print("no content files found under ojs/content/")
        return 1
    allow = load_allow()
    bad = 0
    for f in files:
        rel = str(f.relative_to(ROOT))
        text = f.read_text()
        first = text.splitlines()[0].strip() if text.strip() else ""
        found = []
        if first != BANNER:
            found.append((1, "banner", "first line is not the placeholder banner"))
        sc = Scan()
        sc.feed(text)
        found += sc.findings
        for line, rule, msg in found:
            exact = msg  # the whole message: for a banned word that includes the word itself
            key = (rel, rule, exact)
            if key in allow:
                allow[key] = True
                continue
            bad += 1
            print(f"{rel}:{line}: [{rule}] {msg}")
    for (rel, rule, exact), used in allow.items():
        if not used:
            bad += 1
            print(f"{ALLOW.name}: stale entry (matches nothing): {rel} [{rule}] {exact}")
    print(f"content claims lint: {len(files)} files, {'clean' if not bad else str(bad) + ' finding(s)'}"
          " (known patterns only; human review of every file is still required)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
