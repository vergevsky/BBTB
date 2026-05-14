---
phase: 06d-performance-audit
plan: 03h
slice: h
type: execute
wave: 3.8
mode: mvp
depends_on: [03g]
files_modified:
  - BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift
  - BBTB/Packages/Protocols/VLESSTLS/Tests/VLESSTLSTests/BuildOutboundTests.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift
autonomous: true
requirements: [QUAL-01]
findings_addressed: [M12, M13, M14]
tags: [vlesstls, ws-transport, sni-fallback, server-list, swiftdata, ondemand-migration, notification-contract]
status: complete

must_haves:
  truths:
    - "M12: VLESS+TLS `buildOutbound` теперь подставляет SNI как WS Host header когда `transport == .ws(_, host: \"\")`. Mirror Trojan special-case (ConfigBuilder.swift:160-165). Option A выбран вместо unified `sniFallback:` (Option B), потому что Option B менял бы signature всех 5 TransportHandler — слишком инвазивно."
    - "M13: `pingAllServers` cleanup `.pinging → .idle` теперь в `defer { Task @MainActor }` — guarantees cleanup на ВСЕХ exit-paths (normal, cancellation, throw). `try? context.save()` swallow заменён на explicit `do/catch` с surface через `refreshError` (не overwrite-ает existing)."
    - "M14: `OnDemandMigrationTask` posts `.bbtbProvisionerDidSave` с `object: ours.first` вместо `object: nil` — соответствует contract'у в ManagerSelector.swift:90 (`NETunnelProviderManager?`). Контракт consistency: 4/4 callsites теперь uniform."
    - "Все три фикса в трёх атомарных commit'ах; D-08 regression гейт зелёный после каждого."
    - "D-09 invariants: forbidden symbols grep = 1 (≤ 7 baseline), queue=.main grep = 0 (baseline). Sensitive files (TunnelController/MainScreenViewModel/BBTB_*App/PacketTunnelProvider*) не тронуты."
    - "Регрессионные тесты: AppFeatures 133/133 PASS, VLESSTLS 20/20 (+1 новый M12 тест), TransportRegistry 42/42, iOS Simulator + macOS xcodebuild BUILD SUCCEEDED после каждого из 3 commit'ов."
---

# Wave 06D-03h — M12 + M13 + M14: App-level correctness bugs

## Цель волны

Закрытие трёх не связанных между собой correctness bug'ов из FINDINGS.md (раздел 1/3 unique-but-valuable, Opus-only). Все три — узко-локальные surgical fix'ы; ни один не затрагивает D-09 sensitive list.

- **M12** (Opus #15) — VLESS+TLS `buildOutbound` не подставляет SNI в WS Host header когда URI не содержит `&host=`. Большинство CDN отвергают WS upgrade без Host header → **активный connectivity bug** для VLESS+TLS+WS пользователей.
- **M13** (Opus #18) — `pingAllServers` rows могут застрять в `.pinging` если outer Task cancelled mid-stream (cleanup стоял ПОСЛЕ for-await loop). Параллельно — `try? context.save()` swallow тихо rollback'ал latency mutations.
- **M14** (Opus #19) — `OnDemandMigrationTask` posts `.bbtbProvisionerDidSave` с `object: nil`, в то время как documented contract в `ManagerSelector.swift:90` декларирует `NETunnelProviderManager?`. Единственный outlier против ConfigImporter.swift:1251 и SettingsViewModel.swift:191.

Все три — отдельные atomic commit'ы.

## Source consensus

| Finding | Source | Severity | Specifics |
|---|---|---|---|
| M12 | Opus #15 (MEDIUM) — 1/3 unique-but-valuable | MEDIUM | "Unlike Trojan, VLESS+TLS `buildOutbound` does NOT substitute SNI when WS host is empty. It just delegates to TransportRegistry, which produces a WS block with no `Host` header. Most CDNs reject WS upgrades without a Host header. **Active connectivity bug** for VLESS+TLS+WS users whose URI omits `&host=`." |
| M13 | Opus #18 (MEDIUM) — 1/3 unique-but-valuable | MEDIUM | "The 'reset to .idle' loop runs AFTER the for-await loop exits. If the outer Task is cancelled mid-stream, control returns through cancellation; ... if SwiftData's `try? context.save()` throws and is silently swallowed, the in-memory `lastLatencyMs` mutation is rolled back on the next fetch and pingStates remains stale." |
| M14 | Opus #19 (MEDIUM) — 1/3 unique-but-valuable | MEDIUM | "TunnelController's provisioner observer uses the notification only to trigger `refreshCachedManager()`. But other future observers (and the documented contract in `ManagerSelector.swift:90` 'object: NETunnelProviderManager?') expect the manager. Inconsistent contract." |

## D-09 invariant pre-check (sensitive files NOT modified)

| Invariant | Pre-check | Post-Wave-03h |
|---|---|---|
| `ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay` grep ≤ 7 | 1 (baseline) | 1 ✅ |
| `NEVPNStatusDidChange .*queue:.*\.main\)\|OperationQueue\.main` grep = 0 | 0 (baseline) | 0 ✅ |
| `TunnelController.swift` — touched? | No | No ✅ |
| `MainScreenViewModel.swift` — touched? | No | No ✅ |
| `BBTB_iOSApp.swift` / `BBTB_macOSApp.swift` — touched? | No | No ✅ |
| `PacketTunnelProvider*.swift` — touched? | No | No ✅ |

Touched (NOT sensitive):
- `VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift` — protocol-side buildOutbound (Commit 1).
- `VLESSTLS/Tests/VLESSTLSTests/BuildOutboundTests.swift` — regression test (Commit 1).
- `AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` — VM cleanup (Commit 2).
- `AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` — notification post site (Commit 3).

## Architectural summary

### Fix 1 — M12: VLESS+TLS WS empty-host → SNI fallback

**До:** `VLESSTLS.ConfigBuilder.buildOutbound` без условия делегировал `transport`-блок в `TransportRegistry.shared.handler(for: "ws").buildTransportBlock(...)`. `WSTransportHandler` (по контракту "Empty host invariant" в `WSTransportHandler.swift:14-17`) при empty host **намеренно** опускал `headers` ключ — caller (protocol package) должен подставить SNI. Trojan уже имел эту подстановку (`Trojan/ConfigBuilder.swift:159-169`); VLESS+TLS — нет → активный connectivity bug для URI без `&host=`.

**После:**

```swift
// Phase 6d / Wave 06D-03h — M12 fix. Special-case: WS with empty host →
// substitute SNI as Host header (mirror Trojan/ConfigBuilder.swift:160-165).
if case let .ws(path, wsHost) = transport, wsHost.isEmpty {
    outbound["transport"] = [
        "type": "ws",
        "path": path,
        "headers": ["Host": parsed.sni],
    ] as [String: Any]
} else if let block = TransportRegistry.shared.handler(for: transport.identifier)?
    .buildTransportBlock(for: transport) {
    outbound["transport"] = block
}
```

**Option A vs Option B decision:** Бриф предложил Option B (unified `sniFallback:` параметр в `WSTransportHandler.buildTransportBlock`) — но это меняло бы signature всех 5 `TransportHandler`-реализаций (TCP/WS/HTTP/HTTPUpgrade/GRPC), TransportRegistry dispatch, и 3 ассерта в `WSTransportHandlerTests` на existing "empty host omits headers" контракт. Слишком инвазивно для focused correctness fix. **Выбран Option A** — 12-строчный mirror Trojan-паттерна. Контракт `WSTransportHandler` preserved (sniFallback остаётся caller-side concern). Documented в commit message.

**Regression test** (`test_vlessTLS_ws_outbound_emptyHost_usesSNI`) — mirror Trojan `test_trojan_ws_outbound_emptyHost_usesSNI`:

```swift
let parsed = makeParsed(sni: "sni.example.com")
let result = ConfigBuilder.buildOutbound(from: parsed, transport: .ws(path: "/x", host: ""), tag: "t")
// transport.type == "ws", path == "/x", headers.Host == "sni.example.com"
```

### Fix 2 — M13: pingAllServers cancellation-safe

**Pre-Wave-03h два бага:**

1. **Eager `.pinging` init + cleanup-after-loop:** `for srv in supported { pingStates[srv.id] = .pinging }` устанавливался ДО for-await; cleanup `for id in pingStates.keys where pingStates[id] == .pinging { pingStates[id] = .idle }` стоял ПОСЛЕ for-await. При cancellation mid-stream cleanup всё-таки выполнялся, но если Task cancelled между eager init и началом for-await — некоторые rows могли остаться `.pinging`. `LatencyBadge` спиннер крутится бесконечно до следующего `loadFromStore()`.

2. **Silent SwiftData save errors:** `try? context.save()` swallow'ал ошибки. SwiftData rollback на следующем fetch означал что `lastLatencyMs` mutations silently disappeared — пользователь видел latency badges, которые мгновенно reverted.

**После:**

```swift
let supportedIDs: [UUID] = supported.map(\.id)
for srv in supported { pingStates[srv.id] = .pinging }

defer {
    let captureIDs = supportedIDs
    Task { @MainActor [weak self] in
        guard let self else { return }
        for id in captureIDs where self.pingStates[id] == .pinging {
            self.pingStates[id] = .idle
        }
    }
}

for await (id, agg) in probeService.probeAll(payload) { ... }

do {
    try context.save()
} catch {
    Self.log.error("pingAllServers: SwiftData save failed: \(error.localizedDescription, privacy: .public)")
    if refreshError == nil {
        refreshError = L10n.serverListRefreshErrorMessage
    }
}
```

**Decision notes:**
- Snapshot `supportedIDs` upfront — избегаем capture SwiftData models в defer (они могут принадлежать context'у, который уже закрыт).
- `Task { @MainActor [weak self] }` обязателен — `defer` исполняется в текущем actor context, но @Published mutation требует MainActor.
- `refreshError` не overwrite-ается если уже non-nil — pull-to-refresh partial-failure messages preserved.

### Fix 3 — M14: OnDemandMigrationTask posts manager object

**Contract в `ManagerSelector.swift:88-90`:**

```swift
/// `object` параметр notification: `NETunnelProviderManager?` — наш
/// только что сохранённый manager (опционально, для удобства observer'а).
public static let bbtbProvisionerDidSave = Notification.Name("app.bbtb.provisionerDidSave")
```

**Audit 4 call-/observer-sites:**

| Site | File:Line | Before | After |
|---|---|---|---|
| Producer 1 | `ConfigImporter.swift:1251` | `object: manager` ✓ | unchanged |
| Producer 2 | `SettingsViewModel.swift:191` | `object: manager` (per-iter) ✓ | unchanged |
| Producer 3 | `OnDemandMigrationTask.swift:115` | `object: nil` ❌ | `object: ours.first` ✓ |
| Observer | `TunnelController.swift:489` | `_ in` (ignores object) | unchanged — additive change безопасен |

**Single-post vs loop-per-manager decision:** B-03 design comment (OnDemandMigrationTask.swift:21) явно говорит "post `.bbtbProvisionerDidSave` один раз — TunnelController рефрешит `cachedManager`". Это intended pattern для batch migration. `SettingsViewModel` posts per-manager только потому что toggle handler iterate-ит по нашим managers и сохраняет каждый individually. Здесь — batch atomicity, post once.

**Multi-manager safety:** `ours` массив фильтруется через `ManagerSelector.ourManagers` (B-06); typical iOS установка имеет 0 или 1 наших managers. Если 2+ (residue) — `ours.first` берёт primary, остальные доступны через follow-up `loadAllFromPreferences()` если observer хочет; refresh идемпотентен.

## Commits

| # | SHA | Message | Files |
|---|---|---|---|
| 1 | `1621a08` | `fix(06d-03h): VLESS+TLS WS host fallback to SNI when &host= omitted (M12)` | VLESSTLS/Sources/.../ConfigBuilder.swift (+18/-4), VLESSTLS/Tests/.../BuildOutboundTests.swift (+22/-0) |
| 2 | `61f60a3` | `fix(06d-03h): pingAllServers cancellation-safe — defer cleanup + surface save errors (M13)` | ServerListFeature/ServerListViewModel.swift (+40/-5) |
| 3 | `b6996cb` | `fix(06d-03h): OnDemandMigrationTask posts bbtbProvisionerDidSave with manager object (M14)` | MainScreenFeature/OnDemandMigrationTask.swift (+15/-1) |

## Regression gate D-08 — after each commit

| # | AppFeatures | VLESSTLS | TransportRegistry | iOS Simulator | macOS |
|---|---|---|---|---|---|
| Commit 1 (M12) | 133/133 PASS | 20/20 PASS (incl. new M12 test) | 42/42 PASS | BUILD SUCCEEDED | BUILD SUCCEEDED |
| Commit 2 (M13) | 133/133 PASS | n/a (unchanged) | n/a (unchanged) | BUILD SUCCEEDED | BUILD SUCCEEDED |
| Commit 3 (M14) | 133/133 PASS (incl. OnDemandMigrationTaskTests 5/5) | n/a (unchanged) | n/a (unchanged) | BUILD SUCCEEDED | BUILD SUCCEEDED |

## Acceptance criteria — verified

| Criterion | Status |
|---|---|
| `grep -n "host.*sni\|sniFallback\|host:.*parsed.sni"` в VLESSTLS/ConfigBuilder.swift shows new fallback | ✅ `"headers": ["Host": parsed.sni]` присутствует на новой line |
| VLESSTLS test `test_vlessTLS_ws_outbound_emptyHost_usesSNI` PASS | ✅ green |
| `grep -B 2 -A 8 "pingAllServers"` shows `defer { ... }` block | ✅ defer block с Task @MainActor |
| `grep -n "context.save"` shows `do/catch` вместо `try?` swallow | ✅ explicit do/catch + refreshError surface |
| `grep -n "bbtbProvisionerDidSave.*object:"` в OnDemandMigrationTask shows non-nil object | ✅ `object: ours.first` |
| All `.bbtbProvisionerDidSave` producers post non-nil object | ✅ 3/3 producers consistent |
| `ManagerSelector.swift:90` doc-comment contract matched | ✅ `NETunnelProviderManager?` |
| D-09 forbidden symbols grep ≤ 7 | ✅ 1 |
| D-09 queue=.main grep = 0 | ✅ 0 |
| D-08 после каждого из 3 commit'ов — PASS | ✅ Все 4 гейта зелёные после каждого commit'а |
| Атомарность: 3 отдельных commit'а, никаких bundle'ов | ✅ `1621a08`, `61f60a3`, `b6996cb` |
| Out-of-scope ripples в sensitive files | ✅ Touched 0 sensitive files |

## Risks & mitigations

- **Risk (M12, Option A):** Trojan и VLESSTLS теперь обе содержат идентичный 12-строчный special-case. Drift risk если в будущем добавится 3-й protocol с TLS+WS (Hysteria2 etc.). **Mitigation:** L2 finding ("Trojan WS-host fallback duplicates SNI substitution в 2 местах") уже фиксирует это как maintainability item — будущий Wave может консолидировать в Option B (unified `sniFallback:`) если появится 3-й caller. На данный момент 2 callsite consolidation premature.
- **Risk (M13):** `Task { @MainActor }` в `defer` создаёт unstructured Task. Если ServerListViewModel deallocated до выполнения Task — `[weak self]` guard корректно noop'нет. **Mitigation:** capture `[weak self]` всегда; if `self` gone, cleanup unnecessary anyway.
- **Risk (M13):** `refreshError` mutation внутри `pingAllServers` может перекрыть future caller's expectations. **Mitigation:** мы пишем только если он nil; пользовательские pull-to-refresh partial-failure messages preserved. Logic документирована в коде.
- **Risk (M14):** Future observer может ожидать `object: [NETunnelProviderManager]` (массив) если batch'ит 2+ managers. **Mitigation:** документирован в commit message; multi-manager realistic redirection — observer всё равно делает `loadAllFromPreferences()` за полным списком. Existing observers (TunnelController) ignore object — изменение additive-only.

## Cross-refs

- Wiki: TODO добавить page `wiki/wave-06d-03h-correctness-fixes.md` (M12/M13/M14 закрытые баги, pattern "mirror Trojan special-case", `defer` cleanup для cancellation-safe @MainActor mutations, NotificationCenter contract uniformity).
- Memory: `feedback_swiftdata_uuid_predicate.md` (relevant — M13 не использует predicate, fetch-all + Swift filter), `feedback_failover_two_phase_init.md` (M14 observer pattern). 
- 06D-FINDINGS.md rows M12 / M13 / M14 — closed.
- L2 finding (Trojan WS-host duplication) remains open; Option A документирует, что Option B — следующий шаг при появлении 3-го TLS+WS caller.

## Self-Check: PASSED

- ✅ Files exist:
  - `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift` modified.
  - `BBTB/Packages/Protocols/VLESSTLS/Tests/VLESSTLSTests/BuildOutboundTests.swift` modified.
  - `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` modified.
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift` modified.
- ✅ Commits exist: `1621a08` (M12), `61f60a3` (M13), `b6996cb` (M14) — все в `git log --oneline -3` HEAD.
- ✅ D-08 PASS after each commit (AppFeatures 133/133, VLESSTLS 20/20 после Commit 1, TransportRegistry 42/42, iOS + macOS BUILD SUCCEEDED).
- ✅ D-09 invariants — forbidden symbols=1 (≤7 baseline), queue=.main=0 — оба после всех 3 commit'ов.
- ✅ Sensitive files (TunnelController/MainScreenViewModel/BBTB_*App/PacketTunnelProvider*) не тронуты — verified via grep.
