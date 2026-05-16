// SpinnerSnapshotTests.swift — Phase 12 / Plan 12-02 / Task 6 / DS-08 / M6.
//
// Snapshot baseline для BBTBSpinner Dark mode frozen-frame (rotation=0°).
// perceptualPrecision 0.97 per UI-SPEC §5 для AngularGradient stroke
// (anti-aliasing на градиенте).
//
// PLATFORM GATE (Phase 12 Plan 12-01 Task 5 inherited): swift-snapshot-testing's
// `Snapshotting where Value: SwiftUI.View, Format == UIImage` только iOS/tvOS;
// macOS host skip. Реальный assert через iOS Simulator destination.
//
// ANTI-FLAKE NOTE (RESEARCH §2.4 + Plan 12-02 Task 6 N3 protocol): SwiftUI
// `.onAppear` запускает `withAnimation`, что делает rotation timing зависимым
// от render schedule. Для стабильности — initial snapshot frame захватывается
// до того, как onAppear успевает применить withAnimation (`@State angle = 0`
// initial value renders to rotationEffect(0°)). Если flake появляется на
// CI/local cycle — обернуть BBTBSpinner в `.transaction { $0.disablesAnimations
// = true }` для snapshot test. Executor валидирует через 3 повторных пробега.
//
// RECORD PROTOCOL (N3 — env-var based, no manual isRecording uncomment cycle):
//   - Default: library default `record: .missing` (создаёт baseline только если
//     нет; existing PNG не overwrite'ит).
//   - First-time baseline: первый прогон FAIL'ит "No reference was found"; PNG
//     записывается под `__Snapshots__/SpinnerSnapshotTests/`; коммитим;
//     повторный прогон PASS.
//   - Full re-record (когда визуал меняется): `SNAPSHOT_TESTING_RECORD=1
//     xcodebuild test ...`.

import XCTest
import SwiftUI
import SnapshotTesting
@testable import DesignSystem

#if os(iOS) || os(tvOS)

@MainActor
final class SpinnerSnapshotTests: XCTestCase {

    /// DS-08 / M6 — BBTBSpinner Dark frozen-frame (rotation=0°).
    /// 280pt diameter + 6pt lineWidth + speed 1.2s match production defaults
    /// (ConnectionButton .overlay использует `diameter + 24 = 304pt` runtime,
    /// snapshot тестит base 280pt чтобы isolated component fidelity locked).
    func testSpinner280pt_darkMode_frozen() {
        let view = BBTBSpinner(diameter: 280, lineWidth: 6, speed: 1.2)
            .frame(width: 320, height: 320)
            .background(SwiftUI.Color.black)
            .preferredColorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 1.0,
                perceptualPrecision: 0.97,
                layout: .fixed(width: 320, height: 320)
            )
        )
    }
}

#endif  // os(iOS) || os(tvOS)
