# Research Awards: how to run them

The plugin is `ojs/plugins/generic/worjAwards`. The client approved the plugin option on 2026-11-14 ("Add nomination form and scoring"), so `docs/04-AWARDS.md` Option B applies, in a smaller form than that page lists (see "What it does not do"). Judging uses the four criteria in the client's own awards text: Originality, Research Quality, Scholarly Impact and Outstanding Contribution.

## Turning it on (operator, once)

1. Build and deploy a release that carries the plugin (`scripts/build-release.sh` copies it).
2. `scripts/awards-shared.sh` (dry run), then `scripts/awards-shared.sh --apply`: creates the two tables and enables the plugin.
3. Show the awards pages: `scripts/launch-prep-shared.sh --approve awards,awards-winners --drop-blanks` (dry run first). The pages are held until then.

## Pages

| Address | Who | What |
|---|---|---|
| `/worj/awards-nominate` | anyone | the nomination form (closed until the manager opens it) |
| `/worj/awards-judge` | judges | score each nomination 1 to 5 on the four criteria, add a comment, or declare a conflict |
| `/worj/awards-manage` | journal manager | open or close nominations, set categories and judges, see scores, decide, export, delete |
| `/worj/awards-recipients` | anyone | the recipients (nominations the manager marked Winner) |

## The cycle

1. **Manager, Settings:** tick "Nominations are open"; one category per line (the default is Best Researcher); judges as usernames, one per line (each judge needs an account first).
2. **Nominations arrive** by the form. The journal's mailbox is emailed each one and the nominator gets a confirmation. A nomination is stored even if the email fails.
3. **Judges** sign in and open the judge page. A judge who knows the nominee ticks the conflict box: that judge's scores for it are left out.
4. **Manager** reads the mean total (of 20), sets a status (Received, Shortlisted, Winner, Not selected) and a period such as "Volume 1".
5. **Winner:** the recipient appears on the public recipients page (name, category, period, article; never an email address). Send the certificate (`ojs/client-content/internal/WORJ-Award-Certificate-Template.docx`, fill in the blanks) to the author, and publish an announcement if you want one.
6. **Close nominations** when the period is over.

## What it does not do

- No file upload on the nomination form: the nominator gives a supporting statement (50 to 3000 characters) and, if wanted, the article's web address or DOI.
- No automatic certificate and no email to the nominee: the journal sends those.
- No payment, sponsor or prize handling.
- The score is advice for the manager; the plugin never decides a winner by itself.

## Privacy

Nominations hold the nominator's and nominee's names and email addresses. Only the journal manager sees them (and the judges see the nominee's name, article and statement, not the nominator's email). The CSV export contains email addresses: keep it private. Delete a nomination from the manager page when it is no longer needed. The form asks the nominator to agree to the use of these details; the privacy page may need a line about it (client decision).
