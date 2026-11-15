#!/usr/bin/env python3
"""Turn the journal's own formatted article (a Word file, used only as the source of the LAYOUT) into an EMPTY manuscript template:
   python3 -I scripts/lib/make-manuscript-template.py SOURCE.docx OUT.docx
Everything that belongs to the research or its authors is replaced by a bracketed prompt; the page layout, the header banner, the styles, the
two-column body, the heading bands, the table style and the footer are kept. The footer's volume, issue and year become blanks for the editor.
The document properties (author, last editor, title, word counts) are rewritten. The source is never copied into the repository."""
import copy, datetime, re, shutil, sys, tempfile, zipfile
from lxml import etree

W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
XML = "http://www.w3.org/XML/1998/namespace"
ns = {"w": W}
q = lambda t: "{%s}%s" % (W, t)

src, out = sys.argv[1], sys.argv[2]
tmp = tempfile.mkdtemp()
with zipfile.ZipFile(src) as z:
    z.extractall(tmp)
    names = z.namelist()

doc = etree.parse(f"{tmp}/word/document.xml")
body = doc.getroot().find("w:body", ns)
els = list(body)
final_sect = els[-1]
assert etree.QName(final_sect).localname == "sectPr"

def set_t(r, text):
    for t in r.findall("w:t", ns):
        r.remove(t)
    for br in r.findall("w:br", ns):
        r.remove(br)
    t = etree.SubElement(r, q("t"))
    t.text = text
    t.set("{%s}space" % XML, "preserve")

def set_para(p, text):
    """whole paragraph = one run (the first run's look)"""
    runs = p.findall("w:r", ns)
    keep = runs[0]
    for child in list(p):
        if child.tag not in (q("pPr"), keep.tag) or (child.tag == keep.tag and child is not keep):
            if child.tag != q("pPr"):
                p.remove(child)
    set_t(keep, text)

def run_texts(p):
    return p.findall("w:r", ns)

def clone(i):
    return copy.deepcopy(els[i])

new = []
# --- front matter (single column section)
t0 = clone(0); set_para(t0, "[Title of the Article in Title Case]"); new += [t0, clone(1), clone(2)]
p3 = clone(3); set_para(p3, "[Author name]¹, [Author name]²"); new.append(p3)
p4 = clone(4)
rs = run_texts(p4)            # "1 ", affiliation, br + "2 ", affiliation, br
set_t(rs[1], "[Affiliation of author 1]"); set_t(rs[3], "[Affiliation of author 2]")
new.append(p4)
h1 = clone(5); set_para(h1, "Abstract"); new.append(h1)
ab = clone(6); set_para(ab, "[Abstract: one paragraph that states the problem, the method, the main results and the conclusion. Do not cite references here.]"); new.append(ab)
kw = clone(7); rs = run_texts(kw); set_t(rs[-1], "[keyword one; keyword two; keyword three; further keywords]"); new.append(kw)
ca = clone(8); rs = run_texts(ca)
set_t(rs[2], ": [Name]"); set_t(rs[3], ""); set_t(rs[4], ", [Affiliation],"); set_t(rs[5], " [email address]"); new.append(ca)
new += [clone(9), clone(10)]
hi = clone(11); set_para(hi, "Introduction"); new.append(hi)
new.append(clone(12))                      # end of the single column section (carries the header and footer)
# --- two column body
def body_p(text): p = clone(21); set_para(p, text); return p
def head(i, text): h = clone(i); set_para(h, text); return h
new += [body_p("[Introduction: the background, the gap in what is known, and the aim of the study.]")]
new += [head(19, "2. Literature Review"), head(20, "2.1 [Subheading]"), body_p("[Summarise the earlier work that matters for this study and cite it in the text, for example Author (Year).]")]
new += [head(43, "3. Methodology"), head(44, "3.1 Research Design"), body_p("[Describe the design, the participants or materials, and the ethics approval where it applies.]")]
new += [head(48, "3.2 Data Collection and Analysis"), body_p("[Describe how the data were collected and analysed, with enough detail for another researcher to repeat the work.]")]
lead = clone(50); set_para(lead, "[Lead-in sentence for a list, if you need one:]"); new.append(lead)
for _ in range(2):
    li = clone(51); set_para(li, "[List item.]"); new.append(li)
new += [head(79, "4. Results and Analysis"), head(80, "4.1 [Subheading]"), body_p("[Report the findings. Refer to each table and figure in the text.]")]
new.append(clone(110))                     # end of the two column section
# --- a full width table section
th = head(111, "4.2 [Table heading, if the table needs one]"); new.append(th)
cap = clone(112); set_para(cap, "Table 1. [Table caption]"); new.append(cap)
tbl = clone(113)
rows = tbl.findall("w:tr", ns)
for r in rows[3:]:
    tbl.remove(r)
for ri, r in enumerate(rows[:3]):
    for ci, tc in enumerate(r.findall("w:tc", ns)):
        ps = tc.findall("w:p", ns)
        for extra in ps[1:]:
            tc.remove(extra)
        set_para(ps[0], f"[Column {ci + 1}]" if ri == 0 else "[Entry]")
new += [tbl, clone(114)]
# --- discussion, conclusion, references (two columns again)
new += [head(118, "5. Discussion and Conclusion"), head(119, "5.1 Discussion"), body_p("[Interpret the results, compare them with earlier work, and state the limitations.]")]
new += [head(119, "5.2 Conclusion"), body_p("[The main conclusion and its significance, in a few sentences.]")]
new += [head(144, "References")]
for i, text in ((145, "Author, A. A., & Author, B. B. (Year). Title of the article. Journal Name, volume(issue), pages. https://doi.org/..."),
                (146, "Author, C. C. (Year). Title of the book. Publisher.")):
    p = clone(i); set_para(p, text); new.append(p)
new.append(final_sect)

for child in list(body):
    body.remove(child)
for e in new:
    body.append(e)
doc.write(f"{tmp}/word/document.xml", xml_declaration=True, encoding="UTF-8", standalone=True)

# --- footer: volume, issue and year become blanks for the editor
ft = etree.parse(f"{tmp}/word/footer1.xml")
ts = ft.getroot().findall(".//w:t", ns)
texts = [t.text for t in ts]
def swap(old, new_):
    for t in ts:
        if t.text == old:
            t.text = new_
            t.set("{%s}space" % XML, "preserve")
            return
    raise SystemExit(f"footer run not found: {old!r}")
swap("Vol ", "Vol ")
swap("6", "[  ]")
swap("/ Issue: ", " / Issue: ")
swap("01", "[  ]")
swap("202", "Year")
swap("5", "")
ft.write(f"{tmp}/word/footer1.xml", xml_declaration=True, encoding="UTF-8", standalone=True)

# --- document properties
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
core = open(f"{tmp}/docProps/core.xml", encoding="utf8").read()
core = re.sub(r"<dc:creator>.*?</dc:creator>", "<dc:creator>World Open Research Journal</dc:creator>", core)
core = re.sub(r"<cp:lastModifiedBy>.*?</cp:lastModifiedBy>", "<cp:lastModifiedBy>World Open Research Journal</cp:lastModifiedBy>", core)
core = re.sub(r"<dc:description>.*?</dc:description>", "", core)
core = re.sub(r"<dc:title>.*?</dc:title>|<dc:title/>", "", core)
core = core.replace("</cp:coreProperties>", "<dc:title>Manuscript template</dc:title></cp:coreProperties>")
core = re.sub(r"(<dcterms:created[^>]*>).*?(</dcterms:created>)", r"\g<1>%s\g<2>" % now, core)
core = re.sub(r"(<dcterms:modified[^>]*>).*?(</dcterms:modified>)", r"\g<1>%s\g<2>" % now, core)
core = re.sub(r"<cp:revision>.*?</cp:revision>", "<cp:revision>1</cp:revision>", core)
open(f"{tmp}/docProps/core.xml", "w", encoding="utf8").write(core)
app = open(f"{tmp}/docProps/app.xml", encoding="utf8").read()
for tag in ("Pages", "Words", "Characters", "CharactersWithSpaces", "Lines", "Paragraphs", "TotalTime"):
    app = re.sub(rf"<{tag}>.*?</{tag}>", "", app)
app = re.sub(r"<Company>.*?</Company>|<Company/>", "", app)
open(f"{tmp}/docProps/app.xml", "w", encoding="utf8").write(app)
# the custom property file only held a document number
import os
if os.path.exists(f"{tmp}/docProps/custom.xml"):
    os.remove(f"{tmp}/docProps/custom.xml")
    ct = open(f"{tmp}/[Content_Types].xml", encoding="utf8").read()
    ct = re.sub(r'<Override[^>]*custom\.xml[^>]*/>', "", ct)
    open(f"{tmp}/[Content_Types].xml", "w", encoding="utf8").write(ct)
    rl = open(f"{tmp}/_rels/.rels", encoding="utf8").read()
    rl = re.sub(r'<Relationship [^>]*custom\.xml[^>]*/>', "", rl)
    open(f"{tmp}/_rels/.rels", "w", encoding="utf8").write(rl)

# --- zip (the content types file first, no folder entries)
if os.path.exists(out):
    os.remove(out)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.write(f"{tmp}/[Content_Types].xml", "[Content_Types].xml")
    for root, _, files in os.walk(tmp):
        for f in sorted(files):
            full = os.path.join(root, f)
            arc = os.path.relpath(full, tmp)
            if arc != "[Content_Types].xml":
                z.write(full, arc)
shutil.rmtree(tmp)
print("wrote", out)
