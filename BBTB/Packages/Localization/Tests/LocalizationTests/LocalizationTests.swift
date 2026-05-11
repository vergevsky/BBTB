import XCTest
@testable import Localization

final class LocalizationTests: XCTestCase {
    func test_allKeys_haveEnAndRu() throws {
        // Загружаем .xcstrings JSON напрямую — это smoke на наличие обоих языков для каждого ключа.
        let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings")
        XCTAssertNotNil(url, "Localizable.xcstrings must be bundled via Bundle.module")
        let data = try Data(contentsOf: url!)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let strings = json["strings"] as! [String: Any]

        for (key, raw) in strings {
            let entry = raw as! [String: Any]
            let localizations = entry["localizations"] as! [String: Any]
            XCTAssertNotNil(localizations["en"], "Key '\(key)' missing en localization")
            XCTAssertNotNil(localizations["ru"], "Key '\(key)' missing ru localization")
        }
    }

    func test_keyCount_atLeast20() throws {
        let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings")!
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let strings = json["strings"] as! [String: Any]
        XCTAssertGreaterThanOrEqual(strings.count, 20, "Phase 1 expected ~22 keys; current count: \(strings.count)")
    }

    func test_L10n_namespacedAccessReturnsLocalizedString() {
        // На macOS default locale обычно en. Sanity: app.short_name → "BBTB".
        XCTAssertFalse(L10n.appShortName.isEmpty)
        XCTAssertFalse(L10n.statusIdle.isEmpty)
    }
}
