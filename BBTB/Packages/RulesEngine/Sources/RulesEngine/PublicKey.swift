import Foundation
import Crypto

/// Ed25519 public key (32 raw bytes) для верификации server-signed rules manifest и SRS files.
///
/// **Security model (D-07):**
/// - Public ключ — НЕ secret. Зашит в client binary by design (anti-MITM).
/// - Соответствующий private key хранится ИСКЛЮЧИТЕЛЬНО на VPS администратора.
/// - Один key pair fixes trust в v0.8; key rotation deferred to v1.x
///   (см. Pitfall 5 в `.planning/phases/08-rules-engine-split-tunneling/08-RESEARCH.md`).
///
/// **Rotation strategy (v1.x, NOT in scope for Phase 8):**
/// 1. App build N+1 поддерживает два ключа одновременно (old + new).
/// 2. Manifest подписывается обоими ключами.
/// 3. После 99% migration users → app build N+2 drop'ает old key.
/// Документация: `wiki/rules-engine.md` после Phase 8 closure.
///
/// **W7 invariant (validate-r1-r6.sh extension):** R8 guard requires exactly 32 hex byte
/// literals в `publicKeyBytes` array И rejects all-zero / all-placeholder patterns в production
/// builds (последнее — TODO для W7 task 08-08 — placeholder guard).
///
/// **PHASE 8 W1 placeholder:** `publicKeyBytes` ниже заполнен byte sequence `0x00..0x1F`
/// (32 consecutive integers). Real public key bytes generates developer via:
///
/// ```bash
/// openssl genpkey -algorithm ed25519 -out /tmp/bbtb-rules-private.pem
/// openssl pkey -in /tmp/bbtb-rules-private.pem -pubout -out /tmp/bbtb-rules-public.pem
/// openssl pkey -in /tmp/bbtb-rules-public.pem -pubin -outform DER | tail -c 32 | xxd -i
/// ```
///
/// Output — 32 `0xNN,` элементов — заменяет placeholder ниже. Private key передаётся на VPS
/// в зашифрованном виде (1Password / SecureKeep), **никогда не commit в repo**. Test signing
/// в W1.4 использует test-only keypair, в production binary не попадает.
///
/// **NOT for production до замены placeholder на real bytes** — W7 (08-08-PLAN.md)
/// добавит R12 guard в validate-r1-r6.sh, отвергающий sequential-byte pattern.
enum PublicKey {

    /// Raw 32-byte Ed25519 public key.
    ///
    /// **PLACEHOLDER** sequence `0x00..0x1F`. Replace before shipping production builds.
    /// Tests in W1.4 NOT depend on these bytes — they inject test public key через
    /// internal verify overload (см. RulesSigner.verify(message:signature:key:)).
    private static let publicKeyBytes: [UInt8] = [
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
        0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
    ]

    /// Materialized `Curve25519.Signing.PublicKey` for use в `isValidSignature(_:for:)`.
    ///
    /// `try!` is justified — `publicKeyBytes` is a 32-element compile-time constant; failure
    /// to construct ключ означает build bug (wrong byte count или Crypto API regression),
    /// которая ловится unit-тестом `test_publicKey_constructsValidEd25519Key` если он будет
    /// добавлен в W1.4 (current scope only covers signer-level tests since PublicKey internal).
    static let publicKey: Curve25519.Signing.PublicKey = {
        try! Curve25519.Signing.PublicKey(rawRepresentation: Data(publicKeyBytes))
    }()
}
