#!/usr/bin/env bash
# Captures the real Settings window, with its shadow, corners and elevation.
#
# The window is captured on screen with `screencapture -l`, never rendered
# offscreen: an offscreen bitmap loses the shadow, the corner radius, the
# material and the elevation, and raising the scale factor does not bring them
# back. `-o` is never passed — that is the flag that strips the shadow.
#
# The app reports its own window id, because Mailbell is an accessory app and
# nothing else can reliably say which window is its.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="${1:-docs/assets/screenshots}"
CAPTURE_BUNDLE_ID="com.perso.mailbell.capture"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Pane index matches the tab order: General, Notifications, Accounts, About.
#
# Accounts is not captured by default: it shows the connected address, and a
# published screenshot would carry a real person's email. Pass it explicitly if
# you have a placeholder account signed in.
PANES="${2:-0 1 3}"
PANE_NAMES=(general notifications accounts about)

# The capture runs a bundle built from these sources, never the installed app:
# the flags it relies on may not exist in any release yet, and the installed
# Mailbell shares the owner's Keychain and preferences. The throwaway copy gets
# its own bundle identifier, so it sees no accounts, prompts for no Keychain
# item, and cannot race the real app's notifications. Its preferences are
# deleted on exit. MAILBELL_APP overrides this for a bundle you built yourself.
CAPTURE_WORK="$(mktemp -d)"
if [[ -n "${MAILBELL_APP:-}" ]]; then
  APP="$MAILBELL_APP"
else
  APP="$CAPTURE_WORK/Mailbell.app"
  Scripts/build_app_bundle.sh --output "$APP" --identity "-" --arch "$(uname -m)" >/dev/null
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $CAPTURE_BUNDLE_ID" "$APP/Contents/Info.plist"
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1
  # Registered with LaunchServices, as any opened app is, so SMAppService finds it
  # and Settings shows a fresh install's login-item state instead of a warning.
  # Unregistered again on exit.
  "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
fi
[[ -d "$APP" ]] || { echo "error: $APP not found" >&2; exit 1; }

# A 1x display silently halves the resolution, so refuse rather than publish a
# degraded image.
backing="$(system_profiler SPDisplaysDataType 2>/dev/null | grep -c "Retina" || true)"
if [[ "$backing" -eq 0 ]]; then
  echo "error: no Retina display found; capture would be half resolution" >&2
  exit 1
fi

command -v cwebp >/dev/null 2>&1 && command -v dwebp >/dev/null 2>&1 || {
  echo "error: cwebp/dwebp not found; install them with 'brew install webp'" >&2
  exit 1
}

# Writes the narrower widths of an image the page serves through srcset, as
# <name>-<width>.webp next to <name>.webp. Each width is resampled once from the
# lossless capture. They are near-lossless rather than lossless because a
# resampled screenshot compresses so much worse losslessly that a smaller width
# can outweigh the full-size file; near-lossless keeps every pixel within a few
# levels of the resample, which leaves text edges visibly identical.
#
#   variants <name> <width...>
variants() {
  local name=$1
  shift
  local tmp
  tmp="$(mktemp -d)"
  dwebp -quiet "$OUT_DIR/$name.webp" -o "$tmp/full.png"
  local width
  for width in "$@"; do
    cp "$tmp/full.png" "$tmp/$width.png"
    sips --resampleWidth "$width" "$tmp/$width.png" >/dev/null
    cwebp -quiet -near_lossless 60 -z 9 -metadata none "$tmp/$width.png" -o "$OUT_DIR/$name-$width.webp"
    echo "wrote $OUT_DIR/$name-$width.webp ($(du -h "$OUT_DIR/$name-$width.webp" | cut -f1))"
  done
  rm -rf "$tmp"
}

mkdir -p "$OUT_DIR"
TMP="$(mktemp -d)"
# Every step here tolerates failure: under set -e, a kill of an app that already
# exited would abort the trap before the throwaway preferences are deleted.
cleanup() {
  if [[ -n "${APP_PID:-}" ]]; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  if [[ -z "${MAILBELL_APP:-}" && -n "${APP:-}" ]]; then
    "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP" "$CAPTURE_WORK"
  [[ -n "${MAILBELL_APP:-}" ]] || defaults delete "$CAPTURE_BUNDLE_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for pane in $PANES; do
  name="${PANE_NAMES[$pane]}"
  pkill -f -- "--screenshot-mode" 2>/dev/null || true
  # Light matches the site's default appearance; without the flag Settings would
  # follow whatever the operator's system uses.
  "$APP/Contents/MacOS/Mailbell" --screenshot-mode --screenshot-pane "$pane" --screenshot-appearance light > "$TMP/out.log" 2>&1 &
  APP_PID=$!

  WINDOW_ID=""
  for _ in $(seq 1 100); do
    if grep -q "MAILBELL_SCREENSHOT_READY" "$TMP/out.log" 2>/dev/null; then
      WINDOW_ID="$(grep "MAILBELL_SCREENSHOT_WINDOW_ID=" "$TMP/out.log" | tail -1 | cut -d= -f2)"
      break
    fi
    sleep 0.2
  done

  [[ -n "$WINDOW_ID" ]] || { echo "error: app did not report a window id" >&2; cat "$TMP/out.log" >&2; exit 1; }

  PNG="$TMP/$name.png"
  screencapture -x -l"$WINDOW_ID" "$PNG"
  [[ -s "$PNG" ]] || { echo "error: capture produced no image for $name" >&2; exit 1; }

  # Lossless WebP: identical pixels, keeps the shadow's alpha, and roughly 70%
  # smaller than the PNG. -z 9 is the slowest, smallest lossless setting.
  cwebp -quiet -lossless -z 9 -metadata none "$PNG" -o "$OUT_DIR/$name.webp"
  echo "wrote $OUT_DIR/$name.webp ($(du -h "$OUT_DIR/$name.webp" | cut -f1))"
  kill "$APP_PID" 2>/dev/null || true
done

# The hero's srcset and imagesrcset in docs/index.html list exactly these
# widths. There is no 1200 px width: resampled, it weighs more than the
# full-size lossless file, so a phone would pay more for fewer pixels.
if [[ " $PANES " == *" 0 "* ]]; then
  variants general 480 800
fi
