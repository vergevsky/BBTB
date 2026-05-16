import SwiftUI
import Localization
import DesignSystem

/// EmptyStateCard — pixel-perfect rebuild по Figma "2. Home Screen — Empty state"
/// (BBTB v3, node `3115:325`, 2026-05-16 design pass).
///
/// **Layout (per Figma):**
/// ```
/// VStack(spacing: 0) {
///   Spacer()                          // gap до hero
///   VStack(spacing: 16) {             // Frame 16 (3115:352)
///     Text("Нет конфигураций")        // 16pt Expanded Semibold, textPrimary
///     Text("Добавьте конфигурацию…")  // 10pt Expanded Light, textPrimary
///   }
///   .padding(.vertical, 32)
///   VStack(spacing: DS.Spacing.md) {  // CTAs (3115:346 + 3115:348)
///     PrimaryButton  → onAddFromClipboard
///     SecondaryButton → onScanQR
///   }
///   Spacer()                          // gap до footer
///   Text("Сервер: Авто")              // 12pt Expanded Semibold, textPrimary
///     .padding(.bottom, lg)
/// }
/// .padding(.horizontal, 28)
/// ```
///
/// **Figma elements intentionally omitted в Swift:**
/// - TopBar (3115:327, List + Plus иконки) — рендерится через native `.toolbar`
///   в `MainScreenView` (Apple HIG canonical; визуально совпадает с Figma TopBar
///   на iPhone 17). В native toolbar используются `Ph.list.bold` / `Ph.plus.bold`
///   из Phosphor пакета.
/// - App logo (mascot, 3115:330) — `visible: false` в Figma, asset недоступен.
/// - ConnectionButton (3115:334) — `visible: false` в Figma (empty state не
///   показывает кнопку соединения, пока нет конфигов).
///
/// **CTAs:** переиспользуют `PrimaryButtonStyle` / `SecondaryButtonStyle` из
/// DesignSystem (DS-10) — тот же контракт что в OnboardingView (RoundedRectangle
/// cornerRadius 32, accent fill / textPrimary fill, sensoryFeedback haptic).
public struct EmptyStateCard: View {
    public let onAddFromClipboard: () -> Void
    public let onScanQR: () -> Void

    /// UI-SPEC §2.1 Pitfall 6 — local tap counters для sensoryFeedback (НЕ ConnectionState).
    @State private var pasteTapCounter: Int = 0
    @State private var qrTapCounter: Int = 0

    public init(onAddFromClipboard: @escaping () -> Void, onScanQR: @escaping () -> Void) {
        self.onAddFromClipboard = onAddFromClipboard
        self.onScanQR = onScanQR
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero block — Figma Frame 16 (3115:352): vstack spacing 16, padding-vertical 32.
            VStack(spacing: 16) {
                Text(L10n.emptyTitle)
                    .font(DS.Typography.expanded(16, weight: .semibold))
                    .foregroundStyle(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text(L10n.emptySubtitle)
                    .font(DS.Typography.tipsLight)  // 10pt Expanded Light (DS preset)
                    .foregroundStyle(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    // frame 200 wide → wraps в 2 строки как в Figma (155pt frame, но
                    // SF Pro Expanded Light шире SF Pro Light, давая чуть больший wrap point).
                    .frame(maxWidth: 220)
            }
            .padding(.vertical, 32)

            // CTAs — Figma OnboardingActions (3115:344) с PrimaryButton + SecondaryButton.
            VStack(spacing: DS.Spacing.md) {
                Button(L10n.onboardingPaste) {
                    pasteTapCounter += 1
                    onAddFromClipboard()
                }
                .buttonStyle(PrimaryButtonStyle())
                .sensoryFeedback(.impact(weight: .light), trigger: pasteTapCounter)
                .accessibilityIdentifier("BBTB.Empty.PasteButton")
                .accessibilityLabel(Text(L10n.onboardingPaste))

                Button(L10n.onboardingScanQR) {
                    qrTapCounter += 1
                    onScanQR()
                }
                .buttonStyle(SecondaryButtonStyle())
                .sensoryFeedback(.impact(weight: .light), trigger: qrTapCounter)
                .accessibilityIdentifier("BBTB.Empty.QRButton")
                .accessibilityLabel(Text(L10n.onboardingScanQR))
            }

            Spacer()

            // ServerStatusLabel — Figma 3115:335: статичный "Сервер: Авто" footer,
            // 12pt Expanded Semibold. Empty state коммуницирует default Auto-mode,
            // который будет применён после импорта первого конфига.
            Text(L10n.homeEmptyServerLine)
                .font(DS.Typography.expanded(12, weight: .semibold))
                .foregroundStyle(DS.Color.textPrimary)
                .padding(.bottom, DS.Spacing.lg)
        }
        .padding(.horizontal, 28)  // Figma ScreenContent padding-horizontal 28pt.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
