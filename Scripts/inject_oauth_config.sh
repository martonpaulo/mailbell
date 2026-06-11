#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <Info.plist>|--check" >&2
  exit 2
fi

cd "$(dirname "$0")/.."

python3 - "$1" <<'PY'
import os
import plistlib
import re
import sys
from pathlib import Path

CLIENT_ID_KEY = "MAILBELL_GOOGLE_CLIENT_ID"
CLIENT_SECRET_KEY = "MAILBELL_GOOGLE_CLIENT_SECRET"
BUNDLE_ID_KEY = "PERSONAL_BUNDLE_ID"
DISPLAY_NAME_KEY = "APP_DISPLAY_NAME"
CHECK_ONLY = sys.argv[1] == "--check"

def strip_matching_quotes(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
        return value[1:-1]
    return value

def read_dotenv():
    path = Path(os.environ.get("MAILBELL_DOTENV_PATH", ".env"))
    if not path.exists():
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
        BUNDLE_ID_KEY: os.environ.get(BUNDLE_ID_KEY),
        DISPLAY_NAME_KEY: os.environ.get(DISPLAY_NAME_KEY),
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
        fail(f"set {CLIENT_ID_KEY} and {CLIENT_SECRET_KEY} in the environment or .env")
    if not client_id.endswith(".apps.googleusercontent.com"):
        fail(f"{CLIENT_ID_KEY} must be a Desktop OAuth client ID ending in .apps.googleusercontent.com")
    return client_id

def validate_client_secret(value):
    client_secret = cleaned(value)
    if not client_secret:
        fail(f"set {CLIENT_ID_KEY} and {CLIENT_SECRET_KEY} in the environment or .env")
    return client_secret

def validate_bundle_id(value):
    bundle_id = cleaned(value) or "com.perso.mailbell"
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", bundle_id) or "." not in bundle_id:
        fail(f"{BUNDLE_ID_KEY} must be a reverse-DNS bundle identifier")
    return bundle_id

def validate_display_name(value):
    display_name = cleaned(value) or "Mailbell"
    if "/" in display_name or "\0" in display_name or len(display_name) > 80:
        fail(f"{DISPLAY_NAME_KEY} must be a short app display name")
    return display_name

dotenv = read_dotenv()
credentials, bundle_values = first_configured_source(dotenv)

client_id = validate_client_id(credentials.get(CLIENT_ID_KEY))
client_secret = validate_client_secret(credentials.get(CLIENT_SECRET_KEY))
bundle_id = validate_bundle_id(bundle_values.get(BUNDLE_ID_KEY))
display_name = validate_display_name(bundle_values.get(DISPLAY_NAME_KEY))

if CHECK_ONLY:
    print("OAuth configuration found for local packaging.")
    sys.exit(0)

path = Path(sys.argv[1])
with path.open("rb") as handle:
    plist = plistlib.load(handle)

plist["MailbellGoogleClientID"] = client_id
plist["MailbellGoogleClientSecret"] = client_secret
plist["CFBundleIdentifier"] = bundle_id
plist["CFBundleName"] = display_name
plist["CFBundleDisplayName"] = display_name

with path.open("wb") as handle:
    plistlib.dump(plist, handle, sort_keys=False)
PY
