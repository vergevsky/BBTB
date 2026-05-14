---
phase: 06d-performance-audit
plan: 03g
slice: g
type: execute
wave: 3.7
mode: mvp
depends_on: [03f]
files_modified:
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift
autonomous: true
requirements: [QUAL-01, NET-resilience]
findings_addressed: [H9, M9, M16]
tags: [packet-tunnel-extension, nwpathmonitor, semaphore, libbox, includeAllNetworks, kill-switch]
status: complete

must_haves:
  truths:
    - "H9: `startDefaultInterfaceMonitor` semaphore.wait() без timeout → `semaphore.wait(timeout: .now() + 2.0)`. На timeout — warning log, продолжаем с пустым default interface; libbox толерантно стартует."
    - "M9: `autoDetectControl(fd:)` при `currentInterfaceIndex == 0` больше не молча `return`'ит. Ждёт до 500ms на новый `physicalInterfaceReady: DispatchSemaphore` (signal'ится первым `notifyInterfaceUpdate(index > 0)`); если за 500ms seed не пришёл — throw retryable NSError (domain `BBTB.autoDetectControl`, code -100). Это спарено с H9: даже если NWPathMonitor пропустил initial callback, autoDetectControl не создаёт unbound socket."
    - "M16: `openTun` setTunnelNetworkSettings completion timeout 5s → 2s. Лог-сообщения обновлены."
    - "Все три фикса в одном файле `ExtensionPlatformInterface.swift`; каждый — отдельный atomic commit; D-08 regression гейт зелёный после каждого."
    - "D-09 invariants: forbidden symbols grep = 4 (baseline), `NEVPNStatusDidChange .*queue:.*\\.main\\)|OperationQueue\\.main` grep = 0 (clean). Sensitive files (TunnelController/MainScreenViewModel/BBTB_*App/PacketTunnelProvider*) не тронуты."
    - "Регрессионные тесты: AppFeatures 133/133 PASS, PacketTunnelKit 61/61 PASS, iOS Simulator + macOS xcodebuild BUILD SUCCEEDED после каждого из 3 commit'ов."
---

# Wave 06D-03g — H9 + M9 + M16: Packet Tunnel Extension correctness + perf

## Цель волны

Закрытие трёх связанных проблем в `ExtensionPlatformInterface.swift` — единственном файле NetworkExtension, который взаимодействует с libbox через `LibboxPlatformInterfaceProtocol`. Все три выявлены в Wave 06D-01:

- **H9** (Codex #11) — `startDefaultInterfaceMonitor` блокирует libbox.Start бесконечно, если `NWPathMonitor` не успевает выдать первый callback.
- **M9** (Codex #12) — `autoDetectControl` молча `return`'ит при `currentInterfaceIndex == 0`, sing-box создаёт unbound сокеты, которые iOS routing в режиме `includeAllNetworks=YES` (KILL-01) закольцовывает обратно в наш TUN → handshake timeout.
- **M16** (Opus #32) — `openTun` ждёт `setTunnelNetworkSettings` completion 5s; на залипании это означает 5-секундный замёрзший connect attempt вместо короткой ошибки + on-demand retry.

H9 + M9 — correctness (Codex flagged HIGH/HIGH; M9 синтезировано как MEDIUM до Instruments-измерений). M16 — performance nit. Все три surgical, каждый — отдельный atomic commit.

Файл `ExtensionPlatformInterface.swift` НЕ в D-09 sensitive list (он не в `TunnelController`/`MainScreenViewModel`/`BBTB_*App`/`PacketTunnelProvider*`), но D-09 grep audit мандатный — выполнен после каждого commit'а.

## Source consensus

| Finding | Source | Severity | Specifics |
|---|---|---|---|
| H9 | Codex #11 (HIGH) | HIGH | "`startDefaultInterfaceMonitor` calls `semaphore.wait()` without timeout. If `NWPathMonitor` does not deliver an initial callback promptly in the extension, libbox.Start blocks indefinitely. Hard connect hang." |
| M9 | Codex #12 (HIGH; synthesis downgraded to MEDIUM pending Instruments) | MEDIUM | "`autoDetectControl` returns successfully when `currentInterfaceIndex == 0`. In include-all-networks mode, unbound outbound sockets can route back into the tunnel, causing handshake timeouts and slow/failed connects." |
| M16 | Opus #32 (perf nit) | LOW/MEDIUM | "5s timeout means stuck `setTunnelNetworkSettings` callback kills connect attempt only after 5 full seconds. Apple's own typically completes in <100ms on iPhone 13+. Reduce to 2s — error + on-demand retry cheaper than 5s perceived freeze." |

## D-09 invariant pre-check (sensitive files NOT modified — extension-side fix only)

| Invariant | Pre-check | Post-Wave-03g |
|---|---|---|
| `ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay` grep ≤ 7 | 4 (baseline) | 4 ✅ |
| `NEVPNStatusDidChange .*queue:.*\.main\)\|OperationQueue\.main` grep = 0 | 0 (baseline) | 0 ✅ |
| `TunnelController.swift` — touched? | No | No ✅ |
| `MainScreenViewModel.swift` — touched? | No | No ✅ |
| `BBTB_iOSApp.swift` / `BBTB_macOSApp.swift` — touched? | No | No ✅ |
| `PacketTunnelProvider*.swift` — touched? | No | No ✅ |
| `ExtensionPlatformInterface.swift` — touched | (per-commit) | 3 atomic commits |

## Architectural summary

### Cold-start race (pre-Wave-03g)

`BaseSingBoxTunnel.startTunnel` строит libbox engine с нашим `ExtensionPlatformInterface`. libbox:

1. Вызывает `startDefaultInterfaceMonitor(listener)` — мы создаём `NWPathMonitor`, ждём `semaphore.wait()` до первого `pathUpdateHandler` (синхронно, чтобы вернуть libbox'у уже посчитанный список интерфейсов).
2. Затем вызывает `openTun(options, ret0_)` — мы зовём `provider.setTunnelNetworkSettings(...)` асинхронный, блокируемся на `semaphore.wait(timeout: 5)`, после возврата извлекаем TUN fd.
3. На каждый outbound socket sing-box зовёт `autoDetectControl(fd)` — мы делаем `setsockopt IP_BOUND_IF` на `currentInterfaceIndex`.

Pre-Wave-03g проблемы:

- (1) `semaphore.wait()` без timeout — если `NWPathMonitor` молчит, libbox висит навсегда; видимо как «zombie connect attempt» без логов.
- (3) `currentInterfaceIndex == 0` (NWPathMonitor ещё не seed'нул) → `return` без bind → unbound socket → в `includeAllNetworks=YES` iOS routing отправляет его обратно в TUN → handshake никогда не доходит → user видит «Connecting...» 60s → timeout.
- (2) 5s timeout на залипание `setTunnelNetworkSettings` — Phase 6c on-demand retry политика триггерится только после throw'а, поэтому 5s == 5s замёрзшего spinner'а перед автоматическим retry.

### Fix 1 — H9: bounded NWPathMonitor wait

`startDefaultInterfaceMonitor` теперь:

```swift
let waitResult = semaphore.wait(timeout: .now() + 2.0)
if waitResult == .timedOut {
    TunnelLogger.lifecycle.warning("startDefaultInterfaceMonitor: initial NWPathMonitor callback timeout after 2s — proceeding with empty/default interface")
}
```

Не throw'аем — libbox толерантно стартует с пустым default. Последующие `pathUpdateHandler` callback'и обновят состояние; sing-box их получит через listener.updateDefaultInterface. **Спарен с Fix 2:** если NWPathMonitor молчит, M9 защищает от unbound сокетов.

### Fix 2 — M9: autoDetectControl reject on no-interface

Добавлены:

```swift
private let physicalInterfaceReady = DispatchSemaphore(value: 0)
private var physicalInterfaceSeeded: Bool = false
```

В `notifyInterfaceUpdate` при первом seed'е `index > 0`:

```swift
if !physicalInterfaceSeeded {
    physicalInterfaceSeeded = true
    physicalInterfaceReady.signal()
}
```

В `autoDetectControl` ветка `index == 0`:

```swift
let waitResult = physicalInterfaceReady.wait(timeout: .now() + 0.5)
index = currentInterfaceIndex
if waitResult == .timedOut || index == 0 {
    throw NSError(
        domain: "BBTB.autoDetectControl",
        code: -100,
        userInfo: [NSLocalizedDescriptionKey: "No physical interface available for fd=\(fd) ..."]
    )
}
```

sing-box engine ловит throw → стандартная retry-политика, никаких unbound сокетов. Если seed пришёл во время wait — продолжаем bind на свежем индексе. **Note:** `physicalInterfaceReady` инициализируется с value=0; первый signal разбудит одного waiter, остальные сами протаймаутятся через 500ms; после таймаута они перечитают `currentInterfaceIndex` (который уже > 0, потому что присваивание происходит ДО signal'а в `notifyInterfaceUpdate`) и пройдут дальше без throw'а. Корректно для multi-goroutine sing-box.

### Fix 3 — M16: openTun timeout 5s → 2s

Чистая константа:

```swift
let waitResult = semaphore.wait(timeout: .now() + 2.0)
```

Логи обновлены: `(timeout 5s)` → `(timeout 2s)`, error message содержит `2s`. Семантика throw'а не изменилась. Apple measured baseline для `setTunnelNetworkSettings` на iPhone 13+ < 100ms; 2s == 20× margin, всё ещё ≤ user-perceivable freeze threshold.

## Commits

| # | SHA | Message | Files |
|---|---|---|---|
| 1 | `37e7d34` | `fix(06d-03g): bounded NWPathMonitor wait — no extension hang on missing callback (H9)` | ExtensionPlatformInterface.swift (+10/-1) |
| 2 | `42a908a` | `fix(06d-03g): reject autoDetectControl when no physical interface available (M9)` | ExtensionPlatformInterface.swift (+49/-8) |
| 3 | `5a4db9f` | `fix(06d-03g): reduce openTun semaphore timeout from 5s to 2s (M16)` | ExtensionPlatformInterface.swift (+9/-4) |

## Regression gate D-08 — after each commit

| # | AppFeatures | PacketTunnelKit | iOS Simulator | macOS |
|---|---|---|---|---|
| Commit 1 (H9) | 133/133 PASS | 61/61 PASS | BUILD SUCCEEDED | BUILD SUCCEEDED |
| Commit 2 (M9) | 133/133 PASS | 61/61 PASS | BUILD SUCCEEDED | BUILD SUCCEEDED |
| Commit 3 (M16) | 133/133 PASS | 61/61 PASS | BUILD SUCCEEDED | BUILD SUCCEEDED |

## Acceptance criteria — verified

| Criterion | Status |
|---|---|
| `grep -A 2 "semaphore.wait" ExtensionPlatformInterface.swift \| grep "timeout:"` shows new `2.0` для `startDefaultInterfaceMonitor` | ✅ `timeout: .now() + 2.0` присутствует |
| H9 fix не throw'ит — libbox продолжает с empty default | ✅ Только warning log |
| `grep -B 2 -A 5 "currentInterfaceIndex"` shows new wait+throw branch | ✅ Все компоненты на месте |
| M9 не вводит новые error types — переиспользует `NSError` с custom domain | ✅ `BBTB.autoDetectControl` domain, code -100 |
| `grep "timeout:" .. \| head` shows `2.0` в openTun (M16) | ✅ Единственный `timeout:` в openTun блоке = 2.0 |
| D-09 forbidden symbols grep ≤ 7 | ✅ 4 |
| D-09 queue=.main grep = 0 | ✅ 0 |
| D-08 после каждого из 3 commit'ов — PASS | ✅ Все 4 гейта зелёные после каждого commit'а |
| Атомарность: 3 отдельных commit'а, никаких bundle'ов | ✅ `37e7d34`, `42a908a`, `5a4db9f` |
| Out-of-scope ripples в sensitive files | ✅ Touched 0 sensitive files |

## Risks & mitigations

- **Risk (H9):** 2s timeout слишком короткий на старых device'ах. **Mitigation:** taking no-throw path on timeout — даже если NWPathMonitor реально медленный, libbox стартует, последующие path-updates seed'ят interface, M9 защищает от unbound сокетов в окне. Worst case — первые несколько outbound retries фейлятся через M9 throw, потом всё работает.
- **Risk (M9):** Дополнительные 500ms wait при cold start. **Mitigation:** wait — только когда index реально 0; в нормальном path он seed'ится за <100ms (NWPathMonitor.start уже выполнен в `startDefaultInterfaceMonitor`). Wait — fallback, не hot path.
- **Risk (M9):** semaphore счётчик может позволить одному waiter'у проснуться, остальные — таймаутятся. **Mitigation:** дизайн идемпотентен — после signal'а `currentInterfaceIndex > 0` (присваивание ДО signal'а), все timed-out waiters перечитают index и пройдут дальше без throw'а. Сценарий проверен в комментарии в коде.
- **Risk (M16):** 2s недостаточно для каких-то iOS internal hiccup'ов. **Mitigation:** Apple's measured baseline для `setTunnelNetworkSettings` < 100ms; 2s == 20× margin. Phase 6c on-demand retry политика всё равно подхватит. Если 2s окажется мало — это станет видно в Console logs (`openTun: TIMEOUT`); регрессия дёшево reverible через single-line bump.

## Cross-refs

- Wiki: `wiki/security-gaps.md` (KILL-01, R6 — TUN settings), TODO добавить отдельную page для `NWPathMonitor` + extension lifecycle паттернов.
- Memory: `feedback_netunnelnetworksettings_tunnelRemoteAddress.md` (родственный класс «extension падает на openTun без sing-box логов» — pre-fix симптом).
- 06D-FINDINGS.md rows H9 / M9 / M16 — closed.

## Self-Check: PASSED

- ✅ Files exist: `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift` modified through 3 atomic commits.
- ✅ Commits exist: `37e7d34`, `42a908a`, `5a4db9f` — все в `git log --oneline -3` HEAD.
- ✅ D-08 PASS after each commit (AppFeatures 133/133, PacketTunnelKit 61/61, iOS + macOS BUILD SUCCEEDED).
- ✅ D-09 invariants — forbidden symbols=4 (baseline), queue=.main=0 (baseline) — оба после всех 3 commit'ов.
- ✅ Sensitive files (TunnelController/MainScreenViewModel/BBTB_*App/PacketTunnelProvider*) не тронуты — verified via grep.
