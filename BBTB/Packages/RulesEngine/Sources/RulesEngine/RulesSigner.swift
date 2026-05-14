import Foundation
import Crypto

// MARK: - Protocol abstraction (Phase 8 W2)

/// Protocol для test-injectable signature verify в `RulesEngineCoordinator`.
///
/// Production callers используют `DefaultRulesSigner` (thin delegation к `RulesSigner.verify`);
/// tests инжектят stubs (`AlwaysValidVerifier` / `AlwaysInvalidVerifier`) → decouple pipeline
/// tests от production placeholder public key (`PublicKey.publicKeyBytes` сейчас 0x00..0x1F;
/// W7 заменит на real bytes от admin's Ed25519 keypair).
///
/// **Rationale (Rule 3 auto-fix):** без injection success-path coordinator tests требовали
/// бы доступ к admin's private key. Это нарушает security model + makes tests fragile
/// против rotation. Injection — clean test boundary, production path unchanged.
public protocol SignatureVerifierProtocol: Sendable {
    func verify(message: Data, signature: Data) -> Bool
}

/// Production verifier — direct delegation к `RulesSigner.verify`.
public struct DefaultRulesSigner: SignatureVerifierProtocol {
    public init() {}
    public func verify(message: Data, signature: Data) -> Bool {
        RulesSigner.verify(message: message, signature: signature)
    }
}

/// Ed25519 detached signature verify через swift-crypto.
///
/// **Pure function.** Never throws. Never mutates global state. Thread-safe by design.
/// Возвращает `false` на любую invalid input (wrong length / tampered bytes / unrelated key
/// для известного message). Защищает CryptoKit от попыток парсить garbage byte sequences.
///
/// **Performance:** `< 5 ms` per verify на A13+ для 50-KB message. Curve25519 hardware
/// accelerated через CoreCrypto on Apple platforms (swift-crypto re-exports CryptoKit там).
/// Подробности — `.planning/phases/08-rules-engine-split-tunneling/08-RESEARCH.md` § Pattern 2.
///
/// **Architectural placement** (D-07 + Architectural Responsibility Map):
/// Verify живёт ТОЛЬКО в main app — Network Extension только reads уже-verified SRS files
/// из App Group container (writer = main app gates trust path through this primitive).
public enum RulesSigner {

    /// Verify Ed25519 detached signature against `PublicKey.publicKey`.
    ///
    /// - Parameter message: byte content to verify (manifest JSON, `.srs` file bytes, ...).
    /// - Parameter signature: detached signature payload. MUST be exactly 64 bytes
    ///   (Ed25519 fixed signature length per RFC 8032).
    /// - Returns: `true` iff signature is a valid Ed25519 signature for `message` под нашим
    ///   hardcoded public key. `false` otherwise (wrong length / tamper / unrelated key).
    ///
    /// **Never throws** — invalid inputs return `false`; CryptoKit's `isValidSignature(_:for:)`
    /// сам по себе non-throwing для wrong-content cases.
    public static func verify(message: Data, signature: Data) -> Bool {
        return verify(message: message, signature: signature, key: PublicKey.publicKey)
    }

    /// Internal overload — позволяет unit-тестам инжектить test-only public key
    /// (см. RulesSignerTests fixture pattern). Production callers use the public overload above.
    ///
    /// - Parameter key: any `Curve25519.Signing.PublicKey`. В тестах — derived from test
    ///   keypair; в production — re-derived from `PublicKey.publicKeyBytes` constant.
    static func verify(message: Data, signature: Data, key: Curve25519.Signing.PublicKey) -> Bool {
        // Early-return for wrong-length signatures — avoid passing garbage to CryptoKit.
        // Ed25519 detached signature is fixed 64 bytes per RFC 8032 §3.3.
        guard signature.count == 64 else {
            RulesEngineLogger.signer.error(
                "RulesSigner.verify rejected: signature.count=\(signature.count, privacy: .public) ≠ 64"
            )
            return false
        }

        let isValid = key.isValidSignature(signature, for: message)
        if !isValid {
            RulesEngineLogger.signer.warning(
                "RulesSigner.verify failed for message.count=\(message.count, privacy: .public)"
            )
        }
        return isValid
    }
}
