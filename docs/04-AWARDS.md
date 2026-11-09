# 04. Research Awards

The client wants research awards on the journal site. **This was not in the signed scope**, so the default below is the lightweight option. The heavier option needs a written change request and separate estimate.

## Option A (default, in-scope): static pages + announcements
Build with OJS's built-in tools and theme only:
- A top-level **Research Awards** page (static page) with: purpose, award categories, eligibility, selection criteria, judging process, timeline, how to nominate, past winners, contact.
- Sub-pages: `Awards/Categories`, `Awards/Guidelines`, `Awards/Winners` (empty until real).
- Announcements used for call for nominations, shortlist and winners.
- A homepage call-out card linking to the page, driven by a theme option (on/off).
- Nominations by email or a contact form to `[PLACEHOLDER: awards email]`. No data stored in OJS.

Placeholder categories (clearly marked, client to replace): Best Research Article of the Year, Best Early-Career Researcher Paper, Outstanding Reviewer, Outstanding Contribution to Open Research.

## Option B (needs approval and quote): custom awards plugin
Only build if the human states the change request was approved. Scope would be: nomination form with file upload, award cycle management, judge scoring, public winners list, email notifications, export. This is significant custom OJS plugin development. If approved, write a separate plan in `docs/awards-plugin-plan.md` before coding.

## Integrity rules (copy into the public Awards page as placeholder prompts)
- Criteria and judging process are published before nominations open.
- Judges are independent of the nominees and declare conflicts of interest.
- Awards are never sold or tied to fees, APCs or sponsorship.
- Winners and the basis of selection are published.
- Do not name real sponsors, prizes, amounts, judges or winners until the client supplies them.
