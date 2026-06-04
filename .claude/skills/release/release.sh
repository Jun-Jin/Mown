#!/usr/bin/env bash
#
# Build, sign, notarize, and staple Mown for Developer ID distribution
# (outside the Mac App Store — see SPEC.md §8). Produces a notarized, stapled
# artifact under ./dist/ that runs on any Mac with Gatekeeper enabled.
#
# Pipeline: Release build → codesign (Developer ID + hardened runtime +
# secure timestamp) → notarytool submit → stapler staple → package (zip, and
# optionally a DMG).
#
# ── One-time prerequisites (interactive / secret — you do these) ─────────────
#   1. Install a "Developer ID Application" certificate + its private key:
#        Xcode ▸ Settings ▸ Accounts ▸ (Apple ID) ▸ Manage Certificates
#          ▸ "+" ▸ Developer ID Application
#      Verify:  security find-identity -v -p codesigning
#      (should list  "Developer ID Application: NAME (TEAMID)")
#
#   2. Store notarization credentials in the keychain under a profile name:
#        xcrun notarytool store-credentials "MownNotary" \
#            --apple-id "you@example.com" \
#            --team-id  "TEAMID" \
#            --password "app-specific-password"
#      The app-specific password comes from
#        appleid.apple.com ▸ Sign-In and Security ▸ App-Specific Passwords
#      (NOT your normal Apple ID password). An App Store Connect API key works
#      too: store-credentials --key / --key-id / --issuer.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash .claude/skills/release/release.sh                 # sign + notarize + staple + zip
#   bash .claude/skills/release/release.sh --dmg           # also build a notarized DMG
#   bash .claude/skills/release/release.sh --no-notarize   # sign only (local smoke test)
#   NOTARY_PROFILE=MownNotary IDENTITY="Developer ID Application: …" \
#       bash .claude/skills/release/release.sh             # override autodetected values
set -euo pipefail

NOTARIZE=1
MAKE_DMG=0
for arg in "$@"; do
    case "$arg" in
        --dmg)          MAKE_DMG=1 ;;
        --no-notarize)  NOTARIZE=0 ;;
        *) echo "Unknown option: $arg" >&2
           echo "Usage: release.sh [--dmg] [--no-notarize]" >&2
           exit 2 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

PROJECT="Mown.xcodeproj"
SCHEME="Mown"
TARGET="Mown"
PROFILE="${NOTARY_PROFILE:-MownNotary}"
DIST="$REPO_ROOT/dist"

# ── Resolve the Developer ID signing identity ───────────────────────────────
# Prefer an explicit IDENTITY override; otherwise pick the first installed
# "Developer ID Application" certificate from the login keychain.
if [[ -z "${IDENTITY:-}" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning \
        | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
if [[ -z "${IDENTITY:-}" ]]; then
    cat >&2 <<'EOF'
No "Developer ID Application" certificate found in the keychain.

Install one first (one-time):
  Xcode ▸ Settings ▸ Accounts ▸ (your Apple ID) ▸ Manage Certificates
    ▸ "+" ▸ Developer ID Application
Then re-run this script. (security find-identity -v -p codesigning should
list it.)
EOF
    exit 1
fi
# Team ID is the 10-char code in the identity's trailing parentheses.
TEAM_ID="$(sed -E 's/.*\(([A-Z0-9]+)\)$/\1/' <<<"$IDENTITY")"
echo "Signing identity: $IDENTITY"
echo "Team ID:          $TEAM_ID"

# ── Build (Release, unsigned — we sign explicitly below) ─────────────────────
LOG="$(mktemp -t mown_release.XXXXXX.log)"
echo "Building $SCHEME (Release)…"
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        build CODE_SIGNING_ALLOWED=NO >"$LOG" 2>&1; then
    echo "BUILD FAILED — errors:" >&2
    grep -nE "error:" "$LOG" | head -40 || tail -30 "$LOG"
    echo "(full log: $LOG)" >&2
    exit 1
fi

# Resolve the product path from build settings (same approach as rebuild.sh) so
# we don't hardcode the machine-specific DerivedData hash.
SRC_APP="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -showBuildSettings -json 2>/dev/null | python3 -c '
import json, sys
for item in json.load(sys.stdin):
    if item.get("target") == "'"$TARGET"'":
        bs = item["buildSettings"]
        print(bs["TARGET_BUILD_DIR"] + "/" + bs["FULL_PRODUCT_NAME"])
        break
')"
if [[ -z "$SRC_APP" || ! -d "$SRC_APP" ]]; then
    echo "Build succeeded but product not found at: ${SRC_APP:-<unresolved>}" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
            "$SRC_APP/Contents/Info.plist" 2>/dev/null || echo "0.0.0")"
echo "Version:          $VERSION"

# Stage a fresh copy so signing never mutates the DerivedData product.
rm -rf "$DIST"
mkdir -p "$DIST"
APP="$DIST/Mown.app"
cp -R "$SRC_APP" "$APP"

# ── Codesign: nested Mach-O first (deepest-first), then the outer app ────────
# A Release bundle is normally flat, but sign any embedded frameworks/dylibs/
# helpers first so the seal stays valid if that ever changes.
SIGN_FLAGS=(--force --options runtime --timestamp --sign "$IDENTITY")
while IFS= read -r -d '' nested; do
    echo "Signing nested: ${nested#$APP/}"
    codesign "${SIGN_FLAGS[@]}" "$nested"
done < <(find "$APP/Contents" \
            \( -name "*.framework" -o -name "*.dylib" -o -name "*.appex" \) \
            -print0 2>/dev/null | sort -rz)

echo "Signing app bundle…"
codesign "${SIGN_FLAGS[@]}" "$APP"

echo "Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP"

if [[ "$NOTARIZE" -eq 0 ]]; then
    echo "✅ Signed (not notarized): $APP"
    echo "   (Gatekeeper will still warn until notarized. Re-run without --no-notarize.)"
    exit 0
fi

# ── Notarize the app, then staple the ticket onto it ─────────────────────────
ZIP="$DIST/Mown-$VERSION.zip"
echo "Zipping for notarization…"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Submitting to notary service (profile: $PROFILE)… this can take a few minutes."
if ! xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait; then
    cat >&2 <<EOF

Notarization submit failed. Most common cause: the keychain profile
"$PROFILE" doesn't exist yet. Create it (one-time):

  xcrun notarytool store-credentials "$PROFILE" \\
      --apple-id "you@example.com" --team-id "$TEAM_ID" \\
      --password "app-specific-password"

To inspect a rejected submission:
  xcrun notarytool log <submission-id> --keychain-profile "$PROFILE"
EOF
    exit 1
fi

echo "Stapling ticket onto the app…"
xcrun stapler staple "$APP"

# Re-zip the *stapled* app as the distributable (the earlier zip predates the
# ticket). Stapling applies to the .app, not the zip.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "→ $ZIP"

# ── Optional: notarized + stapled DMG ────────────────────────────────────────
if [[ "$MAKE_DMG" -eq 1 ]]; then
    DMG="$DIST/Mown-$VERSION.dmg"
    STAGE="$(mktemp -d)"
    cp -R "$APP" "$STAGE/Mown.app"
    ln -s /Applications "$STAGE/Applications"
    echo "Building DMG…"
    hdiutil create -volname "Mown" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
    echo "Notarizing DMG…"
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "→ $DMG"
fi

# ── Final verification — what Gatekeeper sees on a clean Mac ──────────────────
echo "Gatekeeper assessment:"
spctl -a -vvv -t exec "$APP" || true
xcrun stapler validate "$APP" || true

echo "✅ Done. Distributable(s) in: $DIST"
