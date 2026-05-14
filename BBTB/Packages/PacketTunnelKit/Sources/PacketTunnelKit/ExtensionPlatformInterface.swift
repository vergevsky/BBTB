import Foundation
import Network
import NetworkExtension
import SingBoxBridge  // re-exports Libbox

/// Реализация двух libbox-протоколов, которые движок sing-box использует для callbacks:
///   • `LibboxPlatformInterfaceProtocol`     — TUN setup, network monitoring, system queries.
///   • `LibboxCommandServerHandlerProtocol`  — system proxy и service control hooks.
///
/// Имена с суффиксом `Protocol` — это результат Swift Obj-C bridging: gomobile сгенерировал
/// одноимённые Obj-C protocol и class (`@protocol LibboxTunOptions` + `@class LibboxTunOptions`),
/// поэтому Swift добавляет `Protocol`-suffix для устранения коллизии. См. упрощённую копию
/// в SagerNet/sing-box-for-apple/Library/Network/ExtensionPlatformInterface.swift.
///
/// **R6 connection point:** `openTun(_:ret0_:)` — ЕДИНСТВЕННОЕ место в проекте, где
/// строится `NEPacketTunnelNetworkSettings` под управлением libbox. Всегда зовёт
/// `TunnelSettings.makeR6Safe(_:)`. После `setTunnelNetworkSettings` — DEBUG
/// assertion через `InterfaceFlagsInspector.assertNoPointToPointOnUtun`.
///
/// **KILL-01:** `includeAllNetworks()` всегда `true` — Phase 1 не предлагает
/// пользователю выключать kill switch.
///
/// **Swift 6 concurrency:** libbox callback'и приходят из Go-runtime threads,
/// поэтому класс помечен `@unchecked Sendable`. Изменяемое состояние (NWPathMonitor,
/// последний listener) обновляется только из libbox callbacks → последовательно
/// по контракту движка, явные локи не нужны.
public final class ExtensionPlatformInterface: NSObject, @unchecked Sendable {
    /// Слабая ссылка на провайдер — libbox владеет PlatformInterface дольше, чем
    /// сам Provider при reload-циклах, поэтому циклов retain быть не должно.
    private weak var provider: NEPacketTunnelProvider?

    /// Имя/адрес сервера для tunnelRemoteAddress (показывается в Settings → VPN).
    /// Передаётся из BaseSingBoxTunnel.startTunnel через providerConfiguration.
    private let serverAddressHint: String

    /// Последний установленный set настроек. Используется для `clearDNSCache()`
    /// (re-apply trick из canonical sing-box-for-apple).
    private var networkSettings: NEPacketTunnelNetworkSettings?

    /// NWPathMonitor для `startDefaultInterfaceMonitor` / `getInterfaces`.
    /// Создаётся лениво при первом запросе от libbox.
    private var nwMonitor: NWPathMonitor?

    /// Index текущего physical interface (Wi-Fi / Cellular / Ethernet) — обновляется
    /// в `notifyInterfaceUpdate`. Используется в `autoDetectControl(fd:)` чтобы
    /// привязывать sing-box outbound сокеты к этому интерфейсу через `IP_BOUND_IF`,
    /// обходя iOS VPN routing (которое иначе закольцевало бы их обратно в наш TUN,
    /// поскольку `includeAllNetworks=YES`).
    private var currentInterfaceIndex: UInt32 = 0

    /// **M9 (06D-03g):** Семафор «physical interface seeded». В `includeAllNetworks=YES`
    /// (KILL-01) режиме, если `autoDetectControl` вызвается до первого seed'а через
    /// `notifyInterfaceUpdate`, sing-box создал бы unbound сокеты → routing закольцевал
    /// бы их обратно в TUN → handshake timeout. Семафор сигналится один раз — при
    /// первом `notifyInterfaceUpdate(index > 0)`, после чего `physicalInterfaceSeeded`
    /// становится `true` и autoDetectControl на индексе 0 кратковременно ждёт seed'а
    /// либо throw'ает retryable error для libbox.
    private let physicalInterfaceReady = DispatchSemaphore(value: 0)
    private var physicalInterfaceSeeded: Bool = false

    /// Счётчик вызовов `autoDetectControl` для diagnostic-логирования. Первые 5
    /// вызовов логируем info, дальше — только notice раз в 100, чтобы не flood'ить.
    private var autoDetectCallCount: Int = 0

    public init(provider: NEPacketTunnelProvider, serverAddressHint: String) {
        self.provider = provider
        self.serverAddressHint = serverAddressHint
        super.init()
    }

    /// Сбрасывает кэши при остановке туннеля. Зовётся из `BaseSingBoxTunnel.stopTunnel`.
    /// **Примечание:** `physicalInterfaceReady`/`physicalInterfaceSeeded` намеренно
    /// не сбрасываются — экземпляр `ExtensionPlatformInterface` живёт ровно один
    /// startTunnel/stopTunnel цикл (создаётся в `BaseSingBoxTunnel.startTunnel`),
    /// поэтому состояние seed'а не переиспользуется между сессиями.
    func reset() {
        networkSettings = nil
        nwMonitor?.cancel()
        nwMonitor = nil
        currentInterfaceIndex = 0
    }
}

// MARK: - LibboxPlatformInterfaceProtocol

extension ExtensionPlatformInterface: LibboxPlatformInterfaceProtocol {

    // MARK: openTun — R6 critical path

    /// **R6 critical:** строит R6-safe `NEPacketTunnelNetworkSettings` и записывает
    /// TUN file descriptor в `ret0_`. На ошибку — `throws`, что libbox конвертирует
    /// в NSError* выходной параметр.
    ///
    /// Phase 1 игнорирует большую часть полей `LibboxTunOptions` (auto-route, IPv6,
    /// HTTP proxy, exclude routes): мы выдаём фиксированный R6-safe layout. Расширение
    /// до полного парсинга `options` — задача Phase 6 (NET-05..07).
    public func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let provider else {
            throw NSError(domain: "BBTB.openTun", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "provider was deallocated"])
        }
        guard let ret0_ else {
            throw NSError(domain: "BBTB.openTun", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "nil return pointer"])
        }

        // R6-safe settings: НИКОГДА не выставляем `NEIPv4Settings.destinationAddresses`,
        // иначе ОС автоматически поднимает IFF_POINTOPOINT на utun*. См. TunnelSettings.swift.
        let settings = TunnelSettings.makeR6Safe(serverAddress: serverAddressHint)

        // setTunnelNetworkSettings — асинхронный. Блокируемся через семафор: libbox
        // вызывает openTun из своего thread'а и ожидает синхронный ответ с FD.
        // ErrorBox оборачивает мутацию из callback'а — semaphore.wait() гарантирует
        // happens-before, поэтому `@unchecked Sendable` корректен в этом сценарии.
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = UncheckedSendableBox(NSMutablePointerHolder())
        TunnelLogger.lifecycle.notice("openTun: calling setTunnelNetworkSettings")
        provider.setTunnelNetworkSettings(settings) { err in
            TunnelLogger.lifecycle.notice("openTun: setTunnelNetworkSettings completion fired, err=\(String(describing: err))")
            errorBox.value.error = err
            semaphore.signal()
        }
        // **M16 (06D-03g):** Timeout сокращён с 5s до 2s. setTunnelNetworkSettings на
        // iPhone 13+ обычно завершается за <100ms; 5-секундный таймаут означал, что
        // в случае залипания completion handler'а пользователь получит замёрзший
        // connect attempt на 5 полных секунд. На Phase 6c on-demand retry дешевле
        // короткая ошибка + автоматический re-connect, чем 5-секундный freeze.
        TunnelLogger.lifecycle.notice("openTun: waiting on semaphore (timeout 2s)")
        let waitResult = semaphore.wait(timeout: .now() + 2.0)
        TunnelLogger.lifecycle.notice("openTun: semaphore wait result=\(String(describing: waitResult))")
        if waitResult == .timedOut {
            TunnelLogger.lifecycle.error("openTun: TIMEOUT — setTunnelNetworkSettings completion did not fire within 2s (provider-queue deadlock hypothesis)")
            throw NSError(domain: "BBTB.openTun", code: -10,
                          userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for setTunnelNetworkSettings completion (2s)"])
        }
        if let settingsError = errorBox.value.error {
            TunnelLogger.lifecycle.error("setTunnelNetworkSettings failed: \(String(describing: settingsError))")
            throw settingsError
        }
        self.networkSettings = settings

        // **R6 self-check (DEBUG only):** утверждаем, что utun не получил IFF_POINTOPOINT.
        // В Release — no-op.
        InterfaceFlagsInspector.assertNoPointToPointOnUtun()
        TunnelLogger.lifecycle.notice("openTun: R6 self-check passed, extracting FD")

        // FD extraction — приватный KVC путь (Pitfall 6 из RESEARCH).
        // Все sing-box / xray-based клиенты так делают; альтернативы нет.
        // Fallback на `LibboxGetTunnelFileDescriptor()` — как в canonical sing-box-for-apple.
        let kvcValue = provider.packetFlow.value(forKeyPath: "socket.fileDescriptor")
        TunnelLogger.lifecycle.notice("openTun: KVC socket.fileDescriptor = \(String(describing: kvcValue))")
        if let tunFd = kvcValue as? Int32 {
            ret0_.pointee = tunFd
            TunnelLogger.lifecycle.notice("TUN opened via KVC, fd=\(tunFd)")
            return
        }

        let fallbackFd = LibboxGetTunnelFileDescriptor()
        TunnelLogger.lifecycle.notice("openTun: LibboxGetTunnelFileDescriptor = \(fallbackFd)")
        if fallbackFd != -1 {
            ret0_.pointee = fallbackFd
            TunnelLogger.lifecycle.notice("TUN opened via LibboxGetTunnelFileDescriptor, fd=\(fallbackFd)")
            return
        }

        TunnelLogger.lifecycle.error("openTun: BOTH FD extraction paths failed — KVC nil and LibboxGetTunnelFileDescriptor=-1")
        throw NSError(domain: "BBTB.openTun", code: -3,
                      userInfo: [NSLocalizedDescriptionKey: "Failed to extract TUN FD (KVC + LibboxGetTunnelFileDescriptor both returned nil/-1)"])
    }

    // MARK: Network state queries

    /// KILL-01: всегда `true`. Phase 1 не предлагает пользователю выключать kill switch,
    /// поэтому весь трафик обязан идти через VPN-туннель.
    public func includeAllNetworks() -> Bool {
        true
    }

    /// Указывает libbox, что процесс работает внутри NetworkExtension sandbox'а.
    public func underNetworkExtension() -> Bool {
        true
    }

    /// Apple platforms не имеют `/proc` — выключаем procFS-based лукапы.
    public func useProcFS() -> Bool {
        false
    }

    /// На Apple platforms канонический клиент возвращает `false` — auto-detect
    /// делает sing-box сам через переданный nwMonitor. Swift-имя `usePlatformAutoDetectControl`
    /// — результат обрезания `Interface` в gomobile→Swift bridging.
    ///
    /// **Возвращаем `true`** — критически важно для iOS extension в `includeAllNetworks=YES`
    /// (KILL-01) режиме. Без этого ALL outbound сокеты sing-box engine идут через iOS
    /// VPN routing → закольцованы обратно в наш TUN inbound → пакеты не выходят наружу
    /// → handshake timeout. С `true` sing-box зовёт `autoDetectControl(fd)` на каждый
    /// свой socket, и мы привязываем его к physical interface через `IP_BOUND_IF`.
    public func usePlatformAutoDetectControl() -> Bool {
        TunnelLogger.lifecycle.info("usePlatformAutoDetectControl queried → returning true")
        return true
    }

    /// Auto-detect control hook — привязывает sing-box outbound socket к physical
    /// interface (текущий Wi-Fi/Cellular), минуя iOS VPN routing.
    ///
    /// **Background:** в `includeAllNetworks=YES` режиме iOS отправляет все сокеты
    /// процесса extension'а через сам VPN tunnel. Sing-box's Go-runtime создаёт TCP/UDP
    /// сокеты для VLESS outbound — без явного `IP_BOUND_IF` они идут в наш же utun и
    /// никогда не достигают сервера. setsockopt `IP_BOUND_IF` обходит VPN routing,
    /// форсируя выход через physical interface.
    ///
    /// **Что делаем:** для каждого fd ставим `IP_BOUND_IF` (IPv4) и `IPV6_BOUND_IF`
    /// (IPv6) с индексом current physical interface (обновляется NWPathMonitor'ом).
    /// Один из двух может не сработать (если socket pure-v4 или pure-v6) — это OK,
    /// throw'аем только если оба failed.
    ///
    /// **Constants:** `IP_BOUND_IF=25` (`<netinet/in.h>`), `IPV6_BOUND_IF=125`
    /// (`<netinet6/in6.h>`). Уровни: `IPPROTO_IP=0`, `IPPROTO_IPV6=41`. Не используем
    /// Darwin-импорт чтобы избежать platform-specific bridging quirks.
    public func autoDetectControl(_ fd: Int32) throws {
        autoDetectCallCount += 1
        let callNum = autoDetectCallCount
        var index = currentInterfaceIndex

        if index == 0 {
            // **M9 (06D-03g):** Physical interface ещё не определён. До 06D-03g мы
            // молча `return`'или — это в `includeAllNetworks=YES` (KILL-01) режиме
            // создаёт unbound socket, который iOS routing закольцовывает обратно в
            // наш TUN → handshake timeout. Корректнее: коротко подождать seed'а
            // (NWPathMonitor может отдать первый callback в ближайшие миллисекунды),
            // а если за 500ms не дождались — throw retryable, чтобы sing-box
            // повторил попытку через свою стандартную retry-политику, а не
            // создавал loop-сокет.
            let waitResult = physicalInterfaceReady.wait(timeout: .now() + 0.5)
            // Перечитываем актуальный index после wait (signal был мог уже произойти
            // до нашего входа в guard — в таком случае wait() сразу возвращает
            // .success на счётчике семафора).
            index = currentInterfaceIndex
            if waitResult == .timedOut || index == 0 {
                if callNum <= 5 {
                    TunnelLogger.lifecycle.error("autoDetectControl #\(callNum) fd=\(fd): no physical interface after 500ms wait — throwing retryable for sing-box")
                }
                throw NSError(
                    domain: "BBTB.autoDetectControl",
                    code: -100,
                    userInfo: [NSLocalizedDescriptionKey:
                        "No physical interface available for fd=\(fd) (currentInterfaceIndex=0 after 500ms wait); refusing to create unbound socket"]
                )
            }
            // Index появился во время wait — продолжаем bind на свежем индексе.
            if callNum <= 5 {
                // Phase 6e Wave 2 Theme C-1 (L15) — `.info` → `.debug`. Per-call
                // autoDetectControl log; не нужен по умолчанию в Console.app. Видно
                // через `log stream --predicate 'category=="lifecycle"' --level=debug`.
                TunnelLogger.lifecycle.debug("autoDetectControl #\(callNum) fd=\(fd): physical interface seeded during wait, proceeding with idx=\(index)")
            }
        }

        var idx = index
        let size = socklen_t(MemoryLayout<UInt32>.size)

        let r4 = withUnsafePointer(to: &idx) { ptr -> Int32 in
            setsockopt(fd, /* IPPROTO_IP   */ 0,  /* IP_BOUND_IF   */ 25, ptr, size)
        }
        let errno4 = errno
        let r6 = withUnsafePointer(to: &idx) { ptr -> Int32 in
            setsockopt(fd, /* IPPROTO_IPV6 */ 41, /* IPV6_BOUND_IF */ 125, ptr, size)
        }
        let errno6 = errno

        // Лог первых 5 вызовов + каждый 100й. Без сэмплинга Console зальётся, sing-box
        // зовёт это часто.
        // Phase 6e Wave 2 Theme C-1 (L15) — `.info` → `.debug`. Filterable через
        // `log stream --predicate 'category=="lifecycle"' --level=debug`.
        if callNum <= 5 || callNum % 100 == 0 {
            TunnelLogger.lifecycle.debug(
                "autoDetectControl #\(callNum) fd=\(fd) idx=\(index) → r4=\(r4)(errno=\(errno4)) r6=\(r6)(errno=\(errno6))"
            )
        }

        if r4 != 0 && r6 != 0 {
            TunnelLogger.lifecycle.error("autoDetectControl #\(callNum) fd=\(fd) FAILED — both r4=\(r4)(\(errno4)) and r6=\(r6)(\(errno6))")
            throw NSError(
                domain: "BBTB.autoDetectControl",
                code: Int(errno4),
                userInfo: [NSLocalizedDescriptionKey:
                    "setsockopt IP_BOUND_IF/IPV6_BOUND_IF failed for fd=\(fd) idx=\(index): errno4=\(errno4) errno6=\(errno6)"]
            )
        }
    }

    // MARK: Default interface monitor (NWPathMonitor)

    /// Запускает мониторинг сетевых изменений. libbox использует обновления
    /// чтобы реконнектить outbound при смене Wi-Fi / Cellular.
    public func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        TunnelLogger.lifecycle.info("startDefaultInterfaceMonitor called by libbox")
        guard let listener else { return }
        let monitor = NWPathMonitor()
        nwMonitor = monitor

        // libbox listener — это Go-managed объект, безопасный к вызовам из любого
        // thread'а; Swift 6 strict concurrency не знает этого, поэтому оборачиваем
        // в `UncheckedSendableBox` для передачи в `@Sendable` closures NWPathMonitor.
        let boxedListener = UncheckedSendableBox(listener)

        // Канонический pattern: первый pathUpdateHandler синхронно сигналит семафор,
        // чтобы libbox знал что интерфейсы уже считаны до возврата из метода.
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { [weak self] path in
            self?.notifyInterfaceUpdate(boxedListener.value, path: path)
            semaphore.signal()
            // Последующие обновления — без сигнала.
            monitor.pathUpdateHandler = { [weak self] path in
                self?.notifyInterfaceUpdate(boxedListener.value, path: path)
            }
        }
        monitor.start(queue: DispatchQueue.global())
        // **H9 (06D-03g):** Bounded wait — без timeout libbox.Start блокируется бесконечно,
        // если NWPathMonitor по какой-то причине не отдаёт первый callback (наблюдалось
        // редкими hang'ами на cold start). 2s достаточно: на iPhone 13+ initial pathUpdate
        // приходит за <100 ms; на таймауте просто продолжаем — libbox толерантно стартует
        // с пустым default interface, а autoDetectControl (M9) защищает от unbound сокетов
        // до прихода реального path-update.
        let waitResult = semaphore.wait(timeout: .now() + 2.0)
        if waitResult == .timedOut {
            TunnelLogger.lifecycle.warning("startDefaultInterfaceMonitor: initial NWPathMonitor callback timeout after 2s — proceeding with empty/default interface")
        }
    }

    private func notifyInterfaceUpdate(_ listener: LibboxInterfaceUpdateListenerProtocol, path: Network.NWPath) {
        // **CRITICAL FIX (W3.1 device test 2026-05-11)**: NWPathMonitor внутри VPN extension
        // видит НАШ собственный TUN (utun*) как один из availableInterfaces — обычно первым,
        // потому что мы только что его создали. Если отдать его sing-box как «default
        // interface», outbound VLESS traffic пойдёт через TUN → попадёт обратно в наш
        // inbound → infinite loop → handshake timeout. Фильтруем по NWInterface.Type
        // оставляя только physical interfaces (Wi-Fi / Cellular / wired Ethernet).
        let physical = path.availableInterfaces.first(where: Self.isPhysical)
        guard path.status != .unsatisfied, let defaultInterface = physical else {
            // Phase 6e Wave 2 Theme C-1 (L15) — `.notice` → `.debug`. NWPathMonitor
            // callbacks с empty-interface бывают during init / sleep — не critical
            // diagnostic для production users.
            TunnelLogger.lifecycle.debug("notifyInterfaceUpdate: no physical interface (status=\(String(describing: path.status))), reporting empty")
            currentInterfaceIndex = 0
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        // Cache index for autoDetectControl(fd:) — каждый sing-box outbound socket
        // привяжется к этому индексу через IP_BOUND_IF.
        currentInterfaceIndex = UInt32(defaultInterface.index)
        // **M9 (06D-03g):** first seed of physical interface — release any
        // `autoDetectControl` callers blocked on `physicalInterfaceReady`.
        if !physicalInterfaceSeeded {
            physicalInterfaceSeeded = true
            physicalInterfaceReady.signal()
        }
        TunnelLogger.lifecycle.info("notifyInterfaceUpdate: default interface=\(defaultInterface.name, privacy: .public) index=\(defaultInterface.index) type=\(String(describing: defaultInterface.type), privacy: .public)")
        listener.updateDefaultInterface(defaultInterface.name,
                                        interfaceIndex: Int32(defaultInterface.index),
                                        isExpensive: path.isExpensive,
                                        isConstrained: path.isConstrained)
    }

    /// Physical interfaces (suitable as default outbound). Excludes TUN (.other type)
    /// which would cause outbound→inbound loop.
    private static func isPhysical(_ iface: NWInterface) -> Bool {
        switch iface.type {
        case .wifi, .cellular, .wiredEthernet:
            return true
        default:
            return false
        }
    }

    public func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        nwMonitor?.cancel()
        nwMonitor = nil
    }

    /// Возвращает iterator по доступным сетевым интерфейсам.
    /// Phase 1: используем последний `currentPath` из NWPathMonitor (если стартовал).
    public func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        guard let nwMonitor else {
            return InterfaceIterator([])
        }
        let path = nwMonitor.currentPath
        if path.status == .unsatisfied {
            return InterfaceIterator([])
        }
        var interfaces: [LibboxNetworkInterface] = []
        for it in path.availableInterfaces where Self.isPhysical(it) {
            // Skip TUN (.other) for the same reason as notifyInterfaceUpdate —
            // sing-box must not see our own utun* as outbound-eligible.
            let iface = LibboxNetworkInterface()
            iface.name = it.name
            iface.index = Int32(it.index)
            switch it.type {
            case .wifi:           iface.type = LibboxInterfaceTypeWIFI
            case .cellular:       iface.type = LibboxInterfaceTypeCellular
            case .wiredEthernet:  iface.type = LibboxInterfaceTypeEthernet
            default:              iface.type = LibboxInterfaceTypeOther
            }
            interfaces.append(iface)
        }
        return InterfaceIterator(interfaces)
    }

    // MARK: Wi-Fi / connection owner / certificates — Phase 1 stubs

    /// Wi-Fi SSID/BSSID — нужен для правил роутинга по сетям. Phase 1: nil
    /// (правила wifi_ssid в роутах появятся в Phase 6+).
    public func readWIFIState() -> LibboxWIFIState? {
        nil
    }

    /// Process attribution (по 5-tuple → процесс) — Phase 8 фича. Phase 1 — throw.
    public func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32, destinationAddress: String?, destinationPort: Int32) throws -> LibboxConnectionOwner {
        throw NSError(domain: "BBTB.findConnectionOwner", code: 0,
                      userInfo: [NSLocalizedDescriptionKey: "Not implemented in Phase 1"])
    }

    /// Системные CA — nil означает «используй дефолтные системные доверенные центры».
    public func systemCertificates() -> LibboxStringIteratorProtocol? {
        nil
    }

    /// Local DNS transport (DoH/DoT внутри extension) — Phase 6 (NET-09).
    public func localDNSTransport() -> LibboxLocalDNSTransportProtocol? {
        nil
    }

    // MARK: Misc hooks

    /// Сбрасывает DNS-кэш ОС. Канонический трюк: переустановить tunnel settings.
    ///
    /// Phase 6e Wave 2 Theme B (L1) — каждый `semaphore.wait()` обёрнут в 2-секундный
    /// timeout (mirror Phase 6d M16 `5a4db9f` openTun pattern, lines 129+320). Без
    /// timeout — потенциальный deadlock libbox thread'а если `setTunnelNetworkSettings`
    /// completion никогда не fires (rare NE bug). На timeout — log warning, но не
    /// блокируем libbox; reasserting флаг всё равно сбрасываем, иначе UI зависает.
    public func clearDNSCache() {
        guard let provider, let networkSettings else { return }
        // Маркируем реконфигурацию, чтобы UI не считал это отключением.
        provider.reasserting = true
        let s1 = DispatchSemaphore(value: 0)
        provider.setTunnelNetworkSettings(nil) { _ in s1.signal() }
        let waitResult1 = s1.wait(timeout: .now() + 2.0)
        if waitResult1 == .timedOut {
            TunnelLogger.lifecycle.warning("clearDNSCache: setTunnelNetworkSettings(nil) timed out after 2s")
        }
        let s2 = DispatchSemaphore(value: 0)
        provider.setTunnelNetworkSettings(networkSettings) { _ in s2.signal() }
        let waitResult2 = s2.wait(timeout: .now() + 2.0)
        if waitResult2 == .timedOut {
            TunnelLogger.lifecycle.warning("clearDNSCache: setTunnelNetworkSettings(restore) timed out after 2s")
        }
        provider.reasserting = false
    }

    /// User notifications (например, deprecation warnings от sing-box).
    /// Phase 1 — лог-только, без UserNotifications. Swift-имя `send(_:)`
    /// получается из gomobile-стиля `sendNotification:error:` — bridge срезает
    /// первое существительное при наличии префикса `send`.
    public func send(_ notification: LibboxNotification?) throws {
        guard let notification else { return }
        TunnelLogger.libbox.info("libbox notification: \(notification.title, privacy: .public) — \(notification.body, privacy: .public)")
    }
}

// MARK: - LibboxCommandServerHandlerProtocol

extension ExtensionPlatformInterface: LibboxCommandServerHandlerProtocol {

    /// System proxy status — Phase 1 без system proxy (только TUN).
    public func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        // Пустой статус: available=false, enabled=false.
        return LibboxSystemProxyStatus()
    }

    /// Включение/выключение system HTTP proxy. Phase 1 — no-op (proxy не настраивается).
    public func setSystemProxyEnabled(_ isEnabled: Bool) throws {
        // no-op: Phase 1 не использует proxySettings.
    }

    /// service reload — sing-box хочет перечитать конфиг.
    /// Реальный re-apply делает `BaseSingBoxTunnel` через `commandServer.startOrReloadService`,
    /// поэтому здесь no-op + log: hook нужен для протокола, но Phase 1 не поддерживает
    /// hot-reload изнутри extension'а (он стартует с финальным configContent).
    public func serviceReload() throws {
        TunnelLogger.lifecycle.info("CommandServerHandler.serviceReload (no-op in Phase 1)")
    }

    /// Запрос на остановку сервиса из внутренних компонент sing-box.
    /// Фактическая остановка происходит в `BaseSingBoxTunnel.stopTunnel`.
    public func serviceStop() throws {
        TunnelLogger.lifecycle.info("CommandServerHandler.serviceStop requested (will be honoured by NEProvider stopTunnel)")
    }

    /// Сообщения от libbox/sing-box engine. Поднято до `notice`, чтобы быть видимыми
    /// в Console.app без включения Debug/Info. Phase 1 debugging — на проде вернуть `.debug`.
    public func writeDebugMessage(_ message: String?) {
        guard let message else { return }
        TunnelLogger.libbox.notice("\(message, privacy: .public)")
    }
}

// MARK: - Concurrency helpers

/// Бокс для безопасной передачи non-Sendable значений через `@Sendable` closures.
/// Используется только когда мы знаем, что underlying value реально потокобезопасно
/// (например, Go-managed объект libbox), но Swift 6 strict concurrency не может это доказать.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Reference holder для возврата ошибки из NEPacketTunnelProvider completion handler.
/// Используется в паре с DispatchSemaphore: запись из handler'а упорядочена `semaphore.signal()`,
/// чтение — после `semaphore.wait()`, поэтому race-conditions нет.
private final class NSMutablePointerHolder {
    var error: Error?
}

// MARK: - InterfaceIterator helper

/// Внутренний адаптер `[LibboxNetworkInterface]` → `LibboxNetworkInterfaceIteratorProtocol`.
/// Контракт `hasNext()` cache'ит следующее значение, чтобы `next()` мог вернуть его без побочных эффектов
/// (повторяет канонический pattern из sing-box-for-apple).
private final class InterfaceIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
    private var iterator: IndexingIterator<[LibboxNetworkInterface]>
    private var nextValue: LibboxNetworkInterface?

    init(_ items: [LibboxNetworkInterface]) {
        self.iterator = items.makeIterator()
        super.init()
    }

    func hasNext() -> Bool {
        nextValue = iterator.next()
        return nextValue != nil
    }

    func next() -> LibboxNetworkInterface? {
        nextValue
    }
}
