// HelpViewTests.swift — Phase 11 / 11-06 / Task 6.1.
//
// LOC-03 lint guard для HelpView FAQ accessors:
// - проверяет, что L10n.helpFaq{1..5}{Question,Answer} существуют и
//   возвращают non-empty значения (compile-time guard — если кто-то
//   удалил ключ в L10n.swift, тест не скомпилируется);
// - гарантирует уникальность 10 поднимаемых ключей: если кто-то случайно
//   замапит две FAQ на один ключ, Set.count != 10;
// - проверяет наличие helpTitle / helpFooter / helpEntryLabel.
//
// LOC-04 content invariant:
// - читает `Localizable.xcstrings` напрямую с диска (через `#filePath`-навигацию
//   до пакета Localization) и проверяет, что значения `help.faq4.question` /
//   `help.faq4.answer` для ru-локали содержат хотя бы один из ключевых маркеров
//   («22», «приложен», «детект», «VPN»). Это защищает текстовое содержание FAQ4
//   от случайного «выпадения» темы про 22 российских приложения.
//
// SPM caveat (см. Plan 11-01 TransportPickerLabelsTests):
//   при запуске `swift test` (SPM) `Localizable.xcstrings` НЕ компилируется в
//   `.strings`, поэтому `NSLocalizedString` возвращает raw key как fallback.
//   Из-за этого L10n.helpFaq* в test-режиме = "help.faq*.question". Поэтому
//   keyword-проверку делаем по сырым xcstrings JSON (Single source of truth),
//   а не по результату L10n accessor'а.
//
// Регрессии типа `Text("FAQ")` (raw literal) ловит grep gate в acceptance criteria
// Plan 11-06 — отдельный shell-уровень.

import XCTest
@testable import SettingsFeature
import Localization

final class HelpViewTests: XCTestCase {

    // MARK: - 1. Все 10 FAQ-accessor'ов резолвятся и non-empty

    /// L10n.helpFaq{1..5}{Question,Answer} существуют, callable, non-empty.
    /// Compile-time guard: если кто-то удалил ключ в L10n.swift, этот test
    /// не скомпилируется. Runtime: если NSLocalizedString вернул пустую строку
    /// (broken bundle) — тест упадёт.
    func test_allFAQ_accessors_resolveNonEmpty() {
        let pairs: [(name: String, value: String)] = [
            ("helpFaq1Question", L10n.helpFaq1Question),
            ("helpFaq1Answer",   L10n.helpFaq1Answer),
            ("helpFaq2Question", L10n.helpFaq2Question),
            ("helpFaq2Answer",   L10n.helpFaq2Answer),
            ("helpFaq3Question", L10n.helpFaq3Question),
            ("helpFaq3Answer",   L10n.helpFaq3Answer),
            ("helpFaq4Question", L10n.helpFaq4Question),
            ("helpFaq4Answer",   L10n.helpFaq4Answer),
            ("helpFaq5Question", L10n.helpFaq5Question),
            ("helpFaq5Answer",   L10n.helpFaq5Answer),
        ]
        for pair in pairs {
            XCTAssertFalse(
                pair.value.isEmpty,
                "L10n.\(pair.name) вернул пустую строку — bundle/xcstrings setup сломан."
            )
        }
    }

    // MARK: - 2. 10 FAQ-ключей уникальны (защита от copy-paste)

    /// Десять FAQ-accessor'ов должны соответствовать десяти разным ключам
    /// (даже если в SPM-test `NSLocalizedString` возвращает raw key —
    /// уникальность raw keys всё равно гарантирует, что в xcstrings каждый
    /// label маппится на отдельную запись).
    func test_allFAQ_keys_areUnique() {
        let values: [String] = [
            L10n.helpFaq1Question, L10n.helpFaq1Answer,
            L10n.helpFaq2Question, L10n.helpFaq2Answer,
            L10n.helpFaq3Question, L10n.helpFaq3Answer,
            L10n.helpFaq4Question, L10n.helpFaq4Answer,
            L10n.helpFaq5Question, L10n.helpFaq5Answer,
        ]
        let unique = Set(values)
        XCTAssertEqual(
            unique.count, 10,
            "FAQ accessor'ы должны быть уникальными — получили \(unique.count) уникальных: \(values)"
        )
    }

    // MARK: - 3. helpTitle / helpFooter / helpEntryLabel резолвятся

    func test_helpTitle_resolves() {
        XCTAssertFalse(L10n.helpTitle.isEmpty, "L10n.helpTitle empty — ключ help.title пропал")
    }

    func test_helpFooter_resolves() {
        XCTAssertFalse(L10n.helpFooter.isEmpty, "L10n.helpFooter empty — ключ help.footer пропал")
    }

    func test_helpEntryLabel_resolves() {
        XCTAssertFalse(
            L10n.helpEntryLabel.isEmpty,
            "L10n.helpEntryLabel empty — ключ help.entry.label пропал (нужен для SettingsView строки «Помощь»)"
        )
    }

    // MARK: - 4. LOC-04 content invariant — FAQ4 ru content про 22 приложения

    /// Читаем `Localizable.xcstrings` с диска и проверяем, что
    /// `help.faq4.question` + `help.faq4.answer` в ru-локали содержат
    /// хотя бы один маркер из {«22», «приложен», «детект», «VPN»}.
    /// Защищает LOC-04 acceptance: «FAQ обязательно содержит секцию про 22
    /// приложения из РФ, которые детектируют VPN».
    func test_LOC04_FAQ4_xcstrings_contains_detection_keywords() throws {
        let xcstrings = try loadXCStrings()
        let strings = try XCTUnwrap(xcstrings["strings"] as? [String: Any], "xcstrings missing top-level 'strings' object")

        let q = try ruValue(for: "help.faq4.question", in: strings)
        let a = try ruValue(for: "help.faq4.answer", in: strings)

        let combined = (q + " " + a).lowercased()
        let keywords = ["22", "приложен", "детект", "vpn"]
        let foundAny = keywords.contains { combined.contains($0) }

        XCTAssertTrue(
            foundAny,
            "FAQ4 ru-контент не содержит ни одного маркера из \(keywords). " +
            "Question: \(q)\nAnswer: \(a)\nLOC-04 acceptance broken — FAQ должен явно " +
            "упоминать «22 приложения» / «детектирование VPN»."
        )
    }

    // MARK: - Helpers

    /// Навигирует от текущего тест-файла до `Localization/Resources/Localizable.xcstrings`
    /// и парсит JSON.
    ///
    /// `#filePath` указывает на этот test-файл:
    ///   .../BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/HelpViewTests.swift
    /// Пять `deletingLastPathComponent()` поднимают до `BBTB/Packages/`, далее
    /// относительный путь до Localization-пакета.
    private func loadXCStrings(file: StaticString = #filePath) throws -> [String: Any] {
        let testFile = URL(fileURLWithPath: "\(file)")
        // .../SettingsFeatureTests/HelpViewTests.swift
        // → .../SettingsFeatureTests
        // → .../Tests
        // → .../AppFeatures
        // → .../Packages
        let packagesDir = testFile
            .deletingLastPathComponent()  // SettingsFeatureTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // AppFeatures
            .deletingLastPathComponent()  // Packages
        let xcstringsURL = packagesDir
            .appendingPathComponent("Localization")
            .appendingPathComponent("Sources")
            .appendingPathComponent("Localization")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Localizable.xcstrings")

        let data = try Data(contentsOf: xcstringsURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "HelpViewTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Localizable.xcstrings is not a JSON object at \(xcstringsURL.path)"
            ])
        }
        return json
    }

    /// Достаёт ru-значение для конкретного ключа из распарсенной xcstrings структуры.
    /// Схема xcstrings:
    ///   strings.<key>.localizations.<lang>.stringUnit.value
    private func ruValue(for key: String, in strings: [String: Any]) throws -> String {
        let entry = try XCTUnwrap(strings[key] as? [String: Any], "xcstrings missing key '\(key)'")
        let loc = try XCTUnwrap(entry["localizations"] as? [String: Any], "xcstrings key '\(key)' missing 'localizations'")
        let ru = try XCTUnwrap(loc["ru"] as? [String: Any], "xcstrings key '\(key)' missing ru localization")
        let unit = try XCTUnwrap(ru["stringUnit"] as? [String: Any], "xcstrings key '\(key)' ru missing stringUnit")
        let value = try XCTUnwrap(unit["value"] as? String, "xcstrings key '\(key)' ru stringUnit missing value")
        return value
    }
}
