import SwiftUI
import Localization

public struct MainScreenView: View {
    @ObservedObject public var viewModel: MainScreenViewModel
    public init(viewModel: MainScreenViewModel) { self.viewModel = viewModel }

    public var body: some View {
        VStack(spacing: 24) {
            header
            Spacer()
            content
            Spacer()
            footer
        }
        .alert(L10n.alertTunnelErrorTitle,
               isPresented: Binding(
                get: { viewModel.lastError != nil && !viewModel.state.isConnected },
                set: { newValue in if !newValue { viewModel.lastError = nil } }
               )
        ) {
            Button("OK") { viewModel.lastError = nil }
        } message: {
            Text(viewModel.lastError ?? "")
        }
    }

    private var header: some View {
        HStack {
            Text(L10n.appShortName).font(.system(.title2, design: .rounded).bold())
            Spacer()
            StatusPill(state: viewModel.state)
        }
        .padding(.horizontal)
        .padding(.top, 24)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .empty:
            ImportFromClipboardButton(action: viewModel.importFromPasteboard)
        case .idle, .connecting, .connected, .error:
            VStack(spacing: 20) {
                ConnectionButton(state: viewModel.state, action: viewModel.toggleConnection)
                if case .connected(let since) = viewModel.state {
                    ConnectionTimer(since: since)
                }
                if case .error(let msg) = viewModel.state {
                    Text(msg).font(.caption).foregroundStyle(.red).padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let name = viewModel.activeServerName {
            Text(name).font(.caption).foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
    }
}
