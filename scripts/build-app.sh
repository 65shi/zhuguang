#!/bin/bash
set -euo pipefail

MAKE_DMG=0
for arg in "$@"; do
    case "$arg" in
        --dmg) MAKE_DMG=1 ;;
        -h|--help)
            echo "Usage: scripts/build-app.sh [--dmg]"
            echo "Builds dist/逐光.app and dist/Zhuguang.zip; --dmg also creates an installer disk image."
            exit 0
            ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Zhuguang"
BUNDLE_NAME="逐光"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/$BUNDLE_NAME.app"
ICON_WORK_DIR="$PROJECT_DIR/.build/app-icon"
ICONSET_DIR="$ICON_WORK_DIR/$APP_NAME.iconset"
STAGING_DIR=""

cleanup() {
    if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
        rm -rf -- "$STAGING_DIR"
    fi
}
trap cleanup EXIT

cd -- "$PROJECT_DIR"
if [[ ! -d "$PROJECT_DIR/Sources/$APP_NAME" ]]; then
    echo "Missing app sources: $PROJECT_DIR/Sources/$APP_NAME" >&2
    exit 1
fi

echo "Building $APP_NAME (release)…"
xcrun swift build --configuration release --arch arm64 --product "$APP_NAME"
BIN_DIR="$(xcrun swift build --configuration release --arch arm64 --show-bin-path)"
if [[ ! -x "$BIN_DIR/$APP_NAME" ]]; then
    echo "Release executable not found: $BIN_DIR/$APP_NAME" >&2
    exit 1
fi

mkdir -p -- "$DIST_DIR" "$ICONSET_DIR"
xcrun swift "$SCRIPT_DIR/generate-icon.swift" "$ICONSET_DIR"
/usr/bin/iconutil --convert icns --output "$ICON_WORK_DIR/$APP_NAME.icns" "$ICONSET_DIR"

# Build in a temporary directory so a failed build preserves the previous app.
STAGING_DIR="$(mktemp -d "$DIST_DIR/.smartlight-build.XXXXXX")"
STAGED_APP="$STAGING_DIR/$BUNDLE_NAME.app"
mkdir -p -- "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
/usr/bin/install -m 755 "$BIN_DIR/$APP_NAME" "$STAGED_APP/Contents/MacOS/$APP_NAME"
/bin/cp "$PROJECT_DIR/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
/bin/cp "$ICON_WORK_DIR/$APP_NAME.icns" "$STAGED_APP/Contents/Resources/$APP_NAME.icns"
for document in README.md SECURITY.md DISCLAIMER.md LICENSE ThirdPartyNotices.md; do
    if [[ -f "$PROJECT_DIR/$document" ]]; then
        /bin/cp "$PROJECT_DIR/$document" "$STAGED_APP/Contents/Resources/$document"
    fi
done
/usr/bin/plutil -lint "$STAGED_APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - --timestamp=none --options runtime \
    --entitlements "$PROJECT_DIR/Resources/Zhuguang.entitlements" "$STAGED_APP"
/usr/bin/codesign --verify --strict "$STAGED_APP"

# These are generated artifacts; no installed application is touched.
rm -rf -- "$APP_DIR"
/bin/mv "$STAGED_APP" "$APP_DIR"
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"
CHECKSUM_FILES=("$APP_NAME.zip")
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$STAGING_DIR/$APP_NAME.zip"
/bin/mv -f "$STAGING_DIR/$APP_NAME.zip" "$ZIP_PATH"
echo "App: $APP_DIR"
echo "ZIP: $ZIP_PATH"

if [[ "$MAKE_DMG" -eq 1 ]]; then
    DMG_SOURCE="$STAGING_DIR/dmg"
    mkdir -p -- "$DMG_SOURCE"
    /usr/bin/ditto "$APP_DIR" "$DMG_SOURCE/$BUNDLE_NAME.app"
    /bin/ln -s /Applications "$DMG_SOURCE/Applications"
    /usr/bin/hdiutil create -quiet -volname "Zhuguang 逐光" -srcfolder "$DMG_SOURCE" \
        -format UDZO "$STAGING_DIR/$APP_NAME.dmg"
    /bin/mv -f "$STAGING_DIR/$APP_NAME.dmg" "$DIST_DIR/$APP_NAME.dmg"
    echo "DMG: $DIST_DIR/$APP_NAME.dmg"
    CHECKSUM_FILES+=("$APP_NAME.dmg")
fi

(cd -- "$DIST_DIR" && /usr/bin/shasum -a 256 "${CHECKSUM_FILES[@]}" > SHA256SUMS.txt)
echo "SHA-256: $DIST_DIR/SHA256SUMS.txt"

echo "Locally ad-hoc signed. Distribution to other Macs requires appropriate Developer ID signing/notarization."
