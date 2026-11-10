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
