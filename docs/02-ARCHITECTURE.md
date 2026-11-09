# 02. Architecture and environment

## What Claude Code can and cannot do here
Claude Code on the web works inside a cloud sandbox on a clone of the GitHub repo. It **can**: write theme code, templates, CSS, scripts, config templates, placeholder content, docs, CI; run linters and tests; open PRs. It **cannot**: SSH into the Hostinger VPS, buy or configure domains, DNS, Cloudflare, Search Console or Crossref accounts, or click through the OJS admin UI on production. Anything in those categories becomes a **human checklist item** in `docs/ADMIN-SETUP-CHECKLIST.md`, never a pretend-done task.

Task 0.1 must probe the sandbox (php, composer, node, mariadb, docker, chromium availability and network reach to pkp.sfu.ca) and record the result in `docs/ENV-REPORT.md`. All later task plans adapt to it. If OJS cannot run in the sandbox, develop the theme against static HTML fixtures (`ojs/fixtures/html/`) and leave the live OJS integration check to the human on a staging VPS.

## Repo layout
```
/
  worj.jpeg                       provided by client (root, immutable)
  CLAUDE.md
  Makefile
  .env.example
  docs/                          these documents
  autoresearch/                  loop program + locked evaluator
    program.md
    results.tsv
    eval/                        LOCKED: agent must not edit
  ojs/
    plugins/themes/worj/         child theme of OJS `default`
    plugins/generic/             only if awards plugin option approved
    config/config.inc.php.template
    content/                     placeholder pages (HTML), policies, announcements
    fixtures/                    sample issue and 3 clearly fake articles (+ generated PDFs)
  infra/
    nginx/                       server block, security headers, rewrites
    php/                         php.ini overrides
    mariadb/                     tuning
    provision-ubuntu.sh          idempotent, human runs on VPS
    backup.sh, restore.sh, cron.d/
  scripts/
    fetch-ojs.sh                 pinned version + checksum
    check-placeholders.sh
    check-citation-meta.sh
  .github/workflows/ci.yml
  ojs-core/                      gitignored, created by `make setup`
```

## Stack decisions (fixed by the signed scope)
Ubuntu 24.04 LTS, Nginx, PHP 8.2+ (confirm against the exact OJS 3.5.x patch release), MariaDB (confirm compatibility with that release), Let's Encrypt, Cloudflare Free (DNS and basic protection), Hostinger KVM 1 VPS. Pin the OJS patch release in `scripts/fetch-ojs.sh` and in `docs/ENV-REPORT.md`. Check the requirements at https://docs.pkp.sfu.ca/ and the OJS release notes, not from memory.

## Theme
- Folder `ojs/plugins/themes/worj/`; internal identifier `worj` (code only, not shown to users).
- Child of `default`. Register styles/scripts via the ThemePlugin API; override only the templates needed (header, footer, index, about, sidebar blocks).
- Self-host fonts and icons. No remote requests.
- Colours as CSS custom properties; light theme only for v1.
- Required template areas: site header with logo, primary nav, hero, announcements list, issue preview, article landing (preserve the stock metadata output), footer.
- **Never remove or reformat the OJS head metadata hooks**: Google Scholar tags are emitted there. The citation check script (`scripts/check-citation-meta.sh`) guards this.

## Server hardening requirements (for `infra/`)
HTTPS redirect; HSTS; `files_dir` outside web root; deny dotfiles and `config.inc.php`; deny PHP execution in uploads; upload size and `memory_limit` tuned for PDF uploads; fail2ban optional; unattended-upgrades on; Cloudflare real-IP handling; gzip/brotli; cache headers for static assets only.

## Backups
Nightly DB dump and `files_dir` plus `public/` archive, retention 14 daily and 8 weekly, copy off the VPS (`rclone` to client-owned storage, remote name from `.env`), and `restore.sh` that restores into a scratch DB and verifies the OJS login page loads. A restore test is a launch-gate item.

## Config template
`config.inc.php.template` with placeholders for DB, base URL, `restful_urls = On`, SMTP, salt (generated at provisioning, never committed), `files_dir`, `show_stacktrace = Off`, `session_cookie_secure = On`, `force_ssl = On`, OAI enabled. Verify each key name against the shipped `config.TEMPLATE.inc.php` of the pinned release.

## CI
GitHub Actions: lint, `make check-placeholders` (warn only until Phase 8), shellcheck, PHP syntax, markdownlint, and `make eval` if the sandbox probe showed it is runnable in CI.
