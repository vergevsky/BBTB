import XCTest
@testable import DeepLinks
import ConfigParser
import VPNCore

/// Phase 9 / Wave 2 — URL parsing edge cases (Pitfall #5 verifications).
///
/// Coverage focus: ImportHandler's percent-decoding pipeline behavior. URLComponents
/// performs **single** percent-decode of query item values; ImportHandler never
/// double-decodes (per RESEARCH.md § Pitfall 5).
///
/// Tests exercise the boundary через FakeImporter что capture'ит decoded raw input.
final class URLParsingTests: XCTestCase {

    // MARK: - Fakes

    /// Captures decoded raw input forwarded to importer. Tests assert на captured value.
    /// Returns empty ImportResult и не throws — full handler flow proceed'ит до return.
    final class CaptureImporter: ConfigImporting, @unchecked Sendable {
        var captured: String?

        func importFromRawInput(_ raw: String, source: ImportSource) async throws -> ImportResult {
            captured = raw
            return ImportResult(
                supported: [],
                unsupported: [],
                failed: [],
                subscriptionURL: nil,
                source: source,
                metadata: nil
            )
        }

        func importFromPasteboard() async throws -> ImportResult {
            fatalError("not used in URLParsingTests")
        }
        func importFromQRCode(_ scanned: String) async throws -> ImportResult {
            fatalError("not used in URLParsingTests")
        }
        func loadActiveServer() -> ServerConfig? { nil }
        func countSupportedConfigs() -> Int { 0 }
        func persistKeychainSecret(for server: ImportedServer) throws -> KeychainPersistResult? {
            fatalError("not used in URLParsingTests")
        }
        func buildServerConfig(from server: ImportedServer,
                                id: UUID,
                                subscriptionID: UUID,
                                keychainTag: String?) -> ServerConfig {
            fatalError("not used in URLParsingTests")
        }
        func provisionTunnelProfile(for selectedID: UUID?) async throws {
            fatalError("not used in URLParsingTests")
        }
        func runIsSupportedUpgrade() async {}
        @MainActor
        func reparseAnyParsedConfig(from cfg: ServerConfig) async -> AnyParsedConfig? { nil }
    }

    // MARK: - Edge cases

    /// 1. Standard percent-encoding — URLComponents auto-decodes once.
    func test_standardPercentEncoded_decodesToOriginalURL() async throws {
        let importer = CaptureImporter()
        let h = ImportHandler(importer: importer)
        let original = "https://panel.example.com/sub/abc?token=xyz"
        let encoded = original.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "bbtb://import?url=\(encoded)")!

        try await h.handle(url)

        XCTAssertEqual(importer.captured, original)
    }

    /// 2. Double-encoded — first decode preserves intermediate form (intentional per Pitfall #5).
    /// `https%253A%252F%252Fexample.com` → after single decode by URLComponents →
    /// `https%3A%2F%2Fexample.com`. `URL(string:)` of that string returns nil (percent
    /// triplet не valid в host) → handler rejects as `.invalidParameterValue`.
    /// Verify captured is nil (handler did NOT reach importer — no double-decode).
    func test_doubleEncodedURL_singleDecodeOnly() async throws {
        let importer = CaptureImporter()
        let h = ImportHandler(importer: importer)
        let outerEncoded = "https%253A%252F%252Fexample.com"
        let url = URL(string: "bbtb://import?url=\(outerEncoded)")!

        do {
            try await h.handle(url)
            // If handler did NOT throw, value made it through — either way it must
            // be the once-decoded intermediate (not double-decoded "https://example.com").
            XCTAssertNotEqual(importer.captured, "https://example.com",
                               "ImportHandler MUST NOT double-decode")
        } catch let err as DeepLinkError {
            // Expected path: URL(string: "https%3A%2F%2Fexample.com") returns nil →
            // .invalidParameterValue throw, importer never invoked.
            guard case .invalidParameterValue = err else {
                XCTFail("expected .invalidParameterValue, got \(err)"); return
            }
            XCTAssertNil(importer.captured, "importer must not be invoked when value invalid")
        }
    }

    /// 3. Plus sign in query value — URLComponents preserves as `+`, not decoded as space
    /// (the `+ = space` decoding is x-www-form-urlencoded convention, not RFC 3986).
    func test_plusSignInQueryValue_preservedAsPlus() async throws {
        let importer = CaptureImporter()
        let h = ImportHandler(importer: importer)
        // url=https://example.com/path?a=1+2 — `+` preserved, not converted to space.
        let url = URL(string: "bbtb://import?url=https%3A%2F%2Fexample.com%2Fpath%3Fa%3D1%2B2")!

        try await h.handle(url)

        XCTAssertEqual(importer.captured, "https://example.com/path?a=1+2")
    }

    /// 4. Multibyte (Cyrillic) percent-encoded path segment — auto-decode preserves UTF-8.
    func test_multibytePercentEncoded_decodesUTF8() async throws {
        let importer = CaptureImporter()
        let h = ImportHandler(importer: importer)
        let original = "https://example.com/тест"
        let encoded = original.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "bbtb://import?url=\(encoded)")!

        try await h.handle(url)

        XCTAssertEqual(importer.captured, original)
    }

    /// 5. Empty `?` (no query items) — throws `.missingQueryParameter`.
    func test_emptyQueryString_throwsMissingParam() async throws {
        let h = ImportHandler(importer: CaptureImporter())
        do {
            try await h.handle(URL(string: "bbtb://import?")!)
            XCTFail("expected throw")
        } catch let err as DeepLinkError {
            guard case .missingQueryParameter = err else {
                XCTFail("wrong case: \(err)"); return
            }
        }
    }
}
