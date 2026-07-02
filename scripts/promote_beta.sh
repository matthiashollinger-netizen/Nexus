#!/bin/bash
# promote_beta.sh — Promotes a beta release to stable
#
# Usage:  ./scripts/promote_beta.sh <BETA_TAG> [ISSUE_NUMBER]
#   e.g.  ./scripts/promote_beta.sh v1.3.1-beta.1 42
#
# Owner-Check:
#   Wenn ISSUE_NUMBER angegeben, prüft das Script ob der Repo-Owner
#   (matthiashollinger-netizen) mit 👍 reagiert hat — auf dem Issue selbst
#   oder dem letzten Kommentar. Nur der Owner kann den Release freigeben.
#   Bei fremder oder fehlender Reaktion: Kommentar + Abbruch.
#
# Was dieses Script macht:
#   1. Owner-Freigabe prüfen (wenn Issue-Nummer angegeben)
#   2. Beta-DMG von GitHub herunterladen
#   3. Stabilen GitHub Release erstellen (selbes DMG)
#   4. appcast.xml aktualisieren → alle Stable-User bekommen das Update
#   5. appcast.xml via GitHub API direkt auf main committen
#   6. (Optional) GitHub Issue schließen mit Label 'verified'

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}ℹ ${NC}$*"; }
success() { echo -e "${GREEN}✅ ${NC}$*"; }
warn()    { echo -e "${YELLOW}⚠️  ${NC}$*"; }
die()     { echo -e "${RED}❌ ${NC}$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GITHUB_REPO="matthiashollinger-netizen/Nexus"
OWNER_LOGIN="matthiashollinger-netizen"
TOKEN_FILE="$REPO_ROOT/github_token.txt"
APPCAST_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/appcast.xml"

[ -f "$TOKEN_FILE" ] || die "github_token.txt not found"
command -v python3   > /dev/null || die "python3 not found"
command -v curl      > /dev/null || die "curl not found"

GITHUB_TOKEN="$(cat "$TOKEN_FILE")"

# ─── Args ────────────────────────────────────────────────────────────────────
[ "${1:-}" != "" ] || die "Usage: ./scripts/promote_beta.sh <BETA_TAG> [ISSUE_NUMBER]"
BETA_TAG="${1}"
ISSUE_NUMBER="${2:-}"

# Version aus Beta-Tag ableiten: v1.3.1-beta.1 → 1.3.1
BASE_TAG="${BETA_TAG#v}"                   # 1.3.1-beta.1
VERSION="${BASE_TAG%-beta.*}"              # 1.3.1
STABLE_TAG="v${VERSION}"
DMG_NAME="Nexus-${BASE_TAG}.dmg"          # Nexus-1.3.1-beta.1.dmg
STABLE_DMG_NAME="Nexus-${VERSION}.dmg"    # Nexus-1.3.1.dmg

echo -e "${BOLD}🚀 Promoting ${BETA_TAG} → ${STABLE_TAG}${NC}"

# ─── Owner-Freigabe prüfen ───────────────────────────────────────────────────
if [ -n "$ISSUE_NUMBER" ]; then
    info "Prüfe Owner-Freigabe auf Issue #${ISSUE_NUMBER}…"

    # Hilfsfunktion: prüft ob Owner eine +1-Reaktion an einem Endpoint hat
    check_reactions_at() {
        local endpoint="$1"
        curl -sf \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            "${endpoint}?content=%2B1&per_page=100" 2>/dev/null | \
        python3 -c "
import json, sys
try:
    rs = json.load(sys.stdin)
    for r in rs:
        if r.get('user', {}).get('login') == '${OWNER_LOGIN}':
            print('yes')
            sys.exit(0)
    print('no')
except:
    print('no')
" 2>/dev/null
    }

    APPROVED="no"

    # 1. Issue-Reaktionen prüfen
    ISSUE_ENDPOINT="https://api.github.com/repos/${GITHUB_REPO}/issues/${ISSUE_NUMBER}/reactions"
    APPROVED="$(check_reactions_at "$ISSUE_ENDPOINT")"

    # 2. Letzten Kommentar prüfen (typischerweise der Bot-Kommentar mit "Bitte testen")
    if [ "$APPROVED" != "yes" ]; then
        LAST_COMMENT_ID="$(curl -sf \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            "https://api.github.com/repos/${GITHUB_REPO}/issues/${ISSUE_NUMBER}/comments?per_page=100" \
            2>/dev/null | \
        python3 -c "
import json, sys
try:
    cs = json.load(sys.stdin)
    if cs:
        print(cs[-1]['id'])
except:
    pass
" 2>/dev/null)"

        if [ -n "$LAST_COMMENT_ID" ]; then
            COMMENT_ENDPOINT="https://api.github.com/repos/${GITHUB_REPO}/issues/comments/${LAST_COMMENT_ID}/reactions"
            APPROVED="$(check_reactions_at "$COMMENT_ENDPOINT")"
        fi
    fi

    if [ "$APPROVED" != "yes" ]; then
        warn "Keine Freigabe durch ${OWNER_LOGIN} gefunden."
        # Ablehnungs-Kommentar posten
        curl -sf -X POST \
            "https://api.github.com/repos/${GITHUB_REPO}/issues/${ISSUE_NUMBER}/comments" \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Content-Type: application/json" \
            -d '{"body":"🔒 Nur der Entwickler kann diesen Fix freigeben."}' \
            > /dev/null
        die "Abgebrochen: Freigabe durch den Repo-Owner (${OWNER_LOGIN}) mit 👍 erforderlich."
    fi

    success "Freigabe durch ${OWNER_LOGIN} bestätigt ✓"
fi

# ─── 1. Beta-Release auf GitHub suchen ───────────────────────────────────────
info "Looking up beta release ${BETA_TAG}…"
BETA_RELEASE=$(curl -sf \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${BETA_TAG}")

BETA_RELEASE_ID="$(echo "$BETA_RELEASE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['id'])" 2>/dev/null)"
[ -n "$BETA_RELEASE_ID" ] || die "Beta release ${BETA_TAG} not found."

BETA_DMG_URL="$(echo "$BETA_RELEASE" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for a in d.get('assets', []):
    if a['name'].endswith('.dmg'):
        print(a['browser_download_url'])
        break
" 2>/dev/null)"
[ -n "$BETA_DMG_URL" ] || die "DMG asset not found in beta release."
success "Beta release found: $BETA_DMG_URL"

# ─── 2. DMG herunterladen ────────────────────────────────────────────────────
BUILD_DIR="$REPO_ROOT/build"
mkdir -p "$BUILD_DIR"
DMG_PATH="$BUILD_DIR/$STABLE_DMG_NAME"

info "Downloading beta DMG…"
curl -sL -o "$DMG_PATH" "$BETA_DMG_URL"
[ -f "$DMG_PATH" ] && [ "$(stat -f%z "$DMG_PATH")" -gt 1000000 ] || die "DMG download failed or too small."
success "Downloaded: $(du -sh "$DMG_PATH" | awk '{print $1}')"

# ─── 3. Sparkle-Signatur aus beta-appcast.xml lesen ──────────────────────────
info "Reading signature from beta-appcast.xml…"
BETA_APPCAST_PATH="$REPO_ROOT/beta-appcast.xml"
SIGNATURE=""
if [ -f "$BETA_APPCAST_PATH" ]; then
    SIGNATURE="$(grep -o 'sparkle:edSignature="[^"]*"' "$BETA_APPCAST_PATH" | head -1 | sed 's/sparkle:edSignature="\([^"]*\)"/\1/')"
fi

# Fallback: neu signieren
if [ -z "${SIGNATURE:-}" ]; then
    warn "Signature not found in beta-appcast.xml — re-signing DMG…"
    SIGN_UPDATE="$SCRIPT_DIR/sign_update"
    [ -x "$SIGN_UPDATE" ] || die "sign_update not found"
    SIGN_OUTPUT="$("$SIGN_UPDATE" "$DMG_PATH")"
    SIGNATURE="$(echo "$SIGN_OUTPUT" | sed 's/.*sparkle:edSignature="\([^"]*\)".*/\1/')"
    [ -n "$SIGNATURE" ] || die "Re-signing failed."
fi
success "Signature: ${SIGNATURE:0:20}…"

# ─── 4. Release Notes aus CHANGELOG lesen ────────────────────────────────────
NOTES=""
if [ -f "$REPO_ROOT/CHANGELOG.md" ]; then
    NOTES="$(awk "/^## \[${VERSION}\]/{found=1; next} found && /^## \[/{exit} found{print}" "$REPO_ROOT/CHANGELOG.md" | sed '/^$/d')"
fi
[ -z "$NOTES" ] && NOTES="Nexus ${VERSION}"
RELEASE_BODY="$(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$NOTES")"

# ─── 5. Bestehenden Stable-Release löschen (falls vorhanden) ─────────────────
EXISTING_ID="$(curl -sf -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${STABLE_TAG}" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || echo '')"
if [ -n "$EXISTING_ID" ]; then
    curl -sf -X DELETE -H "Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/${GITHUB_REPO}/releases/${EXISTING_ID}" || true
    warn "Deleted existing release for ${STABLE_TAG}"
fi

git -C "$REPO_ROOT" tag -f "$STABLE_TAG" 2>/dev/null || true
git -C "$REPO_ROOT" push "https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git" "$STABLE_TAG" --force 2>/dev/null || true

# ─── 6. Stabilen Release erstellen ───────────────────────────────────────────
info "Creating stable release ${STABLE_TAG}…"
RELEASE_JSON="$(curl -sf -X POST \
    "https://api.github.com/repos/${GITHUB_REPO}/releases" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"tag_name\":\"${STABLE_TAG}\",\"name\":\"Nexus v${VERSION}\",\"body\":${RELEASE_BODY},\"draft\":false,\"prerelease\":false}")"
RELEASE_ID="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d['id'])" <<< "$RELEASE_JSON" 2>/dev/null)"
[ -n "$RELEASE_ID" ] || die "Release creation failed: $RELEASE_JSON"
success "Stable release created (id $RELEASE_ID)"

# ─── 7. DMG hochladen ────────────────────────────────────────────────────────
info "Uploading ${STABLE_DMG_NAME}…"
ASSET_JSON="$(curl -sf -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$DMG_PATH" \
    "https://uploads.github.com/repos/${GITHUB_REPO}/releases/${RELEASE_ID}/assets?name=${STABLE_DMG_NAME}")"
ASSET_URL="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d['browser_download_url'])" <<< "$ASSET_JSON" 2>/dev/null)"
[ -n "$ASSET_URL" ] || die "Upload failed: $ASSET_JSON"
success "Asset: $ASSET_URL"

# ─── 8. appcast.xml generieren ───────────────────────────────────────────────
info "Updating appcast.xml…"
DMG_SIZE="$(stat -f%z "$DMG_PATH")"
RELEASE_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
DMG_URL_STABLE="https://github.com/${GITHUB_REPO}/releases/download/${STABLE_TAG}/${STABLE_DMG_NAME}"

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
            <sparkle:releaseNotesLink>https://github.com/${GITHUB_REPO}/releases/tag/${STABLE_TAG}</sparkle:releaseNotesLink>
            <pubDate>${RELEASE_DATE}</pubDate>
            <enclosure
                url="${DMG_URL_STABLE}"
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
success "appcast.xml generated"

# ─── 9. appcast.xml via GitHub API direkt auf main pushen ────────────────────
info "Pushing appcast.xml to main via GitHub API…"
FILE_INFO="$(curl -sf \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPO}/contents/appcast.xml?ref=main" 2>/dev/null || echo '{}')"
FILE_SHA="$(echo "$FILE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('sha',''))" 2>/dev/null || echo '')"

# macOS BSD base64 needs stdin redirection (bare filename arg is GNU-only, and
# aborts the promote before the stable appcast reaches main).
CONTENT_B64="$(base64 < "$REPO_ROOT/appcast.xml" | tr -d '\n')"

if [ -n "$FILE_SHA" ]; then
    SHA_FIELD=",\"sha\":\"${FILE_SHA}\""
else
    SHA_FIELD=""
fi

API_RESULT="$(curl -sf -X PUT \
    "https://api.github.com/repos/${GITHUB_REPO}/contents/appcast.xml" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"message\":\"Release v${VERSION} (promoted from ${BETA_TAG}): update appcast.xml\",\"content\":\"${CONTENT_B64}\",\"branch\":\"main\"${SHA_FIELD}}")"

echo "$API_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('content',{}).get('name',''))" 2>/dev/null | \
    grep -q "appcast.xml" || die "Failed to push appcast.xml to main via API: $API_RESULT"
success "appcast.xml → main (via GitHub API)"

# ─── 10. GitHub Issue schließen (optional) ───────────────────────────────────
if [ -n "$ISSUE_NUMBER" ]; then
    info "Closing issue #${ISSUE_NUMBER}…"
    curl -sf -X POST \
        "https://api.github.com/repos/${GITHUB_REPO}/issues/${ISSUE_NUMBER}/comments" \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"body\":\"✅ Fix verifiziert und in [v${VERSION}](https://github.com/${GITHUB_REPO}/releases/tag/${STABLE_TAG}) released. Danke fürs Testen! 🎉\"}" \
        > /dev/null
    curl -sf -X PATCH \
        "https://api.github.com/repos/${GITHUB_REPO}/issues/${ISSUE_NUMBER}" \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"state\":\"closed\",\"labels\":[\"verified\"]}" \
        > /dev/null
    success "Issue #${ISSUE_NUMBER} closed with label 'verified'"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}🎉 Nexus v${VERSION} ist stable!${NC}"
echo "   GitHub:  https://github.com/${GITHUB_REPO}/releases/tag/${STABLE_TAG}"
echo "   Appcast: ${APPCAST_URL}"
echo ""
