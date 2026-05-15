import SwiftUI
import Localization
import DesignSystem

/// Phase 11 / UX-01 — Onboarding-экран первого запуска.
///
/// CONTEXT.md decisions:
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
/// Структурно — почти 1-в-1 `EmptyStateCard` (Pattern Map → exact analog),
/// но без card-background и фиксированной ширины: занимает весь экран
/// (`fullScreenCover` на iOS, `.sheet` на macOS).
///
/// Pixel-perfect стилизация (точные SF Symbols, шрифт title, отступы)
/// уточняется в Wave 4 visual review по `11-FIGMA-SPEC.md`. Здесь — DS tokens
/// (`DS.Spacing`, `DS.Typography`, `DS.Radius`), без захардкоженных pt.
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
        VStack(spacing: DS.Spacing.xxl) {
            Spacer()

            // Иконка — placeholder pending Figma (Wave 4 visual review).
            // `shield.lefthalf.filled` — нейтральный security-VPN symbol.
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: DS.Spacing.md) {
                Text(L10n.onboardingTitle)
                    .font(DS.Typography.title)
                    .multilineTextAlignment(.center)

                Text(L10n.onboardingSubtitle)
                    .font(DS.Typography.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DS.Spacing.xl)

            Spacer()

            // Две CTA — D-02 strict: ровно 2 кнопки, никакого file picker'а.
            VStack(spacing: DS.Spacing.md) {
                Button(L10n.onboardingPaste, action: onPaste)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("BBTB.Onboarding.PasteButton")
                    .accessibilityLabel(Text(L10n.onboardingPaste))

                Button(L10n.onboardingScanQR, action: onScanQR)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("BBTB.Onboarding.QRButton")
                    .accessibilityLabel(Text(L10n.onboardingScanQR))
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
