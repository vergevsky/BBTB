import SwiftUI
import Localization

/// Phase 8 W3 — D-11 persistent banner row внутри `AdvancedSettingsView` Form.
///
/// **Persistent semantics:** показывается ВСЕГДА пока `min_app_version > current`,
/// независимо от того, dismiss-нул ли пользователь modal sheet (08-UI-SPEC §A-08).
/// `dismissedMinAppVersion` @AppStorage гасит ТОЛЬКО modal sheet; banner stays
/// до тех пор, пока admin не понизит `min_app_version` или пользователь не
/// обновит app.
///
/// **Visual:** Orange-tinted background (mirror ReconnectBanner), SF Symbol
/// `arrow.up.circle.fill` (orange), 2-line title+CTA, trailing chevron.
/// Tap → invokes `onTap` (производитель wire'ит на `openTestFlight()`).
///
/// **Pure view:** no @State, no ViewModel. `currentVersion` показывается в
/// accessibilityLabel для контекста («ваша версия 0.7.0»).
public struct MinAppVersionBanner: View {

    /// Текущая app version — для accessibility описания.
    public let currentVersion: String

    /// Tap handler — обычно `viewModel.openTestFlight()`.
    public let onTap: () -> Void

    public init(currentVersion: String, onTap: @escaping () -> Void) {
        self.currentVersion = currentVersion
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.minAppVersionBannerText)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(L10n.minAppVersionBannerCta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(L10n.minAppVersionBannerA11yLabel(currentVersion)))
        .accessibilityHint(Text(L10n.minAppVersionBannerA11yHint))
        .accessibilityAddTraits(.isButton)
    }
}

#if DEBUG
#Preview {
    Form {
        Section {
            MinAppVersionBanner(currentVersion: "0.7.0", onTap: {})
        }
        .listRowBackground(Color.orange.opacity(0.15))

        Section {
            Text("DNS section placeholder")
        } header: {
            Text("DNS")
        }
    }
}
#endif
