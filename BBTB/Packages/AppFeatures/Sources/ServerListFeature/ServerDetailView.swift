// ServerDetailView.swift — Phase 5 Wave 8 / Task 2.
//
// TRANSP-05 (D-17, D-18): server detail screen with read-only fields + transport Picker.
// Opened via NavigationLink chevron in ServerListSheet.
//
// Sections (Form layout):
//   1. General (L10n.serverDetailGeneralSection):
//      name, host, port, protocol, sni?, latency?, countryCode?
//   2. Protocol parameters (L10n.serverDetailParsedSection, optional):
//      uuid, flow, fingerprint, alpn, publicKey (Reality), shortId (Reality)
//   3. Transport (L10n.serverDetailTransportSection):
//      TransportPicker + footer text

import SwiftUI
import VPNCore
import DesignSystem
import Localization
// Phase 6e Wave 2 Theme D — `import ConfigParser` удалён (Periphery-verified
// unused; ServerDetailView не использует ConfigParser types напрямую).

public struct ServerDetailView: View {
    @ObservedObject public var viewModel: ServerDetailViewModel

    /// 2026-05-16 — inline back via dismiss action (no native navigation chrome,
    /// consistent с ServerListSheet sibling screen).
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: ServerDetailViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 2026-05-16 inline TopBar — matches ServerListSheet header pattern
            // (no native nav bar), prevents layout jump на push/pop transitions.
            // Padding [32,17,16,17] mirrors ServerListSheet header.
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Ph.caretLeft.bold
                        .foregroundStyle(DS.Color.iconSecondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("BBTB.ServerDetail.BackButton")
                .accessibilityLabel(Text(L10n.actionCancel))

                Text(viewModel.server.name)
                    .font(DS.Typography.expanded(16, weight: .semibold))
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(.horizontal, 17)
            .padding(.top, 32)
            .padding(.bottom, 16)

            Form {
            // MARK: Section 1 — General

            Section(L10n.serverDetailGeneralSection) {
                LabeledRow(label: L10n.serverDetailName,
                           value: viewModel.server.name)
                LabeledRow(label: L10n.serverDetailHost,
                           value: viewModel.server.host)
                LabeledRow(label: L10n.serverDetailPort,
                           value: "\(viewModel.server.port)")
                LabeledRow(label: L10n.serverDetailProtocol,
                           value: viewModel.server.protocolDisplayName)
                if let sni = viewModel.server.sni, !sni.isEmpty {
                    LabeledRow(label: "SNI", value: sni)
                }
                if let latency = viewModel.server.lastLatencyMs {
                    LabeledRow(label: L10n.serverDetailLatency,
                               value: "\(latency) ms")
                }
                if let country = viewModel.server.countryCode {
                    LabeledRow(label: "Country",
                               value: "\(viewModel.server.countryFlag) \(country.uppercased())")
                }
            }

            // MARK: Section 2 — Parsed protocol parameters (optional)

            if let details = viewModel.parsedDetails {
                Section(L10n.serverDetailParsedSection) {
                    if let uuid = details.uuid {
                        LabeledRow(label: "UUID", value: uuid.uuidString)
                    }
                    if let flow = details.flow {
                        LabeledRow(label: L10n.serverDetailFlow, value: flow)
                    }
                    LabeledRow(label: L10n.serverDetailFingerprint,
                               value: details.fingerprint)
                    if !details.alpn.isEmpty {
                        LabeledRow(label: "ALPN", value: details.alpn.joined(separator: ", "))
                    }
                    if let publicKey = details.publicKey, !publicKey.isEmpty {
                        LabeledRow(label: L10n.serverDetailPublicKey, value: publicKey)
                    }
                    if let shortId = details.shortId, !shortId.isEmpty {
                        LabeledRow(label: L10n.serverDetailShortId, value: shortId)
                    }
                }
            }

            // MARK: Section 3 — Transport

            Section(
                header: Text(L10n.serverDetailTransportSection),
                footer: Text(L10n.serverDetailTransportFooter)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            ) {
                TransportPicker(selection: $viewModel.selectedTransport)
                    .onChange(of: viewModel.selectedTransport) { _, new in
                        Task { await viewModel.applyTransportSelection(new) }
                    }
            }
        }
        }
        // 2026-05-16 — hide native nav chrome; inline TopBar выше handles back +
        // title визуально consistent с ServerListSheet. Prevents layout shift при
        // push/pop transitions.
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.onAppear()
        }
        .accessibilityIdentifier("BBTB.ServerDetailView")
    }
}

// MARK: - LabeledRow

/// Reusable HStack row: secondary label on the left, selectable primary value on the right.
private struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(DS.Typography.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(DS.Typography.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}
