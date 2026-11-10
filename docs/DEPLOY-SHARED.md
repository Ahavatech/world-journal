# Deploying to the shared hosting plan (Hostinger "Unlimited" web hosting)

**Status: part 1 of 2. Nothing in this document has been run on the host.** The client bought a **shared web hosting plan** (managed hosting on LiteSpeed), not a root VPS, so `docs/DEPLOY.md` (the VPS path) does **not** apply to this client. This file is the shared-hosting path. Part 1 records what is known about the plan and gives the **Day-0 checks** a person runs on the host before anything else is built or deployed: their results decide several choices below.

Decisions already made by the client: the canonical host is **`worldopenresearchjournal.com`** (no `www`; `www` redirects to it); **no Cloudflare at launch** (DNS stays at Hostinger so the mailbox's SPF and DKIM records stay as they are, and Hostinger's own CDN setting stays off while testing). The mailbox is **`editorial@`**, with aliases `support@`, `privacy@` and `doi@`.

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
| Staging | Subdomains are available (the agent said up to 100, none created yet). The plan's CPU, memory and PHP workers are **per plan**, so a staging site **shares them** with production (my reading of the limits table) | Subdomain count `AGENT CLAIM`; limits `READ 2026-11-10` [limits](https://www.hostinger.com/support/6976044-parameters-and-limits-for-hosting-plans) |
| CDN versus Cloudflare | Hostinger warns against running its CDN and Cloudflare together as two caching layers | `AGENT CLAIM` (the agent cited Hostinger's CDN-versus-Cloudflare article, which was not read here) |

## What this changes compared with the VPS design

- **Provisioning, firewall, SSH hardening, certbot, unattended upgrades, the reboot step and the Cloudflare real-IP files no longer apply:** the host runs them.
- **The Nginx rules become an `.htaccess`** (redirects, deny rules, headers, `robots.txt`), tested in a stand-in Apache and then again on the host's staging site.
- **The accessible static 404 page is mostly lost.** On Apache-style servers `ErrorDocument` shows only for errors the web server generates (our deny rules), not for OJS's own bare `<h1>404 Not Found</h1>`. The Phase 2 accessibility finding returns.
- **Backups are weaker** than the VPS design (the host's backups are not encrypted with the client's key; ours must be pulled from outside).
- **Less control and isolation:** ModSecurity may block admin actions, there is no per-site server tuning, and staging shares the production limits.

## Day-0 checks (about half an hour, run by the client or the operator)

Run these **before** anything else is built or deployed. **Do not paste a password, a key's private half or any credential into chat, into the repository or into a ticket.** Write each result in the table at the end, with the date and your name. The test files and pages below are temporary and must be deleted when done.

**A. Create a protected staging subdomain** (for the rest of the checks): in the dashboard create `staging.worldopenresearchjournal.com`, password-protect it, and keep the production site untouched.

**B. SSH** (dashboard SSH access page; the exact menu name is `UNVERIFIED`):
1. Enable SSH. Use a **key**, not a password: give the operator only the **public** key to add.
2. Log in and run `pwd`. **Write the real home path** (it contains the account folder `uXXXXXXXXX`; do not paste it anywhere public).
3. Run each of these and write the version or "not found": `php -v`, `php -m`, `mysqldump --version`, `mysql --version`, `tar --version`, `rsync --version`, `git --version`, `composer --version`, `python3 --version`, `age --version`, `rclone --version`.
4. Compare `php -v` with the PHP version shown in the dashboard's PHP configuration: **are they the same minor version?**

**C, D and F: the Day-0 kit** (a ready-made test folder; replaces the manual `phpinfo()`, folder and `.htaccess` checks). The kit is `infra/shared-hosting/day0-kit/worj-day0/` (its `README.txt` says how to use it).
1. In the dashboard's PHP configuration, choose **PHP 8.3** (the version the sandbox tests ran) for the staging site.
2. Upload the folder `worj-day0` to the **web root of the staging subdomain**, so that `https://STAGING_HOST/worj-day0/probe.php` exists. **Never upload it to the production site.** The staging site must be password-protected.
3. Tell the developer. The developer runs `scripts/probe-day0-kit.sh https://STAGING_HOST` (a staging login goes in a netrc file or the secure credential card, **never on a command line**) and reports every line. It checks: the PHP version, every extension on the OJS README list plus `mysqli`, the memory, upload and execution limits, `open_basedir`, whether PHP can write **above the web root** (where the private files folder goes), and thirteen small `.htaccess` features, each in its own folder (a 301 redirect, rewrite to `index.php`, deny rules, headers including on error responses, a conditional header, `ErrorDocument`, cache lifetimes, redirect for GET and HEAD but not POST, no PHP in a protected folder, no directory listing, and whether `php_value` is allowed).
4. **Delete the `worj-day0` folder** afterwards. The probe prints only non-secret facts, never `phpinfo()` or environment variables, and masks the account folder as `uXXXXXXXXX`.

The kit and the probe are tested in the sandbox against a **stand-in Apache, not LiteSpeed** (`make infra-test-day0`): that proves the files are valid Apache-style rules and that the probe tells a working host from a broken one, but only the real run on the host shows what LiteSpeed does.

**E. Cron:** in the dashboard create a **test** cron job on the staging account.
1. What is the **shortest interval** the dashboard offers? (OJS needs one that divides 60 and includes minute 0.)
2. Can a PHP-type job run `…/lib/pkp/tools/scheduler.php` **with an argument** (`run`), or is a custom job with a small `.sh` file needed?
3. Does the job's output appear in the dashboard, and is there a maximum run time?
4. Delete the test job.

**F. `.htaccess` on LiteSpeed:** done by the kit (see "C, D and F" above); nothing to do by hand.

**G. Email:** create the SMTP settings from the `editorial@` mailbox's own page (host, port, encryption: read them from there). Send **one** test message from OJS (staging) to an inbox the tester controls. Write: did it arrive, did it reach spam, what **From** and **Reply-To** did it show, and does SMTP accept a From that differs from the login?

**H. ModSecurity:** on staging, once OJS is installed, try one large upload and one admin action. If something is blocked, write the exact URL and the time, and look for the security log (its location is `UNVERIFIED`).

**I. Backups and the database:** in the dashboard, note the MariaDB version, whether `utf8mb4` is the default, the backup schedule, and what a restore asks for. Do **not** run a restore on production.

### Day-0 results

| Check | Result (write it) | Date and name | Decides |
|---|---|---|---|
| B2 home path | NOT RUN | | `files_dir` and the cron paths |
| B3 tools present (`php`, `mysqldump`, `rsync`, `git`, `composer`, `python3`, `age`, `rclone`) | NOT RUN | | whether config checks and encrypted backups can run on the host |
| B4 CLI PHP equals web PHP | NOT RUN | | whether the CLI installer and the scheduler use the same PHP |
| C extensions missing, PHP version and limits (kit) | NOT RUN | | whether the plan can run OJS at all |
| D write above `public_html`; `open_basedir` (kit) | NOT RUN | | where `files_dir` goes |
| E shortest cron interval; argument support; run time | NOT RUN | | the scheduler design |
| F `.htaccess` directives that worked (kit, thirteen folders) | NOT RUN | | which rules the `.htaccess` template can rely on |
| G SMTP: arrival, spam, From and Reply-To | NOT RUN | | the mailbox and sender design |
| H ModSecurity blocks | NOT RUN | | whether exceptions are needed |
| I MariaDB version, backups | NOT RUN | | the database lifecycle question and the backup plan |

## What part 2 will add

After the Day-0 results: the `.htaccess` template and its test harness, the release package and deploy script, the installer and configuration steps, the scheduler wrapper, the backup and staging-restore procedure, and the staging-then-production runbook. Until then none of those exist, and nothing here is a claim that the host is tested.
