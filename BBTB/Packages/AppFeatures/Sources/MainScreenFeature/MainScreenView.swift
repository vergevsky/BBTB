import SwiftUI
import Localization
import DesignSystem
import ServerListFeature
import UniformTypeIdentifiers  // Phase 11 / IMP-03 — .json / .yaml / .yml UTType filtering

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

    /// Phase 11 / IMP-03 — toggle для SwiftUI `.fileImporter` (системный document picker).
    /// Активируется третьей кнопкой в меню «+»; результат идёт через
    /// `viewModel.importFromFile(rawContents:)`.
    @State private var showFileImporter = false
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
            #if os(iOS)
            // 2026-05-16 — Figma `TopBar` 3115:327 inline (вместо native `.toolbar`).
            // Native toolbar в iOS 26 auto-применяет Liquid Glass circle backdrop
            // под toolbar items; Figma TopBar требует «naked» Phosphor glyph без
            // подложки. Inline HStack полностью обходит этот эффект.
            // Layout совпадает с Figma: padding-horizontal 28pt, frame.height 56pt,
            // SPACE_BETWEEN distribution через Spacer.
            HStack(spacing: 0) {
                menuButton
                Spacer()
                addMenu
            }
            .padding(.horizontal, 28)
            .padding(.top, DS.Spacing.lg)
            .frame(height: 56)
            #endif

            Spacer()
            content
            Spacer()
        }
        .overlay {
            if viewModel.importInProgress {
                ImportProgressOverlay()
            }
        }
        // 2026-05-16 — Floating banner overlay (Figma 3047:568 pill). Заменяет
        // inline-в-VStack rendering (pre-2026-05-16 — banner сдвигал контент вниз).
        // Per user feedback: banner всплывает поверх TopBar между ≡ и + кнопками
        // НЕ перекрывая их, и НЕ сдвигая ConnectionButton/ServerLineView.
        //
        // Horizontal padding 80pt = 28 (edge→icon) + 24 (icon width) + 28 (icon→banner) —
        // banner живёт между иконками с теми же отступами что edge→icon.
        .overlay(alignment: .top) {
            if let bannerMessage = effectiveBannerMessage {
                ReconnectBanner(
                    message: bannerMessage,
                    onDismiss: effectiveBannerDismiss
                )
                .padding(.horizontal, 80)
                .padding(.top, DS.Spacing.lg + 16)  // TopBar top padding + ~icon center align
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: effectiveBannerMessage)
        #if os(iOS)
        // Скрываем native navigation bar — TopBar теперь inline в body.
        .toolbar(.hidden, for: .navigationBar)
        #else
        // macOS — native window toolbar (нет Liquid Glass auto-backdrop проблемы;
        // macOS toolbar следует platform conventions, не нуждается в inline rebuild).
        .toolbar {
            ToolbarItem(placement: .navigation) {
                menuButton
            }
            ToolbarItem(placement: .primaryAction) {
                addMenu
            }
        }
        #endif
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
        // Phase 11 / IMP-03 — SwiftUI native document picker. Cross-platform
        // (iOS 14+ / macOS 11+, наш минимум выше). Открывается из третьей
        // кнопки в addMenu («Импортировать из файла»). Принимает .json / .yaml
        // / .yml; security-scoped resource handling — обязательное Apple-
        // mandated требование для файлов из iCloud Drive / Files.app (см.
        // RESEARCH Pitfall 5). Чтение файла — внутри Task { ... }, чтобы IO
        // не блокировал main thread на iCloud-located файлах.
        //
        // UTType inline factory — single-use, `??` defensive nil-coalesce на .data
        // если runtime не зарегистрировал yaml/yml UTType (theory; в практике
        // resolve работает, см. test_uttype_yaml_resolvable).
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [
                .json,
                UTType(filenameExtension: "yaml") ?? .data,
                UTType(filenameExtension: "yml") ?? .data
            ],
            allowsMultipleSelection: false
        ) { result in
            Task {
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    // Apple-mandated: внешние URL (iCloud / Files.app) требуют
                    // явный permission через security-scoped resource API.
                    guard url.startAccessingSecurityScopedResource() else {
                        await MainActor.run {
                            viewModel.lastError = L10n.importErrorFileAccessDenied
                        }
                        return
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        let text = try String(contentsOf: url, encoding: .utf8)
                        await MainActor.run {
                            viewModel.importFromFile(rawContents: text)
                        }
                    } catch {
                        await MainActor.run {
                            viewModel.lastError = L10n.importErrorFileReadFailed
                        }
                    }
                case .failure(let error):
                    await MainActor.run {
                        viewModel.lastError = error.localizedDescription
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var menuButton: some View {
        Button {
            onOpenSettings?()
        } label: {
            // 2026-05-16 — Phosphor Icons Bold семейство (Figma BBTB v3 spec).
            // `Ph.list.bold` визуально точно матчит TopBar List иконку (3115:328).
            // .frame(24×24) — Figma icon-slot size.
            Ph.list.bold
                .foregroundStyle(DS.Color.iconPrimary)
                .frame(width: 24, height: 24)
        }
        // .buttonStyle(.plain) — отключает iOS 26 Liquid Glass auto-backdrop
        // на toolbar items (Figma TopBar 3115:327 без circle behind glyph).
        .buttonStyle(.plain)
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
            // Phase 11 / IMP-03 — третья кнопка «Импортировать из файла».
            // Открывает SwiftUI `.fileImporter` (системный document picker)
            // с фильтром .json / .yaml / .yml.
            Button {
                showFileImporter = true
            } label: {
                Label(L10n.menuImportFromFile, systemImage: "doc")
            }
            .accessibilityIdentifier("BBTB.AddMenu.ImportFromFile")
        } label: {
            // 2026-05-16 — Phosphor Plus Bold (Figma 3115:332).
            // SF Symbol native dropdown menu indicator остаётся через Menu API
            // — Phosphor icon заменяет только trigger glyph.
            Ph.plus.bold
                .foregroundStyle(DS.Color.iconPrimary)
                .frame(width: 24, height: 24)
        }
        // .menuStyle(.button) + .buttonStyle(.plain) убирает iOS 26 Liquid Glass
        // auto-backdrop у Menu trigger (Figma TopBar без circle behind +).
        .menuStyle(.button)
        .buttonStyle(.plain)
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
            // 2026-05-16 Figma BBTB v3 unified layout (frames 3043:341, 3047:538,
            // 3047:598, 3047:568). External ConnectionTimer / StatusPill удалены —
            // status, timer и hints живут внутри ConnectionButton labelContent.
            VStack(spacing: 0) {
                Spacer()
                ConnectionButton(
                    state: viewModel.state,
                    connectedSince: connectionStartDate,
                    action: viewModel.toggleConnection
                )
                Spacer()
                if let name = viewModel.activeServerName {
                    ServerLineView(name: name, onTap: viewModel.presentServerList)
                        .padding(.bottom, DS.Spacing.lg)
                }
            }
        }
    }

    private var connectionStartDate: Date? {
        if case let .connected(since) = viewModel.state { return since }
        return nil
    }

    /// 2026-05-16 — derived banner message. Combines:
    /// 1. `.error` state → static "Ошибка подключения" (Figma 3047:568)
    /// 2. ViewModel reconnect banner (auto-reconnect status / kill-switch).
    /// `.error` имеет приоритет (state-driven, не зависит от reconnect cycles).
    private var effectiveBannerMessage: String? {
        if case .error = viewModel.state {
            return L10n.bannerConnectionError
        }
        return viewModel.reconnectBannerMessage
    }

    /// Dismiss-кнопка только для kill-switch reconfigure (user должен confirm
    /// переподключение вручную). Error banner и auto-reconnect статусы — auto-dismiss
    /// при state change (transient).
    private var effectiveBannerDismiss: (() -> Void)? {
        if case .error = viewModel.state {
            return nil
        }
        if viewModel.reconnectBannerState == .killSwitchReconfigure {
            return viewModel.dismissReconnectBanner
        }
        return nil
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.lastError != nil },
            set: { newValue in if !newValue { viewModel.lastError = nil } }
        )
    }
}
