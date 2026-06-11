SWIFT       ?= swift
SWIFTLINT   ?= swiftlint
SWIFTFORMAT ?= swiftformat
CODESIGN    ?= codesign

PRODUCT    := mailbell
APP_NAME   := Mailbell
BUILD_DIR  := .build
APP_BUNDLE := /Applications/$(APP_NAME).app
INFO_PLIST := Resources/Info.plist
APP_ICON   := Resources/AppIcon.icns
ASSETS     := Resources/Assets.xcassets
ARCH       ?= arm64

DMG_DIR     := $(BUILD_DIR)/dmg
DMG_STAGING := $(DMG_DIR)/staging
DMG_PATH    := $(BUILD_DIR)/$(APP_NAME)-$(ARCH).dmg

# Ad-hoc signing by default (identity "-"); no Apple Developer account needed.
# Override CODE_SIGN_IDENTITY only if you later get a Developer ID certificate.
CODE_SIGN_IDENTITY    ?= -
CODE_SIGN             := $(CODESIGN) --force --sign $(CODE_SIGN_IDENTITY)
PLISTBUDDY            := /usr/libexec/PlistBuddy
LSREGISTER            := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

export MAILBELL_GOOGLE_CLIENT_ID
export MAILBELL_GOOGLE_CLIENT_SECRET
export MAILBELL_BUNDLE_ID
export MAILBELL_APP_DISPLAY_NAME
export MAILBELL_DOTENV_PATH

BOLD  := \033[1m
CYAN  := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RESET := \033[0m

.DEFAULT_GOAL := help

# -- Development --------------------------------------------------------------

.PHONY: build app run test lint format check

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

check: ## Run build, lint, and tests
	@printf '\n$(BOLD)[1/3] Building$(RESET)\n'
	@$(MAKE) --no-print-directory build
	@printf '\n$(BOLD)[2/3] Running lint$(RESET)\n'
	@$(MAKE) --no-print-directory lint
	@printf '\n$(BOLD)[3/3] Running tests$(RESET)\n'
	@$(MAKE) --no-print-directory test
	@printf '\n$(GREEN)[ok] All checks passed$(RESET)\n\n'

# -- Packaging ----------------------------------------------------------------

.PHONY: icons require-oauth-config dmg install uninstall refresh-icons

icons: ## Regenerate AppIcon PNGs and AppIcon.icns from Resources/logo.png
	@printf "$(BOLD)[icons]$(RESET) Regenerating app icons\n"
	@chmod +x Scripts/generate_app_icon.sh
	@Scripts/generate_app_icon.sh

require-oauth-config: ## Verify local Google OAuth credentials are available
	@Scripts/inject_oauth_config.sh --check

define compile-app-resources
	@xcrun actool --compile $(1)/Contents/Resources \
		--platform macosx \
		--minimum-deployment-target 26.0 \
		--app-icon AppIcon \
		--output-partial-info-plist /dev/null \
		$(ASSETS) >/dev/null
endef

refresh-icons: install ## Reinstall and flush macOS icon caches for Mailbell
	@printf "$(BOLD)[icons]$(RESET) Refreshing macOS icon caches\n"
	@rm -rf $(HOME)/Library/Caches/com.apple.iconservices.store
	@-$(LSREGISTER) -kill -r -domain local -domain system -domain user >/dev/null 2>&1
	@-$(LSREGISTER) -f $(APP_BUNDLE) >/dev/null 2>&1
	@touch $(APP_BUNDLE)
	@-killall Finder >/dev/null 2>&1
	@printf "$(GREEN)[ok]$(RESET) Icon cache refreshed for %s\n" "$(APP_BUNDLE)"

dmg: require-oauth-config icons ## Build an ad-hoc signed DMG
	@printf "\n$(BOLD)[1/7]$(RESET) Building release app for $(ARCH)\n"
	@$(SWIFT) build -c release --arch $(ARCH) --product $(PRODUCT)
	@printf "$(BOLD)[2/7]$(RESET) Preparing DMG staging directory\n"
	@rm -rf $(DMG_STAGING)
	@mkdir -p $(DMG_STAGING)/$(APP_NAME).app/Contents/MacOS
	@mkdir -p $(DMG_STAGING)/$(APP_NAME).app/Contents/Resources
	@cp $$($(SWIFT) build -c release --arch $(ARCH) --product $(PRODUCT) --show-bin-path)/$(PRODUCT) $(DMG_STAGING)/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)
	@cp $(INFO_PLIST) $(DMG_STAGING)/$(APP_NAME).app/Contents/Info.plist
	@printf "$(BOLD)[3/7]$(RESET) Injecting local bundle/OAuth configuration\n"
	@Scripts/inject_oauth_config.sh $(DMG_STAGING)/$(APP_NAME).app/Contents/Info.plist
	@printf "$(BOLD)[4/7]$(RESET) Compiling app resources\n"
	$(call compile-app-resources,$(DMG_STAGING)/$(APP_NAME).app)
	@printf "$(BOLD)[5/7]$(RESET) Signing app bundle\n"
	@$(CODE_SIGN) $(DMG_STAGING)/$(APP_NAME).app
	@printf "$(BOLD)[6/7]$(RESET) Creating DMG\n"
	@ln -s /Applications $(DMG_STAGING)/Applications
	@rm -f $(DMG_PATH)
	@hdiutil create -volname "$(APP_NAME)" \
		-srcfolder $(DMG_STAGING) \
		-ov -format UDZO \
		$(DMG_PATH)
	@printf "$(BOLD)[7/7]$(RESET) Cleaning temporary DMG staging files\n"
	@rm -rf $(DMG_DIR)
	@printf "$(GREEN)[ok]$(RESET) DMG created: %s\n" "$(DMG_PATH)"

install: require-oauth-config icons ## Install an ad-hoc signed app bundle to /Applications
	@printf "\n$(BOLD)[1/6]$(RESET) Building release app for $(ARCH)\n"
	@$(SWIFT) build -c release --arch $(ARCH) --product $(PRODUCT)
	@printf "$(BOLD)[2/6]$(RESET) Installing app bundle to %s\n" "$(APP_BUNDLE)"
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $$($(SWIFT) build -c release --arch $(ARCH) --product $(PRODUCT) --show-bin-path)/$(PRODUCT) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp $(INFO_PLIST) $(APP_BUNDLE)/Contents/Info.plist
	@printf "$(BOLD)[3/6]$(RESET) Injecting local bundle/OAuth configuration\n"
	@Scripts/inject_oauth_config.sh $(APP_BUNDLE)/Contents/Info.plist
	@printf "$(BOLD)[4/6]$(RESET) Compiling app resources\n"
	$(call compile-app-resources,$(APP_BUNDLE))
	@printf "$(BOLD)[5/6]$(RESET) Signing app bundle\n"
	@$(CODE_SIGN) $(APP_BUNDLE)
	@printf "$(BOLD)[6/6]$(RESET) Registering app with LaunchServices\n"
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
		/^[a-zA-Z_-]+:.*## / {printf "  $(CYAN)make %-10s$(RESET) %s\n", $$1, $$2} \
		END {printf "\n"}' $(MAKEFILE_LIST)
