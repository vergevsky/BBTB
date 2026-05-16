// OnboardingViewSnapshotTests.swift — Phase 12 / Plan 12-02 / Task 8 /
// DS-11 + M7 + W5 fix #2 + B2 visual lock.
//
// Snapshot baseline для OnboardingView полного экрана (hero text 48pt SF Pro
// Expanded Semibold + 2 CTA pill стили + Subtitle + Dark canvas).
//
// W5/B2 LOCK CONTRACT (revision iteration 1): этот test FAIL'ит если кто-то
//   - откатит hero font на titleScreen=16 (B2 — visual catches Display vs
//     Title size difference);
//   - подменит PrimaryButtonStyle/SecondaryButtonStyle на .borderedProminent/
//     .bordered system styles (M7);
//   - откатит accent color на .tint (W5+M7);
//   - удалит hero text split на single `Text(...)`.
//
// PLATFORM GATE (Phase 12 inherited): iOS/tvOS only (`.image(layout:)` extension
// SwiftUI.View ⇒ UIImage).
//
// PERCEPTUAL PRECISION 0.98 — large text + AA + dynamic gradient.
//
// MOCK DEPENDENCIES: MainScreenViewModel.init требует ConfigImporting +
// TunnelControlling. Используем stub'ы — snapshot test'у не нужны realistic
// behavior, только presence (D-03 dismiss logic не triggers на static render).

import XCTest
import SwiftUI
import SnapshotTesting
import Foundation
import NetworkExtension
import VPNCore
import ConfigParser
import DesignSystem
@testable import MainScreenFeature

#if os(iOS) || os(tvOS)

@MainActor
final class OnboardingViewSnapshotTests: XCTestCase {

    // MARK: - Stubs

    /// Minimal stub — все методы возвращают пустые ImportResult; не вызываются
    /// в snapshot render path (D-03 `.onChange` не trigger'ится без state mutation).
    private final class StubImporter: ConfigImporting, @unchecked Sendable {
        func importFromRawInput(_ raw: String, source: ImportSource) async throws -> ImportResult {
            ImportResult(supported: [], unsupported: [], failed: [],
                         subscriptionURL: nil, source: source, metadata: nil)
        }
        func importFromPasteboard() async throws -> ImportResult {
            try await importFromRawInput("", source: .pasteboard)
        }
        func importFromQRCode(_ scanned: String) async throws -> ImportResult {
            try await importFromRawInput("", source: .qrCode)
        }
        func loadActiveServer() -> ServerConfig? { nil }
        func countSupportedConfigs() -> Int { 0 }
        func persistKeychainSecret(for server: ImportedServer) throws -> KeychainPersistResult? { nil }
        func buildServerConfig(from server: ImportedServer,
                                id: UUID,
                                subscriptionID: UUID,
                                keychainTag: String?) -> ServerConfig {
            ServerConfig(id: id, name: "stub", host: "stub", port: 0,
                          protocolID: "vless-reality", keychainTag: keychainTag,
                          isSupported: true, subscriptionID: subscriptionID)
        }
        func provisionTunnelProfile(for selectedID: UUID?) async throws {}
        func runIsSupportedUpgrade() async {}
        @MainActor
        func reparseAnyParsedConfig(from cfg: ServerConfig) async -> AnyParsedConfig? { nil }
    }

    /// Stub TunnelControlling — все методы no-op (snapshot test не triggers).
    private final class StubTunnel: TunnelControlling, @unchecked Sendable {
        func connect() async throws -> Date { Date(timeIntervalSince1970: 0) }
        func disconnect() async throws {}
        func startReachability() async {}
        func stopReachability() async {}
        func handleForeground() async {}
    }

    // MARK: - Helpers

    private func freshDefaults() -> UserDefaults {
        let suite = "snapshot-suite-\(UUID().uuidString)"
        let defs = UserDefaults(suiteName: suite)!
        defs.removePersistentDomain(forName: suite)
        return defs
    }

    private func makeOnboardingVM() -> MainScreenViewModel {
        return MainScreenViewModel(
            importer: StubImporter(),
            tunnel: StubTunnel(),
            modelContainer: nil,  // 0 supported → state stays .empty → Onboarding visible
            probeService: nil,
            userDefaults: freshDefaults()
        )
    }

    // MARK: - Tests

    /// DS-11 / M7 / W5+B2 — OnboardingView full screen Dark baseline.
    /// 375×812 iPhone 16 portrait. Locks:
    ///   - Hero text 48pt SF Pro Expanded Semibold (B2 vs titleScreen=16);
    ///   - White "Интернет, каким он " + accent green "должен быть";
    ///   - PrimaryButtonStyle accent pill + SecondaryButtonStyle white pill (M7);
    ///   - DS.Color.canvas background (Dark #000000);
    ///   - Subtitle DS.Typography.bodyDefault + textSecondary.
    func test_onboardingView_hero_dark() {
        let vm = makeOnboardingVM()
        let view = OnboardingView(
            viewModel: vm,
            onPaste: {},
            onScanQR: {},
            onDismiss: {}
        )
        .frame(width: 375, height: 812)
        .environment(\.colorScheme, .dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 1.0,
                perceptualPrecision: 0.98,
                layout: .fixed(width: 375, height: 812)
            )
        )
    }
}

#endif  // os(iOS) || os(tvOS)
