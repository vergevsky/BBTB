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
        let center = UNUserNotificationCenter.current()
        let initialSettings = await center.notificationSettings()
        switch initialSettings.authorizationStatus {
        case .notDetermined:
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return  // user denied or system error → bail silently
            }
        case .denied:
            return
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            return
        }

        // Re-check after potential prompt — user may have denied.
        let postPromptSettings = await center.notificationSettings()
        switch postPromptSettings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = L10n.notificationReconnectFailedTitle
        if let name = serverName, !name.isEmpty {
            content.body = L10n.notificationReconnectFailedBody(name)
        } else {
            content.body = L10n.notificationReconnectFailedBodyGeneric
        }
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: reconnectFailedIdentifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    /// Phase 6 / Wave 6 — D-08 edge case notification. Posted when the failover
    /// provider determines the pool contains a single server (no alternative
    /// to switch to). Same authorization flow as `notifyReconnectFailed`:
    /// on-demand prompt on first call, silent on denial.
    @MainActor
    public static func notifySingleServerUnavailable() async {
        let center = UNUserNotificationCenter.current()
        let initialSettings = await center.notificationSettings()
        switch initialSettings.authorizationStatus {
        case .notDetermined:
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return
            }
        case .denied:
            return
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            return
        }

        let postPromptSettings = await center.notificationSettings()
        switch postPromptSettings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = L10n.notificationSingleServerUnavailableTitle
        content.body = L10n.notificationSingleServerUnavailableBody
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: singleServerUnavailableIdentifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}
