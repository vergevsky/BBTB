import Foundation
import Libbox

/// Swift-friendly wrapper around `LibboxSetup`.
/// Вызвать ОДИН раз при старте extension process (BaseSingBoxTunnel.startTunnel).
public enum LibboxBootstrap {
    public enum SetupError: Error, LocalizedError {
        case failure(NSError?)
        public var errorDescription: String? {
            switch self {
            case .failure(let err):
                return "LibboxSetup failed: \(err?.localizedDescription ?? "unknown")"
            }
        }
    }

    /// Инициализирует libbox с базовыми путями (все три обычно — App Group container path).
    /// Должен быть вызван до LibboxNewService / LibboxNewCommandServer.
    ///
    /// libbox v1.13.11 API использует `LibboxSetupOptions` object вместо позиционных
    /// аргументов. См. `Libbox.framework/Headers/Libbox.objc.h` для полной структуры.
    public static func setup(basePath: String, workingPath: String, tempPath: String) throws {
        let options = LibboxSetupOptions()
        options.basePath = basePath
        options.workingPath = workingPath
        options.tempPath = tempPath
        var err: NSError?
        let ok = LibboxSetup(options, &err)
        if !ok {
            throw SetupError.failure(err)
        }
    }
}
