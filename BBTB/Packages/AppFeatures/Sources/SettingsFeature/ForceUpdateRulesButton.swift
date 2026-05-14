import SwiftUI
import Localization
import RulesEngine

#if canImport(UIKit)
import UIKit
#endif

/// Phase 8 W3 — RULES-10 force-update button с finite-state machine.
///
/// **States (08-UI-SPEC §Interaction Patterns 3):**
/// - `.idle` — кнопка enabled, label = «Принудительно обновить правила»; status row hidden.
/// - `.inProgress` — кнопка disabled, ProgressView spinner внутри label, текст «Обновление…».
/// - `.cooldown(secondsRemaining:)` — кнопка disabled, label «Подождите 45с» (countdown).
///
/// **Transitions:**
/// ```
/// .idle  --tap--> .inProgress (VM вызывает forceUpdate())
/// .inProgress --return--> .cooldown(60) (VM ставит cooldownExpiresAt + tick)
/// .cooldown(sec) --1s tick--> .cooldown(sec-1)
/// .cooldown(0)   --tick--> .idle
/// ```
///
/// **Race guard:** ViewModel внутри `triggerForceUpdate()` делает
/// `guard buttonState == .idle else { return }` — двойной tap на грани cooldown
/// expiry no-op'ит без дополнительной защиты на UI-стороне.
public enum ForceUpdateButtonState: Equatable, Sendable {
    /// Initial state и after-cooldown — кнопка кликабельна.
    case idle
    /// Fetch в полёте — спиннер + disabled state. Auto-transitions в `.cooldown(60)`
    /// после VM получает `ForceUpdateOutcome` (любой исход — success/failure).
    case inProgress
    /// 60-second cooldown после force-update. `secondsRemaining` decrements every 1s
    /// (Timer.publish в ViewModel) на основе wallclock `cooldownExpiresAt: Date?` —
    /// foreground re-entry recomputes remaining correctly (UI-SPEC §Edge cases).
    case cooldown(secondsRemaining: Int)
}

/// Force-update CTA button + inline status row. Lives внутри `AdvancedSettingsView`'s
/// «Обновление правил» Form Section.
///
/// **Pure view** — no @ObservedObject, no @StateObject. State driven через
/// `buttonState: ForceUpdateButtonState` + `statusOutcome: ForceUpdateOutcome?` props.
/// Owner — `SettingsViewModel.forceUpdateButtonState` / `.forceUpdateStatusOutcome`.
///
/// **Inline status row:** показывает 4-case outcome (success / alreadyLatest /
/// networkFailure / signatureFailure) с SF Symbol icon + L10n text. Auto-dismiss
/// через 4s обрабатывается ViewModel'ем (не View): VM ставит `statusOutcome = nil`
/// → SwiftUI re-renders без status row. Никаких alert'ов / system toast — inline
/// row только (08-UI-SPEC §A-04).
///
/// **`payloadTooLarge` / `cooldownActive`** — VM не передаёт эти outcomes в этот
/// статус row (это user-facing toast cases, обрабатываются State.cooldown(...);
/// payloadTooLarge — out-of-band edge case, обычным пользователям невидимый).
public struct ForceUpdateRulesButton: View {

    public let buttonState: ForceUpdateButtonState
    public let statusOutcome: ForceUpdateOutcome?
    public let onTap: () -> Void

    public init(
        buttonState: ForceUpdateButtonState,
        statusOutcome: ForceUpdateOutcome?,
        onTap: @escaping () -> Void
    ) {
        self.buttonState = buttonState
        self.statusOutcome = statusOutcome
        self.onTap = onTap
    }

    public var body: some View {
        // 08-UI-SPEC §Layout: spacing 8pt между кнопкой и status row;
        // используем литералы (DS.Spacing.md == 12 legacy, A-14 docs).
        VStack(alignment: .leading, spacing: 8) {
            Button(action: handleTap) {
                buttonLabel
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .controlSize(.large)
            .disabled(buttonState != .idle)
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityHint(Text(accessibilityHint))

            if let outcome = statusOutcome, let row = statusRowContent(for: outcome) {
                row
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: outcome)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Tap handler (iOS haptic per UI-SPEC §A-18)

    private func handleTap() {
        guard buttonState == .idle else { return }
        #if canImport(UIKit) && os(iOS)
        // 08-UI-SPEC §A-18 — light impact haptic ТОЛЬКО на iOS.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        onTap()
    }

    // MARK: - Button label (state-dependent)

    @ViewBuilder
    private var buttonLabel: some View {
        switch buttonState {
        case .idle:
            Text(L10n.rulesForceUpdateButton)
                .font(.subheadline.weight(.semibold))
        case .inProgress:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text(L10n.rulesForceUpdateInProgress)
                    .font(.subheadline.weight(.semibold))
            }
        case .cooldown(let sec):
            Text(L10n.rulesForceUpdateCooldown(sec))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }

    // MARK: - Status row (4 mapped outcomes)

    /// Returns nil для outcome cases которые НЕ показываются в inline status row
    /// (`.cooldownActive` отображается через `buttonState`; `.payloadTooLarge`
    /// silently folded в network failure UI — admin's problem).
    @ViewBuilder
    private func statusRowContent(for outcome: ForceUpdateOutcome) -> (some View)? {
        switch outcome {
        case .success(let version):
            statusRow(
                icon: "checkmark.circle.fill",
                color: .green,
                text: L10n.rulesForceUpdateSuccess(version)
            )
        case .alreadyLatest(let version):
            statusRow(
                icon: "checkmark.circle",
                color: .green,
                text: L10n.rulesForceUpdateNoChange(version)
            )
        case .networkFailure:
            statusRow(
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                text: L10n.rulesForceUpdateNetwork
            )
        case .signatureFailure:
            statusRow(
                icon: "lock.slash.fill",
                color: .orange,
                text: L10n.rulesForceUpdateSignature
            )
        case .cooldownActive, .payloadTooLarge:
            // .cooldownActive: уже коммуницируем через buttonState.cooldown(...).
            // .payloadTooLarge: admin-side edge case; для UI fold в general "не удалось".
            EmptyView()
        }
    }

    private func statusRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(text))
    }

    // MARK: - Accessibility (08-UI-SPEC §Accessibility)

    private var accessibilityLabel: String {
        switch buttonState {
        case .idle:
            return L10n.rulesForceUpdateButton
        case .inProgress:
            return L10n.rulesForceUpdateInProgress
        case .cooldown(let sec):
            return L10n.rulesForceUpdateCooldownA11y(sec)
        }
    }

    private var accessibilityHint: String {
        switch buttonState {
        case .idle:
            return L10n.rulesForceUpdateButtonHint
        case .inProgress, .cooldown:
            return L10n.rulesForceUpdateCooldownHint
        }
    }
}

#if DEBUG
#Preview("Idle") {
    Form {
        Section {
            ForceUpdateRulesButton(
                buttonState: .idle,
                statusOutcome: nil,
                onTap: {}
            )
        }
    }
}

#Preview("InProgress") {
    Form {
        Section {
            ForceUpdateRulesButton(
                buttonState: .inProgress,
                statusOutcome: nil,
                onTap: {}
            )
        }
    }
}

#Preview("Cooldown success") {
    Form {
        Section {
            ForceUpdateRulesButton(
                buttonState: .cooldown(secondsRemaining: 45),
                statusOutcome: .success(version: 42),
                onTap: {}
            )
        }
    }
}

#Preview("Cooldown signature failure") {
    Form {
        Section {
            ForceUpdateRulesButton(
                buttonState: .cooldown(secondsRemaining: 30),
                statusOutcome: .signatureFailure,
                onTap: {}
            )
        }
    }
}
#endif
