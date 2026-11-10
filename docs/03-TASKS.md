# 03. Task plan

Work phase by phase. For every phase: plan first, wait for approval, then execute, then open one PR. Each task lists a **model** to keep Claude Pro usage low (Haiku = mechanical, Sonnet = default, Opus = planning or genuinely stuck only). Use `/model opusplan` for phases marked PLAN.

| Phase | Goal | Model |
|---|---|---|
| 0 | Probe environment, scaffold repo | Haiku |
| 1 | Tooling: fetch OJS, Makefile, CI | Sonnet |
| 2 | Theme | PLAN with Opus, build with Sonnet |
| 3 | Placeholder content and awards pages | Haiku for bulk text, Sonnet for templates |
| 4 | OJS configuration and admin checklist | Sonnet |
| 5 | Infra scripts | Sonnet (PLAN with Opus once) |
| 6 | Discoverability checks | Sonnet |
| 7 | DOI / Crossref readiness | Haiku |
| 8 | QA, launch gate, handover | Sonnet |
| 9 | Optional polish with autoresearch loop | Sonnet or Haiku, never Opus |

## Phase 0: Probe and scaffold
- 0.1 Probe sandbox (php, composer, node, mariadb, docker, chromium, network reach to pkp.sfu.ca). Write `docs/ENV-REPORT.md`. **Done when** each tool shows present/absent with version.
- 0.2 Create folder layout from `02-ARCHITECTURE.md`, `.gitignore` (ojs-core, .env, node_modules), `.env.example`, empty `results.tsv` with header.
- 0.3 Locate the logo in repo root; record filename, dimensions, format and dominant colours in `docs/BRAND.md`. Do not modify it.

## Phase 1: Tooling
- 1.1 `scripts/fetch-ojs.sh`: download the pinned OJS 3.5.x tarball from the official PKP site, verify checksum, extract to `ojs-core/`. Fail loudly if checksum is not available; ask the human for it.
- 1.2 `Makefile` targets from `CLAUDE.md`.
- 1.3 `ci.yml`.
- **Done when** `make setup && make lint` run clean or the failure is documented with reason.

## Phase 2: Theme (PLAN first)
- 2.1 Theme skeleton, registers, activates under the pinned OJS (if runnable), otherwise passes `php -l` and is installable per PKP theming docs.
- 2.2 Design tokens from logo (`assets/css/tokens.css`).
- 2.3 Header and nav; footer; responsive menu without JS dependency.
- 2.4 Homepage per `01-SPEC.md` section 5.
- 2.5 About page layout (image beside text), sidebar blocks, no Indexing block.
- 2.6 Article landing, issue and archive styling (do not touch metadata hooks).
- 2.7 Accessibility pass: focus states, skip links, contrast, landmarks, reduced motion.
- **Done when** fixtures render at 320, 768, 1280 px without horizontal scroll and `make eval` hard gates pass.

## Phase 3: Placeholder content
- 3.1 Generate the 13 policy and info pages in `ojs/content/pages/*.html`. Each begins with a visible banner `[PLACEHOLDER: replace with client-approved text]` and contains neutral structure only (headings and short prompts), **not** invented policy claims.
- 3.2 Editorial team: 5 clearly fake entries ("Placeholder Editor-in-Chief") in `ojs/content/editorial-team.html`.
- 3.3 **Done in Phase 2 (PR #3).** Sample issue with 3 fake articles (`ojs/fixtures/`): titles `Sample Article 1..3`, author `Placeholder Author`, PDFs generated with a diagonal "SAMPLE: NOT A REAL PUBLICATION" watermark, selectable text, under 1 MB. Mark every record `sample=true` in a manifest so `check-placeholders` can find and remove them.
- 3.4 Awards pages and announcement templates per `04-AWARDS.md`.
- 3.5 `scripts/check-placeholders.sh` scans for `[PLACEHOLDER`, `Sample Article`, `Placeholder Author`, `example.org`, `lorem`, and prints file:line.

## Phase 4: OJS configuration
- 4.1 `docs/ADMIN-SETUP-CHECKLIST.md`: ordered, click-by-click settings for: journal masthead, contact, sections, submission checklist, roles, review forms and reminders, email templates, notifications, DOI settings (disabled until credentials), licence, search settings, static pages, announcements, navigation menus, theme activation and options. Each step has an expected visible result. Mark steps `HUMAN`. Include a line: "Highlights are not used by this theme; use Announcements" (the theme does not render the homepage highlights slider, so an editor who adds one would see nothing). Also (from Phase 3, see `docs/PHASE3-NOTES.md`): retitle the built-in "Editorial Masthead" menu item to "Editorial Team" and decide `enableEnrollmentMasthead` (off with the placeholder text, or on with real users in masthead roles); assign the custom pages (aims and scope, the five policies, awards) to the primary and About menus; `ojs/content/` and `ojs/fixtures/` never ship. Importers on production: take a backup first and run `scripts/import-pages.php` once (see `docs/DEPLOY.md`). Also: set the journal's search description so the homepage emits a meta description. Also: enable the "Make a Submission" block plugin (a new journal does not have it enabled) and choose the sidebar blocks; no Indexing block until the journal is genuinely indexed. Also: turn on the theme option `showAwardsCard` once the Awards page exists at `/awards` (it is off by default so the homepage never links to a missing page).
- 4.2 Where OJS offers a CLI or import (Native XML import of issues and articles, user import), script it in `scripts/` and document usage; verify tool names against the pinned release first.
- 4.3 `config.inc.php.template`.
- **Phase 4 status:** 4.1, 4.2 and 4.3 are done in the sandbox; see `docs/PHASE4-NOTES.md` for what stays `UNVERIFIED` and why (nothing has run on a VPS).

## Phase 5: Infra scripts (PLAN first; Claude cannot run these on the VPS)
- 5.1 `provision-ubuntu.sh` (idempotent; packages, PHP-FPM tuning, MariaDB, Nginx, certbot, firewall, unattended-upgrades).
- 5.1b Installer defaults (found in Phase 4: the CLI install leaves `salt` at the public default `YouMustSetASecretKeyHere!!`, `api_key_secret` empty, `allowed_hosts` as `[""]` and `time_zone` blank): the provision script **generates a strong salt and API key secret from a secure random source** (for example `openssl rand` or `/dev/urandom`), writes them straight into `config.inc.php` (mode 640, owned by root and the PHP group), and **never** puts them in git, in the shell history, on a command line or in a log; it sets `allowed_hosts` to the real domain and `time_zone` deliberately. A repo test proves the template cannot produce the default salt (`scripts/test-config-template.sh`).
- 5.2 Nginx server block and security headers; PHP ini; MariaDB tuning for 4 GB RAM. Also: a static, accessible 404 page served with `fastcgi_intercept_errors on; error_page 404 ...`, because OJS core prints a bare `<h1>404 Not Found</h1>` with no `lang`, title or landmarks that no theme can change (see `docs/A11Y-REPORT.md`). The public pages currently have no inline scripts or inline event handlers, so a Content-Security-Policy with `script-src 'self'` looks feasible; verify before enabling it.
- 5.2b One URL form per page: nginx redirects `http` to `https`, strips the `index.php` forms (`/index.php/worj/...` to `/worj/...`) and sends other duplicate forms to one (article page vs its galley URLs are different pages, so check what OJS links to and do not redirect between them). Verify each redirect with `curl -I`.
- 5.2c Hardening (OJS core has no two-factor authentication; see `docs/ADMIN-SETUP-CHECKLIST.md` 9.3, 9.3a): Cloudflare rate limiting on the login and registration paths (`/login`, `/user/register`, and the `/index/` forms); no site administrator role for editors, who get **Journal Manager**; a **documented administrator recovery path** (how access is regained if the only administrator is locked out), tested on staging; the bot-protection decision D21 (reCAPTCHA conflicts with the no-external-requests rule; ALTCHA needs JavaScript and a CSP that allows `blob:` workers).
- 5.3 `backup.sh`, `restore.sh`, cron; off-box copy via rclone.
- 5.4 `docs/DEPLOY.md`: exact human steps, rollback steps, DNS and Cloudflare steps (SSL mode "Full (strict)"), smoke tests.
- **Done when** `shellcheck` clean and a dry-run mode (`--check`) prints actions without changing anything.

## Phase 6: Discoverability
- 6.1 `scripts/check-citation-meta.sh <url|file>`: fetches or reads an article landing page and verifies every required `citation_*` tag is present, non-empty, one `citation_author` per author, date tag is `citation_publication_date` or `citation_date` (OJS 3.5.0-6 emits `citation_date`) in format `YYYY/MM/DD`, `citation_pdf_url` returns a PDF. A missing `citation_issn` is reported as `EXPECTED-MISSING` only with `--placeholder-issn` (see 8.3).
- 6.2 `scripts/check-pdf.sh`: text extractable (`pdftotext`), size under 5 MB, title on page 1.
- 6.3 `robots.txt`, sitemap check, OAI-PMH check (`verb=Identify`, `ListRecords`).
- 6.5 Canonical check, **INFO only, never a failure**: report `INFO: no canonical tag on article pages at 3.5.0-6, decision pending` while none is emitted. Google Scholar needs the `citation_*` tags, not a canonical. A localhost sandbox is a weak test because OJS builds canonicals from `base_url`, so re-check on a staging install with the real domain and HTTPS. If staging still shows none, bring it back to the human as a decision; the likely fix is a small, gated hook that adds only a `<link rel="canonical">`, with `make check-citation` run before and after to show the citation tags did not change. Do not add the hook without that decision.
- 6.4 `docs/SEARCH-CONSOLE.md`: human steps for DNS verification and sitemap submission, plus a URL Inspection of one real article page (and one galley URL) to see which URL Google selects as canonical.

## Phase 7: DOI and Crossref readiness (mostly blocked on client)
- 7.1 Read `docs/06-INDEXING-ROADMAP.md`. Produce `docs/DOI-SETUP.md`: what the client must obtain, what to enter in OJS, DOI suffix pattern proposal, test-deposit procedure.
- **Blocked until** the client provides publisher Crossref membership or sponsor details. Do not fake credentials.

## Phase 8: QA, launch gate, handover
- 8.1 Full `make eval`; fix failures.
- 8.2 Manual end-to-end test script `docs/QA-SCRIPT.md` (author submits, editor assigns, reviewer reviews, decision, revision, accept, copyedit, publish) with expected results. Its expected-results list must also cover, from `docs/ADMIN-SETUP-CHECKLIST.md`: **3.3** the submission checklist as the author sees it in the wizard (and that it is the client-approved text), **3.6** the Disable Submissions state as the author sees it, and **6.7** the reviewer invitation email rendered through a mail catcher or the real provider (wording read by a person, no timeframe or policy claim).
- 8.3 Launch gate checklist: placeholders empty; fixtures removed; real ISSN and policies in, and the `--placeholder-issn` flag removed from every `check-citation-meta.sh` call (Makefile `check-citation`, the eval gate) so a missing ISSN fails; SMTP verified; backup and restore tested; HTTPS and redirects; robots and sitemap; Search Console verified; the placeholder step in `.github/workflows/ci.yml` hard-fails (remove `continue-on-error: true` and the `::warning::` wrapper, so the green tick means the check passed); **every default-text setting is either replaced or explicitly confirmed by the client in the decision table, including the ones the scan could not see (the shipped open access policy text and the LOCKSS and CLOCKSS licence texts did not appear on any public page I crawled, so they are NOT shown clean: the client confirms or replaces each, and the human checks where, if anywhere, they are printed)** (OJS ships policy wording, `docs/ADMIN-SETUP-CHECKLIST.md` D10, D13, D14; `scripts/check-placeholders.sh --url` reports shipped default wording, and it must be empty or each hit confirmed); **a real validation email sent through the production provider arrives in an inbox** (with `require_validation = On` a broken mail setup blocks registration); SPF, DKIM and DMARC pass for the sending domain; **a client reviewer has read every enabled email template in full**; **a live-config check** that reads the production `config.inc.php` and fails if `salt` is the shipped default (`YouMustSetASecretKeyHere!!`) or empty, `api_key_secret` is empty, `allowed_hosts` is empty or `[""]`, `time_zone` is blank, or `installed` is not `On`; admin account hardened (2FA if supported, unique strong password in client's password manager).
- 8.4 `docs/HANDOVER.md` (admin guide, how to publish an issue, who to contact, 14-day support terms).

## Phase 9: Optional autoresearch polish
Only after Phase 8.1 passes. Follow `autoresearch/program.md`.
