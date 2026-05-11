#!/usr/bin/env bash
# DIST-01: iOS archive для TestFlight Internal.
# Usage: bash BBTB/scripts/archive-ios.sh [--upload]
# Без --upload — только сборка archive + export .ipa в build/iOS-Distribution/.
# С --upload — после export пытается xcrun altool --upload-app (требует API key).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

WORKSPACE="BBTB/BBTB.xcworkspace"
SCHEME="BBTB-iOS"
ARCHIVE_PATH="build/BBTB-iOS.xcarchive"
EXPORT_PATH="build/iOS-Distribution"
EXPORT_OPTIONS="BBTB/Config/ExportOptions-iOS.plist"

mkdir -p build

echo "==> Cleaning previous archive (if any)"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

echo "==> Archiving $SCHEME → $ARCHIVE_PATH"
xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -configuration Release \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=UAN8W9Q82U

echo "==> Exporting archive → $EXPORT_PATH"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

echo "✓ iOS archive ready: $EXPORT_PATH"
ls -lh "$EXPORT_PATH"

if [[ "${1:-}" == "--upload" ]]; then
    IPA=$(find "$EXPORT_PATH" -name "*.ipa" | head -1)
    if [[ -z "$IPA" ]]; then
        echo "ERROR: .ipa not found in $EXPORT_PATH"
        exit 1
    fi
    echo "==> Uploading $IPA to App Store Connect"
    # Требует App Store Connect API key (AuthKey_*.p8 в ~/.appstoreconnect/private_keys/)
    # либо AC_API_KEY_ID + AC_API_ISSUER_ID env vars.
    xcrun altool --upload-app -f "$IPA" -t ios \
        --apiKey "${AC_API_KEY_ID:?Need AC_API_KEY_ID}" \
        --apiIssuer "${AC_API_ISSUER_ID:?Need AC_API_ISSUER_ID}"
fi
