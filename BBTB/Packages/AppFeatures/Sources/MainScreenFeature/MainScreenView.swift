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

    /// Phase 11 / UX-01 / D-01 — sticky-forever флаг. Set'ится в `true` ТОЛЬКО
    /// после первого успешного импорта (внутри `OnboardingView.dismissIfImported`
    /// → `onDismiss` closure → этот var). Сброс возможен только при полном
    /// удалении приложения (acceptable per RESEARCH Pitfall 4 D-01).
    ///
    /// Даже после `deleteAllServers` Onboarding больше не показывается:
    /// EmptyStateCard на главном экране даёт те же 2 CTA.
    @AppStorage("app.bbtb.hasShownOnboarding") private var hasShownOnboarding: Bool = false

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
        // Phase 6e Wave 2 Theme A (L4) — `ImportProgressOverlay` вынесен в `.overlay`
        // modifier-closure (а не inline-в-ZStack). SwiftUI dependency tracking re-eval-ит
        // closure только когда `importInProgress` меняется; inline branch в ZStack body
        // ребилдит весь ZStack body на каждом render. См. RESEARCH.md L4.
        VStack(spacing: 0) {
            if let message = viewModel.reconnectBannerMessage {
                // Phase 6 / Wave 5 — dismiss button only for kill-switch banner
                // (auto-reconnect statuses are transient and clear themselves).
                if viewModel.reconnectBannerState == .killSwitchReconfigure {
                    ReconnectBanner(message: message,
                                    onDismiss: viewModel.dismissReconnectBanner)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                } else {
                    ReconnectBanner(message: message)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                }
            }
            Spacer()
            content
            Spacer()
        }
        .overlay {
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
        // Phase 8 W3 — D-11 min_app_version sheet modifier (UI-SPEC §Layout sheet).
        // Sheet binding driven через MainScreenViewModel.showMinAppVersionSheet.
        // Trigger — `.task` ниже invokes handleMinAppVersionCheck async после
        // cold-start (DEC-06d-01 pattern — не .onAppear, а .task для async).
        .sheet(isPresented: $viewModel.showMinAppVersionSheet) {
            MinAppVersionSheet(
                currentVersion: viewModel.currentAppVersion,
                onOpenTestFlight: {
                    viewModel.dismissMinAppVersionSheet()
                    viewModel.openTestFlight()
                },
                onDismiss: viewModel.dismissMinAppVersionSheet
            )
            #if os(iOS)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.disabled)
            #endif
        }
        .task {
            // Phase 8 W3 — async check на cold-start (per DEC-06d-01).
            // Phase 8 W4 host bootstrap wires `viewModel.wireRulesCoordinator(coordinator)`
            // ещё до того, как этот hook fires; coordinator может быть nil в тестах
            // — handleMinAppVersionCheck guards безопасно.
            await viewModel.handleMinAppVersionCheck()
        }
        // Phase 6e Wave 1 M7 — duplicate `.onChange(of: scenePhase)` для
        // serverListViewModel.silentForegroundRefresh УДАЛЁН. Этот hook теперь
        // часть consolidated `MainScreenViewModel.handleForegroundReentry()`
        // (single Task spawn в host's BBTB_iOSApp / BBTB_macOSApp). Сохранение
        // только одного scenePhase observer гарантирует deterministic ordering
        // и устраняет параллельную contention за Mach ports / cooperative pool.
        //
        // Phase 11 / UX-01 — Onboarding fullScreenCover (iOS) / .sheet (macOS).
        // Pattern S8 — `fullScreenCover` is unavailable on macOS (API not
        // auto-bridged к .sheet), поэтому платформы ветвятся явно как и в
        // существующем QR-блоке ниже.
        //
        // Onboarding-блок ДОЛЖЕН идти в chain ДО блока `showQRScanner`:
        // SwiftUI не разрешает два одновременно active fullScreenCover'а
        // / sheet'а на одной view. `onScanQR` closure ниже ставит
        // `hasShownOnboarding = true` ПЕРЕД `showQRScanner = true`, что
        // закрывает Onboarding sheet раньше, чем открывается QR scanner
        // sheet (избегаем sheet-over-sheet race).
        //
        // Binding setter — no-op: мы не хотим, чтобы user мог swipe-dismiss
        // Onboarding до import success. fullScreenCover на iOS не имеет
        // swipe-dismiss по умолчанию (safe). Управление dismissal — только
        // через `onDismiss` closure (set'ит `hasShownOnboarding = true`
        // → `!hasShownOnboarding` становится `false` → SwiftUI закрывает sheet).
        #if os(iOS)
        .fullScreenCover(isPresented: Binding<Bool>(
            get: { !hasShownOnboarding },
            set: { _ in /* dismissal управляется внутри OnboardingView через onDismiss */ }
        )) {
            OnboardingView(
                viewModel: viewModel,
                onPaste: { viewModel.importFromPasteboard() },
                onScanQR: {
                    // D-01 compromise — закрыть Onboarding ДО открытия QR (избежать
                    // sheet-over-sheet). После Cancel в QR scanner Onboarding
                    // больше не вернётся — user уже committed решением, и
                    // EmptyStateCard на главном экране даёт те же 2 CTA.
                    hasShownOnboarding = true
                    showQRScanner = true
                },
                onDismiss: { hasShownOnboarding = true }
            )
        }
        #elseif os(macOS)
        .sheet(isPresented: Binding<Bool>(
            get: { !hasShownOnboarding },
            set: { _ in /* dismissal управляется внутри OnboardingView через onDismiss */ }
        )) {
            OnboardingView(
                viewModel: viewModel,
                onPaste: { viewModel.importFromPasteboard() },
                onScanQR: {
                    hasShownOnboarding = true
                    showQRScanner = true
                },
                onDismiss: { hasShownOnboarding = true }
            )
        }
        #endif
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
