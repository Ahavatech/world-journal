# Indexing readiness

**Technical readiness is not eligibility.** This document lists what the repository has built and checked, and what the client must supply. **No row states or implies that the journal is eligible for, will be accepted by, or will appear in any service.** Nothing has been applied for. The "Status" column is fixed at **not applied** and changes only when the client confirms an application in the "Client-confirmed" column. Do not state any status the client has not confirmed.

Most services decide on their own criteria, which this session did not read (see "What was and was not read"). Do not infer a criterion from a row below.

## Services

| Service | Status | Client-confirmed (date, who) | Blocked on (client input) | Evidence the client must supply | Already built here (and the check that proves it) | Official page |
|---|---|---|---|---|---|---|
| **Google Search** (Search Console) | not applied | | The journal live on its final domain; access to the domain's DNS to add a verification record | Proof of domain control (a DNS record the client's DNS provider holds) | A sitemap index and journal sitemap, a `robots.txt` that is open in production and closed on staging, and an OAI-PMH endpoint, all verified by `scripts/check-discovery.sh`; the human steps are in `docs/SEARCH-CONSOLE.md` | <https://search.google.com/search-console> `UNVERIFIED (official page not read)` |
| **Google Scholar** | not applied | | Real published articles on the final domain. There is no submission form to fill in: Scholar finds articles by its own crawl and the schedule is its own | Published articles whose pages carry the expected metadata and a readable PDF | `citation_*` tags on article pages and a readable PDF per article, verified by `scripts/check-citation-meta.sh` (`make check-citation`) and `scripts/check-pdf.sh` (`make check-pdf`). **Nothing in this repository can make Scholar index a paper** (`docs/SEARCH-CONSOLE.md`) | <https://scholar.google.com/intl/en/scholar/inclusion.html> `UNVERIFIED (official page not read)` |
| **Crossref and DOIs** | not applied | | Everything in the BLOCKED table of `docs/DOI-SETUP.md` (B1 to B11): the legal publisher, Crossref membership or a sponsor, a prefix and credentials issued to the client, the ISSN, the final domain, the journal title, an authorised depositor, a budget | What `docs/DOI-SETUP.md` lists; Crossref's own requirements are paraphrased there with URLs and the date read | OJS has a Crossref plugin bundled (not enabled). The only check built is the `citation_doi` rule in `scripts/check-citation-meta.sh` (absent passes, present-but-empty fails). No DOI exists or is enabled | <https://www.crossref.org/> (requirements and fees pages are cited in `docs/DOI-SETUP.md`, read 2026-11-10) |
| **DOAJ** | not applied | | The client's decision to apply; everything DOAJ itself requires `UNVERIFIED` | `UNVERIFIED (official page not read)` | OAI-PMH is on and checked by `scripts/check-discovery.sh`. The OJS source includes a DOAJ export plugin (`plugins/importexport/doaj`); it has not been configured or tried | <https://doaj.org/> `UNVERIFIED (official page not read)` |
| **PKP Index** | not applied | | `UNVERIFIED`: how a journal is added and what it needs were not read | `UNVERIFIED (official page not read)` | OAI-PMH is on and checked by `scripts/check-discovery.sh`. Nothing was submitted | <https://index.pkp.sfu.ca/> `UNVERIFIED (official page not read)` |
| **OpenAlex** | not applied | | `UNVERIFIED`: how OpenAlex finds a journal was not read | `UNVERIFIED (official page not read)` | OAI-PMH, a sitemap and `citation_*` tags exist. **This is not a claim about how OpenAlex ingests anything.** | <https://openalex.org/> `UNVERIFIED (official page not read)` |
| **Scopus** | not applied | | The client's decision to apply; everything Scopus requires `UNVERIFIED` | `UNVERIFIED (official page not read)` | Nothing is built for Scopus | <https://www.scopus.com/> `UNVERIFIED (official page not read)` |
| **Web of Science** (Clarivate; ESCI and the Journal Impact Factor) | not applied | | The client's decision; Clarivate's criteria and process `UNVERIFIED`. See the warning below. | `UNVERIFIED (official page not read)` | Nothing is built for Clarivate | <https://clarivate.com/> `UNVERIFIED (official page not read)` |

## Scam warning

"Global Impact Factor", "Universal Impact Factor", "ISI impact factor" sold by third parties are not Clarivate metrics. Do not pay for them, and never display them.

The journal does not display any impact factor, quartile, ranking or indexing badge anywhere, and none may be added until the client has confirmed the matching row above in writing and the service itself shows it.

## General preparation

The roadmap (`docs/06-INDEXING-ROADMAP.md`) lists what a new journal normally needs before any of the above is worth attempting: a real ISSN, a stable domain, published policies that are the client's own (peer review, ethics, open access), an editorial board with verifiable affiliations, a clear statement on fees, regular publication on schedule, and a body of published articles. **None of these exists yet for this journal**; they are the client's inputs and are tracked in `docs/ADMIN-SETUP-CHECKLIST.md` and `docs/03-TASKS.md`. Do not give the client a date for any of these services: that depends on a track record, not on this repository.

## What was and was not read

- **Read:** Crossref's pages, on 2026-11-10; the results are paraphrased, with URLs and dates, in `docs/DOI-SETUP.md`.
- **Not read:** the official pages of every other service in the table. Each is marked `UNVERIFIED (official page not read)` and linked at its home page only; the link is where a person should start, and the criteria must be read there. Assigning someone to read them is a Phase 8 launch-blocker item.
- **Built and checked in this repository** (the only things the "Already built here" column may name): `scripts/check-discovery.sh`, `scripts/check-citation-meta.sh`, `scripts/check-pdf.sh`, the sitemap and `robots.txt` served by the Nginx layer, OJS's OAI-PMH endpoint, and `docs/SEARCH-CONSOLE.md`.
