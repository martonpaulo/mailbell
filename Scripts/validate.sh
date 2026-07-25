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
# This script is excluded because it necessarily names the prefix it looks for.
if git ls-files -z 2>/dev/null | xargs -0 grep -l 'GOCSPX-' 2>/dev/null \
    | grep -v '^Scripts/validate.sh$' | grep -q .; then
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

# Every website page shares one navigation and one footer. A visitor must never
# see the site's structure change from page to page.
expected_navigation="Features|Download|Privacy|Terms|GitHub"
expected_footer="Privacy|Terms|Source|Issues|Releases"
for page in docs/index.html docs/privacy.html docs/terms.html; do
    [ -f "$page" ] || continue
    navigation=$(sed -n '/<nav aria-label="Page sections">/,/<\/nav>/p' "$page" \
        | sed -E -n 's/.*>([^<]+)<\/a>.*/\1/p' | paste -sd '|' -)
    [ "$navigation" = "$expected_navigation" ] \
        || note "$page navigation must be $expected_navigation (got $navigation)"
    footer=$(sed -n '/<footer class="site-footer">/,/<\/footer>/p' "$page" \
        | sed -E -n 's/.*>([^<]+)<\/a>.*/\1/p' | paste -sd '|' -)
    [ "$footer" = "$expected_footer" ] \
        || note "$page footer must be $expected_footer (got $footer)"
    grep -q 'aria-current="page"' "$page" \
        || note "$page must identify the current page"
done

# Settings control semantics. These are source-shape invariants, not behavior,
# so they live here rather than masquerading as unit tests. Panes are discovered
# so a new one cannot skip the rules.
panes=$(ls Sources/Mailbell/App/Settings*Pane.swift 2>/dev/null || true)
[ -n "$panes" ] || note "no Settings pane sources found"
for pane in $panes; do
    # Comments are stripped first, so prose naming a banned pattern never trips.
    code=$(grep -vE '^[[:space:]]*//' "$pane")

    # A toggle labelled with the inverse action ("Disable Account") reads as its
    # own opposite the moment it is on.
    if grep -q '"Disable ' <<< "$code"; then
        note "$pane: a toggle must not be labelled with the inverse action"
    fi
    if grep -E 'Toggle\(' <<< "$code" | grep -qE 'Title\(for:|accountEnabledTitle'; then
        note "$pane: toggle labels must be fixed strings, not derived from their own value"
    fi

    # LabeledContent means label to value; wrapping a button in one produces
    # rows like "Remove Account: Remove".
    if grep -A2 'LabeledContent(' <<< "$code" | grep -q 'Button('; then
        note "$pane: use a plain Button; LabeledContent is for label to value"
    fi

    # Destructive intent comes from the role, not a hand-applied colour.
    if grep -q 'foregroundStyle(\.red)' <<< "$code"; then
        note "$pane: use Button(role: .destructive) instead of colouring a control red"
    fi

    # Actions must go through the shared row so alignment has one definition.
    if grep -q 'Button(' <<< "$code" && ! grep -q 'SettingsActionRow\|LabeledContent\|confirmationDialog' <<< "$code"; then
        note "$pane: place actions with SettingsActionRow"
    fi
done

# A section header that repeats the tab it lives in is wasted space.
if grep -q 'Text("About")' Sources/Mailbell/App/SettingsAboutPane.swift; then
    note "SettingsAboutPane.swift: drop the section header that repeats the tab name"
fi

# Settings copy has one home.
for pane in $panes; do
    stray=$(grep -vE '^[[:space:]]*//' "$pane" \
        | grep -oE '(Text|Button|Link)\("[^"]{16,}"' | head -1 || true)
    [ -z "$stray" ] || note "$pane: move user-facing copy into SettingsCopy ($stray)"
done

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
