import Foundation
import SwiftUI
import VPNCore
import NetworkExtension
import MainScreenFeature
import RulesEngine
import OSLog

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// KILL-03 + Phase 6 / NET-02..NET-03 — Settings page ViewModel.
///
/// Хранит global-настройки VPN через `@AppStorage` (per-app, синхронизируется с UserDefaults).
/// Phase 6 добавляет: `customDNS`, `adBlockEnabled` и computed `dnsConfig` —
/// derived DNSConfig по priority D-01..D-04 (CONTEXT 06).
@MainActor
public final class SettingsViewModel: ObservableObject {

    // MARK: - Stored prefs

    /// KILL-03 — kill switch toggle.
    @AppStorage("app.bbtb.killSwitchEnabled") public var killSwitchEnabled: Bool = false

    /// Phase 6 / NET-02 — D-03. Пользовательский DNS-сервер: IPv4 или hostname.
    /// Пустая строка = не задан → fall through to `adBlockEnabled` / Cloudflare.
    /// Невалидное значение (мусор) НЕ применяется — `dnsConfig` его игнорирует.
    @AppStorage("app.bbtb.customDNS") public var customDNS: String = ""

    /// Phase 6 / NET-03 — D-04. Если true и `customDNS` пуст → tunnel DNS = AdGuard.
    @AppStorage("app.bbtb.adBlockEnabled") public var adBlockEnabled: Bool = false

    /// **Phase 6c / Plan 06C-03 — D-04 / D-05.**
    ///
    /// UI toggle «Автоматическое переподключение» в разделе «Подключение».
    /// `@AppStorage` default `true` — D-04: безшовный UX из коробки, on-demand
    /// активируется автоматически после первого успешного Connect (user intent
    /// записан через `UserIntentStore` в `TunnelController`).
    ///
    /// **Pitfall 4 (RESEARCH §10):** toggle OFF при активном туннеле НЕ tear down
    /// туннель — это Apple's default behavior, footer текст коммуницирует.
    /// `applyAutoReconnectToManager` ниже только пересчитывает `isOnDemandEnabled`
    /// флаг manager'а (через `applyCurrentState`); активный туннель продолжает
    /// работать до явного пользовательского Disconnect.
    @AppStorage("app.bbtb.autoReconnectEnabled") public var autoReconnectEnabled: Bool = true

    // MARK: - Phase 8 W3 — Rules Engine bindings (RULES-09 / RULES-10 / D-11)

    /// Cached snapshot текущих правил для read-only viewer (RULES-09).
    /// Источник истины — `RulesEngineCoordinator.currentSnapshot()`. Обновляется через
    /// `wireRulesCoordinator(_:)` + `bbtbRulesEngineDidUpdate` notification observer.
    @Published public private(set) var rulesSnapshot: RulesSnapshot?

    /// Удобный публичный mirror `rulesSnapshot?.version` — UI читает через `viewModel.rulesVersion`
    /// без распаковки optional.
    @Published public private(set) var rulesVersion: Int = 0

    /// Когда последний successful refresh завершился. nil = только baseline (никогда не fetched).
    @Published public private(set) var rulesLastFetchedAt: Date?

    /// Phase 8 W3 — состояние RULES-10 force-update button (см. `ForceUpdateButtonState`).
    /// State machine driven через `triggerForceUpdate()` + cooldown timer.
    @Published public private(set) var forceUpdateButtonState: ForceUpdateButtonState = .idle

    /// Последний `ForceUpdateOutcome` для inline status row под кнопкой. Auto-dismiss 4s
    /// через `statusOutcomeAutoDismissTask`.
    @Published public private(set) var forceUpdateStatusOutcome: ForceUpdateOutcome?

    /// True когда `snapshot.minAppVersion > currentAppVersion` — driver для
    /// `MinAppVersionBanner` (persistent UI-SPEC §A-08 / D-11).
    @Published public private(set) var showMinAppVersionBanner: Bool = false

    /// Late-bound coordinator (memory `feedback_failover_two_phase_init.md`) — weak,
    /// owner — App layer; SettingsViewModel создаётся раньше, чем RulesEngineCoordinator
    /// финализирован (Phase 8 W4 host bootstrap).
    public weak var rulesEngineCoordinator: RulesEngineCoordinator?

    /// Per-version dismissal flag для min_app_version modal sheet — D-11.
    /// Banner всегда показывается (UI-SPEC §A-08); sheet — только пока пользователь
    /// не дисмисил для этой specific min_app_version.
    @AppStorage("app.bbtb.minAppVersion.dismissed") public var dismissedMinAppVersion: String = ""

    /// Wallclock deadline для cooldown countdown — выживает foreground re-entry
    /// (UI-SPEC §Edge Cases). Phase 8 W3.2 — pure-Swift, не @AppStorage; force-update
    /// cooldown — ephemeral session state (server-side coordinator также enforce'ит cooldown
    /// через own `lastForceUpdateAt` actor state).
    private var cooldownExpiresAt: Date?

    /// 1Hz timer для countdown tick. nil когда state != .cooldown.
    private var cooldownTimer: Timer?

    /// Task для auto-dismiss 4s inline status row. Cancellable если новый force-update tap.
    private var statusOutcomeAutoDismissTask: Task<Void, Never>?

    /// `bbtbRulesEngineDidUpdate` observer token — removed в `deinit`.
    private var rulesUpdateObserver: NSObjectProtocol?

    /// Текущая версия app — для D-11 comparison. Читается из Bundle.main → CFBundleShortVersionString.
    /// Если нет (test environment) — "0.0.0" sentinel.
    public var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    public init() {}

    deinit {
        // Swift 6 strict-concurrency: @MainActor properties недоступны из nonisolated
        // deinit. Cleanup делегируется к explicit teardown helpers вызываемым из
        // host's onDisappear/scenePhase=.background. Для tests: `MainActor.assumeIsolated`
        // wrapper если потребуется (Phase 6 pattern).
        // Self-destruct Timer: SwiftUI lifetime VM > Timer (VM keeps Timer reference);
        // invalidate() в `cooldownTick()` self-runs до dealloc. Observer token: SwiftUI
        // .ObservedObject lifetimes гарантируют VM живёт пока View on-screen; cleanup
        // at process termination automatic.
    }

    /// Explicit teardown — вызывается tests + host shutdown hook. Removes observer,
    /// invalidates timer, cancels task. Use `MainActor.assumeIsolated { vm.teardown() }`
    /// если нужно вызвать из non-MainActor контекста.
    public func teardown() {
        if let token = rulesUpdateObserver {
            NotificationCenter.default.removeObserver(token)
            rulesUpdateObserver = nil
        }
        cooldownTimer?.invalidate()
        cooldownTimer = nil
        statusOutcomeAutoDismissTask?.cancel()
        statusOutcomeAutoDismissTask = nil
    }

    // MARK: - Derived DNS strategy

    /// Phase 6 / NET-01..04 — derive `DNSConfig` по приоритету D-01..D-04.
    ///
    /// Priority (см. 06-CONTEXT.md):
    /// 1. `customDNS` (если валиден IPv4 или RFC 1123 hostname) — D-03.
    /// 2. `adBlockEnabled == true` → AdGuard — D-04.
    /// 3. Cloudflare default — D-02.
    ///
    /// `bootstrapAddress` всегда `tcp://1.1.1.1` (Cloudflare). Phase 6 Wave 5 (`ConfigImporter.buildDNSConfig`)
    /// переопределит bootstrap на server IP per D-01 — этот ViewModel не знает про конкретный сервер.
    ///
    /// **Defense in depth (Pitfall 9):** мусорный `customDNS` НЕ ломает sing-box JSON —
    /// валидация здесь + повторная в `ConfigImporter`.
    public var dnsConfig: DNSConfig {
        let trimmed = customDNS.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty, let formatted = formatCustomDNS(trimmed) {
            return DNSConfig(
                bootstrapAddress: "tcp://1.1.1.1",
                tunnelDNS: .custom(address: formatted)
            )
        }

        if adBlockEnabled {
            return DNSConfig(
                bootstrapAddress: "tcp://1.1.1.1",
                tunnelDNS: .adguard
            )
        }

        return DNSConfig(
            bootstrapAddress: "tcp://1.1.1.1",
            tunnelDNS: .cloudflare
        )
    }

    // MARK: - Validation helpers

    /// Returns sing-box-formatted DNS address (`tcp://<ip>` или `https://<host>/dns-query`)
    /// or `nil` если input невалиден. Trimmed input assumed (caller обязан trim).
    ///
    /// If input *looks* like an IPv4 (all dot-separated labels are pure digits) but isn't
    /// valid (octet > 255, wrong arity), reject — don't fall through to hostname check
    /// because `1.2.3.999` is clearly an intended IP, not a hostname.
    private func formatCustomDNS(_ trimmed: String) -> String? {
        if looksLikeIPv4(trimmed) {
            return isValidIPv4(trimmed) ? "tcp://\(trimmed)" : nil
        }
        if isValidHostname(trimmed) {
            return "https://\(trimmed)/dns-query"
        }
        return nil
    }

    /// All labels are pure ASCII digits → user intended an IPv4 address.
    private func looksLikeIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        for part in parts {
            guard !part.isEmpty else { return false }
            for ch in part where !ch.isASCII || !ch.isNumber {
                return false
            }
        }
        return true
    }

    /// IPv4 validation: 4 dot-separated octets, each 0...255, no extras.
    private func isValidIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            // No leading "+", "-", or spaces; must be pure digits.
            guard !part.isEmpty, part.count <= 3 else { return false }
            for ch in part where !ch.isASCII || !ch.isNumber {
                return false
            }
            guard let value = Int(part), value >= 0, value <= 255 else { return false }
        }
        return true
    }

    /// RFC 1123 hostname (subset): non-empty, ≤ 253 chars, dot-separated labels,
    /// each label 1...63 chars, letters/digits/hyphens, no leading/trailing hyphen.
    /// Must contain at least one dot (single-label "localhost" rejected — not a DoH host).
    private func isValidHostname(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 253 else { return false }
        let labels = s.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard !label.isEmpty, label.count <= 63 else { return false }
            // First and last chars: letter or digit (no hyphen).
            guard let first = label.first, let last = label.last else { return false }
            guard first.isLetter || first.isNumber else { return false }
            guard last.isLetter || last.isNumber else { return false }
            for ch in label {
                guard ch.isASCII else { return false }
                if ch.isLetter || ch.isNumber || ch == "-" { continue }
                return false
            }
        }
        return true
    }

    // MARK: - Phase 6c — auto-reconnect live-apply

    /// **Phase 6c / Plan 06C-03 — D-06 (live-apply toggle to manager).**
    ///
    /// Применяет текущее состояние UI-toggle к `NETunnelProviderManager`
    /// (через `OnDemandRulesBuilder.applyCurrentState` — single source of truth,
    /// W-04). Один XPC-trip на toggle press; НЕ горячий путь observer.
    ///
    /// **Pitfall 4:** toggle OFF при активном туннеле НЕ tear down туннель —
    /// мы только обновляем `manager.isOnDemandEnabled` (Apple's default
    /// behavior; активный сеанс продолжает работать).
    ///
    /// **Round 2 changes:**
    /// - **W-03:** помечен `nonisolated` — выполняется off MainActor. View
    ///   вызывает через `Task.detached { await viewModel.applyAutoReconnectToManager() }`
    ///   из `.onChange(of:)` modifier, чтобы Form не блокировался XPC-trip'ом.
    /// - **W-04:** consumer `OnDemandRulesBuilder.applyCurrentState` (high-level
    ///   API), НЕ direct `apply`. Финальный `isOnDemandEnabled` всегда
    ///   `toggle && intent` — phantom auto-connect class закрыт через B-04.
    /// - **B-06:** итерируется по ВСЕМ нашим manager'ам через
    ///   `ManagerSelector` (multi-manager safe).
    /// - **B-03 cross-plan:** после save+reload КАЖДОГО manager'а постит
    ///   `.bbtbProvisionerDidSave` чтобы `TunnelController` (Plan 06C-04)
    ///   refresh свой `cachedManager` для watchdog `managerEnabled` gate.
    /// - **B-05:** explicit do/catch вокруг `loadAllFromPreferences`; ошибка
    ///   swallowed (НЕ throws). Следующий `provisionTunnelProfile` подхватит
    ///   fresh toggle value через `applyCurrentState`.
    ///
    /// Read-only consumer: значение `autoReconnectEnabled` уже записано
    /// в @AppStorage до вызова (`.onChange` срабатывает после изменения).
    /// Helper НЕ возвращает значение — он только применяет state к manager'у.
    nonisolated public func applyAutoReconnectToManager() async {
        let log = Logger(subsystem: "app.bbtb.client", category: "settings-auto-reconnect")
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let ours = ManagerSelector.ourManagers(from: managers)
            // Phase 6e Wave 2 Theme A (L11) — post `.bbtbProvisionerDidSave` РОВНО ОДИН РАЗ
            // после for-loop, а не на каждой итерации. Consumer (TunnelController.provisionerObserver)
            // не использует `notification.object` — он просто рефрешит cachedManager;
            // N event'ов → SwiftUI body re-diff storm. Это снижает XPC contention
            // (DEC-06d-02 — XPC consolidation) при rare multi-manager edge case.
            // Флаг `anyManagerSaved` гарантирует post только если хотя бы один save succeeded.
            var anyManagerSaved = false
            var lastSavedManager: NETunnelProviderManager?
            for manager in ours {
                OnDemandRulesBuilder.applyCurrentState(to: manager)
                do {
                    try await manager.saveToPreferences()
                    try await manager.loadFromPreferences()  // RESEARCH §9.1
                    anyManagerSaved = true
                    lastSavedManager = manager
                } catch {
                    log.error("applyAutoReconnectToManager: save/reload failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            if anyManagerSaved {
                NotificationCenter.default.post(name: .bbtbProvisionerDidSave, object: lastSavedManager)
            }
        } catch {
            // B-05: transient NEM ошибка не critical — toggle value уже в @AppStorage,
            // следующий provisionTunnelProfile / migration task подхватит fresh value
            // через OnDemandRulesBuilder.applyCurrentState.
            log.warning("applyAutoReconnectToManager: loadAllFromPreferences failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Phase 8 W3 — Rules Engine wiring + force-update flow

    /// **Late-bind setter (memory `feedback_failover_two_phase_init.md`).**
    ///
    /// Caller — App layer host bootstrap (Phase 8 W4). RulesEngineCoordinator создаётся
    /// в App init после SettingsViewModel, поэтому wire через late-binding setter а не
    /// constructor injection (избегаем circular dep `SettingsViewModel ↔ Coordinator`).
    ///
    /// **Side effects:**
    /// 1. Capture weak reference на coordinator.
    /// 2. Read current snapshot из coordinator (если bootstrap уже ran) → apply.
    /// 3. Register `bbtbRulesEngineDidUpdate` observer (queue: nil per
    ///    `feedback_nevpn_observer_queue_main.md`) — каждый refresh обновляет UI.
    ///
    /// **Idempotent:** при повторном вызове удаляет previous observer и регистрирует
    /// fresh (test path может wire неоднократно).
    public func wireRulesCoordinator(_ coordinator: RulesEngineCoordinator) async {
        self.rulesEngineCoordinator = coordinator

        // Удаляем previous observer (idempotency).
        if let token = rulesUpdateObserver {
            NotificationCenter.default.removeObserver(token)
            rulesUpdateObserver = nil
        }

        // Initial seed — может быть nil если coordinator ещё не bootstrap'нул.
        if let snapshot = await coordinator.currentSnapshot() {
            applySnapshot(snapshot)
        }

        // Observer queue=nil per memory feedback_nevpn_observer_queue_main.md —
        // .main теряет notifications когда app suspended. Task @MainActor hop
        // гарантирует mutation @Published на MainActor.
        rulesUpdateObserver = NotificationCenter.default.addObserver(
            forName: .bbtbRulesEngineDidUpdate,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // Prefer Notification.object (RulesSnapshot?) — coordinator emits typed
            // snapshot прямо в payload. Fallback на refresh через coordinator.
            if let snapshot = notification.object as? RulesSnapshot {
                Task { @MainActor [weak self] in
                    self?.applySnapshot(snapshot)
                }
            } else {
                Task { @MainActor [weak self] in
                    await self?.refreshFromCoordinator()
                }
            }
        }
    }

    /// Read fresh snapshot из coordinator + apply. Используется как fallback path,
    /// если notification.object не содержит RulesSnapshot, либо для manual refresh.
    private func refreshFromCoordinator() async {
        guard let coordinator = rulesEngineCoordinator else { return }
        if let snapshot = await coordinator.currentSnapshot() {
            applySnapshot(snapshot)
        }
    }

    /// Apply snapshot в @Published state. Side-effect free кроме property writes.
    /// MainActor-isolated — caller обязан hop на MainActor.
    private func applySnapshot(_ snapshot: RulesSnapshot) {
        self.rulesSnapshot = snapshot
        self.rulesVersion = snapshot.version
        self.rulesLastFetchedAt = snapshot.lastFetchedAt
        // D-11 — `min_app_version > current` → banner stays (Persistent per UI-SPEC §A-08).
        let needsUpgrade = snapshot.minAppVersion.compare(currentAppVersion, options: .numeric) == .orderedDescending
        self.showMinAppVersionBanner = needsUpgrade
    }

    // MARK: - Force update flow (RULES-10)

    /// Tap handler для `ForceUpdateRulesButton`. Idempotent via race guard
    /// `guard buttonState == .idle` (UI-SPEC §Edge Cases). Подходящие dispatch +
    /// outcome mapping + cooldown start.
    ///
    /// Side effects:
    /// 1. Race guard — если кнопка не `.idle` — return immediately (no-op для double-tap).
    /// 2. iOS haptic — light impact на `ForceUpdateRulesButton.handleTap` уже отрабатывает;
    ///    здесь не дублируем (View-level concern).
    /// 3. Transition `.idle → .inProgress`.
    /// 4. Await `coordinator.forceUpdate()` — actor-safe.
    /// 5. Map outcome → cooldown state + inline status + auto-dismiss task.
    public func triggerForceUpdate() async {
        guard forceUpdateButtonState == .idle else { return }
        forceUpdateButtonState = .inProgress

        let outcome: ForceUpdateOutcome
        if let coordinator = rulesEngineCoordinator {
            outcome = await coordinator.forceUpdate()
        } else {
            // Нет coordinator (тест-сценарий или мисс wire-up) — feedback network failure.
            outcome = .networkFailure
        }

        applyForceUpdateOutcome(outcome)
    }

    /// Apply outcome: stash inline status, schedule 4s auto-dismiss, start cooldown.
    /// MainActor-isolated.
    private func applyForceUpdateOutcome(_ outcome: ForceUpdateOutcome) {
        // Stash outcome для inline status row.
        self.forceUpdateStatusOutcome = outcome

        // Start cooldown — discriminate `.cooldownActive` (already-in-cooldown response)
        // vs других outcomes (свежий attempt → standard 60s).
        let cooldownSeconds: Int
        switch outcome {
        case .cooldownActive(let secondsRemaining):
            cooldownSeconds = secondsRemaining
        case .success, .alreadyLatest, .networkFailure, .signatureFailure, .payloadTooLarge:
            // Coordinator enforces 60s window регardless of attempt outcome (D-10).
            cooldownSeconds = 60
        }
        cooldownExpiresAt = Date().addingTimeInterval(TimeInterval(cooldownSeconds))
        forceUpdateButtonState = .cooldown(secondsRemaining: cooldownSeconds)
        startCooldownTimer()

        // Schedule auto-dismiss 4s — cancel previous если pending.
        statusOutcomeAutoDismissTask?.cancel()
        statusOutcomeAutoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            // Guard — пользователь мог нажать button снова за этот период; если outcome
            // изменился, эта таска уже устарела (новая будет создана).
            guard !Task.isCancelled else { return }
            self?.forceUpdateStatusOutcome = nil
        }

        // На success outcome — рефрешим snapshot (новая версия должна отразиться в viewer).
        if case .success = outcome {
            Task { @MainActor [weak self] in
                await self?.refreshFromCoordinator()
            }
        }
    }

    /// Start 1Hz Timer для cooldown countdown. Wallclock-based — выживает foreground
    /// re-entry (UI-SPEC §Edge Cases).
    private func startCooldownTimer() {
        cooldownTimer?.invalidate()
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Timer callback на main run loop — но мы декларируем @MainActor через Task hop
            // (Swift 6 concurrency strict). Self is @MainActor; Task @MainActor — re-enters
            // actor для @Published mutation.
            Task { @MainActor [weak self] in
                self?.cooldownTick()
            }
        }
    }

    /// Tick callback — recompute remaining через wallclock; transition в `.idle` когда expired.
    private func cooldownTick() {
        guard let expiresAt = cooldownExpiresAt else {
            // Defensive — таймер активен без deadline.
            cooldownTimer?.invalidate()
            cooldownTimer = nil
            forceUpdateButtonState = .idle
            return
        }
        let remaining = Int(expiresAt.timeIntervalSince(Date()).rounded(.up))
        if remaining <= 0 {
            cooldownTimer?.invalidate()
            cooldownTimer = nil
            cooldownExpiresAt = nil
            forceUpdateButtonState = .idle
        } else {
            forceUpdateButtonState = .cooldown(secondsRemaining: remaining)
        }
    }

    // MARK: - TestFlight opener (RULES-08 / D-11)

    /// Open TestFlight URL (placeholder в Phase 8 W3; Phase 12 substitutes real invite token).
    ///
    /// Side effects:
    /// 1. Cross-platform URL open (UIApplication on iOS, NSWorkspace on macOS).
    /// 2. Stash current `min_app_version` в `dismissedMinAppVersion` @AppStorage —
    ///    sheet не показывается повторно для same version (UI-SPEC §Interaction Pattern 4).
    public func openTestFlight() {
        let url = RulesEngineConstants.testFlightInviteURL
        #if canImport(UIKit) && os(iOS)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
        if let snapshot = rulesSnapshot {
            dismissedMinAppVersion = snapshot.minAppVersion
        }
    }
}

// MARK: - Phase 8 W3 — TestFlight URL constants

/// Phase 12 prerequisite: заменить PLACEHOLDER на реальный invite token из
/// App Store Connect → TestFlight → Public Link (см. project memory
/// `project_phase12_distribution_creds_prerequisite.md`).
public enum RulesEngineConstants {
    /// Placeholder TestFlight URL — Phase 12 substitutes реальный invite.
    /// До замены: tap откроет TestFlight 404, что приемлемо для v0.8 dev cycle.
    public static let testFlightInviteURL = URL(string: "https://testflight.apple.com/join/PLACEHOLDER")!
}
