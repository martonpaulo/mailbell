#!/usr/bin/env bash
# Prepends a release entry to appcast.xml (creating it if missing).
# Usage: Scripts/make_appcast.sh <version> <build-number> <archive-path> <signature-attrs>
#   signature-attrs is sign_update's output: sparkle:edSignature="..." length="..."
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: Scripts/make_appcast.sh <version> <build-number> <archive-path> <signature-attrs>}"
BUILD_NUMBER="${2:?missing build number}"
ARCHIVE_PATH="${3:?missing archive path}"
SIGNATURE_ATTRS="${4:?missing signature attributes}"

URL="https://github.com/martonpaulo/mailbell/releases/download/v$VERSION/$(basename "$ARCHIVE_PATH")"
DATE=$(LC_ALL=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")
NOTES_URL="https://github.com/martonpaulo/mailbell/releases/tag/v$VERSION"

ITEM_FILE=$(mktemp)
trap 'rm -f "$ITEM_FILE"' EXIT
cat > "$ITEM_FILE" <<EOF
    <item>
      <title>$VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:releaseNotesLink>$NOTES_URL</sparkle:releaseNotesLink>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <enclosure url="$URL" $SIGNATURE_ATTRS type="application/octet-stream"/>
    </item>
EOF

if [ ! -f appcast.xml ]; then
    cat > appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Mailbell</title>
    <link>https://github.com/martonpaulo/mailbell</link>
    <description>Most recent updates to Mailbell</description>
    <language>en</language>
  </channel>
</rss>
EOF
fi

if grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" appcast.xml; then
    echo "appcast.xml already contains $VERSION; leaving unchanged"
    exit 0
fi

awk -v itemfile="$ITEM_FILE" '
    { print }
    /<language>en<\/language>/ {
        while ((getline line < itemfile) > 0) print line
        close(itemfile)
    }
' appcast.xml > appcast.xml.new
mv appcast.xml.new appcast.xml
echo "appcast.xml updated with $VERSION (build $BUILD_NUMBER)"
