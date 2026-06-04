#!/usr/bin/env bash
# Assembles a Mailbell.app bundle from the SwiftPM build so that macOS features
# requiring a bundle identifier (notifications, login item) work.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="release"
BUNDLE_ID="com.samzong.mailbell"
APP_NAME="Mailbell"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
ASSETS="Resources/Assets.xcassets"

echo "Generating app icons…"
chmod +x Scripts/generate_app_icon.sh
Scripts/generate_app_icon.sh

echo "Building (${CONFIG})…"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/mailbell"
if [[ ! -f "${BIN_PATH}" ]]; then
  echo "error: built binary not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
Scripts/inject_oauth_config.sh "${APP_DIR}/Contents/Info.plist"

xcrun actool --compile "${APP_DIR}/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --app-icon AppIcon \
  --output-partial-info-plist /dev/null \
  "${ASSETS}" >/dev/null

echo "Ad-hoc signing…"
codesign --force --deep --sign - "${APP_DIR}" || \
  echo "warning: ad-hoc signing failed; notifications may not work until signed."

echo "Done: ${APP_DIR}"
echo "Run with: open ${APP_DIR}"
