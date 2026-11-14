# First login: a quick start for every user group

For each person's first visit to `https://worldopenresearchjournal.com/worj/login`. Each card takes about five minutes. The administrator sends the matching card (and the message in section 2) when an account is created. The full handbook is `docs/CLIENT-HANDBOOK.md`; the test checklist is `docs/TEST-FLOW-ROLES.md`.

## 0. How the accounts are created (administrator)

`scripts/create-accounts-shared.sh` (dry run first, then `--apply`) creates the Journal editor and Section editor accounts with a random temporary password each. It prints each password once on your screen and stores it nowhere: send it to the person by a different channel than the username. OJS makes every new account change that password at the first login (a change-password page opens before they can enter). For the first 14 days after they register, a "Welcome" box with the steps below shows at the top of the public pages while they are signed in.

## 1. For everyone, first

1. Open the login page and sign in with the username and temporary password you were given.
2. **Change the password straight away:** click your name (top right), then **Edit Profile**, then **Password**. Use a long unique password kept in a password manager. Never send it in a message.
3. In **Edit Profile**, check your name, email address and affiliation. Reviewers and authors are listed or contacted from these.
4. Check where the journal's email lands. Messages come from **editorial@worldopenresearchjournal.com**. If none arrives within a few minutes, look in **spam** and mark the first one "not spam".
5. Log out and in once to make sure the new password works.

## 2. Message to paste when you create an account (administrator)

> Hello [name],
>
> An account for the World Open Research Journal has been created for you as [role].
> Login: https://worldopenresearchjournal.com/worj/login
> Username: [username]
> Temporary password: [sent separately, not in this message]
>
> Please log in now and change your password (your name, top right, then Edit Profile, then Password). Then follow the quick start for your role: [paste the card]. Messages from the journal come from editorial@worldopenresearchjournal.com; please check your spam folder the first time.
>
> If you cannot log in, use "Forgot your password" on the login page, or reply to this message.

Send the temporary password in a separate message or in person, never in the same message as the username.

## 3. Quick start by role

### Site administrator (the owner)

1. After the first-login steps above, open **Administration > Site Settings**: the contact email should be `admin@worldopenresearchjournal.com`.
2. Open **Administration > Hosted Journals**: the journal is listed and enabled.
3. Create the editorial team's accounts: **Settings > Users & Roles > Users > Add User**. Give each person only the role they need.
4. Keep this login private: use a normal editor account for daily work.
5. Write down who holds the backup key and who runs the weekly backup.

### Journal manager

1. Open **Settings > Journal** and read the About text, summary and contact details.
2. Check **Settings > Workflow > Submission**: whether submissions are open (**Disable Submissions**), the sections authors can choose, and the Author Guidance.
3. Read every email template once: **Settings > Workflow > Emails**. Remove any promise you cannot keep.
4. Create or change team accounts: **Settings > Users & Roles**.
5. Look at **Settings > Website > Setup > Navigation** to see how the menus are built.

### Journal editor (Editor-in-Chief)

1. Open the **Editor Dashboard**. It lists every submission.
2. Open one test submission, find the left menu (**Submission, Review, Copyediting, Production**, then **Publication**).
3. Learn the three buttons you will use most: **Assign** (a person to a submission), **Send for Review**, and the decisions (**Accept**, **Request Revisions**, **Decline**).
4. Read what each decision email says before sending: you can edit the text each time.
5. Check **Issues**: where you create an issue and publish it.

### Section editor (Assistant Editor)

1. Open the dashboard: you see **only** the submissions assigned to you.
2. Open one: check the **Participants** list, the **Review** stage and the **Discussions** tab.
3. You can invite reviewers and record recommendations; the Editor-in-Chief records the final decision unless you were also given that.
4. If a submission you expect is missing, the editor has not assigned it to you yet.

### Copyeditor

1. The dashboard shows the submissions assigned to you at the **Copyediting** stage.
2. Open one, download the file, edit it, and upload the edited file in the copyediting section.
3. Tell the editor through the **Discussions** tab if the author needs to check something.

### Layout editor / Designer

1. Open your assigned submission at the **Production** stage.
2. In the article's **Publication** tab choose **Galleys > Add galley**, label it *PDF*, and upload the final PDF.
3. Check the PDF opens from the article page.

### Proofreader

1. Open your assigned submission and the galley (the final PDF).
2. Check it against the accepted text and report corrections in the **Discussions** tab.

### Reviewer

1. You get an **invitation email** with a link. Open the link (you may be asked to log in or set a password).
2. **Accept** or **decline** the request. If you decline, the editor is told at once.
3. Read the guidelines and download the file. The file has the author's name removed.
4. Write your comments (one box for the author, one for the editor only), choose a recommendation, and **Submit Review** before the due date.
5. You will see only the review you were invited to, nothing else on the journal.

### Author

1. **Register** at `https://worldopenresearchjournal.com/worj/user/register` (tick the privacy box and the Author role). The journal then emails you a link to confirm your address: click it, then log in. The email can take a few minutes and may be in your **spam folder**.
2. Read the **Author Guidelines** (menu: About > Submissions) before you start.
3. Choose **New Submission**, pick the section, and follow the five steps: **Details, Upload Files, Contributors, For the Editors, Review**, then **Submit**.
4. You receive a confirmation email. Follow your article from your own dashboard: you see only your own submissions.
5. If revisions are requested, upload the revised file from **Revisions requested** on your dashboard.

### Reader (no account needed)

1. Read articles and issues from **Current** and **Archives**, or use **Search**.
2. The policies, About, Aims and Scope and the Editorial Team are under **About**.
3. Questions go to `editorial@worldopenresearchjournal.com`; privacy requests to `privacy@worldopenresearchjournal.com`.

## 4. If a first login fails

| Symptom | What to try |
|---|---|
| "Invalid username or password" | Check upper and lower case; use **Forgot your password**; ask the administrator to reset it |
| No email arrives (including the account confirmation) | Look in spam; wait a few minutes (emails are sent by a job that runs every minute); ask the administrator to check your address in Users |
| You see less than you expect | The administrator assigns roles and submissions: ask them to check your role |
| You see more than you should | Tell the administrator at once so the role can be reduced |
