#!/bin/bash
# build_release.sh — Nexus release automation
#
# Usage:
#   ./scripts/build_release.sh [VERSION]
#
# If VERSION is omitted the script uses the latest git tag (e.g. v1.0.0).
# Creates a signed DMG, updates appcast.xml, and publishes a GitHub Release.
#
# Prerequisites:
#   • Xcode with a valid signing identity
#   • github_token.txt in the repo root
#   • Sparkle EdDSA private key in the macOS Keychain (generated once by generate_keys)

set -euo pipefail

# ─── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
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

# ─── Validate tools ──────────────────────────────────────────────────────────
[ -f "$TOKEN_FILE" ]    || die "github_token.txt not found at $TOKEN_FILE"
[ -x "$SIGN_UPDATE" ]   || die "sign_update not found at $SIGN_UPDATE (run chmod +x scripts/sign_update)"
command -v xcodebuild   > /dev/null || die "xcodebuild not found"
command -v hdiutil      > /dev/null || die "hdiutil not found"
command -v python3      > /dev/null || die "python3 not found"

GITHUB_TOKEN="$(cat "$TOKEN_FILE")"

# ─── Version ─────────────────────────────────────────────────────────────────
if [ "${1:-}" != "" ]; then
    VERSION="${1#v}"   # strip leading 'v' if present
else
    RAW_TAG="$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || echo '')"
    VERSION="${RAW_TAG#v}"
fi
[ -n "$VERSION" ] || die "No version found. Pass as argument or create a tag: git tag v1.0.0 && git push --tags"

info "Building Nexus v${VERSION}"

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
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$VERSION" \
    2>&1 | grep -E "^(error:|warning:|✓|Archive)" || true

[ -d "$ARCHIVE_PATH" ] || die "Archive failed — check Xcode build output."
success "Archived to $ARCHIVE_PATH"

# ─── 2. Export ───────────────────────────────────────────────────────────────
# Strategy: try Developer ID export first (requires "Developer ID Application"
# certificate from a paid Apple Developer account). If that cert isn't present,
# copy the .app directly from the archive — it's already development-signed and
# fully functional for distribution to users who allow apps from identified devs.
info "Exporting .app…"
mkdir -p "$EXPORT_DIR"

EXPORT_OPTS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>6XPVCAC62R</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
PLIST

EXPORT_LOG="$BUILD_DIR/export.log"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTS" \
    > "$EXPORT_LOG" 2>&1 || true

if [ -d "$APP_PATH" ]; then
    success "Exported with Developer ID signing"
else
    # Fallback: copy directly from archive (development-signed)
    ARCHIVE_APP="$ARCHIVE_PATH/Products/Applications/Nexus.app"
    [ -d "$ARCHIVE_APP" ] || die "App not found in archive at $ARCHIVE_APP"
    cp -R "$ARCHIVE_APP" "$APP_PATH"
    warn "Developer ID cert not found — using archive copy (development-signed)."
    warn "For notarized distribution, install a 'Developer ID Application' certificate."
fi
[ -d "$APP_PATH" ] || die "Export failed — Nexus.app not found."
success "App ready: $APP_PATH"

# ─── 3. Create DMG ───────────────────────────────────────────────────────────
info "Creating DMG…"
TMP_DMG="$BUILD_DIR/tmp_rw_${VERSION}.dmg"
VOL_NAME="Nexus ${VERSION}"

# Create writable image
hdiutil create -megabytes 150 -fs HFS+ -volname "$VOL_NAME" "$TMP_DMG" -ov -quiet
MOUNT_DIR="$(hdiutil attach "$TMP_DMG" -nobrowse -quiet | grep '/Volumes/' | awk '{print $NF}')"
[ -d "$MOUNT_DIR" ] || die "Failed to mount temp DMG"

# Copy app + Applications symlink
cp -R "$APP_PATH" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"

# Ensure the Finder shows the volume (optional cosmetic)
SetFile -a C "$MOUNT_DIR" 2>/dev/null || true

hdiutil detach "$MOUNT_DIR" -quiet
hdiutil convert "$TMP_DMG" -format UDBZ -o "$DMG_PATH" -quiet
rm -f "$TMP_DMG"
success "DMG: $DMG_PATH ($(du -sh "$DMG_PATH" | awk '{print $1}'))"

# ─── 4. Sign with Sparkle ────────────────────────────────────────────────────
info "Signing DMG with Sparkle EdDSA…"
# sign_update outputs: sparkle:edSignature="VALUE" length="SIZE"
SIGN_OUTPUT="$("$SIGN_UPDATE" "$DMG_PATH")"
SIGNATURE="$(echo "$SIGN_OUTPUT" | sed 's/.*sparkle:edSignature="\([^"]*\)".*/\1/')"
[ -n "$SIGNATURE" ] || die "sign_update returned empty signature. Is the private key in the Keychain?"
success "Signature obtained"

# ─── 5. Update appcast.xml ───────────────────────────────────────────────────
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

# ─── 6. GitHub Release ───────────────────────────────────────────────────────
info "Creating GitHub Release v${VERSION}…"

# Read CHANGELOG entry for this version
NOTES=""
if [ -f "$REPO_ROOT/CHANGELOG.md" ]; then
    NOTES="$(awk "/^## \[${VERSION}\]/{found=1; next} found && /^## \[/{exit} found{print}" "$REPO_ROOT/CHANGELOG.md" | sed '/^$/d')"
fi
[ -z "$NOTES" ] && NOTES="Nexus ${VERSION}"

RELEASE_BODY="$(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$NOTES")"

RELEASE_JSON="$(curl -sf -X POST \
    "https://api.github.com/repos/${GITHUB_REPO}/releases" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"tag_name\":\"v${VERSION}\",\"name\":\"Nexus v${VERSION}\",\"body\":${RELEASE_BODY},\"draft\":false,\"prerelease\":false}")"

RELEASE_ID="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d['id'])" <<< "$RELEASE_JSON" 2>/dev/null || echo '')"
[ -n "$RELEASE_ID" ] || die "Failed to create release. Response: $RELEASE_JSON"
success "Release created (id $RELEASE_ID)"

# ─── 7. Upload DMG ───────────────────────────────────────────────────────────
info "Uploading $DMG_NAME…"
UPLOAD_URL="https://uploads.github.com/repos/${GITHUB_REPO}/releases/${RELEASE_ID}/assets?name=${DMG_NAME}"
ASSET_JSON="$(curl -sf -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$DMG_PATH" \
    "$UPLOAD_URL")"

ASSET_URL="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d['browser_download_url'])" <<< "$ASSET_JSON" 2>/dev/null || echo '')"
[ -n "$ASSET_URL" ] || die "Upload failed. Response: $ASSET_JSON"
success "Asset: $ASSET_URL"

# ─── 8. Commit & Push appcast.xml ────────────────────────────────────────────
info "Pushing appcast.xml…"
cd "$REPO_ROOT"
git add appcast.xml
git commit -m "Release v${VERSION}: update appcast.xml"
git push "https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git" main
success "appcast.xml pushed"

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}🎉 Nexus v${VERSION} released!${NC}"
echo "   GitHub:  https://github.com/${GITHUB_REPO}/releases/tag/v${VERSION}"
echo "   Appcast: ${APPCAST_URL}"
