#!/usr/bin/env bash
# Tests for scripts/check-pdf.sh and scripts/lib/pdf_match.py against a tiny local HTTP server and generated PDFs.
# Every negative case must FAIL the check; the cookie case must PASS with an INFO line.
# Usage: scripts/test-check-pdf.sh      (no sandbox needed; needs python3 and pdftotext)
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v pdftotext >/dev/null || { echo "missing pdftotext (apt-get install poppler-utils)"; exit 2; }
tmp="$(mktemp -d)"
srv=""
trap '[ -z "$srv" ] || kill "$srv" 2>/dev/null; rm -rf -- "${tmp:?}"' EXIT
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
chk() { # chk "label" want_exit [want_text] -- command...
  local label="$1" want="$2" text="$3"; shift 4
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" = "$want" ] && { [ -z "$text" ] || grep -qF -- "$text" <<<"$out"; }; then ok "$label"; else bad "$label (exit $rc, wanted $want${text:+ with "$text"})"; printf '      %s\n' "${out//$'\n'/$'\n      '}"; fi
}

TITLE="Observations of Open Research Practice"
AUTHOR="Placeholder Author"
python3 -I - "$tmp" "$TITLE" "$AUTHOR" <<'PY'
import sys, os
d, title, author = sys.argv[1:4]
def pdf(lines, path, pad=0):
    """lines: list of (y, text). Empty list: a page with only a drawn rectangle (no text)."""
    if lines:
        body = "BT /F1 12 Tf " + " ".join(f"1 0 0 1 72 {y} Tm ({t}) Tj" for y, t in lines) + " ET"
    else:
        body = "72 600 200 100 re f"
    objs = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            f"<< /Length {len(body)} >>\nstream\n{body}\nendstream", "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    out = b"%PDF-1.4\n"; offs = []
    for i, o in enumerate(objs, 1):
        offs.append(len(out)); out += f"{i} 0 obj\n{o}\nendobj\n".encode()
    x = len(out)
    out += f"xref\n0 {len(objs)+1}\n0000000000 65535 f \n".encode() + b"".join(f"{o:010d} 00000 n \n".encode() for o in offs)
    out += f"trailer\n<< /Size {len(objs)+1} /Root 1 0 R >>\nstartxref\n{x}\n%%EOF\n".encode()
    out += b"%" + b"x" * pad + b"\n"
    open(os.path.join(d, path), "wb").write(out)
half = title.split(" ", 3)
pdf([(720, title), (700, author)], "good.pdf")
pdf([(720, " ".join(half[:2])), (706, " ".join(half[2:])), (680, author)], "wrapped.pdf")   # title over two lines
pdf([(720, "Some Other Heading"), (700, author)], "notitle.pdf")
pdf([(720, title)], "noauthor.pdf")
pdf([], "image.pdf")
pdf([(720, title), (700, author)], "big.pdf", pad=5 * 1024 * 1024)
open(os.path.join(d, "notpdf.pdf"), "w").write("<html>viewer</html>")
PY

cat >"$tmp/server.py" <<'PY'
import http.server, sys, os, html
d, title, author = sys.argv[2], sys.argv[3], sys.argv[4]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, ctype, body, extra=()):
        self.send_response(code); self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(body)))
        for k, v in extra: self.send_header(k, v)
        self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        p = self.path
        if p.startswith("/art/"):
            name = p[5:]
            tags = f'<meta name="citation_title" content="{html.escape(title)}"/><meta name="citation_author" content="{html.escape(author)}"/>'
            if name != "nopdf": tags += f'<meta name="citation_pdf_url" content="http://127.0.0.1:{self.server.server_port}/{name}.pdf"/>'
            return self.send(200, "text/html", f"<html><head>{tags}</head></html>".encode())
        if p == "/login.pdf": return self.send(302, "text/html", b"", [("Location", "/index/login?source=%2Flogin.pdf")])
        if p == "/index/login": return self.send(200, "text/html", b"<html>login</html>")
        if p == "/forbidden.pdf": return self.send(403, "text/html", b"no")
        if p == "/viewer.pdf": return self.send(200, "text/html", b"<html>galley viewer page</html>")
        name = p.lstrip("/")
        if name.startswith("api/"): name = "good.pdf"
        f = os.path.join(d, os.path.basename(name if name != "cookie.pdf" else "good.pdf"))
        if os.path.isfile(f):
            extra = [("Set-Cookie", "OJSSID=abc; Path=/")] if name == "cookie.pdf" else []
            return self.send(200, "application/pdf", open(f, "rb").read(), extra)
        self.send(404, "text/plain", b"nope")
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_port)); s.serve_forever()
PY
python3 -I "$tmp/server.py" "$tmp/port" "$tmp" "$TITLE" "$AUTHOR" &
srv=$!
for _ in $(seq 50); do [ -s "$tmp/port" ] && break; sleep 0.1; done
port="$(cat "$tmp/port")"; base="http://127.0.0.1:$port"
cp-check() { "$root/scripts/check-pdf.sh" "$@"; }

echo "--- page mode (the URL citation_pdf_url gives is followed)"
chk "good article: PASS" 0 "RESULT: PASS" -- cp-check "$base/art/good"
chk "cookie on the download: PASS with INFO, not FAIL" 0 "INFO  the download sets a cookie" -- cp-check "$base/art/cookie"
chk "title wrapped over two lines still matches" 0 "PASS  title on page 1" -- cp-check "$base/art/wrapped"
chk "redirect to login: FAIL" 1 "redirects to a login page" -- cp-check "$base/art/login"
chk "403: FAIL" 1 "HTTP 403" -- cp-check "$base/art/forbidden"
chk "HTML viewer page instead of the PDF: FAIL" 1 "not application/pdf" -- cp-check "$base/art/viewer"
chk "no citation_pdf_url: FAIL" 1 "citation_pdf_url missing" -- cp-check "$base/art/nopdf"
chk "title missing from page 1: FAIL" 1 "title not found" -- cp-check "$base/art/notitle"
chk "author missing from page 1: FAIL" 1 "author not found" -- cp-check "$base/art/noauthor"
chk "image-only PDF: FAIL" 1 "no extractable text" -- cp-check "$base/art/image"
chk "5 MB or more: FAIL" 1 "5 MB or more" -- cp-check "$base/art/big"
chk "a PDF under an /api/ path is not a public route: FAIL" 1 "private or API route" -- cp-check --pdf "$base/api/x.pdf" --title "$TITLE"
echo "--- file mode and normalisation"
chk "file: good PDF" 0 "" -- cp-check --pdf "$tmp/good.pdf" --title "$TITLE" --author "$AUTHOR"
chk "file: not a PDF" 1 "not a PDF" -- cp-check --pdf "$tmp/notpdf.pdf" --title "$TITLE"
chk "file: case and spacing differences match" 0 "" -- cp-check --pdf "$tmp/good.pdf" --title "  observations OF open   research practice " --author "PLACEHOLDER author"
chk "usage error exits 2" 2 "" -- cp-check
unit() { python3 -I - "$root/scripts/lib" <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
from pdf_match import missing
assert missing("Beneﬁts of ﬂuent oﬃce work", ["Benefits of fluent office"]) == [], "ligatures"
assert missing("Obser-\nvation of  Open\nResearch", ["observation of open research"]) == [], "hyphen and wrap"
assert missing("Another Title", ["Real Title"]) == ["Real Title"], "negative"
PY
}
chk "pdf_match: ligatures, line-end hyphen, wrapped lines; a miss is reported" 0 "" -- unit

echo
if [ "$fail" -eq 0 ]; then echo "check-pdf tests: all passed"; else echo "check-pdf tests: $fail FAILED"; exit 1; fi
