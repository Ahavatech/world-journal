#!/usr/bin/env python3
"""Build OJS Native XML for ONE published issue with its articles (PDFs embedded), from a metadata file you keep OUTSIDE the repository.

  python3 -I scripts/build-issue-import.py METADATA.json PDF_DIR OUT.xml [--into-existing]

With --into-existing the file carries ONLY the articles, each pointing at the issue that already exists (matched by the issue's volume, number,
year and title, which must match exactly one issue): use it to add articles to a published issue.

METADATA.json (the authors' details are personal data: never commit it):
  {"issue": {"volume": 1, "number": "1", "year": 2026, "title": "...", "date_published": "YYYY-MM-DD"},
   "section": {"abbrev": "ART", "title": "Articles"}, "uploader": "administrator", "licence_url": "https://...",
   "articles": [{"title": "...", "abstract": "...", "keywords": ["..."], "pages": "1-12", "pdf": "article-1.pdf", "date_published": "YYYY-MM-DD (optional)",
                 "authors": [{"given": "...", "family": "...", "affiliation": "...", "email": "..."}], "references": ["..."]}]}
Nothing is invented: a field missing from the metadata is left out of the XML. The result is checked against OJS's own schema when
ojs-core/ is present (xmllint). Import it with scripts/import-issue-shared.sh (the host) or `php tools/importExport.php NativeImportExportPlugin import FILE JOURNAL USER`."""
import base64, json, subprocess, sys
from pathlib import Path
from xml.sax.saxutils import escape as _esc

_dropped = []


def esc(s):
    """XML-escape, and drop characters outside the basic plane (emoji and the like): OJS's database columns (utf8, three bytes) refuse them and the
    whole import fails. What was dropped is reported at the end."""
    s = str(s)
    cleaned = "".join(c for c in s if ord(c) <= 0xFFFF)
    if cleaned != s:
        _dropped.append("".join(c for c in s if ord(c) > 0xFFFF))
    return _esc(cleaned)

into_existing = "--into-existing" in sys.argv
args = [a for a in sys.argv[1:] if a != "--into-existing"]
if len(args) != 3:
    print(__doc__)
    sys.exit(2)
sys.argv = [sys.argv[0]] + args
meta = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
pdf_dir, out = Path(sys.argv[2]), Path(sys.argv[3])
iss, sec = meta["issue"], meta["section"]
uploader = meta.get("uploader", "administrator")
date = iss["date_published"]
for k in ("volume", "number", "year", "title", "date_published"):
    if iss.get(k) in (None, ""):
        sys.exit(f"issue.{k} is missing")

arts, fid, aid = [], 0, 100
for n, a in enumerate(meta["articles"], 1):
    fid += 1
    adate = a.get("date_published", date)      # an article may carry its own publication date; the issue's date is the default
    pdf = pdf_dir / a["pdf"]
    if not pdf.is_file() or pdf.read_bytes()[:4] != b"%PDF":
        sys.exit(f"{pdf} is not a PDF file")
    data = base64.b64encode(pdf.read_bytes()).decode()
    kw = "".join(f"<keyword><name>{esc(k)}</name></keyword>" for k in a.get("keywords", []))
    authors = ""
    for i, au in enumerate(a["authors"]):
        aid += 1
        authors += f"""
          <author include_in_browse="true" user_group_ref="Author" seq="{i}" id="{aid}">
            <givenname locale="en">{esc(au['given'])}</givenname>
            <familyname locale="en">{esc(au['family'])}</familyname>
            {f'<affiliation><name locale="en">{esc(au["affiliation"])}</name></affiliation>' if au.get('affiliation') else ''}
            <email>{esc(au['email'])}</email>
          </author>"""
    refs = "".join(f"<citation>{esc(r)}</citation>" for r in a.get("references", []))
    lic = f"<licenseUrl>{esc(meta['licence_url'])}</licenseUrl>" if meta.get("licence_url") else ""
    issue_ref = (f'<issue_identification><volume>{iss["volume"]}</volume><number>{esc(str(iss["number"]))}</number>'
                 f'<year>{iss["year"]}</year><title locale="en">{esc(iss["title"])}</title></issue_identification>') if into_existing else ""
    arts.append(f"""
    <article xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://pkp.sfu.ca"
        date_submitted="{adate}" stage="production" locale="en" status="3" current_publication_id="{fid}">
      <id type="internal" advice="ignore">{fid}</id>
      <submission_file stage="proof" id="{fid}" file_id="{fid}" genre="Article Text" viewable="true"
          date_created="{adate}" uploader="{esc(uploader)}" xsi:schemaLocation="http://pkp.sfu.ca native.xsd">
        <name locale="en">{esc(a['title'])}</name>
        <file id="{fid}" filesize="{pdf.stat().st_size}" extension="pdf"><embed encoding="base64">{data}</embed></file>
      </submission_file>
      <publication xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="1" status="3"
          date_published="{adate}" section_ref="{esc(sec['abbrev'])}" seq="{n}" access_status="0"
          xsi:schemaLocation="http://pkp.sfu.ca native.xsd">
        <id type="internal" advice="ignore">{fid}</id>
        <title locale="en">{esc(a['title'])}</title>
        <abstract locale="en">{esc(a['abstract'])}</abstract>
        {lic}
        <keywords locale="en">{kw}</keywords>
        <authors>{authors}
        </authors>
        <article_galley xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" locale="en" approved="true"
            xsi:schemaLocation="http://pkp.sfu.ca native.xsd">
          <id type="internal" advice="ignore">{fid}</id>
          <name locale="en">PDF</name>
          <seq>0</seq>
          <submission_file_ref id="{fid}"/>
        </article_galley>
        {f'<citations locale="en">{refs}</citations>' if refs else ''}
        {issue_ref}
        {f'<pages>{esc(a["pages"])}</pages>' if a.get('pages') else ''}
      </publication>
    </article>""")

if into_existing:
    xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<articles xmlns="http://pkp.sfu.ca" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://pkp.sfu.ca native.xsd">{''.join(arts)}
</articles>
"""
else:
    xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<issues xmlns="http://pkp.sfu.ca" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://pkp.sfu.ca native.xsd">
  <issue published="1" current="1" access_status="1">
    <id type="internal" advice="ignore">1</id>
    <issue_identification>
      <volume>{iss['volume']}</volume>
      <number>{esc(str(iss['number']))}</number>
      <year>{iss['year']}</year>
      <title locale="en">{esc(iss['title'])}</title>
    </issue_identification>
    <date_published>{date}</date_published>
    <last_modified>{date}</last_modified>
    <sections>
      <section ref="{esc(sec['abbrev'])}" seq="1" editor_restricted="0" meta_indexed="1" meta_reviewed="1"
          abstracts_not_required="0" hide_title="0" hide_author="0" abstract_word_count="0">
        <id type="internal" advice="ignore">1</id>
        <abbrev locale="en">{esc(sec['abbrev'])}</abbrev>
        <title locale="en">{esc(sec['title'])}</title>
      </section>
    </sections>
    <articles xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://pkp.sfu.ca native.xsd">{''.join(arts)}
    </articles>
  </issue>
</issues>
"""
out.write_text(xml, encoding="utf-8")
if _dropped:
    print("NOTE: dropped characters the database cannot store: " + " ".join(sorted(set(_dropped))))
print(f"wrote {out} ({out.stat().st_size} bytes, {len(arts)} article(s))")
xsd = Path(__file__).resolve().parent.parent / "ojs-core" / "plugins" / "importexport" / "native" / "native.xsd"
if xsd.is_file():
    r = subprocess.run(["xmllint", "--noout", "--schema", str(xsd), str(out)], capture_output=True, text=True)
    print("schema check:", "valid" if r.returncode == 0 else "INVALID\n" + r.stderr[-1500:])
    sys.exit(0 if r.returncode == 0 else 1)
print("schema check: skipped (no ojs-core/ here)")
