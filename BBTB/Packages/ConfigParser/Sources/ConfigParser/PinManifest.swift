import Foundation

/// Phase 10 DPI-08 / D-12 — cert pin manifest schema.
///
/// Server-side signed manifest for SPKI SHA-256 pin distribution.
/// Follows the same snake_case JSON convention as `RulesManifest`.
///
/// **Trust path:**
/// 1. Admin generates SPKI pins via `scripts/generate-spki-pin.swift`.
/// 2. Admin creates `subscription-pins.json` and signs with Ed25519 private key.
/// 3. App fetches manifest + detached `.sig` → `SubscriptionPinManager.performBackgroundRefresh`
///    verifies signature + validUntil before accepting.
/// 4. Accepted manifest pins merged with bootstrap hardcoded pins in `PinStore`.
///
/// **validUntil hard reject** — if manifest expired, pinning falls back to bootstrap-only pins.
/// This is a security-conservative choice: prefer rejection over trusting a stale manifest.
/// Admin must rotate manifest before expiry (RESEARCH.md D-12 recommendation).
public struct PinManifest: Codable, Sendable, Equatable {

    /// Monotonically-increasing manifest version.
    public let version: Int

    /// Manifest validity start date (ISO 8601).
    public let validFrom: Date

    /// Manifest expiry date (ISO 8601). Hard rejected if `validUntil < now` — D-12 policy.
    public let validUntil: Date

    /// Hostname this manifest applies to (e.g. `"vpn.vergevsky.ru"`).
    public let host: String

    /// Primary SPKI SHA-256 pins — hex-encoded, lowercase, 64 chars each (32 bytes).
    /// Generated via `scripts/generate-spki-pin.swift` → Apple SecKeyCopyExternalRepresentation pipeline.
    public let spkiSha256Pins: [String]

    /// Backup SPKI SHA-256 pins (rotation candidates). Same format as `spkiSha256Pins`.
    public let backupPins: [String]

    public init(
        version: Int,
        validFrom: Date,
        validUntil: Date,
        host: String,
        spkiSha256Pins: [String],
        backupPins: [String]
    ) {
        self.version = version
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.host = host
        self.spkiSha256Pins = spkiSha256Pins
        self.backupPins = backupPins
    }

    enum CodingKeys: String, CodingKey {
        case version
        case validFrom = "valid_from"
        case validUntil = "valid_until"
        case host
        case spkiSha256Pins = "spki_sha256_pins"
        case backupPins = "backup_pins"
    }
}
