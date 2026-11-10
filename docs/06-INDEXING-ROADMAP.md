# 06. DOI and Impact Factor roadmap

This is guidance for the client and for DOI setup tasks. Verify fees and requirements on the official sites before quoting anything, because they change.

## DOI (Digital Object Identifier)
**What it is:** a permanent link identifier for each article. **Where it comes from:** the publisher registers DOIs through a registration agency; for scholarly journals that is normally **Crossref**.

**Route:**
1. Decide the registrant (the legal publisher, not the developer).
2. Join Crossref directly as a member, **or** use a Crossref **sponsor** (an organisation that registers on behalf of smaller publishers). Check eligibility and current fees at https://www.crossref.org/fees/ and the membership pages.
3. Receive a DOI prefix and deposit credentials.
4. In OJS enable DOIs (journal settings), set prefix and the suffix format (the OJS Default is random and opaque, which Crossref recommends; a custom pattern is not recommended, see `docs/DOI-SETUP.md`), assign DOIs to published articles, and enable the Crossref export/deposit plugin with the credentials. Verify the exact menu names and plugin options on the pinned OJS 3.5 release.
5. Test with Crossref's test system first if available, then register. Confirm each DOI resolves to the article landing page.
6. Show the DOI on article pages and in the PDF front page.

**Needed from client:** legal publisher name and contact, ISSN (recommended before registering), journal URL live on its final domain, who is authorised to deposit, and budget for membership or sponsor fees plus per-record fees. DOI registration is separate from the development fee.

## Impact Factor
**What it is:** the Journal Impact Factor (JIF), published by **Clarivate** in Journal Citation Reports (JCR). Only journals indexed in the Web of Science Core Collection receive one. It is a trademark metric: you cannot buy, apply for or generate it directly.

**What Clarivate says (check their site for current text):** new journals are evaluated against 24 quality criteria and, if selected, are added to the Emerging Sources Citation Index (ESCI); since the 2023 JCR release, JIF is extended to all Core Collection journals, including ESCI. Clarivate has said its current focus is quality rather than impact, and new submissions are prioritised.

**Realistic route:**
1. Launch properly: real ISSN, stable domain, transparent peer review, ethics and open-access policies, a credible editorial board with verifiable affiliations, clear APC (or no-fee) statement.
2. Publish regularly and on schedule; build a body of articles with working DOIs and good metadata.
3. Get discovered: Google Scholar, DOAJ (if eligible), PKP Index, OpenAlex.
4. Earn citations from independent researchers over time.
5. When the journal meets Clarivate's published criteria, submit through the Web of Science publisher portal.
6. Parallel route: Scopus evaluation (gives CiteScore, which is not the same as JIF).

**Timeline:** not at launch. It depends on a track record and citations. Do not promise a date to the client.

## Scam warning
"Global Impact Factor", "Universal Impact Factor", "ISI impact factor" sold by third parties are not Clarivate metrics. Do not pay for them, and never display them.

## Developer responsibilities in this repo
Make the site technically eligible (metadata, DOIs, OAI-PMH, policies pages, clear editorial info). Provide `docs/INDEXING-READINESS.md` listing each service, its current status (all "not applied"), and the evidence needed. Do not state any status the client has not confirmed.
