# Phase 5 notes (resume point)

A cleared session resumes from this file, `docs/PHASE4-NOTES.md`, `docs/03-TASKS.md` (Phase 5), `docs/ENV-REPORT.md` (Phase 5 environment check) and the git history. Branch: `claude/phase5-infra` (off `origin/main`; never restart an old branch name; no force-push). The approved plan is summarised here because plan files do not survive a clear.

## Rules (from the approved plan, 2026-11-10)

- **Policy:** provisioning is checked with shellcheck, `--check`, config syntax checks, stub tests, a debootstrap chroot run (no services, firewall or SSH, run twice: the second must report `changed: 0`) and a local Nginx in front of the sandbox OJS. **Every production step is `UNVERIFIED (not run on VPS)`.** Never claim a tested provisioning. No Docker daemon here; the Cloudflare IP list URL is blocked in the sandbox (fixtures only).
- Sessions: commits 1 to 8 in session 1, commits 9 to 12 in session 2. This file is updated after commits 3 and 8.
- **Secrets:** generated with `openssl rand` or Python `secrets`, never in argv, `set -x`, history or logs; values go to tools on stdin; the DB password only in `config.inc.php` and a root-only 600 defaults file; the installer's initial admin password comes from the operator's root-only env file or a one-time prompt; the installer answers file is deleted by trap on exit (including failure) and a test proves it is gone and the password appears nowhere.
- **Backups are always encrypted off the server:** `age` public-key encryption (only the public key on the server; the client holds the private key); mode 600 is acceptable for the LOCAL copy only; `DEPLOY.md` says decryption happens off the server and the restore rehearsal is done by the operator with the private key; remote bucket versioning or object lock is strongly recommended; `backup.sh` checks the dump is non-empty and a plausible size and raises a failure alert; `restore.sh` refuses when the scratch DB name or connection target equals the production DB in the live config (tested with a deliberate collision).
- **Cloudflare IP ranges** fetched at provision time; on failure keep the old file and exit non-zero; the provision stage fails with a clear message on first run if no ranges exist yet (never real-IP handling unset).
- **Admin recovery:** a database-level password reset written from the 3.5.0-6 source (exact hashing function and table) and tested on the sandbox; state who holds the break-glass administrator credential.
- **Extra tests:** a `.php` file uploaded into `public/` is not executed through Nginx; `files_dir` content is unreachable by URL while a public PDF galley still downloads through OJS; Nginx serves no `config.inc.php`, `.git`, `.env` or backup file from any path.
- **CSP:** report-only gives no protection; `DEPLOY.md` says so; not counted as hardening until enforced after a clean crawl of public and admin pages.
- **Decisions stay human (`[CLIENT DECISION]`, default shown):** main host; certificate method (Cloudflare Origin CA vs certbot DNS-01, with the paused-proxy caveat); firewall (open during setup, then Cloudflare ranges only, noting it blocks direct-IP testing); HSTS (short max-age, staged, no preload at launch); swap and time zone (never assume a zone); Cloudflare Access on admin (optional, must not block `/api/`); bucket versioning or object lock.
- **Back to the owner before the Phase 5 PR:** curl matrix output (404 page, JSON 404 on `/api/`, POST not redirected); debootstrap run twice with `--check` before and after tree snapshots; the secret-leak sampler results; the backup and restore round trip with the collision refusal; the final `UNVERIFIED (not run on VPS)` list.

## Commit plan and progress

| # | Commit | State |
|---|---|---|
| 1 | `docs(env)` environment check and policy | done |
| 2 | `render-template.py`, `set-ojs-config.py` + tests (27 cases) | done |
| 3 | `check-live-config.py` + negative fixtures (20 cases) | done |
| 4 | PHP, FPM, MariaDB templates + syntax checks | pending |
| 5 | Nginx templates, snippets, static 404 page (CSP report-only) | pending |
| 6 | local Nginx harness (curl matrix, axe on the 404, CSP capture, upload and files_dir tests) | pending |
| 7 | `update-cloudflare-ips.sh` + fixtures | pending |
| 8 | `backup.sh`, `restore.sh`, cron + tests | pending |
| 9 to 12 | provision script, SSH and firewall with dead-man, chroot harness, `DEPLOY.md` (session 2) | pending |

## Findings so far

- `scripts/check-live-config.py` run on the real sandbox install (CLI installer output) fails 9 of 18 checks: salt (the public default), `api_key_secret` (empty), host not listed in `allowed_hosts`, `time_zone` blank, `base_url` not https, `force_ssl`, `force_login_ssl`, `show_stacktrace` On and file mode 664. This is the sandbox, not production, but it shows the check sees exactly what the installer leaves.
- The config template header no longer contains a literal `@@TOKEN@@`, so the renderer can treat any leftover token as an error.
- `render-template.py` and `set-ojs-config.py` take values on stdin only; passing a value on the command line is refused (exit 2).
