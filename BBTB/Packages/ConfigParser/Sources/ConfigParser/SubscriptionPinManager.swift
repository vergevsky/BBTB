import Foundation
import Crypto

// MARK: - PinManagerError

/// Errors thrown by `SubscriptionPinManager.performBackgroundRefresh`.
public enum PinManagerError: Error, Sendable {
    /// Manifest's `validUntil` is in the past — hard reject per D-12 policy.
    case manifestExpired
    /// Ed25519 signature verification failed — manifest tampered or wrong key.
    case signatureInvalid
    /// JSON decode of manifest data failed.
    case malformedJSON
    /// All mirror URLs failed to fetch (network errors, timeouts).
    case fetchFailed(Error)
}

// MARK: - SubscriptionPinManager

/// Phase 10 DPI-08 / D-12 — cert pin manifest manager.
///
/// Mirrors `RulesEngineCoordinator` actor pattern:
/// - `bootstrap()`: copies `subscription-pins-bootstrap.json` from bundle → App Group cache (idempotent).
/// - `performBackgroundRefresh()`: fetches remote signed manifest + verifies Ed25519 + validUntil → atomic write.
/// - `currentPins(for:)`: returns union of bootstrap pins + cached manifest pins.
///
/// **Ed25519 key:** same admin key as `RulesEngine/PublicKey.swift` (same admin signs both manifests).
/// The 32-byte array is manually mirrored here — update both when rotating the key.
///
/// **validUntil hard reject (D-12):** if manifest expired, throws `PinManagerError.manifestExpired`.
/// This is security-conservative: prefer refusing to update over accepting a stale (potentially-replayed) manifest.
/// App continues to use bootstrap pins as graceful degradation.
///
/// **Re-entry guard:** `isInFlight` prevents concurrent `performBackgroundRefresh` races on cache writes.
public actor SubscriptionPinManager {

    // MARK: - Ed25519 key (mirror of RulesEngine/PublicKey.swift)

    /// 32-byte Ed25519 public key — same bytes as `RulesEngine/PublicKey.swift`.
    ///
    /// **Mirror Phase 8 admin key** — update both here AND in RulesEngine/PublicKey.swift
    /// when rotating the signing key. Doc comment in PublicKey.swift describes rotation strategy.
    ///
    /// **PLACEHOLDER** — same as RulesEngine placeholder. Phase 12 replaces with real admin public key.
    private static let defaultPublicKeyBytes: [UInt8] = [
        0xB5, 0x3F, 0xCF, 0xC3, 0x90, 0x4C, 0x73, 0xBE,
        0xC0, 0x51, 0xF5, 0x20, 0xBA, 0xA1, 0x06, 0xAE,
        0xB4, 0x35, 0xEC, 0xFA, 0x25, 0x89, 0xC2, 0x48,
        0x99, 0x06, 0xF7, 0xC2, 0x43, 0xA3, 0x15, 0x99,
    ]

    // MARK: - Production mirrors

    /// Single production mirror URL for subscription pin manifest.
    ///
    /// RESEARCH.md §Open Questions Q4 recommends same VPS as rules.json endpoint.
    /// Admin deploys manifest + detached .sig alongside rules.json.
    public static let productionMirrors: [URL] = [
        URL(string: "https://vpn.vergevsky.ru/.well-known/subscription-pins.json")!,
    ]

    // MARK: - Injected dependencies

    private let cacheDir: URL
    private let bundleResourceURL: URL?
    private let publicKey: Curve25519.Signing.PublicKey
    private let mirrorURLs: [URL]
    private let fetcher: any SubscriptionURLFetching
    private let clock: () -> Date

    // MARK: - Mutable state (actor-isolated)

    private var cachedManifest: PinManifest?
    private var lastFetchedAt: Date?
    private var isInFlight: Bool = false

    // MARK: - Init

    /// Create a SubscriptionPinManager with injectable dependencies.
    ///
    /// - Parameter cacheDir: directory for `subscription-pins-cached.json`. Caller should pass
    ///   `AppGroupContainer.certPinManifestDirectory` from PacketTunnelKit (D-12 App Group path).
    ///   Tests inject a temp directory. No default — caller must provide explicitly.
    /// - Parameter bundleResourceURL: URL of bootstrap JSON in bundle. `nil` triggers
    ///   `Bundle.module.url(forResource:)` lookup at bootstrap time.
    /// - Parameter publicKeyBytes: 32-byte Ed25519 public key. `nil` → use default (Phase 8 admin key).
    /// - Parameter mirrorURLs: ordered list of mirror endpoints. Defaults to `productionMirrors`.
    /// - Parameter fetcher: injectable network layer. Defaults to `DefaultSubscriptionURLFetcher`.
    /// - Parameter clock: injectable wallclock. Defaults to `Date.init`.
    public init(
        cacheDir: URL,
        bundleResourceURL: URL? = nil,
        publicKeyBytes: [UInt8]?,
        mirrorURLs: [URL] = SubscriptionPinManager.productionMirrors,
        fetcher: any SubscriptionURLFetching = DefaultSubscriptionURLFetcher(),
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.cacheDir = cacheDir
        self.bundleResourceURL = bundleResourceURL
        self.mirrorURLs = mirrorURLs
        self.fetcher = fetcher
        self.clock = clock

        // Construct public key — fallback to default if provided bytes are invalid
        if let bytes = publicKeyBytes,
           let key = try? Curve25519.Signing.PublicKey(rawRepresentation: Data(bytes)) {
            self.publicKey = key
        } else {
            self.publicKey = (try? Curve25519.Signing.PublicKey(
                rawRepresentation: Data(Self.defaultPublicKeyBytes)
            ))!
        }
    }

    // MARK: - bootstrap()

    /// Copy bootstrap pin manifest from bundle → App Group cache (idempotent).
    ///
    /// If cache already exists: loads it into memory (cold-start recovery) — does NOT overwrite.
    /// If no cache: copies bundle resource → cache → decodes into memory.
    ///
    /// **Trust:** bundle resource is protected by Apple code signing (T-10-W4-03 accepted).
    /// No Ed25519 verify on bootstrap path — bootstrap pins are hardcoded in `BootstrapPins` anyway.
    public func bootstrap() async {
        let cachedFile = cacheDir.appendingPathComponent("subscription-pins-cached.json")

        // If already have in-memory manifest — no-op
        if cachedManifest != nil { return }

        // If cache file exists — load from disk (cold-start recovery)
        if FileManager.default.fileExists(atPath: cachedFile.path) {
            if let data = try? Data(contentsOf: cachedFile),
               let manifest = try? makeDecoder().decode(PinManifest.self, from: data) {
                cachedManifest = manifest
            }
            // Already exists — idempotent, do NOT overwrite
            return
        }

        // No cache — copy from bundle resource
        guard let bundleURL = bundleResourceURL
            ?? Bundle.module.url(forResource: "subscription-pins-bootstrap", withExtension: "json")
        else {
            return
        }

        guard let bundleData = try? Data(contentsOf: bundleURL) else { return }

        // Atomic write to cache
        try? bundleData.write(to: cachedFile, options: .atomic)

        // Decode into memory
        if let manifest = try? makeDecoder().decode(PinManifest.self, from: bundleData) {
            cachedManifest = manifest
        }
    }

    // MARK: - performBackgroundRefresh()

    /// Fetch remote signed pin manifest, verify Ed25519 + validUntil, atomically write to cache.
    ///
    /// - Parameter certPinningEnabled: if `false`, returns immediately (toggle off — D-13).
    /// - Throws: `PinManagerError.signatureInvalid`, `.manifestExpired`, `.malformedJSON`, `.fetchFailed`.
    public func performBackgroundRefresh(certPinningEnabled: Bool = true) async throws {
        guard certPinningEnabled else { return }

        // Re-entry guard
        guard !isInFlight else { return }
        isInFlight = true
        defer { isInFlight = false }

        // Sequential mirror fetch (concurrency=1 per DEC-06d-04 pattern)
        var manifestData: Data?
        var sigData: Data?
        var lastError: Error?

        for mirrorURL in mirrorURLs {
            let sigURL = mirrorURL.appendingPathExtension("sig")
            do {
                let manifestResult = try await fetcher.fetch(url: mirrorURL)
                let sigResult = try await fetcher.fetch(url: sigURL)
                manifestData = manifestResult.body
                sigData = sigResult.body
                break
            } catch {
                lastError = error
                continue
            }
        }

        guard let manifest = manifestData, let sig = sigData else {
            throw PinManagerError.fetchFailed(lastError ?? SubscriptionURLFetcher.FetchError.timeout)
        }

        // Ed25519 signature verify — sig must be exactly 64 bytes (RFC 8032)
        guard sig.count == 64, publicKey.isValidSignature(sig, for: manifest) else {
            throw PinManagerError.signatureInvalid
        }

        // JSON decode
        let decoded: PinManifest
        do {
            decoded = try makeDecoder().decode(PinManifest.self, from: manifest)
        } catch {
            throw PinManagerError.malformedJSON
        }

        // validUntil hard reject (D-12 policy — RESEARCH.md recommendation)
        guard decoded.validUntil > clock() else {
            throw PinManagerError.manifestExpired
        }

        // Atomic write to cache
        let cachedFile = cacheDir.appendingPathComponent("subscription-pins-cached.json")
        let cachedSigFile = cacheDir.appendingPathComponent("subscription-pins-cached.json.sig")
        try manifest.write(to: cachedFile, options: .atomic)
        try sig.write(to: cachedSigFile, options: .atomic)

        // Update in-memory state
        cachedManifest = decoded
        lastFetchedAt = clock()
    }

    // MARK: - currentPins(for:)

    /// Returns union of bootstrap hardcoded pins + cached manifest pins for a given host.
    ///
    /// Bootstrap pins are always included (graceful degradation when no manifest cached).
    /// Manifest pins deduplicated via Set.
    public func currentPins(for host: String) async -> Set<Data> {
        var result: Set<Data> = []

        // Bootstrap pins (always included for vpn.vergevsky.ru)
        if host == "vpn.vergevsky.ru" {
            for pinBytes in BootstrapPins.vpnVergevskyRu {
                result.insert(Data(pinBytes))
            }
        }

        // Cached manifest pins (if available and matching host)
        if let manifest = cachedManifest, manifest.host == host {
            let allHexPins = manifest.spkiSha256Pins + manifest.backupPins
            for hexPin in allHexPins {
                if let pinData = Data(hexPin: hexPin) {
                    result.insert(pinData)
                }
            }
        }

        return result
    }

    // MARK: - currentPinStore()

    /// Build a `PinStore` merging bootstrap + cached manifest pins.
    ///
    /// Used by `PinnedSubscriptionURLFetcher` on each fetch.
    public func currentPinStore() async -> PinStore {
        var manifestPins: [String: [String]] = [:]
        if let manifest = cachedManifest {
            manifestPins[manifest.host] = manifest.spkiSha256Pins + manifest.backupPins
        }
        return PinStore(
            bootstrap: ["vpn.vergevsky.ru": BootstrapPins.vpnVergevskyRu],
            manifestPins: manifestPins
        )
    }

    // MARK: - Helpers

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Hex Parsing for Data (internal helper)

private extension Data {
    init?(hexPin: String) {
        let hex = hexPin.trimmingCharacters(in: .whitespaces)
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
