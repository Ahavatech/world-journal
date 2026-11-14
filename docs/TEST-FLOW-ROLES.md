# Test flow by user group (run on the closed site before launch)

For the person testing the journal. It walks every user group through what that group must be able to do, and what it must **not** be able to do. It follows the journal's own settings (double-blind review, quarterly issues). The step-by-step editorial run with the expected texts is `docs/QA-SCRIPT.md`; this page is the checklist by **role**, so every group is covered. **Nothing here has been run on the host yet: every row starts as NOT RUN.** Write the date, your name and what you saw in the last column.

## 0. Before you start

**Test accounts.** Use one inbox you control with Gmail "plus" addresses, so each account has its own address (`you+author@gmail.com`, `you+reviewer@gmail.com`, and so on). Each must be a different address (OJS requires it). Write the username and the password of every test account in your password manager, never in a message.

| Account | Role to give it (Settings > Users & Roles > Users > Add User) | Stands for |
|---|---|---|
| `test-author` | Author | an author |
| `test-author2` | Author | a second author (to check one author cannot see another's work) |
| `test-reviewer` | Reviewer | a peer reviewer |
| `test-reviewer2` | Reviewer | a second reviewer (to check the review is blind) |
| `test-editor` | Journal editor | Prof. Paul John, Editor-in-Chief |
| `test-section` | Section editor | Dr. Dan Williams, Assistant Editor (the nearest OJS role; the client chooses the final one) |
| `test-copyeditor` | Copyeditor | copyediting |
| `test-layout` | Layout Editor (or Designer) | typesetting and galleys |
| `test-proof` | Proofreader | proofreading |
| `test-manager` | Journal manager | running the journal's settings |

The real **administrator** account (the site administrator) is the tenth. Roles the journal does not use (Subscription Manager, Funding coordinator, Marketing and sales, Indexer, Translator, Guest editor) are checked once in part 11.

**Settings to check first (administrator):** Settings > Workflow > Submission > **Disable Submissions** is **off** for the test (switch it back to the client's decision afterwards). Settings > Journal > Sections has at least one section authors can choose (a section is needed before anyone can submit). Email: every message below must arrive from `editorial@worldopenresearchjournal.com` (From and Return-Path), with the person's own address, if any, in Reply-To.

**You need:** one test PDF (the one the client promised, or any small PDF), one test Word file, a second small PDF for a revision.

## 1. Visitor and reader (no login)

| # | Do | Expected | Result |
|---|---|---|---|
| 1.1 | Open the home page, then About, Aims and Scope, Editorial Team, Author Guidelines, the policy pages, Privacy, Contact. | Every page loads, has the client's text, no placeholder marker. | |
| 1.2 | Open the page on a phone. Use only the Tab key on one page. | Readable; every link reachable; focus visible. | |
| 1.3 | Switch JavaScript off (browser setting) and open the home page and one article. | Pages still work. | |
| 1.4 | Search for a word from a published article. | The article is found. | |
| 1.5 | Open `/worj/issue/archive` and a published issue. | The issue and its articles are listed; the PDF opens. | |
| 1.6 | Open a page that does not exist. | The site's "Page not found" page (a denied path shows the accessible static page; an unknown route shows OJS's own plain 404). | |
| 1.7 | Try `/worj/management/settings/website` without logging in. | A login page, not the settings. | |
| 1.8 | Open the privacy contact and the contact page. | `privacy@` and `editorial@` / `support@` are shown; no Gmail address. | |

## 2. Author

| # | Do | Expected | Result |
|---|---|---|---|
| 2.1 | Register `test-author` at `/worj/user/register` (tick the privacy consent, the Author role). The page says the confirmation email may land in spam. | Registration completes with a message to check your email and spam folder; the "Validate Your Account" email arrives from `editorial@`; the account can log in only after the link is clicked. | |
| 2.2 | Log in, go to **New Submission**. Choose the section, tick the checklist or confirmation boxes shown, *Begin*. | The five steps open: Details, Upload Files, Contributors, For the Editors, Review. | |
| 2.3 | Details: title, abstract (required), keywords. Upload: add the PDF as *Article Text*. Contributors: check the author, add a co-author. | Each step saves and continues. | |
| 2.4 | Review page, then **Submit**. | A confirmation; the author's confirmation email arrives. The editor side gets a "needs an editor" notice. | |
| 2.5 | In the author dashboard open the submission. | Status "Submission"; the author sees the files and the discussion tab, and **no** other author's submission. | |
| 2.6 | Log in as `test-author2` and look for the first author's submission. | It is not visible (an author sees only their own). | |
| 2.7 | Look for a **Withdraw** action on the first submission (as the author). | If OJS offers it at this stage, it works with a clear message and an editor can reactivate the submission. If it is not offered, write that down. | |
| 2.8 | Edit the profile (name, affiliation, password change). | Saves; the password change works. | |
| 2.9 | Forgot password: use `/worj/login/lostPassword` for `test-author`. | The reset email arrives from `editorial@`; the link works and points to `https://worldopenresearchjournal.com`. | |

## 3. Editor-in-Chief (Journal editor) and Assistant (Section editor)

| # | Do | Expected | Result |
|---|---|---|---|
| 3.1 | Log in as `test-editor`. The dashboard shows the new submission. | Visible under *Submissions*; the editor receives the notice. | |
| 3.2 | Open it. **Assign** `test-section` as the section editor (Participants > Assign). | The assistant appears as a participant and receives an email. | |
| 3.3 | Log in as `test-section`. | Sees **only** the submissions assigned to them; cannot open the journal's settings. | |
| 3.4 | As the editor, **Send for Review** (External Review): notify the author (read the email text), select files, record. | The stage becomes Review; the author receives the email. | |
| 3.5 | Assign `test-reviewer` and `test-reviewer2`. Read the **Review Request** email in full, check the due dates. | The invitations arrive; the text names the journal and the submission and does **not** show the author's name (double-blind). | |
| 3.6 | Read both reviews when they come in (part 4). | Reviewer names are visible to the editor, never to the author. | |
| 3.7 | Record **Request Revisions** (notify the author and the reviewers). | The author gets the "revisions requested" email; the reviewers get their notice. | |
| 3.8 | After the author's revision (part 2.10 below), record **Accept Submission**. | The stage becomes Copyediting; the author gets the acceptance email. | |
| 3.9 | Open a second submission and record **Decline**. | The author gets the decline email; the submission is archived. | |
| 3.10 | Use the discussion tab: start a discussion with the author. | The author is emailed and can reply. | |
| 3.11 | Issues > **Create Issue** (volume, number, year) | The issue appears under *Future Issues*. | |

**2.10 (author side of revisions):** log in as `test-author`, open *Revisions requested*, upload the second PDF as the revision, complete. The editor is notified.

## 4. Peer reviewer

| # | Do | Expected | Result |
|---|---|---|---|
| 4.1 | Open the invitation email as `test-reviewer`, follow the link. | The review page opens (login if asked). | |
| 4.2 | Accept the review, read the guidelines, download the anonymised file. | The file has no author name in its details; the reviewer cannot see the author. | |
| 4.3 | Enter comments for the author and for the editor, choose a recommendation, **Submit Review**. | "Review submitted"; the thank-you email arrives. | |
| 4.4 | As `test-reviewer2`, **decline** the request. | The editor is told; the reviewer gets a confirmation. | |
| 4.5 | As the reviewer, look for other submissions or the journal settings. | Not visible. | |
| 4.6 | Let a due date pass on a second request (or ask the editor to send a reminder). | The reminder arrives. The reminder needs the scheduled-task job, which runs every minute on the host. | |

## 5. Copyeditor

| # | Do | Expected | Result |
|---|---|---|---|
| 5.1 | As the editor, assign `test-copyeditor` in the Copyediting stage and request copyediting. | The copyeditor is emailed. | |
| 5.2 | As `test-copyeditor`, open it, upload a copyedited file. | The file is attached; the editor is notified. | |
| 5.3 | The author reviews the copyedited file and responds (author side). | The editor sees the response. | |
| 5.4 | Check the copyeditor cannot open settings or other stages they are not assigned to. | Not possible. | |

## 6. Layout editor / Designer, proofreader, production

| # | Do | Expected | Result |
|---|---|---|---|
| 6.1 | The editor records **Send To Production**. | The stage becomes Production; the author gets the "sent to production" email. | |
| 6.2 | Assign `test-layout`. As that user, **Add galley** (label *PDF*) and upload the final PDF. | The galley exists with its file. | |
| 6.3 | Assign `test-proof`. As that user, review the galley and report any correction. | The editor is notified. | |
| 6.4 | Check these users see only what they are assigned to. | Confirmed. | |

## 7. Editor publishes

| # | Do | Expected | Result |
|---|---|---|---|
| 7.1 | Open the article's **Publication** tab: check title, abstract, authors, **Pages** (fill them if the journal uses page numbers), the **licence** (it should follow the journal's CC BY-NC 4.0), the issue and section. | Everything is filled; no field says placeholder. | |
| 7.2 | **Schedule for publication** in the issue created in 3.11. | The article is scheduled. | |
| 7.3 | Issues > Future Issues > **Publish Issue**. **Untick** "send an email about this to all registered users" unless you want that email. | The issue is published. | |
| 7.4 | Open the article and its PDF as a visitor. | Both load; the abstract page shows the title, authors and the licence link. | |
| 7.5 | Run `scripts/check-pdf.sh https://worldopenresearchjournal.com/worj/article/view/N` and `scripts/check-citation-meta.sh https://worldopenresearchjournal.com/worj/article/view/N` (use the real article number; the citation check needs an ISSN to pass without `--placeholder-issn`). | The PDF check passes; the citation check reports what is missing (the ISSN, pages). | |
| 7.6 | Run `scripts/check-discovery.sh --robots-mode staging https://worldopenresearchjournal.com` (the site is still closed). | The new article is in the sitemap and in OAI. | |

## 8. Journal manager

| # | Do | Expected | Result |
|---|---|---|---|
| 8.1 | Log in as `test-manager`. Open Settings > Journal, Website, Workflow, Distribution, Users & Roles. | All are open; changes save with "Saved". | |
| 8.2 | Add a user and give them a role; disable one test user. | Works; the disabled user cannot log in. | |
| 8.3 | Open Statistics. | The page opens (it may be empty on a new journal). | |
| 8.4 | Try Administration (site settings, other journals). | Not available (only the site administrator has it). | |

## 9. Site administrator

| # | Do | Expected | Result |
|---|---|---|---|
| 9.1 | Log in as the administrator (first login forces a password change after `--finish`). | Works. | |
| 9.2 | Administration > Site settings: contact email is `admin@`, the site title is right. | As stated. | |
| 9.3 | Administration > Hosted Journals: the journal is listed and enabled. | As stated. | |
| 9.4 | Administration > System Information. | PHP 8.3 is shown; note anything flagged in red. | |
| 9.5 | Check the email settings with `scripts/emails-shared.sh` (it must end `RESULT: PASS`). | Pass. | |

## 10. Cross-checks (every role)

| # | Do | Expected | Result |
|---|---|---|---|
| 10.1 | Open every email you received during the test. | From `editorial@worldopenresearchjournal.com`; Reply-To only where a person wrote it; no placeholder text; links start with `https://worldopenresearchjournal.com`. | |
| 10.2 | Note which emails went to spam, and the time each took to arrive. | Written down (the first mails from a new domain often go to spam: tell the client). | |
| 10.3 | Log in once with a wrong password as a test user. | A clear error message, and the right password still works afterwards. Never test this on the administrator account. | |
| 10.4 | Log out, then press the browser's back button. | No private page is shown. | |

## 11. Roles the journal does not use

Log in as a user with **Subscription Manager**, **Reader**, **Funding coordinator**, **Indexer** and **Guest editor** only if the client wants them. Check that nothing unexpected appears: the journal has no subscriptions and no fees paid on the site (the APC is handled outside the site), so no payment or subscription page may be visible to readers or authors.

## 12. Clean-up before launch (the site must hold no test data)

Do this **after** the tests and before the production deploy.

1. Delete the test submissions. Find their numbers in the editorial dashboard (the number in the address bar), then on the host:

   ```bash
   ssh -i ~/.ssh/key -p 65002 u896415912@145.14.152.95 'cd ~/domains/worldopenresearchjournal.com/public_html && php tools/deleteSubmissions.php N1 N2 N3'
   ```

2. Delete the test issue (Issues > Back Issues or Future Issues > **Delete**).
3. Remove the test users. In Users & Roles > Users, **Disable** each; then merge them into the administrator account, which removes them:

   ```bash
   ssh -i ~/.ssh/key -p 65002 u896415912@145.14.152.95 'cd ~/domains/worldopenresearchjournal.com/public_html && php tools/mergeUsers.php YOUR_ADMIN_USERNAME test-author test-author2 test-reviewer test-reviewer2 test-editor test-section test-copyeditor test-layout test-proof test-manager'
   ```

4. Run `scripts/check-placeholders.sh --url https://worldopenresearchjournal.com/worj`: it must print `0 finding(s)`.
5. Set **Disable Submissions** to the client's decision (on until the opening date).
6. Run `scripts/pull-backup.sh` so the first real backup holds a clean site.
