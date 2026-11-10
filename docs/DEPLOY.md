# Deploy (stub, completed in Phase 5.4)

This file is created early so that production-safety rules are written down before anyone runs a script. Phase 5.4 adds the full steps, rollback, DNS and Cloudflare.

## Loading the placeholder pages on production

`scripts/import-pages.php` creates the custom navigation-menu pages from `ojs/content/`.

1. **Take a backup first** (database dump and the files directory) and check that it can be read. A flag or a habit is not a backup.
2. Run it **once**: `php scripts/import-pages.php --journal=PATH --check` first (dry run), then without `--check`. It is create-only: a second run only skips. Never use `--force-sandbox`; it refuses to run unless `base_url` is localhost.
3. Pages a human has edited (placeholder banner gone) are never touched by the script, so editing in OJS afterwards is safe.
4. `ojs/content/` and `ojs/fixtures/` hold placeholders and fake samples. They are not deployed content; the launch gate (Phase 8.3) requires `make check-placeholders` to be empty.
