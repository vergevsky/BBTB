import ProjectDescription

// MARK: Workspace — BBTB
//
// Tuist 4.x workspace описание. Включает основной BBTB.xcodeproj.
// SocksProbe генерируется отдельно (Tools/SocksProbe/Project.swift),
// поэтому здесь его нет — он стоит изолированно, чтобы исключить
// shared resources (R1 invariant: SocksProbe без App Group / Keychain).

let workspace = Workspace(
    name: "BBTB",
    projects: ["."]
)
