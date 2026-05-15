// MAXDetector.swift — Phase 11 / Plan 04 / Task 4.1.
//
// Silent best-effort detection факта установки MAX-мессенджера (VK 2025).
// Используется как diagnostic facility (DETECT-01 iOS / DETECT-02 macOS) —
// если пользователь жалуется на блокировку, разработчик видит в логе, что
// MAX-app присутствует на устройстве, и может посоветовать ситуативные
// настройки (например через rules.json `block_completely` DETECT-03).
//
// **Никакого UI side-effect.** Detection пишет ровно одну os.Logger.info()
// запись с категорией `detection` и завершается. Результат НЕ сохраняется
// в App Group / Keychain / UserDefaults / SwiftData. NO notifications.
//
// **Cold-start defer pattern (DEC-06d-01).** Real callsite —
// `BBTB_iOSApp.init()` / `BBTB_macOSApp.init()`, обёрнут в
// `Task.detached(priority: .utility) { await MainActor.run { MAXDetector.detectAndLog() } }`.
// detectAndLog @MainActor (UIApplication.shared требует main actor), но сама
// операция (canOpenURL / urlForApplication) дешёвая — несколько μs. Detached
// task — для consistency с другими cold-start init hooks (RulesEngine bootstrap,
// DeepLinkRouter register, SwiftData migration).
//
// **Testable surface.** Production callsite использует `RealUIApplication` /
// `RealNSWorkspace` обёртки, но `detectIOS(query:)` / `detectMacOS(workspace:)`
// принимают protocol-typed аргументы (`URLSchemeQueryable` / `WorkspaceQueryable`),
// которые в тестах подменяются Mock-реализациями. См. MAXDetectorTests.swift.
//
// **Candidates lists internal-visible** для (a) синхронизации с
// `LSApplicationQueriesSchemes` в iOS Info.plist (Pitfall 1 — без whitelist
// `canOpenURL` молча возвращает false), и (b) для unit-тестов через
// `@testable import MainScreenFeature`. НЕ публикуются как public — это
// detection internals, не часть стабильного API.
//
// **Threat model (см. 11-04-PLAN.md `<threat_model>` T-11-04-01..06):**
// - logger использует `privacy: .public` ТОЛЬКО для scheme/bundleID — не PII.
// - URL.path логируется с `privacy: .private` (T-11-04-01 mitigation).
// - canOpenURL / urlForApplication — Apple-canonical APIs, non-throwing.
// - Task.detached изолирует exception от main thread (T-11-04-05 mitigation).
//
// **Что НЕ делаем (anti-patterns):**
// - НЕ trying alternative detection paths (LSCopyApplicationURLsForBundleIdentifier,
//   /Applications scan, mach_port enumeration) — `canOpenURL` / `urlForApplication`
//   единственные Apple-canonical surfaces.
// - НЕ блокируем MAX-домены client-side через NEPacketTunnelProvider rules —
//   это server-side через Phase 8 RulesEngine `block_completely` (DETECT-03).
// - НЕ delegate detection в Network Extension — main app only.

import Foundation
import os

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Mockable surfaces

/// Minimal abstraction поверх `UIApplication.shared.canOpenURL(_:)`. Existence
/// этого protocol'а — единственно для testability (см. MAXDetectorTests.MockSchemeQuery).
/// Production conformance — internal struct `RealUIApplication` ниже.
public protocol URLSchemeQueryable: Sendable {
    func canOpenURL(_ url: URL) -> Bool
}

/// Minimal abstraction поверх `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`.
/// Production conformance — internal struct `RealNSWorkspace` ниже.
public protocol WorkspaceQueryable: Sendable {
    func urlForApplication(withBundleIdentifier identifier: String) -> URL?
}

// MARK: - Detector

/// Static-only namespace для silent MAX-app detection. Один-shot операция;
/// результат живёт только в os.Logger unified-logging buffer.
public enum MAXDetector {

    /// Subsystem/category convention codebase'а — см. TunnelWatchdog.swift:57,
    /// FailoverProvider.swift:71. Category `detection` уникальная для Phase 11
    /// (не пересекается с `tunnel-watchdog`, `failover`, `tunnel-controller`,
    /// `diagnostics`).
    private static let logger = Logger(subsystem: "app.bbtb.client", category: "detection")

    /// Candidate iOS URL schemes для `UIApplication.canOpenURL`. RESEARCH A1:
    /// MAX bundle identifier / URL scheme публично не задокументирован, поэтому
    /// пробуем несколько разумных вариантов до первого matching.
    ///
    /// **CRITICAL invariant (Pitfall 1):** этот массив ДОЛЖЕН быть синхронизирован
    /// буква в букву с `LSApplicationQueriesSchemes` в `BBTB/App/iOSApp/Info.plist`,
    /// иначе iOS rejects `canOpenURL` query как privacy violation и тихо
    /// возвращает false даже если MAX установлен.
    internal static let iOSSchemeCandidates: [String] = [
        "max",
        "max-app",
        "ru-max",
        "vkmax",
    ]

    /// Candidate macOS bundle identifiers для `NSWorkspace.urlForApplication`.
    /// RESEARCH A2/A3: macOS-версия MAX может вообще не существовать (Catalyst
    /// или separate target unclear); detector logs "not detected" как valid
    /// outcome.
    internal static let macOSBundleCandidates: [String] = [
        "ru.vk.max",
        "com.vkontakte.max",
        "chat.max.app",
        "ru.max.messenger",
    ]

    /// Public production entry point. Вызывается из `BBTB_iOSApp.init()` /
    /// `BBTB_macOSApp.init()` через `Task.detached(priority: .utility)` →
    /// `MainActor.run { … }` — DEC-06d-01 cold-start defer pattern.
    ///
    /// `@MainActor` — потому что `UIApplication.shared` is main-actor-isolated
    /// на iOS. macOS вариант не требует main actor, но annotation
    /// унифицирована для cross-platform call-site consistency.
    @MainActor
    public static func detectAndLog() {
        #if os(iOS)
        // Production query — реальный `UIApplication.shared` wrapper.
        let query = RealUIApplication()
        if let scheme = detectIOS(query: query) {
            logger.info("MAX-app detected via scheme: \(scheme, privacy: .public)")
        } else {
            logger.info("MAX-app not detected (iOS, tried \(iOSSchemeCandidates.count, privacy: .public) schemes)")
        }
        #elseif os(macOS)
        // Production query — реальный `NSWorkspace.shared` wrapper.
        let workspace = RealNSWorkspace()
        if let result = detectMacOS(workspace: workspace) {
            logger.info("MAX-app detected via bundle: \(result.bundleID, privacy: .public) at \(result.path, privacy: .private)")
        } else {
            logger.info("MAX-app not detected (macOS, tried \(macOSBundleCandidates.count, privacy: .public) bundles)")
        }
        #endif
    }

    // MARK: - Testable internals (iOS)

    /// iOS detection helper. Internal-visible для unit-тестов
    /// (`@testable import MainScreenFeature` → MAXDetectorTests).
    ///
    /// - Parameter query: any `URLSchemeQueryable` (production passes
    ///   `RealUIApplication`; tests pass mock).
    /// - Returns: первая matching scheme из `iOSSchemeCandidates`, иначе nil.
    ///
    /// Iteration order preserved → "first match wins" — каноничное поведение
    /// для best-effort detection (если у пользователя зарегистрированы
    /// несколько похожих schemes, мы логируем тот что первый в списке).
    @MainActor
    internal static func detectIOS(query: URLSchemeQueryable) -> String? {
        for scheme in iOSSchemeCandidates {
            // `URL(string:)` may return nil для malformed scheme — defensive guard.
            guard let url = URL(string: "\(scheme)://") else { continue }
            if query.canOpenURL(url) {
                return scheme
            }
        }
        return nil
    }

    // MARK: - Testable internals (macOS)

    /// Composite result для macOS detection — позволяет тестам verify'ить
    /// и bundle ID (для match assertion), и path (для smoke что URL валидный).
    /// Sendable — actor-isolation safe, хотя текущая impl synchronous.
    internal struct MacOSDetectionResult: Sendable, Equatable {
        let bundleID: String
        let path: String
    }

    /// macOS detection helper. Internal-visible для unit-тестов.
    ///
    /// - Parameter workspace: any `WorkspaceQueryable` (production passes
    ///   `RealNSWorkspace`; tests pass mock).
    /// - Returns: bundleID + path первого matching bundle, иначе nil.
    internal static func detectMacOS(workspace: WorkspaceQueryable) -> MacOSDetectionResult? {
        for bid in macOSBundleCandidates {
            if let url = workspace.urlForApplication(withBundleIdentifier: bid) {
                return MacOSDetectionResult(bundleID: bid, path: url.path)
            }
        }
        return nil
    }
}

// MARK: - Production conformances

#if os(iOS)
/// Production wrapper для `UIApplication.shared.canOpenURL`. `@MainActor` —
/// `UIApplication.shared` требует main actor (Apple). `Sendable` через
/// `@unchecked` потому что инстанс не имеет mutable state — это pure delegator.
///
/// `@preconcurrency` на conformance: protocol `URLSchemeQueryable` имеет
/// `Sendable`-сallable `canOpenURL` (nonisolated requirement), а наша
/// implementation @MainActor-isolated. Swift 6 strict concurrency
/// (`-swift-version 6`) под Xcode 26 видит несоответствие как ошибку, но
/// production callsite (`MAXDetector.detectAndLog()`) уже @MainActor —
/// сall происходит без cross-actor hop, runtime data race невозможен.
/// `@preconcurrency` явно сообщает компилятору «доверяю мне, проверь в
/// runtime через `dispatchPrecondition` если что» — Apple recommended
/// pattern для main-actor → nonisolated-protocol bridging.
@MainActor
private struct RealUIApplication: @preconcurrency URLSchemeQueryable, @unchecked Sendable {
    func canOpenURL(_ url: URL) -> Bool {
        UIApplication.shared.canOpenURL(url)
    }
}
#elseif os(macOS)
/// Production wrapper для `NSWorkspace.shared.urlForApplication`. На macOS
/// API не main-actor-isolated, поэтому wrapper можно construct'ить и
/// использовать вне main actor (хотя production callsite — `detectAndLog`
/// — все равно @MainActor для cross-platform consistency).
private struct RealNSWorkspace: WorkspaceQueryable {
    func urlForApplication(withBundleIdentifier identifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
    }
}
#endif
