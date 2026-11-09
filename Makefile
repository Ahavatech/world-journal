SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -ec
THEME := ojs/plugins/themes/worj

.PHONY: setup lint eval check-placeholders sandbox-up sandbox-down sandbox-seed check-citation

setup:
	scripts/fetch-ojs.sh
	mkdir -p ojs-core/plugins/themes
	ln -sfn "$(CURDIR)/$(THEME)" ojs-core/plugins/themes/worj

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
	shellcheck -x scripts/*.sh
	@if [ -n "$$(find ojs -name '*.php' -print -quit)" ]; then \
	  find ojs -name '*.php' -print0 | xargs -0 -n1 php -l >/dev/null && echo "php -l ok"; \
	else echo "no PHP files yet"; fi
	npx --no-install markdownlint-cli2 "*.md" "docs/**/*.md" "autoresearch/*.md"
	@if [ -n "$$(find ojs -name '*.css' -print -quit)" ]; then npx --no-install stylelint "ojs/**/*.css"; \
	else echo "no CSS files yet"; fi

eval:
	@echo "make eval: not implemented yet (locked scorer is added later)" >&2; exit 1

check-placeholders:
	@echo "make check-placeholders: not implemented yet (Phase 3.5)" >&2; exit 1
