#!/usr/bin/env bash
# Signs a release archive with the Sparkle EdDSA key (from the login Keychain)
# and prints the appcast signature attributes for Scripts/make_appcast.sh.
# Usage: Scripts/sign_sparkle_update.sh <archive-path>
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHIVE="${1:?usage: Scripts/sign_sparkle_update.sh <archive-path>}"
[ -f "$ARCHIVE" ] || { echo "error: missing archive $ARCHIVE" >&2; exit 1; }

SIGN=$(find .build/artifacts -name sign_update -type f 2>/dev/null | head -1)
[ -n "$SIGN" ] || { echo "sign_update not found; run 'swift build' first" >&2; exit 1; }

"$SIGN" "$ARCHIVE"
