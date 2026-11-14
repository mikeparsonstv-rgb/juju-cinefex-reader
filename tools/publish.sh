#!/bin/bash
# JUJU Cinefex Reader: publish an app exported from Xcode as a GitHub release and an update.
#
# In Xcode: raise Version (and Build) on the target's General tab, then
#   Product → Archive → Distribute App → Direct Distribution → Distribute.
# Xcode signs and notarises it and exports the app. Then in Terminal type the path to this script,
# a space, drag the exported app onto the window, optionally add "what's new", and press Return:
#   tools/publish.sh "/path/to/JUJU Cinefex Reader.app" "What's new"
#
# The first run only creates the update signing key (kept in your login keychain). Archive and export
# once more so the app carries the key, then run this again.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="mikeparsonstv-rgb/juju-cinefex-reader"
ZIPNAME="JUJU-Cinefex-Reader.zip"      # same name every release, so .../releases/latest/download/ always works

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '\n\033[31m✗ %s\033[0m\n' "$*"; exit 1; }

# Sparkle's tools come with the package Xcode downloaded.
BIN=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/JUJU_Cinefex_Reader-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1)
[ -n "$BIN" ] && [ -x "$BIN/sign_update" ] || fail "Sparkle's tools weren't found. Build the app in Xcode once (⌘B), then run this again."

# First time: make the update signing key and put its public half in Info.plist.
KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Info.plist 2>/dev/null || true)
if [ -z "$KEY" ]; then
  KEY=$("$BIN/generate_keys" -p 2>/dev/null || true)
  if [ -z "$KEY" ]; then "$BIN/generate_keys" > /dev/null; KEY=$("$BIN/generate_keys" -p); fi
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $KEY" Info.plist
  BACKUP="$HOME/Documents/JUJU Cinefex Reader update key (keep private).txt"
  [ -f "$BACKUP" ] || { "$BIN/generate_keys" -x "$BACKUP"; chmod 600 "$BACKUP"; }
  ok "Update signing key created. Its backup is in Documents; keep that file safe and private."
  printf '\nNow Archive and export once more in Xcode so the app carries the key, then run this again.\n'
  exit 0
fi

APPPATH="${1:-}"
[ -d "$APPPATH" ] || fail "Drag the app exported from Xcode onto this window after the script's name."
APPPATH="${APPPATH%/}"
NOTES="${2:-}"
INFO="$APPPATH/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")
BUILDNUM=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")
APPKEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO" 2>/dev/null || true)

[ "$APPKEY" = "$KEY" ] || fail "This app doesn't carry the update key yet. Archive and export it again in Xcode."
xcrun stapler validate "$APPPATH" > /dev/null 2>&1 || fail "This app isn't notarised. Export it with Direct Distribution."
if git ls-remote --tags "https://github.com/$REPO.git" "v$VERSION" 2>/dev/null | grep -q .; then
  fail "Version $VERSION is already released. Raise Version on the target's General tab in Xcode."
fi
[ -n "$NOTES" ] || read -r -p "What's new in $VERSION (one line, Return for none): " NOTES
[ -n "$NOTES" ] || NOTES="Improvements and fixes."
printf '\n\033[1mPublishing %s (build %s)\033[0m\n' "$VERSION" "$BUILDNUM"

OUT="Releases/$VERSION"
mkdir -p "$OUT"
rm -f "$OUT/$ZIPNAME"
ditto -c -k --sequesterRsrc --keepParent "$APPPATH" "$OUT/$ZIPNAME"
SIG=$("$BIN/sign_update" "$OUT/$ZIPNAME")          # sparkle:edSignature="…" length="…"
ok "$OUT/$ZIPNAME ($(du -h "$OUT/$ZIPNAME" | cut -f1)), signed for updates"

PUBDATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
ESCAPED=$(printf '%s' "$NOTES" | sed 's/]]>/]]]]><![CDATA[>/g')
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>JUJU Cinefex Reader</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILDNUM</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>$ESCAPED</p>]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/$ZIPNAME" $SIG type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
xmllint --noout "$OUT/appcast.xml"
ok "$OUT/appcast.xml (the update feed)"

TITLE="JUJU Cinefex Reader $VERSION"
BODY="$NOTES

**Download:** $ZIPNAME below, unzip, and drag *JUJU Cinefex Reader* to Applications. Needs macOS 14 or later.
Already installed? The app offers this update itself (or choose *Check for Updates…* in the app menu)."
if command -v gh > /dev/null && gh auth status > /dev/null 2>&1; then
  gh release create "v$VERSION" "$OUT/$ZIPNAME" "$OUT/appcast.xml" --repo "$REPO" --title "$TITLE" --notes "$BODY" --latest
  ok "Published: https://github.com/$REPO/releases/tag/v$VERSION"
else
  printf '%s\n' "$BODY" > "$OUT/release-notes.txt"
  open "https://github.com/$REPO/releases/new?tag=v$VERSION&title=$(printf '%s' "$TITLE" | sed 's/ /%20/g')"
  open "$OUT"
  echo
  echo "  GitHub's new-release page and the $OUT folder are open. On the GitHub page:"
  echo "   1. Paste release-notes.txt into the description"
  echo "   2. Drag $ZIPNAME and appcast.xml into the 'Attach binaries' box and wait for both to upload"
  echo "   3. Leave 'Set as the latest release' ticked and click Publish release"
fi

printf '\n\033[1mDone.\033[0m Public download link (always the newest version):\n  https://github.com/%s/releases/latest/download/%s\n' "$REPO" "$ZIPNAME"
