#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 <staging-dir> <app-name> <app-icon.icns> <volume-name> <output.dmg>" >&2
  exit 2
fi

absolute_path() {
  local path="$1"
  local dir
  local base
  dir="$(dirname "${path}")"
  base="$(basename "${path}")"
  printf '%s/%s\n' "$(cd "${dir}" && pwd -P)" "${base}"
}

STAGING_DIR="$(absolute_path "$1")"
APP_NAME="$2"
APP_ICON="$(absolute_path "$3")"
VOLUME_NAME="$4"
OUTPUT_DMG="$5"

if [[ ! -d "${STAGING_DIR}/${APP_NAME}.app" ]]; then
  echo "error: missing ${STAGING_DIR}/${APP_NAME}.app" >&2
  exit 1
fi

if [[ ! -L "${STAGING_DIR}/Applications" ]]; then
  echo "error: missing Applications shortcut in ${STAGING_DIR}" >&2
  exit 1
fi

if [[ ! -f "${APP_ICON}" ]]; then
  echo "error: missing app icon ${APP_ICON}" >&2
  exit 1
fi

if [[ -z "${VOLUME_NAME}" || "${VOLUME_NAME}" == */* ]]; then
  echo "error: volume name must be a non-empty Finder-safe name" >&2
  exit 1
fi

if [[ "${OUTPUT_DMG}" != *.dmg ]]; then
  echo "error: output path must end in .dmg" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_DMG}")"
OUTPUT_DMG="$(absolute_path "${OUTPUT_DMG}")"

WORK_DIR="$(dirname "${STAGING_DIR}")"
RW_DMG="${WORK_DIR}/${VOLUME_NAME}.rw.dmg"
MOUNT_DIR="${WORK_DIR}/mount"
SETFILE="${SETFILE:-/usr/bin/SetFile}"
DEVICE=""

detach_image() {
  if [[ -n "${DEVICE}" ]]; then
    hdiutil detach "${DEVICE}" >/dev/null 2>&1 || hdiutil detach -force "${DEVICE}" >/dev/null 2>&1 || true
    DEVICE=""
  fi
}

cleanup() {
  local status=$?
  detach_image
  rmdir "${MOUNT_DIR}" >/dev/null 2>&1 || true
  rm -f "${RW_DMG}"
  exit "${status}"
}

trap cleanup EXIT INT TERM

layout_finder_window() {
  osascript - "${MOUNT_DIR}" "${APP_NAME}" <<'APPLESCRIPT'
on run argv
  set mountPath to item 1 of argv
  set appName to item 2 of argv
  set appBundleName to appName & ".app"
  set volumeRoot to POSIX file mountPath as alias

  tell application "Finder"
    open volumeRoot
    set dmgWindow to container window of volumeRoot
    set current view of dmgWindow to icon view
    set toolbar visible of dmgWindow to false
    set statusbar visible of dmgWindow to false
    set bounds of dmgWindow to {120, 120, 640, 430}

    set viewOptions to icon view options of dmgWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13

    set position of item appBundleName of volumeRoot to {170, 165}
    set position of item "Applications" of volumeRoot to {410, 165}
    update volumeRoot without registering applications
    delay 0.5
    close dmgWindow
  end tell
end run
APPLESCRIPT
}

rm -rf "${MOUNT_DIR}"
mkdir -p "${MOUNT_DIR}" "$(dirname "${OUTPUT_DMG}")"
rm -f "${RW_DMG}" "${OUTPUT_DMG}"

hdiutil create \
  -srcfolder "${STAGING_DIR}" \
  -volname "${VOLUME_NAME}" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "${RW_DMG}" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen -mountpoint "${MOUNT_DIR}" "${RW_DMG}")"
DEVICE="$(printf '%s\n' "${ATTACH_OUTPUT}" | awk '/^\/dev\/disk/ { print $1; exit }')"

if [[ -z "${DEVICE}" ]]; then
  echo "error: could not attach writable DMG" >&2
  exit 1
fi

if [[ -z "${MAILBELL_SKIP_DMG_FINDER_LAYOUT:-}" ]]; then
  if ! layout_finder_window; then
    echo "warning: Finder layout could not be customized; DMG contents are still installable" >&2
  fi
fi

cp "${APP_ICON}" "${MOUNT_DIR}/.VolumeIcon.icns"

if [[ -x "${SETFILE}" ]]; then
  "${SETFILE}" -a C "${MOUNT_DIR}"
else
  echo "warning: SetFile not found; mounted DMG volume will use the default disk icon" >&2
fi

if [[ ! -f "${MOUNT_DIR}/.VolumeIcon.icns" ]]; then
  echo "error: failed to apply DMG volume icon" >&2
  exit 1
fi

sync
detach_image

hdiutil convert "${RW_DMG}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "${OUTPUT_DMG}" >/dev/null

hdiutil verify "${OUTPUT_DMG}" >/dev/null
