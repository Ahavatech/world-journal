#!/usr/bin/env bash
# Tests for scripts/check-discovery.sh against a configurable fake site (no OJS, no sandbox needed).
# Each scenario starts a tiny HTTP server; every failure mode must make the check exit 1, every INFO/WARN must not.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v xmllint >/dev/null || { echo "missing xmllint (apt-get install libxml2-utils)"; exit 2; }
tmp="$(mktemp -d)"
srv=""
stop() { [ -z "$srv" ] || { kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null; srv=""; }; }
trap 'stop; rm -rf -- "${tmp:?}"' EXIT
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }

cat >"$tmp/server.py" <<'PY'
import http.server, json, sys
cfg = json.loads(sys.argv[2])
G = dict(robots="User-agent: *\nDisallow: /cache/\n\nSitemap: http://{host}/index/sitemap\n", xrobots="", meta_robots=False,
         sitemap_host=None, articles=True, issues=True, oai_error=False, oai_not_xml=False, admin="journal@example.net",
         rid=None, title="A Real Title", canonical="", status_sitemap=200)
G.update(cfg)
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def out(self, code, ctype, body, extra=()):
        b = body.encode(); self.send_response(code); self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(b)))
        if G["xrobots"]: self.send_header("X-Robots-Tag", G["xrobots"])
        for k, v in extra: self.send_header(k, v)
        self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        host = self.headers["Host"]; sh = G["sitemap_host"] or host; p, _, q = self.path.partition("?")
        rid = G["rid"] or host.split(":")[0]
        if p == "/robots.txt": return self.out(200, "text/plain", G["robots"].replace("{host}", host))
        if p == "/index/sitemap":
            return self.out(200, "application/xml", f'<?xml version="1.0"?><sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><sitemap><loc>http://{host}/j/sitemap</loc></sitemap></sitemapindex>')
        if p == "/j/sitemap":
            u = [f"http://{sh}/j"]
            if G["issues"]: u += [f"http://{sh}/j/issue/view/1"]
            if G["articles"]: u += [f"http://{sh}/j/article/view/1", f"http://{sh}/j/article/view/1/1"]
            u = "".join(f"<url><loc>{x}</loc></url>" for x in u)
            return self.out(G["status_sitemap"], "application/xml", f'<?xml version="1.0"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{u}</urlset>')
        if p == "/j/article/view/1":
            m = '<meta name="robots" content="noindex">' if G["meta_robots"] else ""
            c = f'<link rel="canonical" href="http://{host}/j/article/view/1"/>' if G["canonical"] else ""
            return self.out(200, "text/html", f'<html><head>{m}{c}<meta name="citation_pdf_url" content="http://{host}/j/article/download/1/1"/><link rel="stylesheet" href="/plugins/themes/worj/css/a.css"></head></html>')
        if p == "/j/":
            return self.out(200, "text/html", '<html><head><link rel="stylesheet" href="/plugins/themes/worj/css/a.css"></head></html>')
        if p == "/j/oai":
            if G["oai_not_xml"]: return self.out(200, "text/html", "<html>hello")
            v = dict(x.split("=", 1) for x in q.split("&") if "=" in x).get("verb", "")
            ns = 'xmlns="http://www.openarchives.org/OAI/2.0/" xmlns:dc="http://purl.org/dc/elements/1.1/"'
            if G["oai_error"]: body = '<error code="badVerb">no</error>'
            elif v == "Identify": body = f"<Identify><repositoryName>R</repositoryName><baseURL>http://{host}/j/oai</baseURL><adminEmail>{G['admin']}</adminEmail></Identify>"
            elif v == "ListMetadataFormats": body = "<ListMetadataFormats><metadataFormat><metadataPrefix>oai_dc</metadataPrefix></metadataFormat></ListMetadataFormats>"
            elif v == "ListIdentifiers": body = f"<ListIdentifiers><header><identifier>oai:{rid}:article/1</identifier></header></ListIdentifiers>"
            elif v == "GetRecord": body = f"<GetRecord><record><header><identifier>oai:{rid}:article/1</identifier></header><metadata><dc:title>{G['title']}</dc:title></metadata></record></GetRecord>"
            else: body = f"<ListRecords><record><header><identifier>oai:{rid}:article/1</identifier></header><metadata><dc:title>{G['title']}</dc:title></metadata></record></ListRecords>"
            return self.out(200, "text/xml", f'<?xml version="1.0"?><OAI-PMH {ns}>{body}</OAI-PMH>')
        self.out(404, "text/plain", "no")
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_port)); s.serve_forever()
PY
# scenario "label" want_exit "text-or-empty" 'json-config' [check-discovery args...]
scn() {
  local label="$1" want="$2" text="$3" cfg="$4"; shift 4
  : >"$tmp/port"; stop
  python3 -I "$tmp/server.py" "$tmp/port" "$cfg" & srv=$!
  for _ in $(seq 50); do [ -s "$tmp/port" ] && break; sleep 0.1; done
  local out rc
  out="$("$root/scripts/check-discovery.sh" --curl-arg --noproxy --curl-arg '*' "$@" "http://127.0.0.1:$(cat "$tmp/port")" 2>&1)"; rc=$?
  if [ "$rc" = "$want" ] && { [ -z "$text" ] || grep -qF -- "$text" <<<"$out"; }; then ok "$label"; else bad "$label (exit $rc, wanted $want${text:+, text "$text"})"; printf '      %s\n' "${out//$'\n'/$'\n      '}" | head -30; fi
}
P=(--robots-mode production); S=(--robots-mode staging)

echo "--- production mode"
scn "a healthy site passes" 0 "RESULT: PASS" '{}' "${P[@]}"
scn "whole site disallowed: FAIL" 1 "disallows the whole site" '{"robots":"User-agent: *\nDisallow: /\n"}' "${P[@]}"
scn "X-Robots-Tag noindex: FAIL" 1 "X-Robots-Tag noindex is sent" '{"xrobots":"noindex, nofollow"}' "${P[@]}"
scn "noindex meta tag on the article: FAIL" 1 "noindex meta tag" '{"meta_robots":true}' "${P[@]}"
scn "article pages blocked for Googlebot only: FAIL" 1 "blocks Googlebot" '{"robots":"User-agent: *\nDisallow: /cache/\n\nUser-agent: Googlebot\nDisallow: /j/article/\n\nSitemap: http://x/s\n"}' "${P[@]}"
scn "theme CSS/JS blocked: FAIL" 1 "blocks" '{"robots":"User-agent: *\nDisallow: /plugins/themes/\nSitemap: http://x/s\n"}' "${P[@]}"
scn "the OAI endpoint blocked: FAIL" 1 "blocks" '{"robots":"User-agent: *\nDisallow: /j/oai\nSitemap: http://x/s\n"}' "${P[@]}"
scn "no Sitemap line: FAIL" 1 "no Sitemap: line" '{"robots":"User-agent: *\nDisallow: /cache/\n"}' "${P[@]}"
scn "sitemap names another host: FAIL" 1 "another host" '{"sitemap_host":"other.example"}' "${P[@]}"
scn "sitemap without articles: FAIL" 1 "lists no article pages" '{"articles":false}' "${P[@]}"
scn "sitemap without issues: FAIL" 1 "lists no issue pages" '{"issues":false}' "${P[@]}"
scn "OAI returns an error element: FAIL" 1 "returned an error" '{"oai_error":true}' "${P[@]}"
scn "OAI returns HTML: FAIL" 1 "is not well-formed XML" '{"oai_not_xml":true}' "${P[@]}"
echo "--- INFO and WARN never fail"
scn "personal adminEmail: WARN, exit 0" 0 "WARN  OAI adminEmail" '{"admin":"someone@gmail.com"}' "${P[@]}"
scn "empty adminEmail: WARN, exit 0" 0 "EMPTY adminEmail" '{"admin":""}' "${P[@]}"
scn "no canonical tag: INFO line, exit 0" 0 "INFO  no canonical tag on article pages at 3.5.0-6, decision pending" '{}' "${P[@]}"
scn "canonical present: INFO, exit 0" 0 "INFO  canonical tag present" '{"canonical":"1"}' "${P[@]}"
echo "--- staging mode"
scn "staging closed and noindex: PASS" 0 "RESULT: PASS" '{"robots":"User-agent: *\nDisallow: /\n","xrobots":"noindex, nofollow"}' "${S[@]}"
scn "staging but crawlable robots.txt: FAIL" 1 "robots.txt leaves the site crawlable" '{"xrobots":"noindex"}' "${S[@]}"
scn "staging without the noindex header: FAIL" 1 "no X-Robots-Tag noindex header" '{"robots":"User-agent: *\nDisallow: /\n"}' "${S[@]}"
echo "--- --launch"
scn "launch with clean content passes" 0 "RESULT: PASS" '{"title":"Effects of Light on Plant Growth"}' "${P[@]}" --launch
scn "launch: 'Sample Article' in OAI: FAIL" 1 "placeholder content is discoverable" '{"title":"Sample Article 1"}' "${P[@]}" --launch
scn "launch: 'Placeholder Author' in OAI: FAIL" 1 "Placeholder Author" '{"title":"Placeholder Author wrote this"}' "${P[@]}" --launch
scn "without --launch the same content only passes" 0 "RESULT: PASS" '{"title":"Sample Article 1"}' "${P[@]}"
scn "launch: repository identifier is not the host: FAIL" 1 "repository identifier" '{"rid":"ojs.pkp.sfu.ca"}' "${P[@]}" --launch
scn "launch: robots.txt without a Sitemap line FAILS (never a warning)" 1 "no Sitemap: line" '{"robots":"User-agent: *\nDisallow: /cache/\n","title":"Effects of Light on Plant Growth"}' "${P[@]}" --launch
echo "--- usage"
out="$("$root/scripts/check-discovery.sh" --robots-mode staging --launch http://127.0.0.1:1 2>&1)"; rc=$?
if [ "$rc" = 2 ]; then ok "--launch with --robots-mode staging is a usage error (exit 2)"; else bad "--launch with staging: exit $rc"; fi
out="$("$root/scripts/check-discovery.sh" http://127.0.0.1:1 2>&1)"; rc=$?
if [ "$rc" = 2 ]; then ok "--robots-mode is required (exit 2)"; else bad "missing --robots-mode: exit $rc"; fi

echo
if [ "$fail" -eq 0 ]; then echo "check-discovery tests: all passed"; else echo "check-discovery tests: $fail FAILED"; exit 1; fi
