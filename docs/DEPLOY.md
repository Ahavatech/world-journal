# Deploying the journal to a VPS

**Nothing in this document has been run on a VPS.** Every step that touches a real server is `UNVERIFIED (not run on VPS)`. What was checked, and how, is in the table below; read it before trusting a step. The scripts exist so that a human runs them in a known order, with a way back at each stage.

## What was and was not tested

| Piece | Tested here (sandbox) | Not tested (`UNVERIFIED (not run on VPS)`) |
|---|---|---|
| `scripts/provision-ubuntu.sh` | `shellcheck`; `--check` on the sandbox host and on a fresh chroot (tree snapshots identical); OS refusals (22.04, 24.10, Debian, non-LTS, wrong `--os`); settings validation; a **debootstrap Ubuntu 24.04 chroot provisioned twice (second run `changed: 0`)** with OJS installed and answering through the rendered Nginx; a secret-leak check (process list, logs, history, files) | a real VPS; systemd units; the real firewall and sshd; certbot issuance; real DNS and mail |
| Firewall and SSH stages | real `ufw` (rules only) and real `sshd -t` / `sshd -T`; the `00-` ordering proof; every refusal; the revert command executed as the timer would | `ufw enable`, an sshd reload, a second login, systemd timers |
| Nginx | `nginx -t`; a local Nginx in front of the sandbox OJS: redirects, deny rules, upload not executed, `files_dir` unreachable, headers, 404 pages, JSON 404 on `/api/`, asset crawl of public and admin pages, axe on the 404 page | real TLS, real Cloudflare, real traffic |
| Cloudflare ranges | fixtures and a local HTTP server (the live URL is blocked in the sandbox) | the real fetch, SSL mode, rate limiting |
| Backup and restore | real database dump, age encryption, rclone to a local remote, failure alerts, retention, restore into a scratch database with a collision guard | a real remote, the client's key custody, cron execution |
| Admin recovery | the reset on the sandbox, confirmed by logging in through the real OJS form | the rehearsal on staging |

## Decisions the client must make `[CLIENT DECISION]`

Defaults are what the scripts do when nobody decides. The owner's view is a recommendation, not a choice made for the client.

| # | Decision | Default in the scripts | Recommendation |
|---|---|---|---|
| P1 | Main host: apex or `www` | none: both host names are required and must differ | either works if the other redirects and the certificate covers both |
| P2 | Certificate: Cloudflare Origin CA, or certbot **HTTP-01** (these are the only two implemented) | `CERT_METHOD=origin` (you place the files) | Origin CA is simplest while the site stays proxied. Choose certbot HTTP-01 if the client might leave Cloudflare: an origin certificate shows browser errors the moment the proxy is paused. HTTP-01 needs the host name to resolve to this server (proxy set to "DNS only") for the first issuance |
| P3 | Firewall: 80/443 open to all, or only to Cloudflare (**do not create AAAA records unless Nginx is configured for IPv6**: the origin listens on IPv4 only) | open to all (`FIREWALL_CLOUDFLARE_ONLY=no`) | open during setup; restrict to Cloudflare once the site works behind it, so the origin cannot be reached directly with the rate limits bypassed. This blocks direct-IP testing. Only the IPv4 ranges are used (the origin listens on IPv4 only) |
| P4 | HSTS | `max-age=300`, no preload, no `includeSubDomains` | raise in stages by hand; no preload at launch |
| P5 | Swap file | none | reasonable on a small VPS (not scripted: add it by hand) |
| P6 | Time zone | **none: the script refuses to run without one** | the client's choice |
| P7 | Cloudflare Access in front of `/index/admin` | not used | optional, only after the plain setup works, and it must not block `/api/` for logged-in users |
| P8 | Backup remote versioning or object lock | not controlled by the scripts | **strongly recommended** (see Backups) |
| P9 | Where OJS runs scheduled tasks and queued jobs | **cron, every minute** (`/etc/cron.d/worj`); the web runners are switched off | decided from the source, see "Scheduled tasks" below |
| P10 | `open_basedir` for PHP-FPM | not set | an **optional** hardening measure, not something we claim: it needs its own tested path list (see Hardening notes) |
| D21 | Bot protection (see the admin checklist) | none | `require_validation = On` plus Cloudflare rate limiting first; ALTCHA only if spam appears |

## Scheduled tasks: why cron, and what a quiet site would miss

Read from the pinned 3.5.0-6 source:

- `lib/pkp/classes/core/ScheduleServiceProvider.php` (lines 46 to 65): with `[schedule] task_runner = On` (the shipped default) OJS registers a PHP shutdown function on an ordinary **web request**, and only if the last run is older than `task_runner_interval` (60 s). **Nothing runs unless a request arrives.**
- The runner executes the Laravel scheduler, and `Illuminate\Console\Scheduling\Event::isDue` runs a task only when its **cron expression matches the current minute**. `daily()` is `0 0 * * *` and `monthlyOn(1)` is `0 0 1 * *` (`ManagesFrequencies::daily` is `hourBasedSchedule(0, 0)`). On a quiet site a daily or monthly task is skipped unless a request happens to land in that exact minute.
- Tasks defined in `classes/scheduler/Scheduler.php` and `lib/pkp/classes/scheduledTask/PKPScheduler.php` that a low-traffic journal would miss: **daily** `ReviewReminder` (reviewer reminders), `UsageStatsLoader` (usage statistics), `DepositDois`, `OpenAccessNotification` (subscriptions), `RemoveFailedJobs`, `RemoveExpiredInvitations`; **monthly** `EditorialReminders`, `StatisticsReport` (the editorial statistics emails), `SubscriptionExpiryReminder`, `RemoveUnvalidatedExpiredUsers`, `UpdateRorRegistryDataset`, and on the 10th `UpdateIPGeoDB`. `ProcessQueueJobs` (queued emails) runs every minute only when `[queues] process_jobs_at_task_scheduler` is On.

So the config template sets `task_runner = Off`, `job_runner = Off` and `process_jobs_at_task_scheduler = On`, and `/etc/cron.d/worj` runs `php lib/pkp/tools/scheduler.php run` every minute as `www-data` (log: `/var/log/worj-scheduler.log`). `check-live-config.py` fails if the web runner is left On. In the chroot test the exact cron command ran as `www-data`, listed the tasks above and exited cleanly; cron itself executing it is `UNVERIFIED (not run on VPS)`. Turning reminders on or off is a client decision (D4 in the admin checklist); the scheduler only makes them reliable.

## Caching of theme files

OJS appends `?v=<OJS application version>` to theme CSS and JS (`PKPTemplateManager.php`, lines 2224 and 2313), never the theme's own version, and theme images carry no version. A theme update therefore keeps the same URLs, so Nginx caches `/plugins/themes/` for **one hour** (clients then revalidate), while OJS core files, whose `?v=` changes on an OJS upgrade, are cached for 7 days. Cloudflare honours these `Cache-Control` values. After a theme update, purge the Cloudflare cache if the change must show at once.

## Content Security Policy: report-only means no protection

Nginx sends `Content-Security-Policy-Report-Only` on public pages and **no policy at all** on the admin pages. **This protects nothing yet and is not counted as a hardening measure.** In a test with an enforcing copy of the policy, 6 violations appeared on 2 public pages (the contact page and the galley viewer need inline script or style) and 28 on 7 admin pages. Enforcing is possible only after those are fixed or allow-listed and a crawl is clean (`make infra-test-nginx` prints the result). ALTCHA, if chosen, would also need `blob:` workers.

## Before you start (inputs)

1. A VPS with **Ubuntu 24.04 LTS**, a provider **snapshot** taken now, and the provider's **browser console** (out-of-band rescue) tested once.
2. Your own account (`OPERATOR_USER`) with sudo and your SSH **key** already working. Note the key login in the log: the SSH stage refuses without a recent `Accepted publickey`.
3. DNS: the host names pointing at the VPS (through Cloudflare, proxied, when the site goes live). **Create A records only. Do not create AAAA records unless Nginx is configured for IPv6**: the origin listens on IPv4 only, so an AAAA record would send some visitors to a port that does not answer.
4. **An `age` key pair, made by the client, off the server**: `age-keygen -o worj-backup.key`. Give the server only the **public** key (`age1...`). The **private key never goes on the server** (the scripts refuse it); keep it in the client's password manager and in one offline copy.
5. A backup bucket you own (rclone remote), with **versioning or object lock enabled**.
6. Mail provider credentials: a **provider-issued app password or API credential**, never a personal mailbox password.
7. The Cloudflare Origin CA certificate and key if `CERT_METHOD=origin`.
8. A **non-default administrator username** and a strong password from the client's password manager.

## Stages, in order, each with its way back

Rollback is never literal: package upgrades, database changes and a firewall lockout cannot be undone by a script. Each stage lists what can be undone, what cannot, and the provider snapshot is the fallback for all of it.

### 0. Snapshot

Take a provider snapshot. **Rollback for everything below:** restore the snapshot (you lose changes made since).

### 0b. Rehearse on a throwaway VPS first

The firewall and SSH stages are the ones that can lock you out, and they were only stub-tested here. **Before the client's server, run the whole sequence (provision, firewall and SSH with the second-terminal confirmation, backup, restore rehearsal) end to end on a fresh disposable VPS** (take a provider snapshot first and rehearse the console rescue), fix what it shows, then repeat on the real one. A throwaway VPS costs very little compared with a lockout on the client's server. This is a Phase 8.3 launch-gate item.

### 1. Get the code

```bash
sudo apt-get update && sudo apt-get install -y git
sudo git clone https://github.com/Ahavatech/world-journal /opt/worj-src
cd /opt/worj-src && sudo scripts/fetch-ojs.sh      # pinned OJS, checksum verified, into ojs-core/
```

Rollback: `sudo rm -rf /opt/worj-src`.

### 2. Settings file

```bash
sudo install -d -m 700 /etc/worj
sudo install -m 600 infra/provision.env.example /etc/worj/provision.env
sudoedit /etc/worj/provision.env        # replace every REPLACE value; no secret on a command line
```

The file holds `ADMIN_PASSWORD` and `SMTP_PASSWORD`. **After a successful install the script removes the `ADMIN_PASSWORD` line itself** (the password then exists only as a hash in the database) and **forces a password change at the first login** (`must_change_password`); both are tested in the chroot run. `SMTP_PASSWORD` stays, because it is needed later: the file is root-only, mode 600; do not copy it anywhere. The salt, the API key secret and the database password are not in this file; the script generates them.

### 3. Dry run

```bash
sudo scripts/provision-ubuntu.sh --env /etc/worj/provision.env --os 24.04 --check
```

Read every `WOULD:` line. `--check` changes nothing. The script refuses anything but Ubuntu 24.04 LTS and refuses when `--os` and the machine disagree.

### 4. Provision (everything except the firewall and SSH)

```bash
sudo scripts/provision-ubuntu.sh --env /etc/worj/provision.env --os 24.04 --skip-firewall --skip-ssh
```

Stages, in order, and the way back for each:

| Stage | What it does | Way back |
|---|---|---|
| preflight | validates OS, settings, names | nothing changed |
| packages | installs the packages it needs | `apt-get remove` them (data is not touched) |
| php | PHP ini, a dedicated FPM pool, disables the default pool | each replaced file is kept as `FILE.worj-bak`; move it back and `systemctl reload php8.3-fpm` |
| mariadb | tuning file, database, user; the database password is generated into `/etc/worj/secrets.env` (mode 600, never printed) | `DROP USER` / `DROP DATABASE` by hand |
| ojs-code | copies the pinned OJS and the theme to the web root | re-run with the previous source; `config.inc.php`, `public/` and `cache/` are never overwritten |
| ojs-config | renders `config.inc.php`, runs the CLI installer (answers file mode 600, deleted on exit), re-applies `allowed_hosts` and `time_zone`, generates a strong salt and API key secret, then `check-live-config.py` must pass | the installer cannot be undone: restore the snapshot or drop the database and delete `config.inc.php` |
| cloudflare-ip | fetches Cloudflare's ranges for the real client address. **It stops the whole run with an explanation if no ranges exist yet** | the previous file is kept on any failure |
| nginx | installs a port-80 bootstrap site until the certificate exists, then the full site | `*.worj-bak` next to each replaced file |
| certbot | with `origin`: checks your files (key mode 600, 30+ days left, key matches). With `certbot`: requests a certificate (HTTP-01; the proxy must be "DNS only" for the first issuance) | n/a |
| nginx-final | the full site with TLS | as nginx |
| unattended | security updates, **no automatic reboot** | delete the two files in `/etc/apt/apt.conf.d/` |
| backup-cron | installs `worj-backup`, the cron file, logrotate, backup settings | delete `/etc/cron.d/worj` |

Re-running the same command changes nothing (`changed: 0`): it was shown on a clean Ubuntu 24.04 chroot, twice.

### 5. Firewall and SSH (the dangerous stage)

Do this only after the Hostinger or provider **browser console** works.

```bash
sudo scripts/provision-ubuntu.sh --env /etc/worj/provision.env --os 24.04 --stage firewall --stage ssh
```

The SSH stage checks everything first (sudo group, valid keys, a recent key login in the log, that you are in an ssh session), writes `/etc/ssh/sshd_config.d/00-worj.conf` (the `00-` prefix wins over `50-cloud-init.conf`: proven with `sshd -T`), verifies the effective settings, schedules a **10-minute revert**, and reloads (not restarts) ssh. The firewall allows only 22, 80 and 443, with SSH first.

**Now open a second terminal and log in with your key.** If it works:

```bash
sudo scripts/provision-ubuntu.sh --env /etc/worj/provision.env --os 24.04 --confirm-ssh
```

If it does not work, do nothing: after 10 minutes both changes revert on their own. Out-of-band rescue: the provider's browser console. `UNVERIFIED (not run on VPS)`: the timers, `ufw enable` and the reload were stubbed in tests.

### 6. Cloudflare `UNVERIFIED (not run on VPS)`

1. DNS records proxied (orange cloud) once the origin answers over HTTPS.
2. **SSL/TLS mode: Full (strict).** With the origin certificate (or Let's Encrypt) in place.
3. **Rate limiting** on the login and registration paths (`/login`, `/user/register`, `/index/login`, `/index/user/register`): Block or Managed Challenge. The exact dashboard options and how many rules the Free plan allows were not checked here.
4. Optional later: Cloudflare Access on `/index/admin` (P7); firewall restricted to Cloudflare (P3).

Rollback: set the DNS records to "DNS only"; set SSL mode back; remove the rule.

### 7. Create the journal, load the placeholder pages

Create the journal in the admin interface, then follow `docs/ADMIN-SETUP-CHECKLIST.md`. Loading the placeholder pages (`scripts/import-pages.php`) and any users or articles (`docs/IMPORT.md`): **take a backup first and run each file once.** `--i-have-a-backup` is a speed bump: nothing verifies a backup. **A users import sends a registration email to every new user**: the client decides (D22) whether to import real users at all; never run it against real addresses until SMTP works, the sending domain passes SPF, DKIM and DMARC, and every email template has been read and approved.

### 8. First backup and a restore rehearsal (see Backups below)

### 9. DNS for the sending domain (SPF, DKIM, DMARC) and Search Console

OJS sends mail **from the Technical Support Contact address** (checklist step 6.3). Mail from a domain without authentication usually lands in spam or is rejected, and with `require_validation = On` that stops people registering.

1. Use a transactional mail provider and **its issued app password or API credential**.
2. Publish the DNS records the provider gives you: **SPF** (a TXT record naming the provider), **DKIM** (the provider's selector record), **DMARC** (a TXT record at `_dmarc`, starting with a monitoring policy). Do not invent the values.
3. Send a real "Validate Your Account" email through production (register a test account) and read the headers: SPF, DKIM and DMARC should pass.
4. **Search Console:** add the property and publish the **verification TXT record** Google gives you at the DNS provider; then submit `https://HOST/sitemap` and inspect a real article URL (Phase 6.4).

## Staging versus production: robots and noindex

`ROBOTS_MODE` in `provision.env` has **no default** and the script refuses a missing or unknown value. **`staging`** serves `robots.txt` with `Disallow: /` and sends `X-Robots-Tag: noindex, nofollow` on every response; **`production`** serves the normal `robots.txt` (the shipped `Disallow: /cache/` plus `Sitemap: https://HOST/index/sitemap`) and no `X-Robots-Tag`. The classic launch failure goes both ways: a staging site that gets indexed, or a live site left on `noindex` and never found. `scripts/check-discovery.sh --robots-mode MODE https://HOST` fails if the site does not match its mode, and it is a **Phase 8.3 launch-gate item** (run with `--launch`). Switching a site from staging to production is: set `ROBOTS_MODE=production`, re-run the `nginx` stage, then run the check. Tested in the sandbox with the rendered Nginx (`make infra-test-nginx`); `UNVERIFIED (not run on VPS)`.

## Smoke tests (after stage 5 and again after Cloudflare)

```bash
curl -sI http://HOST/ | head -3                               # 301 to https://HOST/
curl -sI https://ALT_HOST/ | head -3                          # 301 to https://HOST/
curl -sI https://HOST/index.php/JOURNAL/about | head -3       # 301 to /JOURNAL/about
curl -s -o /dev/null -w '%{http_code}\n' https://HOST/config.inc.php   # 404
curl -s -o /dev/null -w '%{http_code}\n' https://HOST/.git/config      # 404
curl -s https://HOST/index/login | grep -c 'name="username"'           # 1
curl -sI https://HOST/ | grep -i -E 'strict-transport|x-content-type|content-security'
curl -s https://HOST/JOURNAL/no-such-page | grep -c 'Page not found'   # 1 (static 404; JOURNAL is the journal path, so create the journal first)
sudo python3 -I scripts/check-live-config.py /var/www/worj/config.inc.php --host HOST --web-root /var/www/worj --owner root:www-data
scripts/check-placeholders.sh --url https://HOST/JOURNAL        # must be empty at launch (Phase 8.3)
sudo stat -c '%y' /var/log/worj-scheduler.log                   # modified within the last 2 minutes (the scheduler ran)
sudo tail -n 3 /var/log/worj-scheduler.log                      # "Running [...]" lines with a time, no PHP errors
```

**Scheduler check, because nothing else tells you it stopped.** The cron line runs the scheduler every minute and appends to `/var/log/worj-scheduler.log` (a rotated file, never mail: `MAILTO=""`). With `process_jobs_at_task_scheduler` On, each run prints at least one `Running [ProcessQueueJobs...]` line (Laravel `ScheduleRunCommand`: a run with nothing due prints `No scheduled commands are ready to run.` instead), so the log's modification time moves every minute. **If it stops, review reminders, statistics emails and queued emails stop silently**: no error page, no alert. Operator checks:

1. After stage 4, wait two minutes and run the `stat` line above (`UNVERIFIED (not run on VPS)`).
2. **After the first full day** (server time is the clock, daily tasks fire at 00:00): `sudo grep -a -c 'Running \[' /var/log/worj-scheduler.log` is in the hundreds, and `sudo grep -a 'Running' /var/log/worj-scheduler.log | grep -a -v ProcessQueueJobs | tail` shows the daily tasks (for example `ReviewReminder`, `UsageStatsLoader`).
3. Repeat the `stat` line at every monthly reboot check, and put the log mtime on the same external heartbeat as the backup if the client wants an alert.

## Backups

`worj-backup` runs nightly at 02:17 server time: database dump, `files_dir`, `public/` and `config.inc.php`, **all encrypted with `age` before anything is stored or sent, the local copy included**. Retention: 14 daily and 8 weekly locally; remote objects older than 15 days (daily) and 57 days (weekly) are pruned with `rclone delete` (never `sync`).

- **The server cannot decrypt its own backups.** It holds only the public key. **Decryption and the restore rehearsal are done by the operator, with the client's private key, on a staging machine or the operator's own machine**, never by leaving the key on the server. The dumps hold password hashes and submission data.
- **Sanity checks** (before encryption): valid gzip, mysqldump's completion line, size, table count, users rows, not suspiciously smaller than the last backup. Any failure writes `/var/backups/worj/FAILED`, logs to syslog and runs `WORJ_ALERT_CMD`. Watch `/var/backups/worj/last-success` with an external heartbeat so a silent cron failure is also noticed.
- **A compromised server can still delete remote backups.** Enable **bucket versioning or object lock** at the remote (strongly recommended, P8).
- **Restore rehearsal** (operator side; needs an OJS code tree and a database user that may create a scratch database):

```bash
scripts/restore.sh --bundle worj-YYYYmmddTHHMMSSZ.tar.age --identity worj-backup.key \
  --code-dir ojs-core --live-config PRODUCTION_config.inc.php --scratch-db worj_restore_check --db-defaults restore.cnf
```

  It decrypts, verifies the manifest, loads a scratch database, serves a throwaway copy on localhost and requires the login page. **It refuses** if the scratch database name equals the production name, does not contain `restore`, contains odd characters, or if the live config is missing. Do the rehearsal before launch and after any change to the backup scripts.

## Administrator recovery

1. **Preferred:** a **second break-glass site administrator** account, created before launch, with its password in the client's password manager. The credential is held by **the client's named business owner** (and the operator holds nothing). Editors get the **Journal Manager** role, never the site administrator role.
2. **Last resort, as root on the server:** `scripts/reset-ojs-admin-password.sh --config /var/www/worj/config.inc.php --username NAME` reads the new password on standard input (or a prompt), hashes it with the same function OJS uses (`password_hash` bcrypt cost 12, from the 3.5.0-6 source), updates `users.password` and sets `must_change_password`. Tested on the sandbox with a real OJS login. **Rehearse it on staging**, not for the first time during an outage. OJS 3.5.0-6 has no password-reset command line tool.
3. OJS core has **no two-factor authentication** (checked in the source and the Plugin Gallery). Compensate with the rate limiting above, unique passwords in a password manager, and the key-only SSH rule.

## Routine operation

- **Reboots.** Unattended upgrades install security updates but **never reboot**, so a new kernel takes effect only after a reboot. Check `ls /var/run/reboot-required` (and `cat /var/run/reboot-required.pkgs`) at least monthly. **Operator monthly step:** if the file exists, reboot in a quiet window agreed with the editors (announce it first), then re-run the smoke tests below and confirm `systemctl is-active nginx php8.3-fpm mariadb`.
- **Backups.** Watch `/var/backups/worj/last-success` with an external heartbeat; run a restore rehearsal before launch and after any backup change.
- **Raise HSTS in stages** after launch (P4); purge the Cloudflare cache after a theme update.
- **Theme updates:** re-run the `ojs-code` stage (it syncs the theme), then **purge the Cloudflare cache** (dashboard: Caching > Configuration > Purge Cache; purge everything, or the changed files by URL under `/plugins/themes/worj/`) `UNVERIFIED (not run on VPS)`. Without the purge, visitors may keep the old copy for up to one hour (the Nginx cache time for theme files) or longer in Cloudflare's own copy. Check with `curl -sI https://HOST/plugins/themes/worj/styles/main.css | grep -i -E 'cf-cache-status|age|cache-control'` after the purge (adjust the path to a real theme file).

## Handover

At handover the **developer's own administrator account is removed, or its ownership is transferred to the client** (a named person, a role address the client controls). Also: the break-glass administrator exists and its credential is held by the client's named business owner; the operator account and SSH keys are the client's choice; the Cloudflare, mail-provider and backup-bucket logins belong to the client; the age private key is with the client (the developer never needs it after the first rehearsal).

## Hardening notes (optional measures; we do not claim them)

- **`open_basedir`** for the PHP-FPM pool would limit which directories PHP may read. It is **not set**: it needs its own tested path list (the web root, `files_dir`, `/tmp`, PHP's own directories) and a full crawl, including uploads and the admin UI, before it is safe. Treat it as an optional extra.
- **Content-Security-Policy** is report-only: no protection (see above).
- **Cloudflare Access** in front of `/index/admin` (P7) and restricting 80/443 to Cloudflare (P3) are optional later steps.
- OJS core has no two-factor authentication.

## Installing OJS: the CLI installer

The provision script uses the command-line installer `php tools/install.php` (it exists in 3.5.0-6). The answers are piped on standard input from a file with mode 600 that is **deleted on exit, even on failure**; the password comes from the root-only settings file or a one-time prompt, never from a command line. Prompt order: locale, additional locales (empty), files directory, administrator username, password twice, email, database driver, host, user, password, name, OAI repository identifier, send usage beacon (n), install (y). **The installer leaves the salt at the public default, `api_key_secret` empty, rewrites `allowed_hosts` to `[""]` and blanks `time_zone`**: the script generates the secrets and re-applies the other two, then `check-live-config.py` must pass. After an OJS pin change, `make setup` fails until `scripts/make-config-template.py` is re-run and its diff reviewed.

## Rolling back, honestly

- **Config files:** each replaced file is kept once as `FILE.worj-bak`.
- **Safety timers:** SSH and the firewall revert by themselves after 10 minutes unless confirmed.
- **Snapshot:** the only complete undo. Take one before stage 4 and again before stage 5.
- **Restore from backup:** brings back the data, not the server.
- **Not undoable by a script:** package upgrades, database changes from the installer, a firewall lockout without console access.

## Not tested (every item `UNVERIFIED (not run on VPS)`)

ufw enable, an sshd reload and a second login, systemd units and timers, certbot issuance and renewal, the real Cloudflare range fetch, SSL mode and rate limiting, real DNS (SPF, DKIM, DMARC, Search Console), real mail delivery, a real rclone remote, the client's age key custody, the admin recovery rehearsal on staging, performance of the 4 GB tuning, anything on a VPS.
