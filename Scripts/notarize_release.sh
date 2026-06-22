#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <release.dmg>" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

DMG_PATH="$1"
if [[ ! -f "${DMG_PATH}" ]]; then
  echo "error: missing DMG ${DMG_PATH}" >&2
  exit 1
fi
DMG_DIR="$(cd "$(dirname "${DMG_PATH}")" && pwd -P)"
DMG_PATH="${DMG_DIR}/$(basename "${DMG_PATH}")"

cd "$(dirname "$0")/.."
source Scripts/mailbell_env.sh
mailbell_load_dotenv

if [[ -z "${MAILBELL_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  echo "error: set MAILBELL_NOTARY_KEYCHAIN_PROFILE in .env or your shell" >&2
  echo "hint: run make setup-release-signing once on the release Mac" >&2
  exit 1
fi

mkdir -p artifacts/notarization
LOG_FILE="artifacts/notarization/notarytool-$(date +%Y%m%d-%H%M%S).log"

echo "Submitting DMG to Apple notary service with Keychain profile '${MAILBELL_NOTARY_KEYCHAIN_PROFILE}'."
if xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile "${MAILBELL_NOTARY_KEYCHAIN_PROFILE}" \
  --wait 2>&1 | tee "${LOG_FILE}"; then
  rm -f "${LOG_FILE}"
  rmdir artifacts/notarization artifacts 2>/dev/null || true
else
  echo "error: notarization failed; log kept at ${LOG_FILE}" >&2
  exit 1
fi

echo "Stapling notarization ticket to ${DMG_PATH}."
xcrun stapler staple "${DMG_PATH}"

echo "Validating stapled DMG."
xcrun stapler validate "${DMG_PATH}"
spctl -a -t open --context context:primary-signature -vv "${DMG_PATH}"
hdiutil verify "${DMG_PATH}" >/dev/null

echo "Notarized and stapled DMG: ${DMG_PATH}"
