# Deploy (stub, completed in Phase 5.4)

This file is created early so that production-safety rules are written down before anyone runs a script. Phase 5.4 adds the full steps, rollback, DNS and Cloudflare.

## Loading the placeholder pages on production

`scripts/import-pages.php` creates the custom navigation-menu pages from `ojs/content/`.

1. **Take a backup first** (database dump and the files directory) and check that it can be read. A flag or a habit is not a backup.
2. Run it **once**: `php scripts/import-pages.php --journal=PATH --check` first (dry run), then without `--check`. It is create-only: a second run only skips. Never use `--force-sandbox`; it refuses to run unless `base_url` is localhost.
3. Pages a human has edited (placeholder banner gone) are never touched by the script, so editing in OJS afterwards is safe.
4. `ojs/content/` and `ojs/fixtures/` hold placeholders and fake samples. They are not deployed content; the launch gate (Phase 8.3) requires `make check-placeholders` to be empty.

## Installing OJS: the CLI installer (same path as the sandbox)

**Which method:** the command-line installer `php tools/install.php`, which exists in 3.5.0-6 (`ojs-core/tools/install.php`, class `OJSInstallTool`) and is the path `scripts/sandbox-ojs.sh` used. Why not the web installer: the CLI route is scriptable and repeatable, its answers are recorded, and the install page is never exposed to the internet where anyone could reach it first. The web installer was not tried.

1. Fill `ojs/config/config.inc.php.template` into `config.inc.php`: replace every `@@TOKEN@@` from `.env`, and **generate** `@@SALT@@` and `@@API_KEY_SECRET@@` (long random strings). **The installer does not do this**: in the sandbox it left the salt at the shipped public default `YouMustSetASecretKeyHere!!` and `api_key_secret` empty. `installed` stays `Off`; it is not set to `On` by hand, the installer does that.
2. Create the database and its user (Phase 5 provisioning).
3. Run the installer with the answers on standard input, **from a file with mode 600**, not typed on the command line (shell history). The order of prompts, taken from `scripts/sandbox-ojs.sh` and checked against `lib/pkp/classes/cliTool/InstallTool.php`: locale, additional locales (empty), files directory, administrator username, password, password again, email, database driver, host, user, password, name, OAI repository identifier, send usage beacon (n), install (y). **Choose a non-default administrator username** (checklist 9.2).
4. **Afterwards**, compare the result with the template: `installed` is now `On` and `app_key` is generated (both expected). The installer also **rewrote `allowed_hosts` to `[""]`, which rejects every request**, and **blanked `time_zone`** in the sandbox: set both again. Expected differences are listed in `docs/PHASE4-NOTES.md`.
5. After an OJS pin change, `make setup` fails until `scripts/make-config-template.py` is re-run and its diff reviewed.

Nothing here has been run on a VPS.

## Importing real users and articles

Use `scripts/import-ojs-xml.sh` (usage and safeguards in `docs/IMPORT.md`), never the raw tool. **Take a backup first and run each file once.** `--i-have-a-backup` is only a speed bump: nothing verifies the backup. **WARNING: a users import sends a registration email to every newly created user.** The client decides (decision D22 in `docs/ADMIN-SETUP-CHECKLIST.md`) whether to import real users at all or let them self-register. **Never run it against real addresses until SMTP works, the sending domain passes SPF, DKIM and DMARC, and every enabled email template has been read and approved.** Real files live in `ojs/import/` (gitignored, personal data).

## DNS for the sending domain (SPF, DKIM, DMARC)

OJS sends mail **from the Technical Support Contact address** (checklist step 6.3). Mail from a domain without authentication usually lands in spam or is rejected, and with `require_validation = On` that stops people registering.

1. Use a transactional mail provider and **its issued app password or API credential**, never a personal mailbox password (checklist 6.5, 9.4).
2. Publish the DNS records the provider gives you for the sending domain: **SPF** (a TXT record naming the provider), **DKIM** (the provider's selector record) and **DMARC** (a TXT record at `_dmarc`, starting with a monitoring policy). The provider's setup page lists the exact values; do not invent them.
3. Send a real "Validate Your Account" email through production (register a test account) and read the message headers: SPF, DKIM and DMARC should all report a pass (`HUMAN`).
4. This is a Phase 8.3 launch-gate item. Nothing here has been run on a VPS.
