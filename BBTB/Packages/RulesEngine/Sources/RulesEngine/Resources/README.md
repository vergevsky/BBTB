# RulesEngine Baseline Resources

**Status:** PLACEHOLDER — заменяются на real signed content через W6
build-baseline-rules.sh (Plan 08-07). Текущее содержимое НЕ для production:

- `baseline-rules-manifest.json` — `version=0`, валидно decode-ится в
  `RulesManifest`, содержит `block_completely.domains = ["max.ru",
  "mssgr.tatar.ru"]` (синхронно с `wiki/max-messenger.md`).
- `baseline-rules-manifest.json.sig` — **64 zero bytes**. `RulesSigner.verify`
  всегда вернёт `false` для этой сигнатуры — bootstrap НЕ проверяет signature
  (D-05: baseline trust = code signing).
- `bbtb-baseline-{block,never,always}.srs` — каждый ровно **4 байта**: magic
  header `0x53 0x52 0x53 0x04` (визуальный marker SRS format v4). НЕ парсятся
  sing-box'ом. Server `.srs` от W6 заменит эти placeholder бинари на real
  compiled sing-box rule-set v4.
- `bbtb-baseline-{block,never,always}.srs.sig` — **64 zero bytes**. Заменяется
  на real Ed25519 detached signature от admin's private key.

**Trust model для baseline:**
- Baseline вшит в client binary через `Bundle.module` resources →
  целостность гарантирует Apple code signing (T-08-W2-08 disposition `accept`).
- `RulesEngineCoordinator.bootstrap()` копирует эти 8 файлов в App Group cache
  на first-launch БЕЗ signature verify. Signature verify применяется только
  для **server-fetched** updates (W2.3 + W4 + W6).

**Replacement workflow (W6 — Plan 08-07):**
1. Admin генерирует Ed25519 keypair (см. `PublicKey.swift` doc-comment).
2. Кладёт private key в `BBTB_SIGNING_KEY_PATH` env (1Password / Keychain).
3. Запускает `scripts/build-baseline-rules.sh` — compiles `baseline-rules.json`
   → 3 real `.srs` (sing-box CLI) → signs each + manifest.
4. Build script копирует output в эту директорию, перезаписывая placeholder'ы.

**W7 invariant (Plan 08-08 — `validate-r1-r6.sh`):**
R12 invariant отвергает builds где `.sig` файлы остались = 64 zero bytes
(detect placeholder в production build).
