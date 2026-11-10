# Search Console, sitemaps and what "indexed" means

Every step below is a human step on the real domain and is `UNVERIFIED (not run on VPS)`. Nothing here has been done against a live site.

## Read this first: Google Scholar

**Nothing in this repository can make Google Scholar index a paper.** Google Scholar has **no submission form and no console**: there is no Search Console equivalent for it. It finds articles by crawling on its own schedule, which can take **weeks or months**, and it needs **actual published articles** with correct metadata. What we can do is make the metadata correct (`scripts/check-citation-meta.sh`, `make check-citation`) and the PDFs readable (`scripts/check-pdf.sh`). Read Google's own inclusion guidelines for webmasters: <https://scholar.google.com/intl/en/scholar/inclusion.html>. If Scholar has not indexed the first articles after a few months, the guidelines are the place to start, not a resubmission.

Ordinary Google Search is different: Search Console exists for it, and the steps below are for that.

## 1. Before you start

- The site is live on its real domain over HTTPS and Cloudflare is in front (`docs/DEPLOY.md`).
- `scripts/check-discovery.sh --robots-mode production https://HOST` passes. It fails if the site is still disallowed (`ROBOTS_MODE=staging`) or sends `noindex`.
- At least one issue with a real published article exists. The sitemap lists issues, articles and galleys, so an empty journal gives Google nothing to find.

## 2. Verify ownership: a Domain property through a DNS TXT record

Recommend a **Domain property**: one property that covers `http`, `https`, `www` and every subdomain, so the apex/`www` redirect and any later host change do not create separate properties.

1. In Search Console choose **Add property**, then **Domain**, and enter the main domain (for example `example.org`, not a URL).
2. Google shows a TXT record. Copy it exactly.
3. In Cloudflare: **DNS > Records > Add record**, type **TXT**, name `@`, content the string Google gave, TTL Auto. A TXT record cannot be proxied, so there is no proxy setting to choose.
4. Back in Search Console press **Verify**. If it says the record is not found, wait a few minutes and try again; do not add a second record.
5. Keep the TXT record. Removing it un-verifies the property.

## 3. Submit the sitemap

Submit the sitemap index: `https://HOST/index/sitemap` (the file `robots.txt` also names it). The index lists the journal's own sitemap, `https://HOST/JOURNAL/sitemap`.

What the sitemap contains and what it omits (read from the 3.5.0-6 source, `pages/sitemap/SitemapHandler.php` and `lib/pkp/pages/sitemap/PKPSitemapHandler.php`):

- **Lists:** the journal home page; `user/register` (if registration is open); `login`; the announcements index and each announcement (if announcements are on); `about`, `about/submissions` and `about/contact`; each navigation-menu page (our static pages); `search`; `issue/current` and `issue/archive`; **each published issue**; and for each issue, **each published article's abstract page and each galley's view page** (`article/view/ID` and `article/view/ID/GALLEY`).
- **Omits:** the PDF **download** URLs (`article/download/...`); unpublished and declined items; and, because articles are only found through their issue, **a published article that is not assigned to any issue**. The sitemap also lists `login` and `user/register`, which are of no use to a searcher; that is harmless.

A "Couldn't fetch" status in the Sitemaps report means a redirect, a block or a non-200 answer: run `scripts/check-discovery.sh` and read the failing line.

## 4. Check that Cloudflare does not stand in the way of Googlebot

A site can pass every check from your own laptop and still return a challenge page to Googlebot. Before relying on indexing, confirm Cloudflare lets crawlers through on **article, galley, sitemap and OAI paths**:

- **Bot Fight Mode** (Security > Bots): may challenge crawlers. Leave it off, or confirm with the live test below that it does not affect them.
- **WAF custom rules and managed rules**: look for any rule that challenges or blocks unknown user agents.
- **Rate limiting** set in Phase 5 (`/login`, `/user/register`, `/index/` forms): must not match article, galley, sitemap or OAI paths.

**The confirming step:** in Search Console, **URL Inspection**, paste a real article URL and press **Test live URL**. It must report that the URL is available to Google with HTTP 200 and show the rendered page. A challenge page, 403 or 5xx here means a Cloudflare rule is blocking Googlebot; fix that first.

## 5. URL Inspection of a real article and a galley

1. Inspect the article URL `https://HOST/JOURNAL/article/view/ID`. Note **Page indexing** and **User-declared canonical** versus **Google-selected canonical**.
2. Inspect one galley URL (`.../article/view/ID/GALLEY`) the same way.
3. Duplicate-URL checks, per `docs/ADMIN-SETUP-CHECKLIST.md`: the article and its galley are different pages with different content; `http://` redirects to `https://`; the `index.php/...` form redirects to the clean form. If Google selects a different canonical than the one you expect, write down both URLs and bring them back as a decision (see "canonical" in `docs/PHASE6-NOTES.md`); do not add a canonical hook before that decision.

## 6. What "indexed" looks like, and what the other statuses mean

- **Indexed** ("URL is on Google"): the page can appear in results. This can take days to weeks after the first crawl.
- **Discovered, currently not indexed:** Google knows the URL (from the sitemap) but has not crawled it yet. On a new site with no links to it this is normal and can last weeks. **What to do: nothing, and check again later.** Make sure the page is linked from the home page or the issue page, so Google has a reason to visit.
- **Crawled, currently not indexed:** Google fetched it and chose not to index it for now. Improve the page only if it is thin or duplicated; otherwise wait.
- **Do not:** press **Request indexing** repeatedly (it does not speed anything up and the quota is small); pay anyone for "indexing services"; or submit the same sitemap again and again. Request indexing once for the home page and, if you like, once for the first article, then leave it.

## 7. After launch

- Re-run `scripts/check-discovery.sh --robots-mode production --launch https://HOST` after every change to settings that touch URLs, mail contacts or the OAI identifier.
- The OAI-PMH endpoint (`https://HOST/JOURNAL/oai`) is what indexing services harvest. Its public contact address and its repository identifier are client decisions (`docs/ADMIN-SETUP-CHECKLIST.md`); an identifier must **never** change after it has been harvested.
