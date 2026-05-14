import Foundation
import OSLog

/// Subsystem-scoped Logger для Rules Engine модуля.
///
/// Three categories track three architectural layers:
///   * **coordinator** — orchestrator actor (W2): bootstrap, performBackgroundRefresh, forceUpdate
///   * **fetcher** — HTTPS + SSRF + mirror failover layer (W1.3): per-mirror attempts and outcomes
///   * **signer** — Ed25519 verify layer (W1.2): signature length checks and verify failures
///
/// Subsystem `app.bbtb.client` mirrors AppFeatures conventions (TunnelLogger использует
/// `app.bbtb.tunnel`; main app side — `app.bbtb.client`).
enum RulesEngineLogger {
    static let coordinator = Logger(subsystem: "app.bbtb.client", category: "rules-engine.coordinator")
    static let fetcher = Logger(subsystem: "app.bbtb.client", category: "rules-engine.fetcher")
    static let signer = Logger(subsystem: "app.bbtb.client", category: "rules-engine.signer")
}
