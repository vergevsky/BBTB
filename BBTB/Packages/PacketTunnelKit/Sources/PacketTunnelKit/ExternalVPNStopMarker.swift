// ExternalVPNStopMarker.swift — Phase 6d post-fix 4 (Codex consult #3).
//
// Cross-process marker для **authoritative** detection of "user disabled VPN
// в iOS Settings" or "provider disabled by OS". Host app не получает
// `NEProviderStopReason` через NEVPNStatusDidChange (только status, без
// reason). Только Packet Tunnel Extension's `stopTunnel(with reason:)` видит
// настоящий reason. Этот marker мостит information из extension в host через
// App Group UserDefaults.
//
// **Why this is needed:**
// iOS Settings → VPN toggle off отправляет stop command с `reason = .userInitiated`
// в extension. Extension stops, but iOS DOES NOT reliably flip
// `manager.isEnabled = false` в preferences. Host's `cachedManager.isEnabled`
// often remains `true`. Therefore host's old intent-close discriminator
// `if !manager.isEnabled` fires unreliably.
//
// **Cross-process flow:**
// 1. Extension `stopTunnel(reason: .userInitiated|.providerDisabled)` →
//    `ExternalVPNStopMarker.mark()` writes flag to App Group UserDefaults.
// 2a. (Background path) iOS on-demand later tries `startTunnel` → extension's
//     `startTunnel` checks `ExternalVPNStopMarker.consume()`. If marker
//     pending → reject start with `TunnelError.userDisabledInSettings`. This
//     blocks iOS auto-reconnect **without** host involvement.
// 2b. (Foreground path) Host's `handleStatusChange.disconnected` path calls
//     `ExternalVPNStopMarker.consume()` as intent-close discriminator. If
//     marker pending → close intent (userIntendedConnected=false).
// 3. Explicit user Connect tap in host calls `ExternalVPNStopMarker.clear()`
//    BEFORE proceeding — re-acquires intent.
//
// **App Group:** `group.app.bbtb.shared` (per AppGroupContainer.identifier).

import Foundation

public enum ExternalVPNStopMarker {
    private static let pendingKey = "app.bbtb.externalVPNStop.pending"
    private static let timestampKey = "app.bbtb.externalVPNStop.timestamp"

    /// App Group shared defaults. nil if entitlement missing (should not happen
    /// in production builds).
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupContainer.identifier)
    }

    /// Записать marker. Вызывается ТОЛЬКО из extension's `stopTunnel(reason:)`
    /// при reason == .userInitiated || .providerDisabled. Idempotent.
    public static func mark() {
        guard let defaults else { return }
        defaults.set(true, forKey: pendingKey)
        defaults.set(Date().timeIntervalSince1970, forKey: timestampKey)
        // synchronize() — extension может быть terminated сразу после, нужна
        // disk-flush guarantee.
        defaults.synchronize()
    }

    /// Phase 6d post-fix 5 (2026-05-14, Codex consult #4 + open-source research) —
    /// **peek without consume**. Прежний `consume()` имел гонку: и host, и
    /// extension `consume()`или маркер; кто первый видел — тот клирил.
    /// После этого следующая iOS on-demand startTunnel-попытка не находила
    /// marker → тоннель стартовал.
    ///
    /// Новая модель **sticky marker**:
    /// - `isPending()` — peek без клиринга, auto-clear только при истечении maxAge
    /// - Marker живёт до тех пор, пока:
    ///   1. истечёт `maxAge` (10 минут default — auto-clear на чтении)
    ///   2. ИЛИ host's `connect()` явно вызовет `clear()` (explicit user override)
    ///
    /// Это позволяет:
    /// - Host's `handleStatusChange.disconnected` — peek для intent-close
    /// - Extension's `startTunnel(options:)` — peek для блокирования ВСЕХ
    ///   iOS on-demand retry-попыток в окне maxAge
    /// - Manual Connect tap → `clear()` + fresh start с `options["manualStart": true]`
    ///
    /// **maxAge default 600s (10 min)** — покрывает разумные iOS on-demand
    /// retry окна. После 10 мин — marker stale.
    /// **Trade-off:** Если user перевключает Settings VPN toggle ON в окне
    /// maxAge — startTunnel будет BLOCKED, user должен открыть BBTB и tap
    /// Connect. Acceptable для primary bug.
    public static func isPending(maxAge: TimeInterval = 600) -> Bool {
        guard let defaults, defaults.bool(forKey: pendingKey) else { return false }

        let ts = defaults.double(forKey: timestampKey)
        let now = Date().timeIntervalSince1970
        if ts > 0 && now - ts > maxAge {
            clear()
            return false
        }
        return true
    }

    /// Принудительно очистить marker. Вызывается из `TunnelController.connect()`
    /// перед setUserIntendedConnected(true) — explicit user intent overrides
    /// any pending Settings-disable marker.
    public static func clear() {
        guard let defaults else { return }
        defaults.removeObject(forKey: pendingKey)
        defaults.removeObject(forKey: timestampKey)
        defaults.synchronize()
    }
}

// MARK: - Start options keys (Apple-canonical discriminator)

/// Phase 6d post-fix 5 — keys для `startTunnel(options:)` discriminator.
///
/// Apple canonical pattern (per NEPacketTunnelProvider docs): `options == nil`
/// for OS/on-demand starts; non-nil dictionary for app-initiated starts.
/// WireGuard iOS refines this with `options["activationAttemptId"]` — мы
/// используем аналогичный `options["manualStart"]: true` ключ.
///
/// Used by:
/// - Host's `TunnelController.connect()` — passes `["manualStart": true]`
/// - Extension's `BaseSingBoxTunnel.startTunnel(options:)` — if options has
///   `manualStart=true`, allow regardless of marker. Otherwise check marker.
public enum TunnelStartOptionsKey {
    public static let manualStart = "manualStart"
}
