// Phase 5 Wave 6 — All types (AnyParsedConfig, UnsupportedReason, ParsedVLESSTLS,
// ParsedShadowsocks, ParsedHysteria2, ImportedServer, ImportSource) relocated to
// VPNCore/Sources/VPNCore/ParsedConfigs.swift to eliminate cyclic dependency.
//
// ConfigParser re-exports them transitively via `import VPNCore`.
import VPNCore
