SWIFT       ?= swift
SWIFTLINT   ?= swiftlint
SWIFTFORMAT ?= swiftformat
CODESIGN    ?= codesign

PRODUCT    := mailbell
APP_NAME   := Mailbell
BUILD_DIR  := .build
APP_BUNDLE := /Applications/$(APP_NAME).app
INFO_PLIST := Support/Info.plist
ARCH       ?= arm64

RELEASE_DIR := $(BUILD_DIR)/release
RELEASE_STAGING := $(RELEASE_DIR)/staging

# Ad-hoc signing by default (identity "-"); no Apple Developer account needed.
# Release builds require MAILBELL_CODE_SIGN_IDENTITY (a Developer ID identity).
CODE_SIGN_IDENTITY    ?= -
PLISTBUDDY            := /usr/libexec/PlistBuddy
LSREGISTER            := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

export MAILBELL_GOOGLE_CLIENT_ID
export MAILBELL_GOOGLE_CLIENT_SECRET
export MAILBELL_BUNDLE_ID
export MAILBELL_CODE_SIGN_IDENTITY
export NOTARY_PROFILE
export MAILBELL_DOTENV_PATH

BOLD  := \033[1m
CYAN  := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RESET := \033[0m

.DEFAULT_GOAL := help

# -- Development --------------------------------------------------------------

.PHONY: build app run test lint format validate check

build: ## Build debug artifacts
	@$(SWIFT) build -c debug

app: require-oauth-config icons ## Package an ad-hoc signed build/Mailbell.app and its update archive
	@scripts/package-with-oauth.sh --identity "$(CODE_SIGN_IDENTITY)" --arch $(ARCH) --force

run: build ## Run the debug executable (unbundled; notifications need 'make install')
	@$(BUILD_DIR)/debug/$(PRODUCT)

test: ## Run tests; fails when a run leaks a test defaults suite into ~/Library/Preferences
	@scripts/check-test-defaults-leak.sh $(SWIFT) test

lint: ## Run SwiftLint
	@$(SWIFTLINT) lint --quiet --strict Sources Tests

format: ## Format sources
	@$(SWIFTFORMAT) Sources Tests

validate: ## Check repository invariants
	@bash scripts/validate.sh

check: ## Run build, lint, tests, and repository validation
	@printf '\n$(BOLD)[1/4] Building$(RESET)\n'
	@$(MAKE) --no-print-directory build
	@printf '\n$(BOLD)[2/4] Running lint$(RESET)\n'
	@$(MAKE) --no-print-directory lint
	@printf '\n$(BOLD)[3/4] Running tests$(RESET)\n'
	@$(MAKE) --no-print-directory test
	@printf '\n$(BOLD)[4/4] Validating$(RESET)\n'
	@$(MAKE) --no-print-directory validate
	@printf '\n$(GREEN)[ok] All checks passed$(RESET)\n\n'

# -- Packaging ----------------------------------------------------------------

.PHONY: icons require-oauth-config setup-release-signing sparkle-keys release dmg install uninstall refresh-icons

icons: ## Regenerate AppIcon PNGs and AppIcon.icns from Support/logo.png
	@printf "$(BOLD)[icons]$(RESET) Regenerating app icons\n"
	@chmod +x scripts/generate-app-icon.sh
	@scripts/generate-app-icon.sh

require-oauth-config: ## Verify the release Google OAuth credentials are available
	@scripts/inject-bundle-config.sh --check

setup-release-signing: ## Configure the Developer ID identity and the shared notarytool Keychain profile
	@scripts/configure-release-signing.sh

sparkle-keys: ## Generate the Sparkle EdDSA key (Keychain) and write the public key
	@bash scripts/make-sparkle-keys.sh

release: icons ## Build, sign, notarize, and staple a tagged release DMG
	@bash -euo pipefail -c '\
		source scripts/mailbell-env.sh; \
		mailbell_load_dotenv; \
		if [[ -n "$$(git status --porcelain --untracked-files=normal)" ]]; then \
			echo "error: worktree must be clean before make release" >&2; \
			git status --short --branch >&2; \
			exit 1; \
		fi; \
		eval "$$(scripts/resolve-release-metadata.sh --shell)"; \
		scripts/inject-bundle-config.sh --check >/dev/null; \
		if [[ -z "$${MAILBELL_CODE_SIGN_IDENTITY:-}" ]]; then \
			echo "error: set MAILBELL_CODE_SIGN_IDENTITY in .env or your shell" >&2; \
			echo "hint: run make setup-release-signing once on the release Mac" >&2; \
			exit 1; \
		fi; \
		notarize() { \
			mkdir -p artifacts/notarization; \
			local log="artifacts/notarization/notarytool-$$(date +%Y%m%d-%H%M%S).log"; \
			if scripts/notarize.sh --artifact "$$1" 2>&1 | tee "$${log}"; then \
				rm -f "$${log}"; \
				rmdir artifacts/notarization 2>/dev/null || true; \
			else \
				echo "error: notarization failed; log kept at $${log}" >&2; \
				echo "hint: run make setup-release-signing once on the release Mac" >&2; \
				exit 1; \
			fi; \
		}; \
		plist_version="$$($(PLISTBUDDY) -c "Print :CFBundleShortVersionString" $(INFO_PLIST))"; \
		plist_build="$$($(PLISTBUDDY) -c "Print :CFBundleVersion" $(INFO_PLIST))"; \
		if [[ "$${plist_version}" != "$${VERSION}" ]]; then \
			echo "error: tag v$${VERSION} does not match $(INFO_PLIST) ($${plist_version})" >&2; \
			exit 1; \
		fi; \
		if [[ "$${plist_build}" != "$${BUILD_NUMBER}" ]]; then \
			echo "error: $(INFO_PLIST) build $${plist_build} does not match derived $${BUILD_NUMBER}" >&2; \
			exit 1; \
		fi; \
		final_dmg="$(BUILD_DIR)/$${DMG_NAME}"; \
		update_zip="artifacts/$(APP_NAME)-$${VERSION}.zip"; \
		app_bundle="$(RELEASE_STAGING)/$(APP_NAME).app"; \
		printf "\n$(BOLD)[1/11]$(RESET) Building signed release app for $(ARCH)\n"; \
		mkdir -p "$(RELEASE_STAGING)" artifacts; \
		scripts/package-with-oauth.sh --output "$${app_bundle}" --archive "$${update_zip}" \
			--identity "$${MAILBELL_CODE_SIGN_IDENTITY}" \
			--version "$${VERSION}" --build-number "$${BUILD_NUMBER}" --arch $(ARCH) --force >/dev/null; \
		printf "$(BOLD)[2/11]$(RESET) Verifying app signature\n"; \
		$(CODESIGN) --verify --deep --strict --verbose=2 "$${app_bundle}"; \
		printf "$(BOLD)[3/11]$(RESET) Notarizing the update archive\n"; \
		notarize "$${update_zip}"; \
		printf "$(BOLD)[4/11]$(RESET) Stapling and re-archiving the app\n"; \
		xcrun stapler staple "$${app_bundle}"; \
		xcrun stapler validate "$${app_bundle}"; \
		rm -f "$${update_zip}"; \
		ditto -c -k --keepParent "$${app_bundle}" "$${update_zip}"; \
		printf "$(BOLD)[5/11]$(RESET) Creating release DMG\n"; \
		scripts/make-dmg.sh --app "$${app_bundle}" --output "$${final_dmg}" --version "$${VERSION}" --force >/dev/null; \
		printf "$(BOLD)[6/11]$(RESET) Cleaning release staging files\n"; \
		rm -rf "$(RELEASE_DIR)"; \
		printf "$(BOLD)[7/11]$(RESET) Signing DMG with Developer ID\n"; \
		$(CODESIGN) --force --timestamp --sign "$${MAILBELL_CODE_SIGN_IDENTITY}" "$${final_dmg}"; \
		$(CODESIGN) --verify --verbose=2 "$${final_dmg}"; \
		printf "$(BOLD)[8/11]$(RESET) Notarizing DMG\n"; \
		notarize "$${final_dmg}"; \
		printf "$(BOLD)[9/11]$(RESET) Verifying final DMG\n"; \
		hdiutil verify "$${final_dmg}" >/dev/null; \
		spctl -a -t open --context context:primary-signature -vv "$${final_dmg}"; \
		printf "$(BOLD)[10/11]$(RESET) Signing the update archive for Sparkle\n"; \
		sig="$$(scripts/sign-sparkle-update.sh "$${update_zip}")"; \
		scripts/make-appcast.sh "$${VERSION}" "$${BUILD_NUMBER}" "$${update_zip}" "$${sig}"; \
		printf "$(BOLD)[11/11]$(RESET) Release artifacts ready\n"; \
		cp -f "$${final_dmg}" "artifacts/$$(basename "$${final_dmg}")"; \
		printf "$(GREEN)[ok]$(RESET) DMG: artifacts/%s\n" "$$(basename "$${final_dmg}")"; \
		printf "$(GREEN)[ok]$(RESET) Update archive: %s\n" "$${update_zip}"; \
		printf "$(GREEN)[ok]$(RESET) appcast.xml updated; commit it before publishing the release\n"; \
	'

refresh-icons: install ## Reinstall and flush macOS icon caches for Mailbell
	@printf "$(BOLD)[icons]$(RESET) Refreshing macOS icon caches\n"
	@rm -rf $(HOME)/Library/Caches/com.apple.iconservices.store
	@-$(LSREGISTER) -kill -r -domain local -domain system -domain user >/dev/null 2>&1
	@-$(LSREGISTER) -f $(APP_BUNDLE) >/dev/null 2>&1
	@touch $(APP_BUNDLE)
	@-killall Finder >/dev/null 2>&1
	@printf "$(GREEN)[ok]$(RESET) Icon cache refreshed for %s\n" "$(APP_BUNDLE)"

dmg: app ## Build an ad-hoc signed drag-and-drop DMG in artifacts/ (needs Node 24 or older)
	@scripts/make-dmg.sh --force

install: require-oauth-config icons ## Install an ad-hoc signed app bundle to /Applications
	@printf "\n$(BOLD)[1/2]$(RESET) Building local packaged app for $(ARCH)\n"
	@scripts/package-with-oauth.sh --output $(APP_BUNDLE) \
		--identity "$(CODE_SIGN_IDENTITY)" --arch $(ARCH) --force >/dev/null
	@printf "$(BOLD)[2/2]$(RESET) Registering app with LaunchServices\n"
	@-$(LSREGISTER) -f $(APP_BUNDLE) >/dev/null 2>&1
	@printf "$(GREEN)[ok]$(RESET) Installed to %s\n" "$(APP_BUNDLE)"
	@printf "Open with: open %s\n" "$(APP_BUNDLE)"

uninstall: ## Remove the installed app bundle
	@rm -rf $(APP_BUNDLE)
	@printf "$(GREEN)[ok]$(RESET) Removed %s\n" "$(APP_BUNDLE)"

# -- Maintenance --------------------------------------------------------------

.PHONY: clean

clean-test-defaults: ## List test preferences left in ~/Library/Preferences by older runs (DELETE=1 removes them)
	@scripts/clean-test-defaults.sh $(if $(filter 1,$(DELETE)),--delete,)

clean: ## Remove SwiftPM build artifacts
	@$(SWIFT) package clean
	@rm -rf $(BUILD_DIR)

# -- Help ---------------------------------------------------------------------

.PHONY: help

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "; printf "\n$(BOLD)mailbell$(RESET) - macOS menu bar Gmail notifier\n"} \
		/^# -- / {n = $$0; gsub(/(^# -- | -+$$)/, "", n); printf "\n$(BOLD)%s$(RESET)\n", n} \
		/^[a-zA-Z_-]+:.*## / {printf "  $(CYAN)make %-22s$(RESET) %s\n", $$1, $$2} \
		END {printf "\n"}' $(MAKEFILE_LIST)
