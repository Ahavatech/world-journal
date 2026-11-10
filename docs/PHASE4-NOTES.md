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
| Admin hardening, credentials, importer note (section 9) | written; none run on a VPS |

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
- Probe journal now carries: theme worj, awards card on, blocks on, navigation assigned. The probe journal was deleted at the end of session 1 (`DELETE /index/api/v1/contexts/2`).

## State at the end of session 1 and what session 2 does

- Checklist sections 1 to 9 are written in `docs/ADMIN-SETUP-CHECKLIST.md`. Every `UNVERIFIED` is labelled with its reason; nothing was run on a VPS.
- No two-factor feature found in OJS core 3.5.0-6 (Plugin Gallery not checked). The admin username cannot be renamed in the profile form (source reading): choose it at install.
- Session 2: **4.2** (verify `php tools/importExport.php list`, the `native` and `users` usage, record the real invocations, then wrapper scripts with the safeguards above) and **4.3** (`ojs/config/config.inc.php.template`, lint against `ojs-core/config.TEMPLATE.inc.php`, record how the sandbox install was done; `require_validation` is a config decision, see section 6.6).
- Not walked: Distribution > Access, Archiving, Registration, PKP Preservation Network, LOCKSS/CLOCKSS tabs; Website > Setup > Information texts; Workflow > Submission > Metadata defaults; the Author role dialog; reviewer-invitation email.

## Session 2, start (review points from session 1)

- Done: launch-gate items in `docs/03-TASKS.md` 8.3 (default text replaced or confirmed; real validation email; SPF/DKIM/DMARC; client reads every enabled email template); Phase 5 task 5.2c (Cloudflare rate limiting on login and registration, editors get Journal Manager not site administrator, documented admin recovery path); DEPLOY.md DNS section.
- D21 (bot protection) added. CAPTCHA findings: reCAPTCHA loads `https://www.recaptcha.net/recaptcha/api.js` (remote script); ALTCHA is self-hosted but needs JavaScript (registration fails with JS off) and four same-origin `blob:` worker requests. Neither is on by default.
- 2FA: Plugin Gallery (101 plugins, 2026-11-10) has no two-factor plugin; no third-party plugin recommended.
- `scripts/ojs-default-wording.txt` (31 fragments, generated from `ojs-core/locale/en/default.po`, checked by `make lint`) is used by `check-placeholders.sh --url`; the sandbox journal still shows the default submission checklist (6 hits).
- Script guard: `scripts/lib/sandbox-guard.js` + `scripts/test-sandbox-guard.js` (12 cases in `make lint`); wired into `sandbox-api.js`, `sandbox-seed.js`, `sandbox-content.js`.
- Walked now: Website > Information (defaults present in the editors and on public pages); Distribution > Access (publishing mode and OAI were on the **Access** tab, not "Setup": corrected), Archiving (PN, LOCKSS and CLOCKSS), DOIs > Registration.
- Mailpit: v1.33.1, sandbox only.

## Session 2: 4.2 and 4.3 (done)

- **4.2** `scripts/import-ojs-xml.sh` + `scripts/import-precheck.py`, documented with the recorded tool output in `docs/IMPORT.md`; 18 negative and positive tests in `scripts/test-import-wrapper.sh` (stub OJS, run by `make lint`). Real runs in the sandbox: users (2 throwaway `.invalid` accounts) and a native issue with 3 sample articles into the throwaway `probe` journal. New users are emailed by the tool; existing users are not updated; the same file is refused the second time.
- **4.3** `ojs/config/config.inc.php.template` generated from the shipped file by `scripts/make-config-template.py` (23 deliberate overrides, each with a reason); `scripts/check-config-template.py` lints it (unknown keys, missing required keys, real-looking secrets, `installed`, pin, first-line guard); 12 cases in `scripts/test-config-template.sh`; `scripts/ojs-config-keys.txt` (117 keys) lets CI run the lint without `ojs-core/`. `make setup` fails after a pin change until the template is regenerated.
- **Install findings (sandbox, 2026-11-10):** the CLI installer `php tools/install.php` exists and was used. It sets `app_key` and `installed = On`, but leaves `salt` at the public default and `api_key_secret` empty; it rewrites `allowed_hosts` to `[""]` and blanks `time_zone`. Provisioning must generate the salt and API key secret and reset `allowed_hosts` and `time_zone`.
- Not done: a full install from the template on a clean database (only a filled-template diff against the sandbox install); web installer; real SMTP.

## Final state (end of session 2)

- `docs/ADMIN-SETUP-CHECKLIST.md`: 20 table rows still carry `UNVERIFIED`. Reasons: not yet run on a VPS (9.1, 9.2, 9.3b, 9.4, 9.6, 6.5, 6.8, 5.4); no author submission walked (3.3, 3.6); defaults of each metadata option not recorded (3.7); role dialog not opened, label from the locale file (5.2); reviewer-invitation email needs a submission in review, Phase 8.2 (6.7); DOIs back on is blocked on the client (7.2); ticked-masthead public output not observed (8.9); text fields not saved in this session, Phase 3 importer verified earlier (8.12, 8.13); open access policy, LOCKSS/CLOCKSS licence texts and help texts have no screen found, privacy statement tab not opened (D13, D14); Cloudflare bot features not checked (D21).
- Sandbox cleaned: the `probe` journal, the throwaway users and `ojs/import/` contents were deleted.
