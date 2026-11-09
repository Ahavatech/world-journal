# 01. Product spec

## 1. Identity
| Field | Value |
|---|---|
| Journal name | World Open Research Journal |
| Logo | `logo.*` in repo root (do not modify) |
| Publisher | `[PLACEHOLDER: publisher name]` |
| Domain | `[PLACEHOLDER: domain]` (use `example.org` in configs) |
| ISSN / eISSN | `[PLACEHOLDER: pending]` (never invent) |
| Language | English |
| Access model | Open access, licence `[PLACEHOLDER: e.g. CC BY 4.0, client to confirm]` |
| Scope text | `[PLACEHOLDER: aims and scope]` (client supplies) |

## 2. Visual direction
The client gave two reference sites for **structure only**, not for content, claims or branding:
- smsjournals.com/index.php/SAMRIDDHI
- pspac.info/index.php/dlbh/about

Take from them: classic OJS information architecture (top nav, About page with image beside intro text, right-hand sidebar blocks). Do **not** copy their text, images, logos, indexing badges or scope statements.

Design: clean, scholarly, high contrast, generous whitespace, serif headings and sans body (self-hosted fonts). Derive the palette from the logo and expose it as CSS custom properties (`--worj-primary`, `--worj-accent`, ...) so the client can retune in one place.

## 3. Information architecture
Top navigation: **Home, About the Journal, Current, Archives, Editorial Team, Submissions, Research Awards, Contact**, then Search, Register, Login.
About dropdown: About the Journal, Aims and Scope, Peer Review Process, Publication Ethics and Misconduct, Open Access Policy, Copyright and Licensing, Archiving Policy, Plagiarism/Similarity Policy, Privacy Statement.

Footer: journal name, publisher placeholder, ISSN placeholder, licence, contact, "Published with OJS" link, privacy link.

Right sidebar (article, archive and about pages): Information (For Readers, For Authors, For Librarians), Make a Submission button, Keywords block, Language. **No "Indexing" block until the journal is genuinely indexed** (see `05-PLACEHOLDERS.md`).

## 4. Pages (all with placeholder text marked as such)
About the Journal; Aims and Scope; Editorial Team; Contact; Publication Ethics and Misconduct; Peer Review Process; Open Access Policy; Copyright and Licensing Policy; Archiving Policy; Plagiarism/Similarity Policy; Privacy Statement; Author Guidelines; Information for Readers, Authors and Librarians; plus Research Awards (`04-AWARDS.md`).

## 5. Homepage
Hero with logo, journal name and a tagline placeholder; buttons: Make a Submission, Current Issue; short About block; latest 3 Announcements; Research Awards call-out card; Current Issue preview (cover placeholder plus article list).

## 6. Functional requirements (mostly OJS settings, not code)
Author registration and submission with checklist; reviewer invitation and review form; editorial decisions and revision rounds; copyediting and production stages; SMTP email notifications; issue creation and publication; article landing pages and PDF galleys; search; announcements. Record the exact settings in `docs/ADMIN-SETUP-CHECKLIST.md` (Task 4.1).

## 7. Discoverability requirements
1. One landing page per article, abstract visible without login.
2. Page-source tags: `citation_title`, `citation_author` (one per author), `citation_publication_date`, `citation_journal_title`, `citation_issn`, `citation_volume`, `citation_issue`, `citation_firstpage`, `citation_lastpage`, `citation_pdf_url`, `citation_doi` when assigned.
3. PDFs: selectable text, title and authors on page 1, under 5 MB.
4. Sitemap, robots.txt, Search Console verification, OAI-PMH enabled.
5. Canonical URLs, HTTPS only.

## 8. Non-functional
Responsive from 320 px. Lighthouse mobile: Accessibility >= 95, SEO >= 95, Best Practices >= 95, Performance >= 85. No third-party scripts on public pages (optional GA4 behind a config flag, off by default).

## 9. Acceptance
Launch gate: `make eval` passes all hard gates, `make check-placeholders` is empty, and the human signs off Phase 8 in `03-TASKS.md`.
