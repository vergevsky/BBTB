import XCTest
@testable import DeepLinks
import ConfigParser
import VPNCore

/// Phase 9 / Wave 2 — ImportHandler unit tests.
///
/// Coverage matrix (VALIDATION.md rows 09-01-03..09-01-07 + 09-02-01..09-02-02):
///   * canHandle — bbtb://import → true
///   * canHandle — bbtb://other → false
///   * canHandle — Universal Link `https://import.bbtb.app/import…` → true
///   * canHandle — wrong host/path/scheme → false
///   * handle — success → calls importer с decoded URL + source=.deepLink
///   * handle — missing `url` → throws `.missingQueryParameter`
///   * handle — empty `url=` → throws `.missingQueryParameter`
///   * handle — invalid URL value → throws `.invalidParameterValue`
///   * handle — importer throws → wraps в `.importFailed`
final class ImportHandlerTests: XCTestCase {

    // MARK: - Fakes

    /// Stub conforming to `ConfigImporting`. Captures `importFromRawInput` calls
    /// для assertions. Прочие protocol methods вызовут `fatalError` если incidentally
    /// invoked — тесты их не должны trigger'ить.
    final class FakeImporter: ConfigImporting, @unchecked Sendable {
        var capturedInput: String?
        var capturedSource: ImportSource?
        var stubError: Error?

        func importFromRawInput(_ raw: String, source: ImportSource) async throws -> ImportResult {
            capturedInput = raw
            capturedSource = source
            if let err = stubError { throw err }
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
            fatalError("not used in ImportHandlerTests")
        }
        func importFromQRCode(_ scanned: String) async throws -> ImportResult {
            fatalError("not used in ImportHandlerTests")
        }
        func loadActiveServer() -> ServerConfig? { nil }
        func countSupportedConfigs() -> Int { 0 }
        func persistKeychainSecret(for server: ImportedServer) throws -> KeychainPersistResult? {
            fatalError("not used in ImportHandlerTests")
        }
        func buildServerConfig(from server: ImportedServer,
                                id: UUID,
                                subscriptionID: UUID,
                                keychainTag: String?) -> ServerConfig {
            fatalError("not used in ImportHandlerTests")
        }
        func provisionTunnelProfile(for selectedID: UUID?) async throws {
            fatalError("not used in ImportHandlerTests")
        }
        func runIsSupportedUpgrade() async {}
        @MainActor
        func reparseAnyParsedConfig(from cfg: ServerConfig) async -> AnyParsedConfig? { nil }
    }

    // MARK: - canHandle tests

    /// 1. canHandle — bbtb://import?url=… → true (DEEP-01 custom scheme path).
    func test_canHandle_bbtbImport_returnsTrue() throws {
        let h = ImportHandler(importer: FakeImporter())
        XCTAssertTrue(h.canHandle(URL(string: "bbtb://import?url=https://example.com")!))
        XCTAssertTrue(h.canHandle(URL(string: "BBTB://IMPORT?url=https://example.com")!), "scheme/host should be case-insensitive")
    }

    /// 2. canHandle — bbtb://other → false (D-06: connect/disconnect deferred).
    func test_canHandle_unknownScheme_returnsFalse() throws {
        let h = ImportHandler(importer: FakeImporter())
        XCTAssertFalse(h.canHandle(URL(string: "bbtb://connect")!))
        XCTAssertFalse(h.canHandle(URL(string: "bbtb://disconnect")!))
        XCTAssertFalse(h.canHandle(URL(string: "vless://abc@host:443")!))
    }

    /// 3. canHandle — Universal Link `https://import.bbtb.app/import…` → true (DEEP-02).
    func test_canHandle_universalLink_returnsTrue() throws {
        let h = ImportHandler(importer: FakeImporter())
        XCTAssertTrue(h.canHandle(URL(string: "https://import.bbtb.app/import?url=https://example.com")!))
        XCTAssertTrue(h.canHandle(URL(string: "https://import.bbtb.app/import/anything?x=1")!))
    }

    /// 4. canHandle — wrong host/path/scheme → false.
    func test_canHandle_otherPath_returnsFalse() throws {
        let h = ImportHandler(importer: FakeImporter())
        // wrong path
        XCTAssertFalse(h.canHandle(URL(string: "https://import.bbtb.app/landing")!))
        // wrong host
        XCTAssertFalse(h.canHandle(URL(string: "https://other.bbtb.app/import")!))
        // wrong scheme (http, not https)
        XCTAssertFalse(h.canHandle(URL(string: "http://import.bbtb.app/import?x=y")!))
    }

    // MARK: - handle tests

    /// 5. handle — success → calls importer с decoded URL + source=.deepLink (Pitfall #5 single-decode).
    func test_handle_callsImporter_withDecodedURL_andDeepLinkSource() async throws {
        let importer = FakeImporter()
        let h = ImportHandler(importer: importer)
        let encoded = "https%3A%2F%2Fpanel.example.com%2Fsub%2Fabc"
        let url = URL(string: "bbtb://import?url=\(encoded)")!

        try await h.handle(url)

        XCTAssertEqual(importer.capturedInput, "https://panel.example.com/sub/abc")
        XCTAssertEqual(importer.capturedSource, .deepLink)
    }

    /// 6. handle — missing `url` query item → throws `.missingQueryParameter(name: "url")`.
    func test_handle_missingURL_throws() async throws {
        let h = ImportHandler(importer: FakeImporter())
        do {
            try await h.handle(URL(string: "bbtb://import")!)
            XCTFail("expected throw")
        } catch let err as DeepLinkError {
            guard case .missingQueryParameter(let name) = err else {
                XCTFail("wrong case: \(err)"); return
            }
            XCTAssertEqual(name, "url")
        }
    }

    /// 7. handle — empty `url=` → throws `.missingQueryParameter` (treated as missing).
    func test_handle_emptyURL_throws() async throws {
        let h = ImportHandler(importer: FakeImporter())
        do {
            try await h.handle(URL(string: "bbtb://import?url=")!)
            XCTFail("expected throw")
        } catch let err as DeepLinkError {
            guard case .missingQueryParameter = err else {
                XCTFail("wrong case: \(err)"); return
            }
        }
    }

    /// 8. handle — value не URL по форме → throws `.invalidParameterValue`.
    /// Construct URL manually because `URL(string:)` rejects unencoded spaces in
    /// the wrapping deep link. Decoded `url=` value contains a space → `URL(string:)`
    /// returns nil → handler must reject as `.invalidParameterValue`.
    func test_handle_invalidURL_throws() async throws {
        let h = ImportHandler(importer: FakeImporter())
        // After URLComponents.queryItems decode: "https:// space.com" (with embedded space).
        // `URL(string: "https:// space.com")` returns nil — handler rejects.
        var comps = URLComponents()
        comps.scheme = "bbtb"
        comps.host = "import"
        comps.queryItems = [URLQueryItem(name: "url", value: "https:// space.com")]
        let url = comps.url!
        do {
            try await h.handle(url)
            XCTFail("expected throw")
        } catch let err as DeepLinkError {
            guard case .invalidParameterValue(let name, _) = err else {
                XCTFail("wrong case: \(err)"); return
            }
            XCTAssertEqual(name, "url")
        }
    }

    /// 9. handle — importer throws → wraps в `.importFailed(underlying:)`.
    func test_handle_importerThrows_wrapsAsImportFailed() async throws {
        let importer = FakeImporter()
        importer.stubError = NSError(
            domain: "test",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "test-error"]
        )
        let h = ImportHandler(importer: importer)
        do {
            try await h.handle(URL(string: "bbtb://import?url=https%3A%2F%2Fexample.com")!)
            XCTFail("expected throw")
        } catch let err as DeepLinkError {
            guard case .importFailed(let underlying) = err else {
                XCTFail("wrong case: \(err)"); return
            }
            XCTAssertEqual(underlying, "test-error")
        }
    }
}
