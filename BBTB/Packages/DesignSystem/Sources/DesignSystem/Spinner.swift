// Spinner.swift — Phase 12 / Plan 12-02 / Task 6 / DS-08 / DS-09 / M6.
//
// BBTBSpinner: rotating ring placeholder для ConnectionButton .connecting state.
// Заменяет ProgressView() из Phase 11 UX-08 D-05. Figma component Spinner
// (3057:167) — 4-frame ring with grayscale AngularGradient stroke.
//
// См. RESEARCH §2.1 (Option B: Circle.trim + AngularGradient + rotationEffect),
// UI-SPEC §2.2 (motion contract — linear 1.2s repeatForever; Reduce-Motion
// fallback = pulsating opacity 0.6↔1.0 cycle 1.0s — W4 lock final),
// UI-SPEC §3.2 (decorative, accessibilityHidden — статус озвучивается parent
// ConnectionButton'ом).
//
// Battery guard (UI-SPEC §2.2 + RESEARCH §9 Pitfall 3): BBTBSpinner монтируется
// условно `if isConnecting { BBTBSpinner(...) }` в ConnectionButton overlay —
// при `.connected/.error/.idle` view удаляется, withAnimation auto-stops.

import SwiftUI

/// Phase 12 / DS-08 / M6 — rotating ring spinner для ConnectionButton .connecting state.
///
/// Default motion: `Circle.trim(0..<0.85)` + `AngularGradient` stroke (iconPrimary →
/// iconMuted → iconSecondary → clear gap) + `.rotationEffect(.degrees(angle))` с
/// `withAnimation(.linear(duration: speed).repeatForever(autoreverses: false))`
/// от 0° до 360°.
///
/// Reduce-Motion fallback (UI-SPEC §3.8 — W4 lock): при
/// `accessibilityReduceMotion = true` rotationEffect остаётся 0° (никакого
/// withAnimation rotation), вместо этого pulsating `.opacity` 0.6↔1.0 cycle
/// 1.0s (`.easeInOut(duration: 1.0).repeatForever(autoreverses: true)`).
/// **NO discrete-snap альтернатива** (revision iteration 1 final decision —
/// rationale: проще audit, 100% predictable, нет flickering от snap frames).
///
/// Battery guard (RESEARCH §9 Pitfall 3): mount conditionally в parent (см.
/// ConnectionButton .overlay на Circle когда isConnecting). При removal view'а
/// withAnimation отменяется автоматически — CPU usage ≤ 1% когда mounted, 0%
/// когда unmounted.
///
/// Accessibility (UI-SPEC §3.2): ring decorative; статус озвучивается parent
/// кнопкой → `accessibilityHidden(true)` обязателен.
public struct BBTBSpinner: View {

    public let diameter: CGFloat
    public let lineWidth: CGFloat
    public let speed: Double

    @State private var angle: Double = 0
    /// Pulsating opacity для Reduce-Motion fallback (W4 lock — UI-SPEC §3.8).
    @State private var pulseOpacity: Double = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    public init(diameter: CGFloat = 280, lineWidth: CGFloat = 6, speed: Double = 1.2) {
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.speed = speed
    }

    public var body: some View {
        Circle()
            .trim(from: 0, to: 0.85)  // ~310° arc → matches Figma 4-frame shape
            .stroke(
                AngularGradient(
                    colors: [
                        DS.Color.iconPrimary,   // #FFFFFF top
                        DS.Color.iconMuted,     // #CCCCCC
                        DS.Color.iconSecondary, // #808080 bottom
                        SwiftUI.Color.clear     // gap (the 15% arc)
                    ],
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(reduceMotion ? 0 : angle))
            .opacity(reduceMotion ? pulseOpacity : 1.0)
            .onAppear {
                if reduceMotion {
                    // W4 — pulsating opacity 0.6↔1.0 cycle 1.0s (UI-SPEC §3.8).
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        pulseOpacity = 0.6
                    }
                } else {
                    // Default — linear 1.2s rotation repeatForever (RESEARCH §2.1).
                    withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) {
                        angle = 360
                    }
                }
            }
            .accessibilityHidden(true)
    }
}
