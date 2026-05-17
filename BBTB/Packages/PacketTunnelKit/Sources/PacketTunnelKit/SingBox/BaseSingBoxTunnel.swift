import Foundation
import NetworkExtension
import SingBoxBridge  // re-exports Libbox
import OSLog
import os.signpost

// MARK: - Engine boundary marker (Phase 7c, 2026-05-14)
//
// Sing-box specific code is contained under `Sources/PacketTunnelKit/SingBox/`.
// Engine-agnostic utilities (`AppGroupContainer`, `TunnelSettings`, `TunnelLogger`,
// `ExternalVPNStopMarker`, `InterfaceFlagsInspector`) stay at the top level.
//
// When introducing a second engine (AmneziaWG / Partout / etc — see
// `wiki/amneziawg-deferral-2026.md` + `wiki/openvpn-deferral-2026.md`), refer to
// `BBTB/Packages/PacketTunnelKit/Docs/EngineAbstractionDecision.md` for the
// trigger criteria and recommended architectural pattern (Amnezia-style switch
// dispatch vs IVPN-style separate extension targets — see Codex thread
// `019e2802-ed23-7f21-bd6a-138edea62528`). Do NOT preemptively introduce a
// `protocol TunnelEngine` while there is only one production engine — Codex
// research confirmed «no production iOS VPN app uses pre-built protocol
// abstraction with a single implementation».

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
        /// Phase 6d post-fix 4 (2026-05-14, Codex consult #3) — user disabled
        /// VPN via iOS Settings; on-demand attempted to restart, blocked.
        case userDisabledInSettings

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
            case .userDisabledInSettings:         return "User disabled VPN in iOS Settings; manual reconnect required"
            }
        }
    }

    /// Активный command server. nil между stopTunnel и следующим startTunnel.
    /// **T-C-H5' (closes A1'-3-002 + C1'-3-003 HIGH/MEDIUM Plan 06 cross-validated):**
    /// все reads/writes идут через `lifecycleQueue.sync` для защиты от race
    /// между provider queue (stopTunnel/sleep/wake) и `DispatchQueue.global`
    /// (startTunnel async closure). Pre-fix race мог двойной `close()` LibboxCommandServer
    /// → Go panic at gomobile boundary → extension SIGABRT.
    private var commandServer: LibboxCommandServer?

    /// Platform interface, удерживаемый strong'ом на время жизни командного сервера.
    /// libbox внутри хранит weak/raw-pointer ссылку, поэтому Swift объект обязан жить
    /// до явного `commandServer.close()`. **T-C-H5':** same lifecycle queue.
    private var platformInterface: ExtensionPlatformInterface?

    /// **T-C-H5' (closes A1'-3-002 HIGH):** dedicated serial queue для lifecycle
    /// mutations. NetworkExtension serializes ITS callbacks (startTunnel /
    /// stopTunnel / sleep / wake on provider queue), but Phase 6e added a
    /// `DispatchQueue.global(qos: .userInitiated).async` block for
    /// `startOrReloadService` (Step 8 of startTunnel) — this breaks the
    /// provider-queue serial assumption from Phase 6c.
    ///
    /// All reads/writes of `commandServer` + `platformInterface` after Step 8
    /// dispatch MUST go through `lifecycleQueue.sync { }`. Read patterns
    /// (e.g. `commandServer?.pause()` в sleep) also need lifecycle queue to
    /// avoid use-after-stop где stopTunnel just set commandServer = nil.
    private let lifecycleQueue = DispatchQueue(label: "app.bbtb.tunnel.lifecycle")

    /// **T-C-H5':** generation counter для filtering stale completion callbacks.
    /// Incremented в stopTunnel; startTunnel async closure captures current gen
    /// and skips error-path mutations if generation advanced (i.e. stopTunnel
    /// happened между). Prevents double-close race.
    private var startGeneration: UInt64 = 0

    /// Phase 6d Wave 02a — OSSignposter для `LibboxStart` span. Покрывает обе
    /// платформы (iOS + macOS PacketTunnelExtension targets), потому что
    /// shells (PacketTunnelExtension-iOS / -macOS) — пустые subclasses без
    /// override'а startTunnel. Категория `performance` (sibling к TunnelLogger
    /// lifecycle/libbox/security). Instruments → Points of Interest →
    /// subsystem=app.bbtb.tunnel, category=performance.
    private static let perfSignposter = OSSignposter(
        subsystem: "app.bbtb.tunnel",
        category: "performance"
    )

    public override init() {
        super.init()
        TunnelLogger.lifecycle.info("BaseSingBoxTunnel init")
    }

    // MARK: - Phase 6e Wave 1 M8 — pre-expand validate cache marker

    /// Phase 6e Wave 1 M8 + L12 (Plan 06E-01) — pure static helper для testable
    /// pre-expand validate gate. Используется в `startTunnel` (под line 158) для
    /// решения: выполнять ли R1/SEC-06 validate (line 156-164) или skip-нуть
    /// если `providerConfiguration["configJSONValidatedAt"]` < 24h.
    ///
    /// **CRITICAL R10 preservation (`wiki/security-gaps.md` R10):**
    /// POST-expand validate (line 240-251) ВСЕГДА выполняется — defense-in-depth
    /// invariant. Этот helper касается ТОЛЬКО pre-expand step.
    ///
    /// Возвращает `true` (skip pre-expand) когда:
    ///   1. `providerConfiguration["configJSONValidatedAt"]` присутствует;
    ///   2. value parsable как ISO8601 date;
    ///   3. (now - parsed) < 24 * 3600 seconds.
    ///
    /// `false` (run pre-expand) во всех остальных случаях — backward-compat
    /// для cold-reboot, защита от corrupted timestamps, и stale > 24h.
    internal static func shouldSkipPreExpandValidate(
        providerConfiguration: [String: Any],
        now: Date = Date()
    ) -> Bool {
        guard let validatedAtRaw = providerConfiguration["configJSONValidatedAt"] as? String else {
            return false  // missing key → backward-compat, run validate
        }
        // Используем shared formatter; instantiation cost минимален (≤ 1 на startTunnel).
        let formatter = ISO8601DateFormatter()
        guard let validatedAt = formatter.date(from: validatedAtRaw) else {
            return false  // malformed timestamp → safety: run validate
        }
        return now.timeIntervalSince(validatedAt) < 24 * 3600
    }

    // MARK: NEPacketTunnelProvider lifecycle

    open override func startTunnel(options: [String : NSObject]?,
                                   completionHandler: @escaping (Error?) -> Void) {
        TunnelLogger.lifecycle.notice("startTunnel called")

        // Phase 6d post-fix 5 (2026-05-14, open-source research) —
        // Apple-canonical discriminator + sticky marker.
        //
        // Host's `TunnelController.connect()` passes `options["manualStart"]=true`
        // via `manager.connection.startVPNTunnel(options:)`. iOS on-demand
        // auto-reconnect ALWAYS passes nil options (per Apple docs:
        // "If the tunnel was started via Connect On Demand, options is nil").
        //
        // Rule:
        //   - If `options["manualStart"] == true` → app-initiated, ALLOW
        //     (host already cleared marker in `connect()` for safety; defensive
        //     clear here too against any leftover state).
        //   - Else if marker pending → iOS on-demand auto-retry, BLOCK.
        //   - Else → first cold-start or non-marked start, ALLOW.
        let isManualStart = (options?[TunnelStartOptionsKey.manualStart] as? Bool) == true
        if isManualStart {
            ExternalVPNStopMarker.clear()
            TunnelLogger.lifecycle.notice("startTunnel: manualStart=true (app-initiated) → ALLOW; marker cleared.")
        } else if ExternalVPNStopMarker.isPending() {
            TunnelLogger.lifecycle.notice("startTunnel BLOCKED: options=nil (OS-driven) AND marker pending (previous Settings VPN-off). Manual Connect in BBTB required.")
            completionHandler(TunnelError.userDisabledInSettings)
            return
        }

        // Phase 6d Wave 02a — open `LibboxStart` span. Закрываем во ВСЕХ
        // completion paths (error guards + async success/error). `endLibboxStart`
        // — local helper closure для readability. Instrumentation only.
        let libboxStartID = Self.perfSignposter.makeSignpostID()
        let libboxStartState = Self.perfSignposter.beginInterval("LibboxStart", id: libboxStartID)
        let endLibboxStart: () -> Void = {
            Self.perfSignposter.endInterval("LibboxStart", libboxStartState)
        }

        // 1. Извлечь конфиг из NETunnelProviderProtocol.providerConfiguration.
        guard let proto = self.protocolConfiguration as? NETunnelProviderProtocol else {
            TunnelLogger.lifecycle.error("startTunnel: missingProviderConfiguration (protocolConfiguration is nil or wrong type)")
            endLibboxStart()
            completionHandler(TunnelError.missingProviderConfiguration); return
        }
        guard let serverAddress = proto.serverAddress, !serverAddress.isEmpty else {
            TunnelLogger.lifecycle.error("startTunnel: missingServerAddress (proto.serverAddress is nil or empty)")
            endLibboxStart()
            completionHandler(TunnelError.missingServerAddress); return
        }
        guard let configJSON = proto.providerConfiguration?["configJSON"] as? String else {
            TunnelLogger.lifecycle.error("startTunnel: missingConfigJSON (providerConfiguration['configJSON'] is missing)")
            endLibboxStart()
            completionHandler(TunnelError.missingConfigJSON); return
        }
        TunnelLogger.lifecycle.info("startTunnel: configJSON extracted, length=\(configJSON.count)")

        // Phase 6 — providerConfiguration["configJSON"] now contains DNS settings
        // baked in by PoolBuilder per DNSConfig (see VPNCore/DNSConfig.swift).
        // No separate `dnsConfig` key is needed; the JSON is the single source of truth.
        //
        // Flow: SettingsViewModel (Wave 3) → ConfigImporter.buildDNSConfig (Wave 5) →
        // PoolBuilder.buildSingBoxJSON(from:dns:) → configJSON → here → libbox.
        //
        // If future phases need to override DNS at extension-side (e.g. emergency
        // bootstrap fallback when 1.1.1.1 is blocked), add a typed `dnsConfigOverride`
        // key here — DO NOT re-parse the JSON.

        // 2. R1 + SEC-06 валидация — fail-fast до любых side-effects.
        //
        // Phase 6e Wave 1 M8 + L12 (Plan 06E-01) — pre-expand validate теперь
        // GUARDED через `configJSONValidatedAt` 24h cache marker:
        // ConfigImporter записывает ISO8601 timestamp в providerConfiguration
        // после собственного successful validate, и здесь мы skip-аем
        // повторный validate если timestamp < 24h. Снижает cold-start /
        // wake-up cost для часто-стартующих туннелей.
        //
        // **R10 defense-in-depth preservation (CRITICAL):** POST-expand validate
        // (шаг 7b ниже, line ~240-251) ОСТАЁТСЯ unconditional и всегда
        // выполняется. Это закрывает attack surface "expandConfigForTunnel
        // mutation adds forbidden inbound" (см. wiki/security-gaps.md R10).
        let providerConfig = proto.providerConfiguration ?? [:]
        let skipPreExpand = Self.shouldSkipPreExpandValidate(providerConfiguration: providerConfig)
        if skipPreExpand {
            TunnelLogger.lifecycle.info("startTunnel: pre-expand R1/SEC-06 validation skipped (validatedAt within 24h window)")
        } else {
            do {
                try SingBoxConfigLoader.validate(json: configJSON)
                TunnelLogger.lifecycle.info("startTunnel: R1/SEC-06 validation passed")
            } catch {
                TunnelLogger.security.error("R1 / SEC-06 validation failed: \(error.localizedDescription)")
                endLibboxStart()
                completionHandler(TunnelError.configValidationFailed(error)); return
            }
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
            endLibboxStart()
            completionHandler(TunnelError.libboxSetupFailed(error)); return
        }

        // 4. PlatformInterface — реализует и LibboxPlatformInterface, и LibboxCommandServerHandler.
        // T-C-H5' (closes A1'-3-002): mutate через lifecycle queue для consistency.
        let pi = ExtensionPlatformInterface(provider: self, serverAddressHint: serverAddress)
        lifecycleQueue.sync { self.platformInterface = pi }

        // 5. CommandServer: первый аргумент — handler (CommandServerHandler), второй —
        //    platformInterface. Один объект конформит обоим протоколам, поэтому
        //    передаём `pi` дважды (как в canonical sing-box-for-apple).
        var libboxError: NSError?
        guard let server = LibboxNewCommandServer(pi, pi, &libboxError) else {
            TunnelLogger.lifecycle.error("startTunnel: LibboxNewCommandServer failed: \(String(describing: libboxError))")
            endLibboxStart()
            completionHandler(TunnelError.commandServerCreationFailed(libboxError)); return
        }
        lifecycleQueue.sync { self.commandServer = server }  // T-C-H5'

        // 6. Поднять command channel.
        do {
            try server.start()
            TunnelLogger.lifecycle.info("startTunnel: commandServer.start OK")
        } catch {
            TunnelLogger.lifecycle.error("startTunnel: commandServer.start failed: \(error.localizedDescription)")
            // Phase 6e Wave 2 Theme B (L20) — defensive cleanup. Если start() throws,
            // `server` уже создан LibboxNewCommandServer (4. выше) и self.commandServer
            // = server (line 245). Без явного close() остаются stale references на
            // PlatformInterface через LibboxCommandServer внутренние состояния, что
            // может привести к use-after-free на rapid restart. Mirror cleanup-в-stop
            // path (line 327-328: closeService + close).
            server.close()
            lifecycleQueue.sync {  // T-C-H5'
                self.commandServer = nil
                self.platformInterface = nil
            }
            endLibboxStart()
            completionHandler(TunnelError.commandServerStartFailed(error)); return
        }

        // 7. Expand config: добавить TUN inbound (Hiddify-импорт не несёт inbounds) +
        //    мигрировать DNS-hijack на sing-box 1.13 формат. См. SingBoxConfigLoader
        //    (W3.1) и Wiki/security-gaps.md R10 для обоснования полей TUN inbound.
        //
        //    Phase 6d-03a (H1, 2026-05-14): Phase 5 debug leftover устранён — в Release
        //    no logPath + logLevel="info". В Debug — full trace для разработки. Это
        //    закрывает 3/3 strong consensus finding (Opus #40 + Codex #4 + Gemini #2);
        //    предположительно главная причина «феель тяжести с Phase 5» — extension
        //    писал десятки MB на каждое соединение в App Group.
        //
        //    Phase 1 device debug history: trace инжектился для diff Vision flow internal
        //    events между working (Apple) и broken (Cloudflare HTTPS) соединениями.
        //    Сохраняем для DEBUG builds.
        #if DEBUG
        let singBoxLogPath: String? = AppGroupContainer.singBoxLogPath
        let singBoxLogLevel = "trace"
        #else
        let singBoxLogPath: String? = nil
        let singBoxLogLevel = "info"
        #endif
        let expandedJSON: String
        do {
            expandedJSON = try SingBoxConfigLoader.expandConfigForTunnel(
                json: configJSON,
                logPath: singBoxLogPath,
                logLevel: singBoxLogLevel
            )
            TunnelLogger.lifecycle.info("startTunnel: expandConfigForTunnel OK, length=\(expandedJSON.count), logPath=\(singBoxLogPath ?? "<nil>", privacy: .public), logLevel=\(singBoxLogLevel, privacy: .public)")
        } catch {
            TunnelLogger.lifecycle.error("startTunnel: expandConfigForTunnel failed: \(error.localizedDescription)")
            // T-B9 / C1-001 fix: commandServer already started (step 6, line 265);
            // expand failure must release libbox resources before completionHandler.
            // Mirror cleanup from step 6 throw path (line 275-277).
            server.close()
            lifecycleQueue.sync {  // T-C-H5'
                self.commandServer = nil
                self.platformInterface = nil
            }
            endLibboxStart()
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
            // T-B9 / C1-001 fix: same cleanup as expandConfigForTunnel failure.
            server.close()
            lifecycleQueue.sync {  // T-C-H5'
                self.commandServer = nil
                self.platformInterface = nil
            }
            endLibboxStart()
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
        // T-C-H5' (closes A1'-3-002 + C1'-3-003): capture generation snapshot
        // before дispatch. On error path, only mutate self.commandServer if
        // generation hasn't advanced (i.e. stopTunnel hasn't run между).
        // Without this check: stopTunnel runs concurrently → both paths call
        // server.close() → Go panic → extension crash.
        let capturedGeneration = lifecycleQueue.sync { startGeneration }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try server.startOrReloadService(expandedJSON, options: overrideOptions)
                TunnelLogger.lifecycle.info("startTunnel: startOrReloadService OK")
                TunnelLogger.lifecycle.notice("Tunnel started successfully")
                endLibboxStart()
                completionHandler(nil)
            } catch {
                TunnelLogger.lifecycle.error("startTunnel: startOrReloadService failed: \(error.localizedDescription)")
                // T-C-H5': guard against stopTunnel having already cleaned up.
                let stillCurrent: Bool = self?.lifecycleQueue.sync { [weak self] in
                    guard let self else { return false }
                    return self.startGeneration == capturedGeneration
                } ?? false
                if stillCurrent {
                    try? server.closeService()
                    server.close()
                    self?.lifecycleQueue.sync { [weak self] in
                        // Re-check inside critical section (stopTunnel could
                        // have raced again between checks).
                        if self?.startGeneration == capturedGeneration {
                            self?.commandServer = nil
                            self?.platformInterface = nil
                        }
                    }
                } else {
                    TunnelLogger.lifecycle.notice("startTunnel error-path: generation advanced (stopTunnel ran); skipping close — already cleaned up")
                }
                endLibboxStart()
                completionHandler(TunnelError.serviceStartFailed(error))
            }
        }
    }

    open override func stopTunnel(with reason: NEProviderStopReason,
                                  completionHandler: @escaping () -> Void) {
        TunnelLogger.lifecycle.info("stopTunnel reason=\(String(describing: reason))")

        // Phase 6d post-fix 4 (2026-05-14, Codex consult #3) — mark
        // user-initiated / provider-disabled stops so that iOS on-demand
        // auto-reconnect is BLOCKED until explicit user Connect tap.
        //
        // Reason values:
        //   .userInitiated      — iOS Settings VPN toggle off, OR host app's
        //                         `connection.stopVPNTunnel()` (manual disconnect)
        //   .providerDisabled   — OS disabled the provider
        //
        // Host's `TunnelController.connect()` clears the marker before each
        // explicit start, so manual Disconnect → Connect cycle works normally.
        // iOS on-demand cannot clear the marker — it goes straight to
        // `startTunnel` which then sees the marker and rejects.
        if reason == .userInitiated || reason == .providerDisabled {
            ExternalVPNStopMarker.mark()
            TunnelLogger.lifecycle.notice("stopTunnel: marked external VPN stop in App Group (reason=\(String(describing: reason)))")
        }

        // T-C-H5' (closes A1'-3-002 HIGH): atomic capture + clear через
        // lifecycle queue. Increment generation BEFORE close to invalidate
        // any in-flight startTunnel async closure waiting на error path.
        let (serverToClose, pi) = lifecycleQueue.sync { () -> (LibboxCommandServer?, ExtensionPlatformInterface?) in
            startGeneration &+= 1
            let s = commandServer
            let p = platformInterface
            commandServer = nil
            platformInterface = nil
            return (s, p)
        }
        if let server = serverToClose {
            do {
                try server.closeService()
            } catch {
                TunnelLogger.lifecycle.error("commandServer.closeService failed: \(error.localizedDescription)")
            }
            server.close()
        }
        pi?.reset()
        completionHandler()
    }

    open override func sleep(completionHandler: @escaping () -> Void) {
        // Hint для sing-box engine о входе в low-power state. На iOS extension этот
        // callback обычно не вызывается, но если ОС нас разбудит — соблюдаем контракт.
        // T-C-H5' (closes A1'-3-002): read commandServer через lifecycle queue
        // для защиты от race с stopTunnel.
        let server = lifecycleQueue.sync { commandServer }
        server?.pause()
        completionHandler()
    }

    open override func wake() {
        // Симметричный hint к sleep(). Реальный реконнект ставится отдельной задачей
        // Phase 6 (NET-09) — там же придёт NWPathMonitor-driven recovery.
        // T-C-H5' (closes A1'-3-002): same lifecycle queue protection as sleep().
        let server = lifecycleQueue.sync { commandServer }
        server?.wake()
    }

}
