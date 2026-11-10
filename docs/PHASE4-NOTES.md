# Phase 4 notes (resume point)

A cleared session resumes from this file, `docs/ADMIN-SETUP-CHECKLIST.md`, `docs/PHASE3-NOTES.md` and the git history. Two sessions: **session 1 = 4.1 only** (this one), **session 2 = 4.2 and 4.3**.

## Rules that apply (from review)

- Labels: `VERIFIED-SANDBOX <date>`, `UNVERIFIED (not yet run on VPS)`, `UNVERIFIED (<reason>)`. Never plain "VERIFIED".
- Decision rows are `[CLIENT DECISION]` with the OJS default beside them; never pick a value; email templates carry no timeframes or policy claims.
- Email credentials: provider-issued app password or API credential, never a personal mailbox password.
- Admin hardening: unique strong password in the client's password manager, non-default admin username, two-factor only if 3.5.0-6 offers it (verify).
- Try Mailpit in the sandbox for registration and reviewer-invitation emails; if it cannot be installed, SMTP is `UNVERIFIED` with the reason.
- Importers (session 2): backup first, run once; refuse `sample=true` and `.invalid` into a non-localhost base URL; `ojs/import/` gitignored; never print email addresses.
- `removeOption()` for the parent theme options is already done; do not redo it.

## Method

Walkthroughs run in the sandbox against a **throwaway journal `probe`** (path `/probe`, journal id 2), created through the REST API, so the real sandbox journal `worj` is not disturbed and the steps start from what a brand-new journal looks like. Delete `probe` when finished (see the end of this file).

## Progress

| Section | State |
|---|---|
| Decision table | written (`docs/ADMIN-SETUP-CHECKLIST.md`), defaults read from the settings store; every "Where" menu path still to be confirmed on screen in the later sections |
| Masthead and contact (section 1) | written, `VERIFIED-SANDBOX 2026-11-10` |
| Sections (section 2) | written, `VERIFIED-SANDBOX 2026-11-10` |
| Submission settings, review settings and forms, users and roles (sections 3, 4, 5) | written; checked on screen except where marked UNVERIFIED |
| Email templates, notifications and delivery (section 6) | written; reviewer-invitation email UNVERIFIED (no submission in review) |
| Distribution: DOI, licence, search description (section 7) | written; DOI-off and meta description checked in the sandbox |
| Website: theme, navigation, blocks, masthead, announcements, Highlights (section 8) | written; most steps checked on screen |
| Admin hardening, email credentials, importer note, launch notes | pending |

## Findings so far

- A fresh OJS 3.5.0-6 journal ships default text with policy claims in several settings (open access, privacy, author guidelines, reader and librarian information, LOCKSS/CLOCKSS licences, submission checklist, help texts). They are decision rows D10, D13, D14. The real journal must either keep them knowingly or replace them.
- Self-registration is **on** by default for Author, Reviewer and Reader (row D11).
- Review reminders are **off** by default; review mode default is double-anonymous (rows D1, D4).
- The sandbox nginx start script can reload instead of start after a restart when `/run/worj-sandbox/nginx.pid` is stale (pid reused). Remove the file and run `scripts/sandbox-ojs.sh up` again.

## Tooling notes (session 1)

- Walkthrough helpers are throwaway Playwright scripts kept in the session scratchpad, not in the repo. Pattern: log in at `/index/login` with the generated admin, open the page, click tabs with `getByRole('tab', {name})`, read labels and the **✓ Saved** status. Playwright resolves from `NODE_PATH=/opt/node22/lib/node_modules`.
- The admin pages are a Vue app: buttons in tab panels are sometimes not `role=button`; `getByText(label, {exact:true})` worked for **Create Section**.
- Saving a form with an empty required field showed no message in my selectors; do not claim the UI warns.
- Journal Settings (Settings > Journal) tabs: Masthead, Contact, Sections, Categories. Required: title, initials, country; contact name and email; technical support name and email.
- Decision table corrected after on-screen checks: review mode labels, deadline labels, reminders (four selectors, all "No reminder set"), licence (no option chosen; "Other license URL" selected and empty), copyright notice under Workflow > Submission > Author Guidance, DOIs **on** by default (D19), publishing mode has no radio selected.
- Roles table (Settings > Users & Roles > Roles) is not a `<table>` I could drive with my selectors; the Author role dialog was not opened. D11 is therefore `UNVERIFIED` on screen (database values verified).

## Mail catcher (session 1)

- Mailpit v1.33.1 (`github.com/axllent/mailpit` release tarball, linux amd64) was downloaded into the scratchpad and run as `mailpit --smtp 127.0.0.1:1025 --listen 127.0.0.1:8025`. **The download was not checksum-verified** (no checksum was fetched); it was used only on the sandbox, never installed into the repo.
- Sandbox only: `ojs-core/config.inc.php` (gitignored) `[email]` got `default = smtp`, `smtp_server = 127.0.0.1`, `smtp_port = 1025`, then `require_validation = On` to provoke an email. The file was restored from a backup afterwards.
- Result: registration with `require_validation = Off` sends no email; with `On` it sends "Validate Your Account" (from = Technical Support Contact, absolute link, signature, no unreplaced variables).
- Reviewer-invitation email not rendered (needs a submission in review with a reviewer; Phase 8.2 script).
- Carry to 4.3: `[email] require_validation` is a config decision; `default`, `smtp_*` are set at provisioning from `.env`.

## Distribution findings (session 1)

- DOIs are **on** by default in 3.5.0-6; unticking and saving removes the **DOIs** sidebar item (checked).
- Setting Search Indexing > Description makes the homepage emit `<meta name="description">`; before it, none (checked by fetching the homepage).
- Public COUNTER SUSHI statistics are on by default (D20); OAI on by default.
- Not walked: Access, Archiving, Registration, PKP Preservation Network, LOCKSS/CLOCKSS tabs.

## Website findings (session 1)

- Menu assignment is drag and drop in the **Edit** dialog of Settings > Website > Setup > Navigation (click the menu name). Playwright `mouse.down/move/up` with small steps works; `dragTo` was not tried. Dropping on an item inside *About* nests under it.
- **Mishap, repaired:** a script with an empty id clicked the first edit link (the *Register* item in the throwaway `probe` journal) and saved the title "Editorial Team" there. I deleted that title setting row (probe only, id 42) and redid the change on the Editorial Masthead item (id 55). Lesson: never build a selector from an empty variable; assert the id first.
- The Make a Submission block plugin: enabling the plugin is not enough; the block must also be ticked in Appearance > Setup > Sidebar, then Save. Enabled-state in the plugin grid lags; read the database or the homepage.
- Announcements are **disabled** on a new journal; enrollment masthead is **enabled**.
- Probe journal now carries: theme worj, awards card on, blocks on, navigation assigned. Delete it before finishing.
