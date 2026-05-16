import SwiftUI
import Localization
import DesignSystem

/// Phase 11 / UX-01 — Onboarding-экран первого запуска.
///
/// CONTEXT.md decisions (Phase 11):
/// - D-01 — sticky-forever флаг `app.bbtb.hasShownOnboarding` (set'ится один раз,
///   живёт пока приложение установлено; даже после удаления всех серверов
///   Onboarding не показывается).
/// - D-02 — один экран, две CTA («Вставить из буфера» primary + «Сканировать QR»
///   secondary). Никаких слайдов, никакого «что такое VPN».
/// - D-03 — auto-dismiss после успешного импорта (state в ViewModel перешёл
///   из `.empty` в любое другое non-error состояние → `onDismiss` вызывается
///   автоматически через `.onChange(of: viewModel.state)`).
/// - D-04 — file picker (IMP-03) здесь НЕ показан, только в меню «+» главного
///   экрана.
///
/// Phase 12 / Plan 12-02 / Task 7 / DS-11 / M7 — Figma pixel-perfect rebuild:
/// hero text split (textPrimary white "Интернет, каким он " + accent green
/// "должен быть") с DS.Typography.expanded(.display=48, .semibold) — B2 lock
/// (48pt SF Pro Expanded Semibold per RESEARCH §12 Q1 RESOLVED); 2 CTA
/// PrimaryButtonStyle (accent pill) + SecondaryButtonStyle (white pill);
/// sensoryFeedback haptic с отдельными tapCounter'ами (UI-SPEC §2.1 Pitfall 6
/// — local @State counters, НЕ ConnectionState).
///
/// CRITICAL preserve (D-01/D-02/D-03 Phase 11):
/// - identifiers `BBTB.Onboarding.PasteButton` / `BBTB.Onboarding.QRButton`
///   (Phase 11 UI test references).
/// - `.onChange(of: viewModel.state)` + `dismissIfImported(_:)` auto-dismiss logic.
/// - Ровно 2 CTA — никакого file picker'а.
///
/// **Иконка top:** Figma `final-01-onboarding.png` показывает branded bug-mascot
/// logo (не SF Symbol). Branded logo asset не входит в Plan 12-02 scope, и SF
/// Symbol `shield.lefthalf.filled` визуально несоответствен Figma. Решение
/// executor: top icon удалить, использовать Spacer'ы. Branded logo добавится
/// в backlog Phase 13+ (TestFlight visual polish).
public struct OnboardingView: View {
    /// ObservedObject — нужен для наблюдения `state` изменений (auto-dismiss
    /// после успешного импорта; см. `.onChange(of: viewModel.state)`).
    @ObservedObject public var viewModel: MainScreenViewModel

    /// Closure для primary CTA — «Вставить из буфера». Owner делает
    /// `viewModel.importFromPasteboard()`.
    public let onPaste: () -> Void

    /// Closure для secondary CTA — «Сканировать QR». Owner показывает
    /// `QRScannerView` через `showQRScanner = true` в MainScreenView.
    public let onScanQR: () -> Void

    /// Closure dismiss-after-import. Owner ставит `hasShownOnboarding = true`,
    /// что закрывает `fullScreenCover` через `isPresented` binding.
    public let onDismiss: () -> Void

    /// Phase 12 / Task 7 — UI-SPEC §2.1 Pitfall 6: local tap counters как
    /// trigger для haptic-modifier на CTA-кнопках. НЕ читаем ConnectionState
    /// (этот approach создавал bug, когда haptic срабатывал на state
    /// transitions, не на tap'ах). Counter инкрементируется в action.
    @State private var pasteTapCounter: Int = 0
    @State private var qrTapCounter: Int = 0

    public init(
        viewModel: MainScreenViewModel,
        onPaste: @escaping () -> Void,
        onScanQR: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onPaste = onPaste
        self.onScanQR = onScanQR
        self.onDismiss = onDismiss
    }

    public var body: some View {
        // Phase 12 / DS-11 / M7 — Figma rebuild applied. Phase 11 placeholder
        // (shield.lefthalf.filled + title + .borderedProminent/.bordered)
        // заменён на: hero text split + PrimaryButtonStyle/SecondaryButtonStyle
        // + sensoryFeedback. CRITICAL preserve (D-01/D-02/D-03 Phase 11):
        // identifiers + onChange dismiss + 2-CTA contract.
        VStack(spacing: DS.Spacing.xxl) {
            Spacer()

            // Hero text split per RESEARCH §4.7 + CONTEXT.md <specifics>.
            // B2 lock: 48pt SF Pro Expanded Semibold per RESEARCH §12 Q1 RESOLVED.
            VStack(spacing: DS.Spacing.md) {
                (Text("Интернет, каким он ")
                    .foregroundStyle(DS.Color.textPrimary)
                 + Text("должен быть")
                    .foregroundStyle(DS.Color.accent))
                    .font(DS.Typography.expanded(DS.Typography.Size.display, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(L10n.onboardingSubtitle)
                    .font(DS.Typography.bodyDefault)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DS.Spacing.xl)

            Spacer()

            // Две CTA — D-02 strict: ровно 2 кнопки, никакого file picker'а.
            // Phase 12 / DS-10 — PrimaryButtonStyle (accent pill) + SecondaryButtonStyle
            // (white pill, инвертированный в Light — wire-only artifact D-05, см.
            // ButtonStyles.swift).
            VStack(spacing: DS.Spacing.md) {
                Button(L10n.onboardingPaste) {
                    pasteTapCounter += 1
                    onPaste()
                }
                .buttonStyle(PrimaryButtonStyle())
                .sensoryFeedback(.impact(weight: .light), trigger: pasteTapCounter)
                .accessibilityIdentifier("BBTB.Onboarding.PasteButton")
                .accessibilityLabel(Text(L10n.onboardingPaste))

                Button(L10n.onboardingScanQR) {
                    qrTapCounter += 1
                    onScanQR()
                }
                .buttonStyle(SecondaryButtonStyle())
                .sensoryFeedback(.impact(weight: .light), trigger: qrTapCounter)
                .accessibilityIdentifier("BBTB.Onboarding.QRButton")
                .accessibilityLabel(Text(L10n.onboardingScanQR))
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.canvas)
        #if os(macOS)
        // Pattern S8 — на macOS `fullScreenCover` ведёт себя как `.sheet`,
        // даём min-size чтобы окно не открывалось ужатым.
        .frame(minWidth: 480, minHeight: 640)
        #endif
        // D-03 — наблюдаем `state` изменения. Как только импорт состоялся
        // (state ≠ .empty AND ≠ .error), Onboarding закрывается автоматически.
        .onChange(of: viewModel.state) { _, newState in
            dismissIfImported(newState)
        }
    }

    /// D-03 — Onboarding закрывается только когда импорт реально проявил
    /// серверы (state поменялась с `.empty` на любое другое non-error).
    /// `.error` не закрывает — user должен иметь возможность повторить.
    private func dismissIfImported(_ state: ConnectionState) {
        switch state {
        case .empty, .error:
            return
        case .idle, .connecting, .connected:
            onDismiss()
        }
    }
}
