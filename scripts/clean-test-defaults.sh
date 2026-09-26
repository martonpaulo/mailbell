#!/usr/bin/env bash
# List, and with --delete remove, the preferences files that test runs before #50 left
# in ~/Library/Preferences. Maintainers run it by hand; no other target calls it.
#
# Only test-suite names are matched, each anchored on its 36-character UUID suffix so no
# app domain (com.perso.mailbell, dev.mailbell.local, ...) can match:
#   mailbell.<Name>Tests.<UUID>.plist
#   mailbell.tests.<area>.<UUID>.plist
#
# Usage: scripts/clean-test-defaults.sh [--delete]
set -euo pipefail
cd "$(dirname "$0")/.."

delete=0
case "${1:-}" in
  "") ;;
  --delete) delete=1 ;;
  *) echo "usage: $0 [--delete]" >&2; exit 2 ;;
esac

prefs="$HOME/Library/Preferences"
uuid='[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}'
pattern="^mailbell\.([A-Za-z]+Tests|tests\.[a-z]+)\.${uuid}\.plist$"

files=()
while IFS= read -r name; do
  files+=("$prefs/$name")
done < <(ls -1 "$prefs" 2>/dev/null | grep -E "$pattern" || true)

echo "${#files[@]} test preferences file(s) in $prefs" >&2
[[ ${#files[@]} -gt 0 ]] || exit 0
printf '  %s\n' "${files[@]:0:5}" >&2
[[ ${#files[@]} -le 5 ]] || echo "  ..." >&2

if [[ $delete -eq 1 ]]; then
  rm -f -- "${files[@]}"
  echo "deleted ${#files[@]} file(s)" >&2
else
  echo "dry run: pass --delete to remove them" >&2
fi
