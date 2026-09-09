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

# A version already in the feed is not proof the feed is current. Rebuilding an
# unpublished release produces a different signature and length for the same
# version, and keeping the old entry would advertise one archive while shipping
# another. Identical input stays a no-op; changed input replaces the entry.
python3 - "$VERSION" "$ITEM_FILE" <<'PY'
import re
import sys

version, item_file = sys.argv[1], sys.argv[2]
new_item = open(item_file).read().rstrip("\n")
feed = open("appcast.xml").read()

pattern = re.compile(
    r"[ \t]*<item>.*?<sparkle:shortVersionString>"
    + re.escape(version)
    + r"</sparkle:shortVersionString>.*?</item>\n?",
    re.DOTALL,
)
existing = pattern.search(feed)


def comparable(text):
    """Everything that identifies the archive; pubDate is just when we wrote it."""
    return re.sub(r"<pubDate>.*?</pubDate>", "", text).split()


if existing:
    if comparable(existing.group(0)) == comparable(new_item):
        print(f"appcast.xml already describes this exact {version} archive; leaving unchanged")
        raise SystemExit(0)
    feed = feed[: existing.start()] + new_item + "\n" + feed[existing.end():]
    open("appcast.xml", "w").write(feed)
    print(f"appcast.xml entry for {version} replaced: the archive differs from the one on record")
    raise SystemExit(0)

anchor = "    <language>en</language>\n"
if anchor not in feed:
    print("error: appcast.xml has no <language>en</language> anchor", file=sys.stderr)
    raise SystemExit(1)
feed = feed.replace(anchor, anchor + new_item + "\n", 1)
open("appcast.xml", "w").write(feed)
print(f"appcast.xml updated with {version}")
PY
