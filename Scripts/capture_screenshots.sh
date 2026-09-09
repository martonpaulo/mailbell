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

APP="${MAILBELL_APP:-/Applications/Mailbell.app}"
OUT_DIR="${1:-docs/assets/screenshots}"
# Pane index matches the tab order: General, Notifications, Accounts, About.
#
# Accounts is not captured by default: it shows the connected address, and a
# published screenshot would carry a real person's email. Pass it explicitly if
# you have a placeholder account signed in.
PANES="${2:-0 1 3}"
PANE_NAMES=(general notifications accounts about)

[[ -d "$APP" ]] || { echo "error: $APP not found; run make install first" >&2; exit 1; }

# A 1x display silently halves the resolution, so refuse rather than publish a
# degraded image.
backing="$(system_profiler SPDisplaysDataType 2>/dev/null | grep -c "Retina" || true)"
if [[ "$backing" -eq 0 ]]; then
  echo "error: no Retina display found; capture would be half resolution" >&2
  exit 1
fi

command -v cwebp >/dev/null 2>&1 || {
  echo "error: cwebp not found; install it with 'brew install webp'" >&2
  exit 1
}

mkdir -p "$OUT_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; [[ -n "${APP_PID:-}" ]] && kill "$APP_PID" 2>/dev/null || true' EXIT

for pane in $PANES; do
  name="${PANE_NAMES[$pane]}"
  pkill -f -- "--screenshot-mode" 2>/dev/null || true
  "$APP/Contents/MacOS/Mailbell" --screenshot-mode --screenshot-pane "$pane" > "$TMP/out.log" 2>&1 &
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
  # smaller than the PNG.
  cwebp -quiet -lossless -alpha_q 100 "$PNG" -o "$OUT_DIR/$name.webp"
  echo "wrote $OUT_DIR/$name.webp ($(du -h "$OUT_DIR/$name.webp" | cut -f1))"
  kill "$APP_PID" 2>/dev/null || true
done
