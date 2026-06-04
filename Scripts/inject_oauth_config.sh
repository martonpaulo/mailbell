#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <Info.plist>" >&2
  exit 2
fi

cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

if [[ -z "${MAILBELL_GOOGLE_CLIENT_ID:-}" || -z "${MAILBELL_GOOGLE_CLIENT_SECRET:-}" ]]; then
  echo "error: set MAILBELL_GOOGLE_CLIENT_ID and MAILBELL_GOOGLE_CLIENT_SECRET" >&2
  exit 1
fi

python3 - "$1" <<'PY'
import os
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
with path.open("rb") as handle:
    plist = plistlib.load(handle)

plist["MailbellGoogleClientID"] = os.environ["MAILBELL_GOOGLE_CLIENT_ID"]
plist["MailbellGoogleClientSecret"] = os.environ["MAILBELL_GOOGLE_CLIENT_SECRET"]

with path.open("wb") as handle:
    plistlib.dump(plist, handle, sort_keys=False)
PY
