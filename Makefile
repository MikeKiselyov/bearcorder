# One entry point for the everyday tasks. Each target runs a script in scripts/; read the script
# for the details. `make` alone lists the targets.

.DEFAULT_GOAL := help
.PHONY: help build app test test-all e2e features perf lint media release-check no-automation clean

help: ## List the targets
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{ printf "  %-14s %s\n", $$1, $$2 }'

build: ## Compile (debug), no app bundle
	swift build

app: ## Build the signed .app in build/
	scripts/build-app.sh

test: ## Unit tests, self-test, lint and the release check (~2 min, no permissions)
	scripts/test/all.sh --quick

test-all: ## Every suite, the real app included (~10 min, moves the mouse)
	scripts/test/all.sh

e2e: ## The real app: buffer, saving, recording
	scripts/test/e2e.sh

features: ## The real app with a browser: every feature and control
	scripts/test/e2e-features.sh

perf: ## CPU and memory while idle and recording
	scripts/test/perf.sh

lint: ## shellcheck on every script, actionlint on the CI workflows and the control list check
	shellcheck -x scripts/*.sh scripts/*/*.sh scripts/*/*/*.sh
	actionlint
	python3 -I scripts/check/control-coverage.py

media: ## Regenerate the README pictures and GIFs (needs ffmpeg)
	scripts/dev/readme-media.sh

release-check: ## What CI checks on a pull request: a new release in the notes
	scripts/check/release.sh origin/main

no-automation: ## A release build has no automation hook, self-test or media tools
	scripts/check/no-automation.sh

clean: ## Remove build output
	rm -rf .build build
