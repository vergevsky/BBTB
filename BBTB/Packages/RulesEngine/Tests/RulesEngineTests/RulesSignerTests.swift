import XCTest
import Crypto
@testable import RulesEngine

/// Unit tests для `RulesSigner.verify` — pure-function Ed25519 verify.
///
/// **Test strategy:**
/// Tests cannot depend на real production `PublicKey.publicKeyBytes` (placeholder 0x00..0x1F).
/// Instead — генерируют свежий Ed25519 keypair per test через `Curve25519.Signing.PrivateKey()`,
/// sign known message, и проверяют через `internal verify(message:signature:key:)` overload
/// (added in W1.2 specifically для testability).
///
/// **Production verify path** (`verify(message:signature:)` public overload) тоже covered
/// implicitly: internal overload — implementation, public — thin wrapper, ОБА используют
/// same `guard signature.count == 64` + `isValidSignature(_:for:)` chain.
final class RulesSignerTests: XCTestCase {

    // MARK: Test 1 — valid signature → true

    func test_verify_acceptsValidSignature() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        let message = Data("hello phase 8 rules engine".utf8)
        let signature = try privateKey.signature(for: message)

        XCTAssertEqual(signature.count, 64, "Ed25519 signature must be exactly 64 bytes per RFC 8032")
        XCTAssertTrue(
            RulesSigner.verify(message: message, signature: signature, key: publicKey),
            "Valid Ed25519 signature must verify true under matching public key"
        )
    }

    // MARK: Test 2 — tampered signature → false

    func test_verify_rejectsTamperedSignature() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        let message = Data("hello".utf8)
        let validSignature = try privateKey.signature(for: message)

        // Flip last bit — produces still-64-byte-but-invalid signature.
        var tampered = validSignature
        tampered[tampered.count - 1] ^= 0x01

        XCTAssertEqual(tampered.count, 64, "Tampered signature still 64 bytes")
        XCTAssertFalse(
            RulesSigner.verify(message: message, signature: tampered, key: publicKey),
            "Single-bit-flipped signature must NOT verify"
        )
    }

    // MARK: Test 3 — wrong-length signature → false (without throw)

    func test_verify_rejectsWrongLengthSignature() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        let message = Data("hello".utf8)

        // Test multiple wrong lengths — RulesSigner must guard ALL with early-return false.
        let short = Data(repeating: 0xAB, count: 63)
        let long = Data(repeating: 0xCD, count: 65)
        let empty = Data()
        let huge = Data(repeating: 0xEE, count: 1024)

        XCTAssertFalse(
            RulesSigner.verify(message: message, signature: short, key: publicKey),
            "63-byte signature must reject without crash"
        )
        XCTAssertFalse(
            RulesSigner.verify(message: message, signature: long, key: publicKey),
            "65-byte signature must reject without crash"
        )
        XCTAssertFalse(
            RulesSigner.verify(message: message, signature: empty, key: publicKey),
            "empty signature must reject without crash"
        )
        XCTAssertFalse(
            RulesSigner.verify(message: message, signature: huge, key: publicKey),
            "1024-byte signature must reject without crash"
        )
    }

    // MARK: Test 4 — valid sig for message1 against message2 → false

    func test_verify_rejectsWrongMessage() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        let message1 = Data("original".utf8)
        let message2 = Data("forged".utf8)
        let signatureForM1 = try privateKey.signature(for: message1)

        XCTAssertTrue(
            RulesSigner.verify(message: message1, signature: signatureForM1, key: publicKey),
            "sanity: original message must verify under its signature"
        )
        XCTAssertFalse(
            RulesSigner.verify(message: message2, signature: signatureForM1, key: publicKey),
            "Signature for message1 must NOT verify against message2 (different content)"
        )
    }

    // MARK: Test 5 — valid sig under wrong public key → false

    func test_verify_rejectsWrongPublicKey() throws {
        let priv1 = Curve25519.Signing.PrivateKey()
        let priv2 = Curve25519.Signing.PrivateKey()  // unrelated keypair
        let message = Data("hello".utf8)
        let signatureUnderPriv1 = try priv1.signature(for: message)

        XCTAssertFalse(
            RulesSigner.verify(message: message, signature: signatureUnderPriv1, key: priv2.publicKey),
            "Signature под priv1 must NOT verify под unrelated priv2.publicKey"
        )
    }

    // MARK: Test 6 — empty message + valid sig → true (edge case but Ed25519 supports empty message)

    func test_verify_acceptsValidSignatureOnEmptyMessage() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        let empty = Data()
        let signature = try privateKey.signature(for: empty)

        XCTAssertTrue(
            RulesSigner.verify(message: empty, signature: signature, key: publicKey),
            "Ed25519 must verify signature over empty message (RFC 8032 allows)"
        )
    }
}
