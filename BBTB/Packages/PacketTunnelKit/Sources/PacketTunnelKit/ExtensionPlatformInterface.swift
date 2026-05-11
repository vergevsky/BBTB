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

    public init(provider: NEPacketTunnelProvider, serverAddressHint: String) {
        self.provider = provider
        self.serverAddressHint = serverAddressHint
        super.init()
    }

    /// Сбрасывает кэши при остановке туннеля. Зовётся из `BaseSingBoxTunnel.stopTunnel`.
    func reset() {
        networkSettings = nil
        nwMonitor?.cancel()
        nwMonitor = nil
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
        provider.setTunnelNetworkSettings(settings) { err in
            errorBox.value.error = err
            semaphore.signal()
        }
        semaphore.wait()
        if let settingsError = errorBox.value.error {
            TunnelLogger.lifecycle.error("setTunnelNetworkSettings failed: \(String(describing: settingsError))")
            throw settingsError
        }
        self.networkSettings = settings

        // **R6 self-check (DEBUG only):** утверждаем, что utun не получил IFF_POINTOPOINT.
        // В Release — no-op.
        InterfaceFlagsInspector.assertNoPointToPointOnUtun()

        // FD extraction — приватный KVC путь (Pitfall 6 из RESEARCH).
        // Все sing-box / xray-based клиенты так делают; альтернативы нет.
        // Fallback на `LibboxGetTunnelFileDescriptor()` — как в canonical sing-box-for-apple.
        if let tunFd = provider.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = tunFd
            TunnelLogger.lifecycle.notice("TUN opened via KVC, fd=\(tunFd)")
            return
        }

        let fallbackFd = LibboxGetTunnelFileDescriptor()
        if fallbackFd != -1 {
            ret0_.pointee = fallbackFd
            TunnelLogger.lifecycle.notice("TUN opened via LibboxGetTunnelFileDescriptor, fd=\(fallbackFd)")
            return
        }

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
    public func usePlatformAutoDetectControl() -> Bool {
        false
    }

    /// Auto-detect control hook — управление маршрутом по конкретному FD.
    /// Phase 1: no-op, маршруты управляются NetworkExtension автоматически.
    public func autoDetectControl(_ fd: Int32) throws {
        // no-op: managed by NetworkExtension framework
    }

    // MARK: Default interface monitor (NWPathMonitor)

    /// Запускает мониторинг сетевых изменений. libbox использует обновления
    /// чтобы реконнектить outbound при смене Wi-Fi / Cellular.
    public func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
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
        semaphore.wait()
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
            TunnelLogger.lifecycle.notice("notifyInterfaceUpdate: no physical interface (status=\(String(describing: path.status))), reporting empty")
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
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
    public func clearDNSCache() {
        guard let provider, let networkSettings else { return }
        // Маркируем реконфигурацию, чтобы UI не считал это отключением.
        provider.reasserting = true
        let s1 = DispatchSemaphore(value: 0)
        provider.setTunnelNetworkSettings(nil) { _ in s1.signal() }
        s1.wait()
        let s2 = DispatchSemaphore(value: 0)
        provider.setTunnelNetworkSettings(networkSettings) { _ in s2.signal() }
        s2.wait()
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
