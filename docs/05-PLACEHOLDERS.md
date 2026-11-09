# 05. Placeholders and integrity rules

## Format
Anything unknown is written as `[PLACEHOLDER: what is needed]`. It must be visible in the rendered page (a coloured banner or inline badge) so nobody can miss it, and greppable by `scripts/check-placeholders.sh`.

## Never fabricate (hard stop)
- ISSN or eISSN, DOI or DOI prefix, impact factor, CiteScore or any metric
- Indexing or database claims and badges (Scopus, Web of Science, DOAJ, Google Scholar, "ISI", "Global Impact Factor" or similar)
- Editors, board members, reviewers, affiliations, photos
- Publication dates, volume or issue numbers for real content
- Policies presented as the client's actual policy

## Why this matters
The reference page the client shared (pspac.info) displays Scopus badges and a long indexing list, and its scope text mixes unrelated fields. Treat it as a layout reference only. A new journal that displays indexing or metric claims it has not earned will be treated as deceptive by indexers and readers, and can be refused by DOAJ, Crossref sponsors and Clarivate. Show an Indexing block only after a real indexing decision, and link to the indexer's own record for it.

## Sample content
Sample articles must be obviously fake ("Sample Article 1", "Placeholder Author"), carry a diagonal watermark in the PDF, and be listed in `ojs/fixtures/manifest.json`. Launch gate: all sample records are deleted from OJS and the fixtures never ship to production.

## Logo and imagery
Use only the provided logo. For other images use neutral generated or CSS shapes. No stock photos of real people, no copied images from reference sites.
