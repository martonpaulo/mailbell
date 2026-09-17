#!/usr/bin/env bash
# Signs a release archive with the Sparkle EdDSA key (from the login Keychain)
# and prints the appcast signature attributes for scripts/make-appcast.sh.
# Usage: scripts/sign-sparkle-update.sh <archive-path>
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHIVE="${1:?usage: scripts/sign-sparkle-update.sh <archive-path>}"
[ -f "$ARCHIVE" ] || { echo "error: missing archive $ARCHIVE" >&2; exit 1; }

SIGN=$(find .build/artifacts -path '*/bin/sign_update' -not -path '*old_dsa*' -type f 2>/dev/null | head -1)
[ -n "$SIGN" ] || { echo "sign_update not found; run 'swift build' first" >&2; exit 1; }

"$SIGN" "$ARCHIVE"
