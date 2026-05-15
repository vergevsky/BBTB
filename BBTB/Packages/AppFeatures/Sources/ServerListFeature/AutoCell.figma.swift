// AutoCell.figma.swift
//
// Figma Code Connect mapping — `Авто` pill frame → `AutoCell` SwiftUI view.
//
// **Status (2026-05):** Documentation contract. Not published (Education plan).
//
// **Figma source:** `Авто` frame inside ServersSheet
// URL: https://www.figma.com/design/tI6DFQDU6PdOSmd19BGXqg/BBTB-v3?node-id=3064-1316
//
// **Variants in Figma:**
//   - Selected (accent green pill, white text + lightning icon) — primary visual in design
//   - Unselected (TBD — Figma не имеет отдельного варианта; Swift отображает через `Color.secondary.opacity(0.12)`)
//
// **Pixel-perfect spec:**
//   - corner radius: 24pt (DS.Radius.section)
//   - background fill (selected): #14664B (DS.Color.accent)
//   - lightning icon: 20×20pt, white
//   - label font: SF Pro Expanded Semibold 12 (Typography/Title/Section)
//
// **Known mismatches (CODE-CONNECT.md M3, M4, M7):**
//   - Swift использует `Color.accentColor` — should be DS.Color.accent
//   - Swift иконка 28pt — should be 20pt
//   - background corner radius DS.Radius.cardLarge=16 — should be DS.Radius.section=24

#if canImport(CodeConnect)
import CodeConnect
import SwiftUI

struct AutoCell_doc: FigmaConnect {
    let component = AutoCell.self
    let figmaNodeUrl = "https://www.figma.com/design/tI6DFQDU6PdOSmd19BGXqg/BBTB-v3?node-id=3064-1316"

    var body: some View {
        AutoCell(isSelected: true, onTap: {})
    }
}
#endif
