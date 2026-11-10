# Phase 3 notes (resume point)

A cleared session resumes from this file, `docs/PHASE2-NOTES.md` and the git history. Task definitions are in `docs/03-TASKS.md`. Plan: `/root/.claude/plans/` (revision 2, approved with the review changes below).

## What was decided (revision 2 of the plan)

- **Built-ins before custom pages.** Standalone pages are OJS custom navigation-menu pages, not the static-pages plugin (its template prints the title as an `h2` with no `h1` and is not themeable; custom pages render an `h1` and breadcrumbs through a core template). Several "pages" are journal settings that OJS renders itself. `ojs/content/pages.json` records, per page, the mechanism and what was checked.
- **Editorial Team is the built-in `/about/editorialMasthead`.** In 3.5.0-6, `/about/editorialTeam` is gone (404; migration `I9937_EditorialTeamToEditorialHistory`). With `enableEnrollmentMasthead` off the page renders the setting `editorialHistory` (with an `h1`); the schema default is **on**, which lists real masthead users instead. The sandbox turns it off and holds the 5 placeholder entries. Aims and Scope has no built-in in 3.5.0-6, so it is a custom page.
- **Importers are safe by default.** `scripts/import-pages.php` is create-only: it skips existing pages, **always** leaves a page whose placeholder banner is gone (a human edited it), and `--force-sandbox` (refresh a still-placeholder page) refuses to run unless `base_url` is localhost. `scripts/sandbox-content.js` (settings texts, REST login) refuses to run unless `SANDBOX_URL` is localhost, writes only empty settings, and with `--force-sandbox` refreshes only those still showing the banner or a placeholder value.
- **Prompts ask, never suggest.** No review model, licence name, indexer, number or duration anywhere. Bulk text was drafted by a Haiku subagent from a fixed skeleton; **every file was reviewed by hand** and 10 prompts were rewritten because they presupposed an answer ("declare", "in place", "data controller", "in one short paragraph"). The claims lint is a backstop, not a guarantee.
- **Claims lint** (`scripts/check-content-claims.py`, in `make lint`): banned words anywhere, digits only in running prose (`<p>`, `<li>`), relative links only, banner required; exact-entry allowlist (`scripts/content-claims-allow.txt`, one entry: the word "Year" in a category name from `04-AWARDS.md`) where stale entries fail.
- **`check-placeholders.sh`** (repo mode) lists `file:line` and exits 1 while anything remains. The theme's own fallback markers are excused by exact file + exact string entries (`scripts/placeholder-allowlist.txt`), never a directory; stale entries fail. **`--url BASE`** scans the rendered site (sitemap, nav/footer/sidebar links, article pages, PDF galleys through `pdftotext`, titles and meta tags; a 404 on a nav link is a failure).
- **Awards card** stays default **off** in the theme. The seed turns it on only if `/awards` returns 200 (it did; the card renders and links to a 200 page).

## What was built

| Task | Result |
|---|---|
| 3.1 pages | 13 files in `ojs/content/pages/` (about, aims and scope, peer review, publication ethics, open access, copyright and licensing, archiving, plagiarism and similarity, privacy, author guidelines, and the three information texts) |
| 3.2 editorial team | `ojs/content/editorial-team.html`, 5 clearly fake entries |
| 3.3 sample issue | done in Phase 2 (PR #3) |
| 3.4 awards | `ojs/content/awards/` (awards, categories, guidelines, winners) and `ojs/content/announcements/` (3 templates); relative links verified (0 broken) |
| 3.5 check | `scripts/check-placeholders.sh`, `scripts/check-placeholders-url.py`, `make check-placeholders`, `make check-placeholders-url` |

Sandbox: `make sandbox-up sandbox-seed` now also imports all of this. A fresh journal is emptied of OJS default text first (or `SANDBOX_RESET_CONTENT=1`), because default text is correctly treated as "not a placeholder, leave it".

## Evidence at the last commit

- 19 pages return 200 with exactly one `h1`; axe 0 violations on 14 pages at 320 and 1280 px; the placeholder banner on the Awards page measures 8.31:1; nav test 15 of 15; `make check-citation` passes; form-error check passes; `make eval`: `GATES: PASS`, `SCORE: 98.8`, `COMPONENT-SET: MATCHES`.
- Negative tests: claims lint (fake indexing claim, digit in prose, licence name, review-model hint, absolute link all caught; a heading numeral not; stale allowlist entry fails); importer (second run 11 skipped; edited page untouched even with `--force-sandbox`; non-localhost refused with exit 3); `check-placeholders` (stray marker flagged; stale and wildcard allowlist entries fail; synthetic sites for 404 nav link, clean site, placeholder in title and meta).
- Rendered scan of the sandbox: 39 pages and 3 PDFs scanned, 394 findings (expected until real content), 0 failures. `make check-placeholders`: 144 lines in 26 files, 9 theme fallback lines excused.

## Decision: flat slugs for the Awards sub-pages (done)

OJS's own sitemap listed the slash sub-pages with an encoded slash (`/worj/awards%2Fcategories`), and both forms returned 200, so each had two live URLs. The three sub-pages are now `awards-categories`, `awards-guidelines` and `awards-winners` (`/awards` stays the parent). Checked in the sandbox after recreating the pages: the sitemap lists the flat slugs, the old slash and `%2F` forms return 404, and the homepage card and the in-page links point to the new URLs. No nginx workaround is needed.

**OJS emits no canonical tag on custom pages** (checked on the awards pages). Not fixed. **Article pages did not emit one either** in the sandbox (`/worj/article/view/1`: 200, citation tags present, 0 canonical tags; no `canonical` link in the shipped templates under `lib/pkp/templates` or `templates`). So the Phase 6 check is expected to fail on 3.5.0-6 as shipped, and fixing it means a head hook, which touches the metadata area Phase 2 agreed to leave alone: the human decides (decided: do not fix now; re-check on staging with the real domain and HTTPS, because OJS builds canonicals from `base_url`; Phase 6.5 reports INFO, not failure). Phase 6 must check that **article pages**, the page type that matters for indexing, do emit `<link rel="canonical">` (task 6.5 in `docs/03-TASKS.md`).

## For the human (not done, on purpose)

- **`autoresearch/eval/baseline.json` is not updated.** The new pages change the placeholder counts: home 11 to 12, about 4 to 10, submissions 3 to 17, contact 3 to 5, and new entries awards 18, editorial 9, peer-review 13. Approve the diff, then run `node autoresearch/eval/checks/gates.js --update-baseline` and commit it.
- **`ojs/content/` and `ojs/fixtures/` must not ship.** Phase 8 gate: `make check-placeholders` empty, and `check-placeholders.sh --url` empty on the real site.
- Per-prompt `[PLACEHOLDER: ...]` markers are plain visible text inside the page; only the page-level banner is styled as a badge.
- OJS accepted `contact@example.invalid` and every placeholder value on save (no rejection to record).

## Hand-offs to Phase 4

- Retitle the built-in menu item "Editorial Masthead" to "Editorial Team"; decide `enableEnrollmentMasthead` (off with text, or on with real users in masthead roles).
- Assign the custom pages to the primary and About menus (menu assignment is not scripted).
- Turn on the theme option `showAwardsCard` on the real site only once `/awards` exists there.
- Task 4.2 needs a **production-safe, create-only** way to load the settings texts: `sandbox-content.js` is localhost-only by design, so either paste the texts from `ojs/content/` by hand (HUMAN steps) or write a separate settings importer with the same banner rule. `scripts/import-pages.php` is already create-only and can run on the VPS without `--force-sandbox`.
