# Deploying to the shared hosting plan (Hostinger "Unlimited" web hosting)

**Status: built and tested on a stand-in, never run on the host.** The client bought a **shared web hosting plan** (managed hosting on LiteSpeed), not a root VPS, so `docs/DEPLOY.md` (the VPS path) does **not** apply to this client. This file is the shared-hosting path: what is known about the plan, the **Day-0 checks** a person runs on the host, and the **runbook** from an empty account to a visible placeholder site. Every script named here was run in the sandbox with a stand-in for the host (a local directory and a stand-in `ssh`, an Apache in place of LiteSpeed, a scratch MariaDB database); **none of it has run on Hostinger** and each such claim is `UNVERIFIED (not run on the host)`.

Decisions already made by the client: **there is no staging site** (2026-11-10): the main domain is the test bed until the day it goes public (see "No staging site" below); the canonical host is **`worldopenresearchjournal.com`** (no `www`; `www` redirects to it); **no Cloudflare at launch** (DNS stays at Hostinger so the mailbox's SPF and DKIM records stay as they are, and Hostinger's own CDN setting stays off while testing). The mailbox is **`editorial@`**, with aliases `support@`, `privacy@` and `doi@`.

Labels: `READ 2026-11-10` (paraphrased from the Hostinger page named beside it, read on that date), `AGENT CLAIM` (what Hostinger's platform agent told the client, not cross-checked), `UNVERIFIED (<reason>)`, `NOT RUN` (a Day-0 check nobody has run yet). Hostinger changes its pages and limits: read the page again before relying on a figure. This document contains no price, no password and no account identifier; the account folder is written `uXXXXXXXXX`.

## What is known about the plan

| Topic | What is known | Source |
|---|---|---|
| Plan | The "Unlimited" web hosting plan: 2 CPU cores, 3 GB RAM, 50 GB, 600,000 inodes, 60 PHP workers, 120 processes, up to 100 parked domains and unlimited websites, database size up to 3 GB, up to 150 databases | `READ 2026-11-10` [limits](https://www.hostinger.com/support/6976044-parameters-and-limits-for-hosting-plans) |
| Web server | **LiteSpeed.** No `httpd.conf`, no virtual hosts. Settings are made with `.htaccess`. `mod_rewrite` is on | `READ 2026-11-10` [server access options](https://www.hostinger.com/support/which-file-transfer-and-server-access-options-are-supported-at-hostinger/) |
| Managed | Hostinger handles server maintenance, security updates and backups. A VPS is the self-managed alternative | `READ 2026-11-10` [web-hosting page](https://www.hostinger.com/web-hosting) |
| Access | SFTP, SSH and rsync are available at this plan tier (plain FTP exists but is unencrypted: **do not use it**). No compilers, no root | `READ 2026-11-10` [server access options](https://www.hostinger.com/support/which-file-transfer-and-server-access-options-are-supported-at-hostinger/), [server capabilities](https://www.hostinger.com/support/which-server-capabilities-are-supported-at-hostinger/). SSH is currently switched **off** (`AGENT CLAIM`) |
| PHP | 8.2 to 8.5 selectable; the site runs 8.3.36 (`AGENT CLAIM`). `php.ini` is not editable: settings are changed in the dashboard's PHP options or with `php_flag` lines in `.htaccess`. Limits: execution 360 s, memory, upload and POST size up to 2048 MB | `READ 2026-11-10` [PHP article](https://www.hostinger.com/support/which-php-extensions-and-configuration-options-are-supported-at-hostinger/), [limits](https://www.hostinger.com/support/6976044-parameters-and-limits-for-hosting-plans) |
| Web application firewall | **ModSecurity is on by default** and can be switched off per site through `.htaccess` | `READ 2026-11-10` [PHP article](https://www.hostinger.com/support/which-php-extensions-and-configuration-options-are-supported-at-hostinger/) |
| Database | MariaDB 10.5 (`AGENT CLAIM`). OJS 3.5.0-6's README requires MySQL 5.7.22 or later, or MariaDB. **MariaDB 10.5's upstream support status is `UNVERIFIED` (from memory it may have ended; the host decides when to upgrade)** | OJS README (`ojs-core/README.md`) |
| Cron | Dashboard cron jobs, on a **UTC** schedule. A PHP-type job runs a `.php` file; a custom job runs any command but special characters (such as `>/dev/null 2>&1`) need a small `.sh` file. The number of jobs is unlimited at this tier. Jobs can be skipped when the plan's limits are reached | `READ 2026-11-10` [cron guide](https://www.hostinger.com/support/1583465-how-to-set-up-a-cron-job-at-hostinger/), [cron limits](https://www.hostinger.com/support/1583765-how-many-cron-jobs-can-you-set-up-in-hostinger/), [troubleshooting](https://www.hostinger.com/support/1583514-troubleshooting-cron-jobs-at-hostinger/) |
| Paths | File paths start at `/home/uXXXXXXXXX/domains/DOMAIN/public_html` (or `/home/uXXXXXXXXX/public_html`) | `READ 2026-11-10` [cron troubleshooting](https://www.hostinger.com/support/1583514-troubleshooting-cron-jobs-at-hostinger/) |
| Mail from scripts | The server's built-in mail is capped at **10 messages a minute and 100 a day**; Hostinger recommends SMTP instead | `READ 2026-11-10` [limits](https://www.hostinger.com/support/6976044-parameters-and-limits-for-hosting-plans) |
| Mailbox | The plan page says mailboxes are free for the first year. SMTP limits are per mailbox and depend on the email product (read the current figures in the dashboard's Emails section) | `READ 2026-11-10` [web-hosting page](https://www.hostinger.com/web-hosting), [email limits](https://www.hostinger.com/support/4625828-parameters-and-limits-of-hostinger-email/). **Which email product is attached is `UNVERIFIED`** |
| Backups | Daily backups with restore are advertised; the platform agent said 7 days of dailies, downloadable, and a manual backup. The client's plan details put the backups in **Germany** and the server in the **United Kingdom** | `READ 2026-11-10` [web-hosting page](https://www.hostinger.com/web-hosting); the rest `AGENT CLAIM`. Restore time and whether backups are encrypted are `UNVERIFIED` |
| SSL | Lifetime SSL active and HTTPS redirect enabled (`AGENT CLAIM`) | |
| Staging (not used: client decision) | Subdomains are available (the agent said up to 100, none created yet). The plan's CPU, memory and PHP workers are **per plan**, so a staging site would **share them** with production (my reading of the limits table) | Subdomain count `AGENT CLAIM`; limits `READ 2026-11-10` [limits](https://www.hostinger.com/support/6976044-parameters-and-limits-for-hosting-plans) |
| CDN versus Cloudflare | Hostinger warns against running its CDN and Cloudflare together as two caching layers | `AGENT CLAIM` (the agent cited Hostinger's CDN-versus-Cloudflare article, which was not read here) |

## What this changes compared with the VPS design

- **Provisioning, firewall, SSH hardening, certbot, unattended upgrades, the reboot step and the Cloudflare real-IP files no longer apply:** the host runs them.
- **The Nginx rules become an `.htaccess`** (redirects, deny rules, headers, `robots.txt`), tested in a stand-in Apache and then again on the real site before it goes public.
- **The accessible static 404 page is mostly lost.** On Apache-style servers `ErrorDocument` shows only for errors the web server generates (our deny rules), not for OJS's own bare `<h1>404 Not Found</h1>`. The Phase 2 accessibility finding returns.
- **Backups are weaker** than the VPS design (the host's backups are not encrypted with the client's key; ours must be pulled from outside).
- **Less control and isolation:** ModSecurity may block admin actions, and there is no per-site server tuning.

## Day-0 checks (about half an hour, run by the client or the operator)

Run these **before** anything else is built or deployed. **Do not paste a password, a key's private half or any credential into chat, into the repository or into a ticket.** Write each result in the table at the end, with the date and your name. The test files and pages below are temporary and must be deleted when done.

**A. No staging site (client decision): use the main domain before it goes public.** Because there is no separate site to break, these controls matter more:
- **Nothing real on it.** No real content, no real users, no real author's work, no DOIs. Test accounts use addresses the tester controls. Everything is removed or reinstalled clean before launch (`docs/LAUNCH-GATES.md` gate 4.4); the safest option is a fresh database and a fresh files folder on launch day.
- **Closed to search engines from the first day.** Put a `robots.txt` containing `User-agent: *` and `Disallow: /` in the web root now (and `X-Robots-Tag: noindex` once the `.htaccess` exists). Switch to the production robots file only at launch (`ROBOTS_MODE`, `docs/DEPLOY.md` "Staging versus production").
- **Password-protect it while testing if the dashboard allows** (an agent claim, not checked). If it does, give the developer a login on the secure credential card (never in chat or on a command line); if not, the kit below is harmless and short-lived.
- **Take a Hostinger backup before each risky step** (an on-demand backup was described by the agent), and note that a restore is rehearsed on a scratch database, not on a staging site.

**B. SSH** (dashboard SSH access page; the exact menu name is `UNVERIFIED`):
1. Enable SSH. Use a **key**, not a password: give the operator only the **public** key to add.
2. Log in and run `pwd`. **Write the real home path** (it contains the account folder `uXXXXXXXXX`; do not paste it anywhere public).
3. Run each of these and write the version or "not found": `php -v`, `php -m`, `mysqldump --version`, `mysql --version`, `tar --version`, `rsync --version`, `git --version`, `composer --version`, `python3 --version`, `age --version`, `rclone --version`.
4. Compare `php -v` with the PHP version shown in the dashboard's PHP configuration: **are they the same minor version?**

**C, D and F: the Day-0 kit** (a ready-made test folder; replaces the manual `phpinfo()`, folder and `.htaccess` checks). The kit is `infra/shared-hosting/day0-kit/worj-day0/` (its `README.txt` says how to use it).
1. In the dashboard's PHP configuration, choose **PHP 8.3** (the version the sandbox tests ran) for the site.
2. Upload the folder `worj-day0` to the **web root of the site**, so that `https://worldopenresearchjournal.com/worj-day0/probe.php` exists. **Only before launch, with the site still closed to search engines (A above).**
3. Tell the developer. The developer runs `scripts/probe-day0-kit.sh https://worldopenresearchjournal.com` (a login, if the site is password-protected, goes in a netrc file or the secure credential card, **never on a command line**) and reports every line. It checks: the PHP version, every extension on the OJS README list plus `mysqli`, the memory, upload and execution limits, `open_basedir`, whether PHP can write **above the web root** (where the private files folder goes), and thirteen small `.htaccess` features, each in its own folder (a 301 redirect, rewrite to `index.php`, deny rules, headers including on error responses, a conditional header, `ErrorDocument`, cache lifetimes, redirect for GET and HEAD but not POST, no PHP in a protected folder, no directory listing, and whether `php_value` is allowed).
4. **Delete the `worj-day0` folder** afterwards. The probe prints only non-secret facts, never `phpinfo()` or environment variables, and masks the account folder as `uXXXXXXXXX`.

The kit and the probe are tested in the sandbox against a **stand-in Apache, not LiteSpeed** (`make infra-test-day0`): that proves the files are valid Apache-style rules and that the probe tells a working host from a broken one, but only the real run on the host shows what LiteSpeed does.

**E. Cron:** in the dashboard create a **test** cron job.
1. What is the **shortest interval** the dashboard offers? (OJS needs one that divides 60 and includes minute 0.)
2. Can a PHP-type job run `…/lib/pkp/tools/scheduler.php` **with an argument** (`run`), or is a custom job with a small `.sh` file needed?
3. Does the job's output appear in the dashboard, and is there a maximum run time?
4. Delete the test job.

**F. `.htaccess` on LiteSpeed:** done by the kit (see "C, D and F" above); nothing to do by hand.

**G. Email:** create the SMTP settings from the `editorial@` mailbox's own page (host, port, encryption: read them from there). Send **one** test message from OJS (the pre-launch site) to an inbox the tester controls. Write: did it arrive, did it reach spam, what **From** and **Reply-To** did it show, and does SMTP accept a From that differs from the login?

**H. ModSecurity:** on the pre-launch site, once OJS is installed, try one large upload and one admin action. If something is blocked, write the exact URL and the time, and look for the security log (its location is `UNVERIFIED`).

**I. Backups and the database:** in the dashboard, note the MariaDB version, whether `utf8mb4` is the default, the backup schedule, and what a restore asks for. Do **not** run a restore on production.

### Day-0 results

| Check | Result (write it) | Date and name | Decides |
|---|---|---|---|
| B2 home path | `/home/uXXXXXXXXX`; domain folder `domains/worldopenresearchjournal.com`, with `public_html` inside (2026-11-10, operator's run) | | `files_dir` and the cron paths |
| B3 tools present (`php`, `mysqldump`, `rsync`, `git`, `composer`, `python3`, `age`, `rclone`) | `php`, `mysqldump`, `mysql`, `tar`, `rsync`, `git`, `composer`, `python3` present; `age` and `rclone` absent (not needed on the host: the backup encrypts on the operator's machine) (2026-11-10, operator's run) | | whether config checks and encrypted backups can run on the host |
| B4 CLI PHP equals web PHP | CLI 8.3.36 and web 8.3.36 (SAPI `litespeed`) (2026-11-10, operator's run) | | whether the CLI installer and the scheduler use the same PHP |
| C extensions missing, PHP version and limits (kit) | **OK:** PHP 8.3.36, every extension on the OJS list loaded (63 in all), memory_limit 2048M, upload and post size 2048M, max_execution_time 360, `date.timezone` UTC. `disable_functions` includes `exec shell_exec system passthru popen proc_open symlink link dl`; whether any OJS feature or plugin needs them is `UNVERIFIED` (2026-11-10, operator's run) | | whether the plan can run OJS at all |
| D write above `public_html`; `open_basedir` (kit) | **OK:** PHP can write one level above the web root, so `files_dir` can live there; `open_basedir` is not set (2026-11-10, operator's run) | | where `files_dir` goes |
| E shortest cron interval; argument support; run time | NOT RUN | | the scheduler design |
| F `.htaccess` directives that worked (kit, thirteen folders) | **OK on LiteSpeed:** redirect, rewrite to `index.php`, `FilesMatch` deny, dotfile deny, `RewriteRule [F]` and `[R=404]`, `Header always set` on normal responses, `ErrorDocument` for server errors, `Expires`, GET and HEAD redirect with POST untouched, `.php` blocked in a protected folder, `Options -Indexes`, `php_value` honoured. **Two FAIL: see Findings below** (2026-11-10, operator's run) | | which rules the `.htaccess` template can rely on |
| G SMTP: arrival, spam, From and Reply-To | NOT RUN | | the mailbox and sender design |
| H ModSecurity blocks | NOT RUN | | whether exceptions are needed |
| I MariaDB version, backups | NOT RUN | | the database lifecycle question and the backup plan |

### Findings from the Day-0 run (2026-11-10, LiteSpeed, `RESULT: FAIL (2)` from `scripts/probe-day0-kit.sh`)

1. **`Header always set` is not added to a 404 the server itself produces** (t06). Our denied paths (404 by rewrite) and unknown URLs answered by the server therefore carry no HSTS, `nosniff` or, on a closed site, `X-Robots-Tag`. Pages OJS answers carry them. Impact: small (a 404 body is the static page); `scripts/check-live-site.sh` does not require headers on a 404.
2. **A header made conditional with `SetEnvIf ... env=!NO_CSP` is sent on every path** (t07), so the admin pages also get the report-only CSP. Impact: none on function, because the policy is **report-only** (it blocks nothing and nothing collects reports), but `check-live-site.sh` expects no CSP on the backend and API paths and **will fail on this host** until a decision is made: drop those two checks and keep the header everywhere, or drop the header. Not changed yet.
3. **`trust_x_forwarded_for` is `Off` in our config template and the probe saw `X-Forwarded-For` on requests** (Hostinger sits in front of the web server). OJS then logs the proxy's address in place of the visitor's, which skews usage statistics and IP-based features. Whether `REMOTE_ADDR` already holds the visitor's address on this host is `UNVERIFIED`; check on the first real request before deciding.
4. **`php_value` in `.htaccess` is honoured**, so the PHP options table can be applied there if the dashboard has no matching option.
5. **First `check-live-site.sh` run on the host (2026-11-11), after install and seeding.** The cron job runs every minute (`end exit=0`). Findings, and what changed because of them:
   - **Hostinger's CDN is in front of the site** (`server: hcdn`, `x-hcdn-*` headers), although the plan was to keep it off while testing. Check hPanel and decide; it also means the visitor's address may arrive in `X-Forwarded-For` (finding 3).
   - **The host adds `Content-Security-Policy: upgrade-insecure-requests`** to every response. It restricts nothing; the check now allows exactly that value and fails on any other enforcing policy.
   - **The host's own firewall answers 403, not our 404, for `/config.inc.php`, `/.git/config` and `/.htaccess`.** Still refused; the check accepts 403 or 404.
   - **The `.htaccess` in `plugins/themes/` was ignored**, and so was a `FilesMatch` + `ExpiresDefault` rule: the host's own 7-day default for static files won (confirmed with a cache-busting URL that reached the origin). **`ExpiresByType` is honoured** (as the Day-0 t09 test already showed), so there is now one `ExpiresByType` line per file type, one hour for all static files, and the themes `.htaccess` is gone from the release.
   - **The report-only CSP is sent on backend and API paths** (finding 2): now a WARN in the check, not a failure.
   - **Our static 404 page works** for the paths our rules deny (`/tools/install.php` answers 404 with the accessible page).
6. **Still to do on the host:** B (done), E cron interval, G SMTP, H ModSecurity, I backups; the Day-0 kit was deleted afterwards.

## Delivery: how the files reach the host

Two ways, both starting from a **release package** built from the pinned OJS core plus our theme and rules (`scripts/build-release.sh`). **The runbook below uses the first.**

1. **rsync over SSH** (`scripts/deploy-shared.sh`, tested against a local directory and a stand-in ssh): a dry run (`--check`) first, the config, `public/`, `cache/` and the files folder are never touched. Needs SSH switched on.
2. **Hostinger's Git deployment** (`AGENT CLAIM`, not read in Hostinger's documentation: connect a GitHub repository and branch, set the deployment folder, optionally auto-deploy on every push).

**Do not connect this repository's `main` to `public_html`.** This repository is where the project is *authored*, not an OJS site: it has no OJS core (that is fetched at a pinned version and never committed), and it contains `docs/`, `scripts/`, tests, `ojs/content` and `ojs/fixtures` (fake sample articles that must never ship), `autoresearch/` and `CLAUDE.md`. Deploying it would put all of that on the public web root and still leave OJS missing.

If Git deployment is chosen, it needs a **separate release repository or branch** containing only the built release (the OJS tree with our theme and `.htaccess`), updated only by a deliberate release step, never `main`. Open questions to ask Hostinger before relying on it (`UNVERIFIED`): can it deploy only a branch or subfolder; what exactly does it overwrite or delete in a folder that already has files (the agent said deploying into an existing directory can overwrite files); does a `.gitignore` protect `config.inc.php`, `public/` and `cache/` (it only protects *untracked* files, and these must also not be tracked); which GitHub permissions does the authorisation ask for (grant only the one repository); and what deploy key or webhook it leaves behind (it must be removed at handover, `docs/LAUNCH-GATES.md` gate 1.10). **After launch, auto-deployment should be off:** a deploy should follow our checks, not every push.

Git deployment does not carry the database, uploaded files, the private files folder, `config.inc.php`, cron jobs or the PHP and email settings (the agent said the same); those stay manual in either method.

## The runbook: from an empty account to a visible placeholder site

Every command runs on **your machine** (the operator's), not on the host, except where it says hPanel. The host needs **no** key, no Python and no extra tool (the scripts use `php` and `mysqldump` on the host, and the Day-0 checks B3 show whether they exist). Menu names in hPanel are `UNVERIFIED` (from the platform agent and Hostinger's help pages, not clicked through).

**You need here:** `git`, `rsync`, `ssh`, `python3`, `age`, and for the seeding step `node` with `playwright` (the Claude sandbox has it; elsewhere `npm i playwright`). **Do not run any of this against the domain until the Day-0 results are in** (above), because they decide which steps work as written.

### Before the first command (hPanel, by the client or with the client)

1. **SSH:** switch it on and add your **public** key (B above). Write down the user, the host or IP, the **port**, and the real home path from `pwd`.
2. **PHP:** choose **PHP 8.3** and enable the extensions OJS needs (`bcmath ctype curl dom fileinfo filter ftp gd hash intl json libxml mbstring mysqli openssl pcre phar session simplexml spl tokenizer xml xmlwriter zip zlib`; `install-shared.sh` checks them on the **command line** PHP, and Day-0 B4 says whether the web PHP is the same). Set the PHP options below.
3. **Database:** create one database and one user for it (the host is `localhost`). Note the password in your password manager.
4. **Mailbox SMTP:** read host, port and encryption from the `editorial@` mailbox's own page. Use the mailbox, never PHP's built-in mail (100 a day).
5. **Hostinger CDN off** while testing, **no Cloudflare** (decision). Take a Hostinger backup now.
6. **Cron** is set up in step 8 below.

**PHP options** (the old `infra/php/99-worj.ini.template` values; `php.ini` is not editable here, so set them in the dashboard's PHP options if they exist there, or with `php_value` lines in `.htaccess` only if Day-0 F13 shows LiteSpeed honours them; otherwise leave the host default and write down which ones could not be set):

| Option | Value | Why |
|---|---|---|
| `upload_max_filesize` | 64M | submission files |
| `post_max_size` | 66M | slightly more than the upload limit |
| `max_file_uploads` | 20 | |
| `memory_limit` | 256M | |
| `max_execution_time` / `max_input_time` | 120 | |
| `display_errors` | Off | never show errors to visitors |

`date.timezone`, `session.cookie_secure` and the other session flags are not needed here: OJS sets its own time zone from `config.inc.php` (`TIME_ZONE`), and `force_ssl = On` is checked by `check-live-config.py`.

### The commands, in order

Copy `infra/shared-hosting/install.env.example` to `.env.shared` (git-ignored, mode 600) and fill it in. It holds the database and mailbox passwords and the first administrator's password: **it never leaves your machine**, never goes in chat, and the scripts refuse it if other users can read it.

| Step | Command | What it does |
|---|---|---|
| 1. Get OJS | `make setup` | fetches the pinned OJS 3.5.0-6 into `ojs-core/` |
| 2. Build | `scripts/build-release.sh --host worldopenresearchjournal.com --robots-mode closed --out ../worj-release` | the package: OJS + theme + rendered `.htaccess`, closed `robots.txt`, static 404 page, a manifest. Refuses unfilled tokens, `config.inc.php`, content and fixtures |
| 3. Dry run | `scripts/deploy-shared.sh --release ../worj-release --target USER@HOST:/home/uXXXX/domains/worldopenresearchjournal.com/public_html/ --ssh-arg -p --ssh-arg PORT --check` | prints `WOULD:` lines, changes nothing |
| 4. Deploy | the same without `--check` | verifies the manifest, then rsync. **Never touches** `config.inc.php`, `public/`, `cache/`, `.well-known/`, `cgi-bin/`; removes files that left the package; sends the two `.htaccess` files last |
| 5. Install | `scripts/install-shared.sh --check`, then without | checks PHP and extensions, makes the private files folder **above** the web root, renders `config.inc.php` here (secrets generated here), runs OJS's own CLI installer on the host (answers on stdin), repairs what the installer leaves weak, verifies with `check-live-config.py`, puts `worj-ops/run-scheduler.sh` on the host. Re-runnable |
| 6. Seed | `scripts/seed-shared.sh --check`, then `scripts/seed-shared.sh --with-sample-issue` | **refuses unless the site is closed to crawlers.** Creates the journal `worj`, the theme, placeholder texts and pages, and (optionally) three clearly fake sample articles. Create-only: never overwrites text a person edited |
| 7. Look | open `https://worldopenresearchjournal.com/worj/` | this is the placeholder site. If you password-protected the domain, the login is the Hostinger one |
| 8. Scheduler | hPanel > Advanced > Cron Jobs: a **custom** job running `/bin/bash /home/uXXXX/domains/worldopenresearchjournal.com/worj-ops/run-scheduler.sh` at the shortest interval that divides 60 and includes minute 0 (Day-0 E) | queued emails and daily or monthly OJS tasks. One run at a time, log kept small. Check later: `tail worj-logs/scheduler.log` shows `end exit=0` |
| 9. Check the host | `scripts/check-live-site.sh --robots-mode closed https://worldopenresearchjournal.com`; `scripts/check-discovery.sh --robots-mode staging https://worldopenresearchjournal.com`; `scripts/check-pdf.sh https://worldopenresearchjournal.com/worj/article/view/1`; `scripts/check-citation-meta.sh --placeholder-issn https://worldopenresearchjournal.com/worj/article/view/1` | the same matrix the stand-in passed, now on LiteSpeed. **A FAIL here is a finding about the host**, not about the test |
| 9b. Mail | `scripts/test-smtp-shared.sh --to YOUR_OWN_INBOX` | the host sends one test message through the SMTP settings OJS uses (the transport OJS builds from `[email]`, so the same connection, encryption and login). Prints `OK` or `FAILED <reason>` with the password masked. **Then read the inbox**: arrival, spam folder, the From address. Accepted by the server is not the same as delivered. Hostinger's mailbox limit applies; send only a few |
| 10. Finish | `scripts/install-shared.sh --finish` | forces the administrator to change the initial password at the first login and removes `ADMIN_PASSWORD` from `.env.shared`. Run it **after** seeding (seeding logs in with that password) |
| 11. Back up | `scripts/pull-backup.sh --check`, then without | see "Backups" below |

### Seeing the pieces, and what is placeholder

Everything in step 6 is the placeholder content from `ojs/content/` (a `[PLACEHOLDER: ...]` banner on each text) and `ojs/fixtures/` (fake articles). It lets you see the journal structured as it will launch; **none of it may stay at launch** (`make check-placeholders-url` must be empty, `docs/LAUNCH-GATES.md` gates 1.2 and 4.4). `ojs/content/` and `ojs/fixtures/` are never in the release package: the seed script copies only `import-pages.php` and `ojs/content/` to `worj-ops/`, **above** the web root.

### Backups

- **Hostinger's own daily backups** are the first line (7 days, held by Hostinger, `AGENT CLAIM`). They are **not** encrypted to the client's key, and a restore on the live site is not rehearsed here.
- **`scripts/pull-backup.sh`** is ours: it streams the database dump (the host builds the dump's credentials from `config.inc.php` through a pipe: no password on a command line) and the files over ssh, runs the same sanity checks as the VPS backup (valid gzip, size, tables, users rows, mysqldump's completion line), and **encrypts here** with `age` to the client's **public** key. The host holds no key. The bundle has the layout `scripts/restore.sh` reads. Optional `rclone copy` (never `sync`) to the client's bucket, size verified.
- **The recovery point is only as fresh as the last time someone runs it.** The VPS design ran every night at 02:17; this one runs when a person (or the client's machine, with a scheduled task) runs it. **Decide who, how often and where the key lives** (`docs/LAUNCH-BLOCKERS.md`). Weekly is the minimum I would accept for a journal that takes submissions.
- **Restore** is done by the operator, with the **private** key kept off the host: `scripts/restore.sh` into a scratch database on the operator's machine (`docs/DEPLOY.md`, Backups). The sandbox runs `scripts/restore.sh` on a pulled bundle: decryption, manifest, scratch database, files and temporary config pass; its last check (the journal's login page) was not covered because that install had no journal. It does not prove a restore onto Hostinger.

### Moving from closed to public (launch day)

1. Replace every placeholder with approved content (`docs/LAUNCH-GATES.md` section 4); delete the sample articles and the test users.
2. Rebuild with `--robots-mode production` and deploy: `robots.txt` carries the sitemap, the `X-Robots-Tag: noindex` header is gone.
3. `scripts/install-shared.sh --launch-check` (the production config has no placeholder host), `scripts/check-live-site.sh --robots-mode production https://worldopenresearchjournal.com`, `scripts/check-discovery.sh --robots-mode production --launch https://worldopenresearchjournal.com`, `scripts/check-placeholders.sh --url https://worldopenresearchjournal.com/worj` (all must exit 0).
4. Hostinger Git auto-deployment, if ever connected, is switched **off**.
5. Search Console (`docs/SEARCH-CONSOLE.md`); HSTS raised in stages only after launch.

## What was tested here, and what was not

Sandbox runs of 2026-11-10 (`VERIFIED-SANDBOX`, exit codes read directly from `make`):

| Suite | Command | Exit | Result |
|---|---|---|---|
| Day-0 kit and probe on a stand-in Apache | `make infra-test-day0` | 0 | 49 PASS, 0 FAIL |
| `.htaccess` on a stand-in Apache in front of the sandbox OJS (redirects, denies, PHP only via `index.php`, headers, caching, both robots modes, the live-site check script, and a mutation proof per rule) | `make infra-test-htaccess` | 0 | 109 PASS, 0 FAIL |
| Release build, deploy (verification, excludes, a stand-in ssh) | in `make lint` (`scripts/test-release.sh`) | 0 | 43 PASS, 0 FAIL |
| Scheduler wrapper | in `make lint` (`scripts/test-run-scheduler.sh`) | 0 | 14 PASS, 0 FAIL |
| Seeding guard | in `make lint` (`node scripts/test-target.js`) | 0 | 12 PASS, 0 FAIL |
| Release, deploy, **real OJS CLI installer** into a scratch database, config repair, real scheduler run, launch check, seed `--check`, pull backup (decrypt, manifest, `restore.sh` up to the login page, truncated dumps), `--finish` | `make infra-test-install` | 0 | 77 PASS, 0 FAIL |
| Everything else | `make lint`, `make infra-test` | 0, 0 | unchanged |

**Not run, each `UNVERIFIED (not run on the host)`:** LiteSpeed's behaviour (the stand-in is Apache: a pass proves the rules are valid Apache rules and that the checks detect their absence, not that LiteSpeed honours them); SSH, rsync and the real paths on Hostinger; the CLI installer on the host's PHP and MariaDB 10.5; `mysqldump` and `tar` on the host; the cron job and its interval; ModSecurity against the admin interface and the API; SMTP delivery and limits; the seeding steps that drive a browser against a real https site (the guard and the sandbox path are tested, the remote login path is the same code with another address and credentials); Hostinger backups and restore; the first-year mailbox cost afterwards; MariaDB 10.5's support status.

## Known differences from the VPS design

- **The accessible static 404 page is mostly lost.** The static page answers errors the web server itself produces (denied paths) but OJS still prints its own bare `404 Not Found` for an unknown route, so the Phase 2 accessibility finding returns for those pages (`docs/A11Y-REPORT.md`, not-covered list).
- **No firewall, no per-site server tuning, less isolation;** ModSecurity may block admin actions (Day-0 H).
- **Backups are weaker** (above). **No Cloudflare**, so no rate limiting on `/login`: OJS's own protections only, to be decided after launch.
- **The host patches the server:** the monthly reboot step of the VPS design is replaced by checking the plan renewal and PHP version notices (`docs/HANDOVER.md`).
- **Email depends on the mailbox's SMTP limit and its price after the first year** (`docs/LAUNCH-BLOCKERS.md`).
