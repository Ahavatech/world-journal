# Client checklist: what to test, and what we need from you

For the publisher and editors of World Open Research Journal. The journal is running as a **private test site** at `https://worldopenresearchjournal.com/worj/`. It is closed to search engines and every text on it is a **placeholder** (a banner reads `[PLACEHOLDER: replace with client-approved text]`) or a clearly marked **fake sample** (the sample issue and its three articles). Nothing on it is real, and nothing on it may stay when the journal goes live.

**Never send a password in an email, a chat or a document.** Where a login is needed, the developer will tell you how to give it safely.

How to use this page: do part A and write what you see; part B and C need a short session with the developer; part D is what we need from you before launch. Write the date and your name beside each item you complete.

## A. Look at the site (about 15 minutes, no login needed)

| # | What to do | What to check | Result, date, name |
|---|---|---|---|
| A1 | Open the home page `https://worldopenresearchjournal.com/worj/` | The logo and header are right; the three sample announcements show; the Awards card is there | |
| A2 | Look at the sidebar | "Make a Submission" and the Information links are there | |
| A3 | Click through every About page, the submission guidelines, the contact page and the four awards pages | The structure is what you want; nothing is missing; every page carries a placeholder banner (the text itself is not for review yet) | |
| A4 | Open the sample issue "Vol. 1 No. 1 (2000): Sample Issue (not a real publication)" and its three fake articles | The pages look right; each article's PDF opens | |
| A5 | Open the site on a phone | Everything is readable and the menu works | |
| A6 | Use only the keyboard (Tab and Enter) on one page | You can reach every link and the focus is visible | |
| A7 | Note anything you dislike or want changed | Write it down with the page address | |

## B. Administrator session (with the developer, about an hour)

| # | What to do | Notes | Result, date, name |
|---|---|---|---|
| B1 | Log in at `/worj/login` with the administrator account and **change the initial password** when asked | Keep the new password in a password manager | |
| B2 | Walk through the settings screens in `docs/ADMIN-SETUP-CHECKLIST.md` | Each step says what you should see | |
| B3 | Create a test section and a test user with an address a tester controls | Not real people's addresses | |
| B4 | Check that "Disable Submissions" is set the way you want | It stays on until the date in D8 | |

## C. The editorial workflow (the real test; named testers with their own inboxes)

This follows `docs/QA-SCRIPT.md`, which has every step.

| # | What to do | What to check | Result, date, name |
|---|---|---|---|
| C1 | A tester submits a test article through the submission form, **uploading the test PDF** (see D13) | The upload works; the confirmation email arrives | |
| C2 | An editor assigns a reviewer; the reviewer accepts and sends a review; the editor decides | Each step works for the person doing it | |
| C3 | The editor schedules and publishes the article into an issue | The published article page and its PDF look right | |
| C4 | Read every email that was sent | It arrives, it is **not in spam**, the wording is acceptable. Mail is sent from `editorial@worldopenresearchjournal.com` | |

What the developer still has to confirm: that email reaches inboxes at all, how Hostinger's sending limit behaves, and that the host's firewall does not block any admin action or a large upload. Report anything that fails, with the time it happened.

## D. What we need from you before launch

Nothing here may be invented by the developer. Items marked **blocks launch** cannot be worked around.

### Content and identity

| # | Item | Why | Blocks launch? | Given, date, name |
|---|---|---|---|---|
| D1 | The journal's **ISSN** | Citation tags and indexing need it; the check fails without it | Yes | |
| D2 | The **legal publisher name** and contact | Shown in the Publisher field and policy pages | Yes | |
| D3 | The **editorial team and board** | Real editors with affiliations that can be verified | Yes | |
| D4 | **Policy texts**: peer review, ethics, open access, copyright and licence, archiving, plagiarism, awards if kept | Replace the placeholders | Yes | |
| D5 | The journal's one-sentence **search description**, the three **information texts** (readers, authors, librarians) and the **privacy statement** | Without the description the home page has no meta description | Yes | |
| D6 | The **submission checklist** and **reviewer guidelines**, or confirmation that OJS's default text stays | The default wording is OJS's, not ours | Yes | |
| D7 | **Contact, support and OAI addresses** you control and monitor. The mailbox `editorial@` and the aliases `support@`, `privacy@` and `doi@` exist; confirm who reads each | Readers and the indexing services use them | Yes | |
| D8 | The **date submissions open** | "Disable Submissions" stays on until then | Yes | |

### Decisions

| # | Decision | Notes | Blocks launch? | Answer, date, name |
|---|---|---|---|---|
| D9 | Do article pages need **first and last page numbers**? | An article with no page range currently fails the citation check | Yes | |
| D10 | Which **licence and copyright terms** | One of the Creative Commons 4.0 options or your own terms | Yes | |
| D11 | The journal's **time zone** | The site is set to `Europe/London` for now | Yes | |
| D12 | Import real users, or let people register themselves? | Never import real addresses before email works and every template has been read and approved | Yes | |

### Material and people

| # | Item | Why | Blocks launch? | Given, date, name |
|---|---|---|---|---|
| D13 | The **test PDF** for step C1 (to be supplied by the client; the developer has not been told which file) | A real-looking article file to test upload, review and publishing | Yes | |
| D14 | **Named testers** for part C, each with an inbox they control | The editorial test needs real inboxes | Yes | |
| D15 | A **named reviewer** who reads every enabled email template in full | No promise or timeframe may go out that you have not approved (`docs/QA-SCRIPT.md`) | Yes | |
| D16 | The **support contact** and the date the 14-day support period starts, in writing at launch | | Yes | |
| D17 | The **signed change request** for the awards pages and the Crossref items, if they stay in scope | | Yes | |

### Accounts and operations

| # | Item | Why | Blocks launch? | Given, date, name |
|---|---|---|---|---|
| D18 | **Rights to edit the domain's DNS** at Hostinger (without touching the mailbox's mail records) | Pointing the domain; the Search Console check | Yes | |
| D19 | A **Google account** for Search Console | Verifying the domain and submitting the sitemap on launch day | No (can follow) | |
| D20 | **Who runs the backup, how often, and who keeps the private key.** The developer has produced the first backup and checked that the key opens it. Weekly at the least | The backup only exists when someone runs it | Yes | |
| D21 | Do you want an **offsite copy** of backups (a bucket you own, with versioning on)? | Protects against losing the developer's machine | No (recommended) | |
| D22 | **Hostinger's CDN**: keep it on or turn it off. After a theme change, a purge in the Hostinger panel is needed if it stays on | The CDN may show an older copy of a file for a while | No (decide before launch) | |
| D23 | Whether the **mailbox** stays after its first free year, and its price | The plan page says free for the first year only | No (before the year ends) | |

### Later, no hurry

Crossref membership and DOIs; applications to indexing services (Google Scholar, DOAJ, PKP Index, OpenAlex and others), one decision per service; HSTS raised in stages after launch. See `docs/LAUNCH-BLOCKERS.md`.

## What the developer will not do without you

- Put any real text, name, ISSN, DOI prefix or indexing claim on the site that you have not supplied and approved.
- Open the site to search engines. That is one deliberate step at launch (`docs/DEPLOY-SHARED.md`, "Moving from closed to public"), after every item above marked **blocks launch** is done and the launch checks in `docs/LAUNCH-GATES.md` pass.
