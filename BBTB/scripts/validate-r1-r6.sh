#!/usr/bin/env bash
# Phase 1 security validation script.
# Запускает:
# - все unit-тесты, относящиеся к R1, R6, KILL-01/02
# - grep-инварианты по source-коду (R1 template, R6 без destinationAddresses)
# - проверка структуры артефактов (entitlements, SocksProbe изоляция)
#
# Не делает device-smoke (это manual в W5-T4).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

FAIL=0
function check() {
    local label="$1"; shift
    if "$@" > /dev/null 2>&1; then
        echo "PASS: $label"
    else
        echo "FAIL: $label  (cmd: $*)"
        FAIL=$((FAIL+1))
    fi
}

echo "=== Phase 1 R1/R6/KILL Static Invariants ==="
echo ""

# R1: SingBoxConfigTemplate не содержит inbounds
check "R1: template has no 'inbounds' key" \
    bash -c '! grep -q "\"inbounds\"" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json'

check "R1: template has empty experimental {}" \
    grep -q '"experimental": {}' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json

# R6: destinationAddresses не присваивается в Sources/
check "R6: no destinationAddresses assignment in PacketTunnelKit Sources" \
    bash -c '! grep -rE "destinationAddresses\s*=" BBTB/Packages/PacketTunnelKit/Sources/'

# R6: assertion вызывается в ExtensionPlatformInterface
check "R6: assertNoPointToPointOnUtun is invoked" \
    grep -q "InterfaceFlagsInspector.assertNoPointToPointOnUtun" \
        BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift

# KILL-01 + KILL-02: KillSwitch.apply устанавливает includeAllNetworks + enforceRoutes
check "KILL-01: includeAllNetworks=true in KillSwitch.apply" \
    grep -q "proto.includeAllNetworks = true" BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift

check "KILL-01: enforceRoutes set via PlatformHooks negation" \
    grep -q "proto.enforceRoutes = !platformShouldDisableEnforceRoutes" BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift

check "KILL-01: ConfigImporter zovets KillSwitch.apply" \
    grep -q "KillSwitch.apply(to: proto)" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift

# SocksProbe изоляция (W1-T3)
check "SEC-03: SocksProbe iOS entitlements БЕЗ application-groups" \
    bash -c '! grep -q "application-groups" BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbe-iOS.entitlements'

check "SEC-03: SocksProbe iOS entitlements БЕЗ keychain-access-groups" \
    bash -c '! grep -q "keychain-access-groups" BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbe-iOS.entitlements'

check "SEC-03: SocksProbe macOS entitlements БЕЗ application-groups" \
    bash -c '! grep -q "application-groups" BBTB/Tools/SocksProbe/SocksProbe-macOS/SocksProbe-macOS.entitlements'

# SEC-05: kSecAttrAccessibleWhenUnlocked
check "SEC-05: kSecAttrAccessibleWhenUnlocked в KeychainStore" \
    grep -q "kSecAttrAccessibleWhenUnlocked" BBTB/Packages/VPNCore/Sources/VPNCore/KeychainStore.swift

echo ""
echo "=== Unit Tests (R1, R6, KILL-01/02, SEC-05) ==="

# Запускаем тесты, нужные для phase gate.
function run_tests() {
    local scheme="$1"
    echo "  → Testing $scheme..."
    if xcodebuild test -workspace BBTB.xcworkspace -scheme "$scheme" \
        -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | tail -5; then
        echo "  PASS: $scheme tests"
    else
        echo "  FAIL: $scheme tests"
        FAIL=$((FAIL+1))
    fi
}

run_tests "PacketTunnelKit"
run_tests "KillSwitch"
run_tests "ConfigParser"
run_tests "VPNCore"
run_tests "VLESSReality"
run_tests "Localization"
run_tests "MainScreenFeature"
run_tests "CrashReporter"

echo ""
if [[ "$FAIL" -eq 0 ]]; then
    echo "✓ ALL STATIC INVARIANTS + UNIT TESTS PASS"
    echo ""
    echo "NEXT: run W5-T4 manual device smoke for R1/R6/KILL-02/DoD#1 — see"
    echo "      .planning/phases/01-foundation/security-evidence/README.md"
    exit 0
else
    echo "✗ $FAIL FAILED — see logs above"
    exit 1
fi
