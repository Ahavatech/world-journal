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

## Local OJS in the sandbox (`scripts/sandbox-ojs.sh`, `make sandbox-up`)

The missing bcmath/MariaDB/nginx are installable from apt, so OJS **does** run here once `sandbox-up` has been run. This is throwaway, not a launch test.

- Stack: PHP 8.3.6 + php8.3-bcmath, MariaDB 10.11.14, nginx 1.24.0, php-fpm. Same Ubuntu 24.04 userland as the target VPS.
- Verified: OJS 3.5.0.6 installs headless (`tools/install.php`, answers piped on stdin); the site, login, search and OAI-PMH (`verb=Identify`) endpoints return 200; a journal "World Open Research Journal" (path `worj`) was created through the admin REST API (`POST /index/api/v1/contexts`) with a Playwright session.
- Container constraints the script works around: no systemd (services started by hand), no IPv6 (nginx runs from its own config), nginx workers must be `www-data` to reach the php-fpm socket.
- OJS gotchas found: the installer rewrites `allowed_hosts` to `[""]`, which rejects every request; the script sets it to `["127.0.0.1"]`. With `restful_urls = On`, nginx must route through `/index.php$uri` so PATH_INFO is set. Phase 5's nginx block must handle both.
- Harmless noise: php-fpm cannot resolve `pkp.sfu.ca` (version check, IP geo database, ROR dataset), and there is no sendmail.
- Not verified: theme activation (the `worj` theme folder is still empty), article metadata output (no articles yet), Docker.
- The stack is lost when the container ends; rerun `make sandbox-up` (a few minutes, idempotent).

## QA tooling in the sandbox (Phase 2.8)

- Chromium (Playwright 1.63.0, `/opt/pw-browsers`) runs headless; axe-core 4.14.0 works through `@axe-core/playwright`.
- Lighthouse 13.6.0 runs against the sandbox with `CHROME_PATH` pointing at the Playwright Chromium (about 11 s per page). It installs 119 packages (about 190 MB in `autoresearch/eval/node_modules`, not committed). Accessibility, SEO and best-practices scores were identical across repeat runs.
- **Limitation:** Lighthouse performance is not measured. It needs throttled, median-of-three runs per page (about 6 to 7 minutes for 11 pages, over the 5-minute budget in `autoresearch/EVAL-SPEC.md`) and is the flaky category on a shared CPU. `make eval` reports `perf=SKIPPED` and re-scales the score; no number is estimated.
- `make eval` takes about 110 s (`autoresearch/eval/README.md`).

## Phase 5 environment check (2026-11-10)

Probed read-only before any Phase 5 work.

| Question | Result |
|---|---|
| Docker or an Ubuntu 24.04 container to test provisioning in? | **No.** The docker CLI (29.9.2) is installed, but there is **no daemon and no `/var/run/docker.sock`**. |
| systemd? | Not PID 1 (services are started by hand), so unit files, timers and `systemctl` behaviour cannot be exercised. |
| A chroot? | Yes. The sandbox is root, `unshare --mount --pid --fork --map-root-user` works, `archive.ubuntu.com` is reachable and `apt-get install -s debootstrap ufw certbot python3-certbot-nginx rclone` resolves on noble. A `debootstrap noble` chroot is feasible (no services, no firewall, no sshd). |
| Cloudflare's published IP ranges | `https://www.cloudflare.com/ips-v4` is **blocked** by the sandbox network proxy. The range fetch can only be tested against local fixtures. |
| Tools present | nginx 1.24, php8.3-fpm, MariaDB 10.11 (for `nginx -t`, `php-fpm -t` and config tests); shellcheck; rclone and age are not installed (installable with apt). |

**What this means for every Phase 5 script.** Provisioning is **not tested in a clean container or on a VPS**. It is checked with:

- `shellcheck -x` (part of `make lint`);
- `--check` dry-run mode (prints actions, changes nothing);
- configuration syntax checks (`nginx -t`, `php-fpm8.3 -t`, a throwaway `mariadbd` loading the cnf);
- stub-based unit tests of the scripts' own logic;
- a **debootstrap chroot run with services, firewall and SSH skipped**, run twice to show idempotency;
- a local Nginx in front of the sandbox OJS for redirect, header, deny-rule and 404 checks.

**Every production step is `UNVERIFIED (not run on VPS)`**, and no document may call provisioning "tested". Not testable here at all: ufw/nftables, sshd reload and key-only login, systemd units and timers, certbot, real Cloudflare (SSL mode, rate limits, IP fetch), real DNS and mail, a real rclone remote, 4 GB tuning performance.
