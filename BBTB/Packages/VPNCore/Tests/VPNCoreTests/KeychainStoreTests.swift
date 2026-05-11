import XCTest
import Security
@testable import VPNCore

final class KeychainStoreTests: XCTestCase {
    private let testTag = "bbtb-test-\(UUID().uuidString)"

    override func tearDown() {
        try? KeychainStore.delete(tag: testTag)
        super.tearDown()
    }

    func test_saveAndLoad_roundtrip() throws {
        let data = "hello bbtb".data(using: .utf8)!
        try KeychainStore.save(secret: data, tag: testTag)
        let loaded = try KeychainStore.load(tag: testTag)
        XCTAssertEqual(loaded, data)
    }

    func test_load_missingTag_throwsNotFound() {
        XCTAssertThrowsError(try KeychainStore.load(tag: "non-existent-\(UUID().uuidString)")) { err in
            guard case KeychainError.notFound = err else {
                XCTFail("Expected .notFound, got \(err)")
                return
            }
        }
    }

    func test_sec05_accessibleFlag_isWhenUnlocked() throws {
        let data = "secret".data(using: .utf8)!
        try KeychainStore.save(secret: data, tag: testTag)
        let flag = try KeychainStore.accessibleFlag(tag: testTag)
        XCTAssertNotNil(flag)
        // CFEqual вместо ==, т.к. это CFString-references.
        XCTAssertTrue(CFEqual(flag!, kSecAttrAccessibleWhenUnlocked),
                       "SEC-05: kSecAttrAccessible must be kSecAttrAccessibleWhenUnlocked, got \(String(describing: flag))")
    }

    func test_delete_idempotent() throws {
        XCTAssertNoThrow(try KeychainStore.delete(tag: "non-existent-\(UUID().uuidString)"))
    }
}
