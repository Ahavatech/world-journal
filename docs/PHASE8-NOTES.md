# Phase 8 notes

Results and decisions for Phase 8 (QA, launch gates, handover). Everything here was run in the local sandbox on 2026-11-10 against `main` at `41b8b4d`, **nothing on a VPS, a real domain, a real mail provider or a real Cloudflare**. Labels: `VERIFIED-SANDBOX 2026-11-10`, `UNVERIFIED (not run on VPS)`.

## 8.1 Suite results (exit codes recorded directly)

Method: each suite was run as `make TARGET >file 2>&1; echo $?`, with no pipe that could hide a failure. The exit code is the one `make` returned. Counts are PASS and FAIL lines in the suite's own output.

| Suite | Command | Exit | Result | Time |
|---|---|---|---|---|
| Lint (shellcheck, contrast, claims, config template, all `test-*.sh` unit suites, php -l, markdownlint, stylelint) | `make lint` | **0** | markdownlint: 25 files, 0 errors | 49 s |
| Infra: config, provisioning preflight, SSH and firewall stubs | `make infra-test` | **0** | 46 PASS, 0 FAIL | 15 s |
| Nginx harness (rendered config in front of the sandbox, browser checks) | `make infra-test-nginx` | **0** | 128 PASS, 0 FAIL | 94 s |
| Backup and restore round trip | `make infra-test-backup` | **0** | 75 PASS, 0 FAIL | 10 s |
| Administrator password reset | `make infra-test-reset` | **0** | 16 PASS, 0 FAIL | 6 s |
| Provisioning in an Ubuntu 24.04 chroot, run twice | `make infra-test-chroot` | **0** | 70 PASS, 0 FAIL; second run `changed: 0`; `--check` `changed: 0`; `check-live-config.py` 22 checks, 0 failed | 177 s |
| QA scorer | `make eval` | **0** | `GATES: PASS`, `SCORE: 98.8` (a11y 100.0, seo 96.0, bp 100.0, resp 100.0, simplicity 100.0, perf SKIPPED) | 144 s |
| Citation tags on the 3 sample articles | `make check-citation` | **0** | 3 of 3 pass (with `--placeholder-issn`) | 0 s |
| PDF readable by a crawler | `make check-pdf` | **0** | 3 of 3 `RESULT: PASS` | 1 s |
| Robots, sitemap, OAI behind the production Nginx render | `make check-discovery` | **0** | `RESULT: PASS` | 4 s |
| Repository placeholder scan | `make check-placeholders` | **2** (make's code for the script's exit 1) | **expected non-zero**: 147 lines in 28 files, 9 theme fallback lines excused by the allowlist | 0 s |
| Rendered-site placeholder scan | `make check-placeholders-url` | **2** | **expected non-zero**: 39 pages and 3 PDFs scanned, 400 findings on 42 pages, 0 failures (sample content is on the site) | 2 s |

The two non-zero results are the launch gate doing its job: they must reach exit 0 only at launch (`docs/LAUNCH-GATES.md`). Every other suite passed; **no known failing suite remains**, so nothing was fixed in 8.1 and no code changed.

The chroot run also re-ran end to end the Phase 6 assertion that had been fixed but not re-run (the OAI `repository_id` is the main host, written quoted by the installer): it passes.

### What the run showed (not repository defects)

- **Lighthouse reports a missing meta description on all 13 pages.** The page description comes from the journal's search description (Settings > Distribution > Search Indexing > Description), which is client content that is still empty. It is why `seo` is 96.0 and not 100. It is on the client's inputs list.
- **The placeholder counts are the client-content backlog**, not bugs: `ojs/content`, `ojs/fixtures` and the markers the pages carry until real text exists.
- `perf` is always `SKIPPED` by design (Lighthouse performance needs throttled median-of-three runs).

## Could not run here (each is `UNVERIFIED (not run on VPS)` or not possible in this sandbox)

| Not run | Why |
|---|---|
| `ufw` rules, `sshd` reload and key-only login, the dead-man timers | no firewall or sshd in the sandbox; only stub-tested (`scripts/test-provision-ssh-firewall.sh`) |
| systemd services, timers and `cron` actually executing the scheduler line | no systemd as PID 1; the cron command itself ran as `www-data` in the chroot, cron executing it did not |
| Certificate issuance and renewal (Cloudflare Origin CA files, certbot HTTP-01) | no real domain or CA |
| The real Cloudflare IP-range fetch | `www.cloudflare.com` is blocked by the sandbox proxy; tested only against local fixtures |
| Cloudflare itself: SSL mode, rate limits, Bot Fight Mode, cache purge, crawler checks | no Cloudflare account or zone |
| A real mail provider: SMTP delivery, SPF, DKIM, DMARC, the real validation email | no provider; mail never left the sandbox |
| IPv6 and AAAA records | no IPv6 in the sandbox |
| The throwaway-VPS rehearsal and the console-rescue rehearsal | no VPS (see decision D-VPS in `docs/LAUNCH-BLOCKERS.md`) |
| The real-domain checks: canonical tag (decision D25), Search Console, Googlebot, `check-discovery.sh --launch`, `check-live-config.py --launch` on the production config | no real domain; the sandbox uses placeholder hosts and sample content, so these **must** fail there |
| `make eval` in CI | the scorer needs the running sandbox; CI runs lint only |
| Lighthouse performance | skipped by design (above) |
| A screen-reader pass | not done at all; see `docs/HANDOVER.md` |
| The editorial workflow end to end, run by a person | `docs/QA-SCRIPT.md` is a manual script; every step reads NOT RUN |
