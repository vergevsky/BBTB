import SwiftUI
import Localization

/// Phase 6 / 06-03 — экран Settings → Advanced. Phase 8 W3 расширен:
/// `MinAppVersionBanner` + `RulesViewerSection` (RULES-09) + `ForceUpdateRulesButton` (RULES-10).
///
/// **Form section order (08-UI-SPEC §Layout):**
/// 1. **MinAppVersionBanner** (conditional, top of Form) — orange-tinted persistent row,
///    показывается ВСЕГДА пока `showMinAppVersionBanner == true` (UI-SPEC §A-08).
/// 2. **DNS section** (Phase 6, existing) — AdBlockToggleSection + CustomDNSField.
/// 3. **Rules viewer** (Phase 8 W3, NEW) — RULES-09 read-only viewer текущего snapshot.
/// 4. **Force-update section** (Phase 8 W3, NEW) — RULES-10 кнопка с inline status row.
///
/// Все строки локализованы через L10n (LOC-01 baseline, Russian primary + English duplicate).
public struct AdvancedSettingsView: View {
    @ObservedObject public var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            // ─── Section 1: MinAppVersionBanner (conditional) ─────────────────────
            // Phase 8 W3 — D-11 persistent banner UI-SPEC §A-08.
            // listRowBackground устанавливает orange tint для row container.
            if viewModel.showMinAppVersionBanner {
                Section {
                    MinAppVersionBanner(
                        currentVersion: viewModel.currentAppVersion,
                        onTap: viewModel.openTestFlight
                    )
                }
                .listRowBackground(Color.orange.opacity(0.15))
            }

            // ─── Section 2: DNS (Phase 6, existing) ───────────────────────────────
            Section {
                AdBlockToggleSection(
                    isOn: $viewModel.adBlockEnabled,
                    footerText: L10n.settingsDnsAdblockFooter
                )
                CustomDNSField(text: $viewModel.customDNS)
            } header: {
                Text(L10n.settingsDnsSection)
            } footer: {
                Text(L10n.settingsDnsCustomFooter)
            }

            // ─── Section 3: Rules viewer (Phase 8 W3, NEW — RULES-09) ─────────────
            Section {
                RulesViewerSection(snapshot: viewModel.rulesSnapshot)
            }

            // ─── Section 4: Force-update button (Phase 8 W3, NEW — RULES-10) ──────
            Section {
                ForceUpdateRulesButton(
                    buttonState: viewModel.forceUpdateButtonState,
                    statusOutcome: viewModel.forceUpdateStatusOutcome,
                    onTap: {
                        Task { @MainActor in
                            await viewModel.triggerForceUpdate()
                        }
                    }
                )
            } header: {
                Text(L10n.rulesForceUpdateSection)
            } footer: {
                Text(L10n.rulesForceUpdateFooter)
            }
        }
        .navigationTitle(L10n.settingsAdvancedTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}
