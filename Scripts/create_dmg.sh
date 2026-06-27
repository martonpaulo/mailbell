#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 <staging-dir> <app-name> <installer-icon.icns> <volume-name> <output.dmg>" >&2
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
INSTALLER_ICON="$(absolute_path "$3")"
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

if [[ ! -f "${INSTALLER_ICON}" ]]; then
  echo "error: missing installer icon ${INSTALLER_ICON}" >&2
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
MOUNT_DIR=""
SETFILE="${SETFILE:-/usr/bin/SetFile}"
SWIFT_TOOL="${SWIFT:-swift}"
WINDOW_WIDTH=900
WINDOW_HEIGHT=540
CARD_MARGIN_X=58
CARD_Y=156
CARD_HEIGHT=284
CARD_WIDTH=$((WINDOW_WIDTH - (CARD_MARGIN_X * 2)))
ICON_ROW_VISUAL_OFFSET=20
ICON_COLUMN_INSET=16
APP_POSITION_X=$((CARD_MARGIN_X + (CARD_WIDTH / 4) + ICON_COLUMN_INSET))
APP_POSITION_Y=$((WINDOW_HEIGHT - CARD_Y - (CARD_HEIGHT / 2) - ICON_ROW_VISUAL_OFFSET))
APPLICATIONS_POSITION_X=$((CARD_MARGIN_X + ((CARD_WIDTH * 3) / 4) - ICON_COLUMN_INSET))
APPLICATIONS_POSITION_Y="${APP_POSITION_Y}"
HIDDEN_POSITION_X=120
HIDDEN_POSITION_Y=650
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
  rm -f "${RW_DMG}"
  exit "${status}"
}

trap cleanup EXIT INT TERM

generate_background_image() {
  local output_path="$1"

  "${SWIFT_TOOL}" - \
    "${output_path}" \
    "${APP_NAME}" \
    "${INSTALLER_ICON}" \
    "${WINDOW_WIDTH}" \
    "${WINDOW_HEIGHT}" \
    "${CARD_MARGIN_X}" \
    "${CARD_Y}" \
    "${CARD_HEIGHT}" \
    "${APP_POSITION_X}" \
    "${APP_POSITION_Y}" \
    "${APPLICATIONS_POSITION_X}" \
    "${APPLICATIONS_POSITION_Y}" <<'SWIFT'
import AppKit

let args = CommandLine.arguments
let outputPath = args[1]
let appName = args[2]
let appIconPath = args[3]
let width = Int(args[4]) ?? 900
let height = Int(args[5]) ?? 540
let cardMarginX = CGFloat(Int(args[6]) ?? 58)
let cardY = CGFloat(Int(args[7]) ?? 156)
let cardHeight = CGFloat(Int(args[8]) ?? 284)
let appX = CGFloat(Int(args[9]) ?? 270)
let appY = CGFloat(Int(args[10]) ?? 222)
let applicationsX = CGFloat(Int(args[11]) ?? 630)
let applicationsY = CGFloat(Int(args[12]) ?? 222)

func color(_ hex: Int, alpha: CGFloat = 1.0) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255.0,
        green: CGFloat((hex >> 8) & 0xff) / 255.0,
        blue: CGFloat(hex & 0xff) / 255.0,
        alpha: alpha
    )
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.cgContext.setShouldAntialias(true)

let bounds = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(colors: [
    color(0xFFF8D7),
    color(0xFFE5A1),
    color(0xBFE9F3)
])?.draw(in: bounds, angle: -35)

if let iconImage = NSImage(contentsOfFile: appIconPath) {
    iconImage.draw(
        in: NSRect(x: -92, y: -150, width: 440, height: 440),
        from: .zero,
        operation: .sourceOver,
        fraction: 0.10
    )
}

let card = NSRect(x: cardMarginX, y: cardY, width: CGFloat(width) - (cardMarginX * 2), height: cardHeight)
let shadow = NSShadow()
shadow.shadowColor = color(0x5F4E1E, alpha: 0.18)
shadow.shadowBlurRadius = 26
shadow.shadowOffset = NSSize(width: 0, height: -9)
shadow.set()

let cardPath = NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18)
color(0xFFFDF4).setFill()
cardPath.fill()
NSShadow().set()
color(0xFFFFFF, alpha: 0.70).setStroke()
cardPath.lineWidth = 1
cardPath.stroke()

let arrow = NSBezierPath()
let arrowY = CGFloat(height) - ((appY + applicationsY) / 2)
let arrowStartX = appX + 128
let arrowEndX = applicationsX - 118
arrow.move(to: NSPoint(x: arrowStartX, y: arrowY))
arrow.line(to: NSPoint(x: arrowEndX, y: arrowY))
arrow.lineWidth = 8
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
color(0xD89B00).setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: arrowEndX, y: arrowY))
arrowHead.line(to: NSPoint(x: arrowEndX - 24, y: arrowY + 24))
arrowHead.move(to: NSPoint(x: arrowEndX, y: arrowY))
arrowHead.line(to: NSPoint(x: arrowEndX - 24, y: arrowY - 24))
arrowHead.lineWidth = 8
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
color(0xD89B00).setStroke()
arrowHead.stroke()

let title = "Drag \(appName) to Applications" as NSString
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 32, weight: .bold),
    .foregroundColor: color(0x2B2517),
    .paragraphStyle: paragraph
]
title.draw(
    in: NSRect(x: 0, y: 74, width: width, height: 46),
    withAttributes: titleAttributes
)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("error: could not render DMG background\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
SWIFT
}

apply_file_icon() {
  local target_path="$1"

  "${SWIFT_TOOL}" - "${INSTALLER_ICON}" "${target_path}" <<'SWIFT'
import AppKit

let args = CommandLine.arguments
let iconPath = args[1]
let targetPath = args[2]

guard let image = NSImage(contentsOfFile: iconPath) else {
    fputs("error: could not read icon at \(iconPath)\n", stderr)
    exit(1)
}

if !NSWorkspace.shared.setIcon(image, forFile: targetPath, options: []) {
    fputs("error: could not apply custom icon to \(targetPath)\n", stderr)
    exit(1)
}
SWIFT
}

ensure_dmgbuild_tools() {
  local tool_dir="${DMGBUILD_TOOL_DIR:-$(dirname "${WORK_DIR}")/dmg-python-tools}"

  if PYTHONPATH="${tool_dir}${PYTHONPATH:+:${PYTHONPATH}}" python3 - <<'PY' >/dev/null 2>&1
import dmgbuild
PY
  then
    printf '%s\n' "${tool_dir}"
    return
  fi

  printf "Installing local DMG layout tool into %s\n" "${tool_dir}" >&2
  rm -rf "${tool_dir}"
  python3 -m pip install \
    --disable-pip-version-check \
    --quiet \
    --target "${tool_dir}" \
    "dmgbuild==1.6.5"
  printf '%s\n' "${tool_dir}"
}

write_dmgbuild_settings() {
  local settings_path="$1"
  local background_path="$2"

  python3 - \
    "${settings_path}" \
    "${STAGING_DIR}/${APP_NAME}.app" \
    "${INSTALLER_ICON}" \
    "${background_path}" \
    "${APP_NAME}" \
    "${WINDOW_WIDTH}" \
    "${WINDOW_HEIGHT}" \
    "${APP_POSITION_X}" \
    "${APP_POSITION_Y}" \
    "${APPLICATIONS_POSITION_X}" \
    "${APPLICATIONS_POSITION_Y}" \
    "${HIDDEN_POSITION_X}" \
    "${HIDDEN_POSITION_Y}" <<'PY'
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
app_bundle = sys.argv[2]
app_icon = sys.argv[3]
background = sys.argv[4]
app_name = sys.argv[5]
window_width = int(sys.argv[6])
window_height = int(sys.argv[7])
app_x = int(sys.argv[8])
app_y = int(sys.argv[9])
applications_x = int(sys.argv[10])
applications_y = int(sys.argv[11])
hidden_x = int(sys.argv[12])
hidden_y = int(sys.argv[13])

settings_path.write_text(
    f"""\
import os
import shutil

files = [{app_bundle!r}]
symlinks = {{"Applications": "/Applications"}}
icon = {app_icon!r}
background = {background!r}
format = "UDZO"
compression_level = 9
filesystem = "HFS+"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((120, 120), ({window_width}, {window_height}))
default_view = "icon-view"
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100.0
scroll_position = (0.0, 0.0)
show_icon_preview = False
show_item_info = False
label_pos = "bottom"
text_size = 13.0
icon_size = 128.0
icon_locations = {{
    "{app_name}.app": ({app_x}, {app_y}),
    "Applications": ({applications_x}, {applications_y}),
    ".background.png": ({hidden_x}, {hidden_y}),
    ".VolumeIcon.icns": ({hidden_x + 180}, {hidden_y}),
}}
hide = [".background.png", ".VolumeIcon.icns"]

def create_hook(mount_point, options):
    shutil.rmtree(os.path.join(mount_point, ".fseventsd"), ignore_errors=True)
""",
    encoding="utf-8",
)
PY
}

create_dmg_with_dmgbuild() {
  local tool_dir
  local background_path="${WORK_DIR}/background.png"
  local settings_path="${WORK_DIR}/dmgbuild_settings.py"

  mkdir -p "${WORK_DIR}" "$(dirname "${OUTPUT_DMG}")"
  rm -f "${OUTPUT_DMG}"
  generate_background_image "${background_path}"
  write_dmgbuild_settings "${settings_path}" "${background_path}"
  tool_dir="$(ensure_dmgbuild_tools)"

  PYTHONPATH="${tool_dir}${PYTHONPATH:+:${PYTHONPATH}}" \
    python3 -m dmgbuild \
      "${VOLUME_NAME}" \
      "${OUTPUT_DMG}" \
      --settings "${settings_path}" \
      --no-hidpi

  apply_file_icon "${OUTPUT_DMG}"
  hdiutil verify "${OUTPUT_DMG}" >/dev/null
}

hide_in_finder() {
  local path="$1"

  chflags hidden "${path}" >/dev/null 2>&1 || true
  if [[ -x "${SETFILE}" ]]; then
    "${SETFILE}" -a V "${path}" >/dev/null 2>&1 || true
  fi
}

layout_finder_window() {
  local background_path="${MOUNT_DIR}/.background/background.png"

  osascript - "${MOUNT_DIR}" \
    "${VOLUME_NAME}" \
    "${APP_NAME}" \
    "${background_path}" \
    "${WINDOW_WIDTH}" \
    "${WINDOW_HEIGHT}" \
    "${APP_POSITION_X}" \
    "${APP_POSITION_Y}" \
    "${APPLICATIONS_POSITION_X}" \
    "${APPLICATIONS_POSITION_Y}" \
    "${HIDDEN_POSITION_X}" \
    "${HIDDEN_POSITION_Y}" <<'APPLESCRIPT'
on run argv
  set mountPath to item 1 of argv
  set volumeName to item 2 of argv
  set appName to item 3 of argv
  set windowWidth to (item 5 of argv) as integer
  set windowHeight to (item 6 of argv) as integer
  set appX to (item 7 of argv) as integer
  set appY to (item 8 of argv) as integer
  set applicationsX to (item 9 of argv) as integer
  set applicationsY to (item 10 of argv) as integer
  set hiddenX to (item 11 of argv) as integer
  set hiddenY to (item 12 of argv) as integer
  set appBundleName to appName & ".app"

  tell application "Finder"
    set volumeRoot to disk volumeName
    set backgroundFile to file "background.png" of folder ".background" of volumeRoot
    open volumeRoot
    set dmgWindow to container window of volumeRoot
    set current view of dmgWindow to icon view
    set toolbar visible of dmgWindow to false
    set statusbar visible of dmgWindow to false
    set bounds of dmgWindow to {120, 120, 120 + windowWidth, 120 + windowHeight}

    set viewOptions to icon view options of dmgWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to backgroundFile

    set position of item appBundleName of volumeRoot to {appX, appY}
    set position of item "Applications" of volumeRoot to {applicationsX, applicationsY}
    my parkHiddenItem(".background", volumeRoot, hiddenX, hiddenY)
    my parkHiddenItem(".VolumeIcon.icns", volumeRoot, hiddenX + 180, hiddenY)
    my parkHiddenItem(".fseventsd", volumeRoot, hiddenX + 360, hiddenY)
    update volumeRoot without registering applications
    delay 1
    close dmgWindow
  end tell
end run

on parkHiddenItem(itemName, volumeRoot, hiddenX, hiddenY)
  tell application "Finder"
    try
      set position of item itemName of volumeRoot to {hiddenX, hiddenY}
    end try
  end tell
end parkHiddenItem
APPLESCRIPT
}

if [[ -z "${MAILBELL_USE_FINDER_DMG_LAYOUT:-}" ]]; then
  create_dmg_with_dmgbuild
  exit 0
fi

mkdir -p "$(dirname "${OUTPUT_DMG}")"
rm -f "${RW_DMG}" "${OUTPUT_DMG}"

hdiutil create \
  -srcfolder "${STAGING_DIR}" \
  -volname "${VOLUME_NAME}" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "${RW_DMG}" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "${RW_DMG}")"
DEVICE="$(printf '%s\n' "${ATTACH_OUTPUT}" | awk '/^\/dev\/disk/ { print $1; exit }')"
MOUNT_DIR="$(printf '%s\n' "${ATTACH_OUTPUT}" | awk '/\/Volumes\// { for (i = 3; i <= NF; i++) { printf "%s%s", (i == 3 ? "" : " "), $i } print ""; exit }')"

if [[ -z "${DEVICE}" ]]; then
  echo "error: could not attach writable DMG" >&2
  exit 1
fi

if [[ -z "${MOUNT_DIR}" || ! -d "${MOUNT_DIR}" ]]; then
  echo "error: could not find mounted DMG volume" >&2
  exit 1
fi

mkdir -p "${MOUNT_DIR}/.background"
generate_background_image "${MOUNT_DIR}/.background/background.png"
cp "${INSTALLER_ICON}" "${MOUNT_DIR}/.VolumeIcon.icns"
hide_in_finder "${MOUNT_DIR}/.background"
hide_in_finder "${MOUNT_DIR}/.background/background.png"
hide_in_finder "${MOUNT_DIR}/.VolumeIcon.icns"

if [[ -z "${MAILBELL_SKIP_DMG_FINDER_LAYOUT:-}" ]]; then
  if ! layout_finder_window; then
    echo "warning: Finder layout could not be customized; DMG contents are still installable" >&2
  fi
fi

if [[ ! -f "${MOUNT_DIR}/.VolumeIcon.icns" ]]; then
  cp "${INSTALLER_ICON}" "${MOUNT_DIR}/.VolumeIcon.icns"
  hide_in_finder "${MOUNT_DIR}/.VolumeIcon.icns"
fi

if [[ -x "${SETFILE}" ]]; then
  "${SETFILE}" -a C "${MOUNT_DIR}"
else
  echo "warning: SetFile not found; mounted DMG volume will use the default disk icon" >&2
fi

if [[ ! -f "${MOUNT_DIR}/.VolumeIcon.icns" ]]; then
  echo "error: failed to apply DMG volume icon" >&2
  exit 1
fi

rm -rf "${MOUNT_DIR}/.fseventsd"
sync
detach_image

hdiutil convert "${RW_DMG}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "${OUTPUT_DMG}" >/dev/null

apply_file_icon "${OUTPUT_DMG}"
hdiutil verify "${OUTPUT_DMG}" >/dev/null
