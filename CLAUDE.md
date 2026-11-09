# World Open Research Journal (WORJ): project memory

New academic journal website on **Open Journal Systems (OJS) 3.5** (PHP 8.2+, MariaDB, Nginx, Ubuntu 24.04 LTS, Cloudflare Free in front).
This repo holds everything we author: a child theme, optional plugin, config templates, placeholder content, infra scripts, QA tooling. **OJS core is never committed.** It is fetched by `scripts/fetch-ojs.sh` at a pinned version.

Read before starting work: `docs/01-SPEC.md` (what), `docs/02-ARCHITECTURE.md` (how), `docs/03-TASKS.md` (order of work). Read others only when the task needs them.

## Hard rules
1. **Placeholders only for now.** Journal name is "World Open Research Journal". Everything else (ISSN, DOI prefix, editors, policies, indexing claims, articles) is a clearly marked placeholder. See `docs/05-PLACEHOLDERS.md`. Never invent an ISSN, DOI, impact factor, indexing badge, editor, affiliation or citation.
2. **Logo**: the provided file is in the repo root (`worj.jpeg`). Never edit or overwrite it. Derive variants into `ojs/plugins/themes/worj/assets/`.
3. **Theme only extends, never forks.** `worj` is a child of OJS `default` theme. Do not edit anything under `ojs-core/` (gitignored).
4. **Verify against OJS 3.5 docs** (https://docs.pkp.sfu.ca/) before using any hook, template variable or CLI tool. OJS 3.4 and 3.5 differ; search results often describe 3.3. If unsure, say so in the PR and stop rather than guess.
5. **Scope guard.** Out of scope: migration, custom payment/APC, multi-journal, large custom plugins. The awards feature is built as static pages plus announcements (see `docs/04-AWARDS.md`) unless the human says the plugin option was approved.
6. **No secrets in git.** Credentials, SMTP passwords and API keys go in `.env` (gitignored). Provide `.env.example` only.
7. **Never claim a check passed unless you ran it.** Paste the command and its tail output in the PR description.

## Commands
- `make setup`: fetch pinned OJS into `ojs-core/` and link the theme
- `make lint`: shellcheck, php -l, stylelint, markdownlint
- `make eval`: run the locked QA scorer (`autoresearch/eval/`), prints a single `SCORE: <float>` line
- `make check-placeholders`: lists every remaining placeholder (must be empty at launch)

## Conventions
- Commits: `type(scope): summary`. One concern per commit.
- Theme code: PHP namespaced classes, Smarty templates, plain CSS with custom properties, no frameworks, no CDN or remote fonts (self-host). Total theme CSS+JS budget: 150 KB uncompressed.
- Accessibility target: WCAG 2.2 AA. Semantic HTML first.
- Every public page must work with JavaScript disabled.

## Working style (keeps usage low)
- Plan first for anything touching more than 3 files; list the files, wait for approval.
- Reference files by path, don't paste them. `/clear` between unrelated tasks.
- Update this file only after the same correction has been needed twice. Keep it under 200 lines.
