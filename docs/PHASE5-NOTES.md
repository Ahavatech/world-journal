# Phase 5 notes (resume point)

A cleared session resumes from this file, `docs/PHASE4-NOTES.md`, `docs/03-TASKS.md` (Phase 5), `docs/ENV-REPORT.md` (Phase 5 environment check) and the git history. Branch: `claude/phase5-infra` (off `origin/main`; never restart an old branch name; no force-push). The approved plan is summarised here because plan files do not survive a clear.

## Rules (from the approved plan, 2026-11-10)

- **Policy:** provisioning is checked with shellcheck, `--check`, config syntax checks, stub tests, a debootstrap chroot run (no services, firewall or SSH, run twice: the second must report `changed: 0`) and a local Nginx in front of the sandbox OJS. **Every production step is `UNVERIFIED (not run on VPS)`.** Never claim a tested provisioning. No Docker daemon here; the Cloudflare IP list URL is blocked in the sandbox (fixtures only).
- Sessions: commits 1 to 8 in session 1, commits 9 to 12 in session 2. This file is updated after commits 3 and 8.
- **Secrets:** generated with `openssl rand` or Python `secrets`, never in argv, `set -x`, history or logs; values go to tools on stdin; the DB password only in `config.inc.php` and a root-only 600 defaults file; the installer's initial admin password comes from the operator's root-only env file or a one-time prompt; the installer answers file is deleted by trap on exit (including failure) and a test proves it is gone and the password appears nowhere.
- **Backups are always encrypted off the server:** `age` public-key encryption (only the public key on the server; the client holds the private key); mode 600 is acceptable for the LOCAL copy only; `DEPLOY.md` says decryption happens off the server and the restore rehearsal is done by the operator with the private key; remote bucket versioning or object lock is strongly recommended; `backup.sh` checks the dump is non-empty and a plausible size and raises a failure alert; `restore.sh` refuses when the scratch DB name or connection target equals the production DB in the live config (tested with a deliberate collision).
- **Cloudflare IP ranges** fetched at provision time; on failure keep the old file and exit non-zero; the provision stage fails with a clear message on first run if no ranges exist yet (never real-IP handling unset).
- **Admin recovery:** a database-level password reset written from the 3.5.0-6 source (exact hashing function and table) and tested on the sandbox; state who holds the break-glass administrator credential.
- **Extra tests:** a `.php` file uploaded into `public/` is not executed through Nginx; `files_dir` content is unreachable by URL while a public PDF galley still downloads through OJS; Nginx serves no `config.inc.php`, `.git`, `.env` or backup file from any path.
- **CSP:** report-only gives no protection; `DEPLOY.md` says so; not counted as hardening until enforced after a clean crawl of public and admin pages.
- **Decisions stay human (`[CLIENT DECISION]`, default shown):** main host; certificate method (Cloudflare Origin CA vs certbot DNS-01, with the paused-proxy caveat); firewall (open during setup, then Cloudflare ranges only, noting it blocks direct-IP testing); HSTS (short max-age, staged, no preload at launch); swap and time zone (never assume a zone); Cloudflare Access on admin (optional, must not block `/api/`); bucket versioning or object lock.
- **Back to the owner before the Phase 5 PR:** curl matrix output (404 page, JSON 404 on `/api/`, POST not redirected); debootstrap run twice with `--check` before and after tree snapshots; the secret-leak sampler results; the backup and restore round trip with the collision refusal; the final `UNVERIFIED (not run on VPS)` list.

## Commit plan and progress

| # | Commit | State |
|---|---|---|
| 1 | `docs(env)` environment check and policy | done |
| 2 | `render-template.py`, `set-ojs-config.py` + tests (27 cases) | done |
| 3 | `check-live-config.py` + negative fixtures (20 cases) | done |
| 4 | PHP ini, FPM pool, MariaDB tuning + `make infra-test` (real php, php-fpm -t, throwaway mariadbd) | done |
| 5 | Nginx site + snippets + static 404 page, `scripts/render-nginx.sh` (`nginx -t` passes, broken snippet rejected) | done |
| 6 | `scripts/test-nginx-harness.sh` + `scripts/test-nginx-browser.js` (`make infra-test-nginx`): 96 checks | done |
| 7 | `scripts/update-cloudflare-ips.sh` + fixtures, 38 cases in `make lint` | done |
| 8 | `scripts/backup.sh`, `scripts/restore.sh`, cron and logrotate templates, `make infra-test-backup`: 75 checks | done |
| 9 to 12 | provision script, SSH and firewall with dead-man, chroot harness, `DEPLOY.md` (session 2) | pending |

## Findings so far

- `scripts/check-live-config.py` run on the real sandbox install (CLI installer output) fails 9 of 18 checks: salt (the public default), `api_key_secret` (empty), host not listed in `allowed_hosts`, `time_zone` blank, `base_url` not https, `force_ssl`, `force_login_ssl`, `show_stacktrace` On and file mode 664. This is the sandbox, not production, but it shows the check sees exactly what the installer leaves.
- The config template header no longer contains a literal `@@TOKEN@@`, so the renderer can treat any leftover token as an error.
- `render-template.py` and `set-ojs-config.py` take values on stdin only; passing a value on the command line is refused (exit 2).

## Session 1 results (commits 1 to 8)

**Nginx harness (`make infra-test-nginx`, 96 checks, all pass).** Instance A is the production render on 18080/18443 in front of the sandbox OJS. Curl matrix: `http` to `https` 301; `www` to the main host (port 80 and 443); `/index.php/worj/about` to `/worj/about` for GET and HEAD with the query kept; `/index.php` to `/`; a POST to an index.php URL is NOT redirected; unknown Host dropped (curl 52 on port 80, TLS refused on 443); `config.inc.php`, `config.TEMPLATE.inc.php`, `.git/config`, `.env`, `.htaccess`, `tools/`, `lib/pkp/tools/`, `cache/`, `registry/`, `classes/`, `locale/*.po`, a `.sql.bak` in `public/`, `composer.json` all 404; an uploaded `public/*.php` is not executed and not shown (also with path info); `files_dir` content unreachable by URL and by traversal, a real private PDF not served by path, while the public PDF galley still downloads through OJS (`%PDF`); security headers on PHP pages, static files and 404s; CSP is Report-Only on public paths and absent on `/management`, `/api/`; static assets cache 7 days, HTML pages do not; the static 404 page (status 404, `lang`, title, main) for an unknown route and for a denied path; `/api/v1/nonexistent` still returns a JSON 404 (not the HTML page); `/_errors/404.html` is internal; the address in `CF-Connecting-IP` is what Nginx logs when a trusted proxy sends it, the peer address otherwise. Browser: axe on the static 404 page at 1280 and 320 px (0 violations, 9 rules passed, no overflow); every public and admin page loads all of its assets (no 4xx), apart from the Plugin Gallery grid which needs `pkp.sfu.ca` from php-fpm (known sandbox limit).

**Bug found by the crawl and fixed:** my first deny rule blocked `lib/pkp/lib/vendor/`, which holds TinyMCE and Plupload (the admin editor and uploads); they came back as the 404 page and were refused (`nosniff`). The directory is no longer denied (its PHP is unreachable anyway; its README and composer files match the file-type rules).

**CSP finding:** with a test-only ENFORCING copy of the policy, **6 violations on 16 public pages** (the contact page: inline script and style; the galley viewer: inline script and style) and 28 on 7 admin pages (inline script, inline style). So **CSP stays Report-Only and is not a hardening measure** until those are fixed or allow-listed and a crawl is clean. Admin paths send no policy.

**Harness gotchas:** the sandbox sets `HTTPS_PROXY` for the agent; curl needs `--noproxy '*'` and Chromium must start with no `*proxy*` variable in its environment, otherwise `journal.example.org` is sent through the proxy and reset. The worker needs read access to the temp tree (mode 755). Access logs must use `$request_uri`, not `$uri` (rewritten to `/index.php/...`).

**Backup and restore (`make infra-test-backup`, 75 checks, all pass).** Everything leaving the work directory is age-encrypted, the local copy included (mode 600 in a 700 directory); only the public key is on the server and a private key in the settings is refused. Real run on the sandbox database: 132 tables, 1.8 MB dump; the ciphertext holds no SQL and no password; no process command line held the database password during the run (a `/proc/*/cmdline` sampler confirmed `mysqldump` ran); the log holds no password. Off-box copy through an rclone local remote is byte-identical and its size is verified. Failures raise an alert (FAILED marker, syslog, `WORJ_ALERT_CMD`) and upload nothing: tested with an empty dump, a tiny dump, a truncated dump (no completion line) and a failing mysqldump, plus a backup under 20% of the previous size. Retention 14 daily and 8 weekly (newest kept, sidecars removed) and remote pruning by age (older than 15 and 57 days deleted, newer kept) with `rclone delete`, never `sync`. Restore rehearsal with the private key: decrypt, manifest check, scratch database (132 tables, 1 user), temporary 600 config, `php -S` on localhost, login page 200 with the username field, scratch database dropped, original config and code tree untouched; a wrong key and a corrupted bundle fail. **Guard:** refuses when the scratch name equals the production name (checked for the right reason), when it lacks "restore", when it has SQL characters, or when the live config is missing; the real sandbox database kept its user.

**Decisions made in code (to confirm in `DEPLOY.md`):** HSTS starts at 300 seconds with no preload or includeSubDomains; IPv4 only on the origin; static cache 7 days; PHP-FPM pool sized for 4 GB; **`open_basedir` is not set** (it would need its own tested path list; optional hardening later); **OJS cron lines are not installed** (the shipped web runners stay on; moving to `php lib/pkp/tools/scheduler.php run` is an untested operator decision); the Nginx `/api/` location is excluded from error interception.

**Not tested here (every one `UNVERIFIED (not run on VPS)`):** the real Cloudflare fetch and ranges, SSL mode and rate limiting, certbot, systemd and cron execution of the jobs, a real rclone remote, age key handling by the client, performance of the 4 GB tuning, anything on a VPS.

## Session 2 (commits 9 to 12)

Provision script (`--check`, OS refusal, secret-safe stages, installer answers file removed by trap, admin password from the root-only env file or a prompt, non-default admin username, first-run Cloudflare failure stops the stage), firewall and SSH stages with the dead-man revert, the debootstrap chroot idempotency run (twice, `changed: 0`) with `--check` before and after tree snapshots and the secret-leak sampler, the admin password-reset path written from the 3.5.0-6 source and tested on the sandbox, and `docs/DEPLOY.md`.
