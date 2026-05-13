// PerfSignposter.swift — Phase 6d Wave 02a Commit 2.
//
// Sibling enum к TunnelLogger pattern (PacketTunnelKit/TunnelLogger.swift).
// Используется для Instruments OSSignposter spans:
//
//   • ColdLaunch         — BBTB_iOSApp.init → BBTBRootView.onAppear
//                          BBTB_macOSApp.init → BBTBMacOSRootView.onAppear
//   • ConnectTap         — TunnelController.connect() (outer span)
//   • ProvisionProfile   — TunnelController.applyCurrentStateToCachedManager()
//   • LibboxStart        — BaseSingBoxTunnel.startTunnel → startOrReloadService
//
// Span names — PascalCase, fixed (см. 06D-RESEARCH.md Pattern 1). Subsystem
// matches existing Loggers; category `performance` is new (sibling к
// "lifecycle"/"libbox"/"diag"). iOS 15+ OSSignposter API.
//
// Wave 06D-02c наполнит baseline numerical tables с этих spans (Instruments
// → Points of Interest → category=performance).

import Foundation
import os.signpost

public enum PerfSignposter {

    /// iOS host app subsystem (matches BBTB_iOSApp.swift line ~30 `app.bbtb.client.ios`).
    public static let app = OSSignposter(
        subsystem: "app.bbtb.client.ios",
        category: "performance"
    )

    /// macOS host app subsystem.
    public static let appMac = OSSignposter(
        subsystem: "app.bbtb.client.macos",
        category: "performance"
    )

    /// Packet Tunnel Extension subsystem (matches TunnelLogger
    /// `app.bbtb.tunnel`). Used for `LibboxStart` from BaseSingBoxTunnel.
    public static let tunnel = OSSignposter(
        subsystem: "app.bbtb.tunnel",
        category: "performance"
    )

    /// Shared client-side subsystem (TunnelController.swift line ~69
    /// `app.bbtb.client`). Used for `ConnectTap`, `ProvisionProfile`.
    public static let client = OSSignposter(
        subsystem: "app.bbtb.client",
        category: "performance"
    )
}
