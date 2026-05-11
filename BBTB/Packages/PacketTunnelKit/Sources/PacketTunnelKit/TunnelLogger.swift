import Foundation
import OSLog

/// Subsystem-scoped Logger для туннельной логики.
/// CLAUDE.md §security: нет третьесторонних log libs; никаких print();
/// secrets маскируем через OSLogPrivacy.private.
public enum TunnelLogger {
    public static let general = Logger(subsystem: "app.bbtb.tunnel", category: "general")
    public static let lifecycle = Logger(subsystem: "app.bbtb.tunnel", category: "lifecycle")
    public static let libbox = Logger(subsystem: "app.bbtb.tunnel", category: "libbox")
    public static let security = Logger(subsystem: "app.bbtb.tunnel", category: "security")
}
