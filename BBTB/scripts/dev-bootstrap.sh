#!/usr/bin/env bash
# dev-bootstrap.sh
#
# Воспроизводимая первичная инициализация и пересборка проекта BBTB.
# Запускать после: (a) клонирования репо, (b) пересборки libbox.xcframework,
# (c) любого изменения в Project.swift / Workspace.swift / Tuist/Package.swift.
#
# Что делает:
# 1. Проверяет наличие libbox.xcframework и (если нужно) flatten'ит iOS/tvOS slices.
# 2. Запускает `tuist install` (резолвит SwiftPM dependencies) + `tuist generate`.
# 3. Проверяет xcodebuild build обоих основных схем (BBTB / BBTB-macOS).
#
# Использование:
#   bash scripts/dev-bootstrap.sh                # полный bootstrap
#   bash scripts/dev-bootstrap.sh --skip-build   # только generate, без xcodebuild

set -euo pipefail

cd "$(dirname "$0")/.."   # BBTB/

SKIP_BUILD=0
[ "${1:-}" = "--skip-build" ] && SKIP_BUILD=1

echo "▶ Step 1/4: libbox.xcframework"
if [ ! -d "Vendored/libbox.xcframework" ]; then
  echo "  ✘ Vendored/libbox.xcframework missing. Build it first:"
  echo "    cd /tmp && git clone --depth 1 --branch v1.13.11 https://github.com/SagerNet/sing-box.git"
  echo "    cd sing-box && make lib_apple"
  echo "    cp -R Libbox.xcframework $PWD/Vendored/libbox.xcframework"
  exit 1
fi
if [ -d "Vendored/libbox.xcframework/ios-arm64/Libbox.framework/Versions" ]; then
  echo "  ⊙ iOS slices still in deep bundle — running fix script..."
  bash scripts/fix-libbox-xcframework.sh
else
  echo "  ✓ already flattened"
fi

echo "▶ Step 2/4: Tuist install (SwiftPM resolution)"
tuist install

echo "▶ Step 3/4: Tuist generate"
tuist generate --no-open

if [ "$SKIP_BUILD" -eq 1 ]; then
  echo
  echo "✔ Skipping xcodebuild (--skip-build). Open BBTB.xcworkspace to continue in Xcode."
  exit 0
fi

echo "▶ Step 4/4: xcodebuild smoke (iOS Simulator + macOS)"
echo "  iOS Simulator build..."
xcodebuild build -workspace BBTB.xcworkspace -scheme BBTB \
  -destination 'generic/platform=iOS Simulator' \
  -allowProvisioningUpdates 2>&1 | tail -3

echo "  macOS build..."
xcodebuild build -workspace BBTB.xcworkspace -scheme BBTB-macOS \
  -destination 'generic/platform=macOS' \
  -allowProvisioningUpdates 2>&1 | tail -3

echo
echo "✔ Bootstrap complete. Ready for Xcode (open BBTB.xcworkspace) or W5-T4 device DoD."
