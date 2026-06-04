#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <Info.plist>" >&2
  exit 2
fi

cd "$(dirname "$0")/.."

python3 - "$1" <<'PY'
import os
import plistlib
import sys
from pathlib import Path

def strip_matching_quotes(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
        return value[1:-1]
    return value

def read_dotenv():
    path = Path(".env")
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

dotenv = read_dotenv()
client_id = os.environ.get("MAILBELL_GOOGLE_CLIENT_ID") or dotenv.get("MAILBELL_GOOGLE_CLIENT_ID")
client_secret = os.environ.get("MAILBELL_GOOGLE_CLIENT_SECRET") or dotenv.get("MAILBELL_GOOGLE_CLIENT_SECRET")

if not client_id or not client_secret:
    print("error: set MAILBELL_GOOGLE_CLIENT_ID and MAILBELL_GOOGLE_CLIENT_SECRET", file=sys.stderr)
    sys.exit(1)

path = Path(sys.argv[1])
with path.open("rb") as handle:
    plist = plistlib.load(handle)

plist["MailbellGoogleClientID"] = client_id
plist["MailbellGoogleClientSecret"] = client_secret

with path.open("wb") as handle:
    plistlib.dump(plist, handle, sort_keys=False)
PY
