---
phase: 03-server-management
plan: G1
type: execute
wave: 5
depends_on: [01, 02, 03, 04, 05]
files_modified:
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift
  - BBTB/Packages/VPNCore/Sources/VPNCore/ProbeResult.swift
  - BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift
  - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/SubscriptionURLFetcherTests.swift
autonomous: true
gap_closure: true
requirements: [SRV-01, SRV-02, SRV-03, UX-04]

must_haves:
  truths:
    - "Когда пользователь выбрал сервер X и его Keychain decode провалился — connect возвращает ошибку, а не подключается к чужому серверу"
    - "confirmDeleteSubscription удаляет подписку ровно один раз и не падает на cross-context delete"
    - "SubscriptionURLFetcher отвергает URL'ы с hostname в loopback/link-local/RFC-1918/multicast диапазонах"
    - "После merge подписки ровно один ServerConfig имеет isActive == true (детерминистично)"
    - "failedProbeCount хранит точное целое число failed probes (0..3) без floating-point truncation"
  artifacts:
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift"
      provides: "CR-01 strict-selection guard + CR-04 deterministic isActive reset"
      contains: "ImporterError.configBuildFailed"
    - path: "BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift"
      provides: "CR-02 same-context delete + CR-05 raw failures count"
      contains: "agg.failures"
    - path: "BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift"
      provides: "CR-03 SSRF hostname blocklist (loopback, link-local, RFC-1918, multicast)"
      contains: "FetchError.blockedHost"
    - path: "BBTB/Packages/VPNCore/Sources/VPNCore/ProbeResult.swift"
      provides: "ProbeAggregate exposes failures: Int explicitly"
      contains: "public let failures: Int"
    - path: "BBTB/Packages/ConfigParser/Tests/ConfigParserTests/SubscriptionURLFetcherTests.swift"
      provides: "test_fetch_rejects_blocked_hosts coverage for CR-03"
      contains: "test_fetch_rejects"
  key_links:
    - from: "ConfigImporter.provisionTunnelProfile(for:)"
      to: "ImporterError.configBuildFailed"
      via: "explicit-selection guard throws вместо fallback на full pool"
      pattern: "selectedID.*throw"
    - from: "ServerListViewModel.pingAllServers"
      to: "ProbeAggregate.failures"
      via: "row.failedProbeCount = agg.failures (no Int(Double * 3))"
      pattern: "failedProbeCount = agg.failures"
    - from: "SubscriptionURLFetcher.fetch"
      to: "FetchError.blockedHost"
      via: "isBlockedHost(_:) check после scheme guard"
      pattern: "isBlockedHost"
---

<objective>
Закрыть 5 критических багов, найденных code review (`03-REVIEW.md`) и подтверждённых verifier'ом (`03-VERIFICATION.md`) — CR-01 silent server substitution (BLOCKER), CR-02 cross-context SwiftData delete (CRASH), CR-03 SSRF без hostname blocklist (SECURITY), CR-04 non-deterministic `isActive` (BLOCKER), CR-05 IEEE-754 truncation в `failedProbeCount` (BLOCKER).

Purpose: Phase 3 ROADMAP success criteria SC-2 (auto-select) сейчас PARTIAL из-за CR-05; explicit-selection contract D-09 нарушен CR-01; T-03-06 в threat model заявлен mitigated, но код пуст (CR-03). Без этих фиксов Phase 3 нельзя закрыть как COMPLETE.

Output:
- `ConfigImporter.swift` — strict guard на selectedID + детерминистичный isActive reset
- `ServerListViewModel.swift` — same-context delete + использование `agg.failures` вместо труncation
- `SubscriptionURLFetcher.swift` — hostname blocklist + новая `FetchError.blockedHost` case
- `ProbeResult.swift` — добавлен `failures: Int` на `ProbeAggregate`
- `ServerProbeService.swift` — `probeServerThreeTimes` возвращает `failures` напрямую
- `SubscriptionURLFetcherTests.swift` — новый тест `test_fetch_rejects_blocked_hosts`
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/03-server-management/03-CONTEXT.md
@.planning/phases/03-server-management/03-VERIFICATION.md
@.planning/phases/03-server-management/03-REVIEW.md
@BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
@BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift
@BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift
@BBTB/Packages/VPNCore/Sources/VPNCore/ProbeResult.swift
@BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift

<interfaces>
Текущая `ProbeAggregate` сигнатура (Phase 3 / Plan 02 — ProbeResult.swift:24-47):

public struct ProbeAggregate: Sendable, Equatable {
    public let avgLatencyMs: Int?
    public let lossRate: Double
    public let probedAt: Date
    public init(avgLatencyMs: Int?, lossRate: Double, probedAt: Date)
    public var score: Double? { ms × (1 + lossRate) или nil }
    public var isUnreachable: Bool { avgLatencyMs == nil }
}

После фикса CR-05 добавляется поле `failures: Int` (0..3, число failed probes), init расширяется параметром `failures: Int` ПЕРЕД `probedAt` (чтобы init clusters связанные fields). Все существующие callsites — только `ServerProbeService.probeServerThreeTimes` (одна строка `return (srv.id, ProbeAggregate(...))`) и тесты — обновляются.

Текущая `ImporterError` (private enum в ConfigImporter.swift — есть case `.configBuildFailed(Error)`, `.noSupportedServers`, `.swiftDataSaveFailed`, `.keychainSaveFailed`, `.parserFailed`, `.tunnelProfileSaveFailed`, `.emptyPasteboard`). CR-01 fix переиспользует `.configBuildFailed` (с NSError содержащим описание «selected server cannot be decoded»), новые cases не вводятся.

Текущая `FetchError` (SubscriptionURLFetcher.swift:54-70 — public enum LocalizedError Equatable с cases `.nonHTTPS(String)`, `.notHTTPResponse`, `.httpStatusError(Int)`, `.malformedURL`, `.timeout`). CR-03 fix добавляет case `.blockedHost(String)` с `errorDescription` "Subscription URL host is blocked: \(host)".
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: CR-03 — Add SSRF hostname blocklist to SubscriptionURLFetcher (TDD)</name>
  <files>BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift, BBTB/Packages/ConfigParser/Tests/ConfigParserTests/SubscriptionURLFetcherTests.swift</files>
  <read_first>
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift (Phase 2 baseline — `FetchError` enum lines 54-70, `fetch(url:session:)` lines 76-93)
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/SubscriptionURLFetcherTests.swift (existing XCTest pattern, `MockURLProtocol` usage at lines 1-128)
    - .planning/phases/03-server-management/03-VERIFICATION.md gap «Subscription URL fetch blocks internal/localhost/private-range SSRF» (lines 36-43)
    - .planning/phases/03-server-management/03-REVIEW.md CR-03 (lines 160-200) — конкретный список blocked prefixes
  </read_first>
  <behavior>
    SubscriptionURLFetcherTests новые юнит-тесты (RED → GREEN):
    - test_fetch_rejects_localhost — `https://localhost/sub` throws `FetchError.blockedHost("localhost")`
    - test_fetch_rejects_loopback_ipv4 — `https://127.0.0.1/sub`, `https://127.5.6.7/x` throw `FetchError.blockedHost`
    - test_fetch_rejects_loopback_ipv6 — `https://[::1]/sub` throws `FetchError.blockedHost`
    - test_fetch_rejects_link_local_v4 — `https://169.254.169.254/latest/meta-data/` (AWS metadata) throws
    - test_fetch_rejects_rfc1918_10 — `https://10.0.0.1/` throws
    - test_fetch_rejects_rfc1918_172 — `https://172.16.0.1/`, `https://172.31.255.254/` throw; но `https://172.32.0.1/` НЕ throws (32 не в blocked range)
    - test_fetch_rejects_rfc1918_192_168 — `https://192.168.1.1/` throws
    - test_fetch_rejects_link_local_v6 — `https://[fe80::1]/` throws
    - test_fetch_rejects_unique_local_v6 — `https://[fc00::1]/`, `https://[fd00::1]/` throw
    - test_fetch_accepts_public_host — `https://example.com/sub` НЕ throws (только MockURLProtocol проверяет request URL дошёл до session)

    Все тесты НЕ требуют сетевого запроса для blocked-cases — throw случается ДО session.data(for:).
  </behavior>
  <action>
    1. В `SubscriptionURLFetcher.FetchError` enum (lines 54-70) добавить case `.blockedHost(String)` с `errorDescription` равным `"Subscription URL host is blocked: \(host)"`. Сохранить `Equatable` conformance (Swift auto-synthesize работает с associated value String).

    2. В `SubscriptionURLFetcher.fetch(url:session:)` (line 76-79) ПОСЛЕ guard `scheme == "https"` добавить:
       - Извлечь host через `url.host` (или `url.host(percentEncoded: false)` если iOS 16+).
       - Если host nil или empty → throw `FetchError.malformedURL`.
       - Вызвать новый private static helper `isBlockedHost(_:) -> Bool`; если true → throw `FetchError.blockedHost(host)`.

    3. Реализовать `private static func isBlockedHost(_ host: String) -> Bool`:
       - Нормализовать: lowercase, strip square brackets для IPv6 literal (`[::1]` → `::1`).
       - Exact-match blocklist: `["localhost", "::1", "0.0.0.0"]` → true.
       - Prefix blocklist для IPv4: `"127."`, `"10."`, `"169.254."`, `"192.168."`, `"0."`, `"224."` (multicast), `"240."` (reserved) → true.
       - IPv4 `172.16.` .. `172.31.` (RFC-1918) — итерация по 16...31, проверка `host.hasPrefix("172.\(n).")` → true. NB: НЕ `172.32.` — не блокировать.
       - IPv6: `host.hasPrefix("fe80:")` (link-local), `host.hasPrefix("fc")` AND длина >= 2 (unique-local fc00::/7 включает fc и fd — проверка `hasPrefix("fc")` или `hasPrefix("fd")`).
       - DNS-rebinding защита НЕ в скоупе (требует DNS resolve внутри fetch) — документировать в комментарии как accepted risk для Phase 3.

    4. SubscriptionURLFetcherTests: добавить новый раздел `// MARK: - CR-03 SSRF Blocklist` с тестами из <behavior>. Использовать существующий `MockURLProtocol` для positive case (test_fetch_accepts_public_host) — для negative cases MockURLProtocol не нужен, throw происходит до session call.

    5. Запустить `swift test --package-path BBTB/Packages/ConfigParser --filter SubscriptionURLFetcherTests` — все 9 новых тестов GREEN + все существующие тесты остаются GREEN.

    6. Commit: `fix(03-G1/CR-03): block SSRF to loopback/link-local/RFC-1918 in SubscriptionURLFetcher`.

    Reference threat model: T-03-06 в `03-01-PLAN.md` объявлен mitigated, но код пуст — этот fix закрывает декларацию.
  </action>
  <verify>
    <automated>cd /Users/vergevsky/ClaudeProjects/VPN && swift test --package-path BBTB/Packages/ConfigParser --filter SubscriptionURLFetcherTests 2>&1 | tail -25</automated>
  </verify>
  <acceptance_criteria>
    - `grep -q "case blockedHost" BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift`
    - `grep -q "isBlockedHost" BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift`
    - `grep -c "127\\.\\|169\\.254\\.\\|192\\.168\\." BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` >= 3
    - `grep -c "test_fetch_rejects" BBTB/Packages/ConfigParser/Tests/ConfigParserTests/SubscriptionURLFetcherTests.swift` >= 8 (по одному на каждый blocked-case)
    - Command `swift test --package-path BBTB/Packages/ConfigParser --filter SubscriptionURLFetcherTests` exits 0
    - Git log shows commit "fix(03-G1/CR-03): block SSRF to loopback/link-local/RFC-1918 in SubscriptionURLFetcher"
  </acceptance_criteria>
  <done>SubscriptionURLFetcher отвергает все 9 blocked patterns с `FetchError.blockedHost`; public-host fetch продолжает работать; новые тесты GREEN; ConfigParser full suite GREEN без regressions.</done>
</task>

<task type="auto">
  <name>Task 2: CR-01 + CR-04 — Strict selection guard + deterministic isActive in ConfigImporter</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift</files>
  <read_first>
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift (lines 200-260 для CR-04 контекста, lines 410-500 для `provisionTunnelProfile(for:)` CR-01 контекста)
    - .planning/phases/03-server-management/03-VERIFICATION.md gaps «provisionTunnelProfile connects to selected server» (lines 22-29) и «isActive flag accurately reflects active server» (lines 50-58)
    - .planning/phases/03-server-management/03-REVIEW.md CR-01 (lines 84-122) и CR-04 (lines 202-235) для recommended fix patterns
    - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterSubscriptionTests.swift (existing test patterns для backward-compat verification)
  </read_first>
  <action>
    **CR-01 (silent server substitution) — `provisionTunnelProfile(for:)` lines 421-500:**

    1. Заменить блок lines 436-444 (`let targets: [ServerConfig]; if let id = selectedID ...`) на ветвление, где `selectedID != nil` НЕ создаёт fallback на full pool при decode failure:
       - Если `selectedID != nil`: найти `cfg` где `cfg.id == id`. Если не найден в `supported` → throw `ImporterError.noSupportedServers` (D-09: stale selection после delete = legit fallback, фикс этого случая остаётся как раньше через `applySelection(nil)` upstream — UNCHANGED behavior). Если найден, но `cfg.keychainTag == nil` ИЛИ `reparseFromKeychain(cfg, tag: tag) == nil` → throw `ImporterError.configBuildFailed(NSError(domain: "BBTB.ConfigImporter", code: -10, userInfo: [NSLocalizedDescriptionKey: "Selected server \(id) cannot be decoded from Keychain"]))`. На GREEN path: `parsedList = [parsed]`.
       - Если `selectedID == nil`: текущее full-pool поведение (iterate `supported`, skip on decode failure, build pool). UNCHANGED.

    2. Удалить existing block lines 458-464 (`if parsedList.isEmpty && targets.count == 1 { ... full pool fallback ... }`) — этот fallback CR-01 был корнем silent substitution. После refactor он не нужен: branch на selectedID разделяет два пути explicitly.

    3. Оставить `guard !parsedList.isEmpty else { throw .noSupportedServers }` (line 465-467) — это catch-all защита для selectedID==nil branch.

    Комментарий перед `provisionTunnelProfile(for:)` обновить: убрать «graceful fallback на full pool» формулировку из Phase 3 / Plan 05 doc (Pitfall 10 mitigation), заменить на: «D-09 explicit-selection contract: при selectedID != nil не пытаемся подключиться к другому серверу. Stale ID (deleted) обрабатывается через ImporterError.noSupportedServers; decode failure — через ImporterError.configBuildFailed».

    **CR-04 (non-deterministic isActive) — subscription merge path lines 213-217:**

    4. Найти блок `if let first = savedConfigs.first { first.isActive = true; try? context.save() }` (lines 214-217). `savedConfigs` приходит из FetchDescriptor без `sortBy:`, поэтому `.first` non-deterministic.

    5. Заменить на детерминистичную последовательность:
       - **Перед** установкой any isActive=true: fetch all `ServerConfig` (не только savedConfigs!) — `let allDesc = FetchDescriptor<ServerConfig>()`; для каждого row установить `row.isActive = false`. Это обеспечивает что после merge ровно один сервер имеет isActive=true.
       - Sort `savedConfigs` детерминистично: `let sorted = savedConfigs.sorted { $0.id.uuidString < $1.id.uuidString }`. Используем `id.uuidString` lexicographic ordering — стабильно между runs, не зависит от SwiftData fetch order.
       - Установить `sorted.first?.isActive = true`.
       - `try? context.save()`.

    Прим.: альтернатива (drop isActive from merge path) — слишком инвазивна для gap-closure; CR-04 fix surgical = clear+sort+set.

    6. Запустить `swift test --package-path BBTB/Packages/AppFeatures` — все существующие тесты ДОЛЖНЫ остаться GREEN (ConfigImporterSubscriptionTests, MergeStrategyTests, AutoSelectIntegrationTests, etc.). Если какой-то тест полагался на silent fallback или на `.first` ordering — обновить тест в соответствии с новым (правильным) контрактом, документируя в test комментарии.

    7. Commit (два логических: CR-01 + CR-04 — но в gap-closure объединяем в один atomic commit чтобы не оставлять half-fix):
       `fix(03-G1/CR-01,CR-04): strict selection guard + deterministic isActive in ConfigImporter`.
  </action>
  <verify>
    <automated>cd /Users/vergevsky/ClaudeProjects/VPN && swift test --package-path BBTB/Packages/AppFeatures 2>&1 | tail -30</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c "parsedList.isEmpty && targets.count == 1" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` == 0 (CR-01 silent fallback removed)
    - `grep -E "selected server.*cannot be decoded|code: -10" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` matches
    - `grep -c "savedConfigs.sorted\\|sorted.*id.uuidString" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` >= 1 (CR-04 deterministic ordering)
    - `grep -B2 "isActive = true" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift | grep -c "isActive = false"` >= 1 (clear-then-set sequence)
    - Command `swift test --package-path BBTB/Packages/AppFeatures` exits 0 (full suite GREEN)
    - Git log shows commit "fix(03-G1/CR-01,CR-04): strict selection guard + deterministic isActive in ConfigImporter"
  </acceptance_criteria>
  <done>provisionTunnelProfile(for:) с selectedID никогда не подключается к другому серверу — throw при decode failure; merge path устанавливает isActive=true ровно на одном детерминистично выбранном сервере; AppFeatures test suite GREEN.</done>
</task>

<task type="auto">
  <name>Task 3: CR-02 + CR-05 — Same-context delete + raw failures count in ServerListViewModel</name>
  <files>BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift, BBTB/Packages/VPNCore/Sources/VPNCore/ProbeResult.swift, BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift</files>
  <read_first>
    - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift (lines 233-266 для `confirmDeleteSubscription` CR-02 контекста, lines 279-302 для `pingAllServers` CR-05 контекста)
    - BBTB/Packages/VPNCore/Sources/VPNCore/ProbeResult.swift (полный файл — нужно расширить `ProbeAggregate` полем `failures: Int`)
    - BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift (lines 145-169 `probeServerThreeTimes` — где `failures` уже считается локально, надо протащить в ProbeAggregate init)
    - BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift (lines 117-118 `isUnreachable` computed property — invariant: 0..3, >=3 means unreachable; не менять)
    - .planning/phases/03-server-management/03-VERIFICATION.md gaps «Auto-select correctly derives isUnreachable» (lines 9-16) и «Deleting a subscription removes it exactly once» (lines 28-34)
    - .planning/phases/03-server-management/03-REVIEW.md CR-02 (lines 126-158) и CR-05 (lines 237-280)
    - Find all callsites of ProbeAggregate(...) init для backward-compat audit:
      grep -rn "ProbeAggregate(" BBTB/Packages/ 2>/dev/null
  </read_first>
  <action>
    **CR-05 — Expose `failures: Int` on `ProbeAggregate` (preferred fix per review):**

    1. ProbeResult.swift `ProbeAggregate`:
       - Добавить stored property `public let failures: Int` (doc-comment: «Число failed probes (0..3). Источник истины для `ServerConfig.failedProbeCount`; `lossRate` derived = `Double(failures) / Double(failures + successes)`»).
       - Расширить init signature: `public init(avgLatencyMs: Int?, failures: Int, lossRate: Double, probedAt: Date)`. Параметр `failures` ставится **между** `avgLatencyMs` и `lossRate` (semantic clustering — count перед rate).
       - В init установить `self.failures = failures`. Остальное unchanged.

    2. ServerProbeService.swift `probeServerThreeTimes` (lines 145-169):
       - В существующий `return (srv.id, ProbeAggregate(avgLatencyMs: avg, lossRate: lossRate, probedAt: Date()))` добавить параметр `failures: failures` (переменная `failures` уже локальна в этой функции, line 149).
       - Финальный вид: `return (srv.id, ProbeAggregate(avgLatencyMs: avg, failures: failures, lossRate: lossRate, probedAt: Date()))`.

    3. Найти и обновить ВСЕ другие callsites `ProbeAggregate(...)` init во всём проекте (тесты, mocks):
       - `grep -rn "ProbeAggregate(" BBTB/Packages/ 2>/dev/null | grep -v "// "` — у каждого callsite добавить `failures:` параметр. Если у callsite есть только `lossRate` (например в тесте), вычислить `failures` обратно: `let f = Int((lossRate * Double(attempts)).rounded())` если attempts=3 fixed; либо вручную проставить корректный count исходя из intent теста.
       - Подсказка: предыдущая формула в производственном коде была `Int(lossRate * 3)` — этого недостаточно для теста (имеет тот же truncation bug), но достаточно как initial migration для уже-зелёных юнит-тестов где lossRate ∈ {0.0, 1/3, 2/3, 1.0}.

    4. ServerListViewModel.swift line 297 (`row.failedProbeCount = Int(agg.lossRate * 3)`):
       - Заменить на `row.failedProbeCount = agg.failures` — точное целое, без truncation.

    **CR-02 — Same-context delete in `confirmDeleteSubscription` (lines 233-266):**

    5. Заменить блок lines 250-257:
       ```
       let lookupID: UUID = subscription.id
       let subRowDesc = FetchDescriptor<Subscription>(predicate: #Predicate { $0.id == lookupID })
       if let row = try? context.fetch(subRowDesc).first {
           context.delete(row)
       } else {
           context.delete(subscription)   // <-- CR-02: caller's foreign-context object
       }
       ```
       на early-return-on-missing:
       ```
       let lookupID: UUID = subscription.id
       let subRowDesc = FetchDescriptor<Subscription>(predicate: #Predicate { $0.id == lookupID })
       guard let row = try? context.fetch(subRowDesc).first else {
           // Subscription already gone from store (concurrent delete или non-persisted).
           // НЕ удаляем caller's `subscription` — он может быть из другого ModelContext;
           // SwiftData cross-context delete = undefined behaviour. Просто завершаем.
           pendingDeleteSubscription = nil
           await loadFromStore()
           return
       }
       context.delete(row)
       ```
       Дополнительная очистка состояния (`pendingDeleteSubscription = nil`, `await loadFromStore()`, проверка `coordinator?.selectedServerID` на удалённую подписку) остаётся в основной ветке после `context.save()` — uncovers single-path-of-success.

    6. Запустить `swift test --package-path BBTB/Packages/VPNCore` для проверки CR-05 совместимости с ProbeAggregate тестами.

    7. Запустить `swift test --package-path BBTB/Packages/AppFeatures` для проверки CR-02 + CR-05 callsite в ServerListViewModel.

    8. Commit: `fix(03-G1/CR-02,CR-05): same-context delete + raw failures count`.
  </action>
  <verify>
    <automated>cd /Users/vergevsky/ClaudeProjects/VPN && swift test --package-path BBTB/Packages/VPNCore 2>&1 | tail -10 && swift test --package-path BBTB/Packages/AppFeatures 2>&1 | tail -10</automated>
  </verify>
  <acceptance_criteria>
    - `grep -q "public let failures: Int" BBTB/Packages/VPNCore/Sources/VPNCore/ProbeResult.swift`
    - `grep -E "failures: failures" BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift` matches
    - `grep -c "Int(agg.lossRate \\* 3)" BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` == 0 (CR-05 truncation removed)
    - `grep -q "row.failedProbeCount = agg.failures" BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift`
    - `grep -c "context.delete(subscription)" BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` == 0 (cross-context delete removed)
    - `grep -A2 "guard let row = try? context.fetch(subRowDesc).first" BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift | grep -q "return"` (early-return pattern present)
    - Command `swift test --package-path BBTB/Packages/VPNCore` exits 0
    - Command `swift test --package-path BBTB/Packages/AppFeatures` exits 0
    - Git log shows commit "fix(03-G1/CR-02,CR-05): same-context delete + raw failures count"
  </acceptance_criteria>
  <done>ProbeAggregate.failures хранит точный count; ServerListViewModel пишет `agg.failures` напрямую (CR-05 закрыт); confirmDeleteSubscription никогда не зовёт `context.delete(subscription)` с caller-supplied foreign-context объектом (CR-02 закрыт); VPNCore + AppFeatures suites GREEN.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| External subscription URL → URLSession | Untrusted user-supplied URL пересекает в сетевой стек. CR-03 закрывает SSRF через hostname blocklist. |
| Keychain payload → AnyParsedConfig reconstruction | Untrusted SwiftData state (например after migration corruption) пересекает в производство sing-box config. CR-01 fix фиксирует контракт: decode failure для manually-selected server = error, не silent substitution. |
| Caller-supplied `Subscription` instance → ModelContext.delete | Cross-context delete = undefined behaviour в SwiftData. CR-02 фикс перекрывает foreign object из caller'а через id-lookup. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-03-06 (closure) | I (Information Disclosure) / E (Elevation) | `SubscriptionURLFetcher.fetch` | mitigate | CR-03 task 1: hostname blocklist для loopback/link-local/RFC-1918/multicast — закрывает декларацию из 03-01-PLAN.md threat model, которая была не реализована. |
| T-G1-01 | T (Tampering) | `provisionTunnelProfile(for:)` silent fallback | mitigate | CR-01 task 2: strict guard на selectedID — при decode failure throw `ImporterError.configBuildFailed`. UI surfaces error через existing error state в MainScreenView; нет молчаливого подключения к чужому серверу. |
| T-G1-02 | T (Tampering) | Non-deterministic isActive после merge | mitigate | CR-04 task 2: сбрасываем isActive=false на всех ServerConfig перед установкой; sort by id.uuidString для воспроизводимого выбора `first`. |
| T-G1-03 | D (DoS) | SwiftData cross-context delete crash | mitigate | CR-02 task 3: early-return при отсутствии row, never delete caller's foreign-context object. |
| T-G1-04 | T (Tampering) | `failedProbeCount` corruption через IEEE-754 truncation | mitigate | CR-05 task 3: ProbeAggregate.failures прокидывает raw count из ServerProbeService без floating-point round-trip; `ServerConfig.isUnreachable` (Bool >=3) теперь точен. |
| T-G1-05 | D (DoS) | DNS rebinding атака на blocklist (host разрешается в IP внутри blocked range после bypass-check) | accept | Документировано в комментарии в isBlockedHost(_:); полное DNS resolve внутри fetch требует кастомный URLSession delegate с custom resolver — не Phase 3 scope. Carry-forward для Phase 7 (DPI-08 cert pinning + connection-level checks). |
</threat_model>

<verification>
**Per-task automated verification** (см. `<verify>` в каждом таске).

**Plan-level verification (после всех 3 тасков):**

```bash
# Full test suite green — no regressions:
swift test --package-path BBTB/Packages/VPNCore
swift test --package-path BBTB/Packages/ConfigParser
swift test --package-path BBTB/Packages/AppFeatures

# CR-05: no truncation pattern anywhere:
grep -rn "Int(.*lossRate.*\\* 3)" BBTB/Packages/ | grep -v "// " | wc -l   # MUST be 0

# CR-01: no silent-fallback pattern in provisionTunnelProfile:
grep -A3 "selectedID" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift | \
  grep -c "parsedList.isEmpty && targets.count == 1"   # MUST be 0

# CR-02: no cross-context delete:
grep -c "context.delete(subscription)" BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift   # MUST be 0

# CR-03: blocklist symbols present:
grep -q "FetchError.blockedHost\\|isBlockedHost" BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift

# CR-04: clear-before-set pattern present:
grep -B2 "isActive = true" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift | \
  grep -c "isActive = false"   # MUST be >= 1

# CR-05: agg.failures wired to failedProbeCount:
grep -q "row.failedProbeCount = agg.failures" BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift
```

**Per-CR gap closure check (matches VERIFICATION.md gaps):**
- CR-01 → "provisionTunnelProfile connects to the server the user explicitly selected" — throw guard verified
- CR-02 → "Deleting a subscription removes it exactly once" — early-return pattern verified
- CR-03 → "Subscription URL fetch blocks internal/localhost/private-range SSRF" — 9 unit tests verified
- CR-04 → "isActive flag accurately reflects active server" — clear+sort+set verified
- CR-05 → "Auto-select correctly derives isUnreachable and score" — direct failures count verified
</verification>

<success_criteria>
1. ✅ `swift test --package-path BBTB/Packages/VPNCore` exits 0 (32+ tests)
2. ✅ `swift test --package-path BBTB/Packages/ConfigParser` exits 0 (83+9 tests = 92+)
3. ✅ `swift test --package-path BBTB/Packages/AppFeatures` exits 0 (37+ tests, no regressions)
4. ✅ CR-01 закрыт — provisionTunnelProfile(for:) с selectedID и decode failure throws ImporterError.configBuildFailed (verified в коде)
5. ✅ CR-02 закрыт — confirmDeleteSubscription никогда не зовёт `context.delete(subscription)` с caller's foreign object (grep == 0)
6. ✅ CR-03 закрыт — 9 новых tests для blocked hosts GREEN; `FetchError.blockedHost` существует и throw'ится для loopback/link-local/RFC-1918/multicast
7. ✅ CR-04 закрыт — savedConfigs.sorted by id.uuidString + предварительный isActive=false reset на всех серверах перед установкой первого
8. ✅ CR-05 закрыт — ProbeAggregate.failures: Int exposed; ServerListViewModel пишет `agg.failures` напрямую; `Int(agg.lossRate * 3)` нет в коде нигде
9. ✅ 3 commits в git log: `fix(03-G1/CR-03):`, `fix(03-G1/CR-01,CR-04):`, `fix(03-G1/CR-02,CR-05):`
10. ✅ Phase 3 ROADMAP SC-2 теперь VERIFIED (был PARTIAL) — auto-select numerically reliable
</success_criteria>

<output>
After completion, create `.planning/phases/03-server-management/03-G1-SUMMARY.md` следуя summary template. Особое внимание:
- Какие тесты были добавлены/изменены (SubscriptionURLFetcherTests +9; ProbeAggregate(...) callsite migration в test mocks)
- ВСЕ 5 critical findings закрыты с reference на конкретные commits
- T-03-06 в Phase 3 threat model теперь действительно mitigated (исправляем расхождение между декларацией и кодом из Plan 01)
- Phase 3 closure recommendation: после Plan G1 → `/gsd-verify-work 3` retry для подтверждения VERIFIED статуса
- Carry-forward: 11 warnings (WR-01..WR-11) из 03-REVIEW.md остаются ОТКРЫТЫМИ — они НЕ блокирующие, документировать в STATE.md «Phase 3 carry-forward» для будущих фаз (Phase 11 UX polish / Phase 4 schema migration / Phase 7 DPI-08).
</output>
