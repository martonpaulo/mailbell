# Task entry points: skill-deck's fourteen shared targets plus Mailbell's own.
# `make validate` runs on every change in CI; `make check CONFIGURATION=release` is the
# path-filtered build job. No target publishes anything: only the tag workflow does.

.DEFAULT_GOAL := help

.PHONY: help build test lint format validate check app dmg icon screenshots keys appcast clean \
	install uninstall run refresh-icons setup-release-signing clean-test-defaults

# Any compiler warning fails `build` and `test`, locally and in CI. Package.swift turns
# warnings into errors, but some Swift 6 diagnostics stay warnings anyway, so
# scripts/fail-on-warnings.sh also fails on any `warning:` line that points into a project file.
CONFIGURATION ?= debug
SWIFT_SOURCES ?= Sources Tests

# FORCE=1 lets `app` and `dmg` replace an existing bundle, archive or disk image.
FORCE ?=
FORCE_FLAG := $(if $(filter 1,$(FORCE)),--force,)

# `appcast` inputs, for a rehearsal or a recovery; the release workflow calls the script itself.
VERSION ?=
BUILD_NUMBER ?=
ARCHIVE ?=
SIGNATURE ?=
# Sparkle's update window shows the release notes the site publishes.
HOST := $(shell tr -d '[:space:]' < site/CNAME)

# Local builds sign with a stable identity when the untracked .env names one, so the Keychain
# tokens and the notification and login-item permissions survive a rebuild: macOS keys both on
# the code signature, and an ad-hoc signature changes with every build (#82). Only this one
# variable is read from .env; the shell wins when it sets it. Without it, builds stay ad-hoc.
DEVELOPER_ID_IDENTITY ?= $(shell sed -n 's/^DEVELOPER_ID_IDENTITY=//p' .env 2>/dev/null | tr -d '"')
export DEVELOPER_ID_IDENTITY

APP_BUNDLE := /Applications/Mailbell.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# -- Canonical targets ---------------------------------------------------------

help: ## List the targets
	@awk 'BEGIN {FS = ":.*## "} \
		/^# -- / {n = $$0; gsub(/(^# -- | -+$$)/, "", n); printf "\n%s\n", n} \
		/^[a-z-]+:.*## / {printf "  make %-22s %s\n", $$1, $$2} \
		END {printf "\n"}' $(MAKEFILE_LIST)

build: ## Build (CONFIGURATION=debug|release); fails on any warning in a project file
	@scripts/fail-on-warnings.sh -- swift build -c $(CONFIGURATION)

test: ## Tests; fails on any warning or a test defaults suite leaked into ~/Library/Preferences
	@scripts/check-test-defaults-leak.sh scripts/fail-on-warnings.sh -- swift test

lint: ## SwiftLint; read-only, fails on any finding
	@swiftlint lint --quiet --strict Sources Tests

format: ## Format the sources with SwiftFormat (the only target that edits sources)
	@swiftformat Sources Tests

validate: ## Repository invariants and the static site (scripts/validate.sh)
	@scripts/validate.sh

check: build lint test validate ## Everything a commit needs, stopping at the first failure

app: ## build/Mailbell.app and its update zip, with the OAuth client (signed with DEVELOPER_ID_IDENTITY from the shell or .env, else ad-hoc; FORCE=1 replaces)
	@scripts/package-with-oauth.sh $(FORCE_FLAG)

dmg: app ## The branded DMG from build/Mailbell.app, with the committed art; needs Node 24 or older (FORCE=1 replaces)
	@scripts/make-dmg.sh $(FORCE_FLAG)

# The art is committed; regenerate it only after changing Support/logo.png or a generator. The
# DMG background frames are intermediates in artifacts/.
icon: ## Regenerate the app icon and the DMG background
	scripts/generate-app-icon.sh
	scripts/render-dmg-background.swift
	tiffutil -cathidpicheck artifacts/dmg-bg.png artifacts/dmg-bg@2x.png \
		-out Support/MailbellInstallerBackground.tiff

screenshots: ## Capture site/screenshots/ from a throwaway bundle (Screen Recording permission, a 2x display)
	@scripts/capture-screenshots.sh

keys: ## Once per machine: the Sparkle key in the login Keychain matches SUPublicEDKey
	@scripts/make-keys.sh

appcast: ## Add one appcast.xml entry: VERSION, BUILD_NUMBER, ARCHIVE and SIGNATURE are required
	@scripts/make-appcast.sh --version "$(VERSION)" --build-number "$(BUILD_NUMBER)" \
		--archive "$(ARCHIVE)" --signature '$(SIGNATURE)' \
		--release-notes-url "https://$(HOST)/release-notes/{version}/update/" \
		--full-release-notes-url "https://$(HOST)/release-notes/"

clean: ## Remove the SwiftPM build, build/ and artifacts/
	swift package clean
	rm -rf .build build artifacts

# -- Mailbell targets ----------------------------------------------------------

# Notifications reach only a real bundle, so this is the way to exercise them.
install: app ## Copy build/Mailbell.app from `make app` into /Applications (FORCE=1 rebuilds an existing bundle)
	@rm -rf $(APP_BUNDLE)
	@ditto build/Mailbell.app $(APP_BUNDLE)
	@-$(LSREGISTER) -f $(APP_BUNDLE) >/dev/null 2>&1
	@printf 'Installed %s; open it with: open %s\n' "$(APP_BUNDLE)" "$(APP_BUNDLE)"

uninstall: ## Remove /Applications/Mailbell.app
	@rm -rf $(APP_BUNDLE)
	@printf 'Removed %s\n' "$(APP_BUNDLE)"

run: build ## Run the debug executable, unbundled; notifications need `make install`
	@.build/debug/Mailbell

refresh-icons: install ## Reinstall and flush the macOS icon caches after an icon change
	@rm -rf $(HOME)/Library/Caches/com.apple.iconservices.store
	@-$(LSREGISTER) -kill -r -domain local -domain system -domain user >/dev/null 2>&1
	@-$(LSREGISTER) -f $(APP_BUNDLE) >/dev/null 2>&1
	@touch $(APP_BUNDLE)
	@-killall Finder >/dev/null 2>&1
	@printf 'Icon cache refreshed for %s\n' "$(APP_BUNDLE)"

setup-release-signing: ## Record DEVELOPER_ID_IDENTITY in .env and create the shared notarytool Keychain profile
	@scripts/configure-release-signing.sh

clean-test-defaults: ## List test preferences left in ~/Library/Preferences by older runs (DELETE=1 removes them)
	@scripts/clean-test-defaults.sh $(if $(filter 1,$(DELETE)),--delete,)
