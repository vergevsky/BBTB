#!/usr/bin/env swift

/// generate-spki-pin.swift — CLI helper for generating SPKI SHA-256 cert pins
/// compatible with `PinnedSessionDelegate` (Apple-side: SecKeyCopyExternalRepresentation).
///
/// **Usage:**
///   swift scripts/generate-spki-pin.swift --host vpn.vergevsky.ru
///   swift scripts/generate-spki-pin.swift --host vpn.vergevsky.ru --port 443
///
/// **Output:**
///   [DEPTH 0] <hex_hash>  ← leaf certificate (copy this into BootstrapPins.vpnVergevskyRu[0])
///   [DEPTH 1] <hex_hash>  ← intermediate
///   [DEPTH 2] <hex_hash>  ← root
///
/// **Before Phase 12 TestFlight upload:**
///   1. Run: swift scripts/generate-spki-pin.swift --host vpn.vergevsky.ru
///   2. Copy leaf hash hex → convert to [UInt8] array → replace placeholder in:
///      BBTB/Packages/ConfigParser/Sources/ConfigParser/PinStore.swift
///      → BootstrapPins.vpnVergevskyRu[0]
///   3. Copy intermediate/backup hash → replace BootstrapPins.vpnVergevskyRu[1]
///
/// **SPKI format compatibility (RESEARCH.md §Pitfall 2):**
///   This script uses the same Apple pipeline as PinnedSessionDelegate:
///   SecCertificateCopyKey → SecKeyCopyExternalRepresentation → SHA256
///   Output is Apple-native format (NOT OpenSSL SubjectPublicKeyInfo DER with OID prefix).
///   Using OpenSSL to generate pins and this script to verify — they will NOT match.
///   Always use this script for production pin generation (verifies RESEARCH.md Assumption A4).

import Foundation
import Network
import Security
import CryptoKit

// MARK: - Argument Parsing

var host: String?
var port: Int = 443

var args = CommandLine.arguments.dropFirst()
var argIterator = args.makeIterator()

while let arg = argIterator.next() {
    switch arg {
    case "--host":
        host = argIterator.next()
    case "--port":
        if let portStr = argIterator.next(), let portNum = Int(portStr) {
            port = portNum
        }
    default:
        break
    }
}

guard let targetHost = host else {
    fputs("Error: --host <hostname> is required\n", stderr)
    fputs("Usage: swift scripts/generate-spki-pin.swift --host vpn.vergevsky.ru [--port 443]\n", stderr)
    exit(1)
}

// MARK: - TLS Connection via NWConnection

print("Connecting to \(targetHost):\(port) via TLS...")

let endpoint = NWEndpoint.hostPort(
    host: NWEndpoint.Host(targetHost),
    port: NWEndpoint.Port(rawValue: UInt16(port)) ?? 443
)

let tlsOptions = NWProtocolTLS.Options()
// Allow any TLS certificate for inspection (we validate SPKI ourselves)
sec_protocol_options_set_verify_block(
    tlsOptions.securityProtocolOptions,
    { (_, trust, completionHandler) in
        completionHandler(true)  // Accept any cert for inspection
    },
    .global(qos: .userInitiated)
)

let parameters = NWParameters.tls
parameters.defaultProtocolStack.applicationProtocols.insert(
    NWProtocolTLS.Options().applicationProtocol, at: 0
)

let connection = NWConnection(to: endpoint, using: NWParameters(tls: tlsOptions, tcp: .tcp))

let group = DispatchGroup()
group.enter()

var extractedPins: [(depth: Int, hexHash: String)] = []
var connectionError: String?

connection.stateUpdateHandler = { state in
    switch state {
    case .ready:
        // Extract TLS trust from the established connection
        if let tlsMetadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata {
            let trust = sec_protocol_metadata_copy_peer_public_key(tlsMetadata.securityProtocolMetadata)
            // Try to get server trust for certificate chain extraction
            sec_protocol_metadata_access_peer_certificate_chain(
                tlsMetadata.securityProtocolMetadata
            ) { secCertificate in
                // Extract public key from each certificate
                let cert = sec_certificate_copy_ref(secCertificate).takeRetainedValue()
                let depth = extractedPins.count

                guard let pubKey = SecCertificateCopyKey(cert) else {
                    print("[DEPTH \(depth)] ERROR: could not extract public key from certificate")
                    return
                }

                var cfError: Unmanaged<CFError>?
                guard let spkiData = SecKeyCopyExternalRepresentation(pubKey, &cfError) as Data? else {
                    print("[DEPTH \(depth)] ERROR: SecKeyCopyExternalRepresentation failed: \(cfError?.takeRetainedValue().localizedDescription ?? "unknown")")
                    return
                }

                // Compute SHA-256 hash (Apple pipeline — same as PinnedSessionDelegate)
                let hash = SHA256.hash(data: spkiData)
                let hexHash = hash.map { String(format: "%02x", $0) }.joined()
                extractedPins.append((depth: depth, hexHash: hexHash))
            }
        }
        connection.cancel()

    case .failed(let error):
        connectionError = "Connection failed: \(error.localizedDescription)"
        connection.cancel()

    case .cancelled:
        group.leave()

    default:
        break
    }
}

connection.start(queue: .global(qos: .userInitiated))

// Wait with timeout
let result = group.wait(timeout: .now() + 10)
if result == .timedOut {
    fputs("Error: connection to \(targetHost):\(port) timed out after 10 seconds\n", stderr)
    exit(1)
}

if let error = connectionError {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}

if extractedPins.isEmpty {
    fputs("Error: no certificates extracted from TLS handshake\n", stderr)
    fputs("Tip: verify the host is reachable and port is correct\n", stderr)
    exit(1)
}

// MARK: - Output

print("\nSPKI SHA-256 pins for \(targetHost):\(port)")
print(String(repeating: "─", count: 72))
for pin in extractedPins.sorted(by: { $0.depth < $1.depth }) {
    let label = pin.depth == 0 ? "(leaf — copy this for BootstrapPins primary)" :
                pin.depth == 1 ? "(intermediate — copy for BootstrapPins backup)" :
                "(root)"
    print("[DEPTH \(pin.depth)] \(pin.hexHash)  \(label)")
}
print(String(repeating: "─", count: 72))
print("\nTo use in PinStore.swift, convert hex to [UInt8] array:")
if let leafPin = extractedPins.first(where: { $0.depth == 0 }) {
    let bytes = leafPin.hexHash.enumerated()
        .filter { $0.offset % 2 == 0 }
        .compactMap { (_, c) -> String? in
            let startIdx = leafPin.hexHash.index(leafPin.hexHash.startIndex, offsetBy: $0.offset)
            let endIdx = leafPin.hexHash.index(startIdx, offsetBy: 2)
            return String(leafPin.hexHash[startIdx..<endIdx])
        }
        .map { "0x\($0)" }
        .joined(separator: ", ")
    print("// Primary pin (leaf):")
    print("[\(bytes)]")
}
print("\nNOTE: Replace BootstrapPins.vpnVergevskyRu placeholder bytes before Phase 12 TestFlight upload.")
