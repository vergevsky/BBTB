import Foundation

/// LOC-01: type-safe accessor для Localizable.xcstrings.
/// Phase 1 baseline + Phase 2 W4.T2 extension (28+ new keys per UI-SPEC §9).
///
/// Phase 6e Wave 2 Theme A (L3) — non-launch keys конвертированы из `static let`
/// в `static var x: String { tr("x") }`. `static let` инициализируется eagerly
/// при первом доступе к enum'у L10n — что приводит к загрузке Bundle.module
/// и parse всех 60+ ключей при cold start. `static var` lazy-резолвится только
/// при actual чтении конкретного ключа. Launch-critical keys (status*, action*,
/// app*, empty*, menu*, alertImportFailed, settingsTitle) оставлены как
/// `static let` — они нужны на первой кадре MainScreenView/EmptyStateCard.
/// См. RESEARCH.md L3.
public enum L10n {
    private static func tr(_ key: String) -> String {
        NSLocalizedString(key, bundle: Bundle.module, comment: "")
    }
    private static func tr(_ key: String, _ args: CVarArg...) -> String {
        let fmt = NSLocalizedString(key, bundle: Bundle.module, comment: "")
        return String(format: fmt, arguments: args)
    }

    // MARK: Launch-critical (static let — eager, on first MainScreenView render)

    public static let appDisplayName = tr("app.display_name")
    public static let appShortName = tr("app.short_name")
    public static let statusEmpty = tr("status.empty")
    public static let statusIdle = tr("status.idle")
    public static let statusConnecting = tr("status.connecting")
    public static let statusConnected = tr("status.connected")
    public static let statusError = tr("status.error")
    public static let statusDisconnected = tr("status.disconnected")
    public static let actionImportFromClipboard = tr("action.import_from_clipboard")
    public static let actionConnect = tr("action.connect")
    public static let actionDisconnect = tr("action.disconnect")
    public static let actionRetry = tr("action.retry")
    public static let actionScanQR = tr("action.scan_qr")
    public static let actionOK = tr("action.ok")
    public static let emptyTitle = tr("empty.title")
    public static let emptySubtitle = tr("empty.subtitle")
    // 2026-05-16 — ConnectionButton per-state labels per Figma BBTB v3
    // (frames 3047:538/598/568 — connecting/connected/error). Все launch-critical
    // т.к. рендерятся на первом кадре `.idle/.connecting/.connected/.error`.
    /// 2026-05-16 — floating banner для .error state (Figma 3047:568 accent pill).
    public static let bannerConnectionError = tr("banner.connection_error")
    public static let homeButtonConnecting = tr("home.button.connecting")
    public static let homeButtonConnected = tr("home.button.connected")
    public static let homeButtonError = tr("home.button.error")
    public static let homeButtonHintDisconnect = tr("home.button.hint_disconnect")
    public static let homeButtonHintReconnect = tr("home.button.hint_reconnect")
    public static let menuAddConfig = tr("menu.add_config")
    public static let menuScanQR = tr("menu.scan_qr")
    public static let menuImportFromClipboard = tr("menu.import_from_clipboard")
    public static let settingsTitle = tr("settings.title")
    public static let alertImportFailed = tr("alert.import_failed.title")
    public static let alertTunnelErrorTitle = tr("alert.tunnel_error.title")

    // MARK: Non-launch (static var — lazy, resolved on first access)

    public static var actionDetails: String { tr("action.details") }
    public static var actionCancel: String { tr("action.cancel") }
    public static var actionDelete: String { tr("action.delete") }

    public static var importErrorNoPasteboard: String { tr("import.error.no_pasteboard") }
    public static var importErrorMalformed: String { tr("import.error.malformed") }
    public static var importErrorNotReality: String { tr("import.error.not_reality") }
    public static var importSuccess: String { tr("import.success") }

    public static var menubarConnect: String { tr("menubar.connect") }
    public static var menubarDisconnect: String { tr("menubar.disconnect") }
    public static var menubarOpenWindow: String { tr("menubar.open_window") }

    public static var serverLabel: String { tr("server.label") }
    public static var serverAuto: String { tr("server.auto") }

    public static var timerLabel: String { tr("timer.label") }

    public static var settingsSecuritySection: String { tr("settings.security.section") }
    public static var settingsKillSwitchLabel: String { tr("settings.kill_switch.label") }
    public static var settingsKillSwitchFooter: String { tr("settings.kill_switch.footer") }

    // MARK: Phase 6c / Plan 06C-03 — раздел «Подключение» + Auto-reconnect (D-04..D-07)

    public static var settingsConnectionSection: String { tr("settings.connection.section") }
    public static var settingsAutoReconnectTitle: String { tr("settings.auto_reconnect.title") }
    public static var settingsAutoReconnectFooter: String { tr("settings.auto_reconnect.footer") }

    public static var bannerReconnectNeeded: String { tr("banner.reconnect_needed") }
    public static var bannerDismiss: String { tr("banner.dismiss") }

    public static var qrTitle: String { tr("qr.title") }
    public static var qrCancel: String { tr("qr.cancel") }
    public static var qrHint: String { tr("qr.hint") }
    public static var qrPermissionDeniedTitle: String { tr("qr.permission_denied.title") }
    public static var qrPermissionDeniedMessage: String { tr("qr.permission_denied.message") }
    public static var qrPermissionDeniedOpenSettings: String { tr("qr.permission_denied.open_settings") }

    public static var importErrorNoSupportedConfigs: String { tr("import.error.no_supported_configs") }
    public static func importErrorNetwork(_ detail: String) -> String { tr("import.error.network", detail) }
    public static var importErrorValidation: String { tr("import.error.validation") }
    public static var importErrorV2rayUnsupported: String { tr("import.error.v2ray_unsupported") }
    public static var importProgress: String { tr("import.progress") }
    public static var importSuccessTitle: String { tr("import.success.title") }
    public static func importSuccessMessage(_ added: Int, _ unsupported: Int) -> String {
        tr("import.success.message", added, unsupported)
    }

    // MARK: Phase 3 Plan 03 — server list sheet (per UI-SPEC §9.5)

    public static var serverAutoTitle: String { tr("server.auto.title") }
    public static var serverAutoSubtitle: String { tr("server.auto.subtitle") }
    public static var serverLineHint: String { tr("server.line.hint") }

    public static var serverListTitle: String { tr("serverList.title") }
    public static var serverListManualSection: String { tr("serverList.manualSection") }
    public static var serverListUnsupportedBadge: String { tr("serverList.unsupportedBadge") }
    public static var serverListUnreachable: String { tr("serverList.unreachable") }
    public static var serverListDeleteServer: String { tr("serverList.deleteServer") }
    public static var serverListDeleteSubscription: String { tr("serverList.deleteSubscription") }
    public static func serverListDeleteSubscriptionConfirm(_ name: String, _ count: Int) -> String {
        tr("serverList.deleteSubscription.confirm.message", name, count)
    }
    public static var serverListEmptyTitle: String { tr("serverList.empty.title") }
    public static var serverListEmptySubtitle: String { tr("serverList.empty.subtitle") }
    public static var serverListRefreshErrorTitle: String { tr("serverList.refresh.error.title") }
    public static var serverListRefreshErrorMessage: String { tr("serverList.refresh.error.message") }
    public static func serverListSubscriptionFetchError(_ code: Int) -> String {
        tr("serverList.subscription.fetchError", code)
    }
    public static var serverListLastFetchedJustNow: String { tr("serverList.lastFetched.justNow") }
    public static func serverListLastFetchedMinutes(_ n: Int) -> String {
        tr("serverList.lastFetched.minutes", n)
    }
    public static func serverListLastFetchedHours(_ n: Int) -> String {
        tr("serverList.lastFetched.hours", n)
    }
    public static func serverListLastFetchedDays(_ n: Int) -> String {
        tr("serverList.lastFetched.days", n)
    }
    public static var importSubscriptionAddedTitle: String { tr("import.subscription.added.title") }
    public static func importSubscriptionAddedMessage(_ added: Int, _ name: String, _ unsupported: Int) -> String {
        tr("import.subscription.added.message", added, name, unsupported)
    }
    public static var importSubscriptionUpdatedTitle: String { tr("import.subscription.updated.title") }
    public static func importSubscriptionUpdatedMessage(_ newCount: Int, _ name: String, _ total: Int) -> String {
        tr("import.subscription.updated.message", newCount, name, total)
    }
    public static func serverListManualSubscriptionFallback(_ n: Int) -> String {
        tr("serverList.manualSubscriptionName.fallback", n)
    }

    // MARK: Phase 3 Plan 05 — pre-connect auto-select + Pitfall-8 errors

    public static var serverListNoReachableServers: String { tr("serverList.noReachableServers") }
    public static var serverListNoSupportedServers: String { tr("serverList.noSupportedServers") }

    // MARK: Phase 5 Wave 8 — ServerDetailView (TRANSP-05, D-18)

    public static var serverDetailGeneralSection: String { tr("serverDetail.generalSection") }
    public static var serverDetailParsedSection: String { tr("serverDetail.parsedSection") }
    public static var serverDetailTransportSection: String { tr("serverDetail.transportSection") }
    public static var serverDetailTransport: String { tr("serverDetail.transport") }
    public static var serverDetailTransportAuto: String { tr("serverDetail.transportAuto") }
    public static var serverDetailTransportFooter: String { tr("serverDetail.transportFooter") }
    public static var serverDetailName: String { tr("serverDetail.name") }
    public static var serverDetailHost: String { tr("serverDetail.host") }
    public static var serverDetailPort: String { tr("serverDetail.port") }
    public static var serverDetailProtocol: String { tr("serverDetail.protocol") }
    public static var serverDetailLatency: String { tr("serverDetail.latency") }
    public static var serverDetailFlow: String { tr("serverDetail.flow") }
    public static var serverDetailFingerprint: String { tr("serverDetail.fingerprint") }
    public static var serverDetailPublicKey: String { tr("serverDetail.publicKey") }
    public static var serverDetailShortId: String { tr("serverDetail.shortId") }
    public static var serverDetailAccessibilityHint: String { tr("serverDetail.accessibilityHint") }

    // MARK: Phase 6 / 06-03 — AdvancedSettingsView + DNS section (NET-02, NET-03)

    public static var settingsAdvancedTitle: String { tr("settings.advanced.title") }
    public static var settingsAdvancedEntryLabel: String { tr("settings.advanced.entry.label") }
    public static var settingsDnsSection: String { tr("settings.dns.section") }
    public static var settingsDnsAdblockLabel: String { tr("settings.dns.adblock.label") }
    public static var settingsDnsAdblockFooter: String { tr("settings.dns.adblock.footer") }
    public static var settingsDnsCustomLabel: String { tr("settings.dns.custom.label") }
    public static var settingsDnsCustomPlaceholder: String { tr("settings.dns.custom.placeholder") }
    public static var settingsDnsCustomFooter: String { tr("settings.dns.custom.footer") }
    public static var settingsDnsCustomInvalid: String { tr("settings.dns.custom.invalid") }

    // MARK: Phase 6 / 06-05 — auto-reconnect banner + notifications (NET-09, NET-10)

    public static func bannerReconnecting(_ attempt: Int) -> String {
        tr("banner.reconnecting", attempt)
    }
    public static var bannerFailover: String { tr("banner.failover") }
    public static var bannerAllFailed: String { tr("banner.all_failed") }

    // Phase 6c / Plan 06C-04 / Task 1 — `.connecting` banner (OQ-7 mapping).
    public static var bannerConnecting: String { tr("banner.connecting") }

    public static var notificationReconnectFailedTitle: String { tr("notification.reconnect_failed.title") }
    public static func notificationReconnectFailedBody(_ serverName: String) -> String {
        tr("notification.reconnect_failed.body", serverName)
    }
    public static var notificationReconnectFailedBodyGeneric: String { tr("notification.reconnect_failed.body_generic") }

    // MARK: Phase 6 / 06-06 — Failover single-server notification (NET-11, D-08 edge)

    public static var notificationSingleServerUnavailableTitle: String { tr("notification.single_server_unavailable.title") }
    public static var notificationSingleServerUnavailableBody: String { tr("notification.single_server_unavailable.body") }

    // MARK: Phase 8 W3 — RULES-09 (rules viewer) + RULES-10 (force-update) + D-11 (min_app_version)

    // RULES-09 — category headers + footers
    public static var rulesSectionBlock: String { tr("rules.section.block") }
    public static var rulesSectionBlockFooter: String { tr("rules.section.block.footer") }
    public static var rulesSectionNever: String { tr("rules.section.never") }
    public static var rulesSectionNeverFooter: String { tr("rules.section.never.footer") }
    public static var rulesSectionAlways: String { tr("rules.section.always") }
    public static var rulesSectionAlwaysFooter: String { tr("rules.section.always.footer") }

    // RULES-09 — matcher sub-section names
    public static var rulesMatcherDomains: String { tr("rules.matcher.domains") }
    public static var rulesMatcherIpCidrs: String { tr("rules.matcher.ipcidrs") }
    public static var rulesMatcherCountries: String { tr("rules.matcher.countries") }

    // RULES-09 — count badges (plural-aware через xcstrings)
    public static func rulesCountDomains(_ n: Int) -> String { tr("rules.count.domains", n) }
    public static func rulesCountIpCidrs(_ n: Int) -> String { tr("rules.count.ipcidrs", n) }
    public static func rulesCountCountries(_ n: Int) -> String { tr("rules.count.countries", n) }
    /// VoiceOver-friendly count: «1247 записей» — Russian inflection через plural.
    public static func rulesCountEntriesA11y(_ n: Int) -> String { tr("rules.count.entries.a11y", n) }

    // RULES-09 — header text «ВЕРСИЯ 42 · ОБНОВЛЕНО 2 Ч НАЗАД»
    public static func rulesHeaderVersion(_ version: Int, _ relative: String) -> String {
        tr("rules.header.version", version, relative)
    }
    public static func rulesHeaderVersionA11y(_ version: Int, _ relative: String) -> String {
        tr("rules.header.version.a11y", version, relative)
    }
    public static var rulesHeaderNeverFetched: String { tr("rules.header.neverFetched") }

    // RULES-09 — defensive empty card
    public static var rulesEmptyCategory: String { tr("rules.empty.category") }
    public static var rulesEmptyTitle: String { tr("rules.empty.title") }
    public static var rulesEmptySubtitle: String { tr("rules.empty.subtitle") }

    // RULES-10 — force-update button (idle / progress / cooldown) + inline status
    public static var rulesForceUpdateSection: String { tr("rules.forceUpdate.section") }
    public static var rulesForceUpdateButton: String { tr("rules.forceUpdate.button") }
    public static var rulesForceUpdateButtonHint: String { tr("rules.forceUpdate.button.hint") }
    public static var rulesForceUpdateInProgress: String { tr("rules.forceUpdate.inProgress") }
    public static func rulesForceUpdateCooldown(_ seconds: Int) -> String {
        tr("rules.forceUpdate.cooldown", seconds)
    }
    public static func rulesForceUpdateCooldownA11y(_ seconds: Int) -> String {
        tr("rules.forceUpdate.cooldown.a11y", seconds)
    }
    public static var rulesForceUpdateCooldownHint: String { tr("rules.forceUpdate.cooldown.hint") }
    public static func rulesForceUpdateSuccess(_ version: Int) -> String {
        tr("rules.forceUpdate.success", version)
    }
    public static func rulesForceUpdateNoChange(_ version: Int) -> String {
        tr("rules.forceUpdate.noChange", version)
    }
    public static var rulesForceUpdateNetwork: String { tr("rules.forceUpdate.network") }
    public static var rulesForceUpdateSignature: String { tr("rules.forceUpdate.signature") }
    public static var rulesForceUpdateFooter: String { tr("rules.forceUpdate.footer") }

    // D-11 — min_app_version modal sheet
    public static var minAppVersionSheetTitle: String { tr("minAppVersion.sheet.title") }
    public static func minAppVersionSheetBody(_ currentVersion: String) -> String {
        tr("minAppVersion.sheet.body", currentVersion)
    }
    public static var minAppVersionSheetPrimary: String { tr("minAppVersion.sheet.primary") }
    public static var minAppVersionSheetPrimaryHint: String { tr("minAppVersion.sheet.primary.hint") }
    public static var minAppVersionSheetSecondary: String { tr("minAppVersion.sheet.secondary") }
    public static var minAppVersionSheetSecondaryHint: String { tr("minAppVersion.sheet.secondary.hint") }

    // D-11 — persistent banner
    public static var minAppVersionBannerText: String { tr("minAppVersion.banner.text") }
    public static var minAppVersionBannerCta: String { tr("minAppVersion.banner.cta") }
    public static func minAppVersionBannerA11yLabel(_ currentVersion: String) -> String {
        tr("minAppVersion.banner.a11yLabel", currentVersion)
    }
    public static var minAppVersionBannerA11yHint: String { tr("minAppVersion.banner.a11yHint") }

    // MARK: Phase 9 / DEEP-01..05 — deep-link error alert (5 keys)

    /// Phase 9 / DEEP-08 — alert title (launch-critical: может показаться сразу после
    /// cold-start, если пользователь открывает приложение через deep link с malformed URL).
    public static let alertDeepLinkErrorTitle = tr("alert.deep_link_error.title")

    /// Phase 9 — generic "unsupported link" body (lazy per Phase 6e Theme A).
    public static var deepLinkErrorUnhandled: String { tr("deep_link.error.unhandled") }

    public static func deepLinkErrorMissingParameter(_ name: String) -> String {
        tr("deep_link.error.missing_parameter", name)
    }

    public static func deepLinkErrorInvalidParameter(name: String, reason: String) -> String {
        tr("deep_link.error.invalid_parameter", name, reason)
    }

    public static func deepLinkErrorImportFailed(_ underlying: String) -> String {
        tr("deep_link.error.import_failed", underlying)
    }

    // MARK: Phase 10 / 10-01 — Anti-DPI section + Security section (DPI-06/08/09, KILL-04)

    // Anti-DPI section header/footer
    public static var settingsAntiDpiSection: String { tr("settings.antiDpi.section") }
    public static var settingsAntiDpiSectionFooter: String { tr("settings.antiDpi.sectionFooter") }

    // CDN fronting toggle
    public static var settingsAntiDpiCdnLabel: String { tr("settings.antiDpi.cdn.label") }
    public static var settingsAntiDpiCdnFooter: String { tr("settings.antiDpi.cdn.footer") }

    // Mux (connection multiplexing) toggle
    public static var settingsAntiDpiMuxLabel: String { tr("settings.antiDpi.mux.label") }
    public static var settingsAntiDpiMuxFooter: String { tr("settings.antiDpi.mux.footer") }

    // uTLS fingerprint picker
    public static var settingsAntiDpiUtlsLabel: String { tr("settings.antiDpi.utls.label") }
    public static var settingsAntiDpiUtlsFooter: String { tr("settings.antiDpi.utls.footer") }
    public static var settingsAntiDpiUtlsOptionRandom: String { tr("settings.antiDpi.utls.option.random") }
    public static var settingsAntiDpiUtlsOptionChrome: String { tr("settings.antiDpi.utls.option.chrome") }
    public static var settingsAntiDpiUtlsOptionFirefox: String { tr("settings.antiDpi.utls.option.firefox") }
    public static var settingsAntiDpiUtlsOptionSafari: String { tr("settings.antiDpi.utls.option.safari") }
    public static var settingsAntiDpiUtlsOptionIos: String { tr("settings.antiDpi.utls.option.ios") }
    public static var settingsAntiDpiUtlsOptionAndroid: String { tr("settings.antiDpi.utls.option.android") }
    public static var settingsAntiDpiUtlsOptionEdge: String { tr("settings.antiDpi.utls.option.edge") }

    // STUN block toggle + confirmation alert
    public static var settingsAntiDpiStunLabel: String { tr("settings.antiDpi.stun.label") }
    public static var settingsAntiDpiStunFooter: String { tr("settings.antiDpi.stun.footer") }
    public static var settingsAntiDpiStunConfirmTitle: String { tr("settings.antiDpi.stun.confirm.title") }
    public static var settingsAntiDpiStunConfirmMessage: String { tr("settings.antiDpi.stun.confirm.message") }
    public static var settingsAntiDpiStunConfirmAction: String { tr("settings.antiDpi.stun.confirm.action") }
    public static var settingsAntiDpiStunConfirmCancel: String { tr("settings.antiDpi.stun.confirm.cancel") }

    // Security section header
    public static var settingsSecurityCertPinningLabel: String { tr("settings.security.certPinning.label") }
    public static var settingsSecurityCertPinningFooter: String { tr("settings.security.certPinning.footer") }
    public static var settingsSecurityEnforceRoutesLabel: String { tr("settings.security.enforceRoutes.label") }
    public static var settingsSecurityEnforceRoutesFooterOn: String { tr("settings.security.enforceRoutes.footer.on") }
    public static var settingsSecurityEnforceRoutesFooterOff: String { tr("settings.security.enforceRoutes.footer.off") }

    // Rules viewer section header (used in AdvancedSettingsView navigation)
    public static var settingsRulesViewerSection: String { tr("settings.rules.viewer.section") }

    // MARK: Phase 11 / 11-01 — Onboarding (UX-01)

    public static var onboardingTitle: String { tr("onboarding.title") }
    public static var onboardingSubtitle: String { tr("onboarding.subtitle") }
    public static var onboardingPaste: String { tr("onboarding.cta_paste") }
    public static var onboardingScanQR: String { tr("onboarding.cta_qr") }
    public static var onboardingAccessibilityHint: String { tr("onboarding.a11y_hint") }
    /// 2026-05-16 — tip text над CTA-кнопками («Добавьте конфигурацию»). Figma 3062:316.
    public static var onboardingHint: String { tr("onboarding.hint") }
    /// 2026-05-16 — accessibility label для Skip (X) кнопки в TopBar. Figma 3062:342.
    public static var onboardingSkip: String { tr("onboarding.skip") }

    // MARK: Phase 11 / 11-01 — Help / FAQ (LOC-03, LOC-04)

    public static var helpTitle: String { tr("help.title") }
    public static var helpEntryLabel: String { tr("help.entry.label") }
    public static var helpFooter: String { tr("help.footer") }
    public static var helpFaq1Question: String { tr("help.faq1.question") }
    public static var helpFaq1Answer: String { tr("help.faq1.answer") }
    public static var helpFaq2Question: String { tr("help.faq2.question") }
    public static var helpFaq2Answer: String { tr("help.faq2.answer") }
    public static var helpFaq3Question: String { tr("help.faq3.question") }
    public static var helpFaq3Answer: String { tr("help.faq3.answer") }
    public static var helpFaq4Question: String { tr("help.faq4.question") }
    public static var helpFaq4Answer: String { tr("help.faq4.answer") }
    public static var helpFaq5Question: String { tr("help.faq5.question") }
    public static var helpFaq5Answer: String { tr("help.faq5.answer") }

    // MARK: Phase 11 / 11-01 — Diagnostics section (TELEM-02)

    public static var diagnosticsSection: String { tr("diagnostics.section") }
    public static var diagnosticsExportLog: String { tr("diagnostics.export_log") }
    public static var diagnosticsShareLog: String { tr("diagnostics.share_log") }
    public static var diagnosticsLast24h: String { tr("diagnostics.last_24h") }
    public static var diagnosticsPreparing: String { tr("diagnostics.preparing") }
    public static var diagnosticsNoLogsTitle: String { tr("diagnostics.no_logs.title") }
    public static var diagnosticsNoLogsMessage: String { tr("diagnostics.no_logs.message") }
    /// `diagnostics.version_format` — format string c двумя `%@`: app version + OS version.
    public static func diagnosticsVersionFormat(_ appVersion: String, _ osVersion: String) -> String {
        tr("diagnostics.version_format", appVersion, osVersion)
    }

    // MARK: Phase 11 / 11-01 — Import (file picker, IMP-03)

    public static var menuImportFromFile: String { tr("menu.import_from_file") }
    public static var importErrorFileAccessDenied: String { tr("import.error.file_access_denied") }
    public static var importErrorFileReadFailed: String { tr("import.error.file_read_failed") }

    // MARK: Phase 11 / 11-01 — Transport labels (LOC-02 cleanup для TransportPicker)

    public static var transportLabelTcp: String { tr("transport.label_tcp") }
    public static var transportLabelWebSocket: String { tr("transport.label_websocket") }
    public static var transportLabelGrpc: String { tr("transport.label_grpc") }
    public static var transportLabelHttp2: String { tr("transport.label_http2") }
    public static var transportLabelHttpUpgrade: String { tr("transport.label_http_upgrade") }

    // MARK: Phase 11 / 11-01 — Subscription fallback name (LOC-02, ConfigImporter:984)

    public static var subscriptionFallbackName: String { tr("subscription.fallback_name") }
}
