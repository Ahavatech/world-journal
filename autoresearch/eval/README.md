# autoresearch/eval: the QA scorer

`make eval` runs `run.sh`. It is read-only: it never changes the theme or the sandbox, and it does not edit its own baseline. Setup:

```bash
make sandbox-up sandbox-seed          # local OJS with the sample issue (sidebar state: blocks)
cd autoresearch/eval && npm ci        # pinned axe-core, @axe-core/playwright, pngjs, lighthouse
make eval                             # about 2 minutes
```

The last three lines are `COMPONENT ...`, `GATES: PASS|FAIL ...` and `SCORE: <0..100>`. A failed gate prints `SCORE: 0.0` and exits 1.

| Gate | Check | Where |
|---|---|---|
| 1 | citation tags on the three sample articles | `scripts/check-citation-meta.sh --placeholder-issn` (Phase 8.3 removes the flag) |
| 2 | no horizontal overflow at 320 px, every page | `checks/gates.js` |
| 3 | no external network request, every page at 320 and 1280 px | `checks/gates.js` |
| 4 | axe, WCAG 2.0/2.1/2.2 A and AA, 11 pages at 320 and 1280 px (stricter than the spec's critical and serious) | `checks/axe.js` |
| 5 | the theme's own CSS + JS at most 150 KB uncompressed (fonts and whole-page totals are reported, not gated) | `checks/gates.js` |
| 6 | every page works with JavaScript off: menu reachable, no dead toggle, h1 and main text present | `checks/gates.js` |
| 7 | no page shows fewer `[PLACEHOLDER` markers than `baseline.json` | `checks/gates.js` |

The 404 page is core-owned (OJS prints a bare `<h1>`); its findings are reported and do not fail the run (`lib/pages.js`, `core: true`).

## Score

`a11y`, `seo` and `bp` come from Lighthouse (accessibility, SEO, best-practices; one run per page, which is deterministic for those three). `seo` is the mean of Lighthouse SEO and citation-tag completeness. `resp` is the pass rate of five layout assertions per page at 320, 768 and 1280 px. `simplicity` loses half a point per KB of theme CSS+JS above the baseline.

**`perf` is always `SKIPPED`**: Lighthouse performance needs throttled median-of-three runs, which is over the 5-minute budget and the flaky category. If Lighthouse is not installed, `a11y`, `seo` and `bp` are `SKIPPED` too. The score is re-scaled over the components that were measured; nothing is estimated.

## Baseline

`baseline.json` holds the theme byte count and the per-page placeholder counts. Rewrite it only after a deliberate review: `node checks/gates.js --update-baseline`. The checksum lock for this directory is a Phase 8 task and is not written yet.

## Other checks (not part of `make eval`)

`checks/a11y-manual.js` (structure, keyboard, target size, reflow, contrast, motion) and `checks/forms-errors.js` back `docs/A11Y-REPORT.md`.
