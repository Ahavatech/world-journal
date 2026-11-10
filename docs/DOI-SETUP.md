# DOI setup for World Open Research Journal (Crossref)

**Status: nothing in this document has been done.** No registration agency is enabled, there is no DOI prefix, no Crossref membership and no credentials. Every item that depends on the client is marked **BLOCKED** with what is needed. This document contains no credential, no DOI prefix, no ISSN and no real or realistic example DOI: examples use `<DOI-PREFIX>/<suffix>`.

## How to read the labels

| Label | Meaning |
|---|---|
| `VERIFIED-SANDBOX 2026-11-10` | Seen on screen in the local sandbox (OJS 3.5.0-6), in a **throwaway journal that was deleted afterwards** (see "How the sandbox checks were done"). It says nothing about the real server. |
| `SOURCE 3.5.0-6` | Read in the OJS 3.5.0-6 source code, not seen on screen. |
| `Crossref, read 2026-11-10` | Paraphrased from the Crossref page named beside it, read on that date. Crossref changes its pages; read the page again before acting. |
| `UNVERIFIED (<reason>)` | Not seen or not read. Do not rely on it. |
| `BLOCKED` | Cannot be done until the client supplies the stated thing. |
| `[CLIENT DECISION]` | The client chooses. This document shows a default and never picks. |

## Where fees and requirements live

Crossref's fees change. **This document contains no amounts.** Read the current fees at <https://www.crossref.org/fees/> and the membership and sponsor pages linked below before budgeting.

## What Crossref says (paraphrased)

- **Membership comes first.** You must be a Crossref member to get a DOI prefix and register content; after applying and paying the pro-rated fee for the rest of the year, Crossref assigns the prefix and helps set up the account credentials, and the account password is set through an email Crossref sends ([Setting up as a member](https://www.crossref.org/documentation/member-setup/), read 2026-11-10).
- **Two kinds of fee, billed separately.** An annual membership fee, tiered by the organisation's publishing revenue or expenses, and a separate one-time fee for each record registered, usually billed quarterly in arrears. The membership fee does not include content registration. Updating the metadata of an existing record has no further fee ([Fees](https://www.crossref.org/fees/), read 2026-11-10). The same page says fees may change.
- **Sponsors.** A small organisation that cannot join directly can join through a **sponsor**, which handles the administrative, billing, technical and, where relevant, language support. When a member joins through a sponsor, the sponsor pays the membership and registration fees on the member's behalf, and may charge the member for its own services ([Sponsors program](https://www.crossref.org/community/sponsors/), [Fees](https://www.crossref.org/fees/), both read 2026-11-10). The sponsors page lists current sponsors. Whether a given publisher is eligible, and what a sponsor would charge, is `UNVERIFIED (depends on the publisher and the sponsor; ask them)`.
- **A programme for some members.** The fees page says members eligible for its GEM programme pay neither membership nor registration fees ([Fees](https://www.crossref.org/fees/), read 2026-11-10). Whether the client's country or organisation qualifies is `UNVERIFIED (not checked)`.
- **Sanctions.** Crossref says membership is not open to organisations or individuals subject to US, UK or EU sanctions ([Sponsors program](https://www.crossref.org/community/sponsors/), read 2026-11-10).
- **A DOI cannot be changed or deleted once registered**, and each registered DOI appears on the next invoice, so register only DOIs you definitely want ([Setting up as a member](https://www.crossref.org/documentation/member-setup/), read 2026-11-10).
- **Opaque suffixes.** Crossref advises that a DOI suffix carry no readable information: no journal title or initials, no page number, no date. Such information can change or turn out wrong, and the DOI cannot be corrected. A random suffix is recommended ([Constructing your DOIs](https://www.crossref.org/documentation/member-setup/constructing-your-dois/), read 2026-11-10).
- **The first journal-article deposit creates the journal title record**, and later deposits must match it, so the exact journal title must be decided before the first deposit ([Setting up as a member](https://www.crossref.org/documentation/member-setup/), read 2026-11-10).
- **Landing pages.** Each DOI must resolve to a page unique to that item, with full bibliographic information, the DOI shown as a link, and a way to reach the full text (the full text may sit behind a login if the landing page itself is public). Linking a DOI straight to a PDF is not good practice ([Creating a landing page](https://www.crossref.org/documentation/member-setup/creating-a-landing-page/), read 2026-11-10).
- **Display.** DOIs are shown as a full link of the form `https://doi.org/<DOI-PREFIX>/<suffix>`, and displaying them is an obligation of membership ([Display guidelines](https://www.crossref.org/display-guidelines/), [Setting up as a member](https://www.crossref.org/documentation/member-setup/), both read 2026-11-10).
- **OJS 3.5.** Crossref has its own page for the OJS 3.5 plugin: enable the plugin, set the DOI settings, enter the credentials, then register from the DOIs page. It says to use the default suffix format, to leave the Testing box unchecked in production, and to list only Articles under "Items with DOI" ([OJS 3.5 plugin](https://www.crossref.org/documentation/register-maintain-records/ojs-plugin/ojs-3.5/), read 2026-11-10). It also says linking references is a requirement of membership and describes switching on reference metadata; what exactly is required of this journal is `UNVERIFIED (ask Crossref or the sponsor)`.
- **Credentials.** The same page says a shared organisational account uses its own username, while a personal account needs the email address and a role in the username field ([OJS 3.5 plugin](https://www.crossref.org/documentation/register-maintain-records/ojs-plugin/ojs-3.5/), read 2026-11-10).
- **Test system.** Crossref has a separate test system at a different address; its page for service providers says an account must be requested from Crossref support before testing there ([HTTPS POST](https://www.crossref.org/documentation/register-maintain-records/direct-deposit-xml/https-post/), read 2026-11-10). That page speaks to service providers. **Whether a normal member can get a test account, and how, is `UNVERIFIED (not stated on a page read)`: ask Crossref or the sponsor.**

## BLOCKED: what the client must supply

| # | Item | Needed from | How we will know it is done |
|---|---|---|---|
| B1 | **The registrant**: the legal publisher's exact name and contact. Not the developer. | Client | The client sends the developer the legal name and contact as plain text (not a credential), and it matches the name on the Crossref membership application. |
| B2 | **Crossref membership, or a sponsor.** Decide direct membership versus a sponsor; check eligibility and cost at the pages linked above. | Client (the sponsor or Crossref decides eligibility) | A written acceptance from Crossref or the sponsor. |
| B3 | **The DOI prefix and the deposit credentials**, issued to the client by Crossref or the sponsor. Never issued to, held by, committed by or pasted to the developer. | Client / Crossref / sponsor | The client confirms in writing that the prefix and an account exist. Nobody else needs to see the values, and this document never shows them. |
| B4 | **The ISSN.** `docs/06-INDEXING-ROADMAP.md` recommends having it before registering. Whether Crossref requires it is `UNVERIFIED (not stated on a page read)`. | Client | The ISSN is entered in OJS (checklist), and `scripts/check-citation-meta.sh` runs without `--placeholder-issn`. |
| B5 | **The journal live on its final HTTPS domain with real published articles.** A live deposit records the article's web address, so depositing from the sandbox or a staging site registers DOIs that point to the wrong place, and a DOI cannot be deleted. | Client / operator | `scripts/check-discovery.sh --robots-mode production --launch https://HOST` and `scripts/check-live-config.py ... --launch` both pass, and at least one real article is published. |
| B6 | **The journal title**, exactly as it should appear in Crossref's record. | Client | The title is decided in writing before the first deposit. |
| B7 | **Who is authorised to deposit**, and the **credential holder** (see "Credentials"). | Client | Two named people, written down. |
| B8 | **Budget** for membership or sponsor fees plus per-record fees. DOI registration is separate from the development fee. | Client | The client confirms a budget after reading the fees page. |
| B9 | **Landing pages meet Crossref's requirements** (above). | Developer, then client | A real article page shows full bibliographic data, the DOI as a link and the full text link. `UNVERIFIED (needs a real DOI, so cannot be seen before B3)`. |
| B10 | **A test-system account**, if Crossref gives one to this journal. | Client asks Crossref or the sponsor | `UNVERIFIED (see "Test system" above)`. |

**Sample articles are never deposited, live or test.** The sandbox's three articles are fixtures. Deposit only real, published, final content.

## `[CLIENT DECISION]` table

| # | Decision | Where in OJS | OJS default (new journal) | Chosen value |
|---|---|---|---|---|
| DD1 | **DOIs on or off until B1 to B9 are done.** | Settings > Distribution > DOIs > Setup > *Allow Digital Object Identifiers (DOIs) to be assigned to work published in this journal* | **On**, but inert without a prefix (checklist row 7.1 turns it off until the credentials exist) | |
| DD2 | **Which items get a DOI.** | Same tab, *Items with DOIs*: *Articles*, *Issues*, *Article galleys, such as a published PDF* | *Articles* only. Crossref's OJS page also recommends articles only. | |
| DD3 | **Suffix format.** See "The suffix decision" below. | Same tab, *DOI Format*: *Default*, *None*, *Custom pattern (not recommended)* | *Default* | |
| DD4 | **When a DOI is assigned.** | Same tab, *Automatic DOI Assignment*: *Upon reaching the copyediting stage*, *Upon publication*, *Never* | *Upon reaching the copyediting stage* (allows the DOI to be printed in the PDF; Crossref's OJS page notes this) | |
| DD5 | **Depositor name.** Required by the plugin; included in deposited metadata (the form says it records who submitted the deposit). | Settings > Distribution > DOIs > Registration > *Depositor name* | empty | |
| DD6 | **Depositor email.** Required by the plugin; included in deposited metadata and used for the deposit confirmation email. Use a **role address the client controls**, not a person's mailbox, for the same reason as the public OAI contact address (decision D23 in `docs/ADMIN-SETUP-CHECKLIST.md`). | same, *Depositor email* | empty | |
| DD7 | **Automatic deposit on or off.** | same, *Automatic Deposit* | off | |
| DD8 | **The credential holder** for the Crossref username and password: a named person at the client, as with the break-glass administrator. | n/a | n/a | |

### The suffix decision

**Baseline: OJS "Default".** `SOURCE 3.5.0-6` (`lib/pkp/classes/doi/DoiGenerator.php`): the default suffix is a random number encoded in a base-32 alphabet followed by a two-character checksum, so it is short, carries no information about the journal, issue, date or pages, and cannot be guessed from other DOIs. The sandbox shows it as *Default - Automatically generates a unique eight-character suffix* (`VERIFIED-SANDBOX 2026-11-10`). This is the format Crossref recommends (above).

| | For a custom pattern | Against a custom pattern |
|---|---|---|
| Readability | Staff can read what a DOI refers to. Crossref accepts that some systems want this ([Constructing your DOIs](https://www.crossref.org/documentation/member-setup/constructing-your-dois/), read 2026-11-10). | Crossref advises against readable information in a suffix. |
| Stability | n/a | Anything built from fields that can change after minting is a risk: journal initials, volume, issue, year, **page numbers (`%p`)** and **custom identifiers (`%x`)**. A DOI cannot be corrected. OJS itself warns that custom patterns often lead to problems generating and depositing DOIs (`SOURCE 3.5.0-6`, `locale/en/manager.po`). |
| Guessing | n/a | A sequence or predictable pattern lets other services try to guess unregistered DOIs ([Constructing your DOIs](https://www.crossref.org/documentation/member-setup/constructing-your-dois/), read 2026-11-10). |
| Sandbox label | The option reads *Custom pattern - (not recommended)* (`VERIFIED-SANDBOX 2026-11-10`). | |

**Never change the suffix format after DOIs have been created.** A registered DOI string cannot change, so a changed format only means two styles of DOI in one journal. The choice stays with the client (DD3).

## Ordered steps once B1 to B9 are done

All paths below were seen in the sandbox (`VERIFIED-SANDBOX 2026-11-10`) unless a step says otherwise. Do them on the **real, final domain**, never in the sandbox or on a staging site.

1. **Enable the Crossref plugin.** Settings > Website > Plugins: the plugin is bundled and listed there (`VERIFIED-SANDBOX 2026-11-10`; the plugin sits in `plugins/generic/crossref`, `SOURCE 3.5.0-6`). Tick its checkbox. Until it is enabled, *Settings > Distribution > DOIs > Registration* reads *No Registration Agency Enabled*.
2. **DOI settings.** Settings > Distribution > DOIs > **Setup**: tick *Allow Digital Object Identifiers (DOIs)*, choose the items (DD2), enter the **DOI prefix** (the value Crossref issued; the screen's own hint shows the shape), choose the assignment time (DD4) and the format (DD3). Save.
3. **Registration settings.** DOIs > **Registration**: choose *Crossref* in *Registration Agency*. The form then shows *Automatic Deposit*, *Depositor name* (required), *Depositor email* (required), *Username*, *Password* and *Testing* (`VERIFIED-SANDBOX 2026-11-10`; nothing was typed or saved when this was looked at). Enter DD5 to DD7. **The credential holder types the username and password; nobody else.** Leave *Testing* **unchecked** for live deposits.
4. **Journal title and metadata.** Confirm B6, and that the article page meets B9, before the first deposit.
5. **Register.** The **DOIs** item in the left menu lists submissions with filters *Needs DOI / DOI Assigned* and *Unregistered / Submitted / Registered / Has Error / Needs Sync*, and a *Bulk Actions* menu (`VERIFIED-SANDBOX 2026-11-10`; the *Deposit DOIs* action is described on [Crossref's OJS 3.5 page](https://www.crossref.org/documentation/register-maintain-records/ojs-plugin/ojs-3.5/), read 2026-11-10, and was `UNVERIFIED (not seen on screen: it needs articles and a prefix)`). Start with **one** real article.
6. **Automatic deposit relies on the server's scheduler.** The form says automatic deposit happens at scheduled intervals. The deposit task is one of the daily tasks listed in `docs/DEPLOY.md` ("Scheduled tasks"); if the scheduler stops, automatic deposits stop silently. Run the scheduler check there.

### Test deposit

Crossref's OJS page tells you to leave *Testing* unchecked in production. The plugin's *Testing* checkbox sends deposits to Crossref's separate test address instead of the live one (`SOURCE 3.5.0-6`, `plugins/generic/crossref/CrossrefExportPlugin.php`), and the plugin's own text says to remove the option in production. A test deposit therefore needs **test-system credentials, which are separate** (B10).

1. Only after B10, tick *Testing*, enter the **test** credentials, and deposit **one real article** (never a sample article).
2. Read the result on the DOIs page and in the email sent to the depositor address. Fix any error before going live.
3. Untick *Testing*, replace the test credentials with the live ones, and run steps 5 to 6 above.
4. If B10 turns out not to be available, say so to the client: the first live deposit then has no rehearsal, so start with one article and check it carefully.

## After the first live deposit

- **Check the DOI resolves.** Open `https://doi.org/<DOI-PREFIX>/<suffix>` for the deposited article. It can take time to start working after registration (`UNVERIFIED (resolution delay not measured here)`).
- **The article page** shows the DOI as a link (Crossref display guidelines above). How the theme shows it is `UNVERIFIED (cannot be seen without a real prefix, which we must not invent)`.
- **The PDF front page:** whether the DOI is printed on the PDF is a client decision and `UNVERIFIED (not built, not seen)`. DD4 *Upon reaching the copyediting stage* is what allows a DOI to exist before the PDF is made.
- **Run the citation check:** `scripts/check-citation-meta.sh https://HOST/JOURNAL/article/view/ID` must show the DOI as `INFO  citation_doi = ...` with a bare DOI (Phase 6 rule: an absent tag passes, a present tag with an empty value fails, a value that is not a bare DOI is a warning).

## Credentials

- **Where the Crossref password lives:** the settings form says on screen that the password is saved **as plain text, not encrypted** (`VERIFIED-SANDBOX 2026-11-10`; the plugin stores `username` and `password` as settings, `SOURCE 3.5.0-6`). So it is in the OJS database, **and therefore in every backup** (the off-server backups are encrypted with the client's key, `docs/DEPLOY.md`) and visible to every administrator who opens the form.
- **Change the password whenever anyone with administrator access leaves**, and whenever it may have been exposed. Use Crossref's own account tools for the change (`UNVERIFIED (not read)`), then update the form.
- **Never** put the username or password in git, `provision.env`, `.env`, an issue, a pull request, a chat message, or an email. If a credential is ever pasted anywhere by mistake, treat it as exposed and change it.
- **Who holds it** is decision DD8. Prefer an organisational (shared role) account over a personal one, as the Crossref OJS page describes; a personal account leaves with the person.

## What not to do

- **Do not enable a registration agency or deposit anything until B1 to B9 are done.**
- **Do not invent or guess a DOI prefix**, and do not use one from a document, a screenshot or another journal.
- **Do not deposit from a non-final domain** (sandbox, staging, a temporary hostname, or an HTTP address). A live deposit records the article's address; the DOI cannot be deleted. Staging deposits belong on Crossref's test system only, and only if B10 exists.
- **Never deposit the sample articles, live or test.**
- **Do not change the suffix format after DOIs exist** (see the suffix decision).
- **Do not leave *Testing* ticked in production**, and do not leave test credentials in the form.
- **Do not promise indexing, a DOI date or an impact factor to anyone.** See `docs/INDEXING-READINESS.md`.

## How the sandbox checks were done

To open the Crossref plugin's settings form the plugin had to be enabled, so four **throwaway journals** were created in the sandbox (`doiprobe`, ids 4 to 7), looked at, and **deleted afterwards**; the sandbox then listed only the real sandbox journal again, and its three sample articles still passed `make check-pdf`. In them the Crossref plugin was ticked, *Crossref* was selected in the agency list (no save), and **nothing was typed into any field, not even a fake value**. DOIs were never enabled in the real sandbox journal.
