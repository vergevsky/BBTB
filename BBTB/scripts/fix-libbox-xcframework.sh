#!/usr/bin/env bash
# fix-libbox-xcframework.sh
#
# gomobile bind собирает libbox.xcframework со всеми slice'ами в macOS-style deep bundle
# (Versions/Current/...) с пустым Info.plist. iOS / iOS Simulator / tvOS требуют
# shallow bundle (Info.plist + binary в корне) с непустым CFBundleExecutable / Identifier.
#
# Этот скрипт постобрабатывает libbox.xcframework: для iOS/tvOS slice'ов делает flatten
# из deep в shallow и пишет валидный Info.plist. macOS slice не трогаем — там deep bundle.
#
# Использование:
#   bash scripts/fix-libbox-xcframework.sh
#
# Запускать ОДИН РАЗ после каждой пересборки libbox.xcframework (см. README в Vendored/).

set -euo pipefail

XCFRAMEWORK="$(cd "$(dirname "$0")/.." && pwd)/Vendored/libbox.xcframework"

if [ ! -d "$XCFRAMEWORK" ]; then
  echo "❌ $XCFRAMEWORK not found. Build libbox first via 'make lib_apple' in sing-box repo."
  exit 1
fi

flatten_and_plist() {
  local slice="$1"
  local platform="$2"  # iPhoneOS | iPhoneSimulator | AppleTVOS | AppleTVSimulator
  local min_os="$3"
  local fw="$XCFRAMEWORK/$slice/Libbox.framework"

  [ -d "$fw" ] || { echo "⊘ $slice — skipped (not present)"; return 0; }

  if [ -d "$fw/Versions" ]; then
    echo "Flattening $slice..."
    (
      cd "$fw"
      rm -f Libbox Headers Modules Resources
      if [ -d "Versions/A" ]; then
        mv Versions/A/* .
      elif [ -d "Versions/Current" ]; then
        mv Versions/Current/* .
      fi
      if [ -f "Resources/Info.plist" ]; then
        rm -f Info.plist
        mv Resources/Info.plist Info.plist
      fi
      rm -rf Resources Versions
    )
  fi

  cat > "$fw/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Libbox</string>
    <key>CFBundleIdentifier</key>
    <string>io.nekohasekai.libbox</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Libbox</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.13.11</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>${min_os}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>${platform}</string>
    </array>
</dict>
</plist>
EOF
  echo "  ✓ $slice → shallow + Info.plist ($platform, MinOS ${min_os})"
}

# iOS slices — shallow bundle convention
flatten_and_plist "ios-arm64"                       "iPhoneOS"          "18.0"
flatten_and_plist "ios-arm64_x86_64-simulator"      "iPhoneSimulator"   "18.0"

# tvOS — нам не нужен для BBTB, но если есть в xcframework — обрабатываем
flatten_and_plist "tvos-arm64"                      "AppleTVOS"         "17.0"
flatten_and_plist "tvos-arm64_x86_64-simulator"     "AppleTVSimulator"  "17.0"

# macOS slice оставляем как есть (deep bundle — это валидно для macOS)
echo "⊘ macos-arm64_x86_64 — left as deep bundle (correct for macOS)"

echo
echo "Done. Re-run 'tuist generate' if needed."
