#!/usr/bin/env bash
# Captures the real Settings window for site/screenshots/, with its shadow, corners and elevation,
# through the canonical capture protocol in scripts/lib/capture.sh: the app prints SCALE, WINDOW_ID
# and READY, and the library captures that window on screen and writes lossless WebP.
#
# The capture runs a bundle built from these sources, never the installed app: the flags it relies
# on may not exist in any release yet, and the installed Mailbell shares the owner's Keychain and
# preferences. The throwaway copy gets its own bundle identifier, so it sees no accounts, prompts
# for no Keychain item, and cannot race the real app's notifications. Its preferences are deleted
# on exit.
#
# Accounts is not captured: it shows the connected address, and a published screenshot would carry
# a real person's email.
set -euo pipefail
cd "$(dirname "$0")/.."

. scripts/lib/capture.sh

OUT_DIR=site/screenshots
CAPTURE_BUNDLE_ID=com.martonpaulo.mailbell.capture
PLIST_BUDDY=${PLIST_BUDDY:-/usr/libexec/PlistBuddy}
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

work=$(mktemp -d "${TMPDIR:-/tmp}/mailbell-capture.XXXXXX")
app=$work/Mailbell.app

# Every step tolerates failure: under set -e, one failing step would abort the trap before the
# throwaway preferences are deleted.
cleanup() {
  capture_cleanup
  "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
  rm -rf "$work"
  defaults delete "$CAPTURE_BUNDLE_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

capture_preflight
command -v dwebp >/dev/null 2>&1 || { echo "error: dwebp is required (brew install webp)" >&2; exit 1; }

scripts/package-with-oauth.sh --output "$app" --archive "$work/Mailbell.zip" --identity - --force >/dev/null
"$PLIST_BUDDY" -c "Set :CFBundleIdentifier $CAPTURE_BUNDLE_ID" "$app/Contents/Info.plist"
# Only the outer bundle changed, so only it is re-signed; the nested Sparkle code keeps the
# signatures package-app.sh gave it.
codesign --force --sign - "$app" >/dev/null 2>&1
# Registered with LaunchServices, as any opened app is, so SMAppService finds it and Settings shows
# a fresh install's login-item state instead of a warning. Unregistered again on exit.
"$LSREGISTER" -f "$app" >/dev/null 2>&1 || true

# Writes the narrower widths of an image the page serves through srcset, as <name>-<width>.webp
# next to <name>.webp. Each width is resampled once from the lossless capture. They are
# near-lossless rather than lossless because a resampled screenshot compresses so much worse
# losslessly that a smaller width can outweigh the full-size file; near-lossless keeps every pixel
# within a few levels of the resample, which leaves text edges visibly identical.
#
#   variants <name> <width...>
variants() {
  local name=$1
  shift
  local tmp width
  tmp=$(mktemp -d "$work/variants.XXXXXX")
  dwebp -quiet "$OUT_DIR/$name.webp" -o "$tmp/full.png"
  for width in "$@"; do
    cp "$tmp/full.png" "$tmp/$width.png"
    sips --resampleWidth "$width" "$tmp/$width.png" >/dev/null
    cwebp -quiet -near_lossless 60 -z 9 -metadata none "$tmp/$width.png" -o "$OUT_DIR/$name-$width.webp"
    echo "wrote $OUT_DIR/$name-$width.webp" >&2
  done
}

# The pane index matches the tab order: General 0, Notifications 1, Accounts 2, About 3. Light
# matches the site's default appearance; without the flag Settings follows the operator's system.
capture_pane() {
  capture_window --name "$1" --output-dir "$OUT_DIR" -- \
    "$app/Contents/MacOS/Mailbell" --screenshot-mode --screenshot-pane "$2" --screenshot-appearance light
}
capture_pane general 0
capture_pane notifications 1
capture_pane about 3

# The hero's srcset and imagesrcset in site/index.html list exactly these widths. There is no
# 1200 px width: resampled, it weighs more than the full-size lossless file, so a phone would pay
# more for fewer pixels.
variants general 480 800
