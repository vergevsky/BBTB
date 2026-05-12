import SwiftUI
import Localization
import DesignSystem
import ServerListFeature

/// UI-SPEC §2-§3 — главный экран Phase 2 rewrite.
///
/// Top bar (≡ menu / + Add Menu) + content branch (empty card vs idle layout).
/// SettingsView navigation через `.toolbar` ToolbarItem с placement `.topBarLeading`
/// (plan-check F-02 — variant A).
public struct MainScreenView: View {
    @ObservedObject public var viewModel: MainScreenViewModel
    @State private var showQRScanner = false
    /// Plan 04 D-12 — scenePhase .active → silent refresh subscriptions (без UI spinner).
    @Environment(\.scenePhase) private var scenePhase

    /// Closure для root App scene — push на SettingsView через NavigationStack.
    /// На iOS — NavigationLink в `.toolbar`. На macOS — Cmd+, Settings Scene.
    public var onOpenSettings: (() -> Void)?

    public init(viewModel: MainScreenViewModel, onOpenSettings: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if viewModel.needsReconnectForKillSwitch,
                   case .connected = viewModel.state {
                    ReconnectBanner(onDismiss: viewModel.dismissReconnectBanner)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                }
                Spacer()
                content
                Spacer()
            }
            if viewModel.importInProgress {
                ImportProgressOverlay()
            }
        }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                menuButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                addMenu
            }
            #else
            ToolbarItem(placement: .navigation) {
                menuButton
            }
            ToolbarItem(placement: .primaryAction) {
                addMenu
            }
            #endif
        }
        .alert(L10n.alertImportFailed, isPresented: errorBinding) {
            Button(L10n.actionOK) { viewModel.lastError = nil }
        } message: {
            Text(viewModel.lastError ?? "")
        }
        .sheet(isPresented: $viewModel.isPresentingServerList) {
            if let listVM = viewModel.serverListViewModel {
                ServerListSheet(viewModel: listVM)
            }
        }
        // Plan 04 D-12 — foreground refresh subscriptions при возврате в active state.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, let vm = viewModel.serverListViewModel {
                Task { @MainActor in
                    await vm.silentForegroundRefresh()
                }
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showQRScanner) {
            QRScannerView(
                onCodeScanned: { uri in
                    viewModel.importFromQRString(uri)
                    showQRScanner = false
                },
                onCancel: { showQRScanner = false }
            )
        }
        #elseif os(macOS)
        .sheet(isPresented: $showQRScanner) {
            QRScannerView(
                onCodeScanned: { uri in
                    viewModel.importFromQRString(uri)
                    showQRScanner = false
                },
                onCancel: { showQRScanner = false }
            )
            .frame(width: 480, height: 640)
        }
        #endif
    }

    @ViewBuilder
    private var menuButton: some View {
        Button {
            onOpenSettings?()
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.title3)
        }
        .accessibilityIdentifier("BBTB.MenuButton")
        .accessibilityLabel(Text(L10n.settingsTitle))
    }

    @ViewBuilder
    private var addMenu: some View {
        Menu {
            Button {
                showQRScanner = true
            } label: {
                Label(L10n.menuScanQR, systemImage: "qrcode.viewfinder")
            }
            Button(action: viewModel.importFromPasteboard) {
                Label(L10n.menuImportFromClipboard, systemImage: "doc.on.clipboard")
            }
        } label: {
            Image(systemName: "plus")
                .font(.title3)
        }
        .accessibilityIdentifier("BBTB.AddButton")
        .accessibilityLabel(Text(L10n.menuAddConfig))
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .empty:
            EmptyStateCard(
                onAddFromClipboard: viewModel.importFromPasteboard,
                onScanQR: { showQRScanner = true }
            )
            .padding(.horizontal)
        case .idle, .connecting, .connected, .error:
            VStack(spacing: DS.Spacing.xxl) {
                ConnectionTimer(since: connectionStartDate)
                StatusPill(state: viewModel.state)
                ConnectionButton(state: viewModel.state, action: viewModel.toggleConnection)
                if let name = viewModel.activeServerName {
                    ServerLineView(name: name, onTap: viewModel.presentServerList)
                }
            }
        }
    }

    private var connectionStartDate: Date? {
        if case let .connected(since) = viewModel.state { return since }
        return nil
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.lastError != nil },
            set: { newValue in if !newValue { viewModel.lastError = nil } }
        )
    }
}
