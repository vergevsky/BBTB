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
        0xB5, 0x3F, 0xCF, 0xC3, 0x90, 0x4C, 0x73, 0xBE,
        0xC0, 0x51, 0xF5, 0x20, 0xBA, 0xA1, 0x06, 0xAE,
        0xB4, 0x35, 0xEC, 0xFA, 0x25, 0x89, 0xC2, 0x48,
        0x99, 0x06, 0xF7, 0xC2, 0x43, 0xA3, 0x15, 0x99,
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
