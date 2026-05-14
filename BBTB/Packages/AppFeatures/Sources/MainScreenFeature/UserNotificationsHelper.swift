// UserNotificationsHelper.swift — Phase 6 / Plan 06-05 / Wave 5 / Task 1.
//
// Local notifications when auto-reconnect exhausts the retry budget (state machine
// reaches `.allFailed`). Per CLAUDE.md UX principle "one tap to VPN", authorization
// is requested **on demand** — first time we actually want to post a notification —
// not at app launch. Denial is silent.
//
// Extension constraint: `UNUserNotificationCenter` only works from the main app
// target. Phase 6 keeps the reconnect state machine inside the main app, so this
// helper is naturally invoked from `MainScreenViewModel` (Wave 5 Task 3 wires it
// to the ReconnectStateMachine observer).
//
// See `.planning/phases/06-network-resilience/06-RESEARCH.md` §11 for the
// canonical implementation.
//
// Phase 6e Wave 2 Theme C-1 (L5) — duplicate authorization + post logic в
// `notifyReconnectFailed` и `notifySingleServerUnavailable` (~30 LOC × 2 = 60
// дублирующих строк) exctracted в `ensureAuthorized()` + `post(content:identifier:)`
// private helpers. Каждый каллер теперь ~10 LOC. Поведение byte-identical:
// authorization flow с notDetermined → requestAuthorization → re-check, на denied
// или unknown → silent return; post через UNTimeIntervalNotificationTrigger 0.5s.

import Foundation
import UserNotifications
import Localization

/// Sole entry-point: `notifyReconnectFailed(serverName:)`. Marked `@MainActor`
/// because `UNUserNotificationCenter.current()` is main-actor scoped on iOS 18+.
public enum UserNotificationsHelper {

    /// Identifier used both for posting and (optionally in the future) for
    /// dismissing pending notifications.
    public static let reconnectFailedIdentifier = "app.bbtb.reconnect-failed"

    /// Phase 6 / Wave 6 — fires when the failover provider determines that
    /// there are no other servers to switch to (single-server pool, D-08 edge).
    public static let singleServerUnavailableIdentifier = "app.bbtb.single-server-unavailable"

    /// Posts a "could not connect" local notification. Requests authorization on
    /// first call (if `.notDetermined`); silently no-ops on denial.
    ///
    /// `serverName == nil` → generic body; otherwise interpolates the name.
    @MainActor
    public static func notifyReconnectFailed(serverName: String?) async {
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = L10n.notificationReconnectFailedTitle
        if let name = serverName, !name.isEmpty {
            content.body = L10n.notificationReconnectFailedBody(name)
        } else {
            content.body = L10n.notificationReconnectFailedBodyGeneric
        }
        content.sound = .default

        await post(content: content, identifier: reconnectFailedIdentifier)
    }

    /// Phase 6 / Wave 6 — D-08 edge case notification. Posted when the failover
    /// provider determines the pool contains a single server (no alternative
    /// to switch to). Same authorization flow as `notifyReconnectFailed`:
    /// on-demand prompt on first call, silent on denial.
    @MainActor
    public static func notifySingleServerUnavailable() async {
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = L10n.notificationSingleServerUnavailableTitle
        content.body = L10n.notificationSingleServerUnavailableBody
        content.sound = .default

        await post(content: content, identifier: singleServerUnavailableIdentifier)
    }

    // MARK: - Private helpers (Phase 6e Wave 2 Theme C-1 — L5 extraction)

    /// Verifies (and on first call requests) UN authorization. Returns `true`
    /// only when the user has granted (or system has provisional/ephemeral) auth;
    /// otherwise silently returns `false`. Two-phase check: initial settings →
    /// possible prompt → re-check post-prompt (user may have denied prompt).
    @MainActor
    private static func ensureAuthorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let initialSettings = await center.notificationSettings()
        switch initialSettings.authorizationStatus {
        case .notDetermined:
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false  // user denied or system error → bail silently
            }
        case .denied:
            return false
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            return false
        }

        // Re-check after potential prompt — user may have denied.
        let postPromptSettings = await center.notificationSettings()
        switch postPromptSettings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    /// Posts an already-prepared `UNMutableNotificationContent` через
    /// `UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)`.
    /// Errors swallowed (try? на add(_:)) — потеря notification не должна
    /// падать VM или вызывающего.
    @MainActor
    private static func post(content: UNMutableNotificationContent, identifier: String) async {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
