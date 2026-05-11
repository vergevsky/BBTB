import Foundation

public enum ConnectionState: Equatable {
    case empty                          // нет сохранённого конфига
    case idle                           // есть конфиг, не подключено
    case connecting
    case connected(since: Date)
    case error(message: String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    public var connectionStart: Date? {
        if case .connected(let since) = self { return since }
        return nil
    }
}
