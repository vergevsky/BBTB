// ServerRow.figma.swift
//
// Figma Code Connect mapping — two related Figma components → `ServerRow` SwiftUI view.
//
// **Status (2026-05):** Documentation contract. Not published (Education plan ограничение —
// см. `BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md` §5 «Real Code Connect SDK setup»).
//
// **Figma sources:**
//   - `ServerRow` (default state, 3071:219)
//     URL: https://www.figma.com/design/tI6DFQDU6PdOSmd19BGXqg/BBTB-v3?node-id=3071-219
//   - `ServerRow Selected` (accent state, 3071:227)
//     URL: https://www.figma.com/design/tI6DFQDU6PdOSmd19BGXqg/BBTB-v3?node-id=3071-227
//
// **Visual diff (default → selected, see CODE-CONNECT.md §1.5):**
//   - row fill: transparent → #14664B (DS.Color.accent)
//   - globe/caret icons: #808080 → #CCCCCC (DS.Color.iconMuted)
//   - latency text color: #808080 → #CCCCCC
//
// **Pixel-perfect spec:**
//   - row height: 52pt
//   - padding all sides: 16pt (DS.Spacing.lg)
//   - leading globe icon: 20×20pt, Phosphor `GlobeHemisphereWest`
//   - trailing caret-right: 18×18pt
//   - server name font: SF Pro Expanded Regular 12 (Typography/Body/Default)
//   - latency font: SF Pro Expanded Regular 9 (Typography/Body/Caption)

#if canImport(CodeConnect)
import CodeConnect
import SwiftUI
import VPNCore

// MARK: - Default state (3071:219)

struct ServerRow_doc: FigmaConnect {
    let component = ServerRow.self
    let figmaNodeUrl = "https://www.figma.com/design/tI6DFQDU6PdOSmd19BGXqg/BBTB-v3?node-id=3071-219"

    var body: some View {
        ServerRow(
            server: ServerConfig(
                name: "WL Латвия",
                host: "example.com",
                port: 443,
                protocolID: "vless",
                keychainTag: nil,
                countryCode: "LV"
            ),
            isSelected: false,
            pingState: .idle,
            onTap: {},
            onDelete: {},
            onDetailTap: {}
        )
    }
}

// MARK: - Selected state (3071:227)

struct ServerRowSelected_doc: FigmaConnect {
    let component = ServerRow.self
    let figmaNodeUrl = "https://www.figma.com/design/tI6DFQDU6PdOSmd19BGXqg/BBTB-v3?node-id=3071-227"

    var body: some View {
        ServerRow(
            server: ServerConfig(
                name: "WL Финляндия",
                host: "example.com",
                port: 443,
                protocolID: "vless",
                keychainTag: nil,
                countryCode: "FI"
            ),
            isSelected: true,
            pingState: .idle,
            onTap: {},
            onDelete: {},
            onDetailTap: {}
        )
    }
}
#endif
