import XCTest
@testable import MainScreenFeature

final class ConnectionTimerTests: XCTestCase {
    func test_format_zero() {
        XCTAssertEqual(ConnectionTimer.format(interval: 0), "00:00:00")
    }
    func test_format_seconds() {
        XCTAssertEqual(ConnectionTimer.format(interval: 5), "00:00:05")
    }
    func test_format_minutes() {
        XCTAssertEqual(ConnectionTimer.format(interval: 65), "00:01:05")
    }
    func test_format_hours() {
        XCTAssertEqual(ConnectionTimer.format(interval: 3661), "01:01:01")
    }
    func test_format_long() {
        XCTAssertEqual(ConnectionTimer.format(interval: 25 * 3600 + 5 * 60 + 7), "25:05:07")
    }
    func test_format_negative_clamps_to_zero() {
        XCTAssertEqual(ConnectionTimer.format(interval: -123), "00:00:00")
    }
}
