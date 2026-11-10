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

| # | Setting | Where | OJS default (fresh journal) | Chosen value |
|---|---|---|---|---|
| D1 | Review model (anonymous, double-anonymous or open) | Workflow > Review > Default review mode | double-anonymous (`defaultReviewMode = 2`) | |
| D2 | Time for a reviewer to respond to a request | Workflow > Review > Review response time | 4 weeks (`numWeeksPerResponse`) | |
| D3 | Time for a reviewer to complete a review | Workflow > Review > Review completion time | 4 weeks (`numWeeksPerReview`) | |
| D4 | Reviewer reminders on or off, and when (before and after the due date, for the response and for the review) | Workflow > Review > Reminders | off: the four reminder day-settings are unset | |
| D5 | One-click reviewer access (link in the email logs the reviewer in) | Workflow > Review > Reviewer access | off (`reviewerAccessKeysEnabled` unset) | |
| D6 | Licence (Creative Commons or other) | Distribution > Permissions > License URL | none set | |
| D7 | Copyright holder (author, journal, or other) | Distribution > Permissions > Copyright holder | none set | |
| D8 | Copyright year basis | Distribution > Permissions | issue publication year (`copyrightYearBasis = issue`) | |
| D9 | Copyright notice text shown to authors at submission | Distribution > Permissions > Copyright notice | empty | |
| D10 | Submission checklist item text | Workflow > Submission > Submission Preparation Checklist | **OJS ships a default list of items** (kept as shipped until the client rewrites it). The text is policy-adjacent, so it is not authored here | |
| D11 | Who may self-register as author, reviewer or reader | Users & Roles > Roles > edit role > "Allow registration" | Author **yes**, Reviewer **yes**, Reader **yes**; every other role no | |
| D12 | Article processing charge (APC) statement | There is no APC field. Payments are off (`paymentsEnabled` unset). Wording, if any, belongs on a policy page | no statement, payments off | |
| D13 | Open access policy text | Settings > Distribution > ... and Journal > Setup | **OJS ships a default text** claiming "immediate open access" (`openAccessPolicy`) | |
| D14 | Other default texts that make claims: author guidelines, reader information, librarian information, privacy statement, LOCKSS and CLOCKSS licence texts, submission help texts | Settings > Journal and Workflow | **OJS ships default wording for each**; the sandbox journal's copies were emptied and replaced by placeholder pages in Phase 3 | |
| D15 | Show real masthead users (on) or the written editorial team text (off) | Settings > Journal > Masthead (`enableEnrollmentMasthead`) | on | |
| D16 | Review forms (questions reviewers answer) | Workflow > Review > Review Forms | none exist | |
| D17 | Editorial statistics emails to editors | Workflow > Emails and notifications (path to be confirmed) | on (`editorialStatsEmail`) | |
| D18 | Which authors receive submission acknowledgement and decision emails | Workflow > Submission | all authors (`submissionAcknowledgement = allAuthors`, `notifyAllAuthors = true`) | |

**Email template rule:** the email templates stay exactly as OJS ships them, or are shortened to contain **no timeframes and no policy claims**. The checklist never asks anyone to type a deadline into a template. The template review is its own section below (pending).

**The OJS-default column was read from the settings store and database (`VERIFIED-SANDBOX 2026-11-10`). The "Where" column menu paths are not yet confirmed on screen**; each section below confirms the paths it uses and corrects this table if one differs. Until a path is confirmed here, treat it as `UNVERIFIED (not yet seen in the sandbox UI)`.

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
