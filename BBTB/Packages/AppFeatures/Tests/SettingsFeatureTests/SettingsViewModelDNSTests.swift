// SettingsViewModelDNSTests.swift — Phase 6 / Plan 06-03 / Wave 3.
//
// Tests for SettingsViewModel DNS settings: @AppStorage persistence + dnsConfig
// priority logic (D-01..D-04 in .planning/phases/06-network-resilience/06-CONTEXT.md).

import XCTest
import VPNCore
@testable import SettingsFeature

@MainActor
final class SettingsViewModelDNSTests: XCTestCase {

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        // @AppStorage backs onto UserDefaults.standard; clear between tests
        // to avoid persistence leakage from previous runs / other tests.
        UserDefaults.standard.removeObject(forKey: "app.bbtb.customDNS")
        UserDefaults.standard.removeObject(forKey: "app.bbtb.adBlockEnabled")
        UserDefaults.standard.removeObject(forKey: "app.bbtb.killSwitchEnabled")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "app.bbtb.customDNS")
        UserDefaults.standard.removeObject(forKey: "app.bbtb.adBlockEnabled")
        UserDefaults.standard.removeObject(forKey: "app.bbtb.killSwitchEnabled")
        try await super.tearDown()
    }

    // MARK: - Default state (Tests 1, 5)

    func test_SettingsViewModel_defaults_customDNS_empty() {
        let vm = SettingsViewModel()
        XCTAssertEqual(vm.customDNS, "")
    }

    func test_SettingsViewModel_defaults_adBlockEnabled_false() {
        let vm = SettingsViewModel()
        XCTAssertFalse(vm.adBlockEnabled)
    }

    func test_SettingsViewModel_dnsConfig_returns_cloudflare_when_defaults() {
        let vm = SettingsViewModel()
        XCTAssertEqual(vm.dnsConfig.tunnelDNS, .cloudflare)
        XCTAssertEqual(vm.dnsConfig.bootstrapAddress, "tcp://1.1.1.1")
    }

    // MARK: - Priority: AdBlock-only (Test 4)

    func test_SettingsViewModel_dnsConfig_returns_adGuard_when_adBlockEnabled() {
        let vm = SettingsViewModel()
        vm.adBlockEnabled = true
        XCTAssertEqual(vm.dnsConfig.tunnelDNS, .adguard)
    }

    // MARK: - Priority: custom > adBlock (Tests 2, 3)

    func test_SettingsViewModel_dnsConfig_returns_custom_when_customDNS_set() {
        let vm = SettingsViewModel()
        vm.customDNS = "8.8.8.8"
        XCTAssertEqual(vm.dnsConfig.tunnelDNS, .custom(address: "tcp://8.8.8.8"))
    }

    func test_SettingsViewModel_dnsConfig_customDNS_wins_over_adBlock() {
        let vm = SettingsViewModel()
        vm.customDNS = "8.8.8.8"
        vm.adBlockEnabled = true
        XCTAssertEqual(vm.dnsConfig.tunnelDNS, .custom(address: "tcp://8.8.8.8"))
    }

    func test_SettingsViewModel_dnsConfig_customDNS_hostname_becomes_doh() {
        let vm = SettingsViewModel()
        vm.customDNS = "my-doh.example.com"
        XCTAssertEqual(
            vm.dnsConfig.tunnelDNS,
            .custom(address: "https://my-doh.example.com/dns-query")
        )
    }

    // MARK: - Whitespace trimming (Test 6)

    func test_SettingsViewModel_dnsConfig_customDNS_whitespace_trimmed() {
        let vm = SettingsViewModel()
        vm.customDNS = "  8.8.8.8  "
        XCTAssertEqual(vm.dnsConfig.tunnelDNS, .custom(address: "tcp://8.8.8.8"))
    }

    // MARK: - Invalid input fallback (Test 7 — Pitfall 9 defense)

    func test_SettingsViewModel_dnsConfig_invalid_customDNS_falls_back_to_cloudflare() {
        let vm = SettingsViewModel()
        vm.customDNS = "not a valid host !!"
        // Invalid + adBlock=false → Cloudflare default (D-02).
        XCTAssertEqual(vm.dnsConfig.tunnelDNS, .cloudflare)
    }

    func test_SettingsViewModel_dnsConfig_invalid_customDNS_falls_back_to_adGuard_if_adBlock() {
        let vm = SettingsViewModel()
        vm.customDNS = "###invalid###"
        vm.adBlockEnabled = true
        // Invalid customDNS → as if empty → adBlock takes over (D-04).
        XCTAssertEqual(vm.dnsConfig.tunnelDNS, .adguard)
    }

    func test_SettingsViewModel_dnsConfig_rejects_out_of_range_octet() {
        let vm = SettingsViewModel()
        vm.customDNS = "1.2.3.999"
        XCTAssertEqual(vm.dnsConfig.tunnelDNS, .cloudflare)
    }

    func test_SettingsViewModel_dnsConfig_rejects_single_label_hostname() {
        let vm = SettingsViewModel()
        vm.customDNS = "localhost"
        XCTAssertEqual(vm.dnsConfig.tunnelDNS, .cloudflare)
    }

    // MARK: - Persistence (Test 8)

    func test_SettingsViewModel_customDNS_persisted_via_AppStorage() {
        let vm1 = SettingsViewModel()
        vm1.customDNS = "1.2.3.4"
        // @AppStorage writes through UserDefaults.standard; a fresh instance
        // should see the same value.
        let vm2 = SettingsViewModel()
        XCTAssertEqual(vm2.customDNS, "1.2.3.4")
    }

    func test_SettingsViewModel_adBlockEnabled_persisted_via_AppStorage() {
        let vm1 = SettingsViewModel()
        vm1.adBlockEnabled = true
        let vm2 = SettingsViewModel()
        XCTAssertTrue(vm2.adBlockEnabled)
    }

    // MARK: - Regression: killSwitch unchanged (Test 9)

    func test_SettingsViewModel_killSwitchEnabled_still_works() {
        let vm = SettingsViewModel()
        XCTAssertFalse(vm.killSwitchEnabled)
        vm.killSwitchEnabled = true
        let vm2 = SettingsViewModel()
        XCTAssertTrue(vm2.killSwitchEnabled)
    }

    // MARK: - Sendable compatibility (Test 10)

    func test_SettingsViewModel_dnsConfig_usable_in_Task_closure() async {
        let vm = SettingsViewModel()
        vm.customDNS = "1.1.1.1"
        let captured = vm.dnsConfig // capture value-type before crossing actor
        let result: DNSConfig = await Task.detached {
            // DNSConfig is Sendable — must compile and propagate untouched.
            return captured
        }.value
        XCTAssertEqual(result.tunnelDNS, .custom(address: "tcp://1.1.1.1"))
    }
}
