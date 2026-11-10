# Launch blockers

> **Partly out of date (2026-11-10).** Decision **D-VPS is resolved**: there is no VPS (the client bought shared hosting, `docs/DEPLOY-SHARED.md`) and no staging site. Rows about the VPS, the firewall, SSH hardening, certbot, the reboot step and a staging rehearsal are reworked when part 2 of the shared-hosting path lands. New open items from the hosting change: the Day-0 results, the mailbox's cost after the first free year, the MariaDB 10.5 lifecycle, and the choice of how files are delivered to the host (see "Delivery" in `docs/DEPLOY-SHARED.md`).

Every human step that nobody can do from the repository, in one table per kind, so the handover does not depend on anyone's memory. **Nothing in this file is done.** A row is ticked only by the person who did it, with a date and a name, and only after the "how we know" check passed.

- **Owner:** *client*, *developer*, *operator* (whoever runs the server: normally the developer unless the client names someone else), or a **named third party** (for example Crossref support, a sponsor, the hosting provider, the mail provider).
- **Named person:** left empty for the client or developer to fill. This file never invents a name.
- **Gates the launch date:** **Yes** means launch cannot happen until the row is done. **No (can follow)** means it can be done after launch.
- **Documented in:** where the details are. The gate numbers refer to `docs/LAUNCH-GATES.md`; the DOI and indexing items refer to `docs/DOI-SETUP.md` and `docs/INDEXING-READINESS.md`.

**At a glance:** 66 rows. **41 gate the launch date** and **25 can be done afterwards**. Of the outside-the-repository items in section A, 32 gate the launch date and 3 can follow. Section B is the developer's repository work (7 gating); section C (8) can wait; section D lists 16 research tasks, each with a source to read and an owner.

## A. Only a person outside the repository can do these

### A1. Client inputs and decisions

| ID | Item | Owner | Named person | What is needed | How we know it is done | Gates the launch date? | Documented in |
|---|---|---|---|---|---|---|---|
| A01 | **Journal ISSN** | client | | The ISSN assigned to the journal (a placeholder today; never invented) | Entered in OJS; `check-citation-meta.sh` passes without `--placeholder-issn` | **Yes** | gate 1.5, `docs/05-PLACEHOLDERS.md` |
| A02 | **Decision: do article pages need `citation_firstpage` and `citation_lastpage`?** | client decides, developer applies | | A yes or no for this journal (an online-only journal may have no page numbers) | The decision is written down and the Pages field and the check agree with it | **Yes** | gate 1.6, `docs/QA-SCRIPT.md` QF2 |
| A03 | **Legal publisher name and contact** | client | | The exact legal name and a contact | Entered in OJS (Publisher field) and matches any later Crossref application | **Yes** | checklist 1.2, `docs/DOI-SETUP.md` B1 |
| A04 | **Editorial team and board** | client | | Real editors with verifiable affiliations (never invented by the developer) | The Editorial Team page shows them; no placeholder remains | **Yes** | checklist D15, `docs/05-PLACEHOLDERS.md` |
| A05 | **Policies and policy text** (peer review, ethics, open access, copyright and licence, archiving, plagiarism, awards if kept) | client | | Approved text in place of the placeholders; OJS default wording replaced or confirmed. **Whether a lawyer reviews the privacy statement and policies is the client's decision, not ours.** | Decision table signed with name and date (D10, D13, D14); gate 4.1 and 4.3 pass | **Yes** | gates 4.1, 4.3, checklist |
| A06 | **Contact, technical-support and OAI role addresses** | client | | Addresses the client controls and monitors, not a person's mailbox (decision D23) | `check-discovery.sh` shows a role address in the OAI `Identify`; test mail reaches it | **Yes** | decision D23, `docs/QA-SCRIPT.md` QF3 |
| A07 | **Search description, Information texts, privacy statement** | client | | Text for Settings > Distribution > Search Indexing > Description, the three Information texts, and the privacy statement | `curl` shows a meta description (gate 4.5); `check-placeholders.sh --url` clean | **Yes** | gates 4.1, 4.5 |
| A08 | **Submission checklist and reviewer guidelines** | client | | Keep OJS's shipped checklist or give approved text (D10); give reviewer guidelines or accept the shipped "no guidelines" screen | Recorded in the decision table | **Yes** | checklist D10, `docs/QA-SCRIPT.md` B1, QF5 |
| A09 | **A client reviewer reads every enabled email template** | client | | One named reviewer reads each enabled template in full; no timeframe or policy claim they have not approved | A signed record with name and date | **Yes** | gate 4.2 |
| A10 | **When submissions open** | client | | The date or event after which "Disable Submissions" is switched off | The option is off at launch | **Yes** | gate 4.6 |
| A11 | **Deployment decisions P1 to P10 and D21** | client | | Main host, certificate method, firewall mode, HSTS, swap, time zone, Cloudflare Access, backup lock, `open_basedir`, bot protection (each has a default and a recommendation) | Each row answered in writing | **Yes** | `docs/DEPLOY.md`, "Decisions the client must make" |
| A12 | **Testers for the QA script, with inboxes they control** | client | | One or more named testers and their own addresses | The testers are named before the QA run | **Yes** | `docs/QA-SCRIPT.md` |

### A2. Accounts and access

| ID | Item | Owner | Named person | What is needed | How we know it is done | Gates the launch date? | Documented in |
|---|---|---|---|---|---|---|---|
| A13 | **The VPS account** (the developer does not pay for hosting) | client | | A VPS with Ubuntu 24.04 LTS at a provider the client pays, snapshot ability, and the provider's **browser console** login | The VPS exists; the console login was used once | **Yes** | `docs/DEPLOY.md` stage 0 |
| A14 | **Domain, DNS and Cloudflare access** | client | | Rights to create A records (no AAAA unless Nginx is set up for IPv6) and to configure the Cloudflare zone, shared with the operator | Records live; the operator can change Cloudflare settings | **Yes** | gate 2.5, 2.7 |
| A15 | **Mail provider account and SMTP credential** | client, with the mail provider | | A provider-issued app password or API credential, never a personal mailbox password | Gate 5.1 passes | **Yes** | `docs/DEPLOY.md`, gate 5.1 |
| A16 | **The age key pair** | client | | The client generates it off the server; only the **public** key goes to the operator | Gate 3.1: no private key on the server | **Yes** | `docs/DEPLOY.md` "Before you start" |
| A17 | **Backup bucket and versioning or object lock** | client decides, operator sets | | A bucket the client owns, with the retention choice written down | Gate 3.4 | **Yes** | decision P8, gate 3.4 |
| A18 | **Break-glass administrator and credential holder** | client | | A named business owner holds the credential in a password manager | Gate 6.2 | **Yes** | `docs/DEPLOY.md` "Administrator recovery", gate 6.2 |
| A19 | **The operator and their SSH key** | client names the operator | | A named person with a working SSH key (the developer unless the client says otherwise) | The SSH stage accepts the key login | **Yes** | `docs/DEPLOY.md` |
| A20 | **Certificate files, or the certbot choice** | client / operator | | Cloudflare Origin CA files placed, or certbot HTTP-01 chosen | The nginx stage passes | **Yes** | decision P2 |

### A3. Rehearsal and server

| ID | Item | Owner | Named person | What is needed | How we know it is done | Gates the launch date? | Documented in |
|---|---|---|---|---|---|---|---|
| **D-VPS** | **Decision: where the rehearsal runs.** (a) the client approves a **short-term second VPS** for the rehearsal, or (b) **rehearse on the real VPS** before any real content or DNS cutover, with a provider snapshot or a rebuild afterwards. **Trade-off:** (b) costs nothing extra but skips the safety of a separate machine, so a mistake in the firewall or SSH stage happens on the real server. **The console-rescue rehearsal is required either way.** | client | | An answer, a or b, in writing | The decision is recorded; gate 3.5 names the machine used | **Yes** | gate 3.5, `docs/DEPLOY.md` stage 0b |
| A21 | **The full rehearsal and the console rescue** | operator | | Provision, firewall and SSH with the second-terminal confirmation, backup and restore, on the machine chosen in D-VPS; the console login used once | Gate 3.5 | **Yes** | gate 3.5 |
| A22 | **A real backup restored with the client's key** | operator, with the client | | The operator restores a real backup using the client's private key, off the server | Gates 3.2 and 3.3 | **Yes** | `docs/DEPLOY.md` "Backups" |
| A23 | **Smoke tests, Cloudflare settings, no AAAA records** | operator | | The `docs/DEPLOY.md` smoke tests; Cloudflare SSL Full (strict), rate limits, no challenge to crawlers | Gates 2.4, 2.5, 2.7, 2.8 | **Yes** | gates 2.4 to 2.8 |
| A24 | **The scheduler's first-day check** | operator | | The day after launch: the log shows daily tasks ran | Gate 2.6 | No (can follow: it is the day after launch) | gate 2.6 |
| A25 | **First administrator password changed** | operator, client's administrator | | The forced change at first login | Gate 2.9 | **Yes** | gate 2.9 |

### A4. Real-domain checks

| ID | Item | Owner | Named person | What is needed | How we know it is done | Gates the launch date? | Documented in |
|---|---|---|---|---|---|---|---|
| A26 | **`check-live-config.py ... --launch`** | operator | | The production config on the VPS | Gate 2.1: exit 0 | **Yes** | gate 2.1 |
| A27 | **`check-discovery.sh --launch`, and the robots mode per site** | operator | | The live domain, with real content and no sample records | Gates 2.2 and 2.3: exit 0 | **Yes** | gates 2.2, 2.3 |
| A28 | **A real validation email, and SPF, DKIM and DMARC passing** | operator, client (DNS and provider) | | A test registration on the live site; the sending domain's DNS records | Gates 5.1 and 5.2 | **Yes** | gates 5.1, 5.2 |
| A29 | **The QA script run by a person** | client's tester, developer for fixes | | Every step run on staging and ticked with a date and a name | Gate 6.3 | **Yes** | `docs/QA-SCRIPT.md` |
| A30 | **Canonical tag recheck on staging** | developer runs, client decides | | The staging site on the real domain | Gate 2.11: the result is written down (INFO, never a failure) | No (can follow; decision D25) | gate 2.11 |
| A31 | **Search Console verification and the sitemap** | client, developer assists | | A Domain property by DNS TXT; the sitemap index submitted | Gate 2.10 | No (can follow: the domain must be live first) | `docs/SEARCH-CONSOLE.md` |
| A32 | **Support contact and the date the 14 days start** | developer supplies the contact; the start date is confirmed in writing at launch | | The contact's name and email; the written start date | `docs/HANDOVER.md` shows both with no BLOCKED left | **Yes** (the start date is written at launch) | `docs/HANDOVER.md` |
| A33 | **The change request is signed** | developer sends, client signs | | A written change request covering the awards pages and the Crossref configuration if the client expects them inside the agreed price | Gate 6.4 | **Yes** | gate 6.4 |
| A34 | **The developer's own administrator account is removed or transferred** | developer, client confirms | | A named person at the client takes ownership | Gate 6.1 | **Yes** (at handover, on launch day) | gate 6.1 |

## B. The developer's launch-day and handover actions (in the repository)

| ID | Item | Owner | Named person | What is needed | How we know it is done | Gates the launch date? | Documented in |
|---|---|---|---|---|---|---|---|
| B01 | **Placeholders replaced and fixtures removed** | developer, with the client's text | | The client's content (A04 to A07) placed; fixtures not shipped | Gates 1.1 and 1.2: exit 0 | **Yes** | gates 1.1, 1.2 |
| B02 | **The launch-day commit** removes `continue-on-error` and every `--placeholder-issn` caller | developer | | Done only after A01 | Gates 1.3 and 1.4, and **CI green on the head commit after the removal** | **Yes** | gates 1.3, 1.4 |
| B03 | **Every suite on the release commit** | developer | | `make lint`, `make infra-test`, `make infra-test-nginx`, `make infra-test-backup`, `make infra-test-reset`, `make infra-test-chroot`, `make eval` | Gate 1.7: every exit code 0 | **Yes** | gate 1.7, `docs/PHASE8-NOTES.md` |
| B04 | **Secret scan of the whole git history** | developer, client's reviewer reads the triage | | The procedure in `docs/LAUNCH-GATES.md` | Gate 1.8 | **Yes** | gate 1.8 |
| B05 | **Deliver the repository, with the licence and copyright notice decided** | developer delivers, client confirms | | The repository transferred or the source handed over; licence and notice chosen (see D13) | Gate 1.9: the client confirms receipt in writing | **Yes** | gate 1.9 |
| B06 | **Revoke tokens and deploy keys used by the Claude Code sessions** | developer | | A list of every key, token and installed app, and each revoked | Gate 1.10 | **Yes** | gate 1.10 |
| B07 | **No indexing, metric or accessibility claim on the site** | developer runs the checks, client reads the pages | | The reading list in gate 7.1 | Gate 7.1 | **Yes** | gate 7.1 |

## C. Can wait until after launch

| ID | Item | Owner | Named person | What is needed | How we know it is done | Gates the launch date? | Documented in |
|---|---|---|---|---|---|---|---|
| C01 | **Crossref membership and DOIs** | client; Crossref or a sponsor (third party) | | Everything in the blocked table `docs/DOI-SETUP.md` B1 to B11, including the final domain with real published articles | `docs/DOI-SETUP.md` steps done on the live site; never from a non-final domain | No (can follow) | `docs/DOI-SETUP.md` |
| C02 | **Indexer applications** (Google Scholar, DOAJ, PKP Index, OpenAlex, Scopus, Web of Science) | client | | The client's decision per service, after the criteria in D07 to D12 are read | The client-confirmed column in `docs/INDEXING-READINESS.md` filled by the client | No (can follow) | `docs/INDEXING-READINESS.md` |
| C03 | **Search Console follow-up** | client | | URL Inspection of the first real article and galley; no repeated resubmission | Recorded in `docs/SEARCH-CONSOLE.md` steps | No (can follow) | `docs/SEARCH-CONSOLE.md` |
| C04 | **The canonical-tag hook, only if staging still shows none** | client decides, developer builds | | A written decision (D25); `make check-citation` before and after to show the citation tags did not change | The hook, if approved, passes both checks | No (can follow) | decision D25 |
| C05 | **HSTS raised in stages** | operator | | A staged plan after a clean period; never preload at launch | `curl` shows the new value | No (can follow) | decision P4 |
| C06 | **`open_basedir`** (optional hardening) | operator | | A tested path list | Documented as done, or not claimed | No (can follow) | decision P10 |
| C07 | **Monthly reboot check and scheduler check** | operator | | A monthly calendar item | `ls /var/run/reboot-required` checked and logged each month | No (recurring) | `docs/HANDOVER.md` |
| C08 | **Phase 9 polish** | developer | | Only if a measurable problem appears after launch | A measured problem and a fix | No (skipped by default) | `autoresearch/program.md` |

## D. Research tasks for a person (not for the repository tooling)

Each needs a named person and a source to read. When read, the finding is written into the named document with the source URL and the date read.

| ID | Item | Owner | Named person | Source to read | Done when | Gates the launch date? |
|---|---|---|---|---|---|---|
| D01 | **B10: can a normal Crossref member get a test-system account, and how?** | client asks Crossref support or the sponsor (third party) | | Crossref's HTTPS POST documentation page and the answer from Crossref or the sponsor | Written into `docs/DOI-SETUP.md` | No (can follow) |
| D02 | **B11: can a credential used only for this journal be issued?** | client asks Crossref or the sponsor | | The Crossref OJS 3.5 plugin page and the answer from Crossref or the sponsor | Written into `docs/DOI-SETUP.md` | No (can follow) |
| D03 | **Does Crossref require an ISSN to register a journal's articles?** | client, with the sponsor | | Crossref's documentation on registering journal content: https://www.crossref.org/documentation/register-maintain-records/ | Written into `docs/DOI-SETUP.md` | No (can follow) |
| D04 | **Sponsor eligibility and cost; whether the client qualifies for the fee-free programme** | client | | https://www.crossref.org/community/sponsors/ and https://www.crossref.org/fees/ (amounts are read there, never copied) | The decision recorded; budget stated in B8 of `docs/DOI-SETUP.md` | No (can follow) |
| D05 | **Reference-linking requirements for this journal** | client, with Crossref or the sponsor | | https://www.crossref.org/documentation/register-maintain-records/ojs-plugin/ojs-3.5/ and the membership terms | Written into `docs/DOI-SETUP.md` | No (can follow) |
| D06 | **How a DOI shows on a real article page and in the PDF** | developer, after a real prefix exists | | The live article page and https://www.crossref.org/display-guidelines/ | Written into `docs/DOI-SETUP.md` | No (can follow) |
| D07 | **Google Scholar inclusion guidelines** | a named person at the client | | https://scholar.google.com/intl/en/scholar/inclusion.html | Criteria written into `docs/INDEXING-READINESS.md` with URL and date | No (can follow) |
| D08 | **DOAJ criteria** | a named person at the client | | https://doaj.org/ (find the current criteria page) | as above | No (can follow) |
| D09 | **PKP Index requirements** | a named person at the client | | https://index.pkp.sfu.ca/ | as above | No (can follow) |
| D10 | **OpenAlex requirements** | a named person at the client | | https://openalex.org/ (find how it discovers a journal) | as above | No (can follow) |
| D11 | **Scopus criteria** | a named person at the client | | https://www.scopus.com/ (find the content selection page) | as above | No (can follow) |
| D12 | **Web of Science (Clarivate) criteria** | a named person at the client | | https://clarivate.com/ (find the current evaluation criteria) | as above | No (can follow) |
| D13 | **What the GPL requires for the OJS code and the theme derived from the OJS default theme** | developer, client decides | | The licence files shipped in the OJS release and the GNU GPL text | The licence and copyright notice chosen and written down | **Yes** (needed for B05) |
| D14 | **How to fully remove a test user in the staging UI** | developer | | The OJS 3.5 documentation at https://docs.pkp.sfu.ca/ | Written into `docs/QA-SCRIPT.md` step H3 | No (can follow) |
| D15 | **Does "Invalid review round" (QF7) happen in an ordinary browser?** | the QA tester, developer reproduces | | Repeat `docs/QA-SCRIPT.md` D4 on staging both routes | The result written into the QA script | No (can follow) |
| D16 | **The checklist rows still marked `UNVERIFIED`** | a person walks them on staging | | `grep -n UNVERIFIED docs/ADMIN-SETUP-CHECKLIST.md` | Each row ticked with a date and a name, or dropped with a reason | **Yes** for the rows a launch gate depends on |
