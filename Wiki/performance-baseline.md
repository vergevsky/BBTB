# Performance baseline (Phase 6d + 6e)

**Summary**: Долгосрочная память о производительности приложения BBTB после Phase 6d (Performance & Code Quality Audit, закрыта 2026-05-14) и Phase 6e (Performance Audit Round 2 — tactical cleanup, закрыта 2026-05-14, v0.6.3). Triple-AI peer review (Claude Opus 4.7 + Codex GPT-5.2 + Gemini 3.1 Pro) → 45 findings, 19 закрыто в 6d, 26 carved-out → 19 закрыто в 6e + 5 subsumed-by-6d + 2 deferred (L16/L18). Cold-start ~−500…−1100 мс, connect-tap ~−1000…−3000 мс, disconnect −2.5 сек, плюс корректность и energy-win. Numerical Instruments baseline осознанно skipped (Variant D — user-выбранный trade-off скорости перед UAT); defer к Phase 11/12.

**Sources**:
- `.planning/phases/06d-performance-audit/06D-FINDINGS.md` — полный список из 45 находок (HIGH/MEDIUM/LOW)
- `.planning/phases/06d-performance-audit/06D-COMPARISON.md` — caталог 19 закрытых fix'ов и expected delta
- `.planning/phases/06d-performance-audit/06D-Final-SUMMARY.md` — Phase 6d closure record
- `.planning/phases/06d-performance-audit/06D-UAT.md` — regression smoke PASS (iPhone iOS 26.5, 2026-05-14)
- `.planning/phases/06d-performance-audit/baselines/*` — pre-fix Instruments scaffolds (templates)
- `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md` — Phase 6e closure record (2026-05-14)
- `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-01-SUMMARY.md` — Wave 1 (atomic MEDIUM fixes M7/M10/M8+L12/M11)
- `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-02-SUMMARY.md` — Wave 2 (LOW bundles + Periphery cleanup)

**Last updated**: 2026-05-14 (Phase 6e закрытие)

---

## Зачем эта страница (долгосрочный контекст)

После Phase 5 пользователь заметил, что приложение «тяжело грузится» — медленный cold start, ощутимая пауза при tap Connect, разряд батареи. Phase 6d закрыл это через triple-AI peer review + targeted atomic fixes. Эта страница — память для будущих фаз 7–12: что было до, что стало после, какие архитектурные паттерны установлены, какие 26 findings ждут отдельной cleanup-фазы. Это позволит не повторять аудит с нуля и сразу замечать перформанс-регрессии в Phase 7+.

---

## Sub-страница: ExternalVPNStopMarker (Settings-disable invariant)

Phase 6d post-fix saga (commits `5110ae0` → `9122bbd` → `cff3f46`) добавила authoritative bridge между Packet Tunnel Extension и host через App Group UserDefaults. Это не perf-fix, а correctness-fix критического user-сценария «отключение VPN из iOS Settings → BBTB не должен реактивироваться».

См. `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExternalVPNStopMarker.swift` — sticky marker с `isPending(maxAge: 600)` peek-only API + Apple-canonical `options["manualStart"]` discriminator (по паттерну WireGuard iOS `activationAttemptId`).

---

## Закрытые findings — 19 fix'ов (Option-B scope)

### Cold-start (D-01 primary target)

| ID | Что было | Fix | Expected delta |
|---|---|---|---|
| **H1** | shipping `logLevel: trace` + `exportSingBoxLogToDocuments` на каждый cold-start копировал многомегабайтный лог в Documents синхронно | Trace logging закрыт за `#if DEBUG`, export-call удалён | **−200…−500 мс** + значительная экономия energy |
| **M1** | 6+ fire-and-forget `Task { ... XPC ... }` из `BBTB_iOSApp.init` создавали Mach port contention | Консолидирован в ordered `await TunnelController.bootstrap()` chain | **−50…−150 мс** + UI responsiveness на первом frame |
| **M2** | SwiftData Phase 2→3 migration выполнялась синхронно в `SwiftDataContainer.makeShared()` | Deferred в background `Task.detached(priority: .utility)` | **−200+ мс** для upgrade-юзеров |
| **M3** | `runIsSupportedUpgrade` аллоцировал `UniversalImportParser` per call (×N rows × scene-active triggers) | Single shared instance + deferred off cold-start hot path | **−30…−80 мс** + **−2-5 МБ** memory |
| **M4** | `MainScreenViewModel.refresh()` N+1 SwiftData reads (1 fetch subscriptions + N fetches per subscription для server count) | Inline `selectionReconcile` снижает N+1 до 1 fetch с group-by | **−50…−150 мс** на cold-start + на каждый subscription delta |
| **H6** | `countSupportedConfigs()` использовал `fetchDescriptor.fetch().count` (materializing all `ServerConfig` rows) | `fetchCount(fetchDescriptor)` (SQL `COUNT(*)`) | **−50…−100 мс** на 50-сервер store, квадратично улучшает scaling |
| **H7** | `pendingDeleteSubscriptionServerCount` computed via fetch-all on every body refresh | Кеш `@Published` property, recomputed только on data change | Smoother UI transitions; no fetch-all during sheet animation |

**Total expected cold-start improvement:** **−500…−1100 мс** (conservative).

### Connect-tap (D-01 primary target)

| ID | Что было | Fix | Expected delta |
|---|---|---|---|
| **H2** | `TunnelController.connect()` делал 6 XPC trips (saveToPreferences + loadFromPreferences дважды, isOnDemandEnabled mutation + save, ...) | Consolidated ≤ 2 trips через `applyCurrentStateToCachedManager()` single save+load | **−200+ мс** |
| **H3** | Connect post-startVPNTunnel polling использовал 1-секундный `sleep` loop в ожидании `.connected` (false-latency baseline) | `AsyncStream<NEVPNStatus>` observer-stream с immediate fall-through | **−800 мс** typical Wi-Fi |
| **H4 (part 1)** | Auto-mode pre-connect probe (`pingAllServers`) блокировал tap, ожидая ping ВСЕХ серверов | Bounded concurrency в `ServerProbeService.probeAll` (limit 8) | **−500…−1500 мс** на medium-server stores |
| **H4 (part 2)** | (продолжение) | Cached auto-mode snapshot: connect использует cached ranking если recent (< 30s) | Дополнительный wins on cold-start tap |
| **M5** | `provisionTunnelProfile` читал 3-5 Keychain entries последовательно | Parallel `TaskGroup` — все reads concurrent | **−100…−500 мс** на cold Keychain |

### Connect-tap correctness (perf + correctness)

| ID | Что было | Fix | Impact |
|---|---|---|---|
| **H9** | `NWPathMonitor.start()` + `semaphore.wait()` без timeout — если callback не сработал, extension висел indefinitely | Bounded 2s wait | Eliminate extension hang; failure surfaces в ≤ 2s |
| **M9** | `autoDetectControl` accepted `currentInterfaceIndex == 0` → unbounded socket creation loop | Reject когда no physical interface | Eliminate socket-loop в airplane-mode transitions |
| **M16** | `openTun` semaphore timeout 5s → 2s | Faster failure → retry chain на poor Wi-Fi | |

**Total expected connect-tap improvement:** **−1000…−3000 мс** на typical Wi-Fi tap.

### Disconnect-tap

| ID | Что было | Fix | Expected delta |
|---|---|---|---|
| **H8** | `disconnect()` polled `NEVPNStatus` с `sleep(0.5s) × 10` (fixed 5s window) | Early-exit if already `.disconnected` до polling start (common case) | **−2500 мс** на immediate disconnect path |

### Energy + UI re-render

| ID | Что было | Fix | Expected delta |
|---|---|---|---|
| **H5** | `ConnectionTimer.publish(every: 1)` тикал constantly даже при `.disconnected` | Conditional publisher — ticks только когда `isConnected` | **−100%** Timer callbacks на idle screens; lower GPU + main-actor work |
| **H1** | (см. cold-start) — trace I/O continuous в Release | (см. выше) | Top-3 battery consumer для VPN apps eliminated |

### Correctness (non-perf, user-visible)

| ID | Что было | Fix | Impact |
|---|---|---|---|
| **M12** | VLESS+TLS WS handler fell back to `host=server` когда `&host=` query param пропущен — **breaks active connectivity** | Fallback to SNI value | Active connectivity bug fixed |
| **M13** | `pingAllServers` non-cancellation-safe — Task cancelled mid-stream → UI rows stuck в `.pinging` forever | `defer { setPingStateCompleted }` per row | UI consistency restored |
| **M14** | `OnDemandMigrationTask` posted `bbtbProvisionerDidSave` with `object: nil` — contract drift vs 3 other emitters | Includes `manager` | Consumer API consistency maintained |

### Memory

| ID | Mechanism | Expected delta |
|---|---|---|
| H4 / H6 / H7 / M4 / M3 | См. cold-start + connect-tap секции выше | Lower peak memory во время connect/sheets/init; **−2-5 МБ** baseline (M3) |

---

## Architectural decisions established (Phase 6d-specific)

- **DEC-06d-01 — Cold-start init defer pattern.** Все non-critical inits (SwiftData migrations, parser allocations, scene-active triggers) выносятся из `BBTB_iOSApp.init` body в `Task.detached(priority: .utility)` или в `.onAppear` hooks. Rationale: cold-start hot path должен делать только то, что нужно для первого frame.
  *Применить в:* всех будущих init-heavy operations (Phase 7 WireGuardKit init, Phase 8 anti-DPI engines, etc.).
  *Reference:* M2 (`6c89996`), M3 (`1099629`), M1 (`cd4b297`) commits.

- **DEC-06d-02 — XPC consolidation в TunnelController.** Connect/disconnect paths должны делать ≤ 2 XPC trips через `applyCurrentStateToCachedManager()` single save+load pattern. Не fire-and-forget tasks.
  *Применить в:* Phase 7 (WireGuard config switching), Phase 9 (deep links → auto-connect flow).
  *Reference:* H2 (`8749985`), M1 (`cd4b297`).

- **DEC-06d-03 — Event-driven status polling.** Никаких `sleep`-based polling loops для NEVPNStatus transitions. Использовать `AsyncStream<NEVPNStatus>` observer-stream с immediate fall-through.
  *Применить в:* Phase 6e/6f если потребуется status-await wrappers.
  *Reference:* H3 (`decd7c4`), H8 (`acd85fa`).

- **DEC-06d-04 — Bounded concurrency для probe-style operations.** `pingAllServers` / `probeAll`-style scanning должно иметь bounded concurrency (limit 4-8) + cancellation-safe defer cleanup.
  *Применить в:* Phase 7 multi-protocol probe (когда добавляются WireGuard + AmneziaWG + TUIC + OpenVPN — каждый со своими probes).
  *Reference:* H4 (`55bde6c`, `dca8e58`), M13 (`61f60a3`).

- **DEC-06d-05 — Apple-canonical options discriminator for startTunnel.** Host передаёт `options["manualStart"]: NSNumber(true)` при explicit user Connect; extension differentiates OS-driven (`options == nil`) vs app-initiated (non-nil + manualStart key). Sticky App Group marker (`ExternalVPNStopMarker.isPending(maxAge: 600)`) бриджит `NEProviderStopReason` из extension в host.
  *Применить в:* Phase 11/12 (Settings/Onboarding deep linking), Phase 9 (Universal Links auto-connect).
  *Reference:* `cff3f46`; pattern derived from WireGuard iOS `activationAttemptId` + sing-box-for-apple App Group persist.

- **DEC-06d-06 — PerfSignposter instrumentation.** Спаны `ColdLaunch` / `ConnectTap` / `PreConnectProbe` / `ProvisionProfile` / `LibboxStart` сохранены в production code как standard performance instrumentation pattern для будущих Instruments capture.
  *Применить в:* Phase 7+ если performance regression suspected.
  *Reference:* `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift` (Wave 02a commit `64368c6`).

---

## Open follow-ups (post-6e)

**Status:** ✅ Все 26 carved finding IDs из Phase 6d полностью учтены в Phase 6e (closure 2026-05-14, v0.6.3) — **19 code-fixed** + **5 subsumed-by-Phase-6d** + **2 deferred** (L16, L18). Дополнительно — 3 trivial unused imports закрыты в Wave 2 Theme D (attributed к QUAL-05, Periphery actionable count 3 → 0).

**Распределение закрытий** (см. `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md` для commit SHAs):

- **4 atomic MEDIUM fixes (Wave 1):**
  - **M7** (`ca21fa9`) — scenePhase=.active hooks → consolidated `MainScreenViewModel.handleForegroundReentry`.
  - **M10** (`6af41db`) — `ServerListViewModel.loadFromStore` idempotency guard (loadInProgress + 100ms debounce) + `confirmDeleteSubscription` single-tail-call collapse.
  - **M8 + L12** (`368c82f`) — pre-expand validate guarded by `configJSONValidatedAt` 24h cache marker; **R10 post-expand validate ОСТАЁТСЯ unconditional** (defense-in-depth preserved).
  - **M11** (`4269570`) — explicit `applyVPNStatus(.connecting)` early-return guard (D-09 single authority preserved).
- **14 LOW в 4 bundle commits (Wave 2):**
  - **Theme A perf** (`5c74423`): L3 (L10n lazy keys), L4 (`.overlay {}` modifier-closure), L7 (detents `@State` driver), L8 (QR QoS `.userInteractive`), L11 (notification once outside for-loop), L13 (`.prettyPrinted` → `[]` in 6 ConfigBuilder call-sites).
  - **Theme B correctness** (`f857763`): L1 (`clearDNSCache` 2s timeout), L9 (failover banner 5s TTL), L10 (observer-fire-before-attempt), L20 (commandServer defensive cleanup).
  - **Theme C-1 maintainability** (`a03007f`): L2 (WS sniFallback unification — Option A2 WS-overload), L5 (UserNotificationsHelper extraction), L14 (`print` → `Logger` importer-upgrade), L15 (autoDetectControl log level downgrade).
- **3 trivial unused imports (Wave 2 Theme D, `f42499f`):** ServerDetailView `ConfigParser`, ServerListSheet `ConfigParser`, TransportPicker `DesignSystem` — Periphery actionable 3 → 0 (closes QUAL-05).
- **5 bookkeeping subsumed-by-Phase-6d:** M6 (`1467328` + `9b38796`), M15 (`55bde6c`), L6 (`5ef3888`), L17 (`bc7bc26` + `1467328`), L19 (`b8d9294`) — no code change в Phase 6e, tracking rows only.
- **2 deferred finding IDs:**
  - **L16** (Theme C-2) — applyVPNStatus `reduceStateBanner` extraction. Codex Plan Reviewer HIGH-RISK no-go (touches D-09 single authority + Phase 6c R18 sliding window invariant; outer-level dedupe guard `9b38796` уже даёт 8k-duplicate-event protection — extraction is cosmetic, not corrective). AUTO_MODE first-option safe-default. **Carry-forward → Phase 6f либо Phase 7+ refactor.**
  - **L18** — lazy `serverListViewModel` в `MainScreenViewModel`. Coordinator backlink на init line 252 (`self.serverListViewModel?.coordinator = self`) форсирует lazy resolution immediately (defeats laziness); `public let → public private(set) lazy var` меняет ObservedObject mutation ABI. **Carry-forward → Phase 6f либо Phase 7+.**

### Carry-forward backlog (post-6e)

- **L16** — applyVPNStatus extraction (Codex no-go) → Phase 6f либо integrated в Phase 7+ refactor.
- **L18** — lazy `serverListViewModel` (architectural incompatibility) → Phase 6f либо Phase 7+.
- **MainScreenView.swift:15 unused `@Environment(\.scenePhase)` declaration** — leftover из Wave 1 M7 (`ca21fa9`); Periphery flagged out-of-scope в Wave 2 final gate. Trivial 1-line removal → Phase 6f либо Phase 7+.
- **NET-12** — active liveness probe (Phase 6c R18 carve-out — soft-kill server detection). См. `.planning/REQUIREMENTS.md:113`. **НЕ в scope 6e/6f, defer → Phase 7-8.**
- **Numerical Instruments baseline** (Time Profiler cold-launch + connect-tap + Energy Log 5-min idle + Allocations host + extension) — Phase 6e D-02 explicit defer. PerfSignposter (DEC-06d-06) готов в production code. **Defer → Phase 11/12** (pre-TestFlight obligatory snap).
- **macOS UAT replay** — Phase 6c/6d scenarios A / F-direct / F-reverse / Settings-disable / G не выполнялись на macOS отдельно (только scenario C). Phase 6e D-03 explicit defer. **Defer → Phase 11/12** (pre-TestFlight polish).

Полный детальный список оригинальных 26 carved findings — `.planning/phases/06d-performance-audit/06D-FINDINGS.md` (git-tracked). Closure mapping — `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md`.

---

## Methodology (для будущих phase performance audits)

Если в Phase 7-12 потребуется повторить performance audit — следовать pattern Phase 6d:

1. **Multi-AI peer review** — 3 passes, identical 7-section brief, parallel execution (Opus + Codex + Gemini, fallback chain для Gemini 503).
2. **Findings synthesis** — single `FINDINGS.md` с consensus markers (3-AI / 2-AI / 1-AI), invariant filter (D-09), severity classification.
3. **CHECKPOINT** для user budget decision (HIGH only / + selected MEDIUM / + all MEDIUM / + LOW).
4. **Atomic-commit fix cycle** с regression gate между каждой fix (`swift test` + iOS xcodebuild + macOS xcodebuild).
5. **Post-fix re-measure** (если Instruments снимался pre-fix) + comparison + wiki update.
6. **UAT regression smoke** — Phase 6c-style scenarios (A..I + Settings-disable) на physical device.

Pattern документирован в `.planning/phases/06d-performance-audit/06D-RESEARCH.md` (полная research output, действителен до 2026-05-28; revisit если переиспользуется).

**Variant D (no pre-fix Instruments)** — допустимый trade-off, если user приоритизирует velocity. Numerical confirmation возможен post-phase через single capture.

---

## Related pages

- [[auto-reconnect]] — Phase 6c long-term memory (architectural baseline для invariants Phase 6d preserved).
- [[architecture]] — SwiftPM-структура и Network Extension targets (Phase 6d не изменила структуру).
- [[tech-stack]] — Periphery (опционально), OSSignposter как standard performance tooling.
- [[security-gaps]] — открытые вопросы безопасности (R10 Settings-disable mitigation теперь укреплён через ExternalVPNStopMarker).
- [[dns-pipeline-decisions]] — Phase 6 long-term DNS-decisions baseline (Phase 6d не трогала).
