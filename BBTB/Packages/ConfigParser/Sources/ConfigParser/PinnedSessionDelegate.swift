import Foundation
import Crypto
import Security

/// Phase 10 DPI-08 / D-11 — SPKI SHA-256 cert pinning URLSession delegate.
///
/// Implements Apple-standard TLS certificate validation pipeline:
/// 1. `SecTrustEvaluateWithError` — system trust validation (CA chain, hostname, expiry) FIRST.
/// 2. `SecTrustCopyCertificateChain` — enumerate all certs in server chain.
/// 3. `SecCertificateCopyKey` + `SecKeyCopyExternalRepresentation` — extract raw key bytes.
/// 4. `SHA256.hash(data:)` — compute SPKI hash (matches Apple client format, NOT OpenSSL DER).
/// 5. `PinStore.isValid(spkiHash:for:)` — gate connection on pin match.
///
/// **Scope (D-13):** Main app only. Network Extension does NOT use cert pinning —
/// sing-box handles its own TLS. Only subscription URL fetch is pinned.
///
/// **Pitfall: SPKI format (RESEARCH.md §Pitfall 2):**
/// `SecKeyCopyExternalRepresentation` returns Apple-native format:
/// - EC keys: ANSI X9.63 uncompressed point (65 bytes for P-256).
/// - RSA keys: PKCS#1 DER.
/// This is NOT the same as OpenSSL's SubjectPublicKeyInfo DER (which includes OID prefix).
/// The `scripts/generate-spki-pin.swift` CLI uses the same Apple pipeline — ensuring
/// A4 compatibility (RESEARCH.md Assumptions Log).
///
/// **Delegate retention:** URLSession strongly retains its delegate (Apple-documented).
/// `PinnedSubscriptionURLFetcher` creates a session-per-request with `defer { session.invalidateAndCancel() }`.
public final class PinnedSessionDelegate: NSObject, URLSessionDelegate {

    private let pinStore: PinStore

    public init(pinStore: PinStore) {
        self.pinStore = pinStore
        super.init()
    }

    // MARK: - URLSessionDelegate

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Step 1: Only handle serverTrust challenges — delegate all others to default handling.
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Step 2: Guard nil serverTrust (should not happen for HTTPS, but defensive).
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Step 3: CRITICAL pre-check — system trust validation BEFORE pin matching.
        // This blocks expired certs, wrong hostname, untrusted root CA — all before we
        // even look at pins. Without this, a self-signed cert with a known SPKI could bypass
        // standard TLS validation (T-10-W4-02 mitigation).
        var cfError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &cfError) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // Step 4: Enumerate certificate chain.
        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Step 5: For each cert in chain, extract SPKI hash and check against PinStore.
        for cert in chain {
            guard let publicKey = SecCertificateCopyKey(cert) else { continue }
            guard let spkiData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { continue }

            // Compute SHA-256 of raw SPKI bytes (Apple format — compatible with generate-spki-pin.swift).
            let spkiHash = Data(SHA256.hash(data: spkiData))

            if pinStore.isValid(spkiHash: spkiHash, for: host) {
                // Pin matched — allow connection with server's credential.
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        // No pin matched anywhere in the chain — reject connection (T-10-W4-01 mitigation).
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
