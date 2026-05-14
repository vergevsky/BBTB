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
import ConfigParser

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
    private static let headerH:     CGFloat = 81   // xl-pad + title-row + md-pad + divider
    private static let autoCellH:   CGFloat = 116  // cell body + surrounding padding
    private static let subHeaderH:  CGFloat = 44   // SubscriptionHeader row
    private static let manHeaderH:  CGFloat = 36   // manual-section label row
    private static let serverRowH:  CGFloat = 80   // minHeight 56 + vertical padding 24
    private static let emptyCardH:  CGFloat = 220  // empty-state card
    private static let bottomBuf:   CGFloat = 40   // safe-area / breathing room

    /// Pure helper — testable независимо от UI body. Считает estimated sheet height
    /// из секций; см. константы выше для derivation.
    private static func estimatedHeight(sections: [ServerListSection]) -> CGFloat {
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
        NavigationStack {
            VStack(spacing: 0) {
                // Sheet header — breathing room below drag indicator + title + refresh button.
                HStack {
                    Text(L10n.serverListTitle)
                        .font(DS.Typography.title)
                    Spacer()
                    Button {
                        Task { await viewModel.pullToRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .imageScale(.medium)
                    }
                    .disabled(viewModel.state == .refreshing || viewModel.state == .loading)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.md)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        AutoCell(
                            isSelected: viewModel.isAutoSelected,
                            onTap: viewModel.selectAuto
                        )
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.md)
                        .padding(.bottom, DS.Spacing.sm)

                    if viewModel.sections.isEmpty {
                        emptyCard
                            .padding(DS.Spacing.xl)
                    } else {
                        ForEach(viewModel.sections) { section in
                            Section {
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
                            } header: {
                                sectionHeader(for: section)
                            }
                        }
                    }
                }
            }
            // Plan 04 — pull-to-refresh: fetch all subscriptions → ping all (D-13).
            .refreshable {
                await viewModel.pullToRefresh()
            }
            .accessibilityIdentifier("BBTB.ServerListSheet")
            }
            // Phase 5 Wave 8 — navigation destination: chevron → ServerDetailView push.
            .navigationDestination(item: $viewModel.openServerDetail) { server in
                ServerDetailView(viewModel: viewModel.makeDetailViewModel(for: server))
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(for section: ServerListSection) -> some View {
        if let sub = section.subscription {
            SubscriptionHeader(
                subscription: sub,
                fetchError: viewModel.subscriptionFetchErrors[sub.id],
                onDelete: { viewModel.requestDeleteSubscription(sub) }
            )
        } else {
            Text(L10n.serverListManualSection)
                .font(DS.Typography.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
        }
    }

    @ViewBuilder
    private var emptyCard: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(L10n.serverListEmptyTitle)
                .font(DS.Typography.title)
            Text(L10n.serverListEmptySubtitle)
                .font(DS.Typography.subheadline)
                .foregroundStyle(.secondary)
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
