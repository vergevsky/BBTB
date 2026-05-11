import Foundation
import NetworkExtension
import SingBoxBridge  // re-exports Libbox
import OSLog

/// Базовый класс для PacketTunnelExtension target shells на iOS и macOS.
///
/// **Жизненный цикл (libbox v1.13.11 API — CommandServer-based):**
/// 1. ОС создаёт PacketTunnelProvider (subclass) при `manager.connection.startVPNTunnel()`
/// 2. `startTunnel(options:completionHandler:)` извлекает sing-box JSON из providerConfiguration
/// 3. `SingBoxConfigLoader.validate(json:)` — R1 + SEC-06 enforcement (защита от
///    inbounds[], clash_api/v2ray_api/cache_file, отсутствия VLESS outbound)
/// 4. `LibboxBootstrap.setup(basePath:workingPath:tempPath:)` — один раз на процесс
/// 5. Создание `ExtensionPlatformInterface(provider:serverAddressHint:)`
/// 6. `LibboxNewCommandServer(handler:platformInterface:&error)` — handler и platform
///    interface это один и тот же объект (платформа конформит обоим протоколам).
/// 7. `commandServer.start()` — поднимает локальный command channel.
/// 8. `commandServer.startOrReloadService(configContent, options:)` — запуск sing-box engine;
///    внутри он вызовет `platformInterface.openTun(_:ret0_:)`.
/// 9. После старта — `completionHandler(nil)`.
///
/// **Sleep/Wake:** `commandServer.pause()` / `commandServer.wake()` — внутренние
/// hint'ы движку. На iOS extension часто не получает эти события (RESEARCH §2), но
/// зову их безусловно, чтобы соблюсти контракт с libbox.
///
/// **Stop:** `commandServer.closeService()` + `commandServer.close()` — закрываем
/// сначала sing-box engine, потом command channel.
///
/// **Swift 6 concurrency:** libbox lifecycle и open/close вызываются как из NEProvider
/// thread'а, так и из Go-runtime. Класс `@unchecked Sendable`, изменяемое состояние
/// модифицируется только из основных NEProvider методов (NetworkExtension сериализует
/// startTunnel/stopTunnel/sleep/wake), поэтому явные локи не нужны.
open class BaseSingBoxTunnel: NEPacketTunnelProvider, @unchecked Sendable {

    public enum TunnelError: Error, LocalizedError {
        case missingProviderConfiguration
        case missingConfigJSON
        case missingServerAddress
        case configValidationFailed(Error)
        case libboxSetupFailed(Error)
        case commandServerCreationFailed(Error?)
        case commandServerStartFailed(Error)
        case serviceStartFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .missingProviderConfiguration:   return "Missing protocolConfiguration"
            case .missingConfigJSON:              return "providerConfiguration['configJSON'] missing"
            case .missingServerAddress:           return "protocolConfiguration.serverAddress missing"
            case .configValidationFailed(let e):  return "Config validation: \(e.localizedDescription)"
            case .libboxSetupFailed(let e):       return "LibboxSetup: \(e.localizedDescription)"
            case .commandServerCreationFailed(let e): return "LibboxNewCommandServer: \(String(describing: e))"
            case .commandServerStartFailed(let e):    return "commandServer.start: \(e.localizedDescription)"
            case .serviceStartFailed(let e):      return "startOrReloadService: \(e.localizedDescription)"
            }
        }
    }

    /// Активный command server. nil между stopTunnel и следующим startTunnel.
    private var commandServer: LibboxCommandServer?

    /// Platform interface, удерживаемый strong'ом на время жизни командного сервера.
    /// libbox внутри хранит weak/raw-pointer ссылку, поэтому Swift объект обязан жить
    /// до явного `commandServer.close()`.
    private var platformInterface: ExtensionPlatformInterface?

    public override init() {
        super.init()
        TunnelLogger.lifecycle.info("BaseSingBoxTunnel init")
    }

    // MARK: NEPacketTunnelProvider lifecycle

    open override func startTunnel(options: [String : NSObject]?,
                                   completionHandler: @escaping (Error?) -> Void) {
        TunnelLogger.lifecycle.notice("startTunnel called")

        // 1. Извлечь конфиг из NETunnelProviderProtocol.providerConfiguration.
        guard let proto = self.protocolConfiguration as? NETunnelProviderProtocol else {
            completionHandler(TunnelError.missingProviderConfiguration); return
        }
        guard let serverAddress = proto.serverAddress, !serverAddress.isEmpty else {
            completionHandler(TunnelError.missingServerAddress); return
        }
        guard let configJSON = proto.providerConfiguration?["configJSON"] as? String else {
            completionHandler(TunnelError.missingConfigJSON); return
        }

        // 2. R1 + SEC-06 валидация — fail-fast до любых side-effects.
        do {
            try SingBoxConfigLoader.validate(json: configJSON)
        } catch {
            TunnelLogger.security.error("R1 / SEC-06 validation failed: \(error.localizedDescription)")
            completionHandler(TunnelError.configValidationFailed(error)); return
        }

        // 3. Libbox setup (paths внутри App Group). Идемпотентно для re-start цикла.
        let basePath = AppGroupContainer.singBoxWorkingPath
        do {
            try LibboxBootstrap.setup(
                basePath: basePath,
                workingPath: basePath,
                tempPath: basePath
            )
        } catch {
            completionHandler(TunnelError.libboxSetupFailed(error)); return
        }

        // 4. PlatformInterface — реализует и LibboxPlatformInterface, и LibboxCommandServerHandler.
        let pi = ExtensionPlatformInterface(provider: self, serverAddressHint: serverAddress)
        self.platformInterface = pi

        // 5. CommandServer: первый аргумент — handler (CommandServerHandler), второй —
        //    platformInterface. Один объект конформит обоим протоколам, поэтому
        //    передаём `pi` дважды (как в canonical sing-box-for-apple).
        var libboxError: NSError?
        guard let server = LibboxNewCommandServer(pi, pi, &libboxError) else {
            completionHandler(TunnelError.commandServerCreationFailed(libboxError)); return
        }
        self.commandServer = server

        // 6. Поднять command channel.
        do {
            try server.start()
        } catch {
            completionHandler(TunnelError.commandServerStartFailed(error)); return
        }

        // 7. PHASE 1 HACK: инжектируем TUN inbound и мигрируем DNS-hijack на sing-box 1.13.
        //    Hiddify-импорт не содержит inbounds (R1-валидатор их запрещал), из-за чего
        //    sing-box engine не звал openTun. Заодно sing-box 1.13 удалил `dns` outbound —
        //    тут же переписываем `dns-out`-маршрутизацию на новый `action: "hijack-dns"`.
        //    TODO Phase 1.x: перенести в SingBoxConfigLoader.expandConfigForTunnel + ослабить
        //    R1-валидатор (см. memory: project_phase1_tun_inbound_cleanup).
        let expandedJSON: String
        do {
            expandedJSON = try Self.injectTunInbound(into: configJSON)
        } catch {
            completionHandler(TunnelError.configValidationFailed(error)); return
        }

        // 8. Стартовать sing-box engine. Внутри будет вызван `pi.openTun(_:ret0_:)`,
        //    который ставит R6-safe NEPacketTunnelNetworkSettings и возвращает TUN FD.
        let overrideOptions = LibboxOverrideOptions()
        do {
            try server.startOrReloadService(expandedJSON, options: overrideOptions)
        } catch {
            // Откатываем создание сервера, чтобы повторный startTunnel начал с чистого листа.
            try? server.closeService()
            server.close()
            self.commandServer = nil
            self.platformInterface = nil
            completionHandler(TunnelError.serviceStartFailed(error)); return
        }

        TunnelLogger.lifecycle.notice("Tunnel started successfully")
        completionHandler(nil)
    }

    open override func stopTunnel(with reason: NEProviderStopReason,
                                  completionHandler: @escaping () -> Void) {
        TunnelLogger.lifecycle.info("stopTunnel reason=\(String(describing: reason))")

        // Сначала останавливаем sing-box engine, затем command channel.
        // closeService может бросить — не блокирующее, лог и продолжаем.
        if let server = commandServer {
            do {
                try server.closeService()
            } catch {
                TunnelLogger.lifecycle.error("commandServer.closeService failed: \(error.localizedDescription)")
            }
            server.close()
        }
        platformInterface?.reset()
        commandServer = nil
        platformInterface = nil
        completionHandler()
    }

    open override func sleep(completionHandler: @escaping () -> Void) {
        // Hint для sing-box engine о входе в low-power state. На iOS extension этот
        // callback обычно не вызывается, но если ОС нас разбудит — соблюдаем контракт.
        commandServer?.pause()
        completionHandler()
    }

    open override func wake() {
        // Симметричный hint к sleep(). Реальный реконнект ставится отдельной задачей
        // Phase 6 (NET-09) — там же придёт NWPathMonitor-driven recovery.
        commandServer?.wake()
    }

    // MARK: - PHASE 1 HACK: TUN inbound injection + sing-box 1.13 DNS-hijack migration
    // TODO: перенести в SingBoxConfigLoader.expandConfigForTunnel(json:), ослабить R1
    // валидатор (разрешить tun inbound, оставить запрет socks/http/mixed), добавить tests.
    // См. auto-memory: project_phase1_tun_inbound_cleanup.

    /// Декодирует sing-box JSON, добавляет TUN inbound (если отсутствует) и мигрирует
    /// DNS-hijacking из старого формата (`dns-out` outbound + `route.rule.outbound:"dns-out"`)
    /// в новый sing-box 1.13 формат (`route.rule.action:"hijack-dns"`, без отдельного outbound).
    /// Вызывается ПОСЛЕ `SingBoxConfigLoader.validate(json:)`, поэтому полагается на то,
    /// что root — валидный JSON object с outbounds[].
    private static func injectTunInbound(into json: String) throws -> String {
        guard let data = json.data(using: .utf8),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw NSError(domain: "BBTB.injectTunInbound", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "config JSON root is not an object"])
        }

        // 1. Inject TUN inbound (idempotent).
        var inbounds = (root["inbounds"] as? [[String: Any]]) ?? []
        let hasTun = inbounds.contains { ($0["type"] as? String) == "tun" }
        if !hasTun {
            inbounds.append([
                "type": "tun",
                "tag": "tun-in",
                // /30 — узкая подсеть только для TUN p2p, не пересекается с пользовательскими LAN.
                "address": ["198.18.0.1/30"],
                "mtu": 1400,
                // false — мы УЖЕ сами настроили NEPacketTunnelNetworkSettings.includedRoutes
                // (default route). Не дать sing-box перетянуть routes на себя.
                "auto_route": false,
                // gVisor system stack — наиболее стабильный на iOS.
                "stack": "system",
                "sniff": true
            ])
            root["inbounds"] = inbounds
        }

        // 2. Удалить legacy `dns` outbound (sing-box 1.13 удалил поддержку, см. миграцию
        //    https://sing-box.sagernet.org/migration/#dns-outbound). Импорт из Hiddify мог
        //    его содержать; наш собственный шаблон тоже исторически добавлял `dns-out`.
        if var outbounds = root["outbounds"] as? [[String: Any]] {
            let filtered = outbounds.filter { ($0["type"] as? String) != "dns" }
            if filtered.count != outbounds.count {
                outbounds = filtered
                root["outbounds"] = outbounds
            }
        }

        // 3. Переписать route.rules: правила с `outbound: "dns-out"` (или вообще с протоколом
        //    `dns` и outbound, указывающим на удалённый dns outbound) превратить в
        //    `action: "hijack-dns"`. Это эквивалент в новом API.
        if var route = root["route"] as? [String: Any] {
            if var rules = route["rules"] as? [[String: Any]] {
                var changed = false
                for i in rules.indices {
                    var rule = rules[i]
                    let outboundRef = rule["outbound"] as? String
                    let isDnsProto = (rule["protocol"] as? String) == "dns"
                    if outboundRef == "dns-out" || (isDnsProto && outboundRef != nil) {
                        rule.removeValue(forKey: "outbound")
                        rule["action"] = "hijack-dns"
                        rules[i] = rule
                        changed = true
                    }
                }
                if changed {
                    route["rules"] = rules
                    root["route"] = route
                }
            }
            // Если final ссылался на dns-out — это бессмыслица для финального outbound,
            // но на всякий случай подменим на vless-out (он гарантирован SEC-06).
            if (route["final"] as? String) == "dns-out" {
                route["final"] = "vless-out"
                root["route"] = route
            }
        }

        let modifiedData = try JSONSerialization.data(withJSONObject: root, options: [])
        guard let modifiedString = String(data: modifiedData, encoding: .utf8) else {
            throw NSError(domain: "BBTB.injectTunInbound", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "failed to encode modified JSON"])
        }
        return modifiedString
    }
}
