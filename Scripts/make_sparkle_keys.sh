#!/usr/bin/env bash
# One-time-per-machine setup: generate the Sparkle EdDSA signing key (stored in
# your login Keychain) and write its public half into Resources/Info.plist. The
# private key never leaves the Keychain and must never be committed.
# Usage: Scripts/make_sparkle_keys.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build >/dev/null 2>&1 || true
GENERATE=$(find .build/artifacts -name generate_keys -type f 2>/dev/null | head -1)
[ -n "$GENERATE" ] || { echo "generate_keys not found; run 'swift build' first" >&2; exit 1; }

# Idempotent: creates a key only if the login Keychain has none.
"$GENERATE" >/dev/null 2>&1 || true
PUBLIC_KEY=$("$GENERATE" -p 2>/dev/null | tr -d '[:space:]')
[ -n "$PUBLIC_KEY" ] || { echo "failed to read the Sparkle public key" >&2; exit 1; }

/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" Resources/Info.plist 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $PUBLIC_KEY" Resources/Info.plist

echo "SUPublicEDKey written to Resources/Info.plist: $PUBLIC_KEY"
echo "The private key stays in your login Keychain. Never commit it."
