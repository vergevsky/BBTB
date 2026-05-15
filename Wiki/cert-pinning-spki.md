# Certificate Pinning (SPKI SHA-256)

**Summary**: DPI-08 certificate pinning для subscription URL — SPKI SHA-256 Apple-standard pipeline, `scripts/generate-spki-pin.swift` usage, remote Ed25519-signed manifest, и процедура ротации пинов до TestFlight.

**Sources**: `.planning/phases/10-advanced-settings-security-polish/10-CONTEXT.md` (D-08..D-14), `.planning/phases/10-advanced-settings-security-polish/10-RESEARCH.md` (A1..A4), Phase 10 Plan 04 SUMMARY.

**Last updated**: 2026-05-15 (Phase 10 closure — cert pinning implemented, Phase 12 prerequisite: replace placeholder pins)

---

## Зачем SPKI (Subject Public Key Info) SHA-256, не cert SHA-256

Certificate pinning бывает двух видов:

- **Cert pinning** — pin на конкретный сертификат. Ломается при renewal (Let's Encrypt → 90 дней).
- **SPKI pinning** — pin на публичный ключ внутри сертификата. Ключ можно сохранить при renewal — pin не ломается.

**D-08 решение**: SPKI SHA-256 (Apple-standard). Протоколируем публичный ключ сервера, не сам сертификат. При плановом обновлении TLS-сертификата (но с тем же ключом) — pin сохраняется. Смена ключа → нужна ротация pin + обновление через remote manifest.

## Apple-standard SPKI pipeline

Вместо OpenSSL-подхода (который даёт другой hash — Pitfall 2 в RESEARCH.md A4) используем Apple Security framework:

```swift
// 1. Получить цепочку сертификатов от TLS
let chain = SecTrustCopyCertificateChain(trust) as! [SecCertificate]

// 2. Извлечь публичный ключ из сертификата сервера (leaf = chain[0])
let serverCert = chain[0]
let publicKey = SecCertificateCopyKey(serverCert)!

// 3. Получить raw DER bytes публичного ключа (SPKI format)
var error: Unmanaged<CFError>?
let keyData = SecKeyCopyExternalRepresentation(publicKey, &error)! as Data

// 4. SHA-256 хэш
import CryptoKit
let hash = SHA256.hash(data: keyData)
let hexPin = hash.map { String(format: "%02x", $0) }.joined()
```

**Важно**: OpenSSL `openssl x509 -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256` даёт **ДРУГОЙ** результат. Apple и OpenSSL используют разные DER encoding для некоторых key types. ВСЕГДА генерируй пины через `scripts/generate-spki-pin.swift` (который использует `SecKeyCopyExternalRepresentation`), не через CLI OpenSSL.

## scripts/generate-spki-pin.swift — usage

```bash
# Генерация SPKI SHA-256 pin для конкретного hostname
swift run --package-path scripts generate-spki-pin --host vpn.vergevsky.ru

# Output:
# Connecting to vpn.vergevsky.ru:443...
# Certificate chain: 3 certs
# Leaf cert: [Subject]
# SPKI SHA-256: a1b2c3d4...  (64 hex chars)
# Backup cert SPKI SHA-256: 8f7e6d5c...
```

Скрипт:
1. Делает TLS handshake к `host:443`.
2. Вытаскивает leaf certificate + intermediate (backup).
3. Вычисляет SPKI SHA-256 через `SecKeyCopyExternalRepresentation`.
4. Выводит hex строки для copy-paste в `PinStore.swift`.

## PinStore.swift — bootstrap pins

```swift
// BBTB/Packages/ConfigParser/Sources/ConfigParser/PinStore.swift

public enum BootstrapPins {
    /// Phase 12 prerequisite — replace with real SPKI SHA-256 via generate-spki-pin.swift
    /// BEFORE TestFlight upload.
    public static let vpnVergevskyRu: [String] = [
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",  // PRIMARY — placeholder
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",  // BACKUP — placeholder
    ]
}
```

**Phase 12 prerequisite**: эти placeholder bytes (64 `a`s и `b`s) ДОЛЖНЫ быть заменены реальными SPKI SHA-256 пинами через `generate-spki-pin.swift` ПЕРЕД TestFlight upload. Иначе все subscription requests упадут с `pinning mismatch` ошибкой.

## Remote signed manifest (subscription-pins.json)

Кроме bootstrap pins, app поддерживает **remote pin rotation** через `subscription-pins.json`:

```json
{
  "version": 1,
  "validUntil": "2027-01-01T00:00:00Z",
  "pins": [
    {
      "host": "vpn.vergevsky.ru",
      "primarySPKI": "a1b2c3d4...",
      "backupSPKI": "8f7e6d5c..."
    }
  ]
}
```

Подписан Ed25519 — тот же ключ что и `rules.json` (D-12 решение: единый admin key). Манифест хранится на том же endpoint что и `rules.json`.

### validUntil hard reject policy

**D-11**: если `validUntil` в манифесте истёк — hard reject. App НЕ использует expired manifest даже если пины совпадают. Это защищает от replay attack с устаревшим манифестом. Пользователь видит ошибку в UI.

## Phase 12: процедура ротации пинов

Когда VPN сервер меняет TLS ключ (или admin впервые активирует реальный сервер):

1. **Генерировать новые пины**:
   ```bash
   swift run --package-path scripts generate-spki-pin --host vpn.vergevsky.ru
   ```
2. **Обновить `PinStore.swift`**: заменить `primarySPKI` (+ `backupSPKI` для промежуточного cert или next-upcoming cert).
3. **Обновить `subscription-pins.json`**: bump `version`, продлить `validUntil` (≥ 1 год), обновить пины.
4. **Подписать manifest**: использовать admin Ed25519 ключ (тот же что подписывает `rules.json`).
5. **Deploy manifest**: тот же endpoint что rules manifest.
6. **TestFlight build**: пересобрать с новым `PinStore.swift` → submit.

> **Backward compat**: bootstrap pins в bundle должны совпадать с реальным сервером ДО выхода обновлённого manifesta. Поэтому ротацию делать в два шага: сначала deploy manifest → потом bundle update в следующем release.

## PinnedSessionDelegate + SubscriptionPinManager

Реализовано в Phase 10 Plan 04:

- **`PinnedSessionDelegate`**: `URLSessionDelegate` — переопределяет `urlSession(_:didReceive:completionHandler:)`, проверяет SPKI SHA-256 leaf cert против bootstrap pins + remote manifest.
- **`SubscriptionPinManager`** (actor): загружает и кэширует remote manifest (Ed25519 verify), thread-safe.
- **`PinnedSubscriptionURLFetcher`**: обёртка над `URLSession(configuration:delegate:)` с `PinnedSessionDelegate`.

## Когда pinning отключён

Toggle «Cert pinning» в AdvancedSettingsView (UserDefaults key `app.bbtb.certPinningEnabled`, default `true`). При `false` — обычный `URLSession` без кастомного delegate. Только для debug/dev (тест 8 в Plan 04: `test_noPinningWhenDisabled`).

## Related pages

- [[security-gaps]]
- [[rules-engine]] — тот же Ed25519 admin key
- [[advanced-settings]]
- [[anti-dpi-techniques]]
