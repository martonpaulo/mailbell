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
# Antigravity CLI loads at most 24,000 bytes of a rule file and drops the rest.
agents_bytes=$(wc -c < AGENTS.md | tr -d ' ')
[ "$agents_bytes" -le 24000 ] || note "AGENTS.md is $agents_bytes bytes; the limit is 24000"

# The bundle identifier is fixed: Keychain and UserDefaults ownership derive
# from it, so a change silently orphans every user's accounts and tokens.
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Support/Info.plist)
[ "$BUNDLE_ID" = "com.martonpaulo.mailbell" ] \
    || note "bundle id must be com.martonpaulo.mailbell (got $BUNDLE_ID)"
# The previous identifier may appear only where the one-time preference copy reads
# its domain (#47). The bracket keeps this line from matching itself.
stale_identifier=$(git grep -lE 'com[.]perso[.]' -- . 2>/dev/null \
    | grep -v '^Sources/Mailbell/App/LegacyDomainMigration.swift$' || true)
[ -z "$stale_identifier" ] \
    || note "the previous bundle identifier appears outside LegacyDomainMigration.swift: $(echo $stale_identifier)"

# The menu bar app must stay accessory-style.
[ "$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" Support/Info.plist)" = "true" ] \
    || note "LSUIElement must be true so Mailbell stays out of the Dock"

# Sparkle needs both halves of its contract, over HTTPS.
FEED=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" Support/Info.plist 2>/dev/null || echo "")
SPARKLE_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Support/Info.plist 2>/dev/null || echo "")
case "$FEED" in
    https://*) ;;
    *) note "SUFeedURL must be an https appcast URL (got '$FEED')" ;;
esac
[ -n "$SPARKLE_KEY" ] || note "SUPublicEDKey must ship in Support/Info.plist"

# No credentials or signing material are ever committed.
if git ls-files 2>/dev/null | grep -qiE '\.(p12|pem)$|_priv$|^\.env$'; then
    note "credentials and signing material must not be committed"
fi
# Google installed-app secrets carry a fixed prefix; nothing tracked may hold one.
# This script is excluded because it necessarily names the prefix it looks for.
if git ls-files -z 2>/dev/null | xargs -0 grep -l 'GOCSPX-' 2>/dev/null \
    | grep -v '^scripts/validate.sh$' | grep -q .; then
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
# Tests make UserDefaults suites only through TestDefaults, whose absolute-path names keep
# cfprefsd from writing them into ~/Library/Preferences (#50).
if grep -rln 'UserDefaults(suiteName' Tests | grep -v '^Tests/MailbellTests/TestDefaults.swift$' | grep -q .; then
    note "a test makes a UserDefaults suite outside Tests/MailbellTests/TestDefaults.swift"
fi
if [ -f .env.example ] && grep -qE '^[A-Z_]+=.+' .env.example; then
    note ".env.example must list variable names with empty values only"
fi

# Release credentials are injected at packaging time, never checked in.
grep -q 'MailbellGoogleClientID' scripts/inject-bundle-config.sh \
    || note "packaging must inject the OAuth client into the bundle plist"

# Every packaging path goes through scripts/package-with-oauth.sh, which injects the OAuth
# client for one run of the canonical scripts/package-app.sh and restores Support/Info.plist.
# A direct package-app.sh call would ship a bundle without the client.
for caller in Makefile .github/workflows/release.yml scripts/capture-screenshots.sh; do
    if grep -vE '^[[:space:]]*#' "$caller" | grep -q 'package-app\.sh'; then
        note "$caller must package through scripts/package-with-oauth.sh, not scripts/package-app.sh"
    fi
done
for target in install dmg release; do
    grep -qE "^${target}:" Makefile || note "Makefile must define the $target target"
done
if grep -qE '^\s+@?cp .*Contents/MacOS' Makefile; then
    note "packaging paths must go through scripts/package-with-oauth.sh"
fi
# The client is injected only for the length of a packaging run; a key left in the source
# plist means an interrupted run, and committing it would publish the client.
for key in MailbellGoogleClientID MailbellGoogleClientSecret; do
    if /usr/libexec/PlistBuddy -c "Print :$key" Support/Info.plist >/dev/null 2>&1; then
        note "Support/Info.plist carries $key from an interrupted packaging run; run git checkout -- Support/Info.plist"
    fi
done

# A release tag must be able to match the shipped version.
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
echo "$PLIST_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || note "CFBundleShortVersionString must be X.Y.Z (got $PLIST_VERSION)"

# The changelog is Keep a Changelog, read by the canonical release-notes script;
# its newest version must be the shipped one.
scripts/release-notes.sh --check || note "CHANGELOG.md must pass scripts/release-notes.sh --check"

# The website as one set of pages: the canonical validator owns the shared rules
# (links, breadcrumbs, canonical URLs, sitemap, header and footer parity, asset
# versions). Mailbell's own site rules, which read its own data, follow it.
scripts/validate-site.sh --generated release-notes/ \
    || note "site/ must pass scripts/validate-site.sh"
# The deploy renders the release notes into a staged copy; render them the same
# way so a changelog the renderer cannot read, or a newest version without its
# Sparkle update page, fails here instead of in the deploy.
staged=$(mktemp -d "${TMPDIR:-/tmp}/mailbell-site.XXXXXX")
trap 'rm -rf "$staged"' EXIT
cp -R site "$staged/site"
if scripts/render-release-notes.sh --site "$staged/site" 2>/dev/null; then
    [ -f "$staged/site/release-notes/$PLIST_VERSION/update/index.html" ] \
        || note "the staged site has no release-notes/$PLIST_VERSION/update/index.html"
    scripts/validate-site.sh --site "$staged/site" --generated release-notes/ >/dev/null \
        || note "the staged site with its release notes must pass scripts/validate-site.sh"
else
    note "scripts/render-release-notes.sh could not render the release notes"
fi

# The public beta must be honest about Google's review status everywhere it
# tells users what to expect.
for page in README.md site/index.html site/privacy.html site/terms.html; do
    [ -f "$page" ] || { note "missing public document $page"; continue; }
    grep -qi 'unverified' "$page" \
        || note "$page must disclose the unverified Google OAuth status"
done
grep -qi '100' README.md || note "README must state Google's 100-new-user cap"
# Settings is where a user who opened the DMG directly meets the flow, so the
# same two disclosures have to be there and not only in public copy.
settings_copy=Sources/Mailbell/App/SettingsCopy.swift
if [ -f "$settings_copy" ]; then
    grep -qi 'unverified' "$settings_copy" \
        || note "$settings_copy must disclose the unverified Google OAuth status"
    grep -q '100 new users' "$settings_copy" \
        || note "$settings_copy must state Google's 100-new-user cap"
fi
# An "unlimited" claim is only allowed when it is being denied.
if grep -hiE 'unlimited' README.md site/*.html 2>/dev/null \
    | grep -viE '\b(no|not|never|without|cannot)\b' | grep -q .; then
    note "public copy must not promise unlimited use before Google verification"
fi

# validate-site.sh keeps every page's header and footer equal to index.html's;
# which labels index.html carries is Mailbell's own list.
# The header nav carries this site's own destinations and no outward link; the
# footer carries the outward links and no internal one. Neither repeats the
# other, so a link appears once per page.
# Download is the last item in the header nav, fleet-wide.
expected_navigation="Features|Privacy|Terms|Releases|Download"
expected_footer="Source|Issues"
for page in site/index.html; do
    [ -f "$page" ] || continue
    navigation=$(sed -n '/<nav aria-label="Page sections">/,/<\/nav>/p' "$page" \
        | sed -E 's/<svg[^>]*>.*<\/svg>//g' \
        | sed -E -n 's/.*>([^<]+)<\/a>.*/\1/p' | paste -sd '|' -)
    [ "$navigation" = "$expected_navigation" ] \
        || note "$page navigation must be $expected_navigation (got $navigation)"
    footer=$(sed -n '/<footer class="site-footer">/,/<\/footer>/p' "$page" \
        | sed -E 's/<svg[^>]*>.*<\/svg>//g' \
        | sed -E -n 's/.*>([^<]+)<\/a>.*/\1/p' | paste -sd '|' -)
    [ "$footer" = "$expected_footer" ] \
        || note "$page footer must be $expected_footer (got $footer)"
done
for page in site/index.html site/privacy.html site/terms.html; do
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

# UI text is read from an English-only String Catalog. An entry without an
# English value compiles to nothing (skill-deck#333), so every entry needs one;
# a compiled table is generated at packaging time and never committed.
CATALOG=Support/Localizable.xcstrings
if [ ! -f "$CATALOG" ]; then
    note "$CATALOG is missing"
else
    catalog_problem=$(python3 - "$CATALOG" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        catalog = json.load(f)
except ValueError as error:
    print(f"is not valid JSON ({error})")
    sys.exit()
if catalog.get("sourceLanguage") != "en":
    print(f"source language is {catalog.get('sourceLanguage')!r}, not 'en'")
    sys.exit()
for key, entry in sorted(catalog.get("strings", {}).items()):
    value = entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value")
    if not value:
        print(f"entry {key!r} has no English value")
        break
PY
)
    [ -z "$catalog_problem" ] || note "$CATALOG: $catalog_problem"
fi
if git ls-files 2>/dev/null | grep -qE '^Support/[^/]+\.lproj/Localizable\.strings(dict)?$'; then
    note "compiled Localizable tables are generated by package-app.sh; do not commit them"
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

# The website names the shipped version on its download buttons, so a release
# that forgets the site fails here instead of shipping a page that advertises
# the previous version.
for page in site/index.html; do
    grep -Fq "Download Mailbell $PLIST_VERSION" "$page" \
        || note "$page must name the shipped version on its download button (Download Mailbell $PLIST_VERSION)"
    grep -Fq "href=\"/release-notes/$PLIST_VERSION/\"" "$page" \
        || note "$page release notes link must point at /release-notes/$PLIST_VERSION/"
done

# The 404 page is part of the site, not a bare fallback: same header, same
# footer, same design.
if [ ! -f site/404.html ]; then
    note "website must ship a 404 page"
else
    for marker in 'class="site-header"' 'class="site-footer"' 'styles/main.css'; do
        grep -Fq "$marker" site/404.html || note "site/404.html must carry $marker"
    done
fi

# Every link that leaves the site carries the external-link arrow. validate-site.sh
# owns its target and rel.
while IFS= read -r line; do
    case "$line" in
        *'class="external-icon"'*) ;;
        *) note "external link without the external-link icon: $(printf '%s' "$line" | cut -c1-80)" ;;
    esac
done < <(grep -hoE '<a [^>]*href="https?://[^"]+"[^>]*>[^<]*(<svg[^>]*>.*</svg>)?</a>' \
    site/index.html site/privacy.html site/terms.html site/404.html 2>/dev/null || true)

# The published appcast must describe the shipped app.
if [ -f appcast.xml ]; then
    grep -q '<title>Mailbell</title>' appcast.xml \
        || note "appcast.xml must be Mailbell's feed"
    grep -q 'releases/download/v' appcast.xml \
        || note "appcast enclosures must point at GitHub release assets"
    # Sparkle's update window shows the site's notes page, never GitHub's full
    # release page with its menu and sign-in.
    if grep -q 'releaseNotesLink>https://github.com/' appcast.xml; then
        note "appcast release-notes links must point at the site's release-notes pages, not GitHub"
    fi
fi

if [ "$fail" -eq 0 ]; then
    echo "validate: ok"
else
    echo "validate: FAILED"
    exit 1
fi
