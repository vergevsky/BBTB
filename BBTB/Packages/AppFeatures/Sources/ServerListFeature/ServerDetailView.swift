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
import ConfigParser

public struct ServerDetailView: View {
    @ObservedObject public var viewModel: ServerDetailViewModel

    public init(viewModel: ServerDetailViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
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
        .navigationTitle(viewModel.server.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
