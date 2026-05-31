#!/usr/bin/env bash
# Regenerate AppIcon.appiconset PNGs and Resources/AppIcon.icns from Resources/logo.png.
set -euo pipefail

cd "$(dirname "$0")/.."

MASTER="Resources/logo.png"
APPICONSET="Resources/Assets.xcassets/AppIcon.appiconset"
ICNS="Resources/AppIcon.icns"
WORK="build/icon-gen"

if [[ ! -f "${MASTER}" ]]; then
  echo "error: missing ${MASTER}" >&2
  exit 1
fi

mkdir -p "${APPICONSET}" "${WORK}"

MASTER_1024="${WORK}/master-1024.png"
sips -z 1024 1024 "${MASTER}" --out "${MASTER_1024}" >/dev/null

render() {
  local name="$1"
  local size="$2"
  sips -z "${size}" "${size}" "${MASTER_1024}" --out "${APPICONSET}/${name}" >/dev/null
}

render icon_16x16.png 16
render icon_16x16@2x.png 32
render icon_32x32.png 32
render icon_32x32@2x.png 64
render icon_128x128.png 128
render icon_128x128@2x.png 256
render icon_256x256.png 256
render icon_256x256@2x.png 512
render icon_512x512.png 512
render icon_512x512@2x.png 1024

ICONSET="${WORK}/AppIcon.iconset"
rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"
cp "${APPICONSET}"/icon_*.png "${ICONSET}/"

iconutil -c icns "${ICONSET}" -o "${ICNS}"
rm -rf "${WORK}"

echo "App icons regenerated from ${MASTER}"
