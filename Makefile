SWIFT       ?= swift
SWIFTLINT   ?= swiftlint
SWIFTFORMAT ?= swiftformat
CODESIGN    ?= codesign

PRODUCT    := mailbell
APP_NAME   := Mailbell
BUILD_DIR  := .build
APP_BUNDLE := /Applications/$(APP_NAME).app
INFO_PLIST := Resources/Info.plist
INSTALLER_ICON := Resources/AppInstallerIcon.icns
ARCH       ?= arm64

DMG_DIR     := $(BUILD_DIR)/dmg
DMG_STAGING := $(DMG_DIR)/staging
DMG_VOLUME_NAME := Install $(APP_NAME)
DMG_PATH    := $(BUILD_DIR)/$(DMG_VOLUME_NAME).dmg
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
export MAILBELL_NOTARY_KEYCHAIN_PROFILE
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

app: ## Build the debug executable product
	@$(SWIFT) build -c debug --product $(PRODUCT)

run: app ## Run the debug executable (unbundled; notifications need 'make install')
	@$(BUILD_DIR)/debug/$(PRODUCT)

test: ## Run tests
	@$(SWIFT) test

lint: ## Run SwiftLint
	@$(SWIFTLINT) lint --quiet Sources Tests

format: ## Format sources
	@$(SWIFTFORMAT) Sources Tests

validate: ## Check repository invariants
	@bash Scripts/validate.sh

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

icons: ## Regenerate AppIcon PNGs and AppIcon.icns from Resources/logo.png
	@printf "$(BOLD)[icons]$(RESET) Regenerating app icons\n"
	@chmod +x Scripts/generate_app_icon.sh
	@Scripts/generate_app_icon.sh

require-oauth-config: ## Verify the release Google OAuth credentials are available
	@Scripts/inject_bundle_config.sh --check

setup-release-signing: ## Configure Developer ID identity and notarytool Keychain profile
	@Scripts/configure_release_signing.sh

sparkle-keys: ## Generate the Sparkle EdDSA key (Keychain) and write the public key
	@bash Scripts/make_sparkle_keys.sh

release: icons ## Build, sign, notarize, and staple a tagged release DMG
	@bash -euo pipefail -c '\
		source Scripts/mailbell_env.sh; \
		mailbell_load_dotenv; \
		if [[ -n "$$(git status --porcelain --untracked-files=normal)" ]]; then \
			echo "error: worktree must be clean before make release" >&2; \
			git status --short --branch >&2; \
			exit 1; \
		fi; \
		eval "$$(Scripts/resolve_release_metadata.sh --shell)"; \
		Scripts/inject_bundle_config.sh --check >/dev/null; \
		if [[ -z "$${MAILBELL_CODE_SIGN_IDENTITY:-}" ]]; then \
			echo "error: set MAILBELL_CODE_SIGN_IDENTITY in .env or your shell" >&2; \
			echo "hint: run make setup-release-signing once on the release Mac" >&2; \
			exit 1; \
		fi; \
		if [[ -z "$${MAILBELL_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then \
			echo "error: set MAILBELL_NOTARY_KEYCHAIN_PROFILE in .env or your shell" >&2; \
			echo "hint: run make setup-release-signing once on the release Mac" >&2; \
			exit 1; \
		fi; \
		plist_version="$$($(PLISTBUDDY) -c "Print :CFBundleShortVersionString" $(INFO_PLIST))"; \
		if [[ "$${plist_version}" != "$${VERSION}" ]]; then \
			echo "error: tag v$${VERSION} does not match $(INFO_PLIST) ($${plist_version})" >&2; \
			exit 1; \
		fi; \
		final_dmg="$(BUILD_DIR)/$${DMG_NAME}"; \
		update_zip="artifacts/$(APP_NAME)-$${VERSION}.zip"; \
		app_bundle="$(RELEASE_STAGING)/$(APP_NAME).app"; \
		printf "\n$(BOLD)[1/13]$(RESET) Building signed release app for $(ARCH)\n"; \
		mkdir -p "$(RELEASE_STAGING)" artifacts; \
		Scripts/build_app_bundle.sh --output "$${app_bundle}" \
			--identity "$${MAILBELL_CODE_SIGN_IDENTITY}" --hardened \
			--version "$${VERSION}" --build-number "$${BUILD_NUMBER}" --arch $(ARCH); \
		printf "$(BOLD)[2/13]$(RESET) Verifying app signature\n"; \
		$(CODESIGN) --verify --deep --strict --verbose=2 "$${app_bundle}"; \
		printf "$(BOLD)[3/13]$(RESET) Creating the Sparkle update archive\n"; \
		rm -f "$${update_zip}"; \
		ditto -c -k --keepParent "$${app_bundle}" "$${update_zip}"; \
		printf "$(BOLD)[4/13]$(RESET) Notarizing the update archive\n"; \
		Scripts/notarize_release.sh "$${update_zip}"; \
		printf "$(BOLD)[5/13]$(RESET) Stapling and re-archiving the app\n"; \
		xcrun stapler staple "$${app_bundle}"; \
		xcrun stapler validate "$${app_bundle}"; \
		rm -f "$${update_zip}"; \
		ditto -c -k --keepParent "$${app_bundle}" "$${update_zip}"; \
		printf "$(BOLD)[6/13]$(RESET) Adding Applications shortcut\n"; \
		ln -sfn /Applications "$(RELEASE_STAGING)/Applications"; \
		printf "$(BOLD)[7/13]$(RESET) Creating release DMG\n"; \
		rm -f "$${final_dmg}"; \
		Scripts/create_dmg.sh "$(RELEASE_STAGING)" "$(APP_NAME)" "$(INSTALLER_ICON)" "$${DMG_VOLUME_NAME}" "$${final_dmg}"; \
		printf "$(BOLD)[8/13]$(RESET) Cleaning release staging files\n"; \
		rm -rf "$(RELEASE_DIR)"; \
		printf "$(BOLD)[9/13]$(RESET) Signing DMG with Developer ID\n"; \
		$(CODESIGN) --force --timestamp --sign "$${MAILBELL_CODE_SIGN_IDENTITY}" "$${final_dmg}"; \
		$(CODESIGN) --verify --verbose=2 "$${final_dmg}"; \
		printf "$(BOLD)[10/13]$(RESET) Notarizing DMG\n"; \
		Scripts/notarize_release.sh "$${final_dmg}"; \
		printf "$(BOLD)[11/13]$(RESET) Verifying final DMG\n"; \
		hdiutil verify "$${final_dmg}" >/dev/null; \
		spctl -a -t open --context context:primary-signature -vv "$${final_dmg}"; \
		printf "$(BOLD)[12/13]$(RESET) Signing the update archive for Sparkle\n"; \
		sig="$$(Scripts/sign_sparkle_update.sh "$${update_zip}")"; \
		Scripts/make_appcast.sh "$${VERSION}" "$${BUILD_NUMBER}" "$${update_zip}" "$${sig}"; \
		printf "$(BOLD)[13/13]$(RESET) Release artifacts ready\n"; \
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

dmg: require-oauth-config icons ## Build an ad-hoc signed drag-and-drop DMG
	@printf "\n$(BOLD)[1/4]$(RESET) Building local packaged app for $(ARCH)\n"
	@rm -rf $(DMG_STAGING)
	@mkdir -p $(DMG_STAGING)
	@Scripts/build_app_bundle.sh --output $(DMG_STAGING)/$(APP_NAME).app \
		--identity "$(CODE_SIGN_IDENTITY)" --arch $(ARCH)
	@printf "$(BOLD)[2/4]$(RESET) Adding Applications shortcut\n"
	@ln -sfn /Applications $(DMG_STAGING)/Applications
	@printf "$(BOLD)[3/4]$(RESET) Creating standard macOS installer DMG\n"
	@rm -f "$(DMG_PATH)"
	@Scripts/create_dmg.sh "$(DMG_STAGING)" "$(APP_NAME)" "$(INSTALLER_ICON)" "$(DMG_VOLUME_NAME)" "$(DMG_PATH)"
	@printf "$(BOLD)[4/4]$(RESET) Cleaning temporary DMG staging files\n"
	@rm -rf $(DMG_DIR)
	@printf "$(GREEN)[ok]$(RESET) DMG created: %s\n" "$(DMG_PATH)"

install: require-oauth-config icons ## Install an ad-hoc signed app bundle to /Applications
	@printf "\n$(BOLD)[1/2]$(RESET) Building local packaged app for $(ARCH)\n"
	@Scripts/build_app_bundle.sh --output $(APP_BUNDLE) \
		--identity "$(CODE_SIGN_IDENTITY)" --arch $(ARCH)
	@printf "$(BOLD)[2/2]$(RESET) Registering app with LaunchServices\n"
	@-$(LSREGISTER) -f $(APP_BUNDLE) >/dev/null 2>&1
	@printf "$(GREEN)[ok]$(RESET) Installed to %s\n" "$(APP_BUNDLE)"
	@printf "Open with: open %s\n" "$(APP_BUNDLE)"

uninstall: ## Remove the installed app bundle
	@rm -rf $(APP_BUNDLE)
	@printf "$(GREEN)[ok]$(RESET) Removed %s\n" "$(APP_BUNDLE)"

# -- Maintenance --------------------------------------------------------------

.PHONY: clean

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
