#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/mailbell-env.sh
mailbell_load_dotenv


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

current_identity="${DEVELOPER_ID_IDENTITY:-}"
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

# Notarization uses one notarytool Keychain profile shared by every app of the
# owner, authenticated with the team App Store Connect API key. It is created
# once per Mac; scripts/notarize.sh reads NOTARY_PROFILE, default skd-notary.
notary_profile="${NOTARY_PROFILE:-skd-notary}"
printf '\nNotarization uses the shared Keychain profile %s.\n' "${notary_profile}"
printf 'Create or replace it now with the team API key? [y/N]: '
IFS= read -r create_profile
create_profile="$(mailbell_trim "${create_profile}")"
if [[ "${create_profile}" == [yY] ]]; then
  printf 'Path to the AuthKey_<id>.p8 file: '
  IFS= read -r key_path
  key_path="$(mailbell_trim "${key_path}")"
  key_path="${key_path/#\~/${HOME}}"
  if [[ ! -f "${key_path}" ]]; then
    echo "error: API key file not found: ${key_path}" >&2
    exit 1
  fi

  printf 'API key ID: '
  IFS= read -r key_id
  key_id="$(mailbell_trim "${key_id}")"
  printf 'Issuer ID: '
  IFS= read -r issuer_id
  issuer_id="$(mailbell_trim "${issuer_id}")"
  if [[ -z "${key_id}" || -z "${issuer_id}" ]]; then
    echo "error: the API key ID and the issuer ID are both required" >&2
    exit 1
  fi

  echo "Creating or updating notarytool Keychain profile '${notary_profile}'."
  xcrun notarytool store-credentials "${notary_profile}" \
    --key "${key_path}" \
    --key-id "${key_id}" \
    --issuer "${issuer_id}"
else
  echo "Keeping the existing profile. To create it later:"
  echo "  xcrun notarytool store-credentials ${notary_profile} --key <AuthKey.p8 path> --key-id <key id> --issuer <issuer uuid>"
fi

mailbell_update_dotenv_values \
  DEVELOPER_ID_IDENTITY "${selected_identity}"

echo "Updated .env signing key:"
echo "  DEVELOPER_ID_IDENTITY"
echo "Notary credentials live in the Keychain profile, not in .env."
