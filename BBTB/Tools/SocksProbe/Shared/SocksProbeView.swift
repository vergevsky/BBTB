import SwiftUI

public struct SocksProbeView: View {
    @StateObject private var viewModel = SocksProbeViewModel()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BBTB SocksProbe")
                .font(.system(.title2, design: .rounded).bold())
            Text("Scan 127.0.0.1 for SOCKS / HTTP-proxy / Tor ports (R1 / SEC-03)")
                .font(.caption)
                .foregroundStyle(.secondary)

            statusRow

            HStack {
                Button(scanButtonTitle, action: startScan)
                    .disabled(scanInProgress)
                Button("Reset", action: viewModel.reset)
                    .disabled(viewModel.state == .idle)
            }

            if !viewModel.summary.isEmpty {
                GroupBox(label: Text("Summary")) {
                    Text(viewModel.summary)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox(label: Text("Ports tested")) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.portResults) { r in
                            HStack {
                                Text(":\(r.port)")
                                    .frame(width: 70, alignment: .leading)
                                Text(statusLabel(r.status))
                                    .foregroundStyle(statusColor(r.status))
                                Spacer()
                                Text("\(r.durationMs) ms")
                                    .foregroundStyle(.secondary)
                                    .font(.caption.monospaced())
                            }
                            .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            GroupBox(label: Text("utun interfaces (R6 check)")) {
                VStack(alignment: .leading, spacing: 4) {
                    if viewModel.interfaces.isEmpty {
                        Text("(no utun* interfaces — VPN not active?)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(viewModel.interfaces) { iface in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading) {
                                    Text("\(iface.name)").font(.caption.monospaced().bold())
                                    Text(iface.addresses.joined(separator: ", "))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(iface.hasPointToPoint ? "POINTOPOINT: YES (R6 FAIL)" : "POINTOPOINT: NO ✓")
                                    .foregroundStyle(iface.hasPointToPoint ? .red : .green)
                                    .font(.caption.monospaced().bold())
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 600)
    }

    // MARK: - Subviews

    private var statusRow: some View {
        HStack {
            Text("Status:").font(.caption)
            switch viewModel.state {
            case .idle:
                Text("Idle").foregroundStyle(.secondary)
            case .scanning(let completed, let total):
                Text("Scanning \(completed)/\(total)")
                    .foregroundStyle(.orange)
                ProgressView()
                    .controlSize(.small)
            case .done:
                Text("Done").foregroundStyle(.green)
            }
        }
    }

    private var scanButtonTitle: String {
        switch viewModel.state {
        case .idle: return "Start Scan"
        case .scanning: return "Scanning…"
        case .done: return "Re-scan"
        }
    }

    private var scanInProgress: Bool {
        if case .scanning = viewModel.state { return true }
        return false
    }

    private func startScan() {
        Task { await viewModel.startScan() }
    }

    private func statusLabel(_ status: PortStatus) -> String {
        switch status {
        case .open: return "OPEN ⚠"
        case .closed: return "closed"
        case .timeout: return "timeout"
        case .error(let msg): return "error: \(msg)"
        }
    }

    private func statusColor(_ status: PortStatus) -> Color {
        switch status {
        case .open: return .red
        case .closed: return .green
        case .timeout: return .secondary
        case .error: return .orange
        }
    }
}
