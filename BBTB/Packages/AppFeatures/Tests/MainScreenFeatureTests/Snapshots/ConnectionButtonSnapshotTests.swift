// ConnectionButtonSnapshotTests.swift — Phase 12 / Plan 12-02 / Task 8 /
// DS-08 + DS-09 + M3 + M6 + UX-09.
//
// Snapshot baselines для ConnectionButton 4 states (idle/connecting/connected/
// error) compact + 1 regular size class (W1 fix для DS-05 regular coverage).
//
// PLATFORM GATE (inherited Plan 12-01 Task 5 / RESEARCH §6.4-6.5): swift-
// snapshot-testing `.image(layout:)` extension только iOS/tvOS на SwiftUI.View.
// macOS host skip. Реальный assert через iOS Simulator destination
// (`xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 16'`).
//
// PERCEPTUAL PRECISION (UI-SPEC §5):
//   - 1.0 для solid fill (.idle/.connected/.error — Circle с одним color)
//   - 0.97 для .connecting (BBTBSpinner AngularGradient stroke — anti-alias
//     на градиенте)
//
// ANTI-FLAKE (Plan 12-02 Task 6 + N3 protocol): .connecting test использует
// `.transaction { $0.disablesAnimations = true }` чтобы исключить race с
// `withAnimation(.linear.repeatForever)` rotation на initial render frame.
//
// RECORD PROTOCOL (N3 env-var):
//   - Default `record: .missing` — первый прогон создаёт PNG; коммитим;
//     повторный прогон PASS.
//   - Full re-record: `SNAPSHOT_TESTING_RECORD=1 xcodebuild test ...`.

import XCTest
import SwiftUI
import SnapshotTesting
import DesignSystem
import VPNCore
@testable import MainScreenFeature

#if os(iOS) || os(tvOS)

@MainActor
final class ConnectionButtonSnapshotTests: XCTestCase {

    /// DS-09 / M3 — .idle compact (default size class) on Dark canvas.
    /// fillColor = DS.Color.controlIdle (#222222 Dark); power-icon visible
    /// (Phase 12 .opacity(1)); diameter = 280pt (compact).
    func test_connectionButton_idle_dark() {
        let view = ConnectionButton(state: .idle, action: {})
            .frame(width: 320, height: 320)
            .background(DS.Color.canvas)
            .preferredColorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 1.0,
                perceptualPrecision: 1.0,
                layout: .fixed(width: 320, height: 320)
            )
        )
    }

    /// DS-09 / M6 — .connecting compact: fillColor = controlIdle + BBTBSpinner
    /// ring AROUND Circle (diameter+24=304pt). Anti-flake disablesAnimations.
    /// perceptualPrecision 0.97 для AngularGradient stroke anti-aliasing.
    func test_connectionButton_connecting_dark() {
        let view = ConnectionButton(state: .connecting, action: {})
            .frame(width: 360, height: 360)
            .background(DS.Color.canvas)
            .preferredColorScheme(.dark)
            .transaction { transaction in
                transaction.disablesAnimations = true
            }

        assertSnapshot(
            of: view,
            as: .image(
                precision: 1.0,
                perceptualPrecision: 0.97,
                layout: .fixed(width: 360, height: 360)
            )
        )
    }

    /// DS-09 / M3 — .connected compact: fillColor = DS.Color.accent (#14664B
    /// Dark==Light per Phase 11 designer-decision). Deterministic `since` Date.
    func test_connectionButton_connected_dark() {
        let view = ConnectionButton(
            state: .connected(since: Date(timeIntervalSince1970: 0)),
            action: {}
        )
        .frame(width: 320, height: 320)
        .background(DS.Color.canvas)
        .preferredColorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 1.0,
                perceptualPrecision: 1.0,
                layout: .fixed(width: 320, height: 320)
            )
        )
    }

    /// DS-09 / M3 — .error compact: fillColor = DS.Color.error (#661414 Dark).
    func test_connectionButton_error_dark() {
        let view = ConnectionButton(
            state: .error(message: "Тестовая ошибка"),
            action: {}
        )
        .frame(width: 320, height: 320)
        .background(DS.Color.canvas)
        .preferredColorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 1.0,
                perceptualPrecision: 1.0,
                layout: .fixed(width: 320, height: 320)
            )
        )
    }

    /// DS-05 / W1 fix — .idle на regular size class (iPad / Mac Catalyst).
    /// Locks regularDiameter=320pt + regularIcon=128pt без этого теста только
    /// compact path validate'ится через snapshots (revision iteration 1 W1 gap
    /// closure).
    func test_connectionButton_idle_regular() {
        let view = ConnectionButton(state: .idle, action: {})
            .environment(\.horizontalSizeClass, .regular)
            .frame(width: 360, height: 360)
            .background(DS.Color.canvas)
            .preferredColorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 1.0,
                perceptualPrecision: 1.0,
                layout: .fixed(width: 360, height: 360)
            )
        )
    }
}

#endif  // os(iOS) || os(tvOS)
