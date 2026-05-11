import Foundation

/// LOC-01: type-safe accessor для Localizable.xcstrings.
/// Все строки UI Phase 1 объявлены здесь явно; добавление новой строки = update .xcstrings + новый case ниже.
public enum L10n {
    private static func tr(_ key: String) -> String {
        NSLocalizedString(key, bundle: Bundle.module, comment: "")
    }

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
}
