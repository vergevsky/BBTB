import XCTest
@testable import DeepLinks

final class DeepLinkRouterTests: XCTestCase {

    // MARK: - Fakes

    /// In-memory test recorder для verification что handler был invoked, и с каким URL.
    /// `actor` — для thread-safe accumulation между actor boundaries.
    actor HandleRecorder {
        private(set) var urls: [URL] = []
        func record(_ url: URL) {
            urls.append(url)
        }
    }

    /// Fake handler — predicate-driven canHandle + records invocations через `HandleRecorder`.
    struct FakeHandler: DeepLinkHandler {
        static let identifier = "fake"
        let predicate: @Sendable (URL) -> Bool
        let recorder: HandleRecorder

        func canHandle(_ url: URL) -> Bool { predicate(url) }
        func handle(_ url: URL) async throws { await recorder.record(url) }
    }

    // MARK: - Tests

    /// REGISTER + HANDLE — iteration through registered handlers; first matching wins.
    func test_handle_dispatchesToFirstMatchingHandler() async throws {
        let recorder1 = HandleRecorder()
        let recorder2 = HandleRecorder()
        let router = DeepLinkRouter()
        await router.register(FakeHandler(predicate: { _ in false }, recorder: recorder1))
        await router.register(FakeHandler(predicate: { _ in true }, recorder: recorder2))

        let url = URL(string: "bbtb://import?url=https%3A%2F%2Fexample.com")!
        try await router.handle(url)

        let r1 = await recorder1.urls
        let r2 = await recorder2.urls
        XCTAssertEqual(r1.count, 0, "first handler should not match")
        XCTAssertEqual(r2.count, 1, "second handler should receive URL")
        XCTAssertEqual(r2.first, url)
    }

    /// UNHANDLED — no handler matches → DeepLinkError.unhandled thrown.
    func test_handle_throwsUnhandledWhenNoHandlerMatches() async throws {
        let router = DeepLinkRouter()
        let recorder = HandleRecorder()
        await router.register(FakeHandler(predicate: { _ in false }, recorder: recorder))

        let url = URL(string: "bbtb://unknown")!
        do {
            try await router.handle(url)
            XCTFail("expected DeepLinkError.unhandled to be thrown")
        } catch let err as DeepLinkError {
            guard case .unhandled(let u) = err else {
                XCTFail("wrong DeepLinkError case: \(err)")
                return
            }
            XCTAssertEqual(u, url)
        }

        // Recorder must remain untouched — handler was never invoked.
        let urls = await recorder.urls
        XCTAssertEqual(urls.count, 0, "handler should not have been invoked")
    }

    /// REGISTRATION ORDER — first registered wins when both match.
    func test_handle_registrationOrderMatters_firstMatchWins() async throws {
        let recorder1 = HandleRecorder()
        let recorder2 = HandleRecorder()
        let router = DeepLinkRouter()
        // BOTH match — verify first registered wins.
        await router.register(FakeHandler(predicate: { _ in true }, recorder: recorder1))
        await router.register(FakeHandler(predicate: { _ in true }, recorder: recorder2))

        let url = URL(string: "bbtb://import?url=foo")!
        try await router.handle(url)

        let r1 = await recorder1.urls
        let r2 = await recorder2.urls
        XCTAssertEqual(r1.count, 1, "first-registered handler should win")
        XCTAssertEqual(r2.count, 0, "second-registered handler should not be invoked")
    }
}
