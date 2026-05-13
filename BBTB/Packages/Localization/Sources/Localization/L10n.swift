import Foundation

/// LOC-01: type-safe accessor для Localizable.xcstrings.
/// Phase 1 baseline + Phase 2 W4.T2 extension (28+ new keys per UI-SPEC §9).
public enum L10n {
    private static func tr(_ key: String) -> String {
        NSLocalizedString(key, bundle: Bundle.module, comment: "")
    }
    private static func tr(_ key: String, _ args: CVarArg...) -> String {
        let fmt = NSLocalizedString(key, bundle: Bundle.module, comment: "")
        return String(format: fmt, arguments: args)
    }

    // MARK: Phase 1 carry-forward

    public static let appDisplayName = tr("app.display_name")
    public static let appShortName = tr("app.short_name")
    public static let statusEmpty = tr("status.empty")
    public static let statusIdle = tr("status.idle")
    public static let statusConnecting = tr("status.connecting")
    public static let statusConnected = tr("status.connected")
    public static let statusError = tr("status.error")
    public static let actionImportFromClipboard = tr("action.import_from_clipboard")
    public static let actionConnect = tr("action.connect")
    public static let actionDisconnect = tr("action.disconnect")
    public static let actionRetry = tr("action.retry")
    public static let actionDetails = tr("action.details")
    public static let emptyTitle = tr("empty.title")
    public static let emptySubtitle = tr("empty.subtitle")
    public static let importErrorNoPasteboard = tr("import.error.no_pasteboard")
    public static let importErrorMalformed = tr("import.error.malformed")
    public static let importErrorNotReality = tr("import.error.not_reality")
    public static let importSuccess = tr("import.success")
    public static let menubarConnect = tr("menubar.connect")
    public static let menubarDisconnect = tr("menubar.disconnect")
    public static let menubarOpenWindow = tr("menubar.open_window")
    public static let alertTunnelErrorTitle = tr("alert.tunnel_error.title")

    // MARK: Phase 2 W4.T2 — additions per UI-SPEC §9.1

    public static let statusDisconnected = tr("status.disconnected")

    public static let actionScanQR = tr("action.scan_qr")
    public static let actionCancel = tr("action.cancel")
    public static let actionOK = tr("action.ok")

    public static let menuAddConfig = tr("menu.add_config")
    public static let menuScanQR = tr("menu.scan_qr")
    public static let menuImportFromClipboard = tr("menu.import_from_clipboard")

    public static let serverLabel = tr("server.label")
    public static let serverAuto = tr("server.auto")

    public static let timerLabel = tr("timer.label")

    public static let settingsTitle = tr("settings.title")
    public static let settingsSecuritySection = tr("settings.security.section")
    public static let settingsKillSwitchLabel = tr("settings.kill_switch.label")
    public static let settingsKillSwitchFooter = tr("settings.kill_switch.footer")

    public static let bannerReconnectNeeded = tr("banner.reconnect_needed")
    public static let bannerDismiss = tr("banner.dismiss")

    public static let qrTitle = tr("qr.title")
    public static let qrCancel = tr("qr.cancel")
    public static let qrHint = tr("qr.hint")
    public static let qrPermissionDeniedTitle = tr("qr.permission_denied.title")
    public static let qrPermissionDeniedMessage = tr("qr.permission_denied.message")
    public static let qrPermissionDeniedOpenSettings = tr("qr.permission_denied.open_settings")

    public static let importErrorNoSupportedConfigs = tr("import.error.no_supported_configs")
    public static func importErrorNetwork(_ detail: String) -> String { tr("import.error.network", detail) }
    public static let importErrorValidation = tr("import.error.validation")
    public static let importErrorV2rayUnsupported = tr("import.error.v2ray_unsupported")
    public static let importProgress = tr("import.progress")
    public static let importSuccessTitle = tr("import.success.title")
    public static func importSuccessMessage(_ added: Int, _ unsupported: Int) -> String {
        tr("import.success.message", added, unsupported)
    }
    public static let alertImportFailed = tr("alert.import_failed.title")

    // MARK: Phase 3 Plan 03 — server list sheet (per UI-SPEC §9.5)

    public static let serverAutoTitle = tr("server.auto.title")
    public static let serverAutoSubtitle = tr("server.auto.subtitle")
    public static let serverLineHint = tr("server.line.hint")

    public static let serverListTitle = tr("serverList.title")
    public static let serverListManualSection = tr("serverList.manualSection")
    public static let serverListUnsupportedBadge = tr("serverList.unsupportedBadge")
    public static let serverListUnreachable = tr("serverList.unreachable")
    public static let serverListDeleteServer = tr("serverList.deleteServer")
    public static let serverListDeleteSubscription = tr("serverList.deleteSubscription")
    public static func serverListDeleteSubscriptionConfirm(_ name: String, _ count: Int) -> String {
        tr("serverList.deleteSubscription.confirm.message", name, count)
    }
    public static let serverListEmptyTitle = tr("serverList.empty.title")
    public static let serverListEmptySubtitle = tr("serverList.empty.subtitle")
    public static let serverListRefreshErrorTitle = tr("serverList.refresh.error.title")
    public static let serverListRefreshErrorMessage = tr("serverList.refresh.error.message")
    public static func serverListSubscriptionFetchError(_ code: Int) -> String {
        tr("serverList.subscription.fetchError", code)
    }
    public static let serverListLastFetchedJustNow = tr("serverList.lastFetched.justNow")
    public static func serverListLastFetchedMinutes(_ n: Int) -> String {
        tr("serverList.lastFetched.minutes", n)
    }
    public static func serverListLastFetchedHours(_ n: Int) -> String {
        tr("serverList.lastFetched.hours", n)
    }
    public static func serverListLastFetchedDays(_ n: Int) -> String {
        tr("serverList.lastFetched.days", n)
    }
    public static let actionDelete = tr("action.delete")
    public static let importSubscriptionAddedTitle = tr("import.subscription.added.title")
    public static func importSubscriptionAddedMessage(_ added: Int, _ name: String, _ unsupported: Int) -> String {
        tr("import.subscription.added.message", added, name, unsupported)
    }
    public static let importSubscriptionUpdatedTitle = tr("import.subscription.updated.title")
    public static func importSubscriptionUpdatedMessage(_ newCount: Int, _ name: String, _ total: Int) -> String {
        tr("import.subscription.updated.message", newCount, name, total)
    }
    public static func serverListManualSubscriptionFallback(_ n: Int) -> String {
        tr("serverList.manualSubscriptionName.fallback", n)
    }

    // MARK: Phase 3 Plan 05 — pre-connect auto-select + Pitfall-8 errors

    public static let serverListNoReachableServers = tr("serverList.noReachableServers")
    public static let serverListNoSupportedServers = tr("serverList.noSupportedServers")

    // MARK: Phase 5 Wave 8 — ServerDetailView (TRANSP-05, D-18)

    public static let serverDetailGeneralSection = tr("serverDetail.generalSection")
    public static let serverDetailParsedSection = tr("serverDetail.parsedSection")
    public static let serverDetailTransportSection = tr("serverDetail.transportSection")
    public static let serverDetailTransport = tr("serverDetail.transport")
    public static let serverDetailTransportAuto = tr("serverDetail.transportAuto")
    public static let serverDetailTransportFooter = tr("serverDetail.transportFooter")
    public static let serverDetailName = tr("serverDetail.name")
    public static let serverDetailHost = tr("serverDetail.host")
    public static let serverDetailPort = tr("serverDetail.port")
    public static let serverDetailProtocol = tr("serverDetail.protocol")
    public static let serverDetailLatency = tr("serverDetail.latency")
    public static let serverDetailFlow = tr("serverDetail.flow")
    public static let serverDetailFingerprint = tr("serverDetail.fingerprint")
    public static let serverDetailPublicKey = tr("serverDetail.publicKey")
    public static let serverDetailShortId = tr("serverDetail.shortId")
    public static let serverDetailAccessibilityHint = tr("serverDetail.accessibilityHint")

    // MARK: Phase 6 / 06-03 — AdvancedSettingsView + DNS section (NET-02, NET-03)

    public static let settingsAdvancedTitle = tr("settings.advanced.title")
    public static let settingsAdvancedEntryLabel = tr("settings.advanced.entry.label")
    public static let settingsDnsSection = tr("settings.dns.section")
    public static let settingsDnsAdblockLabel = tr("settings.dns.adblock.label")
    public static let settingsDnsAdblockFooter = tr("settings.dns.adblock.footer")
    public static let settingsDnsCustomLabel = tr("settings.dns.custom.label")
    public static let settingsDnsCustomPlaceholder = tr("settings.dns.custom.placeholder")
    public static let settingsDnsCustomFooter = tr("settings.dns.custom.footer")
    public static let settingsDnsCustomInvalid = tr("settings.dns.custom.invalid")

    // MARK: Phase 6 / 06-05 — auto-reconnect banner + notifications (NET-09, NET-10)

    public static func bannerReconnecting(_ attempt: Int) -> String {
        tr("banner.reconnecting", attempt)
    }
    public static let bannerFailover = tr("banner.failover")
    public static let bannerAllFailed = tr("banner.all_failed")

    public static let notificationReconnectFailedTitle = tr("notification.reconnect_failed.title")
    public static func notificationReconnectFailedBody(_ serverName: String) -> String {
        tr("notification.reconnect_failed.body", serverName)
    }
    public static let notificationReconnectFailedBodyGeneric = tr("notification.reconnect_failed.body_generic")

    // MARK: Phase 6 / 06-06 — Failover single-server notification (NET-11, D-08 edge)

    public static let notificationSingleServerUnavailableTitle = tr("notification.single_server_unavailable.title")
    public static let notificationSingleServerUnavailableBody = tr("notification.single_server_unavailable.body")
}
