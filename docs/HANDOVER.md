# Handover guide

For the journal administrator and editors of World Open Research Journal. Written by the developer on 2026-11-10 from what was built and tested in a local sandbox. **Nothing in it has been run on the live server**, and the client has not reviewed it yet. Items that need the signed scope or a client input are marked **BLOCKED**.

Labels used: `VERIFIED-SANDBOX 2026-11-10` (seen on screen in the sandbox, in a throwaway journal that was deleted afterwards), `UNVERIFIED (...)` (not seen or not run), `BLOCKED` (waiting on a person), `[CLIENT DECISION]`.

## Where things are

| You want to | Read |
|---|---|
| Set the journal up or change a setting, step by step | `docs/ADMIN-SETUP-CHECKLIST.md` |
| Test the editorial workflow end to end | `docs/QA-SCRIPT.md` |
| Run or check the host (shared hosting) | `docs/DEPLOY-SHARED.md` |
| See what must be true before launch, and who does it | `docs/LAUNCH-GATES.md`, `docs/LAUNCH-BLOCKERS.md` |
| Set up DOIs (blocked on the client) | `docs/DOI-SETUP.md` |
| See which services the journal has applied to (none yet) | `docs/INDEXING-READINESS.md` |
| Add the journal to Google Search | `docs/SEARCH-CONSOLE.md` |

## Roles and access

- **Editors get the *Journal Manager* role, never the site administrator role.** The roles list in Settings > Users & Roles > Roles shows, for example, *Journal manager*, *Journal editor*, *Production editor*, *Section editor*, *Copyeditor* and *Layout Editor*, each with a permission level of *Journal Manager*, *Section Editor* or *Assistant* (`VERIFIED-SANDBOX 2026-11-10`).
- **The developer's own administrator account is removed or its ownership is transferred** to a named person at the client (`docs/LAUNCH-GATES.md` gate 6.1).
- **A break-glass administrator exists.** Its password is in the client's password manager and is held by the client's named business owner; the operator holds nothing. How to recover an administrator account if everything else fails is in `docs/DEPLOY.md` ("Administrator recovery").
- OJS has **no two-factor authentication**. The compensations are unique strong passwords in a password manager, the rate limits at Cloudflare, and key-only SSH on the server.
- **The client's own logins stay with the client:** Cloudflare, the mail provider, the backup bucket and, later, Crossref.

## Everyday administration

The left menu of the editor dashboard lists *Editor Dashboard, Issues, DOIs, Settings, Statistics, Tools, Administration*. *Settings* has *Journal, Website, Workflow, Distribution* and *Users & Roles* (`VERIFIED-SANDBOX 2026-11-10`). The step-by-step paths for every setting are in `docs/ADMIN-SETUP-CHECKLIST.md`.

The Editor Dashboard groups submissions into views such as *Needs editor, All in submission stage, Needs reviews, Awaiting reviews, Reviews submitted, Reviews overdue, Author revisions submitted, All in review stage, All in copyediting stage, All in production stage, Scheduled for publication, Published* and *Declined* (`VERIFIED-SANDBOX 2026-11-10`).

Things to know before changing anything:

- **Submissions can be switched off** (Settings > Workflow > Disable Submissions). The text authors then see is OJS's own wording; see `docs/QA-SCRIPT.md` finding QF4.
- **Mail notices go to the journal contact email**, so it must be a monitored role address (`docs/QA-SCRIPT.md` QF3, decision D23).
- **Do not turn on DOIs or install a registration agency** until `docs/DOI-SETUP.md` is complete.

## How to publish an issue

Seen in the sandbox in a throwaway journal (`VERIFIED-SANDBOX 2026-11-10`), on an article that had already reached the production stage. The editorial steps before that (review, decision, copyediting) are in `docs/QA-SCRIPT.md`; copyediting itself was not walked (`UNVERIFIED`).

1. **Create the issue:** Issues > Future Issues > *Create Issue*. Fill *Volume*, *Number* and *Year* and tick their "show" boxes (or give a *Title*); OJS refuses to save otherwise. *Save*.
2. **Add the galley:** open the article > Publication > *Galleys* > *Add galley*; give the label (for example PDF), save, then upload the real PDF file. The PDF's first page must show the title and every author.
3. **Assign the issue and fill the details:** Publication > *Issue*: choose the issue and the section, and **fill *Pages*** (the citation tags need it, `docs/QA-SCRIPT.md` QF2). Press *Schedule For Publication* and confirm.
4. **Publish the issue:** Issues > Future Issues > *Publish Issue*. **The box "Send an email about this to all registered users" is ticked by default: untick it unless you want every registered user emailed.** Press *OK*.
5. **Check the result:** open the article page and the PDF, then ask the operator to run `scripts/check-citation-meta.sh URL` and `scripts/check-pdf.sh URL` on the article (both must pass), and `scripts/check-discovery.sh --robots-mode production URL` after a batch.

## After a theme change

- **Theme changes can take up to an hour to appear to visitors.** Theme files are cached for one hour by the server (there is no Cloudflare at launch; if Hostinger's CDN is turned on later, whoever deploys a theme change purges it too), and a visitor's browser may still show the old version for up to an hour. Do not re-deploy in a panic if a change is not visible at once.

## Routine care of the hosting (the operator)

- **Scheduled tasks run from a hosting cron job, not from website visits.** If review reminders or statistics emails ever stop, nothing shows an error: ask the operator to run the scheduler check (`docs/DEPLOY-SHARED.md` step 8): `worj-logs/scheduler.log` must end with `end exit=0` within two cron intervals, and the hPanel cron job must still exist.
- **The host patches the server, so there is no reboot step.** Once a month the operator checks the plan's renewal date, the PHP version notices in hPanel (OJS 3.5 needs PHP 8.2 or newer: do not let the site be moved to an older one), the scheduler log, and the date of the last pulled backup, and writes down that it was done.
- **Backups.** Hostinger keeps its own daily backups (7 days, `AGENT CLAIM`), **not encrypted to the client's key**. Ours is `scripts/pull-backup.sh`, which someone has to run: **the recovery point is only as fresh as the last run** (gate 3.3 and blocker A38 name who and how often). It is encrypted with the client's public key; **only the client holds the private key**. A restore needs that key, off the host (`docs/DEPLOY-SHARED.md`, "Backups"). A restore must be rehearsed once before launch.
- **Do not connect Hostinger's Git deployment to this repository's `main`** (`docs/DEPLOY-SHARED.md`, "Delivery"): releases are built and deployed by `scripts/build-release.sh` and `scripts/deploy-shared.sh`.
- **HSTS** starts short and is raised in stages after launch, never with preload at launch.

## Accessibility: what was checked and what was not

The theme was **checked against WCAG 2.2 AA with these tools**, on the sandbox site with placeholder content, and the report is `docs/A11Y-REPORT.md`:

- **axe-core 4.14.0** through `@axe-core/playwright` 4.14.0, with the WCAG 2.0, 2.1 and 2.2 A and AA rule tags, on the ten theme-rendered pages (home, about, article, issue, archive, login, register, search, submissions, contact) at 320 px and 1280 px, plus the 404 page;
- **Lighthouse** (accessibility category), run by `make eval`;
- the developer's own scripts: `checks/a11y-manual.js` (document structure, keyboard targets, reflow, contrast, motion), `checks/forms-errors.js` (a failed login and a failed registration), and `scripts/check-contrast.py` (colour pairs);
- keyboard and focus checks run as scripts in Chromium (Playwright 1.63.0) at 320, 640 (for the 200 % zoom check) and 1280 px; **no human tester used a keyboard or an assistive technology**.

**This is not a conformance statement and not a certification.** A claim of WCAG 2.2 AA conformance on the public site would need an audit with assistive technology, on the real content. **The public site must not say or imply conformance, a certification, or a score** (`docs/LAUNCH-GATES.md` gate 7.1).

**What was not covered** (copied from `docs/A11Y-REPORT.md`):

- **Screen readers: none was tested (NVDA, JAWS, VoiceOver, TalkBack).** Everything is automated measurement and keyboard testing.
- Voice control, switch access, screen magnifiers, and Windows forced-colours or high-contrast mode.
- Browsers other than Chromium, real devices, and touch targets measured on a real phone.
- WCAG 1.4.12 text spacing and 1.3.4 orientation.
- Authenticated pages and the submission, review and editorial workflows (OJS's own screens, which are not themed).
- The accessibility of the PDF galleys, which depends on how the client prepares them.
- Real content: headings, link text, images and alt text, tables and language changes that editors write.
- Email notifications.
- Usability testing with disabled users.

One conditional exception: if the client chooses the ALTCHA bot protection (decision D21, not enabled), the registration page needs JavaScript (`docs/A11Y-REPORT.md`).

## Support terms (from the signed scope, as given)

- **Included:** 14 days of post-launch defect support for issues directly caused by the delivered configuration.
- **Not covered:** new features, client content changes, third-party outages, server compromise caused by compromised client credentials, plugin updates that introduce new compatibility problems, and new integrations.
- **After the 14 days:** ongoing maintenance can be quoted separately, with hours and response times agreed in writing.

**BLOCKED:**

- **The support contact** (name and email): to be supplied by the developer.
- **The date the 14 days start:** to be confirmed in writing at launch.

## What the client keeps

The age private key; the Cloudflare, mail-provider and backup-bucket logins; the break-glass administrator credential (held by the named business owner); the repository, delivered with its licence and copyright notice (`docs/LAUNCH-GATES.md` gate 1.9). Anything still undecided is in `docs/LAUNCH-BLOCKERS.md`.
