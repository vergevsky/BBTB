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
# (Phase 7c, 2026-05-14: sing-box-specific files relocated to SingBox/ namespace)
check "R1: template has no 'inbounds' key" \
    bash -c '! grep -q "\"inbounds\"" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/Resources/SingBoxConfigTemplate.vless-reality.json'

check "R1: template has empty experimental {}" \
    grep -q '"experimental": {}' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/Resources/SingBoxConfigTemplate.vless-reality.json

# R6: destinationAddresses не присваивается в Sources/
check "R6: no destinationAddresses assignment in PacketTunnelKit Sources" \
    bash -c '! grep -rE "destinationAddresses\s*=" BBTB/Packages/PacketTunnelKit/Sources/'

# R6: assertion вызывается в ExtensionPlatformInterface
# (Phase 7c, 2026-05-14: relocated to SingBox/ namespace)
check "R6: assertNoPointToPointOnUtun is invoked" \
    grep -q "InterfaceFlagsInspector.assertNoPointToPointOnUtun" \
        BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/ExtensionPlatformInterface.swift

# KILL-01 + KILL-02: KillSwitch.apply устанавливает includeAllNetworks + enforceRoutes
check "KILL-01: includeAllNetworks=true in KillSwitch.apply" \
    grep -q "proto.includeAllNetworks = true" BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift

check "KILL-01: enforceRoutes set via PlatformHooks negation" \
    grep -q "proto.enforceRoutes = !platformShouldDisableEnforceRoutes" BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift

check "KILL-01: ConfigImporter zovets KillSwitch.apply" \
    grep -qE "KillSwitch\.apply\(to: ?proto, ?enabled:" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift

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

# Запускаем тесты, нужные для phase gate. SPM packages — через `swift test` в
# директории пакета (Tuist workspace не генерит per-package схемы; main schemes
# собирают app, а не xctest). linkerSettings на testTarget'ах PacketTunnelKit
# и AppFeatures обеспечивают линковку libbox transitive deps.
function run_pkg_tests() {
    local pkg="$1"; local path="$2"
    echo "  → Testing $pkg..."
    if (cd "$path" && swift test 2>&1 | tail -3); then
        echo "  PASS: $pkg tests"
    else
        echo "  FAIL: $pkg tests"
        FAIL=$((FAIL+1))
    fi
}

run_pkg_tests "PacketTunnelKit"  "BBTB/Packages/PacketTunnelKit"
run_pkg_tests "KillSwitch"       "BBTB/Packages/KillSwitch"
run_pkg_tests "ConfigParser"     "BBTB/Packages/ConfigParser"
run_pkg_tests "VPNCore"          "BBTB/Packages/VPNCore"
run_pkg_tests "VLESSReality"     "BBTB/Packages/Protocols/VLESSReality"
run_pkg_tests "Localization"     "BBTB/Packages/Localization"
run_pkg_tests "AppFeatures"      "BBTB/Packages/AppFeatures"
run_pkg_tests "CrashReporter"    "BBTB/Packages/CrashReporter"
run_pkg_tests "RulesEngine"      "BBTB/Packages/RulesEngine"

echo ""
echo "=== Phase 8 Invariants ==="
echo ""

# R8: sing-box vless-reality template has NO inline rule_set entries
# (rule_set is injected at runtime by SingBoxConfigLoader.expandConfigForTunnel — D-01)
check "R8: vless-reality template has no inline rule_set" \
    bash -c '! grep -q "rule_set" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/Resources/SingBoxConfigTemplate.vless-reality.json'

# R8b: SingBoxConfigLoader uses AppGroupContainer paths for rule_set (runtime injection — D-01)
check "R8b: SingBoxConfigLoader uses AppGroupContainer paths for rule_set" \
    grep -q "AppGroupContainer" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift

# RULES-02 / R6-pubkey: publicKeyBytes array in PublicKey.swift contains exactly 32 hex byte literals.
# Uses sed to extract only lines between "private static let publicKeyBytes" and its closing "]".
check "RULES-02: publicKeyBytes array has exactly 32 hex bytes" \
    bash -c 'START=$(grep -n "private static let publicKeyBytes" BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift | cut -d: -f1); END=$(awk "NR>$START && /^    \]$/{print NR; exit}" BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift); [[ $(sed -n "${START},${END}p" BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift | grep -oE "0x[0-9A-Fa-f]{2}" | wc -l | tr -d " ") -eq 32 ]]'

# R12: PublicKey.swift does NOT contain placeholder sequential bytes (0x00, 0x01, 0x02, 0x03)
# Sequential 0x00..0x1F pattern = W1 placeholder that must be replaced before shipping.
check "R12: PublicKey.swift has no placeholder sequential byte pattern (0x00..0x03)" \
    bash -c '! grep -q "0x00, 0x01, 0x02, 0x03" BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift'

# D-08: No NEAppProxyProvider imports remain in main app or AppFeatures
# (AppProxyExtension-macOS target deleted in Phase 8 W0 per D-08/D-09)
check "D-08: no NEAppProxyProvider in main app sources (BBTB/App/iOSApp + macOSApp)" \
    bash -c '! grep -rE "NEAppProxyProvider|app-proxy-provider" BBTB/App/iOSApp BBTB/App/macOSApp 2>/dev/null'

check "D-08: no NEAppProxyProvider in AppFeatures package" \
    bash -c '! grep -rE "NEAppProxyProvider|app-proxy-provider" BBTB/Packages/AppFeatures/Sources 2>/dev/null'

echo ""
if [[ "$FAIL" -eq 0 ]]; then
    echo "✓ ALL STATIC INVARIANTS + UNIT TESTS PASS"
    echo ""
    echo "NEXT: run manual device UAT for Phase 8 (M-04/M-05/M-07/M-08) — see"
    echo "      .planning/phases/08-rules-engine-split-tunneling/08-VALIDATION.md"
    exit 0
else
    echo "✗ $FAIL FAILED — see logs above"
    exit 1
fi
