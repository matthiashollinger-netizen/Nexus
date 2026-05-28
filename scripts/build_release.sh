#!/bin/bash
# build_release.sh — Nexus release automation
#
# Usage:  ./scripts/build_release.sh [VERSION]
#
# If VERSION is omitted the latest git tag is used.
# Produces a signed DMG, updates appcast.xml, creates a GitHub Release.
#
# Prerequisites:
#   • Xcode + valid signing identity
#   • github_token.txt in repo root
#   • Sparkle EdDSA private key in macOS Keychain (generated once by generate_keys)
#   • For notarized builds: Developer ID Application cert + NOTARIZE=1 env var
#     export NOTARIZE=1 APPLE_ID="you@example.com" APPLE_TEAM="XXXXXXXXXX"

set -euo pipefail

# ─── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}ℹ ${NC}$*"; }
success() { echo -e "${GREEN}✅ ${NC}$*"; }
warn()    { echo -e "${YELLOW}⚠️  ${NC}$*"; }
die()     { echo -e "${RED}❌ ${NC}$*" >&2; exit 1; }

# ─── Configuration ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$REPO_ROOT/Nexus.xcodeproj"
SCHEME="Nexus"
GITHUB_REPO="matthiashollinger-netizen/Nexus"
TOKEN_FILE="$REPO_ROOT/github_token.txt"
APPCAST_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/appcast.xml"
SIGN_UPDATE="$SCRIPT_DIR/sign_update"
BG_IMG="$SCRIPT_DIR/dmg-assets/background.png"
ICON_512="$REPO_ROOT/Nexus/Assets.xcassets/AppIcon.appiconset/icon_512x512.png"

# ─── Validate ────────────────────────────────────────────────────────────────
[ -f "$TOKEN_FILE" ]    || die "github_token.txt not found"
[ -x "$SIGN_UPDATE" ]   || die "sign_update not found at $SIGN_UPDATE"
command -v xcodebuild   > /dev/null || die "xcodebuild not found"
command -v python3      > /dev/null || die "python3 not found"

GITHUB_TOKEN="$(cat "$TOKEN_FILE")"

# ─── Version ─────────────────────────────────────────────────────────────────
if [ "${1:-}" != "" ]; then
    VERSION="${1#v}"
else
    RAW_TAG="$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || echo '')"
    VERSION="${RAW_TAG#v}"
fi
[ -n "$VERSION" ] || die "No version. Pass as argument or create a tag: git tag v1.1.0"

echo -e "${BOLD}📦 Nexus v${VERSION}${NC}"

# ─── Paths ───────────────────────────────────────────────────────────────────
BUILD_DIR="$REPO_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/Nexus-${VERSION}.xcarchive"
EXPORT_DIR="$BUILD_DIR/Nexus-${VERSION}-export"
APP_PATH="$EXPORT_DIR/Nexus.app"
DMG_NAME="Nexus-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$DMG_PATH"

# ─── 1. Archive ──────────────────────────────────────────────────────────────
info "Archiving (Release, arm64)…"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Nexus-ggzdrjuyysxxadanmpxkyorzgfrn \
    -disableAutomaticPackageResolution \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$VERSION" \
    2>&1 | grep -E "^(error:|warning: )" || true
[ -d "$ARCHIVE_PATH" ] || die "Archive failed."
success "Archived → $ARCHIVE_PATH"

# ─── 2. Export / sign ────────────────────────────────────────────────────────
info "Signing .app…"
mkdir -p "$EXPORT_DIR"
EXPORT_OPTS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>6XPVCAC62R</string>
    <key>signingStyle</key><string>automatic</string>
    <key>stripSwiftSymbols</key><true/>
</dict></plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTS" \
    > "$BUILD_DIR/export.log" 2>&1 || true

if [ -d "$APP_PATH" ]; then
    success "Signed with Developer ID"
else
    # Fallback: copy from archive (development-signed)
    ARCHIVE_APP="$ARCHIVE_PATH/Products/Applications/Nexus.app"
    [ -d "$ARCHIVE_APP" ] || die "App not found in archive."
    cp -R "$ARCHIVE_APP" "$APP_PATH"
    warn "Developer ID cert not found — using development signature."
    warn "For notarized/Gatekeeper-free builds: install 'Developer ID Application' cert."
fi

# ─── 3. Notarize (optional — set NOTARIZE=1) ─────────────────────────────────
if [ "${NOTARIZE:-0}" = "1" ]; then
    info "Notarizing…"
    APPLE_ID="${APPLE_ID:-}"
    APPLE_TEAM="${APPLE_TEAM:-6XPVCAC62R}"
    [ -n "$APPLE_ID" ] || die "Set APPLE_ID env var for notarization"
    ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/Nexus-notarize.zip"
    xcrun notarytool submit "$BUILD_DIR/Nexus-notarize.zip" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM" \
        --keychain-profile "notarytool-profile" \
        --wait
    xcrun stapler staple "$APP_PATH"
    rm -f "$BUILD_DIR/Nexus-notarize.zip"
    success "Notarized & stapled"
fi

# ─── 4. Create stylish DMG ───────────────────────────────────────────────────
info "Creating DMG…"
TMP_DMG="$BUILD_DIR/tmp_rw.dmg"
VOL_NAME="Nexus"
DMG_WIN_W=660; DMG_WIN_H=400
APP_X=180;  APP_Y=185
APPS_X=480; APPS_Y=185
rm -f "$TMP_DMG"

hdiutil create -megabytes 200 -fs HFS+ -volname "$VOL_NAME" "$TMP_DMG" -ov -quiet
MOUNT_DIR="$(hdiutil attach "$TMP_DMG" -nobrowse | grep '/Volumes/' | awk '{print $NF}')"
[ -d "$MOUNT_DIR" ] || die "Failed to mount temp DMG"

# Copy app and Applications symlink
cp -R "$APP_PATH"          "$MOUNT_DIR/"
ln -sf /Applications        "$MOUNT_DIR/Applications"

# Background MUST be in place before AppleScript runs
mkdir -p "$MOUNT_DIR/.background"
[ -f "$BG_IMG" ] && cp "$BG_IMG" "$MOUNT_DIR/.background/background.png"

# Set DMG window look via AppleScript
osascript <<APPLESCRIPT 2>/dev/null || true
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, $((DMG_WIN_W+200)), $((DMG_WIN_H+120))}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set background picture of viewOptions to file ".background:background.png"
        set position of item "Nexus.app"    of container window to {${APP_X},  ${APP_Y}}
        set position of item "Applications" of container window to {${APPS_X}, ${APPS_Y}}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

hdiutil detach "$MOUNT_DIR" -quiet
hdiutil convert "$TMP_DMG" -format UDBZ -o "$DMG_PATH" -quiet
rm -f "$TMP_DMG"
success "DMG: $(du -sh "$DMG_PATH" | awk '{print $1}') → $DMG_PATH"

# ─── 5. Sign with Sparkle ────────────────────────────────────────────────────
info "Signing with Sparkle EdDSA…"
SIGN_OUTPUT="$("$SIGN_UPDATE" "$DMG_PATH")"
SIGNATURE="$(echo "$SIGN_OUTPUT" | sed 's/.*sparkle:edSignature="\([^"]*\)".*/\1/')"
[ -n "$SIGNATURE" ] || die "sign_update failed. Is private key in Keychain?"
success "EdDSA signature obtained"

# ─── 6. Update appcast.xml ───────────────────────────────────────────────────
info "Updating appcast.xml…"
DMG_SIZE="$(stat -f%z "$DMG_PATH")"
RELEASE_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
DMG_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${DMG_NAME}"

cat > "$REPO_ROOT/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Nexus Changelog</title>
        <link>${APPCAST_URL}</link>
        <description>Most recent changes with links to updates.</description>
        <language>en</language>
        <item>
            <title>Nexus ${VERSION}</title>
            <sparkle:releaseNotesLink>https://github.com/${GITHUB_REPO}/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
            <pubDate>${RELEASE_DATE}</pubDate>
            <enclosure
                url="${DMG_URL}"
                sparkle:version="${VERSION}"
                sparkle:shortVersionString="${VERSION}"
                length="${DMG_SIZE}"
                type="application/octet-stream"
                sparkle:edSignature="${SIGNATURE}"
            />
        </item>
    </channel>
</rss>
EOF
success "appcast.xml updated"

# ─── 7. GitHub Release ───────────────────────────────────────────────────────
info "Creating GitHub Release v${VERSION}…"
NOTES=""
if [ -f "$REPO_ROOT/CHANGELOG.md" ]; then
    NOTES="$(awk "/^## \[${VERSION}\]/{found=1; next} found && /^## \[/{exit} found{print}" "$REPO_ROOT/CHANGELOG.md" | sed '/^$/d')"
fi
[ -z "$NOTES" ] && NOTES="Nexus ${VERSION}"
RELEASE_BODY="$(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$NOTES")"

# Check if release already exists; delete if so
EXISTING_ID="$(curl -sf -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPO}/releases/tags/v${VERSION}" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || echo '')"
if [ -n "$EXISTING_ID" ]; then
    curl -sf -X DELETE -H "Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/${GITHUB_REPO}/releases/${EXISTING_ID}" || true
    warn "Deleted existing release $EXISTING_ID"
fi

RELEASE_JSON="$(curl -sf -X POST \
    "https://api.github.com/repos/${GITHUB_REPO}/releases" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"tag_name\":\"v${VERSION}\",\"name\":\"Nexus v${VERSION}\",\"body\":${RELEASE_BODY},\"draft\":false,\"prerelease\":false}")"
RELEASE_ID="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d['id'])" <<< "$RELEASE_JSON" 2>/dev/null)"
[ -n "$RELEASE_ID" ] || die "Release creation failed: $RELEASE_JSON"
success "Release created (id $RELEASE_ID)"

# ─── 8. Upload DMG ───────────────────────────────────────────────────────────
info "Uploading $DMG_NAME…"
ASSET_JSON="$(curl -sf -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$DMG_PATH" \
    "https://uploads.github.com/repos/${GITHUB_REPO}/releases/${RELEASE_ID}/assets?name=${DMG_NAME}")"
ASSET_URL="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d['browser_download_url'])" <<< "$ASSET_JSON" 2>/dev/null)"
[ -n "$ASSET_URL" ] || die "Upload failed: $ASSET_JSON"
success "Asset: $ASSET_URL"

# ─── 9. Commit & Push ────────────────────────────────────────────────────────
info "Pushing appcast.xml…"
cd "$REPO_ROOT"
git add appcast.xml
git diff --staged --quiet || git commit -m "Release v${VERSION}: update appcast.xml"
git push "https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git" main
success "Pushed"

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}🎉 Nexus v${VERSION} released!${NC}"
echo "   GitHub:  https://github.com/${GITHUB_REPO}/releases/tag/v${VERSION}"
echo "   Appcast: ${APPCAST_URL}"
echo ""
echo -e "${YELLOW}ℹ️  Gatekeeper:${NC} Users may see a security warning if the app is not notarized."
echo "   To notarize: get a 'Developer ID Application' cert, then run:"
echo "   NOTARIZE=1 APPLE_ID=you@example.com ./scripts/build_release.sh ${VERSION}"
