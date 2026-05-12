---
phase: 03-server-management
plan: 01
subsystem: database
tags: [swiftdata, model, migration, subscription, multi-source, swift-concurrency, swift6]

# Dependency graph
requires:
  - phase: 02-trojan-import-flow
    provides: "ServerConfig (Phase 2 baseline init signature: isSupported, subscriptionURL, outboundJSON, protocolDisplayName, sni, rawURI), ConfigImporter (importFromRawInput с replace-pool semantics, persistSupported/persistUnsupported, deleteExistingPool by URL), UniversalImportParser (ImportResult + SubscriptionMetadata), SwiftDataContainer.makeShared (App Group + in-memory fallback)"
  - phase: 01-foundation
    provides: "@Model ServerConfig (Phase 1 baseline), KeychainStore, App Group entitlement group.app.bbtb.shared"
provides:
  - "Subscription @Model { id (unique), url, name, lastFetched } — multi-subscription foundation"
  - "ServerConfig +5 optional Phase-3 fields: subscriptionID (FK), countryCode, lastPingedAt, failedProbeCount, missingFromLastFetch"
  - "SwiftDataContainer.migratePhase2ToPhase3 (internal, testable) — idempotent group-by-URL → Subscription rows + FK assignment"
  - "UserDefaults idempotency flag app.bbtb.phase3.migrationDone (Pitfall 9 mitigation)"
  - "ConfigImporter.getOrCreateSubscription — fetch-by-URL → reuse OR insert с T-03-01 sanitization"
  - "UniversalImportParsing protocol — DI boundary над UniversalImportParser actor"
  - "TunnelProvisioning protocol + DefaultTunnelProvisioner — DI boundary над NETunnelProviderManager"
  - "ConfigImporter.sanitizeSubscriptionName — strip \\n\\r\\t, clamp 100 chars (T-03-01)"
affects: [03-02-server-probe, 03-03-server-list-ui, 03-04-pull-to-refresh-merge, 04-protocol-expansion, 11-onboarding-ux]

# Tech tracking
tech-stack:
  added:
    - "Subscription @Model (SwiftData) — second persistent entity рядом с ServerConfig"
    - "UserDefaults migration flag pattern app.bbtb.phase3.migrationDone"
    - "Protocol-based DI для testable ConfigImporter (parser + tunnel provisioner)"
  patterns:
    - "Manual FK через UUID field (subscriptionID) вместо @Relationship — обусловлено Pitfall 2 (lightweight migration не поддерживает смену типа поля)"
    - "Sendable snapshot pattern в тестах — fetch внутри @MainActor, наружу выходят только Sendable значения (UUID, String, Date, Bool)"
    - "Two-tier idempotency для миграции — UserDefaults flag (production guard) + row-level FetchDescriptor check (testable безусловная функция)"
    - "Security-by-default sanitization для server-controlled headers (T-03-01: Profile-Title → strip+clamp до persist)"

key-files:
  created:
    - "BBTB/Packages/VPNCore/Sources/VPNCore/Subscription.swift — @Model entity"
    - "BBTB/Packages/VPNCore/Tests/VPNCoreTests/SubscriptionModelTests.swift — 3 CRUD tests"
    - "BBTB/Packages/VPNCore/Tests/VPNCoreTests/Phase3MigrationTests.swift — 5 migration tests"
    - "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterSubscriptionTests.swift — 4 tests (3 plan + 1 T-03-01)"
  modified:
    - "BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift — +5 Phase-3 fields"
    - "BBTB/Packages/VPNCore/Sources/VPNCore/SwiftDataContainer.swift — register Subscription + migratePhase2ToPhase3"
    - "BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift — добавлен UniversalImportParsing protocol"
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift — DI ctor, getOrCreateSubscription, sanitizeSubscriptionName, DefaultTunnelProvisioner extracted"

key-decisions:
  - "Manual FK через UUID вместо @Relationship — RESEARCH Pitfall 2 (изменение типа поля subscriptionURL: String? → @Relationship не lightweight)."
  - "subscriptionURL retained as DEPRECATED — удаление через VersionedSchema в Phase 4. Phase 3 пишет ОБА поля (T-03-06 mitigation against split-source-of-truth)."
  - "migratePhase2ToPhase3 internal (не private) — функция безусловна; UserDefaults guard стоит в makeShared (production) и в Phase3MigrationTests очищается в tearDown. Это позволяет тестам напрямую вызывать миграцию с in-memory контейнером."
  - "DI рефакторинг ConfigImporter — добавлен полный init с UniversalImportParsing + TunnelProvisioning параметрами. Phase 2 convenience init сохранён (back-compat для production callsites)."
  - "T-03-01 sanitization выполняется в getOrCreateSubscription (point of persistence), не в parser — точка минимально необходимая, и охватывает оба flow (новый Subscription + переименование существующего)."
  - "Branch result.subscriptionURL != nil: сохранили Phase 2 'replace pool by URL' (deleteExistingPool) — backwards-compat. Plan 04 заменит на merge-by-identity (D-14)."
  - "Test файлы используют XCTest (matches Phase 1/2 baseline) + @MainActor class isolation — устраняет SwiftData PersistentModel-not-Sendable race warnings под Swift 6 strict concurrency."

patterns-established:
  - "Lightweight migration + manual FK — стандартный путь для @Model evolution (избегаем VersionedSchema до пока возможно)"
  - "Idempotent data migration с двойной защитой — UserDefaults для production, row-level FetchDescriptor для testability"
  - "Protocol-DI обёртки над actor / OS-API классами для testability (UniversalImportParsing, TunnelProvisioning)"
  - "Sanitization-at-persistence для server-controlled данных (вместо доверчивого persist + UI-side escape)"
  - "@MainActor XCTestCase class когда тесты затрагивают SwiftData — устраняет Sendable boundary issues"

requirements-completed: [SRV-02]

# Metrics
duration: 10min
completed: 2026-05-12
---

# Phase 03 Plan 01: Subscription foundation Summary

**Multi-subscription @Model + Phase 2 → Phase 3 idempotent migration + ConfigImporter get-or-create branch с T-03-01 sanitization — data foundation для server-list секций Plan 03 и merge-by-identity Plan 04.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-05-12T11:42:06Z
- **Completed:** 2026-05-12T11:52:16Z
- **Tasks:** 3 / 3
- **Files modified:** 4 source + 3 test files created/modified

## Accomplishments

- `Subscription` @Model добавлен в VPNCore с `@Attribute(.unique) id: UUID`, `url`, `name`, `lastFetched: Date?`. Регистрирован в `SwiftDataContainer` обеих веток (App Group + in-memory fallback).
- `ServerConfig` расширен пятью optional Phase-3 полями (subscriptionID, countryCode, lastPingedAt, failedProbeCount, missingFromLastFetch). Lightweight migration — старые row'ы получают nil/false дефолты автоматически; backward compat для Phase 2 callsites через trailing-default параметры в init.
- `SwiftDataContainer.migratePhase2ToPhase3` — internal idempotent функция: для каждого `ServerConfig.subscriptionURL != nil` создаёт (или переиспользует существующий) `Subscription` row + проставляет FK на серверах. Production-сайт guard'ит UserDefaults flag `app.bbtb.phase3.migrationDone` (Pitfall 9).
- `ConfigImporter` получил протокол-DI границу (`UniversalImportParsing`, `TunnelProvisioning`) — позволяет тестам внедрять StubParser+StubTunnelProvisioner без сети / OS NetworkExtension entitlement.
- Branch при импорте subscription URL: `getOrCreateSubscription` (fetch-by-URL → reuse OR insert, с T-03-01 sanitization), `sub.lastFetched = .now`, затем сохранён Phase 2 `deleteExistingPool` semantic (Plan 04 заменит на merge-by-identity), и FK `subscriptionID` прокидывается в `persistSupported`/`persistUnsupported`. Single-paste branch остался unchanged (orphan servers с `subscriptionID == nil`).
- T-03-01 mitigation реализован — `sanitizeSubscriptionName` strip'ит `\n\r\t` через regex и clamp'ит до 100 chars, защищая UI от malicious Profile-Title (server-controlled header).
- 12 новых тестов GREEN: 3 CRUD Subscription + 5 migration scenarios + 4 import flow (включая T-03-01 verification). 0 regressions в Phase 1/2 suites: VPNCore 13/13, AppFeatures 10/10, ConfigParser 78/78.

## Task Commits

Each task committed atomically (TDD red→green pattern):

1. **Task 1 (RED): failing tests for Subscription + Phase 3 migration** — `29cb678` (test)
2. **Task 2 (GREEN): Subscription @Model + ServerConfig +5 fields + idempotent migration** — `3b574a9` (feat)
3. **Task 3 (GREEN): ConfigImporter get-or-create branch + DI рефакторинг** — `1a0a00c` (feat)

## Files Created/Modified

### Created

- `BBTB/Packages/VPNCore/Sources/VPNCore/Subscription.swift` — `@Model public final class Subscription { id (unique), url, name, lastFetched: Date? }`
- `BBTB/Packages/VPNCore/Tests/VPNCoreTests/SubscriptionModelTests.swift` — round-trip persist+fetch by url, `@Attribute(.unique)` invariant, lastFetched round-trip
- `BBTB/Packages/VPNCore/Tests/VPNCoreTests/Phase3MigrationTests.swift` — group-by-url, idempotency (двойной вызов), UserDefaults flag guard, multi-url grouping, orphan skip
- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterSubscriptionTests.swift` — new subscription, reuse existing, single-paste orphan, T-03-01 sanitization

### Modified

- `BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift` — +5 Phase-3 optional fields + init signature extension (back-compat defaults); subscriptionURL помечен DEPRECATED в DocC
- `BBTB/Packages/VPNCore/Sources/VPNCore/SwiftDataContainer.swift` — register `Subscription.self`, добавлены `migrationDoneKey`, internal `migratePhase2ToPhase3(in:)`, internal `derivedName(from:)`
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift` — добавлен `public protocol UniversalImportParsing`; existing actor conform'ит к нему
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — добавлен `public protocol TunnelProvisioning` + `DefaultTunnelProvisioner` (extracted Phase 2 NETunnelProviderManager logic); полный DI init; `getOrCreateSubscription` helper; `sanitizeSubscriptionName` static helper (T-03-01); `persistSupported`/`persistUnsupported` сигнатуры расширены `subscriptionID:` параметром (back-compat default nil)

## Decisions Made

- **Manual FK через UUID вместо @Relationship** — D-05 + RESEARCH Pitfall 2: переход `subscriptionURL: String?` → `@Relationship` не lightweight, потребовал бы VersionedSchema + migration mapping model. Manual FK через UUID — простой Add (lightweight, безопасный).
- **subscriptionURL retained as DEPRECATED** — DocC помечает поле deprecated, удаление в Phase 4 через VersionedSchema. Phase 3 запись пишет ОБА поля для backward-compat (T-03-06 mitigation: предотвращает split-source-of-truth между старым и новым кодом).
- **migratePhase2ToPhase3 internal, безусловная** — UserDefaults guard стоит в `makeShared`, а не внутри `migratePhase2ToPhase3`. Это позволяет `Phase3MigrationTests` напрямую вызывать миграцию с in-memory контейнером (несколько раз, для idempotency check) без необходимости очищать UserDefaults между вызовами. Production-сайт защищён двойным барьером (UserDefaults + row-level FetchDescriptor).
- **DI рефакторинг ConfigImporter** — добавил `UniversalImportParsing` protocol в ConfigParser (existing actor conform'ит к нему) и `TunnelProvisioning` protocol в MainScreenFeature (с `DefaultTunnelProvisioner` impl). Это deviation Rule 3 (testability blocker), детали ниже.
- **T-03-01 sanitization выполняется в getOrCreateSubscription** — точка минимально необходимая (point-of-persistence), охватывает оба сценария (новый Subscription + переименование существующего при reuse). Не в парсере, потому что парсер может использоваться для других целей.
- **Branch subscription URL сохраняет Phase 2 deleteExistingPool semantic** — соответствует acceptance criteria плана: «сохранить» Phase 2 поведение «replace pool по URL» как часть merge: после get-or-create — вызвать `deleteExistingPool` для подписки (Phase 2 backwards-compat — Plan 04 заменит на merge-by-identity)». Subscription row НЕ удаляется при этом, только её ServerConfig rows.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Добавлены protocol-DI обёртки для testability (UniversalImportParsing, TunnelProvisioning)**
- **Found during:** Task 3 (компиляция ConfigImporterSubscriptionTests)
- **Issue:** План указывает «mock UniversalImportParser (или test double через protocol)» — но `UniversalImportParser` — `public actor` без protocol. `provisionTunnelProfile` в `ConfigImporter` вызывает `NETunnelProviderManager.loadAllFromPreferences()`, который требует entitlement и недоступен в `swift test` под CLI. Без DI границ тесты Task 1 не могли скомпилироваться.
- **Fix:** Добавлен `public protocol UniversalImportParsing` в `ConfigParser/UniversalImportParser.swift` (existing actor conform'ит к нему). Добавлен `public protocol TunnelProvisioning` + `public final class DefaultTunnelProvisioner` в `ConfigImporter.swift` (extracted Phase 2 logic). `ConfigImporter` получил полный DI ctor; Phase 2 convenience ctor сохранён (back-compat для production callsites).
- **Files modified:** BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
- **Verification:** ConfigImporterSubscriptionTests (4) GREEN; ConfigParser 78/78 GREEN (no regressions); AppFeatures 10/10 GREEN (Phase 2 ConnectionTimerTests + новые subscription tests).
- **Committed in:** `1a0a00c` (Task 3 commit)

**2. [Rule 2 - Missing Critical] Добавлена sanitization T-03-01 + 4-й тест**
- **Found during:** Task 3 (анализ threat model)
- **Issue:** `<threat_model>` плана фиксирует T-03-01 (mitigate) — «Subscription.name из malicious Profile-Title header может содержать `\n\r\t` + control chars + JS-like injection». План явно требует «clamp до 100 chars + strip via regex в `getOrCreateSubscription`», но не выделил это как отдельный test case. Безопасность Rule 2 — критично для correctness.
- **Fix:** В `ConfigImporter` добавлен internal static `sanitizeSubscriptionName(_:)` — regex `[\\n\\r\\t]` → space + `trimmingCharacters(.whitespaces)` + `prefix(100)`. Применён в `getOrCreateSubscription` для обоих case'ов (new + reuse). Добавлен `test_subscription_name_sanitized_strips_control_chars_and_clamps_length`.
- **Files modified:** BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterSubscriptionTests.swift
- **Verification:** test passes; assertions проверяют отсутствие `\n`/`\r`/`\t` в persisted name + length ≤ 100.
- **Committed in:** `1a0a00c` (Task 3 commit)

**3. [Rule 1 - Bug] Тесты RED не компилировались под Swift 6 strict concurrency (SwiftData @Model not Sendable)**
- **Found during:** Task 3 verification (после первого build attempt)
- **Issue:** `await MainActor.run { ... }` возвращающий `[ServerConfig]` или `[Subscription]` падал с «conformance of 'X' to 'Sendable' is unavailable: PersistentModels are not Sendable». В Swift 6 mode @Model classes — explicit @unavailable Sendable, пересечь actor boundary нельзя.
- **Fix:** Class `ConfigImporterSubscriptionTests` помечен `@MainActor`, что устраняет cross-actor calls вообще. Snapshots тестов используют Sendable value-types (`SubscriptionSnapshot`, `ServerSnapshot`) — fetch выполняется внутри `@MainActor` контекста, наружу выходят только Sendable значения (UUID, String, Date, Bool).
- **Files modified:** BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterSubscriptionTests.swift (один файл, переписан в Task 1+3 итерации)
- **Verification:** AppFeatures build + 10/10 tests pass без Sendable warnings.
- **Committed in:** `1a0a00c` (Task 3 commit — последняя итерация теста перед green)

**4. [Rule 1 - Bug] ParsedVLESS init signature не совпадал с предположением плана**
- **Found during:** Task 3 (компиляция ConfigImporterSubscriptionTests)
- **Issue:** Я использовал в тестовом fixture сигнатуру `ParsedVLESS(host:port:uuid:publicKey:shortId:sni:fingerprint:flow:)`, но реальная сигнатура — `ParsedVLESS(uuid:host:port:flow:security:sni:publicKey:shortId:fingerprint:networkType:remarks:)`. Compile-fail на missing arguments.
- **Fix:** В test fixture `makeSupportedVLESS` перешёл к корректной сигнатуре (security="reality", networkType="tcp", remarks=nil).
- **Files modified:** BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterSubscriptionTests.swift
- **Verification:** Test build succeeds.
- **Committed in:** `1a0a00c` (Task 3 commit)

---

**Total deviations:** 4 auto-fixed (1 Rule 2 — критическая безопасность T-03-01, 1 Rule 3 — testability infrastructure, 2 Rule 1 — bug fixes по ходу написания тестов).

**Impact on plan:** Все auto-fixes необходимы для completeness. Plan acceptance criteria выполнены 100%. Никакого scope creep — добавленные protocol/sanitizer прямо обусловлены планом (план явно упоминает «mock через protocol» и T-03-01 sanitization). DI рефакторинг расширяет ConfigImporter но сохраняет полную back-compat для Phase 2 callsites через convenience init.

## Issues Encountered

- **libbox.xcframework отсутствует в worktree.** AppFeatures транзитивно зависит от libbox через PacketTunnelKit; в новом git worktree (Vendored/ в .gitignore) artefact отсутствует. **Решение:** создан симлинк `BBTB/Vendored/libbox.xcframework -> /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework` (main repo). Тяжёлый 802 МБ binary не копируется. Симлинк намеренно не закоммичен (untracked); `.gitignore` ищет `Vendored/libbox.xcframework/` с trailing slash, что не покрывает симлинк-файл — это известное orchestrator workaround pattern.

## Threat Flags

Нет новых threat surfaces вне `<threat_model>` плана. Все 6 STRIDE-угроз (T-03-01 .. T-03-06) обработаны:

| T-ID | Disposition | Verification |
|------|-------------|--------------|
| T-03-01 (Tampering — malicious Profile-Title) | mitigate | `sanitizeSubscriptionName` + `test_subscription_name_sanitized_strips_control_chars_and_clamps_length` |
| T-03-02 (Idempotency violation) | mitigate | `migrationDoneKey` UserDefaults + `test_migration_is_idempotent` |
| T-03-03 (DoS body-size) | accept (carry-forward Phase 7) | Документировано в Plan 03-01 frontmatter; не вводит новой surface |
| T-03-04 (URL contains secret token) | accept (carry-forward Phase 1) | App Group sandbox isolation |
| T-03-05 (@Predicate injection) | mitigate (framework-provided) | Swift macro — type-safe parameterized queries |
| T-03-06 (split source-of-truth) | mitigate | Phase 3 пишет ОБА поля (`subscriptionURL` + `subscriptionID`); Phase 4 удалит `subscriptionURL` |

## Self-Check

Verified post-write:

| Artifact | Check |
|----------|-------|
| BBTB/Packages/VPNCore/Sources/VPNCore/Subscription.swift | FOUND |
| BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift (Phase 3 fields) | FOUND |
| BBTB/Packages/VPNCore/Sources/VPNCore/SwiftDataContainer.swift (migration) | FOUND |
| BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift (getOrCreateSubscription) | FOUND |
| BBTB/Packages/VPNCore/Tests/VPNCoreTests/SubscriptionModelTests.swift | FOUND |
| BBTB/Packages/VPNCore/Tests/VPNCoreTests/Phase3MigrationTests.swift | FOUND |
| BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterSubscriptionTests.swift | FOUND |
| Commit 29cb678 (RED) | FOUND in git log |
| Commit 3b574a9 (GREEN Task 2) | FOUND in git log |
| Commit 1a0a00c (GREEN Task 3) | FOUND in git log |
| VPNCore tests | 13/13 PASS (1 skip = SEC-05 macOS CLI, pre-existing) |
| AppFeatures tests | 10/10 PASS |
| ConfigParser tests | 78/78 PASS (no regression от UniversalImportParsing protocol) |

## Self-Check: PASSED

## Next Phase Readiness

Phase 03 Plan 02+ ready:

- **Plan 02 (server probe + auto-select):** `ServerConfig.lastPingedAt`, `failedProbeCount` уже добавлены — ServerProbeService может писать сразу. Sendable tuple boundary `(UUID, host, port)` для actor — RESEARCH Pitfall 4 уже учтён в API ServerConfig (полей достаточно).
- **Plan 03 (server list UI):** sections группируются по `Subscription` rows (already persisted). `subscriptionID == nil` секция = «Добавлены вручную». Cascade delete (D-07) — отдельный helper в Plan 04.
- **Plan 04 (pull-to-refresh + merge-by-identity):** `getOrCreateSubscription` + `lastFetched` уже работают. `missingFromLastFetch: Bool` поле подготовлено для D-14 merge semantics. Текущий `deleteExistingPool` в branch subscription URL — точка замены: SubscriptionMergeService займёт его место.

### Carry-forward / TODO для следующих планов

- **Plan 04:** Заменить `deleteExistingPool(subscriptionURL:)` в `ConfigImporter` на `SubscriptionMergeService.merge(...)` — `missingFromLastFetch` ставится true для disappeared rows, новые — insert с FK.
- **Plan 04:** SwiftPM Package.swift в AppFeatures возможно потребует extension/новый target `ServerListFeature` (см. PATTERNS §«Package Wiring»). В текущем плане НЕ выполнялось.
- **Phase 4 VersionedSchema:** удалить `ServerConfig.subscriptionURL` (DEPRECATED), `ServerConfig.isActive` (если Phase 3 Plan 03 завершит миграцию на `selectedServerID` в state).
- **CI infra:** libbox.xcframework symlink в worktree — orchestrator может стандартизировать pre-test step (или Vendored/.gitignore изменить чтобы покрывать симлинки).

---

*Phase: 03-server-management*
*Completed: 2026-05-12*
