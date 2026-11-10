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

## Session 2 results (commits 9 to 12 and the admin reset)

| # | Piece | Evidence |
|---|---|---|
| reset | `scripts/reset-ojs-admin-password.sh` (from the 3.5.0-6 source: `password_hash` bcrypt cost 12, `users.password`, `must_change_password`) | 16 checks on the sandbox: the NEW password logs in through the real OJS login form, the old one does not, a short password, an unknown user, SQL characters and a password on the command line are refused, the original row is restored |
| 9 | `scripts/provision-ubuntu.sh` + `scripts/lib/provision-common.sh`, `infra/provision.env.example` | `--check`, OS refusal, settings validation, secret handling: 39 stub tests (`make infra-test`) |
| 10 | firewall and SSH stages with 10-minute dead-man timers and `--confirm-ssh` | 48 checks with the real `ufw` (never enabled) and real `sshd -t` / `sshd -T`; the `00-` prefix proven against a `50-` file that says `PasswordAuthentication yes` (a `99-` control shows the 50 file would win); the revert command executed as the timer would |
| 11 | `scripts/test-provision-chroot.sh` (`make infra-test-chroot`) | a clean Ubuntu 24.04 debootstrap chroot provisioned **twice**: run 1 made 14 changes, run 2 `changed: 0` (12 stages, all unchanged); `--check` on the fresh image listed 36 actions and changed nothing; `--check` after provisioning said `changed: 0`; tree snapshots identical; 49 checks |
| 12 | `docs/DEPLOY.md` (ordered steps, rollback per stage, smoke tests, backups, recovery), checklist rows | `make lint` |

**What the chroot run showed** (in a real Ubuntu userland, daemons started by hand): the real OJS CLI installer ran; `check-live-config.py` passed on the result (19 checks, 0 failed); 132 tables; `https://journal.example.org/index/login` returned 200 with a username field through the rendered Nginx, PHP-FPM pool and MariaDB; HSTS, nosniff and the Report-Only CSP were present; `http` redirected to `https`; `/config.inc.php` was 404; an unknown site path returned the static 404 page; the Cloudflare ranges file (fixture, 22 ranges) was in place; the installed `worj-backup --check` ran. **Secret hygiene:** the administrator password appears only in the operator's `provision.env`; the SMTP password only there and in `config.inc.php`; the database password only in `secrets.env`, `mysql-backup.cnf` and `config.inc.php`; the salt and API key secret only in `config.inc.php`. A process-list sampler (1.08 million lines, including `rsync` and `tools/install.php`) never saw any of them, the provisioning output never printed one, the answers file and its directory are gone, there is no shell history. **First-run Cloudflare failure** (the live URL is blocked here): the stage stopped the run with the explanation that every visitor would look like a Cloudflare address, and wrote no file. **Bootstrap path:** with no certificate, only the port-80 site was installed and the certificate stage refused to continue, naming the files to place.

**Bugs the chroot run found and fixed (none would have shown up without a real Ubuntu install):**
1. A minimal image has no `python3`, which the renderers need: preflight now says so and the package list includes it.
2. The dev OJS tree contains a `plugins/themes/worj` symlink (made by `make setup`) that broke the theme sync: excluded from the core sync.
3. The OJS installer **appends a second `allowed_hosts = "[\"\"]"` line** after the template's, and the later line wins: `set-ojs-config.py` now removes later duplicates (test added).
4. The `nginx -t` test inside the Cloudflare stage failed on the stock Ubuntu default site (it listens on `[::]:80`; no IPv6 here) before our site existed: the test now runs only when our config includes the file.
5. The installer runs as root, so `cache/`, `public/` and `files_dir` are handed to `www-data` afterwards.
6. The installer answers directory was left behind: removed with the answers file.
(Also found by the firewall tests: a `pipe | grep -q` under `pipefail`, `ufw delete` argument quoting, and IPv6 rules refused when IPv6 is off, so Cloudflare-only mode uses IPv4 ranges only.)

**Not tested here, every item `UNVERIFIED (not run on VPS)`:** `ufw enable`, an sshd reload and a second login, systemd units and timers, certbot issuance and renewal, the real Cloudflare range fetch, SSL mode and rate limiting, real DNS (SPF, DKIM, DMARC, Search Console), real mail, a real rclone remote, the client's age key custody, cron actually running the jobs, the admin recovery rehearsal on staging, 4 GB tuning performance, a full run of the firewall and ssh stages in the chroot (they are skipped there and covered by `test-provision-ssh-firewall.sh`), `CERT_METHOD=certbot` issuance and DNS-01 (not implemented).

**Decisions made in code, confirm in `DEPLOY.md`:** HSTS 300 s with no preload; IPv4-only origin; 7-day static cache; PHP-FPM sized for a 4 GB host; `open_basedir` not set; no OJS cron lines (built-in web runners); the unattended-upgrades stage never reboots; the break-glass administrator is held by the client's named business owner.

## Review follow-ups applied before the Phase 5 PR (owner decisions, 2026-11-10)

- **Scheduled tasks now run from cron.** Evidence from the 3.5.0-6 source is in `docs/DEPLOY.md` ("Scheduled tasks"): the web runner fires only on a request and the Laravel scheduler runs a task only when its cron expression matches that minute, so a quiet site misses daily and monthly tasks (reviewer reminders, usage statistics, editorial statistics emails). The template sets `task_runner = Off`, `job_runner = Off`, `process_jobs_at_task_scheduler = On`; `/etc/cron.d/worj` runs `php lib/pkp/tools/scheduler.php run` every minute as `www-data`; `check-live-config.py` fails if the web runner is left On.
- **Theme caching:** OJS appends `?v=<OJS version>` (not the theme version) to theme CSS and JS and does not version theme images, so `/plugins/themes/` is cached for one hour and other static files for seven days.
- **Admin password:** the script removes the `ADMIN_PASSWORD` line from `provision.env` after a successful install and sets `must_change_password` for the administrator (chroot-tested).
- DEPLOY.md: no AAAA records unless Nginx is configured for IPv6; only Origin CA and HTTP-01 are offered; a monthly `reboot-required` step; a handover item removing or transferring the developer's administrator account; `open_basedir` listed as an optional measure we do not claim; a throwaway-VPS rehearsal (also a Phase 8.3 gate item).
- **Regression tests (mutation status below; the first four were mutated in Phase 5, the last three in Phase 6, see "Mutation results"):** no `python3` (preflight), the dev theme symlink in the OJS tree (ojs-code), `nginx -t` before our site includes the ranges file (Cloudflare stage), duplicate `allowed_hosts` lines (config tools), plus chroot checks for www-data ownership of `cache/`, `public/` and `files_dir` with a root-owned code tree, the removed answers directory, the single `allowed_hosts` line, the removed admin password and the forced change.

## Hand-offs to Phase 6 (owner requirements, 2026-11-10; start in plan mode, branch off `main`)

- **6.2 `check-pdf.sh`:** `pdftotext` extracts selectable text; the file is under 5 MB; the title and authors appear on page 1; the galley URL returns `application/pdf` with no login redirect and no auth cookie; `citation_pdf_url` is that same URL; private submission files are not reachable (the Phase 5 harness covers the server side: check the public path is distinct).
- **6.3:** read the `robots.txt` OJS ships in 3.5.0-6 and make sure no rule blocks article pages, galleys or `/public/`; add the sitemap URL with a placeholder host; the sitemap lists issue and article pages; OAI-PMH `Identify`, `ListMetadataFormats`, `ListRecords` and `GetRecord` return valid responses; **check which admin email `Identify` exposes (it is public) and add that to the decision table so it is not a personal address**; recheck the sitemap and OAI URLs behind the Phase 5 Nginx redirects (the harness `make infra-test-nginx` is the place).
- **6.4 `docs/SEARCH-CONSOLE.md`:** DNS verification through Cloudflare, sitemap submission, URL inspection of a real article, what "indexed" looks like; say plainly that nothing in the repo can make Google Scholar index a paper.
- **6.5 canonical:** an INFO finding (no canonical tag on article pages at 3.5.0-6, decision pending) with the staging recheck on the real domain; add the URL inspection step and the duplicate-URL checks (article versus galley, `http` versus `https`, `index.php` forms) to the checklist.
- **Also:** `citation_doi` appears only when a DOI is assigned: the check must NOT require it and must FAIL if a DOI tag is present with an empty value. `scripts/check-citation-meta.sh` (6.1) already exists.

## Mutation results for the remaining regression tests (Phase 6, commit 0, 2026-11-10, `VERIFIED-SANDBOX`)

Each fix was removed, the test run, then the source restored byte-identical (`git diff` empty). Because a missing fix also breaks later stages, the failing list contains knock-on failures; the test named here is the one that must be in it.

| Regression test | Fix removed | Result without the fix |
|---|---|---|
| installer ran as root: `cache/`, `public/`, `files_dir` belong to www-data | the `chown -R www-data:www-data` line in the ojs-config stage | `FAIL  REGRESSION the installer ran as root, yet cache/, public/ and files_dir belong to www-data` (also: the scheduler as www-data cannot run, exit 255) |
| leftover answers directory | `cleanup_answers` made a no-op and the failure-path `rm` removed | `FAIL  the installer answers file is gone`, `FAIL  no installer log or temp output is left in /root`, and the secret sampler found the admin and database passwords in `/root/.worj-provision/answers` |
| single `allowed_hosts` line | both `del lines[d]` sites in `scripts/set-ojs-config.py` (there are two) | fast unit test `only ONE allowed_hosts line is left` fails; chroot `FAIL  REGRESSION no second allowed_hosts line` fails (18 failures in all, most knock-on) |

**An honest miss on the way:** my first attempt at the third mutation changed only one of the two `del lines[d]` sites, and the tests still passed. That did not show a weak test; it showed a half-removed fix. Both sites are mutated in the recorded run.

## Scheduler visibility (Phase 6 follow-up)

`/var/log/worj-scheduler.log` is rotated (weekly, 8 kept) and cron mail is off (`MAILTO=""`). `docs/DEPLOY.md` now has a smoke test (log modification time) and an operator check after the first day. **A stopped scheduler means no review reminders, no statistics emails and no queued emails, silently.** Not run on a VPS.
