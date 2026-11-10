# Phase 6 notes: discoverability

Branch `claude/phase6-discoverability`. Everything below is `VERIFIED-SANDBOX 2026-11-10` unless marked otherwise; nothing has run on a VPS or against Google.

## What was built

| Task | Files | Tests |
|---|---|---|
| Commit 0 (Phase 5 follow-ups) | `docs/DEPLOY.md` (scheduler check, Cloudflare purge), `docs/HANDOVER.md` (stub), `docs/PHASE5-NOTES.md` (mutation results) | the three Phase 5 mutations are recorded in `PHASE5-NOTES.md` |
| 6.2 | `scripts/check-pdf.sh`, `scripts/lib/pdf_match.py` | `scripts/test-check-pdf.sh` (17 checks) |
| 6.3 | `scripts/check-discovery.sh`, `scripts/lib/discovery.py`, `infra/robots/*`, Nginx snippets, `ROBOTS_MODE` in provisioning, `[oai] repository_id` live-config check | `scripts/test-check-discovery.sh` (26), Nginx harness discovery section, `test-check-live-config.sh`, preflight |
| 6.4 | `docs/SEARCH-CONSOLE.md` | none (human steps) |
| 6.5 | the canonical INFO line in `check-discovery.sh`; checklist section 10; decision D25 | `test-check-discovery.sh` |
| `citation_doi` | `scripts/check-citation-meta.sh` | `scripts/test-check-citation-meta.sh` |

## Facts read from the 3.5.0-6 source

- **`robots.txt`:** OJS ships `ojs-core/robots.txt` with only `User-agent: *` / `Disallow: /cache/` and **no Sitemap line**. Our Nginx serves its own file from the `ERRORS_ROOT` directory (`location = /robots.txt`), because core is not edited.
- **Sitemap** (`pages/sitemap/SitemapHandler.php`, `lib/pkp/pages/sitemap/PKPSitemapHandler.php`): `/index/sitemap` is a sitemap **index** listing each journal's `/JOURNAL/sitemap`. The journal sitemap lists the home page, `user/register`, `login`, the announcements index and each announcement, `about`, `about/submissions`, `about/contact`, every navigation-menu page, `search`, `issue/current`, `issue/archive`, each published issue, each published article's abstract page and each galley's view page. It omits: PDF download URLs, unpublished items, and any published article not assigned to an issue (articles are found through their issue).
- **OAI `Identify` `adminEmail`** is the **journal contact email** (`classes/oai/ojs/JournalOAI.php:128`), falling back to the site contact email (line 131). It is public. Sandbox value: `contact@example.invalid` (placeholder). Decision **D23**.
- **OAI identifiers** are `oai:<repository_id>:article/<id>`; `[oai] repository_id` ships as `ojs.pkp.sfu.ca`, and the installer takes it from the install answer. Our provisioning answer is `HOST` (the main host). The sandbox holds `sandbox.invalid`. Decision **D24**; `check-live-config.py` now fails an empty, shipped or non-host value (3 mutation tests).
- **`citation_doi`** is added only when a DOI exists (`plugins/generic/googleScholar/GoogleScholarPlugin.php`: `if ($doi = $publication->getDoi())`), and `getDoi()` returns the stored DOI **bare** (`10.NNNN/suffix`), not a URL. The check therefore: absent passes; present and empty **FAILS**; present and not bare is a **WARN**.

## Decisions taken in the build (flag if you disagree)

- `ROBOTS_MODE` has **no default**; the provisioning script refuses a missing or unknown value (both tested).
- The robots check uses Python `urllib.robotparser` for `*` and `Googlebot` on the home page, both sitemaps, OAI, an article, the galley download, an issue page and the theme CSS/JS.
- `check-pdf.sh` follows the URL `citation_pdf_url` names (the **download** URL; the galley view URL returns an HTML viewer page), sends no cookies, and treats `Set-Cookie` as INFO.
- `check-discovery.sh` uses `sed -n 1p` instead of `head -n1` in pipelines (a `head` under `pipefail` gave exit 141 on the first mismatch; the test that found it is kept).
- `make check-discovery` **fails in the sandbox on purpose**: the sandbox serves OJS's own `robots.txt` (no Sitemap line). The Nginx harness checks the rendered one.

## Final chroot provisioning run (after the last commit)

Two full runs on a fresh Ubuntu 24.04 chroot: the second ends `changed: 0`, `--check` on the provisioned machine says `changed: 0`, no secret was printed, and `check-live-config.py` passed on the provisioned config with **22 checks, 0 failed** (including the new `[oai] repository_id` check). The staging `robots.txt` and the `X-Robots-Tag` header were installed. **One assertion failed and was my error:** it expected `repository_id = journal.example.org`, but the installer writes the value quoted. The config was right; the assertion now accepts the quoted form (checked against the produced line, not re-run end to end).
