// ServerListSheet.swift — Phase 3 / Plan 03 / Task 2.
//
// UI-SPEC §2.1-2.2 — root view sheet, открываемый из ServerLineView через
// MainScreenView.sheet(isPresented: $vm.isPresentingServerList).
//
// Структура (RESEARCH Example 4):
//   ScrollView
//     LazyVStack(spacing: 0)
//       AutoCell                       — sticky top
//       (empty card если sections.isEmpty)
//       Section { servers } header: { SubscriptionHeader | "ДОБАВЛЕНЫ ВРУЧНУЮ" }
//   .refreshable { Plan 04 fills pullToRefresh }
//   .presentationDetents([.large])
//   .presentationDragIndicator(.visible)
//   .task { await onAppear() }
//
// HARD constraints:
// - НЕ List — UI-SPEC §2.2 фиксирует ScrollView+LazyVStack+Section.
// - .refreshable hook ОБЯЗАТЕЛЕН в body (Plan 04 заполнит); plan-level acceptance.
// - macOS: .frame(minWidth: 480, minHeight: 720) внутри #if (T-03-16 mitigation).

import SwiftUI
import VPNCore
import DesignSystem
import Localization
// Phase 6e Wave 2 Theme D — `import ConfigParser` удалён (Periphery-verified
// unused; ServerListSheet не использует ConfigParser types напрямую).

public struct ServerListSheet: View {
    @ObservedObject public var viewModel: ServerListViewModel

    // Phase 6e Wave 2 Theme A (L7) — `@State` detents + `.onChange` driver.
    // Раньше `sheetDetents` пересчитывался каждый SwiftUI body re-render
    // (iterating `viewModel.sections` для расчёта height). Теперь detents
    // хранится в `@State`; пересчёт происходит только при изменении
    // `viewModel.sections` через `.onChange`. См. RESEARCH.md L7.
    @State private var detents: Set<PresentationDetent> = [.large]

    public init(viewModel: ServerListViewModel) {
        self.viewModel = viewModel
    }

    // Heights derived from DS.Spacing constants (server row minHeight=56 + padding.vertical md×2=24 = 80;
    // AutoCell minHeight=72 + padding md×2=24 + parent top md=12 + bottom sm=8 = 116; etc.)
    //
    // Phase 11 / D-08 — Figma height re-tune TODO.
    // Текущие значения derived эмпирически Phase 3 (см. computation comment выше).
    // Figma rev-1 на момент Phase 11 Wave 4 closure: ещё не передан — заменить
    // numeric values после Figma handoff. Comment block + accuracy guarantee
    // sheet height соответствует pixel-perfect spec.
    // См. `.planning/phases/11-onboarding-ux-polish/11-FIGMA-SPEC.md` §4.
    static let headerH:     CGFloat = 81   // TODO: Figma value — xl-pad + title-row + md-pad + divider
    static let autoCellH:   CGFloat = 116  // TODO: Figma value — cell body + surrounding padding
    static let subHeaderH:  CGFloat = 44   // TODO: Figma value — SubscriptionHeader row
    static let manHeaderH:  CGFloat = 36   // TODO: Figma value — manual-section label row
    static let serverRowH:  CGFloat = 80   // TODO: Figma value — minHeight 56 + vertical padding 24
    static let emptyCardH:  CGFloat = 220  // TODO: Figma value — empty-state card
    static let bottomBuf:   CGFloat = 40   // TODO: Figma value — safe-area / breathing room

    /// Pure helper — testable независимо от UI body. Считает estimated sheet height
    /// из секций; см. константы выше для derivation.
    ///
    /// Phase 11 / 11-07 Task 7.2 — exposed `internal` (was `private`) для
    /// прямого тестирования из `ServerListSheetHeightTests`. UI body не
    /// изменился — `computeDetents` остаётся единственным caller'ом из body.
    static func estimatedHeight(sections: [ServerListSection]) -> CGFloat {
        var h = headerH + autoCellH
        if sections.isEmpty {
            return h + emptyCardH + bottomBuf
        }
        for section in sections {
            h += section.subscription != nil ? subHeaderH : manHeaderH
            h += CGFloat(section.servers.count) * serverRowH
        }
        return h + bottomBuf
    }

    /// Pure helper — testable. Конвертирует sections в detents set (iOS only;
    /// macOS = `[.large]` всегда).
    static func computeDetents(sections: [ServerListSection]) -> Set<PresentationDetent> {
        #if os(iOS)
        let maxH = UIScreen.main.bounds.height * 0.88
        let h = estimatedHeight(sections: sections)
        return h < maxH ? [.height(h)] : [.large]
        #else
        return [.large]
        #endif
    }

    public var body: some View {
        sheetContent
            .presentationDetents(detents)
            .onAppear {
                detents = Self.computeDetents(sections: viewModel.sections)
            }
            .onChange(of: viewModel.sections) { _, newSections in
                detents = Self.computeDetents(sections: newSections)
            }
            .presentationDragIndicator(.visible)
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 720)
            #endif
            .task {
                await viewModel.onAppear()
            }
            .alert(
                L10n.serverListRefreshErrorTitle,
                isPresented: refreshErrorBinding,
                actions: {
                    Button(L10n.actionOK) { viewModel.refreshError = nil }
                },
                message: {
                    Text(viewModel.refreshError ?? L10n.serverListRefreshErrorMessage)
                }
            )
            // Plan 04 — D-07 confirmation dialog при swipe-delete на SubscriptionHeader.
            .confirmationDialog(
                L10n.serverListDeleteSubscriptionConfirm(
                    viewModel.pendingDeleteSubscription?.name ?? "",
                    viewModel.pendingDeleteSubscriptionServerCount
                ),
                isPresented: deleteSubscriptionBinding,
                titleVisibility: .visible
            ) {
                Button(L10n.actionDelete, role: .destructive) {
                    if let sub = viewModel.pendingDeleteSubscription {
                        Task { await viewModel.confirmDeleteSubscription(sub) }
                    }
                }
                Button(L10n.actionCancel, role: .cancel) {
                    viewModel.pendingDeleteSubscription = nil
                }
            }
    }

    @ViewBuilder
    private var sheetContent: some View {
        // Phase 5 Wave 8 — NavigationStack wraps content for chevron → ServerDetailView push.
        // Open Q3 mitigation: detent remains user-controlled; if sheet collapses on push,
        // Phase 11 will force .large detent reactively.
        //
        // Phase 12 / DS-14 / M9 — top corners 32pt (UnevenRoundedRectangle).
        // Risk #2 (RESEARCH §2.6): Wave 1 visual verify на iOS 18 simulator —
        // clipShape поверх .presentationDetents. Pitfall 7 (RESEARCH §9):
        // `.background` ДО `.clipShape`, иначе background рисуется как fill,
        // не clipped. См. RESEARCH §2.6 + CODE-CONNECT.md §1.7 + §2.2.
        NavigationStack {
            VStack(spacing: 0) {
                // 2026-05-16 — unified BBTBTopBar (DesignSystem). Title "Список серверов"
                // 16pt Semibold + Phosphor ArrowClockwise refresh trailing (iconSecondary).
                BBTBTopBar(
                    title: L10n.serverListTitle,
                    leading: { EmptyView() },
                    trailing: {
                        Button {
                            Task { await viewModel.pullToRefresh() }
                        } label: {
                            Ph.arrowClockwise.bold
                                .foregroundStyle(DS.Color.iconSecondary)
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.state == .refreshing || viewModel.state == .loading)
                    }
                )

                ScrollView {
                    LazyVStack(spacing: 8, pinnedViews: []) {
                        // AutoCell — standalone card (вне SectionCard, т.к. в Figma
                        // отдельный pill с cornerRadius 24).
                        AutoCell(
                            isSelected: viewModel.isAutoSelected,
                            onTap: viewModel.selectAuto
                        )

                        if viewModel.sections.isEmpty {
                            emptyCard
                                .padding(DS.Spacing.xl)
                        } else {
                            ForEach(viewModel.sections) { section in
                                let collapsed = viewModel.isCollapsed(sectionID: section.id)
                                SectionCard {
                                    sectionHeader(for: section, isCollapsed: collapsed)
                                    // Collapsible: rows рендерятся только когда секция expanded.
                                    if !collapsed {
                                        ForEach(section.servers, id: \.id) { server in
                                            ServerRow(
                                                server: server,
                                                isSelected: viewModel.selectedServerID == server.id,
                                                pingState: viewModel.pingState(for: server.id),
                                                onTap: { viewModel.selectServer(id: server.id) },
                                                onDelete: {
                                                    Task { await viewModel.deleteServer(id: server.id) }
                                                },
                                                onDetailTap: { viewModel.openDetail(for: server) }
                                            )
                                        }
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .animation(.easeInOut(duration: 0.2), value: collapsed)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 16)
                }
                // Plan 04 — pull-to-refresh: fetch all subscriptions → ping all (D-13).
                .refreshable {
                    await viewModel.pullToRefresh()
                }
                .accessibilityIdentifier("BBTB.ServerListSheet")
            }
            // Phase 12 / DS-14 / M9 — 32pt top corners (UnevenRoundedRectangle).
            // background DO clipShape: Pitfall 7 RESEARCH §9 — без правильного
            // порядка background рисуется как unclipped fill за пределами углов.
            //
            // 2026-05-16 fix — `.ignoresSafeArea(edges: .bottom)` устраняет тёмную
            // полосу в самом низу sheet: NavigationStack frame по умолчанию
            // ограничен bottom safe area inset (home indicator), и underlying view
            // показывается через эту полосу. Extension surface bg через safe area
            // заполняет полосу до самого края экрана.
            .background(DS.Color.surface)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: DS.Radius.sheet,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: DS.Radius.sheet,
                    style: .continuous
                )
            )
            .ignoresSafeArea(edges: .bottom)
            // 2026-05-16 — Hide native navigation chrome consistently to prevent
            // layout jump when pushing ServerDetailView (which also hides nav bar
            // and provides own inline back TopBar). Sheet рендерит свой custom
            // header inline — system nav bar дублирует визуально + создаёт shift.
            .toolbar(.hidden, for: .navigationBar)
            // Phase 5 Wave 8 — navigation destination: chevron → ServerDetailView push.
            .navigationDestination(item: $viewModel.openServerDetail) { server in
                ServerDetailView(viewModel: viewModel.makeDetailViewModel(for: server))
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(for section: ServerListSection, isCollapsed: Bool) -> some View {
        if let sub = section.subscription {
            SubscriptionHeader(
                subscription: sub,
                fetchError: viewModel.subscriptionFetchErrors[sub.id],
                isCollapsed: isCollapsed,
                onToggle: { viewModel.toggleCollapsed(sectionID: section.id) },
                onDelete: { viewModel.requestDeleteSubscription(sub) }
            )
        } else {
            // 2026-05-16 Figma sync — Manual section header использует тот же
            // template что SubscriptionHeader: CaretDown + name + collapse toggle.
            Button(action: { viewModel.toggleCollapsed(sectionID: section.id) }) {
                HStack(spacing: 16) {
                    Ph.caretDown.bold
                        .foregroundStyle(DS.Color.iconSecondary)
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
                    Text(L10n.serverListManualSection)
                        .font(DS.Typography.expanded(12, weight: .regular))
                        .foregroundStyle(DS.Color.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Color.surfaceHeader)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var emptyCard: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(DS.Color.textTertiary)
                .accessibilityHidden(true)
            Text(L10n.serverListEmptyTitle)
                .font(DS.Typography.title)
            Text(L10n.serverListEmptySubtitle)
                .font(DS.Typography.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.cardLarge)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var refreshErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.refreshError != nil },
            set: { newValue in if !newValue { viewModel.refreshError = nil } }
        )
    }

    /// Plan 04 — driver для confirmationDialog cascade-delete.
    private var deleteSubscriptionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingDeleteSubscription != nil },
            set: { newValue in if !newValue { viewModel.pendingDeleteSubscription = nil } }
        )
    }
}
