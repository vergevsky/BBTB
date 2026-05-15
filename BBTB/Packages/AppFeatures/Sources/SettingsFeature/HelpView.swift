// HelpView.swift — Phase 11 / LOC-03 / LOC-04 / D-09.
//
// FAQ-экран приложения. Отдельный SwiftUI View, открывается из Settings
// через NavigationLink (см. SettingsView.swift «Помощь» строка).
//
// Структура: List → один Section с пятью FAQRow (DisclosureGroup-обёртка)
// → footer. Все 5 пар вопрос/ответ берутся из L10n.helpFaq{1..5}{Question,Answer}.
// Полностью двуязычный (ru/en) — никаких hardcoded строк (LOC-03).
//
// FAQ4 содержит обязательную секцию про 22 приложения из РФ, которые
// детектируют VPN (LOC-04 acceptance — см. wiki/vpn-detection-by-apps.md).
//
// Pattern reference: RulesViewerSection.swift (DisclosureGroup label/expanded
// composition). FAQRow — упрощённая версия RuleMatcherDisclosure: только
// текст вопроса как label + текст ответа в expandable области.
//
// Accessibility identifiers `BBTB.Help.FAQ{1..5}` — для UI-тестов Wave 5 UAT.

import SwiftUI
import Localization

public struct HelpView: View {
    public init() {}

    public var body: some View {
        List {
            Section {
                FAQRow(question: L10n.helpFaq1Question, answer: L10n.helpFaq1Answer)
                    .accessibilityIdentifier("BBTB.Help.FAQ1")
                FAQRow(question: L10n.helpFaq2Question, answer: L10n.helpFaq2Answer)
                    .accessibilityIdentifier("BBTB.Help.FAQ2")
                FAQRow(question: L10n.helpFaq3Question, answer: L10n.helpFaq3Answer)
                    .accessibilityIdentifier("BBTB.Help.FAQ3")
                FAQRow(question: L10n.helpFaq4Question, answer: L10n.helpFaq4Answer)
                    .accessibilityIdentifier("BBTB.Help.FAQ4")
                FAQRow(question: L10n.helpFaq5Question, answer: L10n.helpFaq5Answer)
                    .accessibilityIdentifier("BBTB.Help.FAQ5")
            } footer: {
                Text(L10n.helpFooter)
            }
        }
        .navigationTitle(L10n.helpTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .accessibilityIdentifier("BBTB.HelpView")
    }
}

/// DisclosureGroup-обёртка для одной FAQ-пары.
///
/// Вопрос — label, ответ — expanded content. State `isExpanded` локальный,
/// дефолт = `false` (LOC-03 acceptance: «Пользователь видит ровно 5 вопросов,
/// раскрытие — по тапу»).
///
/// `textSelection(.enabled)` на ответе — пользователь может скопировать
/// текст (важно для FAQ4: путь до wiki-страницы).
private struct FAQRow: View {
    let question: String
    let answer: String

    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(answer)
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(question)
                .font(.body)
                .multilineTextAlignment(.leading)
        }
    }
}
