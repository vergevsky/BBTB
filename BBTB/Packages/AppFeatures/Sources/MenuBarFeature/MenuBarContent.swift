import SwiftUI
import MainScreenFeature
import Localization

public struct MenuBarContent: View {
    @ObservedObject public var viewModel: MainScreenViewModel
    public init(viewModel: MainScreenViewModel) { self.viewModel = viewModel }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.appShortName).font(.headline)
                Spacer()
                StatusBadge(state: viewModel.state)
            }
            Divider()
            switch viewModel.state {
            case .connected(let since):
                ConnectionTimer(since: since)
                Button(L10n.menubarDisconnect, action: viewModel.toggleConnection)
                    .buttonStyle(.borderedProminent)
            case .idle, .error:
                Button(L10n.menubarConnect, action: viewModel.toggleConnection)
                    .buttonStyle(.borderedProminent)
            case .connecting:
                ProgressView()
                    .controlSize(.small)
            case .empty:
                Text(L10n.statusEmpty).foregroundStyle(.secondary)
            }
            Divider()
            if let name = viewModel.activeServerName {
                Text(name).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 280)
    }
}

public extension ConnectionState {
    var menuBarSymbol: String {
        switch self {
        case .empty, .idle: return "bolt.shield"
        case .connecting:   return "bolt.shield.fill"
        case .connected:    return "checkmark.shield.fill"
        case .error:        return "exclamationmark.shield.fill"
        }
    }
}
