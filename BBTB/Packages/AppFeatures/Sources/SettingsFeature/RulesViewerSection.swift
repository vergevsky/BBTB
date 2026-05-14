import SwiftUI
import Localization
import RulesEngine

/// Phase 8 W3 — RULES-09 read-only viewer для текущего `RulesSnapshot`.
///
/// **Composition (08-UI-SPEC §Layout):**
/// - Header row «ВЕРСИЯ N · ОБНОВЛЕНО 2 Ч НАЗАД» (caption, uppercase, secondary color).
/// - Три CategoryGroup секции: block_completely → never_through_vpn → always_through_vpn.
/// - Каждая category содержит три DisclosureGroup (Domains / IP CIDRs / Countries)
///   с count-badge + lazy expanded list (`textSelection(.enabled)` для copy-to-pasteboard).
///
/// **Empty state (UI-SPEC §A-17):** показывается если `snapshot == nil` (защитное —
/// baseline всегда applied per D-05; defensively обрабатываем corrupt bundle case).
///
/// **No ViewModel:** pure data view, всё state injected через `snapshot` prop.
/// Owner — `SettingsViewModel.rulesSnapshot`.
public struct RulesViewerSection: View {

    public let snapshot: RulesSnapshot?

    public init(snapshot: RulesSnapshot?) {
        self.snapshot = snapshot
    }

    public var body: some View {
        if let snap = snapshot {
            content(for: snap)
        } else {
            emptyCard
        }
    }

    // MARK: - Content (snapshot != nil)

    @ViewBuilder
    private func content(for snapshot: RulesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 08-UI-SPEC §Layout — header «ВЕРСИЯ N · ОБНОВЛЕНО 2 Ч НАЗАД».
            // Section parent уже даёт system header; добавляем sub-header inline
            // чтобы overall Form визуально читался единым целым.
            headerRow(version: snapshot.version, lastFetchedAt: snapshot.lastFetchedAt)
                .padding(.bottom, 8)

            // 3 категории в фиксированном order — D-01 priority hierarchy.
            RuleCategoryGroup(category: .block, entries: snapshot.block)
            RuleCategoryGroup(category: .never, entries: snapshot.never)
            RuleCategoryGroup(category: .always, entries: snapshot.always)
        }
    }

    @ViewBuilder
    private func headerRow(version: Int, lastFetchedAt: Date?) -> some View {
        // Phase 3 §2.4 RelativeDateTimeFormatter pattern.
        let relativeText: String = {
            guard let lastFetchedAt else {
                return L10n.rulesHeaderNeverFetched
            }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: lastFetchedAt, relativeTo: Date())
        }()
        Text(L10n.rulesHeaderVersion(version, relativeText))
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text(L10n.rulesHeaderVersionA11y(version, relativeText)))
    }

    // MARK: - Empty card (defensive — UI-SPEC §A-17)

    @ViewBuilder
    private var emptyCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.rulesEmptyTitle)
                    .font(.subheadline.weight(.semibold))
                Text(L10n.rulesEmptySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - RuleCategoryGroup (sub-component)

/// Одна категория правил (block / never / always). 3 DisclosureGroup-а внутри +
/// per-category footer text.
///
/// Internal (не public) — детальная композиция RulesViewerSection. Не reused вне
/// этого файла; tests проверяют через RulesViewerSection.
struct RuleCategoryGroup: View {

    enum Category {
        case block
        case never
        case always
    }

    let category: Category
    let entries: CategoryEntries

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Sub-header — uppercase caption (08-UI-SPEC Typography §caption).
            Text(categoryHeader)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .padding(.bottom, 4)

            // 3 matcher sub-rows.
            RuleMatcherDisclosure(
                matcherKind: .domains,
                category: category,
                items: entries.domains
            )
            RuleMatcherDisclosure(
                matcherKind: .ipCidrs,
                category: category,
                items: entries.ipCidrs
            )
            RuleMatcherDisclosure(
                matcherKind: .countries,
                category: category,
                items: entries.countries
            )

            // Footer (08-UI-SPEC §Copywriting).
            Text(categoryFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var categoryHeader: String {
        switch category {
        case .block: return L10n.rulesSectionBlock
        case .never: return L10n.rulesSectionNever
        case .always: return L10n.rulesSectionAlways
        }
    }

    private var categoryFooter: String {
        switch category {
        case .block: return L10n.rulesSectionBlockFooter
        case .never: return L10n.rulesSectionNeverFooter
        case .always: return L10n.rulesSectionAlwaysFooter
        }
    }
}

// MARK: - RuleMatcherDisclosure (sub-component)

/// Один тип matcher'а (domains / ip_cidrs / countries) внутри одной category.
/// DisclosureGroup с label = HStack { icon + name + count badge }; expanded =
/// LazyVStack monospaced entries с `.textSelection(.enabled)`.
///
/// Internal — детальная композиция RuleCategoryGroup.
struct RuleMatcherDisclosure: View {

    enum MatcherKind {
        case domains
        case ipCidrs
        case countries
    }

    let matcherKind: MatcherKind
    let category: RuleCategoryGroup.Category
    let items: [String]

    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            expandedContent
        } label: {
            HStack(spacing: 8) {
                Image(systemName: categoryIcon)
                    .foregroundStyle(categoryColor)
                    .frame(width: 22, alignment: .center)
                    .accessibilityHidden(true)
                Text(matcherName)
                    .font(.body)
                Spacer(minLength: 0)
                countBadge
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(matcherName), \(countBadgeAccessibilityLabel)"))
        }
        .disabled(items.isEmpty)
    }

    @ViewBuilder
    private var expandedContent: some View {
        if items.isEmpty {
            Text(L10n.rulesEmptyCategory)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 4)
        } else {
            // 08-UI-SPEC §Layout — LazyVStack для 10K+ entries scrolling.
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.self) { entry in
                    Text(entry)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 4)
        }
    }

    private var matcherName: String {
        switch matcherKind {
        case .domains: return L10n.rulesMatcherDomains
        case .ipCidrs: return L10n.rulesMatcherIpCidrs
        case .countries: return L10n.rulesMatcherCountries
        }
    }

    @ViewBuilder
    private var countBadge: some View {
        Text(countBadgeText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color(.tertiarySystemFill))
            )
    }

    /// Текст badge'а («1247 доменов» / «3 адреса» / «пусто»).
    private var countBadgeText: String {
        if items.isEmpty {
            return L10n.rulesEmptyCategory
        }
        switch matcherKind {
        case .domains: return L10n.rulesCountDomains(items.count)
        case .ipCidrs: return L10n.rulesCountIpCidrs(items.count)
        case .countries: return L10n.rulesCountCountries(items.count)
        }
    }

    /// VoiceOver-friendly badge text (включает "записей" для clarity).
    private var countBadgeAccessibilityLabel: String {
        if items.isEmpty {
            return L10n.rulesEmptyCategory
        }
        return L10n.rulesCountEntriesA11y(items.count)
    }

    private var categoryIcon: String {
        switch category {
        case .block: return "hand.raised.fill"
        case .never: return "arrow.uturn.backward.circle.fill"
        case .always: return "lock.shield.fill"
        }
    }

    private var categoryColor: Color {
        switch category {
        case .block: return .red
        case .never: return .orange
        case .always: return .green
        }
    }
}

// MARK: - Color helpers (iOS/macOS bridge)

#if canImport(UIKit)
import UIKit
private extension Color {
    init(tertiarySystemFillCompat: UIColor.Type) {
        self = Color(uiColor: .tertiarySystemFill)
    }
}
#endif

#if DEBUG
#Preview("Snapshot with data") {
    Form {
        Section {
            RulesViewerSection(snapshot: RulesSnapshot(
                version: 42,
                lastFetchedAt: Date().addingTimeInterval(-7200),
                block: CategoryEntries(domains: ["max.ru", "mssgr.tatar.ru"]),
                never: CategoryEntries(
                    domains: ["bank.example.ru", "gov.example.ru"],
                    ipCidrs: ["192.168.0.0/16"]
                ),
                always: CategoryEntries(),
                minAppVersion: "0.8.0"
            ))
        }
    }
}

#Preview("Empty (defensive)") {
    Form {
        Section {
            RulesViewerSection(snapshot: nil)
        }
    }
}
#endif
