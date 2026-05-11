import NetworkExtension

/// CORE-05 — реализация в Phase 8. Phase 1 — пустая заготовка чтобы target собирался.
final class AppProxyProvider: NEAppProxyProvider {
    override func startProxy(options: [String : Any]? = nil,
                             completionHandler: @escaping (Error?) -> Void) {
        completionHandler(NSError(domain: "BBTB.AppProxy",
                                  code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Phase 8"]))
    }
    override func stopProxy(with reason: NEProviderStopReason,
                            completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
