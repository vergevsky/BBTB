import SwiftUI
import Foundation
import Localization
import DesignSystem

/// Phase 11 / 11-05 — TELEM-02: «Диагностика» секция в Settings.
///
/// Self-contained SwiftUI компонент — содержит собственный `Section` с header / footer
/// и три состояния:
///
/// 1. **Idle (default)** — кнопка «Подготовить лог» (`L10n.diagnosticsExportLog`).
///    Tap запускает `Task { await DiagnosticsExporter.prepareLog() }`. На время сбора
///    переключается в `isPreparing`.
/// 2. **Preparing** — spinner `ProgressView()` + текст `L10n.diagnosticsPreparing`.
/// 3. **Ready** — `ShareLink(item: url)` (cross-platform iOS 16+/macOS 13+) с подготовленным
///    temp файлом. Tap открывает системный Share Sheet — пользователь сам выбирает куда
///    отправить (Mail/Telegram/AirDrop). См. D-11.
///
/// Если `prepareLog()` возвращает `nil` (sing-box.log отсутствует — Pitfall 8) →
/// показывается `.alert` «Нет данных» (заголовок + сообщение из L10n). Этот случай
/// типичен для свежеустановленного приложения — пользователь ещё ни разу не подключался
/// к VPN, поэтому extension не успел создать лог.
///
/// **Footer:** «Последние 24ч. IP-адреса маскируются.» + версия приложения / ОС
/// (через `L10n.diagnosticsVersionFormat(appVer, osVer)`).
///
/// **Размещается в SettingsView напрямую** (без обёртки в outer Section) — компонент
/// УЖЕ возвращает Section на верхнем уровне body. Вложение Section-in-Section даёт
/// странные UI-эффекты в Form.
public struct DiagnosticsSection: View {

    @State private var preparedLogURL: URL? = nil
    @State private var isPreparing: Bool = false
    @State private var showNoLogsAlert: Bool = false

    public init() {}

    public var body: some View {
        Section {
            if let url = preparedLogURL {
                ShareLink(item: url) {
                    Label(L10n.diagnosticsShareLog, systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("BBTB.Settings.DiagnosticsShareLink")
            } else if isPreparing {
                HStack(spacing: DS.Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.diagnosticsPreparing)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task {
                        isPreparing = true
                        defer { isPreparing = false }
                        let url = await DiagnosticsExporter.prepareLog()
                        if let url {
                            preparedLogURL = url
                        } else {
                            // Pitfall 8 — sing-box.log отсутствует → alert «Нет данных».
                            showNoLogsAlert = true
                        }
                    }
                } label: {
                    Label(L10n.diagnosticsExportLog, systemImage: "doc.text.magnifyingglass")
                }
                .accessibilityIdentifier("BBTB.Settings.DiagnosticsExportButton")
            }
        } header: {
            Text(L10n.diagnosticsSection)
        } footer: {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(L10n.diagnosticsLast24h)
                Text(L10n.diagnosticsVersionFormat(appVersionString, osVersionString))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .alert(L10n.diagnosticsNoLogsTitle, isPresented: $showNoLogsAlert) {
            Button(L10n.actionOK, role: .cancel) {}
        } message: {
            Text(L10n.diagnosticsNoLogsMessage)
        }
    }

    // MARK: - Helpers

    private var appVersionString: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
    }

    private var osVersionString: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }
}
