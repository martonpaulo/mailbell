#!/usr/bin/env bash
# Mailbell's only packaging entry point. It wraps the canonical scripts/package-app.sh, which takes
# no hook: that script copies Support/Info.plist into the bundle and signs it, so the Google OAuth
# client has to be in Support/Info.plist before it runs. This script injects it there for the
# length of one packaging run and restores the file byte for byte afterwards, whatever happens.
#
# The restore uses a backup, not git checkout, so an uncommitted edit to the plist survives.
# Arguments are passed to scripts/package-app.sh unchanged, and so is its stdout (the app path and
# the archive path); everything else goes to stderr.
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST=Support/Info.plist

# A client key already in the plist means an earlier run was killed before its restore ran.
for key in MailbellGoogleClientID MailbellGoogleClientSecret; do
  if /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" >/dev/null 2>&1; then
    echo "error: $PLIST already carries $key, left by an interrupted packaging run; run git checkout -- $PLIST" >&2
    exit 1
  fi
done

# A build without credentials fails here, before anything is written.
scripts/inject-bundle-config.sh --check >&2

backup=$(mktemp "${TMPDIR:-/tmp}/mailbell-info-plist.XXXXXX")
cp -p "$PLIST" "$backup"
restore() {
  local status=$?
  trap - EXIT INT TERM
  cp -p "$backup" "$PLIST"
  if ! cmp -s "$backup" "$PLIST"; then
    echo "error: could not restore $PLIST; the original is kept at $backup" >&2
    exit 1
  fi
  rm -f "$backup"
  exit "$status"
}
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

scripts/inject-bundle-config.sh "$PLIST" >&2
scripts/package-app.sh "$@"
