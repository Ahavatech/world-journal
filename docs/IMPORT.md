# Importing users and articles (task 4.2)

OJS 3.5.0-6 ships its own import tool, `tools/importExport.php`. This page records **what that tool actually prints** (run in the sandbox on 2026-11-10) and how `scripts/import-ojs-xml.sh` wraps it. Nothing here has been run on a VPS.

## Recorded tool output (OJS 3.5.0-6)

The plugin names on the command line are the **class names**, not "native" or "users":

```text
$ php tools/importExport.php list
Available plugins:
    UserImportExportPlugin
    PubMedExportPlugin
    NativeImportExportPlugin
    DOAJExportPlugin
```

```text
$ php tools/importExport.php NativeImportExportPlugin usage
Commands:
    import [xmlFileName] [journal_path] [--user_name] ...
    export [xmlFileName] [journal_path] articles [articleId1] [articleId2] ...
    export [xmlFileName] [journal_path] article [articleId]
    export [xmlFileName] [journal_path] issues [issueId1] [issueId2] ...
    export [xmlFileName] [journal_path] issue [issueId]
If the root node is <article> or <articles>, additional parameters are required:
    import [xmlFileName] [journal_path] [--user_name] issue_id [issueId] section_id [sectionId]
    import [xmlFileName] [journal_path] [--user_name] issue_id [issueId] section_name [name]
    import [xmlFileName] [journal_path]              issue_id [issueId] section_abbrev [abbrev]
```

```text
$ php tools/importExport.php UserImportExportPlugin usage
Commands:
    import [xmlFileName] [journal_path]
    export [xmlFileName] [journal_path]
    export [xmlFileName] [journal_path] [userId1] [userId2] ...
```

The invocations that worked in the sandbox (the account name is passed as the argument after the journal path for a native import):

```bash
php tools/importExport.php UserImportExportPlugin import ojs/import/users.xml worj
php tools/importExport.php NativeImportExportPlugin import ojs/import/issue.xml worj ADMIN_ACCOUNT
```

A native import of an issue file printed "The import completed successfully. The following items were imported: Submission … Issue …". A failing import exits non-zero (255 in my runs).

## What I learned about the formats and behaviour

- **Users XML** (root `PKPUsers`, namespace `http://pkp.sfu.ca`) must contain `user_groups` with **at least one `user_group`**, then `users`. Each `user` needs `givenname`, `familyname`, `email`, `username`, `password`, **`date_registered`** (without it the import crashes in the database layer), and `user_user_group` containing `user_group_ref` (the role name) **and a `masthead` element**. A working shape is what `php tools/importExport.php UserImportExportPlugin export FILE JOURNAL` writes: start from an export.
- **An export contains password hashes and real email addresses.** Treat every users file as personal data: it belongs in `ojs/import/`, which is in `.gitignore`.
- **New users are emailed.** For each newly created user the tool sends OJS's registration message (the tool printed a mail-connection error per user when no mail server was reachable, yet still exited 0 and created the users). Importing real users therefore sends real email: set up and test the `[email]` settings first.
- **Existing users are not updated.** Re-importing a file with a changed family name left the stored name unchanged; the same username and email only has its role assignments re-applied. A username and email that belong to different accounts is reported as an error.
- A native import of the same articles twice would create them twice: OJS does not de-duplicate. The wrapper therefore refuses to import the same file twice.

## The wrapper

```bash
scripts/import-ojs-xml.sh users  FILE --journal=PATH [--check]
scripts/import-ojs-xml.sh native FILE --journal=PATH --user-name=ACCOUNT [--issue-id=N --section-abbrev=X] [--check]
```

Safeguards (each has a test in `scripts/test-import-wrapper.sh`, run by `make lint`):

- **Create-only in practice:** a file's SHA-256 is recorded in `ojs/import/.done/` after a successful import; the same file is refused afterwards. `--again` exists for localhost only.
- **Fake data never reaches a real target:** if `base_url` is not localhost, the file is refused when it holds any address on a **`.invalid`** domain or any title or author that `ojs/fixtures/manifest.json` marks `sample=true` (plus the words "sample article", "sample issue", "not a real publication", "placeholder author").
- **Real data stays out of git:** for a non-localhost target the file must live in `ojs/import/` (gitignored).
- **Never prints an email address:** the pre-check prints counts only and the tool's output is redacted.
- **`--i-have-a-backup` is a speed bump, not proof.** Nothing checks that a backup exists or restores. Take a real backup and test the restore first (`docs/DEPLOY.md`). A users import to a non-localhost target also needs `--i-understand-users-are-emailed`.
- Run on production **once**, after the backup.
- `--check` runs only the pre-flight checks and imports nothing.

Not covered: article PDFs and galleys in a real native XML file (the sample XML embeds its files), conflicts in sections or issues, and large files. A real migration is out of scope (`CLAUDE.md`).
