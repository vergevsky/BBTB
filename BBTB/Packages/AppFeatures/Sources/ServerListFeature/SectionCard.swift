import SwiftUI
import DesignSystem

/// SectionCard — Figma BBTB v3 section container pattern (2026-05-16 design pass).
///
/// Каждая секция ServerListSheet (Подписка / Конфигурации / AutoCell standalone)
/// обёрнута в RoundedRectangle(cornerRadius=24) с DS.Color.surfaceSunken fill.
/// Внутри: header (surfaceHeader bg) сверху + rows ниже с hairline strokes.
///
/// Используется через `@ViewBuilder` content slot чтобы caller мог свободно
/// композировать header + rows.
struct SectionCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(DS.Color.surfaceSunken)
        )
    }
}
