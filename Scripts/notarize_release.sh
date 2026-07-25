#!/usr/bin/env bash
# Submits an artifact to the Apple notary service. A DMG is stapled and
# Gatekeeper-assessed in place; a ZIP is only a transport container, so the
# caller staples the .app it was made from afterwards.
#
# Usage: Scripts/notarize_release.sh <release.dmg|release.zip>
set -euo pipefail

usage() {
  echo "usage: $0 <release.dmg|release.zip>" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

TARGET_PATH="$1"
if [[ ! -f "${TARGET_PATH}" ]]; then
  echo "error: missing artifact ${TARGET_PATH}" >&2
  exit 1
fi
TARGET_DIR="$(cd "$(dirname "${TARGET_PATH}")" && pwd -P)"
TARGET_PATH="${TARGET_DIR}/$(basename "${TARGET_PATH}")"

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

echo "Submitting $(basename "${TARGET_PATH}") to the Apple notary service with Keychain profile '${MAILBELL_NOTARY_KEYCHAIN_PROFILE}'."
if xcrun notarytool submit "${TARGET_PATH}" \
  --keychain-profile "${MAILBELL_NOTARY_KEYCHAIN_PROFILE}" \
  --wait 2>&1 | tee "${LOG_FILE}"; then
  if ! grep -q "status: Accepted" "${LOG_FILE}"; then
    echo "error: notarization did not reach Accepted; log kept at ${LOG_FILE}" >&2
    exit 1
  fi
  rm -f "${LOG_FILE}"
  rmdir artifacts/notarization 2>/dev/null || true
else
  echo "error: notarization failed; log kept at ${LOG_FILE}" >&2
  exit 1
fi

case "${TARGET_PATH}" in
  *.dmg)
    echo "Stapling notarization ticket to ${TARGET_PATH}."
    xcrun stapler staple "${TARGET_PATH}"

    echo "Validating stapled DMG."
    xcrun stapler validate "${TARGET_PATH}"
    spctl -a -t open --context context:primary-signature -vv "${TARGET_PATH}"
    hdiutil verify "${TARGET_PATH}" >/dev/null

    echo "Notarized and stapled DMG: ${TARGET_PATH}"
    ;;
  *)
    echo "Notarized archive: ${TARGET_PATH} (the caller staples the .app it contains)"
    ;;
esac
