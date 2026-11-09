# EVAL-SPEC: what `make eval` must do (implemented in Phase 0/6, then locked)

The evaluator must be deterministic, finish in under 5 minutes, and be **read-only to the loop**. Implement it as `autoresearch/eval/run.sh` calling small scripts. Lock it after Phase 8 by committing a checksum file `autoresearch/eval/CHECKSUMS` and making `run.sh` refuse to run if checksums differ (the human regenerates it intentionally).

## Inputs
Rendered pages from either (a) a local OJS instance seeded with fixtures, or (b) static HTML fixtures in `ojs/fixtures/html/` if the sandbox cannot run OJS (see `docs/ENV-REPORT.md`). Pages: home, about, issue archive, current issue, article landing (3 samples), submission page, login, awards, 404. Viewports: 320, 768, 1280 px.

## Hard gates (any failure => `GATES: FAIL`, score ignored)
1. Citation tags complete and correct on article fixtures (`scripts/check-citation-meta.sh`).
2. No horizontal overflow at 320 px on any page.
3. No external network requests from any page (fonts, scripts, images, analytics).
4. No critical or serious accessibility violations (axe-core via headless browser) on any page.
5. Theme CSS + JS size <= 150 KB uncompressed.
6. Pages work with JS disabled (nav reachable, content present).
7. No `[PLACEHOLDER` banner removed by the loop (banners are content, not theme).

## Score (0 to 100)
| Component | Weight | Source |
|---|---|---|
| Accessibility | 30 | Lighthouse a11y mean across pages, mobile |
| SEO and metadata | 25 | Lighthouse SEO mean + citation tag completeness |
| Performance | 20 | Lighthouse performance mean, mobile, throttled |
| Best practices | 10 | Lighthouse best-practices mean |
| Responsiveness | 10 | pass rate of layout assertions at 320/768/1280 |
| Simplicity | 5 | 5 minus penalty for bytes added vs baseline (min 0) |

Report each component on separate lines and the total on `SCORE:`. Use the median of 3 runs for Lighthouse to reduce noise; treat deltas under 0.3 as noise.

## Tooling fallbacks
- If Chromium or Lighthouse cannot run in the sandbox, implement components with static analysers: axe via jsdom is limited, so mark Lighthouse-based components `SKIPPED` and re-weight the remaining ones; log the limitation in `docs/ENV-REPORT.md`. Do **not** substitute made-up numbers.
- Pin all tool versions in `autoresearch/eval/package.json` with a lockfile.

## Output format (last lines of stdout)
```
COMPONENT a11y=..., seo=..., perf=..., bp=..., resp=..., simplicity=...
GATES: PASS
SCORE: 87.4
```
