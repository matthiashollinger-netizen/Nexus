#!/bin/bash
# build_beta.sh — Nexus beta release pipeline
#
# Usage:  ./scripts/build_beta.sh <VERSION> [BETA_NUM]
#   e.g.  ./scripts/build_beta.sh 1.3.0 1
#         ./scripts/build_beta.sh 1.3.0        ← auto-increments beta number
#
# Produces a signed beta DMG, GitHub pre-release, and a separate beta-appcast.xml.
# Does NOT update the main appcast.xml — stable users won't see this release.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}ℹ ${NC}$*"; }
success() { echo -e "${GREEN}✅ ${NC}$*"; }
warn()    { echo -e "${YELLOW}⚠️  ${NC}$*"; }
die()     { echo -e "${RED}❌ ${NC}$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$REPO_ROOT/Nexus.xcodeproj"
SCHEME="Nexus"
GITHUB_REPO="matthiashollinger-netizen/Nexus"
TOKEN_FILE="$REPO_ROOT/github_token.txt"
SIGN_UPDATE="$SCRIPT_DIR/sign_update"
BG_IMG="$SCRIPT_DIR/dmg-assets/background.png"

[ -f "$TOKEN_FILE" ]  || die "github_token.txt not found"
[ -x "$SIGN_UPDATE" ] || die "sign_update not found at $SIGN_UPDATE"
command -v xcodebuild > /dev/null || die "xcodebuild not found"
command -v python3    > /dev/null || die "python3 not found"

GITHUB_TOKEN="$(cat "$TOKEN_FILE")"

# ─── Version ─────────────────────────────────────────────────────────────────
[ "${1:-}" != "" ] || die "Usage: ./scripts/build_beta.sh <VERSION> [BETA_NUM]"
BASE_VERSION="${1#v}"

# Auto-increment beta number if not provided
if [ "${2:-}" != "" ]; then
    BETA_NUM="${2}"
else
    # Find highest existing beta tag for this version
    EXISTING=$(git -C "$REPO_ROOT" tag -l "v${BASE_VERSION}-beta.*" 2>/dev/null | \
        sed "s/v${BASE_VERSION}-beta\.//" | sort -n | tail -1)
    BETA_NUM=$(( ${EXISTING:-0} + 1 ))
fi

VERSION="${BASE_VERSION}-beta.${BETA_NUM}"
TAG="v${VERSION}"

echo -e "${BOLD}🧪 Nexus ${TAG} (Pre-Release)${NC}"

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
info "Archiving (Release, arm64) — version ${VERSION}…"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Nexus-ggzdrjuyysxxadanmpxkyorzgfrn \
    -disableAutomaticPackageResolution \
    MARKETING_VERSION="$BASE_VERSION" \
    CURRENT_PROJECT_VERSION="$BASE_VERSION" \
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

if [ ! -d "$APP_PATH" ]; then
    ARCHIVE_APP="$ARCHIVE_PATH/Products/Applications/Nexus.app"
    [ -d "$ARCHIVE_APP" ] || die "App not found in archive."
    cp -R "$ARCHIVE_APP" "$APP_PATH"
    warn "Developer ID cert not found — using development signature."
fi
success "Signed"

# ─── 3. Create DMG ───────────────────────────────────────────────────────────
info "Creating beta DMG…"
TMP_DMG="$BUILD_DIR/tmp_rw_beta.dmg"
VOL_NAME="NexusBeta${BETA_NUM}"
DMG_WIN_W=660; DMG_WIN_H=400
APP_X=180; APP_Y=185; APPS_X=480; APPS_Y=185
rm -f "$TMP_DMG"

hdiutil create -megabytes 200 -fs HFS+ -volname "$VOL_NAME" "$TMP_DMG" -ov -quiet
MOUNT_DIR="$(hdiutil attach "$TMP_DMG" -nobrowse | grep '/Volumes/' | awk '{print $NF}')"
[ -d "$MOUNT_DIR" ] || die "Failed to mount temp DMG"

cp -R "$APP_PATH" "$MOUNT_DIR/"
ln -sf /Applications "$MOUNT_DIR/Applications"
mkdir -p "$MOUNT_DIR/.background"
[ -f "$BG_IMG" ] && cp "$BG_IMG" "$MOUNT_DIR/.background/background.png"

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
success "Beta DMG: $(du -sh "$DMG_PATH" | awk '{print $1}') → $DMG_PATH"

# ─── 4. Sparkle sign ─────────────────────────────────────────────────────────
info "Signing with Sparkle EdDSA…"
SIGN_OUTPUT="$("$SIGN_UPDATE" "$DMG_PATH")"
SIGNATURE="$(echo "$SIGN_OUTPUT" | sed 's/.*sparkle:edSignature="\([^"]*\)".*/\1/')"
[ -n "$SIGNATURE" ] || die "sign_update failed."
success "EdDSA signature obtained"

# ─── 5. Beta appcast.xml (separate, does NOT replace main appcast.xml) ────────
info "Writing beta-appcast.xml…"
DMG_SIZE="$(stat -f%z "$DMG_PATH")"
RELEASE_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
DMG_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${DMG_NAME}"
BETA_APPCAST_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/beta-appcast.xml"

cat > "$REPO_ROOT/beta-appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Nexus Beta Changelog</title>
        <link>${BETA_APPCAST_URL}</link>
        <description>Beta releases for testing.</description>
        <language>en</language>
        <item>
            <title>Nexus ${VERSION} (Beta)</title>
            <sparkle:releaseNotesLink>https://github.com/${GITHUB_REPO}/releases/tag/${TAG}</sparkle:releaseNotesLink>
            <pubDate>${RELEASE_DATE}</pubDate>
            <enclosure
                url="${DMG_URL}"
                sparkle:version="${BASE_VERSION}"
                sparkle:shortVersionString="${VERSION}"
                length="${DMG_SIZE}"
                type="application/octet-stream"
                sparkle:edSignature="${SIGNATURE}"
            />
        </item>
    </channel>
</rss>
EOF
success "beta-appcast.xml written"

# ─── 6. GitHub pre-release ───────────────────────────────────────────────────
info "Creating GitHub Pre-Release ${TAG}…"
NOTES="🧪 **Beta ${VERSION}** — zum Testen\n\nDieser Build ist ein Pre-Release und wird nur an Beta-Tester verteilt."

# Delete existing pre-release if present
EXISTING_ID="$(curl -sf -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${TAG}" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || echo '')"
if [ -n "$EXISTING_ID" ]; then
    curl -sf -X DELETE -H "Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/${GITHUB_REPO}/releases/${EXISTING_ID}" || true
fi

# Create tag
git -C "$REPO_ROOT" tag -f "$TAG" 2>/dev/null || true
git -C "$REPO_ROOT" push "https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git" "$TAG" --force 2>/dev/null || true

RELEASE_BODY="$(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$(echo -e "$NOTES")")"
RELEASE_JSON="$(curl -sf -X POST \
    "https://api.github.com/repos/${GITHUB_REPO}/releases" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"tag_name\":\"${TAG}\",\"name\":\"Nexus ${VERSION} (Beta)\",\"body\":${RELEASE_BODY},\"draft\":false,\"prerelease\":true}")"
RELEASE_ID="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d['id'])" <<< "$RELEASE_JSON" 2>/dev/null)"
[ -n "$RELEASE_ID" ] || die "Pre-release creation failed: $RELEASE_JSON"
success "Pre-release created (id $RELEASE_ID)"

# ─── 7. Upload DMG ───────────────────────────────────────────────────────────
info "Uploading ${DMG_NAME}…"
ASSET_JSON="$(curl -sf -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$DMG_PATH" \
    "https://uploads.github.com/repos/${GITHUB_REPO}/releases/${RELEASE_ID}/assets?name=${DMG_NAME}")"
ASSET_URL="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d['browser_download_url'])" <<< "$ASSET_JSON" 2>/dev/null)"
[ -n "$ASSET_URL" ] || die "Upload failed: $ASSET_JSON"
success "Asset: $ASSET_URL"

# ─── 8. Commit beta-appcast.xml ──────────────────────────────────────────────
info "Committing beta-appcast.xml…"
cd "$REPO_ROOT"
git add beta-appcast.xml
git diff --staged --quiet || git commit -m "Beta ${VERSION}: update beta-appcast.xml"
git push "https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git" main
success "Pushed"

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}🧪 Nexus ${VERSION} Beta bereit!${NC}"
echo ""
echo -e "  ${BOLD}Download:${NC} ${ASSET_URL}"
echo -e "  ${BOLD}GitHub:${NC}   https://github.com/${GITHUB_REPO}/releases/tag/${TAG}"
echo ""
echo -e "${YELLOW}Zum Promoten auf Stable:${NC}"
echo "  ./scripts/promote_beta.sh ${TAG} [issue_nummer]"
