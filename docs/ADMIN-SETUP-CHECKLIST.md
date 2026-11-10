# Admin setup checklist (OJS 3.5.0-6)

Status of this document: **work in progress, built section by section** (Phase 4, task 4.1). Sections not written yet are listed in `docs/PHASE4-NOTES.md`.

## How to read the labels

| Label | Meaning |
|---|---|
| `VERIFIED-SANDBOX <date>` | I performed the step in the local sandbox (OJS 3.5.0-6, a throwaway journal) and saw the stated result. It says nothing about the real server. |
| `UNVERIFIED (not yet run on VPS)` | A production step. Nothing has been run on the real VPS. |
| `UNVERIFIED (<reason>)` | I could not perform or observe it, for the stated reason. |
| `HUMAN` | A person must do it (decision, credential, real content). |
| `[CLIENT DECISION]` | The client chooses. This checklist never picks the value. |

## Decision table `[CLIENT DECISION]`

Every row is a choice that belongs to the client and the editors. **The "OJS default" column is what a brand-new journal holds in OJS 3.5.0-6**, read from a freshly created throwaway journal in the sandbox on 2026-11-10 (`VERIFIED-SANDBOX 2026-11-10`: REST `GET /api/v1/contexts/{id}` and the database). The "chosen value" column stays empty until the client decides. Nothing below is a recommendation.

| # | Setting | Where (path seen on screen) | OJS default (fresh journal) | Chosen value |
|---|---|---|---|---|
| D1 | Review model | Settings > Workflow > Review > Setup > **Default Review Mode** (radios: *Anonymous Reviewer/Anonymous Author*, *Anonymous Reviewer/Disclosed Author*, *Open*) | *Anonymous Reviewer/Anonymous Author* selected (`defaultReviewMode = 2`) | |
| D2 | Time for a reviewer to respond to a request | Settings > Workflow > Review > Setup > **Default Response Deadline** | 4 (weeks) | |
| D3 | Time for a reviewer to complete a review | Settings > Workflow > Review > Setup > **Default Completion Deadline** | 4 (weeks) | |
| D4 | Reviewer reminders on or off, and when | Settings > Workflow > Review > Setup > **Set Reminders for Review** (four selectors: request response before or after the due date, review submission before or after the due date) | all four show **No reminder set** (reminders are off) | |
| D5 | Reviewer access options | Settings > Workflow > Review > Setup: **One-click Reviewer Access**, **Restrict File Access**, **Reviewer Suggestion at Submission**, **Minimum Confirmed Reviews Required** | the three checkboxes are unticked; minimum confirmed reviews is 0 | |
| D6 | Licence | Settings > Distribution > License > **License** | none chosen: *Other license URL* is selected with an empty field | |
| D7 | Copyright holder | Settings > Distribution > License > **Copyright Holder** (*Author*, *Journal*, *Custom copyright statement*) | none selected | |
| D8 | Copyright year basis | Settings > Distribution > License > **Copyright Year** | *Use the issue's publication date* | |
| D9 | Copyright notice shown to authors at submission | Settings > Workflow > Submission > Author Guidance > **Copyright Notice** | empty | |
| D10 | Submission checklist item text | Settings > Workflow > Submission > Author Guidance > **Submission Checklist** | **OJS ships a default list of items.** It is policy-adjacent, so it is kept as shipped until the client rewrites it; it is not authored here | |
| D11 | Who may self-register as author, reviewer or reader | Settings > Users & Roles > Roles (path to be confirmed in section 4) | Author **yes**, Reviewer **yes**, Reader **yes**; every other role no | |
| D12 | Article processing charge (APC) statement | There is no APC field. Payments: Settings > Distribution > Payments > **Payments will be enabled for this journal**. Any APC wording belongs on a policy page | payments off; no statement | |
| D13 | Publishing mode, and the open access policy text | Publishing mode: Settings > Distribution > Setup > **Publishing Mode** (*open access*, *subscription*, *not used to publish online*). The `openAccessPolicy` text: field location `UNVERIFIED (not found in the sandbox UI yet)` | no publishing mode selected; **OJS ships a default open access policy text** ("immediate open access") | |
| D14 | Other default texts that make claims: author guidelines, reader and librarian information, privacy statement, LOCKSS and CLOCKSS licence texts, submission help texts | author guidelines under Settings > Workflow > Submission > Author Guidance; others `UNVERIFIED (locations confirmed in later sections)` | **OJS ships default wording for each** (the sandbox journal's copies were emptied and replaced by placeholder pages in Phase 3) | |
| D15 | Show real masthead users (on) or the written editorial team text (off) | `enableEnrollmentMasthead`; screen path to be confirmed in section 9 | on | |
| D16 | Review forms (questions reviewers answer) | Settings > Workflow > Review > Review Forms | none exist | |
| D17 | Editorial statistics emails to editors | to be confirmed in section 5 | on (`editorialStatsEmail`) | |
| D18 | Which authors receive submission acknowledgement and decision emails | to be confirmed in section 5 | all authors (`submissionAcknowledgement = allAuthors`, `notifyAllAuthors = true`) | |
| D19 | DOIs: on or off, prefix, assignment time and suffix pattern | Settings > Distribution > DOIs | **DOIs are ON by default**, only *Articles* ticked, prefix empty, assignment *Upon reaching the copyediting stage*, suffix *Default*, registration agency "No Registration Agency Enabled" | |

**Email template rule:** the email templates stay exactly as OJS ships them, or are shortened to contain **no timeframes and no policy claims**. The checklist never asks anyone to type a deadline into a template. The template review is its own section below (pending).

**Defaults and paths were checked on screen in the sandbox on 2026-11-10** (`VERIFIED-SANDBOX 2026-11-10`) except where a cell says `UNVERIFIED` or "to be confirmed"; later sections resolve those and correct this table if one differs.

## Conventions in the steps

Menu paths are the **left sidebar** of the admin interface: *Editor Dashboard, Issues, DOIs, Settings (Journal, Website, Workflow, Distribution, Users & Roles), Statistics, Tools, Administration* (`VERIFIED-SANDBOX 2026-11-10`). "Save" is the button at the bottom right of each form; after a successful save a green **"✓ Saved"** appears beside it (`VERIFIED-SANDBOX 2026-11-10`). Steps below were performed on a throwaway journal at `/probe` in the sandbox with placeholder values; the real journal's URL path is `worj` (Phase 3 content uses it).

## 1. Journal masthead and contact

Open **Settings > Journal**. The page is titled **Journal Settings** and has four tabs: **Masthead, Contact, Sections, Categories** (`VERIFIED-SANDBOX 2026-11-10`).

| Step | Do | Expected visible result | Status |
|---|---|---|---|
| 1.1 | Tab **Masthead**, group *Journal Identity*: set **Journal title** (required) and **Journal initials** (required). Use "World Open Research Journal" and its initials. Fill **Journal Abbreviation** only if the client has one. | Fields accept the text. | `VERIFIED-SANDBOX 2026-11-10` (fields present and marked required) |
| 1.2 | Group *Publishing Details*: choose **Country** (required). Fill **Publisher** and **URL** with the client's real values (`HUMAN`). Leave **Online ISSN** and **Print ISSN** empty until the client supplies real numbers. **Never type an invented ISSN.** | After choosing a country and pressing Save, **✓ Saved** shows and the country is stored (checked in the database). Saving with the country empty showed no visible message in my run, so do not rely on the form to warn you. | Country and Save `VERIFIED-SANDBOX 2026-11-10`; real values `HUMAN` |
| 1.3 | Group *Editorial Masthead > Editorial History*: this is the text the public **Editorial Team** page shows when the masthead users setting is off (see step 9.2). Paste the approved text here (`HUMAN`); until then the Phase 3 placeholder stands. | Text editor accepts input; public page `/about/editorialMasthead` shows it once saved. | Field present `VERIFIED-SANDBOX 2026-11-10`; public result `VERIFIED-SANDBOX 2026-11-10` (Phase 3 sandbox, `PHASE3-NOTES.md`) |
| 1.4 | Group *Description*: **Journal Summary** (short description, used on the homepage) and **About the Journal** (the public `/about` page). Paste approved text (`HUMAN`). The Phase 3 placeholder text for About lives in `ojs/content/pages/about.html`. | Save shows **✓ Saved**. | `VERIFIED-SANDBOX 2026-11-10` |
| 1.5 | Tab **Contact**, group *Principal Contact*: **Name** and **Email address** are required; Phone, Affiliation and Mailing Address are optional. Use a **role address** the client controls (for example one the journal's domain owns), not a personal mailbox (`HUMAN`). | After filling and saving: **✓ Saved**. | `VERIFIED-SANDBOX 2026-11-10` (placeholder values) |
| 1.6 | Group *Technical Support Contact*: **Name** and **Email address** are **also required** here. Enter the person or address that will handle login and technical problems (`HUMAN`). | Saved together with 1.5. | `VERIFIED-SANDBOX 2026-11-10` (the form lists these four fields as required) |

Real values are `HUMAN` steps. In the sandbox, every field accepted `example.invalid` addresses and `[PLACEHOLDER: ...]` text without rejecting them (`VERIFIED-SANDBOX 2026-11-10`), so the form will not warn if a placeholder is left in place: `make check-placeholders-url` against the live site is the guard (Phase 8 launch gate).

## 2. Sections

Still under **Settings > Journal**, tab **Sections**.

| Step | Do | Expected visible result | Status |
|---|---|---|---|
| 2.1 | Look at the list. A new journal already has one section, **Articles**, with Editors "None". | A table with columns *Title, Editors, Inactive* and a **Create Section** button. | `VERIFIED-SANDBOX 2026-11-10` |
| 2.2 | Decide the section list with the client (`[CLIENT DECISION]`: names, whether each is peer-reviewed). Keep, rename or add sections. | The decided list. | `HUMAN` |
| 2.3 | **Create Section**. The dialog asks for **Section title** and **Abbreviation** (both required), optional **Section Policy**, **Word Count** (0 = no limit), and checkboxes: inactive, *Will not be peer-reviewed*, *Do not require abstracts*, *Will not be included in the indexing of the journal*, *Items can only be submitted by Editors and Section Editors*, omit title or author names from the table of contents, plus **Identify items published in this section as a(n)** and *Editorial Assignments*. **Press Save.** | The dialog closes and the new section appears in the table (an **Order** button also appears once there are two sections). | `VERIFIED-SANDBOX 2026-11-10` (created `[PLACEHOLDER: section title]`, abbreviation `PLC`) |
| 2.4 | Do not type policy wording in *Section Policy* until the client supplies it. | Field stays empty. | `HUMAN` |

## 3. Submission settings (checklist, guidance, copyright notice)

Open **Settings > Workflow**. The page is **Workflow Settings** with main tabs **Submission, Review, Publisher Library, Emails**. Under *Submission* the sub-tabs are **Disable Submissions, Author Guidance, Metadata, Components**; under *Review* they are **Setup, Reviewer Guidance, Review Forms** (`VERIFIED-SANDBOX 2026-11-10`).

| Step | Do | Expected visible result | Status |
|---|---|---|---|
| 3.1 | **Submission > Author Guidance.** The page holds the headings *Author Guidelines, Before you begin, Submission Checklist, Upload Files, Contributors, Details, For the Editors, Review and Submit, Copyright Notice, For Reviewer Suggestion*. | All the headings listed are on the page. | `VERIFIED-SANDBOX 2026-11-10` |
| 3.2 | Replace *Author Guidelines* with the approved text (`HUMAN`). The Phase 3 placeholder is `ojs/content/pages/author-guidelines.html`; import it as in `docs/DEPLOY.md` or paste it. | Public page `/about/submissions` shows the text. | Public page `VERIFIED-SANDBOX 2026-11-10` (Phase 3) |
| 3.3 | *Submission Checklist* `[CLIENT DECISION]` (D10): OJS ships a default list. Keep it as shipped or replace it with client text (`HUMAN`). **Do not write checklist items in this repository.** | The author sees the items as ticks in the submission wizard. | Field present `VERIFIED-SANDBOX 2026-11-10`; the wizard view `UNVERIFIED (no author submission was walked in this session)` |
| 3.4 | *Copyright Notice* `[CLIENT DECISION]` (D9): empty by default. Leave empty until the client decides the licence and holder (D6, D7). | Field empty. | `VERIFIED-SANDBOX 2026-11-10` (empty on a new journal) |
| 3.5 | Press **Save** on the Author Guidance form. | **✓ Saved** beside the button. | `VERIFIED-SANDBOX 2026-11-10` (saved with no change; the indicator appeared) |
| 3.6 | **Submission > Disable Submissions** is a tab of its own (its default state was not recorded). Tick the option only while the journal must not accept submissions (for example before launch) (`HUMAN`). | Authors see that submissions are closed. | Tab present `VERIFIED-SANDBOX 2026-11-10`; default state and the author view `UNVERIFIED (not observed)` |
| 3.7 | **Submission > Metadata** has options for keywords, subjects, disciplines, supporting agencies, coverage, rights, source, type, competing interests, references, data availability statement and categories. Which ones to ask authors for is an editorial decision (`HUMAN`, `[CLIENT DECISION]`). The default state of each is not recorded here. | n/a | `UNVERIFIED (defaults of each option not recorded)` |

## 4. Review settings, reminders and review forms

Open **Settings > Workflow > Review**.

| Step | Do | Expected visible result | Status |
|---|---|---|---|
| 4.1 | **Setup.** The form shows *Default Review Mode* (three radios), *Restrict File Access*, *One-click Reviewer Access*, *Reviewer Suggestion at Submission*, *Default Response Deadline*, *Default Completion Deadline*, *Minimum Confirmed Reviews Required*, and *Set Reminders for Review*. **Leave every value as shipped until the client fills D1 to D5** (`[CLIENT DECISION]`). | A new journal shows: *Anonymous Reviewer/Anonymous Author* selected, the three checkboxes unticked, deadlines 4 and 4, minimum confirmed reviews 0. | `VERIFIED-SANDBOX 2026-11-10` |
| 4.2 | *Set Reminders for Review* has four selectors (request response before or after due date; review submission before or after due date). **Do not set them** until D4 is decided. | All four read **No reminder set**, so no reminder emails are sent. | `VERIFIED-SANDBOX 2026-11-10` |
| 4.3 | Once D1 to D5 are decided, set them and press **Save**. | **✓ Saved** beside the button. | Save `VERIFIED-SANDBOX 2026-11-10` (saved with no change); the chosen values are `HUMAN` |
| 4.4 | **Reviewer Guidance** has *Review Guidelines*, *Competing Interests* and a link-to-anonymization-guidance option. Paste the approved text (`HUMAN`); do not write it here. | Text editors accept input. | Fields present `VERIFIED-SANDBOX 2026-11-10` |
| 4.5 | **Review Forms.** A new journal has none: the panel shows a **Create Review Form** button and a table (*Title, In Review, Completed, Active*) that reads **No Items**. Create forms only if the client wants them (D16). | The table reads **No Items**. | `VERIFIED-SANDBOX 2026-11-10` |

## 5. Users and roles

Open **Settings > Users & Roles**. Tabs: **Users, Roles, Site Access Options, ORCID** (`VERIFIED-SANDBOX 2026-11-10`).

| Step | Do | Expected visible result | Status |
|---|---|---|---|
| 5.1 | **Roles.** A new journal lists these roles with a permission level: Journal manager, Journal editor, Production editor (Journal Manager level); Section editor, Guest editor (Section Editor); Copyeditor, Designer, Funding coordinator, Indexer, Layout Editor, Marketing and sales coordinator, Proofreader (Assistant); Author, Translator (Author); Reviewer; Reader; Subscription Manager. Each row has a **Settings** link. | The list matches. | `VERIFIED-SANDBOX 2026-11-10` |
| 5.2 | `[CLIENT DECISION]` (D11): who may self-register. A new journal allows self-registration for **Author, Reviewer and Reader** and for no other role (read from the database, `VERIFIED-SANDBOX 2026-11-10`). To change it, open the role's **Settings** and use the option the shipped interface labels "Allow user self-registration" (`UNVERIFIED (I could not open the role dialog with my automation; the label comes from the shipped locale file, not from the screen)`). | n/a | `HUMAN` |
| 5.3 | **Site Access Options** has two options, both unticked on a new journal: *Users must be registered and log in to view the journal site* and *Users must be registered and log in to view open access content*. **Leave both unticked**: an open journal must not require a login to read. A *User Registration* option (visitors can register an account) is also on this tab. | Both boxes unticked. | `VERIFIED-SANDBOX 2026-11-10` |
| 5.4 | Create the first real accounts: the Journal manager and editors, using **real names and role addresses** (`HUMAN`). Give each person their own account. | New users appear under **Users**. | `UNVERIFIED (user creation is part of 4.2, session 2)` |
