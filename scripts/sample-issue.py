#!/usr/bin/env python3
"""Sample issue for development: 3 clearly fake articles (Phase 3.3).

  scripts/sample-issue.py pdfs          write ojs/fixtures/pdfs/*.pdf (needs reportlab)
  scripts/sample-issue.py xml OUT.xml   write OJS Native XML for the issue (PDFs embedded)

Every record is listed in ojs/fixtures/manifest.json with sample=true so
`check-placeholders` can find and remove them. Nothing here is real: names,
dates, volume and issue numbers are obviously fake, and there is no ISSN or DOI.
"""
import base64
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "ojs" / "fixtures"
PDF_DIR = FIXTURES / "pdfs"
MANIFEST = FIXTURES / "manifest.json"
WATERMARK = "SAMPLE: NOT A REAL PUBLICATION"
AUTHOR = ("Placeholder", "Author")
EMAIL = "placeholder.author@example.invalid"

ISSUE = {
    "volume": 1,
    "number": "1",
    "year": 2000,
    "title": "Sample Issue (not a real publication)",
    "date_published": "2000-01-01",
}
ARTICLES = [
    {"n": n, "title": f"Sample Article {n}", "pages": f"{2 * n - 1}-{2 * n}",
     "pdf": f"sample-article-{n}.pdf",
     "abstract": f"[PLACEHOLDER: sample abstract {n}. Not a real publication.]",
     "keywords": ["sample", "placeholder"]}
    for n in (1, 2, 3)
]


def write_manifest():
    records = [{"type": "issue", "title": ISSUE["title"], "sample": True}]
    for a in ARTICLES:
        records.append({"type": "article", "title": a["title"], "author": " ".join(AUTHOR),
                        "pdf": f"ojs/fixtures/pdfs/{a['pdf']}", "sample": True})
    MANIFEST.write_text(json.dumps(
        {"note": "All records are fake. Delete them from OJS before launch; "
                 "fixtures never ship to production.",
         "records": records}, indent=2) + "\n")


def write_pdfs():
    from reportlab.lib.pagesizes import A4
    from reportlab.pdfgen import canvas

    PDF_DIR.mkdir(parents=True, exist_ok=True)
    w, h = A4
    for a in ARTICLES:
        c = canvas.Canvas(str(PDF_DIR / a["pdf"]), pagesize=A4, invariant=1)
        c.setTitle(a["title"])
        c.setAuthor(" ".join(AUTHOR))
        c.setSubject(WATERMARK)
        for page in (1, 2):
            c.setFont("Helvetica-Bold", 20)
            if page == 1:
                c.drawString(60, h - 90, a["title"])
                c.setFont("Helvetica", 12)
                c.drawString(60, h - 115, " ".join(AUTHOR))
                c.drawString(60, h - 135, "World Open Research Journal (sample record)")
                y = h - 175
            else:
                c.drawString(60, h - 90, "Continued")
                y = h - 130
            c.setFont("Helvetica", 11)
            for line in (
                "This is a sample document used only to develop and test the journal website.",
                "It is not a real publication. The title, author, dates and text are placeholders.",
                "",
                "Selectable text is included so PDF text extraction can be tested.",
            ):
                c.drawString(60, y, line)
                y -= 16
            c.saveState()
            c.translate(w / 2, h / 2)
            c.rotate(45)
            c.setFillGray(0.82)
            c.setFont("Helvetica-Bold", 34)
            c.drawCentredString(0, 0, WATERMARK)
            c.restoreState()
            c.showPage()
        c.save()


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def build_xml():
    fid = 0
    arts = []
    for a in ARTICLES:
        fid += 1
        data = base64.b64encode((PDF_DIR / a["pdf"]).read_bytes()).decode()
        size = (PDF_DIR / a["pdf"]).stat().st_size
        kw = "".join(f"<keyword><name>{esc(k)}</name></keyword>" for k in a["keywords"])
        arts.append(f"""
    <article xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://pkp.sfu.ca"
        date_submitted="2000-01-01" stage="production" locale="en" status="3" current_publication_id="{fid}">
      <id type="internal" advice="ignore">{fid}</id>
      <submission_file stage="proof" id="{fid}" file_id="{fid}" genre="Article Text" viewable="true"
          date_created="2000-01-01" uploader="admin" xsi:schemaLocation="http://pkp.sfu.ca native.xsd">
        <name locale="en">{a['pdf']}</name>
        <file id="{fid}" filesize="{size}" extension="pdf"><embed encoding="base64">{data}</embed></file>
      </submission_file>
      <publication xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="1" status="3"
          date_published="{ISSUE['date_published']}" section_ref="ART" seq="{a['n']}" access_status="0"
          xsi:schemaLocation="http://pkp.sfu.ca native.xsd">
        <id type="internal" advice="ignore">{fid}</id>
        <title locale="en">{esc(a['title'])}</title>
        <abstract locale="en">{esc(a['abstract'])}</abstract>
        <keywords locale="en">{kw}</keywords>
        <authors>
          <author include_in_browse="true" user_group_ref="Author" seq="0" id="{fid}">
            <givenname locale="en">{AUTHOR[0]}</givenname>
            <familyname locale="en">{AUTHOR[1]}</familyname>
            <email>{EMAIL}</email>
          </author>
        </authors>
        <article_galley xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" locale="en" approved="true"
            xsi:schemaLocation="http://pkp.sfu.ca native.xsd">
          <id type="internal" advice="ignore">{fid}</id>
          <name locale="en">PDF</name>
          <seq>0</seq>
          <submission_file_ref id="{fid}"/>
        </article_galley>
        <pages>{a['pages']}</pages>
      </publication>
    </article>""")
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<issues xmlns="http://pkp.sfu.ca" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://pkp.sfu.ca native.xsd">
  <issue published="1" current="1" access_status="1">
    <id type="internal" advice="ignore">1</id>
    <issue_identification>
      <volume>{ISSUE['volume']}</volume>
      <number>{ISSUE['number']}</number>
      <year>{ISSUE['year']}</year>
      <title locale="en">{esc(ISSUE['title'])}</title>
    </issue_identification>
    <date_published>{ISSUE['date_published']}</date_published>
    <last_modified>{ISSUE['date_published']}</last_modified>
    <sections>
      <section ref="ART" seq="1" editor_restricted="0" meta_indexed="1" meta_reviewed="1"
          abstracts_not_required="0" hide_title="0" hide_author="0" abstract_word_count="0">
        <id type="internal" advice="ignore">1</id>
        <abbrev locale="en">ART</abbrev>
        <title locale="en">Articles</title>
      </section>
    </sections>
    <articles xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://pkp.sfu.ca native.xsd">{''.join(arts)}
    </articles>
  </issue>
</issues>
"""


def main(argv):
    if len(argv) >= 2 and argv[1] == "pdfs":
        write_pdfs()
        write_manifest()
    elif len(argv) == 3 and argv[1] == "xml":
        Path(argv[2]).write_text(build_xml())
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
