#!/usr/bin/env bash
# Assembles a runnable Mailbell.app: release binary, Info.plist with injected
# bundle/OAuth/release metadata, compiled asset catalog, and the embedded
# Sparkle framework with the nested-signing order Sparkle requires.
#
# Every packaging path (install, dmg, release) goes through this script so the
# bundle layout and signing order have exactly one definition.
#
# Usage:
#   Scripts/build_app_bundle.sh --output <Mailbell.app> [options]
# Options:
#   --identity <id>       codesign identity; "-" (default) is ad-hoc
#   --version <X.Y.Z>     release short version (requires --build-number)
#   --build-number <N>    release build number (requires --version)
#   --arch <arch>         build architecture (default arm64)
#   --hardened            add --timestamp --options runtime (Developer ID only)
set -euo pipefail
cd "$(dirname "$0")/.."

APP=""
IDENTITY="-"
VERSION=""
BUILD_NUMBER=""
ARCH="arm64"
HARDENED=0
PRODUCT="mailbell"
APP_NAME="Mailbell"

usage() {
  echo "usage: $0 --output <Mailbell.app> [--identity <id>] [--version X.Y.Z --build-number N] [--arch <arch>] [--hardened]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) APP="${2:?}"; shift 2 ;;
    --identity) IDENTITY="${2:?}"; shift 2 ;;
    --version) VERSION="${2:?}"; shift 2 ;;
    --build-number) BUILD_NUMBER="${2:?}"; shift 2 ;;
    --arch) ARCH="${2:?}"; shift 2 ;;
    --hardened) HARDENED=1; shift ;;
    *) usage; exit 2 ;;
  esac
done

[[ -n "$APP" ]] || { usage; exit 2; }
if [[ -n "$VERSION" && -z "$BUILD_NUMBER" ]] || [[ -z "$VERSION" && -n "$BUILD_NUMBER" ]]; then
  echo "error: --version and --build-number must be provided together" >&2
  exit 2
fi

swift build -c release --arch "$ARCH" --product "$PRODUCT" >/dev/null
BIN_PATH="$(swift build -c release --arch "$ARCH" --product "$PRODUCT" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_PATH/$PRODUCT" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ -n "$VERSION" ]]; then
  Scripts/inject_bundle_config.sh --version "$VERSION" --build-number "$BUILD_NUMBER" \
    "$APP/Contents/Info.plist" >/dev/null
else
  Scripts/inject_bundle_config.sh "$APP/Contents/Info.plist" >/dev/null
fi

xcrun actool --compile "$APP/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 26.0 \
  --app-icon AppIcon \
  --output-partial-info-plist /dev/null \
  Resources/Assets.xcassets >/dev/null

# ditto preserves the framework's symlink structure; cp -R would break it and
# Sparkle's signature with it.
SPARKLE_FRAMEWORK="$BIN_PATH/Sparkle.framework"
[[ -d "$SPARKLE_FRAMEWORK" ]] || { echo "error: Sparkle.framework not found at $SPARKLE_FRAMEWORK" >&2; exit 1; }
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

SIGN_FLAGS=(--force --sign "$IDENTITY")
if [[ "$HARDENED" -eq 1 ]]; then
  SIGN_FLAGS+=(--timestamp --options runtime)
fi

# Nested code first (Sparkle's XPC helpers and updater app), then the
# framework, then the app itself.
SPARKLE_VERSIONS="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE_VERSIONS/XPCServices/Downloader.xpc"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE_VERSIONS/XPCServices/Installer.xpc"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE_VERSIONS/Autoupdate"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE_VERSIONS/Updater.app"
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"

echo "built $APP (identity: $IDENTITY${VERSION:+, version $VERSION build $BUILD_NUMBER})"
