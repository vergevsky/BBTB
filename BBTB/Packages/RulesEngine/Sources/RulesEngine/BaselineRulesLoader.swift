import Foundation

/// Loader для baseline (embedded) rules manifest + SRS files.
///
/// **Use:** Вызывается из `RulesEngineCoordinator.bootstrap()` на first-launch для
/// копирования signed baseline в App Group cache. Baseline шиппится внутри binary
/// (Bundle.module) → integrity guaranteed by Apple code signing (D-05).
///
/// **Pattern:** mirror `SingBoxConfigLoader.loadVLESSRealityTemplate()` (lines 246-256
/// в PacketTunnelKit) — `Bundle.module.url(forResource:withExtension:)` + `throws` if
/// missing.
///
/// **Failure semantics:** missing resource = build bug (file not bundled). `LoadError
/// .resourceMissing` сообщает имя файла. Coordinator должен treat это как fatal
/// (нет fallback — без baseline first-launch broken).
public enum BaselineRulesLoader {

    /// Loading failure.
    public enum LoadError: Error, LocalizedError {
        /// Bundle.module не нашёл resource — bundle bug либо missing file declaration в
        /// Package.swift `resources: [.process("Resources")]`.
        case resourceMissing(String)
        public var errorDescription: String? {
            switch self {
            case .resourceMissing(let name):
                return "Baseline resource not found in Bundle.module: \(name)"
            }
        }
    }

    /// Load `baseline-rules-manifest.json` + `.sig` (zero-bytes placeholder в W2; real
    /// signature после W6).
    ///
    /// - Returns: tuple (manifest JSON bytes, signature bytes).
    /// - Throws: `LoadError.resourceMissing` если bundle malformed.
    public static func loadManifest() throws -> (manifest: Data, signature: Data) {
        let manifestData = try loadResource(name: "baseline-rules-manifest", ext: "json")
        // CodingKey trick: `Bundle.module.url(forResource: "baseline-rules-manifest.json",
        // withExtension: "sig")` resolves "baseline-rules-manifest.json.sig" correctly.
        let sigData = try loadResource(name: "baseline-rules-manifest.json", ext: "sig")
        return (manifestData, sigData)
    }

    /// Load one baseline `.srs` file + its `.sig` для given category.
    ///
    /// - Parameter category: `.block` / `.never` / `.always` — maps to filename basename
    ///   `bbtb-baseline-block` / `-never` / `-always` (sync с manifest's `files[].name`).
    /// - Returns: tuple (`.srs` bytes, signature bytes).
    /// - Throws: `LoadError.resourceMissing` если bundle malformed.
    public static func loadSRS(category: RulesManifest.Category) throws
        -> (srs: Data, signature: Data) {

        let basename: String
        switch category {
        case .block: basename = "bbtb-baseline-block"
        case .never: basename = "bbtb-baseline-never"
        case .always: basename = "bbtb-baseline-always"
        }
        let srsData = try loadResource(name: basename, ext: "srs")
        let sigData = try loadResource(name: "\(basename).srs", ext: "sig")
        return (srsData, sigData)
    }

    /// Resolved filename → bare bytes. Throws on missing.
    private static func loadResource(name: String, ext: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw LoadError.resourceMissing("\(name).\(ext)")
        }
        return try Data(contentsOf: url)
    }
}
