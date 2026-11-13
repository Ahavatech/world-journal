# Client content: what we received, and what we still need

Source: the client's document "World Open Research Journal Details" (version 1, received 2026-11-11). The text is kept as sent in `ojs/client-content/source-v1.txt` (one personal email address replaced by a REDACTED marker). **None of it is approved for publication.** The parts that are usable are in `ojs/client-content/` as HTML (`make lint` checks that every sentence is a passage of the source, so nothing is added or changed) and `scripts/seed-shared.sh` puts them on the closed test site; each page keeps a pending banner naming what is unconfirmed, so the launch check (`scripts/check-placeholders.sh --url`) stays red until a person resolves it. Rule 1 of `CLAUDE.md` still holds: we do not invent an ISSN, a name, an affiliation, a licence or a fee. Where the document is blank or unclear we ask; we do not fill the gap.

Send section 2 and section 3 to the client. Section 1 says what we will do with what is already here.

## 0. Decisions given on 2026-11-13 (recorded in `ojs/client-content/addendum-2026-11-13.txt`)

- **Editorial Team:** Prof. Paul John is **Editor-in-Chief** and Dr. Dan Williams is **Assistant Editor**. The reviewers are listed exactly as the document lists them (name, affiliation, area of interest); the one personal email address in the document is **left out** (no consent to publish it). The document gives no institution or country for the two editors, so none is shown.
- **Phone number:** later. No phone number is published.
- **Awards:** later. The awards pages and the awards card stay off.
- **Everything else that was unclear:** the document is the source of truth. Nothing is added to it except what follows from its own text, listed in the addendum: the **licence** (the document's terms are those of CC BY-NC 4.0, https://creativecommons.org/licenses/by-nc/4.0/) and the **privacy contact line** (`privacy@`). Items the document is silent on stay out: no publisher name, no ISSN (the footer's ISSN line is left out for a launch without one), no support contact other than the journal's own mailboxes.
- **Still open, and the client should be told:** the licence is an inference from the document's terms (change it in one place if the client meant another); the publisher's name is not in the document; the document's Gmail support address is not shown, because every address the site shows or sends from is one of the journal's own.

## 1. What was received, and where each part goes

**Loaded on the test site:** About, Aims and Scope, the privacy statement, the Author Guidelines, the Disclaimer, the Access and APC policy, the Peer Review policy, the Plagiarism and Publication Ethics policy, the Copyright and Licensing terms (licence name and address left as marked blanks), the Research Awards page and the "Call for Reviewers" announcement. **Not loaded** (so nothing is shown that needs consent or is blank): the Editorial Team and reviewers, the contact details, the award recipients, and the archiving policy (not supplied).

| Received | Goes to | Status |
|---|---|---|
| About the Journal (three paragraphs) | the About page (journal description) | usable as is, after the client confirms the claims in 2.9 |
| Aims and Scope (seven subject groups) | the Aims and Scope page | usable; the list is flat in the document, so the grouping below is our reading and the client confirms it (2.10) |
| Privacy Statement (a short version beside the announcement and a longer one under policies) | Settings > Website > Privacy Statement | **two versions: the client picks one** (3.13) |
| Announcement "Call for Reviewers" | the first announcement | **no address to send CVs to**, and signed only "Editor-in-Chief" with no name (2.13) |
| Editorial Team and five "Peer reviewer" entries | the Editorial Team page | **incomplete and needs consent** (2.3, 2.4) |
| Journal Policies 1 to 6 (disclaimer, access and APC, peer review, plagiarism and ethics, privacy, copyright and licence) | policy pages | usable except the **blank licence** and the points in 2.6 to 2.8 |
| Guidelines 1 to 10 (manuscript, submission, APC, review, copyright, ethics, post-publication, refund, awards criteria, contact) | Author Guidelines page | usable after the points in 2.6, 2.7 and 2.11 |
| Research Awards (criteria; the recipients list is a placeholder) | the awards pages | **criteria usable; the recipients text must change until there are recipients** (2.12) |
| Contact: Principal Contact (empty) and Support Contact (a Gmail address) | the Contact page | **incomplete** (2.2) |

## 2. Questions about what was sent (the client must answer; we do not guess)

### Identity and contact

- **2.1** **Licence.** The Copyright and Licensing text reads "adopts the —---) licence" and "visit: —---": the licence name and its web address are blank. The wording (copy and adapt, credit the author, no commercial use without permission) points at a Creative Commons NonCommercial licence, but we will not choose it for the client. Which exact licence, and who holds the copyright (the author or the journal)? This is decision D10 in `docs/CLIENT-CHECKLIST.md`.
- **2.2** **Principal Contact is empty.** Give the contact name, a role address, a postal address and, if wanted, a phone number. **The Support Contact is `worldopenresearchjournal@gmail.com`**, a personal-style Gmail address, while the journal has the mailboxes `editorial@`, `support@`, `privacy@` and `doi@` on its own domain. Should the site show the domain addresses instead? A Gmail address on a journal site is a trust problem for authors and for indexers; this is the client's decision.
- **2.3** **Editorial Team.** Only two names are given, "Prof. Paul John" and "Dr. Dan Williams", with no role, no affiliation, no country and no contact. For each editor we need: full name, title, role (Editor-in-Chief, Editor, Associate Editor and so on), institution, country, and optionally an ORCID and a public email. **Who is the Editor-in-Chief?** The announcement is signed by that role but no name is given. We cannot publish an editor whose affiliation cannot be verified.
- **2.4** **Peer reviewers listed.** Five people are listed (Aramide, Kaushik, Sunkara, Angelova, Goel), with partial affiliations and, for one, a personal Gmail address (which we removed from our copy). We need **each person's written consent to be named publicly**, their correct name, affiliation and country, and confirmation that their email address may be published or should be left out. Should the page be called "Peer reviewers", "Reviewer board" or "Editorial board"? Is the list meant to be public at all? Many journals publish reviewer names once a year instead.
- **2.5** **Dates and numbers on the journal itself:** the **ISSN** (print, online, or both), the **legal publisher name** and address, the year it was founded, the **journal abbreviation** for citations, and the **publication plan** for "published quarterly": which month each issue appears and the date of the first issue.

### Fees and promises

Each of these is a public promise, so the client confirms it.

- **2.6** **Article Processing Charge.** The document says USD 50 to 100 "depending on the applicable publication category". Which categories cost what? How do authors pay (bank details, a payment link, who issues the invoice)? Are there waivers? Also the Refund Policy refers to "the journal's stated refund policy" while being the refund policy itself, and says refunds are never issued for dissatisfaction or delay: the client decides whether that wording is final. **Whether a lawyer reviews fee and refund terms is the client's decision, not ours.**
- **2.7** **Review timeline.** "The initial round of peer review within 5 to 7 days of submission." This is a promise that every automatic email and every editor will have to keep. Confirm it, or give the figure the client can really keep. A named person at the client must read every enabled email template against it (`docs/CLIENT-CHECKLIST.md` D15).
- **2.8** **Plagiarism threshold.** "A similarity index of no more than 15%." Which software does the journal use, who runs the check, and is the figure final?
- **2.9** **Claims in About the Journal:** "international", "peer-reviewed", "published quarterly", "multidisciplinary". We keep them only if the client confirms each is true today. No indexing claim, impact figure or "recognised by" claim appears in the document and none may be added.
- **2.10** **Aims and Scope grouping.** Our reading is seven groups: Artificial Intelligence and Computer Science; Engineering and Physical Sciences; Medical, Health and Biomedical Sciences; Management, Business and Economics; Education and Educational Technology; Law, Governance and Public Policy; Digital Humanities and Emerging Technologies. Confirm, and say whether the trailing "etc." stays.

### Submission and awards

- **2.11** **How authors submit.** The guidelines say "through the journal's designated online submission system **or official editorial email**". The site uses the online system. Are submissions by email accepted too? If yes, which address and who enters them into the system? We recommend the system only. The guidelines also name a **manuscript template** (Times New Roman 12, Word format) and a **cover letter**: please send the template file and, if wanted, a cover-letter template.
- **2.12** **Research Awards.** The page says "The following researchers ... **have been recognized**" above a list with no names. Until a real recipient exists, that sentence is untrue, so we will not publish it. What is the award (a certificate, a prize, money)? Is it decided per volume? Who decides? Do we publish the criteria now and add the recipients page only when there are recipients?
- **2.13** **Call for Reviewers.** Where do applicants send their CVs (which address)? Is there a deadline? Who signs it (a name and title)? Which sections does the list of "subject areas covered" refer to?

## 3. What is missing (please send)

| # | Item | Why we need it |
|---|---|---|
| 3.1 | **The test PDF** the client promised | to test submission, review and publishing (`docs/CLIENT-CHECKLIST.md` C1). It was not in this document |
| 3.2 | The **ISSN** | citation tags, indexing; a hard blocker |
| 3.3 | The **licence name and web address**, and the **copyright holder** | blank in the document |
| 3.4 | A **complete Editorial Team** (3.3 above) and the **Editor-in-Chief's name** | the Editorial Team page and signing announcements |
| 3.5 | **Written consent** from every named reviewer or editor to be listed, and from anyone whose email is shown | their personal data; GDPR-style rules may apply to reviewers in Europe |
| 3.6 | The **Principal Contact** details and the choice between the Gmail and the domain addresses | the Contact page and the sender address of the site's emails |
| 3.7 | The **legal publisher name** and address | the Publisher field |
| 3.8 | The **manuscript template** (Word) and the **copyright and publication agreement** the guidelines promise ("the journal's applicable copyright and publication agreement") | authors will ask for them; the agreement is not in the document |
| 3.9 | **How APC is paid**, the category prices, waivers, and a final refund text | the Author Guidelines and acceptance emails |
| 3.10 | The **reviewer guidelines** (what a reviewer is asked to assess, the form, the timeline) | OJS's default text is not the client's, and the 5 to 7 day promise needs to be written down for reviewers |
| 3.11 | The **section list**: the document names original research articles, review papers, systematic reviews, case studies and "innovative scholarly contributions". Confirm the names, whether each is peer reviewed, and any word limit | these become the sections authors choose from |
| 3.12 | **Policies the document does not cover** (optional, the client decides): archiving and preservation (for example LOCKSS or CLOCKSS), conflict of interest, authorship and ORCID, data availability, use of AI tools by authors, complaints and appeals, retraction and correction (the document only says authors should contact the office) | usual expectations of indexing services; none is added unless the client supplies the wording |
| 3.13 | **One privacy statement**, with who is responsible for the data, how long it is kept, how a person asks for deletion, and the address for it (`privacy@`) | two versions were sent; neither says these things |
| 3.14 | The **date submissions open** | "Disable Submissions" stays on until then |
| 3.15 | The **DOI prefix**, when Crossref membership exists | not needed for launch (`docs/DOI-SETUP.md`) |

Already agreed or supplied earlier, not repeated: the domain, the mailbox, the logo file, the time zone question (`Europe/London` is in place, please confirm), and the named testers and reviewer in `docs/CLIENT-CHECKLIST.md`.
