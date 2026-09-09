#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 [--version X.Y.Z --build-number N] [--check] <Info.plist>" >&2
}

VERSION=""
BUILD_NUMBER=""
CHECK_ONLY=0
PLIST_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      CHECK_ONLY=1
      shift
      ;;
    --version)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      VERSION="$2"
      shift 2
      ;;
    --build-number)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      BUILD_NUMBER="$2"
      shift 2
      ;;
    -*)
      usage
      exit 2
      ;;
    *)
      if [[ -n "${PLIST_PATH}" ]]; then
        usage
        exit 2
      fi
      PLIST_PATH="$1"
      shift
      ;;
  esac
done

# The plist owns the bundle identity, so preflight reads it too rather than
# reporting an identifier the produced app would not have.
if [[ -z "${PLIST_PATH}" ]]; then
  if [[ "${CHECK_ONLY}" -eq 1 ]]; then
    PLIST_PATH="$(cd "$(dirname "$0")/.." && pwd)/Resources/Info.plist"
  else
    usage
    exit 2
  fi
fi

if [[ -n "${VERSION}" && -z "${BUILD_NUMBER}" ]] || [[ -z "${VERSION}" && -n "${BUILD_NUMBER}" ]]; then
  echo "error: release version and build number must be provided together" >&2
  exit 2
fi

cd "$(dirname "$0")/.."

python3 - "${CHECK_ONLY}" "${VERSION}" "${BUILD_NUMBER}" "${PLIST_PATH}" <<'PY'
import os
import plistlib
import re
import sys
from pathlib import Path

CLIENT_ID_KEY = "MAILBELL_GOOGLE_CLIENT_ID"
CLIENT_SECRET_KEY = "MAILBELL_GOOGLE_CLIENT_SECRET"
BUNDLE_ID_KEY = "MAILBELL_BUNDLE_ID"
PRODUCT_NAME = "Mailbell"
CHECK_ONLY = sys.argv[1] == "1"
VERSION = sys.argv[2].strip()
BUILD_NUMBER = sys.argv[3].strip()
PLIST_PATH = sys.argv[4]

def strip_matching_quotes(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
        return value[1:-1]
    return value

def read_dotenv():
    dotenv_path = cleaned(os.environ.get("MAILBELL_DOTENV_PATH")) or ".env"
    path = Path(dotenv_path)
    if not path.is_file():
        return {}
    values = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = strip_matching_quotes(value.strip())
    return values

def first_configured_source(dotenv):
    bundle = {
        BUNDLE_ID_KEY: os.environ.get(BUNDLE_ID_KEY) or dotenv.get(BUNDLE_ID_KEY),
    }
    env_credentials = {
        CLIENT_ID_KEY: os.environ.get(CLIENT_ID_KEY),
        CLIENT_SECRET_KEY: os.environ.get(CLIENT_SECRET_KEY),
    }
    dotenv_credentials = {
        CLIENT_ID_KEY: dotenv.get(CLIENT_ID_KEY),
        CLIENT_SECRET_KEY: dotenv.get(CLIENT_SECRET_KEY),
    }

    if any((value or "").strip() for value in env_credentials.values()):
        return env_credentials, bundle
    if any((value or "").strip() for value in dotenv_credentials.values()):
        return dotenv_credentials, bundle
    return env_credentials, bundle

def cleaned(value):
    return (value or "").strip()

def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)

def validate_client_id(value):
    client_id = cleaned(value)
    if not client_id:
        fail(f"set {CLIENT_ID_KEY} in the environment or .env")
    if not client_id.endswith(".apps.googleusercontent.com"):
        fail(f"{CLIENT_ID_KEY} must be a Desktop OAuth client ID ending in .apps.googleusercontent.com")
    return client_id

def validate_client_secret(value):
    return cleaned(value) or None

def validate_bundle_id(value, canonical):
    """The plist owns the identity. Optional configuration may restate it, never
    replace it: a second identifier would orphan the Keychain items and
    UserDefaults keys derived from the first."""
    if not canonical or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", canonical) or "." not in canonical:
        fail(f"the plist must already carry a reverse-DNS CFBundleIdentifier, found {canonical!r}")
    configured = cleaned(value)
    if configured and configured != canonical:
        fail(
            f"{BUNDLE_ID_KEY} is {configured!r} but this app is {canonical!r}. "
            "Packaging never changes the bundle identifier; unset the variable "
            "or set it to the canonical value."
        )
    return canonical

def validate_release_metadata(version, build_number):
    if not version and not build_number:
        return None
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        fail("release version must use X.Y.Z format")
    if not re.fullmatch(r"[0-9]+", build_number):
        fail("release build number must be a positive integer")
    if int(build_number) <= 0:
        fail("release build number must be a positive integer")
    return version, build_number

dotenv = read_dotenv()
credentials, bundle_values = first_configured_source(dotenv)

path = Path(PLIST_PATH)
try:
    with path.open("rb") as handle:
        plist = plistlib.load(handle)
except OSError as error:
    fail(f"cannot read {PLIST_PATH}: {error}")

client_id = validate_client_id(credentials.get(CLIENT_ID_KEY))
client_secret = validate_client_secret(credentials.get(CLIENT_SECRET_KEY))
bundle_id = validate_bundle_id(bundle_values.get(BUNDLE_ID_KEY), plist.get("CFBundleIdentifier"))
release_metadata = validate_release_metadata(VERSION, BUILD_NUMBER)

if CHECK_ONLY:
    print("Bundle configuration found for local packaging.")
    print(f"Bundle identifier: {bundle_id}")
    print(f"Product name: {PRODUCT_NAME}")
    sys.exit(0)

plist["MailbellGoogleClientID"] = client_id
if client_secret:
    plist["MailbellGoogleClientSecret"] = client_secret
else:
    plist.pop("MailbellGoogleClientSecret", None)
plist["CFBundleIdentifier"] = bundle_id
plist["CFBundleName"] = PRODUCT_NAME
plist["CFBundleDisplayName"] = PRODUCT_NAME
if release_metadata:
    plist["CFBundleShortVersionString"] = release_metadata[0]
    plist["CFBundleVersion"] = release_metadata[1]

with path.open("wb") as handle:
    plistlib.dump(plist, handle, sort_keys=False)

print(f"Injected local configuration into {path}")
print(f"Bundle identifier: {bundle_id}")
print(f"Product name: {PRODUCT_NAME}")
if release_metadata:
    print(f"Release version: {release_metadata[0]}")
    print(f"Build number: {release_metadata[1]}")
PY
