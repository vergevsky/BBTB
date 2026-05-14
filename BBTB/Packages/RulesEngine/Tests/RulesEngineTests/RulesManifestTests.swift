import XCTest
@testable import RulesEngine

/// Tests для `RulesManifest` Codable schema + `BaselineRulesLoader` Bundle.module resource access.
///
/// **Acceptance focus:** baseline manifest бандлится правильно (Package.swift `.process("Resources")`
/// declaration) И декодируется без потерь (snake_case ↔ camelCase mapping integrity).
final class RulesManifestTests: XCTestCase {

    // MARK: Test 1 — baseline manifest decodes successfully

    func test_decodeBaselineManifest() throws {
        let (data, _) = try BaselineRulesLoader.loadManifest()
        let manifest = try JSONDecoder().decode(RulesManifest.self, from: data)

        // Sanity — поля decoded без throws.
        XCTAssertEqual(manifest.minAppVersion, "0.8.0", "minAppVersion должен decode из min_app_version")
        XCTAssertEqual(manifest.srsFormatVersion, 4, "srsFormatVersion должен decode из srs_format_version")
        XCTAssertEqual(manifest.totalSizeBytes, 0, "totalSizeBytes должен decode из total_size_bytes")
    }

    // MARK: Test 2 — baseline has version 0

    func test_baselineHasVersion0() throws {
        let (data, _) = try BaselineRulesLoader.loadManifest()
        let manifest = try JSONDecoder().decode(RulesManifest.self, from: data)
        XCTAssertEqual(manifest.version, 0, "Baseline manifest должен иметь version=0 (signal никогда не fetched)")
    }

    // MARK: Test 3 — baseline contains 3 file entries (one per category)

    func test_baselineHas3FileEntries() throws {
        let (data, _) = try BaselineRulesLoader.loadManifest()
        let manifest = try JSONDecoder().decode(RulesManifest.self, from: data)
        XCTAssertEqual(manifest.files.count, 3, "Должно быть ровно 3 file entries (по одному на category)")
    }

    // MARK: Test 4 — file entries cover все три Category enum cases

    func test_baselineCategoryEnum_decodesAllThree() throws {
        let (data, _) = try BaselineRulesLoader.loadManifest()
        let manifest = try JSONDecoder().decode(RulesManifest.self, from: data)

        let categories = Set(manifest.files.map { $0.category })
        XCTAssertEqual(categories.count, 3, "Уникальных category должно быть 3")
        XCTAssertTrue(categories.contains(.block), "Должен быть .block (block_completely)")
        XCTAssertTrue(categories.contains(.never), "Должен быть .never (never_through_vpn)")
        XCTAssertTrue(categories.contains(.always), "Должен быть .always (always_through_vpn)")
    }

    // MARK: Test 5 — BaselineRulesLoader загружает все 4 ресурса (manifest+sig + 3 srs+sig)

    func test_BaselineRulesLoader_loadsAll4Resources() throws {
        // 1. Manifest + sig
        let (manifestData, manifestSig) = try BaselineRulesLoader.loadManifest()
        XCTAssertGreaterThan(manifestData.count, 0, "Manifest JSON не должен быть пустым")
        XCTAssertEqual(manifestSig.count, 64, "Manifest signature placeholder = 64 байта (W2)")

        // 2. SRS .block
        let (srsBlock, sigBlock) = try BaselineRulesLoader.loadSRS(category: .block)
        XCTAssertEqual(srsBlock.count, 4, ".srs placeholder = 4 байта magic header")
        XCTAssertEqual(sigBlock.count, 64, ".srs.sig placeholder = 64 байта")

        // 3. SRS .never
        let (srsNever, sigNever) = try BaselineRulesLoader.loadSRS(category: .never)
        XCTAssertEqual(srsNever.count, 4)
        XCTAssertEqual(sigNever.count, 64)

        // 4. SRS .always
        let (srsAlways, sigAlways) = try BaselineRulesLoader.loadSRS(category: .always)
        XCTAssertEqual(srsAlways.count, 4)
        XCTAssertEqual(sigAlways.count, 64)
    }

    // MARK: Test 6 — baseline manifest содержит ожидаемые domains в block_completely (max.ru, mssgr.tatar.ru)

    func test_baselineManifest_blockCompletely_containsMaxRu() throws {
        let (data, _) = try BaselineRulesLoader.loadManifest()
        let manifest = try JSONDecoder().decode(RulesManifest.self, from: data)

        XCTAssertNotNil(manifest.blockCompletely, "block_completely должен decode как CategoryBodies")
        XCTAssertEqual(manifest.blockCompletely?.domains ?? [], ["max.ru", "mssgr.tatar.ru"],
                       "Baseline block содержит ровно max.ru + mssgr.tatar.ru (sync с wiki/max-messenger.md)")

        // never / always категории должны быть empty (но present).
        XCTAssertEqual(manifest.neverThroughVpn?.domains ?? [], [], "Baseline never пуст")
        XCTAssertEqual(manifest.alwaysThroughVpn?.domains ?? [], [], "Baseline always пуст")
    }

    // MARK: Test 7 — RulesSnapshot + CategoryEntries Sendable+Equatable smoke

    func test_RulesSnapshot_equatable_smoke() {
        let entry = CategoryEntries(domains: ["a.com"], ipCidrs: ["1.0.0.0/24"], countries: ["RU"])
        let s1 = RulesSnapshot(
            version: 1, lastFetchedAt: Date(timeIntervalSince1970: 1000),
            block: entry, never: CategoryEntries(), always: CategoryEntries(),
            minAppVersion: "0.8.0"
        )
        let s2 = RulesSnapshot(
            version: 1, lastFetchedAt: Date(timeIntervalSince1970: 1000),
            block: entry, never: CategoryEntries(), always: CategoryEntries(),
            minAppVersion: "0.8.0"
        )
        XCTAssertEqual(s1, s2, "Identical RulesSnapshots должны быть Equatable")
    }
}
