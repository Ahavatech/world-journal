# Search engine optimisation (SEO) and crawling

What is in place, what the client does after launch, and what honestly cannot be promised. Nothing here claims a ranking, an index status or a metric.

## In place on every public page (theme `worj`, `WorjSeo.php`)

- A **canonical link** (the page's own address; a search page drops its query string).
- A **meta description** on the home page, every article and every issue (the abstract for an article). Ordinary pages carry none, so no two pages share a description.
- **Open Graph and Twitter card** tags (title, description, address, image; `article:published_time`, `article:author` and one `article:tag` per keyword on an article).
- **The article's own keywords** as `<meta name="keywords">`, and as links: each keyword on an article page links to a search for it, so related articles are reachable by crawlers.
- **Structured data (schema.org JSON-LD):** a `Periodical` and `WebSite` (with a search action) on the home page, a `PublicationIssue` on an issue, and a `ScholarlyArticle` on an article with its authors, abstract, keywords, dates, licence, open-access flag, issue and PDF. An ISSN or DOI is printed only when the journal has a real one (a placeholder is never printed).
- The data is escaped so a title cannot break out of the page (tested).

Already provided by OJS and kept: **Google Scholar `citation_*` tags** (including `citation_keywords` and `citation_pdf_url`), **Dublin Core** tags, the **sitemap** (`/index/sitemap`, listed in the production `robots.txt`), `robots.txt` that blocks only `/cache/`, an OAI-PMH feed, clean URLs and a PDF viewer.

## What the client or operator does on launch day and after

1. Launch in **production robots mode** (`docs/LAUNCH-GATES.md`): `robots.txt` open, no `noindex` header.
2. **Google Search Console** (`docs/SEARCH-CONSOLE.md`): verify the domain by a DNS record, submit `https://worldopenresearchjournal.com/index/sitemap`, then URL Inspection on the home page and the first article and press "Request indexing".
3. **Bing Webmaster Tools:** add the site (it can import from Search Console) and submit the same sitemap. Other engines (and many AI search tools) take their data from Bing.
4. **Google Scholar** has no application form: it crawls scholarly articles it finds. It needs published articles with the `citation_*` tags (done) and a PDF per article (the Download button and `citation_pdf_url` point to it), on a public site. It can take weeks or months after the first articles appear. Check the Scholar inclusion guidelines before expecting anything.
5. **Publish regularly and with complete metadata:** a real abstract and keywords for every article, a PDF galley, authors' affiliations (and ORCID iDs when authors have them). The page metadata is generated from those fields, so complete records are the biggest lever.
6. **ISSN and DOIs** (being applied for): when the ISSN exists, enter it in Settings > Journal. It then appears in the structured data, the Scholar tags and the footer. DOIs come from Crossref (`docs/DOI-SETUP.md`); they are added after launch.
7. **Directories** that help discovery once there is a published issue and an ISSN: DOAJ, OpenAlex, BASE and CORE (see `docs/INDEXING-READINESS.md` and `docs/06-INDEXING-ROADMAP.md`).
8. **Links from elsewhere:** the client's own site, social profiles and the authors' institutional pages linking to the articles do more for ranking than any tag.

## What this cannot do

- It cannot make Google index or rank pages on a schedule. Indexing is Google's decision.
- It cannot give an impact factor or a listing in any index. Do not pay a service that sells one (`docs/INDEXING-READINESS.md`).
- Keywords as a meta tag are read by few search engines today; they are kept because the client asked and because they cost nothing. The links and the structured data are the part that helps.
- The JSON-LD has been checked for valid structure here; it has not been run through Google's Rich Results Test or the Schema.org validator (no access from this environment). Run one real article through both after launch.
