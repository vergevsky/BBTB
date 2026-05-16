# Phase 13 / Plan 02 — Pre-TestFlight Comprehensive Audit

**Type:** Read-only quality gate
**Status:** ⚪ PLANNING (awaiting user approval)
**Created:** 2026-05-16
**Phase:** 13 (TestFlight Internal Distribution v0.13)
**Precondition:** Plan 01 (D-14 Routing rules toggle) ✅ DONE 2026-05-16

---

## Goal

Перед первой TestFlight Internal Distribution отправкой провести comprehensive cross-package audit shipping кода (15 пакетов, ~23k LOC) силами двух AI reviewer'ов (Opus 4.7 + Codex 5.5) с целью поймать критические bugs / security / concurrency / energy / logic issues которые embarrass'или бы на real-device user'е.

**Out of scope:**
- Code fixes (отдельный fix-up цикл после приоритизации findings).
- UI snapshot diffing (Phase 12 baselines уже recorded, проверены).
- Performance benchmarks с device runtime (manual UAT по необходимости).
- Automated fuzz / property-based testing (defer to v1.1+).
- Tests директории (1936 файлов) — audit shipping кода only.

---

## Success Criteria

- ✅ AUDIT.md создан в `.planning/phases/13-testflight-internal-distribution/13-02-AUDIT-PLAN.md` соседом
- ✅ Все 15 пакетов покрыты (HIGH-risk × 2 reviewer + MEDIUM-risk × 1 reviewer + LOW-risk × 1 reviewer = full sweep)
- ✅ Findings классифицированы по severity (CRITICAL / HIGH / MEDIUM / LOW)
- ✅ Каждый finding включает: location (path:line), описание, why-it-matters, suggested-fix-approach
- ✅ Critical-only finds cross-validated между Opus и Codex (не доверяем single-reviewer на блокирующие issues)
- ✅ User приоритизирует findings → отдельный fix-up cycle с per-fix атомарными commits
- ✅ Verified-by-build: оригинальный `xcodebuild` BBTB scheme + `swift test --filter` зелёные на момент audit-start (baseline для not-regressing)

---

## Scope & Risk Stratification

### HIGH-risk (Opus deep audit + Codex second-opinion)

| Package | LOC | Risk areas | Why HIGH |
|---------|-----|-----------|---------|
| `PacketTunnelKit` | ~11 файлов | sing-box config expand, TUN setup, R1/R10 invariants, App Group access | Это сам tunnel; bug = data leak / connection broken |
| `VPNCore` | ~13 файлов | TunnelController actor, NEVPNStatus state machine, on-demand rules builder, kill switch, keychain | State machine ошибки = inconsistent UI / стуёные races |
| `AppFeatures/MainScreenFeature` | ~30+ файлов | MainScreenViewModel reactive driver, NEVPNStatusDidChange handler, foreground resync, deep link routing | Race conditions historically обнаруживались здесь (см. memory: nevpn_xpc_mach_port, observer queue, connectedDate authority) |
| `ConfigParser` | ~20 файлов | URI parsing (vless/trojan/ss/hy2/tuic), JSON deserialization, PoolBuilder, SubscriptionMergeService, PinStore | Security input boundary — atak surface для malicious config |
| `RulesEngine` | ~10 файлов | Ed25519 signature verify, RulesFetcher network + SSRF guard, SRSCacheStore atomic writes, BaselineRulesLoader | Compromised signing key или race в cache = malicious rules applied |

### MEDIUM-risk (Opus sweep, single-pass)

| Package | LOC | Risk areas |
|---------|-----|-----------|
| `AppFeatures/SettingsFeature` | ~20 файлов | @AppStorage suite correctness, DiagnosticsExporter (IP-masking), RulesViewerSection, ForceUpdateButton state machine |
| `AppFeatures/ServerListFeature` | ~10 файлов | SwiftData @Query bindings, ImporterUI integration, edit/delete flows |
| `FrontingEngine` | 9 файлов | CDN fronting overlay, FrontingConfigApplier |
| `DeepLinks` | 7 файлов | URL parsing, universal links validation, Phase 9 router |
| `KillSwitch` | 1 файл | Kill switch policy enforcement |
| `TransportRegistry` | 7 файлов | Transport config dispatch |
| `Protocols/*` | 18 файлов (6 protocols × 3 each) | Per-protocol ConfigBuilder.buildOutbound (security-sensitive — generates sing-box outbound JSON) |

### LOW-risk (Opus quick sanity sweep)

| Package | LOC | Notes |
|---------|-----|------|
| `DesignSystem` | 6 файлов | UI primitives, mostly SwiftUI views and tokens |
| `ProtocolEngine` | 3 файла | Protocol-agnostic engine abstraction |
| `ProtocolRegistry` | 1 файл | Registry singleton |
| `Localization` | 1 файл | L10n.swift codegen accessor |
| `CrashReporter` | 1 файл | Stub Sentry adapter |

---

## Audit Dimensions (all packages)

### 1. Bugs + Logic
- Off-by-one, nil unwrap'ы без guard
- Edge case'ы: empty collections, zero values, max values
- Dead code, дублирование, unreachable branches
- TODO/FIXME comments → выяснить статус
- Missing guard clauses на public API boundary
- Inconsistent error handling (throw vs result vs silent)

### 2. Thread Safety + Swift 6 Strict Concurrency
- `Sendable` violations (особенно `[String: Any]` через async)
- Actor isolation gaps — calling `nonisolated` методы из actor context без явного hop
- Race conditions: shared mutable state без protection
- Retain cycles (особенно `weak`/`unowned` неправильное использование)
- `@MainActor` mismatches (UI updates с background thread)
- Reentry окна в actor методах с `await` (state может измениться)
- `nonisolated(unsafe)` без обоснования
- NEVPNStatusDidChange race conditions (известны проблемы — см. memory)

### 3. Security
- Input validation на URI/JSON boundary (ConfigParser)
- SSRF / open-redirect (RulesFetcher, SubscriptionURLFetcher, FrontingEngine)
- Deserialization risks (JSONDecoder с untrusted input)
- Log injection / sensitive data в logs (PII / IP / Keychain refs)
- Keychain access patterns — leak between targets, кеширование tags
- Signature verification gaps (Ed25519 в RulesEngine)
- App Group data exposure (что extension читает/пишет)
- Code signing assumptions (entitlements correctness, NE capability check)
- Insecure defaults (нaprимер ATS exemptions, http endpoints)

### 4. Performance + Energy
- Hot path allocations (особенно в reactive paths NEVPNStatusDidChange handler)
- Sync I/O на main thread (UserDefaults reads, file I/O, JSONDecoder)
- Polling loops vs event-driven (Phase 6d DEC принципы)
- Unbounded loops / collections (большие arrays без preview/limit)
- Background task efficiency — `BGAppRefreshTask` configured correctly?
- XPC trip count (cap = 2 per DEC-06d-02)
- TaskGroup concurrency bounded (cap = 8 per Phase 6d M5)
- Keychain reads concurrent / sequential
- Repeated work — кеширование snapshot'ов, memoization
- Battery-aware behavior — низкое потребление при idle tunnel

---

## Agent Allocation (parallel dispatch)

### Wave 1 — HIGH-risk audit (parallel, ~20-25 мин wall time)

**Opus subagent'ы (5 параллельно):**

| Agent | Package | Focus dimensions | Output |
|-------|---------|------------------|--------|
| A1 | `PacketTunnelKit` | Thread safety + Security + Energy | Findings list |
| A2 | `VPNCore` | Thread safety + Logic + Bugs | Findings list |
| A3 | `AppFeatures/MainScreenFeature` | Thread safety + Logic + Energy (reactive paths) | Findings list |
| A4 | `ConfigParser` | Security + Bugs (URI parsing input boundary) | Findings list |
| A5 | `RulesEngine` | Security + Thread safety + Logic (sign verify + atomic) | Findings list |

Каждый Opus agent — `general-purpose` subagent с prompt включающим:
- Package path
- Dimensions focus
- Output format (severity, file:line, description, why-it-matters, suggested-fix)
- Read-only constraint (НЕ Edit/Write кодa)
- Прочитать MEMORY.md релевантные feedback memories перед началом (NEVPNStatus patterns, two-phase init, swiftdata uuid predicate, etc.)

**Codex second-opinion (5 параллельных threads через `mcp__codex__codex`):**

Каждый Codex call:
- Single HIGH-risk package
- Same dimensions focus
- Read-only (`sandbox: "read-only"`)
- Developer-instructions = code-reviewer.md prompt (как с Phase 13 D-04 review)
- 7-section delegation format (TASK / EXPECTED OUTCOME / CONTEXT / CONSTRAINTS / MUST DO / MUST NOT DO / OUTPUT FORMAT)

### Wave 2 — MEDIUM-risk audit (1 Opus subagent + 3 Codex threads, ~10-15 мин)

**Opus side (A6):** general-purpose subagent с broader scope — все MEDIUM пакеты в одном проходе, focus на known anti-patterns.
- `AppFeatures/SettingsFeature` + `ServerListFeature`
- `FrontingEngine` + `DeepLinks` + `KillSwitch`
- `TransportRegistry` + `Protocols/*` (6 protocols)
- All 4 dimensions, shallower depth

**Codex side (3 параллельных threads):**

| Codex thread | Packages | Focus |
|--------------|---------|-------|
| C6 — UI features | `AppFeatures/SettingsFeature` + `ServerListFeature` | @AppStorage suite correctness (extension vs main-app), SwiftData bindings, DiagnosticsExporter IP-masking, force-update state machine |
| C7 — Network/policy infra | `FrontingEngine` + `DeepLinks` + `KillSwitch` + `TransportRegistry` | URL parsing (DEEP-01..05), CDN fronting overlay, kill switch policy enforcement, transport dispatch |
| C8 — Protocols | `Protocols/*` (6 protocols: VLESSReality, VLESSTLS, Trojan, Shadowsocks, Hysteria2, TUIC) | Per-protocol ConfigBuilder.buildOutbound — security-sensitive sing-box JSON generation; consistency across protocols |

### Wave 3 — LOW-risk audit (1 Opus subagent + 1 Codex thread, ~5-8 мин)

**Opus side (A7):** quick sanity sweep — все 5 LOW пакетов одним проходом:
- `DesignSystem` + `ProtocolEngine` + `ProtocolRegistry` + `Localization` + `CrashReporter`
- Только bugs + obvious issues (без deep concurrency / security analysis)

**Codex side (C9):** single thread, same scope, second-opinion focus — выявляет hidden coupling / dead code / unused deps которые Opus может пропустить из-за маленького размера пакетов.

### Wave 4 — Aggregation + cross-validation (main thread, ~15 мин)

Main thread (этот разговор):
1. Собрать findings из A1-A7 (Opus, 7 subagents) + C1-C9 (Codex, 9 threads) = 16 источников
2. Deduplicate overlapping findings
3. Для CRITICAL findings — cross-check: если Opus нашёл но Codex нет (или наоборот) → выделить как "single-source critical, требует verification"
4. Cross-tier pattern detection — если одна и та же anti-pattern повторяется в HIGH и MEDIUM (например, UserDefaults.standard вместо App Group suite) — это systemic issue, поднять severity
5. Сортировать по severity → AUDIT.md
6. Записать total counts + cross-validation summary

**Total reviewers:** 7 Opus subagents + 9 Codex threads = **16 parallel reviewers**.

---

## Output Format — AUDIT.md

```markdown
# Pre-TestFlight Comprehensive Audit — Phase 13 Plan 02

**Date:** 2026-05-16 (evening)
**Reviewers:** Opus 4.7 (7 subagents) + Codex 5.5 (5 threads)
**Scope:** 15 packages / ~23k LOC shipping code
**Verdict:** [BLOCK / REQUEST CHANGES / APPROVE]

## Summary

- Total findings: N
- CRITICAL: N (must fix before TestFlight)
- HIGH: N (should fix before TestFlight)
- MEDIUM: N (fix in next iteration)
- LOW: N (track for cleanup)
- Cross-validated (Opus + Codex agree): N
- Single-source (require verification): N

## Critical Findings

### C1: <title>
- **Location:** `path/to/file.swift:line`
- **Dimension:** [bugs|security|concurrency|energy|logic]
- **Source:** [Opus A1 | Codex thread X | both]
- **Description:** ...
- **Why it matters:** ...
- **Suggested fix:** ...

(repeat for all CRITICAL)

## High Findings
...

## Medium Findings
...

## Low Findings
...

## Cross-Validation Notes

(Опционально: где Opus и Codex разошлись + verification approach)

## Recommended Fix Order

1. ...
2. ...
```

---

## Verification (success of audit itself)

- [ ] AUDIT.md создан, structure совпадает с above
- [ ] Все 15 пакетов имеют entries или явный «no critical findings»
- [ ] CRITICAL/HIGH findings cross-validated (Opus + Codex)
- [ ] Каждый finding имеет file:line (не размытое «где-то в X»)
- [ ] Baseline build verified green до audit-start: `xcodebuild -scheme BBTB build` + `swift test --filter SingBoxConfigLoaderTests`
- [ ] User получает summary с counts + recommendation для fix-up cycle

---

## Risks

| Risk | Mitigation |
|------|-----------|
| Context overflow при aggregation 12 sources | Каждый subagent возвращает compressed findings list (markdown structured), main thread не читает raw outputs |
| Hallucinated file:line citations | Cross-validate: Opus + Codex агенты получили те же file paths; spot-check 3 random CRITICAL find'a на main thread |
| False positives flood (особенно от security-focused agent) | Severity calibration в prompt: CRITICAL = exploitable / data leak / data loss; HIGH = bug в hot path; MEDIUM = edge case; LOW = code smell |
| Codex SSE timeout на больших пакетах | Сплит prompt — один package на call; AppFeatures/MainScreenFeature разбить на смысловые группы (state machine / reactive driver / kill switch) если 30+ files |
| Cross-package issues пропущены (агенты видят только свой scope) | Wave 4 — main thread читает AUDIT.md целиком и ищет patterns которые повторяются across packages. Codex MEDIUM split на 3 группы (UI / infra / protocols) даёт некоторый cross-package view внутри groups. |
| MEDIUM tier single-Opus blind spots (Protocols/* security-sensitive) | Codex C8 — dedicated thread на Protocols/* (per-protocol buildOutbound consistency check across 6 protocols) |

---

## Next Steps After Approval

1. User approves этот plan (или скоррыгирует scope)
2. Main thread: baseline build verify (`xcodebuild` + `swift test`)
3. Wave 1: dispatch 5 Opus subagents + 5 Codex threads параллельно
4. Wave 2: dispatch 1 Opus subagent (MEDIUM)
5. Wave 3: dispatch 1 Opus subagent (LOW)
6. Wave 4: aggregate → AUDIT.md → present to user
7. User приоритизирует findings → отдельный fix-up cycle (atomic commits per fix)
8. After fixes: re-run baseline build + tests → mark Plan 02 ✅ DONE

---

## Estimated Wall Time

- Wave 1 HIGH (parallel): ~25 мин (5 Opus + 5 Codex параллельно)
- Wave 2 MEDIUM: ~12-15 мин (1 Opus + 3 Codex параллельно с Wave 1)
- Wave 3 LOW: ~5-8 мин (1 Opus + 1 Codex параллельно)
- Wave 4 aggregation: ~15 мин (sequential, после ожидания всех 16)
- **Total:** ~35-45 мин wall time

## Estimated Cost

| Reviewer pool | Calls | Tokens per call | Subtotal |
|---------------|-------|----------------|---------|
| Opus HIGH (A1-A5) | 5 | 50-100k | 250-500k |
| Opus MEDIUM (A6) | 1 | 80k | 80k |
| Opus LOW (A7) | 1 | 30k | 30k |
| Codex HIGH (C1-C5) | 5 | 50k | 250k |
| Codex MEDIUM (C6-C8) | 3 | 40k | 120k |
| Codex LOW (C9) | 1 | 25k | 25k |
| Main thread aggregation | 1 | 50k | 50k |
| **TOTAL** | | | **~800k-1.05M tokens** |

Это самый дорогой quality gate в проекте — обоснован тем что это PRE-TESTFLIGHT, ловить bugs дешевле сейчас чем после первого user feedback. Codex parallel coverage всех 3 tier'ов добавляет +170k tokens vs original plan, но сильно снижает risk single-reviewer blind spot'ов (особенно на MEDIUM где security-sensitive Protocols/* live).
