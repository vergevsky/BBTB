import Foundation

// MARK: - Bootstrap Pins

/// Hardcoded SPKI SHA-256 bootstrap pins for `vpn.vergevsky.ru`.
///
/// **PHASE 12 PREREQUISITE** — replace placeholder bytes with real SPKI hashes from
/// `vpn.vergevsky.ru` production certificate chain. Run:
/// ```bash
/// swift scripts/generate-spki-pin.swift --host vpn.vergevsky.ru
/// ```
/// Copy the leaf-cert hex hash bytes (depth 0) → replace `vpnVergevskyRu[0]`.
/// Copy an intermediate/backup cert hash → replace `vpnVergevskyRu[1]`.
///
/// Memory: `project_phase12_subscription_pins_prerequisite.md` (created in Plan 06 closure).
///
/// **DO NOT SHIP TO PRODUCTION** with placeholder 0x00/0x01 bytes — these will reject ALL
/// real connections because no production cert will have SHA-256(SPKI) = all-zeros.
public enum BootstrapPins {

    /// SPKI SHA-256 pins for `vpn.vergevsky.ru`.
    ///
    /// - Index 0: current primary pin (leaf certificate).
    /// - Index 1: backup pin (intermediate or rotation candidate).
    ///
    /// **PLACEHOLDER bytes** — 0x00 primary, 0x01 backup.
    /// Replace before Phase 12 TestFlight upload via `scripts/generate-spki-pin.swift`.
    public static let vpnVergevskyRu: [[UInt8]] = [
        // Primary pin — PLACEHOLDER (Phase 12 replaces with real SPKI SHA-256 bytes)
        [UInt8](repeating: 0x00, count: 32),
        // Backup pin — PLACEHOLDER (Phase 12 replaces with rotation candidate)
        [UInt8](repeating: 0x01, count: 32),
    ]
}

// MARK: - PinStore

/// Thread-safe immutable store of SPKI SHA-256 hashes per hostname.
///
/// Merges bootstrap hardcoded pins (`BootstrapPins`) with remote signed manifest pins
/// (`PinManifest.spkiSha256Pins ∪ PinManifest.backupPins`).
///
/// **Usage:** `PinnedSessionDelegate` calls `isValid(spkiHash:for:)` to gate TLS connections.
///
/// **Deduplication:** pins are stored as `Set<Data>` per host — duplicates silently dropped.
/// This is correct behavior: manifest may re-include a bootstrap pin (belt + suspenders).
public struct PinStore: Sendable {

    /// Host → set of accepted SPKI SHA-256 Data values (32 bytes each).
    public let pinsByHost: [String: Set<Data>]

    /// Create a PinStore merging bootstrap byte-array pins with hex-encoded manifest pins.
    ///
    /// - Parameter bootstrap: host → array of raw 32-byte SPKI SHA-256 hashes.
    ///   Default: `["vpn.vergevsky.ru": BootstrapPins.vpnVergevskyRu]`.
    /// - Parameter manifestPins: host → array of hex-encoded (64-char) SPKI SHA-256 hashes.
    ///   Sourced from `PinManifest.spkiSha256Pins ∪ PinManifest.backupPins`.
    ///   Invalid hex strings silently skipped (logged via print in debug builds).
    public init(
        bootstrap: [String: [[UInt8]]] = ["vpn.vergevsky.ru": BootstrapPins.vpnVergevskyRu],
        manifestPins: [String: [String]] = [:]
    ) {
        var result: [String: Set<Data>] = [:]

        // Bootstrap: UInt8 arrays → Data
        for (host, pinArrays) in bootstrap {
            var pins = result[host] ?? Set<Data>()
            for pinBytes in pinArrays {
                pins.insert(Data(pinBytes))
            }
            result[host] = pins
        }

        // Manifest: hex strings → Data (skip invalid)
        for (host, hexPins) in manifestPins {
            var pins = result[host] ?? Set<Data>()
            for hexPin in hexPins {
                if let pinData = Data(hex: hexPin) {
                    pins.insert(pinData)
                } else {
                    // Invalid hex — skip with warning (should not happen if manifest is well-formed)
                    #if DEBUG
                    print("[PinStore] WARNING: invalid hex pin '\(hexPin)' for host '\(host)' — skipping")
                    #endif
                }
            }
            result[host] = pins
        }

        pinsByHost = result
    }

    /// Returns `true` iff `spkiHash` is an accepted SPKI SHA-256 hash for `host`.
    ///
    /// - Parameter spkiHash: Raw SHA-256 of `SecKeyCopyExternalRepresentation` bytes (32 bytes).
    /// - Parameter host: Hostname from `URLProtectionSpace.host`.
    /// - Returns: `true` if hash matches any accepted pin for this host; `false` otherwise.
    public func isValid(spkiHash: Data, for host: String) -> Bool {
        guard let pins = pinsByHost[host] else { return false }
        return pins.contains(spkiHash)
    }
}

// MARK: - Hex Parsing Helper

private extension Data {
    /// Parse a hex-encoded string into `Data`. Returns `nil` for invalid input.
    /// Expected format: lowercase or uppercase hex, even number of characters.
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: .whitespaces)
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
