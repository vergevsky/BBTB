import XCTest
@testable import RulesEngine

/// Unit tests для `SRSCacheStore` actor — atomic write / read / mtime / exists.
///
/// **Test isolation:** Каждый test использует свежий tmp directory с UUID-наked путём
/// (`FileManager.default.temporaryDirectory.appendingPathComponent("rules-test-\(UUID())")`),
/// в `tearDown` снос. Никаких pollutions между тестами, никаких касаний к App Group.
final class SRSCacheStoreTests: XCTestCase {

    var tmpDir: URL!
    var store: SRSCacheStore!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rules-test-\(UUID().uuidString)", isDirectory: true)
        // SRSCacheStore.init создаёт directory idempotent — отдельный mkdir не нужен.
        store = SRSCacheStore(directory: tmpDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        tmpDir = nil
        store = nil
        try await super.tearDown()
    }

    // MARK: Test 1 — write → read round-trip

    func test_write_thenRead_returnsSameBytes() async throws {
        let payload = Data(repeating: 0xAB, count: 100)
        try await store.write(payload, filename: "test.srs")

        let read = await store.read(filename: "test.srs")
        XCTAssertEqual(read, payload, "Read bytes должны matchиться записанным")
        XCTAssertEqual(read?.count, 100, "Размер должен быть 100 байт")
    }

    // MARK: Test 2 — overwrite replaces existing file

    func test_write_overwritesExistingFile() async throws {
        let first = Data(repeating: 0x01, count: 50)
        let second = Data(repeating: 0x02, count: 80)

        try await store.write(first, filename: "test.srs")
        try await store.write(second, filename: "test.srs")

        let read = await store.read(filename: "test.srs")
        XCTAssertEqual(read, second, "После overwrite файл содержит второй payload")
        XCTAssertEqual(read?.count, 80, "Размер обновлён до 80 байт")
        XCTAssertNotEqual(read, first, "Старый payload не остался")
    }

    // MARK: Test 3 — mtime is recent after write

    func test_mtime_returnsRecentDate_afterWrite() async throws {
        let before = Date()
        try await store.write(Data([0xFF]), filename: "test.srs")
        let after = Date()

        let mtime = await store.mtime(filename: "test.srs")
        XCTAssertNotNil(mtime, "mtime должен присутствовать после write")
        guard let mtime else { return }

        // mtime должен быть между `before` и `after + 5s slack` (filesystem precision).
        XCTAssertGreaterThanOrEqual(
            mtime.timeIntervalSince1970,
            before.timeIntervalSince1970 - 1.0,
            "mtime не должен быть раньше начала теста"
        )
        XCTAssertLessThanOrEqual(
            mtime.timeIntervalSince1970,
            after.timeIntervalSince1970 + 5.0,
            "mtime delta от now < 5 секунд"
        )
    }

    // MARK: Test 4 — read missing file returns nil

    func test_read_returnsNilForMissingFile() async {
        let read = await store.read(filename: "nonexistent.srs")
        XCTAssertNil(read, "Read missing file должен возвращать nil, не throws")
    }

    // MARK: Test 5 — exists flips false → true after write

    func test_exists_returnsFalseBeforeWrite_trueAfter() async throws {
        let existsBefore = await store.exists(filename: "test.srs")
        XCTAssertFalse(existsBefore, "До write файла нет → exists false")

        try await store.write(Data([0xAA]), filename: "test.srs")

        let existsAfter = await store.exists(filename: "test.srs")
        XCTAssertTrue(existsAfter, "После write exists → true")
    }

    // MARK: Test 6 — mtime returns nil для missing file

    func test_mtime_returnsNilForMissingFile() async {
        let mtime = await store.mtime(filename: "ghost.srs")
        XCTAssertNil(mtime, "mtime missing файла = nil")
    }
}
