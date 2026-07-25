#!/usr/bin/env bash
# Repository invariants that must always hold. Fast and grep-based; the build
# and tests run separately.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
note() { echo "FAIL: $1"; fail=1; }

# One agent-guidance source of truth.
if [ ! -L CLAUDE.md ] || [ "$(readlink CLAUDE.md)" != "AGENTS.md" ]; then
    note "CLAUDE.md must be a symlink to AGENTS.md"
fi

# The bundle identifier is fixed: Keychain and UserDefaults ownership derive
# from it, so a change silently orphans every user's accounts and tokens.
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist)
[ "$BUNDLE_ID" = "com.perso.mailbell" ] \
    || note "bundle id must be com.perso.mailbell (got $BUNDLE_ID)"

# The menu bar app must stay accessory-style.
[ "$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" Resources/Info.plist)" = "true" ] \
    || note "LSUIElement must be true so Mailbell stays out of the Dock"

# Sparkle needs both halves of its contract, over HTTPS.
FEED=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" Resources/Info.plist 2>/dev/null || echo "")
SPARKLE_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Resources/Info.plist 2>/dev/null || echo "")
case "$FEED" in
    https://*) ;;
    *) note "SUFeedURL must be an https appcast URL (got '$FEED')" ;;
esac
[ -n "$SPARKLE_KEY" ] || note "SUPublicEDKey must ship in Resources/Info.plist"

# No credentials or signing material are ever committed.
if git ls-files 2>/dev/null | grep -qiE '\.(p12|pem)$|_priv$|^\.env$'; then
    note "credentials and signing material must not be committed"
fi
# Google installed-app secrets carry a fixed prefix; nothing tracked may hold one.
if git ls-files -z 2>/dev/null | xargs -0 grep -l 'GOCSPX-' 2>/dev/null | grep -q .; then
    note "a Google OAuth client secret must never be committed"
fi
# The credentials this machine actually builds with must not appear in git.
if [ -f .env ]; then
    while IFS='=' read -r key value; do
        case "$key" in
            MAILBELL_GOOGLE_CLIENT_ID|MAILBELL_GOOGLE_CLIENT_SECRET) ;;
            *) continue ;;
        esac
        [ -n "$value" ] || continue
        if git ls-files -z 2>/dev/null | xargs -0 grep -lF "$value" 2>/dev/null | grep -q .; then
            note "the real $key value is present in a tracked file"
        fi
    done < .env
fi
if [ -f .env.example ] && grep -qE '^[A-Z_]+=.+' .env.example; then
    note ".env.example must list variable names with empty values only"
fi

# Release credentials are injected at packaging time, never checked in.
grep -q 'MailbellGoogleClientID' Scripts/inject_bundle_config.sh \
    || note "packaging must inject the OAuth client into the bundle plist"

# Sparkle is embedded and nested-signed by exactly one script, so no packaging
# path can ship an unsigned updater.
grep -q 'Sparkle.framework' Scripts/build_app_bundle.sh \
    || note "the shared bundle builder must embed Sparkle.framework"
grep -q 'XPCServices/Downloader.xpc' Scripts/build_app_bundle.sh \
    || note "the shared bundle builder must sign Sparkle's nested XPC services"
for target in install dmg release; do
    grep -qE "^${target}:" Makefile || note "Makefile must define the $target target"
done
if grep -qE '^\s+@?cp .*Contents/MacOS' Makefile; then
    note "packaging paths must go through Scripts/build_app_bundle.sh"
fi

# The public beta must be honest about Google's review status everywhere it
# tells users what to expect.
for page in README.md docs/index.html docs/privacy.html docs/terms.html; do
    [ -f "$page" ] || { note "missing public document $page"; continue; }
    grep -qi 'unverified' "$page" \
        || note "$page must disclose the unverified Google OAuth status"
done
grep -qi '100' README.md || note "README must state Google's 100-new-user cap"
# An "unlimited" claim is only allowed when it is being denied.
if grep -hiE 'unlimited' README.md docs/*.html 2>/dev/null \
    | grep -viE '\b(no|not|never|without|cannot)\b' | grep -q .; then
    note "public copy must not promise unlimited use before Google verification"
fi

# Public-facing copy must not tell end users to create their own OAuth client.
if grep -qi 'create your own google' Sources/Mailbell/App/*.swift; then
    note "Settings must report a build error, not ask users to create an OAuth client"
fi

# Privacy claims that the app must keep true.
grep -q 'BODY.PEEK' Sources/Mailbell/IMAP/IMAPClient.swift \
    || note "body previews must stay non-mutating (BODY.PEEK)"
if grep -rqE '"https://(www\.)?googleapis\.com/(gmail|drive)' Sources; then
    note "Mailbell must not call Gmail REST endpoints; the product transport is IMAP"
fi

# Dependabot must cover both runtime packages and pinned GitHub Actions.
if [ ! -f .github/dependabot.yml ]; then
    note "Dependabot configuration is required"
else
    grep -q 'package-ecosystem: "swift"' .github/dependabot.yml \
        || note "Dependabot must monitor Swift packages"
    grep -q 'package-ecosystem: "github-actions"' .github/dependabot.yml \
        || note "Dependabot must monitor GitHub Actions"
fi

# A release tag must be able to match the shipped version.
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
echo "$PLIST_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || note "CFBundleShortVersionString must be X.Y.Z (got $PLIST_VERSION)"

# The published appcast must describe the shipped app.
if [ -f appcast.xml ]; then
    grep -q '<title>Mailbell</title>' appcast.xml \
        || note "appcast.xml must be Mailbell's feed"
    grep -q 'releases/download/v' appcast.xml \
        || note "appcast enclosures must point at GitHub release assets"
fi

if [ "$fail" -eq 0 ]; then
    echo "validate: ok"
else
    echo "validate: FAILED"
    exit 1
fi
