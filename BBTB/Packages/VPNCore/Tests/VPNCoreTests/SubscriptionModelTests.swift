import Foundation
import SwiftData
import XCTest
@testable import VPNCore

/// Phase 3 Plan 01 / Task 1 — RED tests for `Subscription` @Model.
///
/// Verifies basic SwiftData CRUD invariants for the new entity:
/// - insert + fetch by `url` predicate (round-trip).
/// - `@Attribute(.unique)` on `id` — повторная вставка с тем же id rejected SwiftData.
///
/// Must FAIL compile/run until `Subscription.swift` exists (Task 2).
final class SubscriptionModelTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Subscription.self, configurations: config)
    }

    @MainActor
    func test_create_subscription_persists_and_fetches_by_url() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let id = UUID()
        let url = "https://x.example/sub-\(UUID().uuidString)"
        let sub = Subscription(id: id, url: url, name: "Example", lastFetched: nil)
        context.insert(sub)
        try context.save()

        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.url == url }
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, id)
        XCTAssertEqual(fetched.first?.name, "Example")
        XCTAssertNil(fetched.first?.lastFetched)
    }

    @MainActor
    func test_subscription_id_is_unique() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let id = UUID()
        let a = Subscription(id: id, url: "https://a.example/sub", name: "A", lastFetched: nil)
        let b = Subscription(id: id, url: "https://b.example/sub", name: "B", lastFetched: nil)
        context.insert(a)
        try context.save()

        // Insert second row with the same id — @Attribute(.unique) на id означает,
        // что SwiftData выполняет upsert (replaces existing) ИЛИ throws на save.
        // В обоих случаях итог: ровно одна row с этим id.
        context.insert(b)
        _ = try? context.save()  // допустимы оба исхода — главное, нет дублей

        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.id == id }
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1, "Subscription.id MUST be unique (@Attribute(.unique))")
    }

    @MainActor
    func test_subscription_lastFetched_round_trip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let url = "https://lf.example/sub"
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let sub = Subscription(url: url, name: "LF", lastFetched: fetchedAt)
        context.insert(sub)
        try context.save()

        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.url == url }
        )
        let row = try context.fetch(descriptor).first
        XCTAssertEqual(row?.lastFetched, fetchedAt)
    }
}
