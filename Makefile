SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -ec
THEME := ojs/plugins/themes/worj

.PHONY: setup lint eval check-placeholders sandbox-up sandbox-down sandbox-seed check-citation check-placeholders-url

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

lint:
	shellcheck -x scripts/*.sh autoresearch/eval/run.sh
	python3 -I scripts/check-contrast.py | tail -1
	python3 -I scripts/check-content-claims.py | tail -1
	python3 -I scripts/extract-ojs-default-wording.py --check
	node scripts/test-sandbox-guard.js | tail -1
	scripts/test-import-wrapper.sh | tail -1
	python3 -I scripts/check-config-template.py | tail -1
	python3 -I scripts/make-config-template.py --check
	scripts/test-config-template.sh | tail -1
	scripts/test-config-tools.sh | tail -1
	scripts/test-check-live-config.sh | tail -1
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
