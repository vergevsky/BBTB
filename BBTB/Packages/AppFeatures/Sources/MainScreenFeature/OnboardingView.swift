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
/// **TopBar (2026-05-16 user feedback applied):**
/// - **Skip (X)** button в top-right — Figma node `3062:342`. SF Symbol
///   `xmark`, тап вызывает `onDismiss()` (= `hasShownOnboarding = true`
///   sticky-forever per D-01). Доступен accessibility label `onboarding.skip`.
/// - **Bug-mascot logo** (Figma node `3062:310`) центральный — intentionally
///   omitted in Swift: branded logo asset не входит в Plan 12-02 scope, SF
///   Symbol эквивалента нет. Backlog Phase 13+ (TestFlight visual polish).
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
        // заменён на: TopBar (Skip X) + hero text split LEFT-aligned +
        // tip text «Добавьте конфигурацию» + PrimaryButtonStyle/SecondaryButtonStyle.
        // CRITICAL preserve (D-01/D-02/D-03 Phase 11): identifiers + onChange
        // dismiss + 2-CTA contract.
        //
        // 2026-05-16 user UI/UX feedback applied:
        // 1. Hero text LEFT-aligned (Figma `final-01-onboarding.png`)
        // 2. Removed subtitle «Один тап...» (не нужен per Figma)
        // 3. Added tip «Добавьте конфигурацию» (L10n.onboardingHint) above CTAs
        // 4. Buttons height = 49pt (Figma 3062:345 frame)
        // 5. Added Skip X button (top-right, Figma 3062:342)
        VStack(spacing: 0) {
            // TopBar — только Skip (X) per user requirement. Mascot logo (Figma
            // node 3062:310) intentionally омитен в Swift — branded asset не в scope.
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DS.Color.iconPrimary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("BBTB.Onboarding.SkipButton")
                .accessibilityLabel(Text(L10n.onboardingSkip))
            }
            .padding(.horizontal, 28)
            .padding(.top, DS.Spacing.lg)
            .frame(height: 56)  // Figma TopBar 3062:307 height

            Spacer()

            // Hero text split per Figma reference (Tab 12-03 snippet) — LEFT-aligned,
            // 40pt SF Pro Expanded Semibold. Hero stays semantic textPrimary
            // (inverts с canvas в Light) — Apple HIG: avoid `.white` literal
            // которая ломает Light mode.
            (Text("Интернет, каким он ")
                .foregroundStyle(DS.Color.textPrimary)
             + Text("должен быть")
                .foregroundStyle(DS.Color.accent))
                .font(DS.Typography.expanded(40, weight: .semibold))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)

            Spacer()

            // Tip text + Две CTA — D-02 strict: ровно 2 кнопки, никакого file picker'а.
            // Phase 12 / DS-10 — PrimaryButtonStyle (accent pill) + SecondaryButtonStyle
            // (white pill, инвертированный в Light — wire-only artifact D-05).
            //
            // 2026-05-16 user feedback — gap между tip text и buttons = ~28pt
            // (per Figma reference snippet). Tip и buttons разделены в outer VStack
            // (spacing=28), buttons в nested VStack (spacing=DS.Spacing.md=12pt
            // между собой).
            VStack(spacing: 28) {
                // Figma node 3062:316 — hint text над CTAs. «Tips» style = SF Pro
                // Expanded Light 10pt per Figma typography spec.
                Text(L10n.onboardingHint)
                    .font(DS.Typography.tipsLight)
                    .foregroundStyle(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

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
            }
            .padding(.horizontal, 28)
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
