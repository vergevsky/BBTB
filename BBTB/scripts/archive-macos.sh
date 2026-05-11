#!/usr/bin/env bash
# DIST-02: macOS archive для TestFlight Internal.
# Usage: bash BBTB/scripts/archive-macos.sh [--upload]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

WORKSPACE="BBTB.xcworkspace"
SCHEME="BBTB-macOS"
ARCHIVE_PATH="build/BBTB-macOS.xcarchive"
EXPORT_PATH="build/macOS-Distribution"
EXPORT_OPTIONS="BBTB/Config/ExportOptions-macOS.plist"

mkdir -p build
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

echo "==> Archiving $SCHEME → $ARCHIVE_PATH"
xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -configuration Release \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=UAN8W9Q82U

echo "==> Exporting archive → $EXPORT_PATH"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

echo "✓ macOS archive ready: $EXPORT_PATH"
ls -lh "$EXPORT_PATH"

if [[ "${1:-}" == "--upload" ]]; then
    PKG=$(find "$EXPORT_PATH" -name "*.pkg" -o -name "*.app" | head -1)
    if [[ -z "$PKG" ]]; then
        echo "ERROR: no .pkg or .app found in $EXPORT_PATH"
        exit 1
    fi
    echo "==> Uploading $PKG to App Store Connect"
    xcrun altool --upload-app -f "$PKG" -t macos \
        --apiKey "${AC_API_KEY_ID:?Need AC_API_KEY_ID}" \
        --apiIssuer "${AC_API_ISSUER_ID:?Need AC_API_ISSUER_ID}"
fi
