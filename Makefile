SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -ec
THEME := ojs/plugins/themes/worj

# Needs php-fpm8.3, mariadbd and nginx in this sandbox; not part of `make lint` (CI has no FPM or MariaDB).
.PHONY: infra-test infra-test-nginx infra-test-backup infra-test-reset infra-test-chroot infra-test-day0 infra-test-htaccess infra-test-install infra-test-client infra-test-email infra-test-launch
infra-test:
	scripts/test-infra-config.sh
	scripts/test-provision-preflight.sh | tail -1
	scripts/test-provision-ssh-firewall.sh | tail -1

# Needs root, the sandbox up, and age + rclone (apt-get install -y age rclone).
infra-test-backup:
	scripts/test-backup-restore.sh

# Needs root and the sandbox up; restores the sandbox admin row afterwards.
infra-test-reset:
	scripts/test-reset-admin-password.sh

# Needs root, debootstrap, apt access and about 6 GB; 15 to 25 minutes. Provisions a clean Ubuntu 24.04 chroot twice.
infra-test-chroot:
	scripts/test-provision-chroot.sh

# Needs the sandbox (make sandbox-up sandbox-seed), root, and `cd autoresearch/eval && npm ci`. Takes a few minutes.
infra-test-nginx:
	scripts/test-nginx-harness.sh

# The Day-0 kit and its probe against a stand-in Apache (apt-get install apache2); not LiteSpeed, see scripts/test-day0-kit.sh.
infra-test-day0:
	scripts/test-day0-kit.sh

# The shared-hosting .htaccess on a stand-in Apache in front of the sandbox (make sandbox-up sandbox-seed), root, apache2.
# Proves Apache semantics, not LiteSpeed's: see docs/DEPLOY-SHARED.md. Binds 127.0.0.1:80 and :443 for a minute.
infra-test-htaccess:
	scripts/test-htaccess-harness.sh

# Release -> deploy -> install-shared.sh with a stand-in ssh, a scratch MariaDB database and the real OJS CLI installer.
# Needs root (mariadb socket), rsync and ojs-core (make setup). Proves the script, not the host.
infra-test-install:
	scripts/test-install-shared.sh

# The client's own text (ojs/client-content) loaded into the sandbox journal and read back over HTTP, then the sandbox is restored.
# Needs the sandbox (make sandbox-up sandbox-seed) and Playwright. The text-only checks run in `make lint`.
infra-test-client:
	scripts/test-client-content-sandbox.sh

# What OJS really sends (a password-reset email read back from a fake SMTP server): From is the mailbox, the contact address only in
# Reply-To. Needs the sandbox (make sandbox-up sandbox-seed).
infra-test-email:
	scripts/test-email-sender-sandbox.sh

# Launch preparation (delete sample content, hide pages with no client text, confirm or hold the client's pages) and the theme option that
# leaves the ISSN line out, against the sandbox journal. The sandbox is snapshotted and restored. Needs the sandbox and Playwright.
infra-test-launch:
	scripts/test-theme-issn-option.sh
	scripts/test-launch-prep-sandbox.sh

.PHONY: setup lint eval check-placeholders sandbox-up sandbox-down sandbox-seed check-citation check-pdf check-discovery check-placeholders-url

setup:
	scripts/fetch-ojs.sh
	mkdir -p ojs-core/plugins/themes
	ln -sfn "$(CURDIR)/$(THEME)" ojs-core/plugins/themes/worj
	# after an OJS pin change this fails until the config template is regenerated and reviewed
	python3 -I scripts/make-config-template.py --check

sandbox-up: setup
	scripts/sandbox-ojs.sh up

sandbox-down:
	scripts/sandbox-ojs.sh down

sandbox-seed:
	node scripts/sandbox-seed.js
	scripts/sandbox-import-sample.sh

# Citation tags on the three sample articles (needs the sandbox running).
# --placeholder-issn: the journal has no real ISSN yet.
check-citation:
	@for n in 1 2 3; do \
	  scripts/check-citation-meta.sh --placeholder-issn "$${SANDBOX_URL:-http://127.0.0.1:8082}/worj/article/view/$$n" | tail -1; \
	done

# Crawler access to the PDF each sample article names in citation_pdf_url (needs the sandbox running).
check-pdf:
	@for n in 1 2 3; do \
	  scripts/check-pdf.sh "$${SANDBOX_URL:-http://127.0.0.1:8082}/worj/article/view/$$n" | tail -1 || exit 1; \
	done

# robots.txt, sitemap, OAI-PMH, noindex and the canonical INFO line, run against the sandbox BEHIND the production Nginx
# render of the Phase 5 harness (it serves our repo robots.txt, with the Sitemap line), so a pass means the real thing.
# Needs root and the sandbox running (make sandbox-up sandbox-seed). Pointing check-discovery.sh straight at the sandbox
# would fail on OJS's own robots.txt (no Sitemap line): that case is a fixture test (scripts/test-check-discovery.sh).
check-discovery:
	HARNESS_DISCOVERY_ONLY=1 scripts/test-nginx-harness.sh

lint:
	shellcheck -x scripts/*.sh autoresearch/eval/run.sh
	python3 -I scripts/check-contrast.py | tail -1
	python3 -I scripts/check-content-claims.py | tail -1
	python3 -I scripts/extract-ojs-default-wording.py --check
	node scripts/test-sandbox-guard.js | tail -1
	node scripts/test-target.js | tail -1
	scripts/test-import-wrapper.sh | tail -1
	python3 -I scripts/check-config-template.py | tail -1
	python3 -I scripts/make-config-template.py --check
	scripts/test-config-template.sh | tail -1
	scripts/test-config-tools.sh | tail -1
	scripts/test-check-live-config.sh | tail -1
	scripts/test-cloudflare-ips.sh | tail -1
	scripts/test-check-pdf.sh | tail -1
	scripts/test-check-discovery.sh | tail -1
	scripts/test-check-citation-meta.sh | tail -1
	scripts/test-release.sh | tail -1
	scripts/test-run-scheduler.sh | tail -1
	python3 -I scripts/check-client-content.py | tail -1
	scripts/test-client-content.sh | tail -1
	@if [ -n "$$(find ojs scripts -name '*.php' -print -quit)" ]; then \
	  find ojs scripts -name '*.php' -print0 | xargs -0 -n1 php -l >/dev/null && echo "php -l ok"; \
	else echo "no PHP files yet"; fi
	npx --no-install markdownlint-cli2 "*.md" "docs/**/*.md" "autoresearch/*.md"
	@if [ -n "$$(find ojs -name '*.css' -print -quit)" ]; then npx --no-install stylelint "ojs/**/*.css"; \
	else echo "no CSS files yet"; fi

# Needs the sandbox (make sandbox-up sandbox-seed) and `cd autoresearch/eval && npm ci`.
eval:
	autoresearch/eval/run.sh

# Repository scan: every remaining placeholder with file:line (exit 1 while any remain; CI keeps it warn-only until Phase 8).
check-placeholders:
	scripts/check-placeholders.sh

# Rendered-site scan (the launch gate): needs the sandbox, or pass the journal URL.
check-placeholders-url:
	scripts/check-placeholders.sh --url "$${SANDBOX_URL:-http://127.0.0.1:8082}/worj"
