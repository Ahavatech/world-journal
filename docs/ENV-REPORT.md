# ENV-REPORT: sandbox probe (Phase 0.1)

Probed 2026-11-09 in the Claude Code cloud sandbox (Linux, Ubuntu 24.04 userland). The OJS pin is recorded in the Phase 1 update at the end of this file.

## Tools

| Tool | Status | Version / note |
|---|---|---|
| php | present | 8.3.6 CLI. **Meets 8.2+: YES.** Exact requirement for the chosen OJS 3.5.x patch is confirmed against the PKP docs in Phase 1. |
| php extensions | present | curl, dom, gd, intl, mbstring, mysqli, pdo_mysql, xml, xsl, zip, sodium, fileinfo, exif, opcache |
| composer | present | works (installed `psr/log` in a scratch dir) |
| node / npm | present | node 22.23.4, npm 10.9.9 |
| mariadb / mysql | **absent** | no server or client; apt not tested for it |
| docker | present | 29.9.2 client (daemon not tested) |
| chromium | present | Playwright build in `/opt/pw-browsers/chromium-1243` (not on PATH) |
| nginx | **absent** | |
| shellcheck | **absent** | installable via apt (0.9.0) |
| stylelint, markdownlint | **absent** | installable via npm |
| pdftotext | present | poppler 24.02.0 |
| rclone | **absent** | |
| git, make, python3 | present | 2.43.0, 4.3, 3.13.18 (Pillow 12.3.0) |
| ImageMagick | present | 6.9.12 |

## Network and package installs

| Check | Result |
|---|---|
| `npm install` (registry.npmjs.org) | **works** |
| `composer install` (packagist / GitHub) | **works** |
| `apt-get update` + `apt-get install --dry-run shellcheck` | **works** (as root) |
| github.com / api.github.com | reachable (api 200; the root page returned 400 via proxy) |
| pkp.sfu.ca | **BLOCKED**: proxy returned 403 on CONNECT |
| docs.pkp.sfu.ca | **BLOCKED**: proxy returned 403 on CONNECT |
| OJS release archive from the PKP site | **BLOCKED** (same host, `pkp.sfu.ca`) |

## Consequences

1. **OJS cannot be fetched from the PKP site in this sandbox.** Phase 1 (`scripts/fetch-ojs.sh`) can be written and linted here, but not run end to end.
2. **PKP docs cannot be read here**, so hook and template checks (CLAUDE.md rule 4) can't be verified from this environment. Anything unverified will be flagged, not guessed.
3. **No MariaDB or Nginx**, so OJS can't be run even if the archive were present unless installed via apt. **Develop the theme against static HTML fixtures** in `ojs/fixtures/html/`, and leave the live-OJS check to a staging VPS.
4. Linters (shellcheck, stylelint, markdownlint) are installable via apt/npm, so `make lint` is feasible.

## What the human must do

Pick one:
- **A (preferred):** allow `pkp.sfu.ca` and `docs.pkp.sfu.ca` in the environment's network allowlist (Claude Code environment settings), then start a new session.
- **B:** download the pinned OJS 3.5.x tarball and its checksum from the PKP site yourself and give me the checksum, as Phase 1.1 already requires. The archive itself must still reach `ojs-core/` by a route the sandbox allows, or be fetched on the staging VPS.

Either way, give me the exact OJS 3.5.x patch version to pin.

## Phase 1 update (2026-11-09)

- The environment now allows `pkp.sfu.ca` and `docs.pkp.sfu.ca`; both return 200. The PKP block described above is resolved.
- **Pinned OJS: 3.5.0-6**, from the PKP download page (`scripts/ojs-version.env`). Archive size 120,980,607 bytes.
- **Checksum:** PKP publishes none (`.sha256`, `.md5` and `.asc` next to the tarball return 404; no checksum on the download, archive or releases pages). The pinned SHA-256 was computed on first download. It detects corruption or later tampering, not that the original is authentic. Replace it if the client obtains a checksum from a trusted source.
- **PHP:** the 3.5.0 release notebook and the pinned release's `README.md` require PHP 8.2 or later. The sandbox's 8.3.6 meets that.
- **PHP extensions:** the release README lists `ext-bcmath` as required. The sandbox PHP does **not** have bcmath, so OJS cannot run here even with a database. The VPS provisioning script (Phase 5) must install `php8.x-bcmath`.
- **Database:** the release README states MySQL 5.7.22+, MariaDB 4.1+ or PostgreSQL 9.5+. The README gives no more specific MariaDB version, so the server version is chosen in Phase 5.
- `make setup` and `make lint` ran clean in the sandbox (see the Phase 1 PR for output).
