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

public struct ServerListSheet: View {
    @ObservedObject public var viewModel: ServerListViewModel

    public init(viewModel: ServerListViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        sheetContent
            .presentationDetents([.large])
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
                                    }
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
