import Foundation

// MARK: - Bootstrap Pins

/// Hardcoded SPKI SHA-256 bootstrap pins for `vpn.vergevsky.ru`.
///
/// **v1.0 STATUS (2026-05-16):** SPKI certificate pinning **deferred to v1.1+**.
/// Production app uses `DefaultSubscriptionURLFetcher` (standard HTTPS + ATS + public
/// CA validation) для всех user-facing subscription URL fetches. Это уровень
/// безопасности равный банковским приложениям на iOS without custom pinning.
///
/// `PinnedSubscriptionURLFetcher` существует в codebase (Phase 10 DPI-08) но не
/// wired в production code paths — `SubscriptionPinManager.performBackgroundRefresh`
/// не вызывается из live production code (verified 2026-05-16 grep).
///
/// **v1.1+ enhancement plan:**
/// 1. Generate real pins: `swift scripts/generate-spki-pin.swift --host vpn.vergevsky.ru`
/// 2. Replace placeholder bytes ниже на real SPKI SHA-256 (leaf + intermediate).
/// 3. Wire `PinnedSubscriptionURLFetcher` в production через `ServerListViewModel`
///    constructor + Settings toggle `certPinningEnabled` (default ON).
/// 4. Add cert-rotation runbook (когда обновляем сертификат — обновляем primary +
///    оставляем старый как backup до следующей rotation).
///
/// **Why deferred:** Phase 12 UAT verified app работает корректно с standard HTTPS
/// для все user flows. Cert pinning — defence-in-depth против compromised public CA
/// (исторически редкий риск); custom root CA MITM (jailbreak / corporate Wi-Fi —
/// out of v1.0 threat model для regular App Store users).
///
/// Memory: `project_phase13_subscription_pins_prerequisite.md` (downgraded to v1.1+).
public enum BootstrapPins {

    /// SPKI SHA-256 pins for `vpn.vergevsky.ru`.
    ///
    /// - Index 0: primary pin slot (leaf certificate).
    /// - Index 1: backup pin slot (intermediate or rotation candidate).
    ///
    /// **v1.0:** Placeholder 0x00/0x01 bytes. **DEAD CODE** — никакой production
    /// code path не использует этот PinStore для cert validation. Subscription
    /// fetch использует `DefaultSubscriptionURLFetcher` (standard HTTPS).
    ///
    /// **v1.1+:** Replace via `scripts/generate-spki-pin.swift` + wire
    /// `PinnedSubscriptionURLFetcher` в production fetcher injection.
    public static let vpnVergevskyRu: [[UInt8]] = [
        // Primary pin — v1.0 placeholder; v1.1+ real SPKI SHA-256 bytes
        [UInt8](repeating: 0x00, count: 32),
        // Backup pin — v1.0 placeholder; v1.1+ rotation candidate
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
