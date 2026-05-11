import Foundation
import MetricKit
import OSLog
import PacketTunnelKit

/// TELEM-01 — локальный crash reporter без UI отправки.
///
/// Жизненный цикл:
/// - `install()` вызывается из BBTB_iOSApp.init() / BBTB_macOSApp.init() ОДИН раз
/// - MetricKit доставляет payload'ы при следующем запуске после краша
/// - `didReceive(_ payloads:)` для MXDiagnosticPayload сохраняет JSON в App Group
///
/// **Phase 1 scope:** только запись на диск. UI отправки — Phase 12 (TELEM-03).
/// **Pitfall 8:** на macOS до 14 MetricKit мог молчать; macOS 15 улучшен, но не гарантирован.
public final class CrashReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    public static let shared = CrashReporter()

    private let log = Logger(subsystem: "app.bbtb.app", category: "CrashReporter")
    private var isInstalled = false
    private let lock = NSLock()

    public override init() { super.init() }

    /// Idempotent install — повторный вызов — no-op.
    public func install() {
        lock.lock(); defer { lock.unlock() }
        guard !isInstalled else { return }
        MXMetricManager.shared.add(self)
        isInstalled = true
        log.info("CrashReporter installed (subscribed to MXMetricManager)")
    }

    // MARK: MXMetricManagerSubscriber

    public func didReceive(_ payloads: [MXMetricPayload]) {
        // Phase 1: метрики не сохраняем (TELEM-04 — Phase 12 telemetry pipeline).
        log.debug("Received \(payloads.count) MXMetricPayload(s) — ignored in Phase 1")
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        log.notice("Received \(payloads.count) MXDiagnosticPayload(s)")
        for payload in payloads {
            saveDiagnostic(payload)
        }
    }

    // MARK: Internals

    /// Internal helper: тестируемая часть. Принимает MXDiagnosticPayload и пишет .json
    /// в `AppGroupContainer.crashReportsURL`. Используется и production path,
    /// и unit-тест через mock-subclass payload'а.
    internal func saveDiagnostic(_ payload: MXDiagnosticPayload) {
        let dir = AppGroupContainer.crashReportsURL
        let timestamp = isoFormatter.string(from: payload.timeStampBegin)
        let filename = "crash-\(timestamp.replacingOccurrences(of: ":", with: "-")).json"
        let url = dir.appendingPathComponent(filename)
        do {
            let data = payload.jsonRepresentation()
            try data.write(to: url, options: .atomic)
            log.info("Saved crash payload to \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("Failed to write crash payload: \(error.localizedDescription, privacy: .public)")
        }
    }

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: Test-only

    #if DEBUG
    /// Test hook: ручная инжекция payload для unit-test.
    /// Production code никогда это не вызывает.
    public func _test_inject(_ payloads: [MXDiagnosticPayload]) {
        didReceive(payloads)
    }
    #endif
}
