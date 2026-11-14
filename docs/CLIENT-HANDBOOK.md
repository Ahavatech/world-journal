# World Open Research Journal: handbook for the editorial team

For the publisher, the Editor-in-Chief, the Assistant Editor and anyone who runs the journal day to day. Written in plain language. Screens are described as they appear in OJS 3.5 (the journal software); if a button is named slightly differently on your screen, the position in the menu is the same.

**Status while you read this:** the site `https://worldopenresearchjournal.com/worj/` is **private**: search engines are asked to ignore it. You can use everything below exactly as it will work after launch. Test articles you create now are removed before launch, so do not rely on them.

## 1. The big picture

A manuscript travels through the same stages every time:

1. **An author submits** (title, abstract, the file, contributors).
2. **An editor is assigned** and screens it. The editor can decline it now, or send it to review.
3. **Peer review:** reviewers are invited, accept, read the anonymised file and send a recommendation. The journal uses **double-blind** review: reviewers never see the author, and authors never see the reviewers.
4. **The editor decides:** accept, request revisions, or decline. Revisions go back to the author and, if needed, to the reviewers.
5. **Copyediting, then production:** the accepted article is copyedited, typeset into a PDF (a "galley"), and checked.
6. **Publication:** the article is put into an issue and the issue is published. The journal is published **quarterly**.

Every step sends emails automatically. They leave from **editorial@worldopenresearchjournal.com**. A person's own address, when one is involved, appears only as the *Reply-To*.

## 2. Who can do what (roles)

| Role | Who in your team | Can do | Cannot do |
|---|---|---|---|
| **Site administrator** | one trusted person (the owner) | everything: site settings, hosted journals, all users | nothing is hidden from this role, so keep this login private |
| **Journal manager** | the person who runs the settings | all journal settings, users and roles, emails, statistics, sections | site-level settings |
| **Journal editor (Editor-in-Chief)** | Prof. Paul John | sees every submission, assigns editors, sends to review, records decisions, creates and publishes issues | the journal settings |
| **Section editor (Assistant Editor)** | Dr. Dan Williams | works the submissions assigned to them: review, decisions | sees only what is assigned to them |
| **Copyeditor** | as needed | edits the language of accepted articles | other stages |
| **Layout editor / Designer** | as needed | prepares the final PDF (galley) | other stages |
| **Proofreader** | as needed | checks the final PDF | other stages |
| **Reviewer** | invited experts | reviews the anonymised manuscript | sees nothing else |
| **Author** | anyone who registers | submits and follows their own articles | sees only their own |
| **Reader** | anyone | reads published articles | nothing private |

Give people **the smallest role they need**. A person can hold several roles. Add or change roles in **Settings > Users & Roles > Users** (the pencil icon next to a name). Create an account for a new team member with **Add User**; they receive no email unless you ask OJS to send one, so give them their username and a temporary password in person, and ask them to change it at the first login (profile > Password).

## 3. Logging in, and keeping it safe

- The login page is `https://worldopenresearchjournal.com/worj/login`. Use the **administrator** login only for settings that need it, and a normal editor account for daily work.
- OJS has **no two-factor login**. Protect accounts with a **long, unique password** kept in a password manager, never shared in a message. Do not use the same password anywhere else.
- If someone forgets a password, use **Forgot your password** on the login page: a reset link is emailed to their address. If the email does not arrive within a few minutes, look in the spam folder, then ask the administrator to set a new password for them (open the person under **Settings > Users & Roles > Users** and edit the account).
- **Registering an account sends no email.** This is how the journal is set up now (email validation is off). Someone who registers can log in straight away. If you later switch email validation on, new accounts must click a link in an email first: only do that once you have confirmed your mail reaches inboxes (see section 9).
- Remove or disable accounts of people who leave (Users > the person > *Disable*).

## 4. The daily work, step by step

### 4.1 A new submission arrives

1. The notification email says an editor is needed. Log in and open the **Editor Dashboard** (the dashboard link in the top menu or left sidebar).
2. Open the submission (**View**). The left menu shows the stages: **Submission, Review, Copyediting, Production**, and **Publication** for the article's final details.
3. Under **Participants**, **Assign** an editor (Prof. John or Dr. Williams). The editor is emailed.
4. The editor reads the manuscript. To start review choose **Send for Review**, tick the files reviewers may see, and record the decision. The author is notified.
5. To refuse a manuscript now, choose **Decline Submission** and send the author the decline email (read it first: you can edit the text).

### 4.2 Review

1. In the **Review** stage choose **Add Reviewer**, pick or search for a person, set the due dates, and read the **Review Request** email before sending. It names the journal and the manuscript, and (because review is blind) not the author.
2. The reviewer opens the link in the email, accepts, downloads the anonymised file, writes comments and a recommendation, and submits. You are told at every step.
3. If a reviewer is late, use **Send Reminder**. Reminders and many other emails are sent by a background job that runs **every minute**; if emails are late, mention it to the developer.
4. When enough reviews are in, record the decision: **Accept Submission**, **Request Revisions**, or **Decline Submission**. You choose who is notified (author, reviewers) and can edit the email text each time.

### 4.3 Revisions

The author sees **Revisions requested** on their dashboard, uploads the revised file, and completes the step. You are notified and can accept or ask for more.

### 4.4 Copyediting and production

1. After **Accept Submission** the stage becomes **Copyediting**. Assign a copyeditor, ask for the edit, and let the author check it if you wish.
2. Choose **Send To Production**. Assign a layout editor, who adds a **galley** (the final PDF): in the article's **Publication** tab choose **Galleys > Add galley**, label it *PDF*, and upload the file.
3. Assign a proofreader if you use one.

### 4.5 Publishing

1. Open the article's **Publication** tab and check every field: title, abstract, authors, keywords, the licence (the journal's licence is Creative Commons Attribution-NonCommercial 4.0), pages if you use page numbers, section.
2. **Issues > Create Issue**: volume, number, year (a quarterly journal has four issues a year).
3. In the article choose **Schedule for Publication** and pick the issue.
4. **Issues > Future Issues > Publish Issue.** OJS offers to email every registered user about the new issue: **untick** that box unless you really want it.
5. Open the article and its PDF as a visitor to check them.

## 5. Running the journal (settings)

All in the left menu under **Settings**. Each form has a **Save** button; a green "Saved" confirms it.

| To change | Go to |
|---|---|
| Journal name, summary, About text, contact details | **Settings > Journal** |
| Open or close submissions | **Settings > Workflow > Submission > Disable Submissions** (tick it to close) |
| Sections authors can choose, and their rules | **Settings > Journal > Sections** |
| The submission checklist authors must confirm | **Settings > Workflow > Submission** (the *Author Guidance* tab; the checklist is empty now: add your own items if you want one) |
| Reviewer guidelines | **Settings > Workflow > Review > Reviewer Guidance** |
| The wording of every email | **Settings > Workflow > Emails** (read each template before launch) |
| The licence, indexing description | **Settings > Distribution** |
| Publisher name and ISSN (they appear in the footer once entered) | **Settings > Journal**, group *Publishing Details* |
| Menus, pages, announcements | **Settings > Website > Setup** (Navigation, Announcements, Information, Privacy Statement) |
| Users and roles | **Settings > Users & Roles** |
| Statistics | **Statistics** (left menu) |

### Editing a page

- The text pages (About, Author Guidelines, Privacy, Editorial Team) are edited in the settings above (each has a text editor).
- The other pages (Aims and Scope, Peer Review, Ethics, Access and APC, Copyright and Licensing, Disclaimer) are **custom pages**: **Settings > Website > Setup > Navigation > Navigation Menu Items**, open the item and edit its content.
- To move a page in the menu, use **Navigation > Navigation Menus > Primary Navigation Menu** and drag it.

### Announcements

**Settings > Website > Setup > Announcements**: tick *Enable announcements* if needed, then add announcements in the **Announcements** menu. The menu entry appears when there is at least one.

### Issues and archives

**Issues** lists future and back issues. To fix a published article, use the article's **Publication** tab; to remove an issue, **Back Issues > Delete**.

## 6. Emails: what to expect

- Every message leaves from **editorial@worldopenresearchjournal.com**. People who reply to an email an editor sent reach that editor (their address is the *Reply-To*).
- The contact page shows **editorial@** (general) and **support@** (technical). **privacy@** is the contact for privacy requests and appears on the privacy page. **doi@** will be used for DOI registration when that is set up. **admin@** is the site administrator's mailbox.
- Mail from a brand-new domain sometimes lands in **spam**, especially at first. Ask authors and reviewers to look there and mark the first messages "not spam".
- Read **every** email template once, in **Settings > Workflow > Emails**, and check no promise in it (for example a review deadline) is one you cannot keep. The review policy says the first round aims at 5 to 7 days.

## 7. What the journal states, and where it came from

Everything on the public pages is your own text from the document you supplied (the policies, guidelines, About and Aims and Scope), with these decisions recorded: Prof. Paul John is Editor-in-Chief and Dr. Dan Williams Assistant Editor; reviewers are listed as in your document (one reviewer's personal email address was left out); the **licence is CC BY-NC 4.0**, which is what the terms in your document describe; the **privacy contact is privacy@**. If any of this is not what you want, change it in the page or setting (section 5) or tell the developer.

**Not on the site yet, and left out rather than invented:** the publisher name, the ISSN, a phone number, the Research Awards pages, and any support address other than the journal's own mailboxes. Add each when you have it (publisher name and ISSN in Settings > Journal, Publishing Details: the footer then shows them).

**Fees:** the Article Processing Charge (USD 50 to 100 after acceptance) is stated on the site, but **the website does not take payments**: you arrange payment with authors yourselves.

## 8. Backups and safety

- Hostinger keeps its own daily backups for seven days. The developer also makes an **encrypted backup** of the database and files with `pull-backup.sh`, encrypted to a key only you hold. **Decide who runs it and how often** (weekly at the least) and where the private key is kept: a backup you cannot decrypt is worthless.
- Keep one offline copy of the key and the administrator password.
- Never paste a password or the backup key into an email or chat.

## 9. If something goes wrong

| Problem | What to do |
|---|---|
| An author says they received no email | Ask them to check spam; check their address in Users; resend from the submission page; tell the developer the time it was sent |
| Nobody can log in | Use *Forgot your password*; if that fails, the developer can reset the administrator password from the server |
| A page shows old text after you changed it | Add `?x=1` to the web address to bypass the cache, or wait up to an hour |
| The site shows an error page | Take a screenshot with the address bar and send it to the developer |
| You deleted something by mistake | Do not edit more; tell the developer: the host and the developer both hold backups |

**Contact for technical help:** the developer's support period and contact are confirmed in writing at launch (14 days from the date you both agree).

## 10. Before launch, your checklist

1. Read the pages as a visitor (`docs/CLIENT-CHECKLIST.md`, part A).
2. Do the editorial run with test accounts (`docs/TEST-FLOW-ROLES.md`) and read every email.
3. Decide who runs the weekly backup and who holds the key.
4. Decide the **date submissions open** (Settings > Workflow > Submission > Disable Submissions stays ticked until then).
5. Give the developer: the publisher name, the ISSN (or "launch without it"), and any change you want to the pages.
6. When you are satisfied, tell the developer to **open the site to search engines**. That is one deliberate step.

## 11. Words you will meet

- **Galley:** the final PDF (or HTML) of an article.
- **Section:** a category of article authors choose, for example *Original Research*.
- **Stage:** Submission, Review, Copyediting or Production.
- **Participant:** a person assigned to a submission.
- **Double-blind:** neither authors nor reviewers know each other's identity.
- **Publication tab:** the screen where an article's final details, galleys and issue are set.
- **Reply-To:** the address a reply goes to, different from the address a message is sent from.
