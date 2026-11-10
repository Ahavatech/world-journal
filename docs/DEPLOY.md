# Deploy (stub, completed in Phase 5.4)

This file is created early so that production-safety rules are written down before anyone runs a script. Phase 5.4 adds the full steps, rollback, DNS and Cloudflare.

## Loading the placeholder pages on production

`scripts/import-pages.php` creates the custom navigation-menu pages from `ojs/content/`.

1. **Take a backup first** (database dump and the files directory) and check that it can be read. A flag or a habit is not a backup.
2. Run it **once**: `php scripts/import-pages.php --journal=PATH --check` first (dry run), then without `--check`. It is create-only: a second run only skips. Never use `--force-sandbox`; it refuses to run unless `base_url` is localhost.
3. Pages a human has edited (placeholder banner gone) are never touched by the script, so editing in OJS afterwards is safe.
4. `ojs/content/` and `ojs/fixtures/` hold placeholders and fake samples. They are not deployed content; the launch gate (Phase 8.3) requires `make check-placeholders` to be empty.

## Importing real users and articles

Use `scripts/import-ojs-xml.sh` (usage and safeguards in `docs/IMPORT.md`), never the raw tool. **Take a backup first and run each file once.** `--i-have-a-backup` is only a speed bump: nothing verifies the backup. A users import emails every new user, so test the mail settings first. Real files live in `ojs/import/` (gitignored, personal data).

## DNS for the sending domain (SPF, DKIM, DMARC)

OJS sends mail **from the Technical Support Contact address** (checklist step 6.3). Mail from a domain without authentication usually lands in spam or is rejected, and with `require_validation = On` that stops people registering.

1. Use a transactional mail provider and **its issued app password or API credential**, never a personal mailbox password (checklist 6.5, 9.4).
2. Publish the DNS records the provider gives you for the sending domain: **SPF** (a TXT record naming the provider), **DKIM** (the provider's selector record) and **DMARC** (a TXT record at `_dmarc`, starting with a monitoring policy). The provider's setup page lists the exact values; do not invent them.
3. Send a real "Validate Your Account" email through production (register a test account) and read the message headers: SPF, DKIM and DMARC should all report a pass (`HUMAN`).
4. This is a Phase 8.3 launch-gate item. Nothing here has been run on a VPS.
