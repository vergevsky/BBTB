// TransportPicker.swift — Phase 5 Wave 8 / Task 2.
//
// TRANSP-05: Transport Picker component for ServerDetailView.
// Provides TransportSelection enum (Picker model) and TransportPicker view
// using DesignSystem styling.

import SwiftUI
import VPNCore
// Phase 6e Wave 2 Theme D — `import DesignSystem` удалён (Periphery-verified
// unused; TransportPicker не использует DS.* types напрямую).
import Localization

// MARK: - TransportSelection

/// UI-level transport selection enum for the Transport Picker in ServerDetailView.
///
/// Maps to/from `TransportConfig?` (D-19):
/// - `.auto` ↔ `nil` (use URI-derived transport)
/// - `.tcp` ↔ `.tcp`
/// - `.ws` ↔ `.ws(path:"/", host:"")` — coarse override (Phase 5)
/// - `.grpc` ↔ `.grpc(serviceName:"TunService")`
/// - `.http` ↔ `.http(path:"/")`
/// - `.httpUpgrade` ↔ `.httpUpgrade(path:"/", host:"")`
///
/// **Phase 5 Picker provides COARSE override** — user selects transport type but does NOT
/// edit path/host/serviceName. URI-derived values are lost when override is applied.
/// Wave 10 (Advanced settings) will expose per-field editing.
public enum TransportSelection: Hashable, Sendable {
    case auto
    case tcp
    case ws
    case grpc
    case http
    case httpUpgrade

    /// Maps a `TransportConfig?` to the Picker selection.
    /// nil → .auto; non-nil → corresponding case.
    public static func from(_ override: TransportConfig?) -> TransportSelection {
        guard let override else { return .auto }
        switch override {
        case .tcp:         return .tcp
        case .ws:          return .ws
        case .grpc:        return .grpc
        case .http:        return .http
        case .httpUpgrade: return .httpUpgrade
        }
    }

    /// Maps Picker selection to a `TransportConfig?` for persisting in `ServerConfig.transportOverride`.
    /// `.auto` → nil (remove override); others → TransportConfig with Phase 5 defaults.
    public func toOverride() -> TransportConfig? {
        switch self {
        case .auto:        return nil
        case .tcp:         return .tcp
        case .ws:          return .ws(path: "/", host: "")           // user-editable path/host — Wave 10
        case .grpc:        return .grpc(serviceName: "TunService")   // sing-box default
        case .http:        return .http(path: "/")
        case .httpUpgrade: return .httpUpgrade(path: "/", host: "")
        }
    }
}

// MARK: - TransportPicker View

/// DesignSystem-styled `Picker` for selecting transport override in ServerDetailView.
///
/// Binds to `TransportSelection` — caller is responsible for persisting on change
/// (see `ServerDetailViewModel.applyTransportSelection(_:)`).
public struct TransportPicker: View {
    @Binding public var selection: TransportSelection

    public init(selection: Binding<TransportSelection>) {
        self._selection = selection
    }

    public var body: some View {
        Picker(selection: $selection) {
            Text(L10n.serverDetailTransportAuto).tag(TransportSelection.auto)
            Text(L10n.transportLabelTcp).tag(TransportSelection.tcp)
            Text(L10n.transportLabelWebSocket).tag(TransportSelection.ws)
            Text(L10n.transportLabelGrpc).tag(TransportSelection.grpc)
            Text(L10n.transportLabelHttp2).tag(TransportSelection.http)
            Text(L10n.transportLabelHttpUpgrade).tag(TransportSelection.httpUpgrade)
        } label: {
            Text(L10n.serverDetailTransport)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("BBTB.ServerDetail.TransportPicker")
    }
}
