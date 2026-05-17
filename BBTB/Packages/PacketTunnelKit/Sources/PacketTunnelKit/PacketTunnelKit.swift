// T-C-D3 (closes A1'-3-013 LOW Plan 06): module placeholder removed.
//
// Was: `public enum PacketTunnelKit { public static let version = "0.1.0" }`
// — added в Wave 0 as compile-shim when modules были empty. Stale ("0.1.0"
// while shipping v1.0+), unused (no callers found via grep), dead code.
//
// Module-level types now live в:
// - `SingBox/BaseSingBoxTunnel.swift` (NEPacketTunnelProvider subclass)
// - `SingBox/SingBoxConfigLoader.swift` (R1 validate + W3 expand)
// - `SingBox/ExtensionPlatformInterface.swift` (libbox platform bridge)
// - `TunnelSettings.swift` (R6-safe NEPacketTunnelNetworkSettings)
// - `AppGroupContainer.swift` (group.app.bbtb.shared paths)
// - `ExternalVPNStopMarker.swift` (extension↔host disconnect signal)
//
// This file intentionally left near-empty as documentation-only marker.
