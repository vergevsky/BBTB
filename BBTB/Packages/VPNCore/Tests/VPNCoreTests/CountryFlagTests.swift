// CountryFlagTests.swift — Phase 3 / Plan 03 / Task 1.
//
// Verifies T-03-13 mitigation: ServerConfig.countryFlag computed property валидирует
// country code через regex `^[A-Za-z]{2}$` и возвращает fallback 🌐 при любом mismatch
// (nil, неверная длина, не-латинские символы).
//
// UI-SPEC §7.3 — приоритет источников countryCode (1: URI cc=, 2: fragment regex, 3:
// GeoIP, 4: nil → fallback) — этот тест-кейс покрывает контракт fallback'а.

import XCTest
@testable import VPNCore

final class CountryFlagTests: XCTestCase {

    private func makeServer(countryCode: String?) -> ServerConfig {
        ServerConfig(
            name: "Test",
            host: "example.com",
            port: 443,
            protocolID: "trojan",
            keychainTag: nil,
            countryCode: countryCode
        )
    }

    func test_country_flag_two_letter_code_returns_emoji() {
        let server = makeServer(countryCode: "DE")
        XCTAssertEqual(server.countryFlag, "🇩🇪")
    }

    func test_country_flag_lowercase_normalized() {
        let server = makeServer(countryCode: "de")
        XCTAssertEqual(server.countryFlag, "🇩🇪")
    }

    func test_country_flag_nil_returns_globe() {
        let server = makeServer(countryCode: nil)
        XCTAssertEqual(server.countryFlag, "🌐")
    }

    func test_country_flag_invalid_length_returns_globe() {
        XCTAssertEqual(makeServer(countryCode: "DEU").countryFlag, "🌐")
        XCTAssertEqual(makeServer(countryCode: "").countryFlag, "🌐")
        XCTAssertEqual(makeServer(countryCode: "X").countryFlag, "🌐")
    }

    func test_country_flag_invalid_chars_returns_globe() {
        // T-03-13 mitigation: malicious cc="12" digits → fallback 🌐.
        XCTAssertEqual(makeServer(countryCode: "12").countryFlag, "🌐")
        XCTAssertEqual(makeServer(countryCode: "!@").countryFlag, "🌐")
        XCTAssertEqual(makeServer(countryCode: "A1").countryFlag, "🌐")
    }
}
