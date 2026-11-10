# QA script: the editorial run, end to end (manual)

**This is a manual script for a person. Every step below reads NOT RUN, because no person has run it.** Nothing here is a test result. The "Seen in sandbox dry run" column records what the developer saw on screen in a throwaway sandbox journal on 2026-11-10 (`VERIFIED-SANDBOX 2026-11-10`, journal and test users deleted afterwards); it helps a tester recognise the screens and says nothing about the real server.

## Rules for the tester

- Run it on **staging or a throwaway journal, never with real users or real authors' work on the live site.**
- **Tester inbox addresses must be ones the tester controls.** Real addresses are only for people who agreed to receive the test emails.
- **Do not import real users** until SMTP and the email templates have been reviewed: a users import emails every new person (`docs/ADMIN-SETUP-CHECKLIST.md` row 5.4, decision D22).
- **Never enter a DOI prefix, a Crossref credential or deposit anything** during this script (`docs/DOI-SETUP.md`). Sample articles are never deposited.
- Record for every step what was seen (a screenshot, the email, the URL). A step is ticked only by the person who ran it, in the Status column, with the date and their name.
- The expected results come from the OJS 3.5 behaviour seen in the sandbox and from the checklist; where neither shows a screen, the step says `UNVERIFIED`.

## Read this first: what the developer dry run found

| # | Finding | What to do |
|---|---|---|
| QF1 | In the **Publish Issue** dialog the box "Send an email about this to all registered users" is **ticked by default**. | Untick it unless the client wants every registered user emailed. On a live site that is real mail to everyone. |
| QF2 | An article whose **Pages** field is empty fails `scripts/check-citation-meta.sh` (no `citation_firstpage` or `citation_lastpage`). | Fill Pages for each article (step G3), or the client decides whether an online-only journal needs those tags (an open decision, not made here). |
| QF3 | The "Review accepted" notice went to the **journal contact email**. With **no editor enrolled**, the "needs an editor" notice went to the site administrator. | The contact address must be a monitored role address (decision D23); enrol an editor (step A4). |
| QF4 | When submissions are disabled, authors read a message that tells them to "Visit the workflow settings", which authors normally cannot open. | The client decides whether that shipped wording stays (default-wording gate in `docs/LAUNCH-GATES.md`). |
| QF5 | The reviewer guidelines screen reads "This publisher has not set any reviewer guidelines." | The client supplies the guidelines or accepts that wording. |
| QF6 | The shipped **Review Request** template uses dates the editor enters; the shipped *Sent to Review* help text suggests telling authors how long review might take. | Do not add timeframes or policy claims unless the client approves them. |
| QF7 | Starting **Add Reviewer** from the workflow's Review tab gave "Invalid review round", and the reviewers table showed empty after a reviewer was assigned. It worked from the dashboard row's **Assign Reviewers**. | `UNVERIFIED` whether a person in an ordinary browser sees this or it was an effect of the automation. Note which route you used. |
| QF8 | The **Create Issue** dialog refuses to save with "Title is required for the issue" unless at least one identification part is filled and shown. | Fill Volume, Number, Year and tick their "show" boxes, or give a title. |

## A. Set-up

| ID | Role | Action | Expected result | Seen in sandbox dry run | Status |
|---|---|---|---|---|---|
| A1 | Tester | Use staging or create a throwaway journal. Note its URL. | A journal home page loads with its name. | Journal created through the site administrator's API. | NOT RUN |
| A2 | Author | Open `/JOURNAL/user/register`, fill the form with a tester-controlled address, tick the privacy consent, register. | "Registration complete"; the author is logged in. | Form: *Given Name*, *Family Name*, *Affiliation*, *Country*, *Email address*, *Username*, *Password*, *Repeat password*, a privacy consent tickbox, a notifications tickbox, a "contacted with requests to review" tickbox, *Reviewing interests*. Result: "Registration complete" with *Make a New Submission*. | NOT RUN |
| A3 | Reviewer | Register a second account, this time ticking the reviewer-contact box. | "Registration complete"; the account is a reviewer candidate. | Same form; the reviewer box is the only role tickbox. | NOT RUN |
| A4 | Administrator | Enrol an editor: Settings > Users & Roles > Users. Confirm who receives the "needs an editor" notice before and after. | The new submission notice goes to the editor, not only the site administrator (QF3). | Not walked: the site administrator acted as editor. `UNVERIFIED`. | NOT RUN |
| A5 | Administrator | Settings > Users & Roles > Roles. Open the **Edit** action on the Author row. Read *Role Options*. Cancel. | An option labelled "Allow user self-registration" exists; **its state for Author, Reviewer and Reader matches decision D11**. Nobody else is self-registrable. | Dialog "Edit" with *Role details*, *Stage Assignment* and *Role Options*; the label is exactly "Allow user self-registration", ticked for Author. Reviewer and Reader not opened (`UNVERIFIED` on screen; the checklist read them from the database). | NOT RUN |

## B. Submission settings as the author sees them

| ID | Role | Action | Expected result | Seen in sandbox dry run | Status |
|---|---|---|---|---|---|
| B1 | Author | Open `/JOURNAL/submission` while submissions are **enabled**. | The first wizard page shows a title field, **the submission checklist with one confirmation tickbox**, privacy consent, and *Begin Submission*. **The checklist text is the client-approved text** (decision D10), not OJS's shipped list; the reader notes any shipped wording still present. | *Make a Submission / Before you begin*; *Title*, *Submission Checklist* (five shipped items and one confirmation tickbox, the shipped wording is deliberately not copied here), *Privacy Consent*, *Begin Submission*. | NOT RUN |
| B2 | Administrator | Settings > Workflow > **Disable Submissions**. Tick the option and save. | The setting saves. | Tab list: *Submission, Review, Publisher Library, Emails, Disable Submissions, Author Guidance, Metadata, Components, Setup, Reviewer Guidance, Review Forms*. The option is off by default. | NOT RUN |
| B3 | Author | Open `/JOURNAL/submission` while disabled. | The author sees that the journal is not accepting submissions, and **no** *Begin Submission* button. Read the wording as the client would (QF4). | "This journal is not accepting submissions at this time. Visit the workflow settings to allow submissions." No *Begin Submission* button. | NOT RUN |
| B4 | Administrator | Untick the option and save. | The author can begin a submission again (B1). | Restored in the dry run. | NOT RUN |

## C. Author submits

| ID | Role | Action | Expected result | Seen in sandbox dry run | Status |
|---|---|---|---|---|---|
| C1 | Author | Fill the title, tick the checklist confirmation and the privacy consent, press *Begin Submission*. | Step "1 Details" opens. | Five steps: *Details, Upload Files, Contributors, For the Editors, Review*. | NOT RUN |
| C2 | Author | Details: enter an abstract (required); keywords and references optional. *Continue*. | Step 2 opens. | Fields: *Title*, *Keywords*, *Abstract*, *References*. Title and abstract are rich-text fields. | NOT RUN |
| C3 | Author | Upload Files: add a file and choose its component. *Continue*. | The file is listed with its component. | *Add File / Upload File*, then component buttons such as *Article Text*. | NOT RUN |
| C4 | Author | Contributors: check the author is listed. *Continue*. | The author appears as *Author* and *Primary Contact*. | Listed from the profile, with *Edit* and *Delete*. | NOT RUN |
| C5 | Author | For the Editors: optional comment. *Continue*. | Review page opens. | *Comments for the Editor*. | NOT RUN |
| C6 | Author | Review page: check it shows no error, then *Submit* and confirm. | A confirmation says the journal has been notified and a confirmation email was sent. | A missing abstract showed "There are one or more problems that need to be fixed" and "This field is required". Dialog: "...will be submitted to JOURNAL for editorial review. Are you sure...?" with *Submit* and *Cancel*; then "The journal has been notified of your submission...". | NOT RUN |
| C7 | Tester | Read the emails. | The author gets a submission confirmation; the editor (or administrator, QF3) gets a notice that an editor must be assigned. | Subjects seen: "Thank you for your submission to JOURNAL" and "A new submission needs an editor to be assigned: ...". | NOT RUN |

## D. Editor sends it to review and invites a reviewer

| ID | Role | Action | Expected result | Seen in sandbox dry run | Status |
|---|---|---|---|---|---|
| D1 | Editor | Editor Dashboard: open the submission (*View*). | The workflow opens. | Left menu: *Submission, Review, Copyediting, Production*, and *Publication* with *Title & Abstract, Contributors, Metadata, References, JATS XML, Galleys, Permissions & Disclosure, Issue*. Actions: *Send for Review*, *Accept and Skip Review*, *Decline Submission*, *Assign*. | NOT RUN |
| D2 | Editor | *Send for Review*: Notify Authors (template *Sent to Review*), Select Files, *Record Decision*. | The stage becomes Review. Read the email text as the client would (QF6). | Two steps, *Notify Authors* and *Select Files*; *Skip this email* is offered. Status: "The submission is currently in the Review stage." | NOT RUN |
| D3 | Author | Read the email. | "Your submission has been sent for review". | Subject seen as quoted. | NOT RUN |
| D4 | Editor | Assign a reviewer from the dashboard row (*Needs reviews* view, **Assign Reviewers**). Pick the reviewer. Read the **Review Request** template in full, set the due dates, choose the review type, *Add Reviewer*. | The reviewer is added. **A client reviewer reads the whole invitation (checklist 6.7): no timeframe, deadline or policy claim that the client has not approved.** | Dialog *Add Reviewer*: *Submission Author List*, *Locate a Reviewer* (search, filters), *Select Reviewer*, *Create New Reviewer* / *Enroll Existing User*. Then template *Review Request*, *Response Due Date*, *Review Due Date*, *Files To Be Reviewed*, review type (three options), *Do not send email to Reviewer*. Route from the workflow Review tab failed (QF7). | NOT RUN |
| D5 | Reviewer | Read the invitation email. | Subject "Invitation to review"; the text names the journal and the submission; the due dates are the ones entered; it links to the reviewer page. | The rendered email carried the entered dates and a link to the reviewer page. | NOT RUN |

## E. Reviewer reviews

| ID | Role | Action | Expected result | Seen in sandbox dry run | Status |
|---|---|---|---|---|---|
| E1 | Reviewer | Open the link. Tick the privacy consent. *Accept Review, Continue to Step #2*. | Step 2 opens. | Four steps: *Request, Guidelines, Download & Review, Completion*. Also *Decline Review Request*. | NOT RUN |
| E2 | Reviewer | Guidelines: read, *Continue to Step #3*. | Guidelines shown (QF5). | "This publisher has not set any reviewer guidelines." | NOT RUN |
| E3 | Reviewer | Enter comments, choose a recommendation, *Submit Review*, confirm. | "Review Submitted"; thanks shown. | Comment boxes *For author and editor* and *For editor*; recommendation list *Accept Submission, Revisions Required, Resubmit for Review, Resubmit Elsewhere, Decline Submission, See Comments*; confirm "Are you sure you want to submit this review?" with *OK* and *Cancel*. | NOT RUN |
| E4 | Tester | Read the emails. | The editor side is told the review was accepted; the reviewer is thanked. | Subjects seen: "Review accepted: ... accepted review assignment for #N" (sent to the journal contact address, QF3) and "Thank you for your review". | NOT RUN |

## F. Decision, revisions, acceptance

| ID | Role | Action | Expected result | Seen in sandbox dry run | Status |
|---|---|---|---|---|---|
| F1 | Editor | Record **Request Revisions**: Notify Authors (*Revisions Requested*), Notify Reviewers (*Notify Reviewers of Decision*), *Record Decision*. | Author is told revisions are needed; reviewer is thanked. | Two steps; *Previous*, *Record Decision*. | NOT RUN |
| F2 | Author | Dashboard > *Revisions requested*: **Submit revisions**. Choose the component first, upload, name the file, *Complete*. | The submission moves to *Revisions submitted*. | Dialog steps *Upload File, Review Details, Confirm*; the component must be chosen before uploading; *Complete*. | NOT RUN |
| F3 | Editor | Record **Accept Submission**: Notify Authors (*Submission Accepted*), Notify Reviewers, Select Files. | The stage becomes Copyediting. | Three steps. Round status "Submission accepted." | NOT RUN |
| F4 | Editor / Copyeditor | Copyediting: assign a copyeditor, run copyediting, upload copyedited files. | Copyedited files exist. | **Not walked** (no copyeditor enrolled); `UNVERIFIED`. | NOT RUN |
| F5 | Editor | Record **Send To Production**: Notify Authors (*Sent to Production*), Select Files. | The stage becomes Production. | Two steps; the "Copyedited" list was empty because F4 was skipped. | NOT RUN |
| F6 | Tester | Read the emails. | The author gets acceptance and "next steps" emails. | Subjects seen: "Your submission has been accepted to JOURNAL" and "Next steps for publishing your submission". | NOT RUN |

## G. Production and publication

| ID | Role | Action | Expected result | Seen in sandbox dry run | Status |
|---|---|---|---|---|---|
| G1 | Editor | **Issues > Create Issue**: fill Volume, Number, Year, tick their show boxes, *Save* (QF8). | The issue appears under *Future Issues* with *Edit*, *Preview*, *Publish Issue*, *Delete*. | Dialog fields *Date Published, Volume, Number, Year, Title, Description, Cover image, URL Path*. | NOT RUN |
| G2 | Editor | Publication > **Galleys** > *Add galley*: label (for example PDF), save, upload the **real** PDF file. | A galley with its file exists. | Dialog *Create New Galley* (*Galley Label*, *Language*, a remote-site tickbox, *URL Path*), then *Upload a File Ready for Publication* (three steps). Row menu: *Edit, Change File, Delete*. | NOT RUN |
| G3 | Editor | Publication > **Issue**: assign the issue, section, and **fill Pages** (QF2). *Schedule For Publication*, confirm. | The article is scheduled for the issue. | Dialog "Select an issue to schedule for publication"; confirm text "All publication requirements have been met. This will be published when ISSUE is published". Fields *Section, Cover Image, Pages, URL Path, Date Published*. | NOT RUN |
| G4 | Editor | Issues > Future Issues > **Publish Issue**. **Untick** "Send an email about this to all registered users" unless intended (QF1). *OK*. | The issue is published; the article page loads. | Box was ticked by default; the "Just published" email was generated. | NOT RUN |
| G5 | Tester | Open the article and the PDF. Run `scripts/check-citation-meta.sh --placeholder-issn URL` and `scripts/check-pdf.sh URL`. | Both pass **with a real article and real PDF** (title and authors on page 1). | With a sample fixture PDF and empty Pages, both FAILED (QF2; title not on page 1). They passed on the three seeded samples. | NOT RUN |
| G6 | Tester | Run `scripts/check-discovery.sh --robots-mode production URL`. | The new article is in the sitemap and in OAI. | Not run on the dry-run article. | NOT RUN |

## H. Information texts and clean-up

| ID | Role | Action | Expected result | Seen in sandbox dry run | Status |
|---|---|---|---|---|---|
| H1 | Administrator | Settings > Website > Setup > **Information**: read *For Readers*, *For Authors*, *For Librarians*. | Each holds **client-approved** text, not OJS's default wording (decisions D14, row 8.12 of the checklist). | The three public pages `/information/readers`, `/authors` and `/librarians` answered 200. Their default wording was not re-read here. | NOT RUN |
| H2 | Tester | Run `scripts/check-placeholders.sh --url URL`. | No placeholder marker and no unconfirmed shipped default wording. | Not applicable to the throwaway journal. | NOT RUN |
| H3 | Tester | Remove the test content. Confirm no test article, issue or test user remains. | The sitemap and OAI list no test record; no test user can log in. | The journal was deleted through the API. **There is no supported user-deletion route in the API**: the two test users were removed by a direct database edit in the sandbox only. How to fully remove a user in the staging UI is `UNVERIFIED`. | NOT RUN |
