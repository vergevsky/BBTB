// ConnectionButton.figma.swift
//
// Figma Code Connect mapping — `Button` component set → `ConnectionButton` SwiftUI view.
//
// **Status (2026-05):** Documentation contract. Cannot publish to Figma — `code_connect:write`
// scope unavailable on Education plan (requires Organization+ subscription, ≈$45/user/mo).
// When/if upgraded:
//   1. Add Swift package `https://github.com/figma/code-connect` (1.0+) to AppFeatures target
//   2. Run `figma connect publish` from repo root
//
// **Figma source:** BBTB v3 / Components page / `Button` component set
// URL: https://www.figma.com/design/tI6DFQDU6PdOSmd19BGXqg/BBTB-v3?node-id=3054-712
//
// **Variant mapping (Figma `Property 1` → Swift `ConnectionState`):**
//   - "disconnected" (3054:711) → .idle    [Figma collapses .empty + .idle into one visual]
//   - "connecting"   (3054:713) → .connecting
//   - "error"        (3054:733) → .error(message: "")
//   - "connected"    (3054:736) → .connected(since: Date())
//
// **Known Swift↔Figma mismatches** (see BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md §4):
//   - M1: button diameter 140 (Swift) vs 280 (Figma)
//   - M2: icon size 56 (Swift) vs 112 (Figma)
//   - M3: fill colors use system Color.* — should bind DS.Color.controlIdle/.accent/.error
//   - M4: font family .system rounded — should be SF Pro Expanded

#if canImport(CodeConnect)
import CodeConnect
import SwiftUI

struct ConnectionButton_doc: FigmaConnect {
    let component = ConnectionButton.self
    let figmaNodeUrl = "https://www.figma.com/design/tI6DFQDU6PdOSmd19BGXqg/BBTB-v3?node-id=3054-712"

    @FigmaEnum("Property 1", mapping: [
        "disconnected": ConnectionState.idle,
        "connecting":   ConnectionState.connecting,
        "error":        ConnectionState.error(message: ""),
        "connected":    ConnectionState.connected(since: Date())
    ])
    var state: ConnectionState

    var body: some View {
        ConnectionButton(state: state, action: {})
    }
}
#endif
