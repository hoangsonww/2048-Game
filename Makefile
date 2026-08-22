SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help setup doctor serve check test test-web test-android test-android-device test-ios screenshots-web clean-web

help: ## Show available project commands
	@awk 'BEGIN {FS = ":.*## "; printf "2048 project commands\n\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## Install locked dependencies and activate Git hooks
	./scripts/bootstrap.sh

doctor: ## Report available platform toolchains
	./scripts/doctor.sh

serve: ## Serve the web app at http://localhost:8080
	npm start

check: ## Run fast repository, syntax, and metadata checks
	./scripts/check-repo.sh

test: ## Run all test suites supported by this host
	./scripts/test-all.sh

test-web: ## Run web unit, metadata, and browser tests
	./scripts/test-web.sh

test-android: ## Run Android unit tests, lint, and APK assembly
	./scripts/test-android.sh

test-android-device: ## Also run Android tests on a connected emulator/device
	./scripts/test-android.sh --device

test-ios: ## Run iOS unit and UI tests on an available simulator
	./scripts/test-ios.sh

screenshots-web: ## Capture desktop/mobile gameplay, dialogs, win/loss, and About
	npm run screenshots:web

clean-web: ## Remove generated web coverage and latest local screenshots
	rm -rf -- "$(CURDIR)/coverage" "$(CURDIR)/output/playwright/latest"
