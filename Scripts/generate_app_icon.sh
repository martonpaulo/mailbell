#!/usr/bin/env bash
# Regenerate AppIcon.appiconset PNGs and Resources/AppIcon.icns from Resources/logo.png.
set -euo pipefail

cd "$(dirname "$0")/.."

MASTER="Resources/logo.png"
APPICONSET="Resources/Assets.xcassets/AppIcon.appiconset"
ICNS="Resources/AppIcon.icns"
WORK_ROOT=".build/icon-gen"

if [[ ! -f "${MASTER}" ]]; then
  echo "error: missing ${MASTER}" >&2
  exit 1
fi

mkdir -p "${APPICONSET}" "${WORK_ROOT}"
WORK="$(mktemp -d "${WORK_ROOT}/work.XXXXXX")"

cleanup() {
  rm -rf "${WORK}"
}

trap cleanup EXIT INT TERM

GENERATED_APPICONSET="${WORK}/AppIcon.appiconset"
mkdir -p "${GENERATED_APPICONSET}"

MASTER_1024="${WORK}/master-1024.png"
sips -z 1024 1024 "${MASTER}" --out "${MASTER_1024}" >/dev/null

render() {
  local name="$1"
  local size="$2"
  sips -z "${size}" "${size}" "${MASTER_1024}" --out "${GENERATED_APPICONSET}/${name}" >/dev/null
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
mkdir -p "${ICONSET}"
cp "${GENERATED_APPICONSET}"/icon_*.png "${ICONSET}/"

GENERATED_ICNS="${WORK}/AppIcon.icns"
iconutil -c icns "${ICONSET}" -o "${GENERATED_ICNS}"

changed=0
unchanged=0

install_if_changed() {
  local source_path="$1"
  local destination_path="$2"

  if [[ -f "${destination_path}" ]] && cmp -s "${source_path}" "${destination_path}"; then
    unchanged=$((unchanged + 1))
    return
  fi

  cp "${source_path}" "${destination_path}"
  changed=$((changed + 1))
  printf 'Updated %s\n' "${destination_path}"
}

for generated_png in "${GENERATED_APPICONSET}"/icon_*.png; do
  install_if_changed "${generated_png}" "${APPICONSET}/$(basename "${generated_png}")"
done

install_if_changed "${GENERATED_ICNS}" "${ICNS}"

printf 'App icons checked from %s: %d changed, %d unchanged\n' "${MASTER}" "${changed}" "${unchanged}"
