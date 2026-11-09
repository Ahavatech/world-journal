# autoresearch/program.md: the loop for polishing the WORJ theme

Adapted from Karpathy's autoresearch pattern: a human writes this file; the agent edits **one narrow surface**, runs a **fixed-budget, locked evaluator**, keeps the change only if the score improves, otherwise reverts, and repeats.

## When to use this
Only in Phase 9, after the normal build passes `make eval`. The loop tunes quality (accessibility, SEO metadata correctness, performance, responsiveness). It is not for building features, writing content or touching infra. Those use the normal plan-then-build workflow.

## Files
| Role | Path | Agent may edit? |
|---|---|---|
| Instructions | `autoresearch/program.md`, `autoresearch/EVAL-SPEC.md` | NO |
| Evaluator | `autoresearch/eval/**`, `Makefile` target `eval` | NO |
| Editable surface | `ojs/plugins/themes/worj/assets/css/**`, `.../assets/js/**`, `.../templates/**` | YES |
| Log | `autoresearch/results.tsv` | append only |
| Everything else | | NO |

Before every run, verify `git diff --name-only` contains only editable-surface paths and `results.tsv`. If not, revert and log `invalid`.

## Metric
`make eval` prints `SCORE: <0..100>` (higher is better) and `GATES: PASS|FAIL <reason>`. See `EVAL-SPEC.md`. A change is kept only if **GATES: PASS** and `SCORE >= best + 0.3`. A change that gives equal score with **less code** (fewer lines or bytes) is also kept (simplicity wins ties).

## One experiment
1. Read the last 15 lines of `results.tsv` and `git log --oneline -n 10`. Do not re-read the whole history.
2. Pick **one** hypothesis (e.g. "raise link contrast on sidebar", "replace render-blocking CSS import", "add width/height to hero image to stop layout shift"). Write it in one line.
3. Make the smallest edit that tests it.
4. Run `make eval`. Budget: 5 minutes. If it exceeds 10, kill it and log `timeout`.
5. Append a row: `exp_id<TAB>score<TAB>gates<TAB>status<TAB>description` with status `keep`, `discard`, `invalid` or `timeout`.
6. `keep`: commit `exp-<id>: <description>`. Otherwise `git checkout -- .` to revert.
7. Next experiment.

## Limits for a Claude Pro plan (overrides "run forever")
- **Maximum 6 experiments per session.** Then stop and summarise: best score, kept changes, ideas not yet tried.
- Stop immediately on any usage-limit message; the log and git history are the memory, so nothing is lost.
- Run `/clear` after every 3 experiments; resume from step 1.
- Model: **Sonnet** for the loop; **Haiku** for pure CSS/ARIA tweaks. Do not switch to Opus inside the loop.
- Do not ask questions mid-loop. If blocked, log `blocked: <reason>` and stop.

## Forbidden (each is an automatic revert and a note in `results.tsv`)
- Editing the evaluator, thresholds, fixtures or this file.
- Hard-coding values to satisfy a check (e.g. static meta tags in templates, hidden text for SEO, faking ARIA labels).
- Removing OJS metadata hooks, removing sidebar or navigation items, hiding content from keyboard or screen-reader users.
- Adding third-party requests, remote fonts, tracking, or any dependency.
- Overfitting to a single fixture page (changes must be generic CSS/template improvements).

## Principles
Prefer deletions over additions. A small gain that adds a lot of complexity is not worth keeping. Never trade accessibility for performance score.
