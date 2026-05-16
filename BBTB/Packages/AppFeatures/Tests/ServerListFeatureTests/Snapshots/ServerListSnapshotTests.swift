// ServerListSnapshotTests.swift — Phase 12 / Plan 12-02 / Task 8 /
// DS-12 (ServerRow) + DS-13 (AutoCell) + DS-14 (ServerListSheet 32pt corners
// W5 fix #1) + DS-15.
//
// Snapshot baselines:
//   - test_serverRow_default_dark / _selected_dark — 2 ServerRow state'а
//     (DS-12 tokens align + accent selected background).
//   - test_autoCell_default_dark / _selected_dark — 2 AutoCell state'а
//     (DS-13 24pt section radius + accent/surfaceSunken fill).
//   - test_serverListSheet_corners_dark — W5 fix #1: locks UnevenRoundedRectangle
//     32pt top corners (DS-14). Render minimal wrapper view (NavigationStack-free
//     mini-mock) с тем же clipShape chain что production ServerListSheet.swift
//     L209-221 — full ServerListSheet требует ViewModel + ModelContainer + 7
//     transitive deps, что не нужно для locks-corner-radius testа.
//
// PLATFORM GATE: iOS/tvOS only (`.image(layout:)` SwiftUI.View ⇒ UIImage).
//
// PERCEPTUAL PRECISION (UI-SPEC §5):
//   - 0.98 для text + AA (ServerRow / AutoCell)
//   - 0.98 для corner anti-aliasing (sheet corners)
//
// N2 fixture: ServerRowFixtures.swift (этот же каталог) — deterministic
// ServerConfig + completed PingState чтобы baseline PNG не дрейфовал.

import XCTest
import SwiftUI
import SnapshotTesting
import DesignSystem
import VPNCore
@testable import ServerListFeature

#if os(iOS) || os(tvOS)

@MainActor
final class ServerListSnapshotTests: XCTestCase {

    // MARK: - ServerRow

    /// DS-12 — ServerRow default state on surface background.
    /// 375pt width × 56pt minHeight; ping completed (28ms) для deterministic
    /// LatencyBadge render.
    func test_serverRow_default_dark() {
        let view = ServerRow(
            server: ServerRowFixtures.sample,
            isSelected: false,
            pingState: ServerRowFixtures.completedPing,
            onTap: {},
            onDelete: {},
            onDetailTap: {}
        )
        .frame(width: 375, height: 56)
        .background(DS.Color.surface)
        .preferredColorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 1.0,
                perceptualPrecision: 0.98,
                layout: .fixed(width: 375, height: 56)
            )
        )
    }

    /// DS-12 / M8 — ServerRow selected state. Locks accent background +
    /// iconMuted checkmark/chevron.
    func test_serverRow_selected_dark() {
        let view = ServerRow(
            server: ServerRowFixtures.sample,
            isSelected: true,
            pingState: ServerRowFixtures.completedPing,
            onTap: {},
            onDelete: {},
            onDetailTap: {}
        )
        .frame(width: 375, height: 56)
        .background(DS.Color.surface)
        .preferredColorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 1.0,
                perceptualPrecision: 0.98,
                layout: .fixed(width: 375, height: 56)
            )
        )
    }

    // MARK: - AutoCell

    /// DS-13 — AutoCell default state. Locks 24pt section radius +
    /// surfaceSunken fill + iconSecondary bolt-icon.
    func test_autoCell_default_dark() {
        let view = AutoCell(isSelected: false, onTap: {})
            .frame(width: 375, height: 80)
            .background(DS.Color.surface)
            .preferredColorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 1.0,
                perceptualPrecision: 0.98,
                layout: .fixed(width: 375, height: 80)
            )
        )
    }

    /// DS-13 / M10 — AutoCell selected state. Locks accent fill +
    /// iconPrimary bolt + textPrimary subtitle opacity 0.8.
    func test_autoCell_selected_dark() {
        let view = AutoCell(isSelected: true, onTap: {})
            .frame(width: 375, height: 80)
            .background(DS.Color.surface)
            .preferredColorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 1.0,
                perceptualPrecision: 0.98,
                layout: .fixed(width: 375, height: 80)
            )
        )
    }

    // MARK: - ServerListSheet corners (W5 fix #1)

    /// DS-14 / M9 / W5 — locks UnevenRoundedRectangle 32pt top corners.
    /// Minimal wrapper view с тем же clipShape chain что production
    /// ServerListSheet.swift L209-221. Full ServerListSheet требует
    /// ViewModel + ModelContainer + transitive deps; mini-mock достаточен
    /// для corners-only baseline (W5 sampling continuity gap closure).
    /// Snapshot 375×120 — захватывает верхнюю часть с radius'ами.
    func test_serverListSheet_corners_dark() {
        let mockSheetTop = VStack(spacing: 0) {
            // Mimics production drag-indicator area + first row of content.
            Color.clear.frame(height: 8)  // drag indicator gap
            Rectangle()
                .fill(DS.Color.surface)
                .frame(height: 112)
        }
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
        .frame(width: 375, height: 120)
        .background(DS.Color.canvas)
        .preferredColorScheme(.dark)

        assertSnapshot(
            of: mockSheetTop,
            as: .image(
                precision: 1.0,
                perceptualPrecision: 0.98,
                layout: .fixed(width: 375, height: 120)
            )
        )
    }
}

#endif  // os(iOS) || os(tvOS)
