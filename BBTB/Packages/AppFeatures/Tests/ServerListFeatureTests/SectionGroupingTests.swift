// SectionGroupingTests.swift — Phase 3 / Plan 03 / Task 1.
//
// Verifies pure-function `ServerListViewModel.groupSections(...)` корректно группирует
// серверы по subscriptionID в секции, добавляет «Manual» секцию для orphan-серверов,
// сортирует подписки по `lastFetched` DESC (nil last), и не создаёт пустых секций.
//
// Test-cases:
// 1. Базовая группировка — 2 подписки + orphan → 3 секции в правильном порядке.
// 2. Manual секция появляется ТОЛЬКО при наличии orphan.
// 3. Сортировка подписок: lastFetched DESC, nil идёт в конце subscription-секций.
// 4. Пустой ввод — пустой массив секций.

import XCTest
import VPNCore
@testable import ServerListFeature

final class SectionGroupingTests: XCTestCase {

    private func makeServer(subscriptionID: UUID?, name: String = "srv") -> ServerConfig {
        ServerConfig(
            name: name,
            host: "\(name).example.com",
            port: 443,
            protocolID: "trojan",
            keychainTag: nil,
            subscriptionID: subscriptionID
        )
    }

    private func makeSubscription(name: String, lastFetched: Date?) -> Subscription {
        Subscription(url: "https://\(name).example.com/sub", name: name, lastFetched: lastFetched)
    }

    func test_groups_servers_by_subscription_id() {
        let subA = makeSubscription(name: "A", lastFetched: Date(timeIntervalSinceNow: -3600))
        let subB = makeSubscription(name: "B", lastFetched: Date(timeIntervalSinceNow: -300))
        let server1 = makeServer(subscriptionID: subA.id, name: "s1")
        let server2 = makeServer(subscriptionID: subA.id, name: "s2")
        let server3 = makeServer(subscriptionID: subB.id, name: "s3")
        let orphan = makeServer(subscriptionID: nil, name: "manual")

        let sections = ServerListViewModel.groupSections(
            subscriptions: [subA, subB],
            servers: [server1, server2, server3, orphan]
        )

        // Sorted by lastFetched DESC: subB (5 min ago) then subA (1h ago), manual at end.
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].subscription?.id, subB.id)
        XCTAssertEqual(sections[0].servers.count, 1)
        XCTAssertEqual(sections[1].subscription?.id, subA.id)
        XCTAssertEqual(sections[1].servers.count, 2)
        XCTAssertNil(sections[2].subscription)
        XCTAssertEqual(sections[2].servers.count, 1)
    }

    func test_orphan_section_only_when_orphans_exist() {
        let subA = makeSubscription(name: "A", lastFetched: nil)
        let server1 = makeServer(subscriptionID: subA.id)

        let sections = ServerListViewModel.groupSections(
            subscriptions: [subA],
            servers: [server1]
        )

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].subscription?.id, subA.id)
    }

    func test_section_sort_by_lastFetched_desc() {
        let subOld = makeSubscription(name: "Old", lastFetched: Date(timeIntervalSinceNow: -7200))
        let subNew = makeSubscription(name: "New", lastFetched: Date(timeIntervalSinceNow: -60))
        let subNil = makeSubscription(name: "Nil", lastFetched: nil)
        let s1 = makeServer(subscriptionID: subOld.id)
        let s2 = makeServer(subscriptionID: subNew.id)
        let s3 = makeServer(subscriptionID: subNil.id)

        let sections = ServerListViewModel.groupSections(
            subscriptions: [subOld, subNew, subNil],
            servers: [s1, s2, s3]
        )

        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].subscription?.name, "New")
        XCTAssertEqual(sections[1].subscription?.name, "Old")
        XCTAssertEqual(sections[2].subscription?.name, "Nil")
    }

    func test_empty_state() {
        let sections = ServerListViewModel.groupSections(subscriptions: [], servers: [])
        XCTAssertTrue(sections.isEmpty)
    }

    func test_empty_subscription_excluded() {
        // Подписка без серверов не должна порождать секцию.
        let subA = makeSubscription(name: "A", lastFetched: nil)
        let subB = makeSubscription(name: "B", lastFetched: nil)
        let server = makeServer(subscriptionID: subA.id)

        let sections = ServerListViewModel.groupSections(
            subscriptions: [subA, subB],
            servers: [server]
        )

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].subscription?.id, subA.id)
    }
}
