SHELL := /bin/bash
THEME := ojs/plugins/themes/worj

.PHONY: setup lint eval check-placeholders

setup:
	scripts/fetch-ojs.sh
	mkdir -p ojs-core/plugins/themes
	ln -sfn "$(CURDIR)/$(THEME)" ojs-core/plugins/themes/worj

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
