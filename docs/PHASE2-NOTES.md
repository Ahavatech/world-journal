# Phase 2 notes (resume point)

A cleared session resumes from this file and the git history, not from the chat. Task definitions are in `docs/03-TASKS.md`; this records what was decided and where Phase 2 stands.

## Approved decisions

- **2.8 evaluator: yes.** Build `autoresearch/eval/` as its own commit after 2.7. Hard gates from `autoresearch/EVAL-SPEC.md`: overflow at 320 px, external requests, axe, CSS+JS size, JS-off. Print the component lines, `GATES:` and `SCORE:` in the spec's exact format. Anything it cannot measure honestly is `SKIPPED`, no invented numbers. Skip Lighthouse if it adds a lot of weight or flakiness; a working gate set beats a fragile full score. **No checksum lock** (that is Phase 8).
- **Real Phase 3.3 sample issue: done.** 3 fake articles, `Sample Article N`, `Placeholder Author`, watermarked text-selectable PDFs (about 2.7 KB each), `ojs/fixtures/manifest.json` with `sample=true`. Generator: `scripts/sample-issue.py`; import: `scripts/sandbox-import-sample.sh`. The sandbox database is never committed. Mark 3.3 done in the Phase 2 PR.
- **6.1 pulled forward: done.** `scripts/check-citation-meta.sh`; `make check-citation`. 6.2 to 6.4 stay in Phase 6. The date tag is `citation_publication_date` or `citation_date` (OJS 3.5.0-6 emits `citation_date`). `--placeholder-issn` reports a missing ISSN as `EXPECTED-MISSING`; the launch gate (8.3) requires removing that flag.
- **Fonts:** Source Serif 4 and Source Sans 3 (variable, Latin). 108,268 bytes of woff2 is accepted. Keep the italic. **Add no more weights or files.** Swappable through `tokens.css` and `fonts.css`; licence notices in the theme's `NOTICE`.
- **Logo on a light band:** the JPEG's white background sits on white or very light bands; no thresholding or cut-outs. On the light grey hero band `mix-blend-mode: multiply` lets the white take the band colour. The "ask the client for an SVG or transparent PNG" item in `docs/BRAND.md` stays open.
- **Tagline:** "Advancing Knowledge Globally" is baked into the client's logo file, so it is not fabricated, and it is not repeated as text (no `[PLACEHOLDER: tagline]` line). Below 48em the hero uses the header crop (no tagline) so it is not illegible. The human will ask the client whether it is their official tagline.
- **Budget:** the 150 KB CSS+JS budget applies to the theme's own files (16 KB at last measure). The whole-page total (about 458 KB) includes jQuery and jQuery UI, which stay because OJS core frontend forms depend on them. Say this in the PR; do not trim further.
- **Highlights slider:** not built. Task 4.1 carries the line "Highlights are not used by this theme; use Announcements".
- **Awards card:** theme option `showAwardsCard`, default off. Turn it on when 3.4 builds `/awards`.
- **Stylelint:** `selector-class-pattern`, `selector-id-pattern`, `no-descending-specificity` and range-notation media queries are relaxed (OJS's own names, layered overrides, older browsers).

## Where it stands

| Step | State |
|---|---|
| 2.1 skeleton | done |
| 2.2 tokens, fonts, logo variants | done |
| 2.3 header, CSS-only nav, footer | done |
| 2.4 homepage | done |
| 2.5 about page and sidebar (zero blocks, blocks, configured-but-empty) | done |
| 2.6 article, issue, archive (overflow fixed; stress-tested with a long title, DOI-like string and URL at 320, 768, 1280, then reverted) | done |
| 2.7 accessibility pass (results in `docs/A11Y-REPORT.md`) | done |
| 2.8 evaluator (`make eval`, about 110 s; gates 1 to 7, score re-scaled, `perf` SKIPPED; see `autoresearch/eval/README.md`) | done |
| PR | one PR at the end of Phase 2: open it next (see the list below) |

Per phase: `make lint`, `scripts/test-nav.js` (15 of 15 must pass) and `make check-citation` after every theme commit. Report the viewport checks at 320, 768 and 1280, the CSS+JS and font sizes, the axe results and the citation output in the PR.

## Open decisions for the human

- **Meta description (decided: no hook).** OJS core emits `<meta name="description">` only on the journal homepage and only when the journal's search description is set (a Task 4.1 step). The Lighthouse SEO score of 92 on inner pages comes from OJS core and is not chased: a theme hook would touch the metadata area we agreed to leave alone, for a small gain.
- **404 page:** needs a static page served by nginx in Phase 5 (core prints a bare `<h1>`).
- **Parent theme dependency:** the article and issue templates still come from the parent theme; only the CSS is replaced.
- **Lighthouse performance** is not measured; decide later whether to run it manually before launch.

## Evaluator rules added after review

- **Gate 8: no uncaught JavaScript error or console error on any page.** Proven by reintroducing the parent `main.js` (the Swiper bug): the gate failed with `uncaught: Swiper is not defined` on every page and exit 1; restored, it passes.
- **Component set.** `make eval` prints `COMPONENTS: ran=... skipped=...` and `COMPONENT-SET: MATCHES|DIFFERS`. `baseline.json` records `a11y,seo,bp,resp,simplicity`. The Phase 9 loop refuses to start when it says `DIFFERS` (rule in `autoresearch/program.md`). Lighthouse stays optional.

## Resume commands

```bash
make setup            # fetch OJS 3.5.0-6 into ojs-core/ and link the theme
make sandbox-up       # apt packages, MariaDB, php-fpm, nginx, install OJS
make sandbox-seed     # journal "worj", theme, sample issue
node scripts/sandbox-api.js GET /worj/api/v1/contexts/1/theme
```

The sandbox needs the `world-journal` environment network allowlist (`pkp.sfu.ca`, `docs.pkp.sfu.ca`). Announcements and the description in the sandbox journal are throwaway placeholders created through the API, not committed.

## Things learned (do not rediscover)

- 2.7 tooling lives in `autoresearch/eval/` (`npm ci` there): `checks/axe.js`, `checks/a11y-manual.js`, `checks/forms-errors.js`, `lib/pages.js`. The 404 page is flagged `core: true` (OJS prints a bare `<h1>`); its findings are reported, not failed. Phase 5 needs a static 404 page.
- The parent `main.js` ran `new Swiper()` unconditionally and threw on every page after Swiper was removed; `assets/js/forms.js` replaces it. Check the browser console for errors, not only layout.
- Parent options removed from the admin form: typography, baseColour, showDescriptionInJournalIndex, useHomepageImageAsHeader. `displayStats` stays (the parent article template reads it). Stored values live under the parent plugin name (`defaultthemeplugin`) and are harmless.
- Focus colour is `#2f7bf5`: it holds 3:1 against white, panel grey, navy and dark navy. The old `#0b5fff` was 2.80:1 against navy buttons.
- Parent CSS often wins on specificity (`.page_register #formErrors .pkp_form_error_list a`); prefix with `body .pkp_structure_main` or use the same id/class chain.
- Public pages have zero inline scripts and event handlers.
- **The flaky form-error check was a race in the test, not the page (resolved).** `waitForLoadState('load')` after a click resolves at once because the previous page is already loaded, so the check ran while the new page was still parsing and `forms.js` had not executed (no `role`, no focus, no `aria-describedby`). Reproduced with `EVAL_CPU_THROTTLE=8` (and the CDP throttle in a scratch script at 4x, 8x and 16x). Fix: register `page.waitForEvent('load')` before the click, which waits for the new page's own load event; no sleeps, no retries, no loosened assertion; the `networkidle` waits added earlier were removed because they only hid the race. Evidence: old pattern at 8x throttle failed 3 of 3 runs; fixed pattern passed 10 of 10 at normal speed and 10 of 10 at 8x. The same pattern in `scripts/sandbox-seed.js` and `scripts/sandbox-api.js` (login before an API call) was fixed too.

- Any grid or flex container that is also a parent-theme clearfix (`.pkp_helpers_clear`) needs its `::before`/`::after` set to `content: none`, or the pseudo-elements become grid items (seen on `.pkp_structure_content` and `.obj_article_details .row`).
- Stress test recipe: `node scripts/sandbox-api.js PUT /worj/api/v1/submissions/3/publications/3 '{"title":{"en":"...long..."}}'`, check overflow, then PUT the original title and abstract back.
- Sidebar states are set with `SANDBOX_SIDEBAR=blocks|none|empty node scripts/sandbox-seed.js`. All three are verified: no empty aside and no empty grid column when blocks render nothing (`:has(> .pkp_structure_sidebar)` for the grid, `{if $sidebarCode|trim}` for the aside).
- A fresh journal does not enable the Make a Submission block plugin (the sandbox script enables it). Task 4.1 must include enabling it.
- The About page has no photo and uses no stock image: text at a 46rem measure, with the sidebar beside it when blocks exist.

- The parent sets `html { font-size: 14px }`; `base.css` resets it to 100%.
- The parent styles `.pkp_navigation_user` and `.pkp_navigation_primary` heavily. The worj header passes its own `ulClass` to `load_menu` to avoid that.
- Parent layout is float-based with pseudo-element borders and negative margins (`.pkp_structure_main:first-child:last-child`, `.obj_issue_toc .section`, `.cmp_announcements`). `layout.css` and `components.css` replace them.
- `headerHead.tpl` is not overridden: the `citation_*` tags come from the googleScholar generic plugin through hooks, not the theme.
- The parent theme's appearance options (typography, base colour, homepage image, show summary) still appear in the admin form but have no effect on this theme. Open question for the human: remove them with `removeOption()`?
- The `Makefile` uses `-o pipefail` so a failing check in a pipeline fails the target.
