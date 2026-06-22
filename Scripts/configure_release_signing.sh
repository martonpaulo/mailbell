#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source Scripts/mailbell_env.sh
mailbell_load_dotenv

DEFAULT_NOTARY_PROFILE="mailbell-notary"

echo "Available Developer ID Application certificates:"

identities=()
while IFS= read -r identity; do
  identities+=("${identity}")
done < <(
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/^[[:space:]]*[0-9]+\)[[:space:]]+[A-Fa-f0-9]+[[:space:]]+"([^"]+)".*/\1/p' \
    | grep '^Developer ID Application:' || true
)

if [[ ${#identities[@]} -eq 0 ]]; then
  echo "  No Developer ID Application identities were found in your keychains."
  echo "  Create/import one in Xcode or Apple Developer Certificates before release signing."
else
  for index in "${!identities[@]}"; do
    printf '  %d) %s\n' "$((index + 1))" "${identities[index]}"
  done
fi

current_identity="${MAILBELL_CODE_SIGN_IDENTITY:-}"
if [[ -n "${current_identity}" ]]; then
  printf '\nCurrent .env signing identity: %s\n' "${current_identity}"
fi

printf '\nEnter a number from the list or paste the exact Developer ID Application identity'
if [[ -n "${current_identity}" ]]; then
  printf ' [press Return to keep current]'
fi
printf ': '
IFS= read -r identity_choice

identity_choice="$(mailbell_trim "${identity_choice}")"
if [[ -z "${identity_choice}" && -n "${current_identity}" ]]; then
  selected_identity="${current_identity}"
elif [[ "${identity_choice}" =~ ^[0-9]+$ ]] \
  && [[ "${identity_choice}" -ge 1 ]] \
  && [[ "${identity_choice}" -le ${#identities[@]} ]]; then
  selected_identity="${identities[$((identity_choice - 1))]}"
else
  selected_identity="${identity_choice}"
fi

if [[ -z "${selected_identity}" ]]; then
  echo "error: a Developer ID Application identity is required" >&2
  exit 1
fi

if [[ "${selected_identity}" != Developer\ ID\ Application:* ]]; then
  echo "error: signing identity must start with 'Developer ID Application:'" >&2
  exit 1
fi

notary_profile="${MAILBELL_NOTARY_KEYCHAIN_PROFILE:-${DEFAULT_NOTARY_PROFILE}}"
printf 'Notarytool Keychain profile name [%s]: ' "${notary_profile}"
IFS= read -r profile_choice
profile_choice="$(mailbell_trim "${profile_choice}")"
if [[ -n "${profile_choice}" ]]; then
  notary_profile="${profile_choice}"
fi

if [[ -z "${notary_profile}" || "${notary_profile}" == *[[:space:]]* ]]; then
  echo "error: notary profile name must be non-empty and contain no spaces" >&2
  exit 1
fi

printf 'Apple ID for notarization: '
IFS= read -r apple_id
apple_id="$(mailbell_trim "${apple_id}")"
if [[ -z "${apple_id}" ]]; then
  echo "error: Apple ID is required to create the notarytool profile" >&2
  exit 1
fi

printf 'Apple Developer Team ID: '
IFS= read -r team_id
team_id="$(mailbell_trim "${team_id}")"
if [[ -z "${team_id}" ]]; then
  echo "error: Team ID is required to create the notarytool profile" >&2
  exit 1
fi

printf 'App-specific password for notarization (input hidden): '
IFS= read -r -s app_password
printf '\n'
if [[ -z "${app_password}" ]]; then
  echo "error: app-specific password is required to create the notarytool profile" >&2
  exit 1
fi

echo "Creating or updating notarytool Keychain profile '${notary_profile}'."
xcrun notarytool store-credentials "${notary_profile}" \
  --apple-id "${apple_id}" \
  --team-id "${team_id}" \
  --password "${app_password}"

mailbell_update_dotenv_values \
  MAILBELL_CODE_SIGN_IDENTITY "${selected_identity}" \
  MAILBELL_NOTARY_KEYCHAIN_PROFILE "${notary_profile}"

echo "Updated .env signing keys:"
echo "  MAILBELL_CODE_SIGN_IDENTITY"
echo "  MAILBELL_NOTARY_KEYCHAIN_PROFILE"
echo "Secrets were stored by notarytool in the Keychain profile, not in .env."
