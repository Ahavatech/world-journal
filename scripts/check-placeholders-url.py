#!/usr/bin/env python3
"""Scan the RENDERED site for placeholders: the launch gate that matters.

  scripts/check-placeholders.sh --url http://127.0.0.1:8082/worj

Also reports wording OJS ships as default settings text (scripts/ojs-default-wording.txt).
Crawls the journal sitemap and the nav, footer and sidebar links on the home page.
For every page it scans the visible text, the <title>, the meta tags (description,
citation_*, DC.*, og:*, twitter:*) and image alt / aria-label text. For every
article it downloads the PDF galley (citation_pdf_url) and runs pdftotext, which
catches the watermark. A 404 (or any error) on a nav link, a sitemap URL or a PDF is
a FAILURE. Nothing from the repository allowlist applies here: rendered pages must
be empty. Exit 1 if anything is found or fails.
"""
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

PATTERN = re.compile(
    r"\[PLACEHOLDER|Sample Article|Sample Issue|Placeholder Author|Placeholder Editor|"
    r"example\.org|example\.invalid|lorem|NOT A REAL PUBLICATION|not a real publication",
    re.IGNORECASE,
)
# Fragments of the wording OJS ships as default settings text (see
# scripts/extract-ojs-default-wording.py). Text left as shipped goes live as the
# journal's own policy, so it is reported like a placeholder.
DEFAULT_WORDING_FILE = __import__("pathlib").Path(__file__).resolve().parent / "ojs-default-wording.txt"
DEFAULT_WORDING = [l.strip() for l in DEFAULT_WORDING_FILE.read_text().splitlines()
                   if l.strip() and not l.startswith("#")] if DEFAULT_WORDING_FILE.exists() else []
CORE_PAGES = ["/about", "/about/privacy", "/about/submissions", "/about/contact", "/about/editorialMasthead",
              "/information/readers", "/information/authors", "/information/librarians"]
META_NAME = re.compile(r"^(description|citation_.*|dc\..*|og:.*|twitter:.*)$", re.IGNORECASE)


def fetch(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": "worj-check-placeholders/1"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(), r.headers.get("Content-Type", "")
    except urllib.error.HTTPError as e:
        return e.code, b"", ""
    except Exception as e:  # network error
        return 0, str(e).encode(), ""


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title = ""
        self.text = []
        self.fields = []  # (field, value) for meta, alt, aria-label
        self.nav_links = []
        self._in_title = False
        self._skip = 0
        self._region = []  # open nav / aside / footer elements

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in ("script", "style"):
            self._skip += 1
        if tag == "title":
            self._in_title = True
        if tag == "meta":
            name = a.get("name") or a.get("property") or ""
            if META_NAME.match(name) and a.get("content"):
                self.fields.append((f"meta {name}", a["content"]))
        for attr in ("alt", "aria-label", "title"):
            if a.get(attr):
                self.fields.append((f"{tag}[{attr}]", a[attr]))
        if tag in ("nav", "aside", "footer", "header"):
            self._region.append(tag)
        if tag == "a" and self._region and a.get("href"):
            self.nav_links.append(a["href"])

    def handle_endtag(self, tag):
        if tag in ("script", "style") and self._skip:
            self._skip -= 1
        if tag == "title":
            self._in_title = False
        if tag in ("nav", "aside", "footer", "header") and self._region:
            self._region.pop()

    def handle_data(self, data):
        if self._in_title:
            self.title += data
        elif not self._skip:
            self.text.append(data)


def scan_html(url, body, findings):
    p = Page()
    p.feed(body.decode("utf-8", "replace"))
    for field, value in [("title", p.title)] + p.fields + [("text", " ".join(p.text))]:
        for m in PATTERN.finditer(value):
            findings.append((url, field, value[max(0, m.start() - 20): m.end() + 40].strip().replace("\n", " ")))
    visible = re.sub(r"\s+", " ", " ".join(p.text)).lower()
    for frag in DEFAULT_WORDING:
        if frag in visible:
            findings.append((url, "ojs default wording", frag))
    return p


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    base = sys.argv[1].rstrip("/")
    origin = "{0.scheme}://{0.netloc}".format(urllib.parse.urlparse(base))
    findings, failures = [], []

    status, body, _ = fetch(base + "/")
    if status != 200:
        print(f"FAIL  home page {base}/ returned {status or 'a network error'}")
        return 1
    home = Page()
    home.feed(body.decode("utf-8", "replace"))

    # sitemap: the journal sitemap, then /sitemap.xml
    sitemap_urls = []
    for candidate in (base + "/sitemap", base + "/sitemap.xml", origin + "/sitemap.xml"):
        st, sb, _ = fetch(candidate)
        if st == 200 and b"<loc>" in sb:
            sitemap_urls = re.findall(r"<loc>([^<]+)</loc>", sb.decode("utf-8", "replace"))
            print(f"sitemap: {candidate} ({len(sitemap_urls)} URLs)")
            break
    else:
        failures.append(("sitemap", "no sitemap found at /sitemap or /sitemap.xml"))

    nav = {urllib.parse.urljoin(base + "/", h.split("#")[0]) for h in home.nav_links
           if h and not h.startswith(("#", "mailto:", "javascript:", "tel:"))}
    nav = {u for u in nav if u.startswith(origin)}
    # Core pages that print journal settings (some default text only shows here, and the
    # Information pages are linked only when the sidebar block is on). A 404 on one of
    # these is not a failure: the page may be switched off.
    optional = {base + path for path in CORE_PAGES}
    urls = {base + "/"} | set(sitemap_urls) | nav | optional

    pdfs, pages_done = set(), 0
    for url in sorted(urls):
        st, body, ctype = fetch(url)
        is_nav = url in nav
        if st != 200:
            if url in optional and url not in nav and url not in sitemap_urls:
                continue
            failures.append((url, f"{'nav link' if is_nav else 'sitemap URL'} returned {st or 'a network error'}"))
            continue
        if "html" not in ctype and not body.lstrip().startswith(b"<"):
            continue
        pages_done += 1
        p = scan_html(url, body, findings)
        for field, value in p.fields:
            if field == "meta citation_pdf_url":
                pdfs.add(value)

    pdfs_done = 0
    for pdf in sorted(pdfs):
        st, body, _ = fetch(pdf, timeout=60)
        if st != 200 or not body.startswith(b"%PDF"):
            failures.append((pdf, f"PDF galley returned {st or 'a network error'} or is not a PDF"))
            continue
        try:
            out = subprocess.run(["pdftotext", "-layout", "-", "-"], input=body, capture_output=True, timeout=60)
        except FileNotFoundError:
            failures.append((pdf, "pdftotext is not installed, cannot read the PDF"))
            continue
        pdfs_done += 1
        text = out.stdout.decode("utf-8", "replace")
        for m in PATTERN.finditer(text):
            findings.append((pdf, "pdf text", text[max(0, m.start() - 20): m.end() + 40].strip().replace("\n", " ")))

    for url, why in failures:
        print(f"FAIL  {url}: {why}")
    seen = set()
    for url, field, snippet in findings:
        key = (url, field, snippet)
        if key not in seen:
            seen.add(key)
            print(f"{url} [{field}]: ...{snippet}...")
    pages_with = len({u for u, _, _ in findings})
    print(f"check-placeholders (rendered {base}): {pages_done} pages and {pdfs_done} PDF(s) scanned; "
          f"{len(seen)} finding(s) on {pages_with} page(s); {len(failures)} failure(s)")
    if not findings and not failures:
        print("empty: no placeholder is visible on the rendered site")
    return 1 if findings or failures else 0


if __name__ == "__main__":
    sys.exit(main())
