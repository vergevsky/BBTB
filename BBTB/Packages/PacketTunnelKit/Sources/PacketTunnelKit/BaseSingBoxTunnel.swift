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
            TunnelLogger.lifecycle.error("startTunnel: missingProviderConfiguration (protocolConfiguration is nil or wrong type)")
            completionHandler(TunnelError.missingProviderConfiguration); return
        }
        guard let serverAddress = proto.serverAddress, !serverAddress.isEmpty else {
            TunnelLogger.lifecycle.error("startTunnel: missingServerAddress (proto.serverAddress is nil or empty)")
            completionHandler(TunnelError.missingServerAddress); return
        }
        guard let configJSON = proto.providerConfiguration?["configJSON"] as? String else {
            TunnelLogger.lifecycle.error("startTunnel: missingConfigJSON (providerConfiguration['configJSON'] is missing)")
            completionHandler(TunnelError.missingConfigJSON); return
        }
        TunnelLogger.lifecycle.info("startTunnel: configJSON extracted, length=\(configJSON.count)")

        // 2. R1 + SEC-06 валидация — fail-fast до любых side-effects.
        do {
            try SingBoxConfigLoader.validate(json: configJSON)
            TunnelLogger.lifecycle.info("startTunnel: R1/SEC-06 validation passed")
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
            TunnelLogger.lifecycle.info("startTunnel: LibboxBootstrap.setup OK (basePath=\(basePath, privacy: .public))")
        } catch {
            TunnelLogger.lifecycle.error("startTunnel: LibboxBootstrap.setup failed: \(error.localizedDescription)")
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
            TunnelLogger.lifecycle.error("startTunnel: LibboxNewCommandServer failed: \(String(describing: libboxError))")
            completionHandler(TunnelError.commandServerCreationFailed(libboxError)); return
        }
        self.commandServer = server

        // 6. Поднять command channel.
        do {
            try server.start()
            TunnelLogger.lifecycle.info("startTunnel: commandServer.start OK")
        } catch {
            TunnelLogger.lifecycle.error("startTunnel: commandServer.start failed: \(error.localizedDescription)")
            completionHandler(TunnelError.commandServerStartFailed(error)); return
        }

        // 7. Expand config: добавить TUN inbound (Hiddify-импорт не несёт inbounds) +
        //    мигрировать DNS-hijack на sing-box 1.13 формат. См. SingBoxConfigLoader
        //    (W3.1) и Wiki/security-gaps.md R10 для обоснования полей TUN inbound.
        //
        //    Phase 1 device debug (2026-05-11): инжектим log.output → App Group/sing-box.log
        //    чтобы различать root cause «status=connected, user traffic не идёт»:
        //    нет tun-in flows = FD problem; dial timeouts = outbound loopback; нет DNS =
        //    hijack-dns не работает. TODO Phase 5: убрать logPath или сделать opt-in флагом.
        let singBoxLogPath = AppGroupContainer.singBoxLogPath
        let expandedJSON: String
        do {
            // Phase 1 W5 device debug (опция Б): logLevel="trace" — нужен для diff
            // Vision flow internal events между working (Apple) и broken (Cloudflare HTTPS)
            // соединениями. Дамп будет десятки MB; main app копирует его в Documents/ как
            // обычно через AppGroupContainer.exportSingBoxLogToDocuments(). TODO Phase 5:
            // downgrade на "debug" или вообще убрать logPath перед prod release.
            expandedJSON = try SingBoxConfigLoader.expandConfigForTunnel(
                json: configJSON,
                logPath: singBoxLogPath,
                logLevel: "trace"
            )
            TunnelLogger.lifecycle.info("startTunnel: expandConfigForTunnel OK, length=\(expandedJSON.count), logPath=\(singBoxLogPath, privacy: .public), logLevel=trace")
        } catch {
            TunnelLogger.lifecycle.error("startTunnel: expandConfigForTunnel failed: \(error.localizedDescription)")
            completionHandler(TunnelError.configValidationFailed(error)); return
        }

        // 7b. Defense-in-depth (R10): повторная R1-валидация post-expand. Если expand
        //     когда-нибудь добавит что-то запрещённое (регрессия) — поймаем здесь до
        //     `startOrReloadService`. white-list inbound types гарантирует что только
        //     {tun, direct} проходят, плюс experimental APIs всё ещё запрещены.
        do {
            try SingBoxConfigLoader.validate(json: expandedJSON)
            TunnelLogger.lifecycle.info("startTunnel: post-expand R1 re-validation passed")
        } catch {
            TunnelLogger.security.error("R1 post-expand validation failed: \(error.localizedDescription)")
            completionHandler(TunnelError.configValidationFailed(error)); return
        }

        // 8. Стартовать sing-box engine на background queue.
        //
        // КРИТИЧНО: `startOrReloadService` синхронно вызывает `pi.openTun(_:ret0_:)`,
        // который вызывает `setTunnelNetworkSettings` и блокируется на semaphore.wait()
        // до его completion-handler. iOS dispatch'ит completion на provider queue
        // (ту же, что вызвала startTunnel). Если мы запустим startOrReloadService
        // на provider queue — completion-handler будет ждать освобождения очереди,
        // которая ждёт completion-handler → deadlock → 30s timeout → extension kill.
        //
        // Канонический паттерн (sing-box-for-apple, WireGuard NE-extensions):
        // отдать тяжёлый старт на background, освободить provider queue, чтобы
        // setTunnelNetworkSettings completion мог сработать.
        let overrideOptions = LibboxOverrideOptions()
        TunnelLogger.lifecycle.notice("startTunnel: dispatching startOrReloadService off the provider queue")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try server.startOrReloadService(expandedJSON, options: overrideOptions)
                TunnelLogger.lifecycle.info("startTunnel: startOrReloadService OK")
                TunnelLogger.lifecycle.notice("Tunnel started successfully")
                completionHandler(nil)
            } catch {
                TunnelLogger.lifecycle.error("startTunnel: startOrReloadService failed: \(error.localizedDescription)")
                try? server.closeService()
                server.close()
                self?.commandServer = nil
                self?.platformInterface = nil
                completionHandler(TunnelError.serviceStartFailed(error))
            }
        }
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

}
