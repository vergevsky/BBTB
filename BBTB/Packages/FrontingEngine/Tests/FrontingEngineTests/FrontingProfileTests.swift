import Foundation
import Testing
@testable import FrontingEngine

// MARK: - FrontingProfile Codable tests

@Suite("FrontingProfile — Codable + CaseIterable")
struct FrontingProfileTests {

    // MARK: FrontingProfile Codable roundtrip

    @Test("FrontingProfile Codable roundtrip preserves all 6 fields")
    func test_FrontingProfile_codable_roundtrip() throws {
        let original = FrontingProfile(
            provider: .cloudflare,
            connectHost: "1.1.1.1",
            connectPort: 443,
            sniHost: "legit.example.com",
            httpHost: "api.origin.com",
            mode: .domain
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FrontingProfile.self, from: data)

        #expect(decoded.provider == original.provider)
        #expect(decoded.connectHost == original.connectHost)
        #expect(decoded.connectPort == original.connectPort)
        #expect(decoded.sniHost == original.sniHost)
        #expect(decoded.httpHost == original.httpHost)
        #expect(decoded.mode == original.mode)
        #expect(decoded == original)
    }

    // MARK: CDNProvider CaseIterable

    @Test("CDNProvider.allCases has exactly 3 cases")
    func test_CDNProvider_caseIterable() {
        #expect(CDNProvider.allCases.count == 3)
        #expect(CDNProvider.allCases.contains(.cloudflare))
        #expect(CDNProvider.allCases.contains(.fastly))
        #expect(CDNProvider.allCases.contains(.custom))
    }

    // MARK: FrontingMode CaseIterable

    @Test("FrontingMode.allCases has exactly 3 cases")
    func test_FrontingMode_caseIterable() {
        #expect(FrontingMode.allCases.count == 3)
        #expect(FrontingMode.allCases.contains(.domain))
        #expect(FrontingMode.allCases.contains(.ipPool))
        #expect(FrontingMode.allCases.contains(.remoteSigned))
    }

    // MARK: Adapter provider identification

    @Test("CloudflareAdapter.provider == .cloudflare")
    func test_CloudflareAdapter_provider_identifier() {
        #expect(CloudflareAdapter.provider == .cloudflare)
        #expect(CloudflareAdapter.displayName == "Cloudflare")
    }

    @Test("FastlyAdapter.provider == .fastly")
    func test_FastlyAdapter_provider_identifier() {
        #expect(FastlyAdapter.provider == .fastly)
        #expect(FastlyAdapter.displayName == "Fastly")
    }

    @Test("CustomCDNAdapter.provider == .custom")
    func test_CustomCDNAdapter_provider_identifier() {
        #expect(CustomCDNAdapter.provider == .custom)
        #expect(CustomCDNAdapter.displayName == "Custom CDN")
    }
}
