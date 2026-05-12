import SwiftUI
import Localization

/// Phase 6 / NET-02 (D-03) — текстовое поле «Свой DNS-сервер» с inline-валидацией.
///
/// Поле принимает IPv4 (`8.8.8.8`) или RFC 1123 hostname (`my-doh.example.com`).
/// Невалидный input не блокирует ввод — но показывает красную подсказку,
/// и `SettingsViewModel.dnsConfig` всё равно игнорирует мусор (defense in depth, Pitfall 9).
public struct CustomDNSField: View {
    @Binding public var text: String
    @State private var isInvalid: Bool = false

    public init(text: Binding<String>) {
        self._text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.settingsDnsCustomLabel)
                .font(.caption)
                .foregroundColor(.secondary)

            textFieldView

            if isInvalid {
                Text(L10n.settingsDnsCustomInvalid)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .onAppear {
            recomputeValidity(for: text)
        }
    }

    // Extracted to keep the `body` builder type-checking fast and to allow
    // platform-specific modifiers without nesting too deeply.
    private var textFieldView: some View {
        let field = TextField(L10n.settingsDnsCustomPlaceholder, text: $text)
            .autocorrectionDisabled(true)
            .onChange(of: text) { _, newValue in
                recomputeValidity(for: newValue)
            }

        #if os(iOS)
        return field
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
        #else
        return field
        #endif
    }

    private func recomputeValidity(for value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isInvalid = false
            return
        }
        isInvalid = !Self.isValidIPv4OrHostname(trimmed)
    }

    // MARK: - Validation (mirrors SettingsViewModel; intentionally duplicated
    // to keep this view standalone — both layers validate per Pitfall 9).

    static func isValidIPv4OrHostname(_ trimmed: String) -> Bool {
        if looksLikeIPv4(trimmed) {
            return isValidIPv4(trimmed)
        }
        return isValidHostname(trimmed)
    }

    private static func looksLikeIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        for part in parts {
            guard !part.isEmpty else { return false }
            for ch in part where !ch.isASCII || !ch.isNumber { return false }
        }
        return true
    }

    private static func isValidIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard !part.isEmpty, part.count <= 3 else { return false }
            for ch in part where !ch.isASCII || !ch.isNumber { return false }
            guard let value = Int(part), value >= 0, value <= 255 else { return false }
        }
        return true
    }

    private static func isValidHostname(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 253 else { return false }
        let labels = s.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard !label.isEmpty, label.count <= 63 else { return false }
            guard let first = label.first, let last = label.last else { return false }
            guard first.isLetter || first.isNumber else { return false }
            guard last.isLetter || last.isNumber else { return false }
            for ch in label {
                guard ch.isASCII else { return false }
                if ch.isLetter || ch.isNumber || ch == "-" { continue }
                return false
            }
        }
        return true
    }
}
