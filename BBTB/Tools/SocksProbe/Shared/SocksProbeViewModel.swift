import Foundation
import SwiftUI

@MainActor
public final class SocksProbeViewModel: ObservableObject {
    public enum ScanState: Equatable {
        case idle
        case scanning(completed: Int, total: Int)
        case done
    }

    @Published public private(set) var state: ScanState = .idle
    @Published public private(set) var portResults: [PortResult] = []
    @Published public private(set) var interfaces: [InterfaceSnapshot] = []
    @Published public private(set) var summary: String = ""

    public init() {}

    public func startScan() async {
        guard case .idle = state else { return }
        let ports = RKNPorts.phase1
        state = .scanning(completed: 0, total: ports.count)
        portResults = []
        let results = await PortProber.probeAll(ports)
        portResults = results
        interfaces = InterfaceInspector.snapshotUtunInterfaces()
        let open = results.filter { $0.status == .open }
        let pointToPointUtuns = interfaces.filter { $0.hasPointToPoint }
        summary = """
        Ports tested: \(results.count)
        Open: \(open.count)
        utun interfaces: \(interfaces.count)
        utun with POINTOPOINT: \(pointToPointUtuns.count)
        R1 verdict: \(open.isEmpty ? "PASS — no ports respond" : "FAIL — open ports detected")
        R6 verdict: \(pointToPointUtuns.isEmpty ? "PASS — no IFF_POINTOPOINT on utun*" : "FAIL — IFF_POINTOPOINT detected")
        """
        state = .done
    }

    public func reset() {
        state = .idle
        portResults = []
        interfaces = []
        summary = ""
    }
}
