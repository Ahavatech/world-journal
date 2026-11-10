# Handover guide (STUB)

> **Stub.** Task 8.4 writes the full guide (admin guide, how to publish an issue, who to contact, 14-day support terms). Only items that must not be forgotten are listed here so far.

## For the journal administrator

- **Theme changes can take up to an hour to appear to visitors.** Theme files are cached for one hour by the server, and by Cloudflare's copy; whoever deploys a theme change purges the Cloudflare cache, but a visitor's browser may still show the old version for up to an hour. Do not re-deploy in a panic if a change is not visible at once.
- **The developer's own administrator account is removed or its ownership is transferred** to a named person at the client (see "Handover" in `docs/DEPLOY.md`).
- **Scheduled tasks run from the server's cron, not from website visits.** If review reminders or statistics emails ever stop, ask the operator to run the scheduler check in `docs/DEPLOY.md` ("Scheduler check").
