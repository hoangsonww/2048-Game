SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help



.PHONY: help setup doctor serve check test test-web test-android test-android-device test-ios \
	screenshots-web clean-web android-build android-install android-run android-tasks \
	android-clean android-devices gradle ios-build ios-run ios-boot ios-devices verify-devcontainer \
	version version-sync

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

version: ## Print the version and verify every client agrees with it
	@./scripts/version.sh
	@./scripts/version.sh check

version-sync: ## Rewrite package.json, Gradle, and Xcode from the VERSION file
	./scripts/version.sh sync

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

android-build: ## Build the Android debug APK
	./scripts/android.sh assembleDebug

android-install: ## Build and install the debug APK on a connected device
	./scripts/android.sh installDebug

android-run: ## Install the debug APK and launch it on a connected device
	./scripts/android.sh run

android-devices: ## List connected Android devices and emulators
	./scripts/android.sh devices

android-tasks: ## List every available Gradle task for the Android client
	./scripts/android.sh tasks

android-clean: ## Remove Android build output
	./scripts/android.sh clean

gradle: ## Run an arbitrary Gradle task, e.g. make gradle ARGS="assembleRelease"
	@test -n "$(ARGS)" || { printf 'Usage: make gradle ARGS="<gradle-task>"\n' >&2; exit 2; }
	./scripts/android.sh $(ARGS)

ios-build: ## Build the iOS app for an available simulator
	./scripts/ios.sh build

ios-run: ## Build, install, and launch the iOS app on a simulator
	./scripts/ios.sh run

ios-boot: ## Boot an available iPhone simulator and open Simulator.app
	./scripts/ios.sh boot

ios-devices: ## List available iPhone simulators
	./scripts/ios.sh devices

verify-devcontainer: ## Build the dev container image and verify its toolchain
	./scripts/verify-devcontainer.sh

screenshots-web: ## Capture desktop/mobile gameplay, dialogs, win/loss, and About
	npm run screenshots:web

clean-web: ## Remove generated web coverage and latest local screenshots
	rm -rf -- "$(CURDIR)/coverage" "$(CURDIR)/output/playwright/latest"
