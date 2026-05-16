# Phase 13 / Plan 03 — Audit Fix-Up Cycle

**Type:** Implementation (code fixes)
**Status:** ⚪ PLANNING (awaiting user approval)
**Created:** 2026-05-16 (evening)
**Phase:** 13 (TestFlight Internal Distribution v0.13)
**Preconditions:**
- Plan 01 (D-14 Routing rules toggle) ✅ DONE 2026-05-16
- Plan 02 (Pre-TestFlight audit) ✅ DONE 2026-05-16 — 160 findings в `AUDIT.md`

---

## Goal

Closure **CRITICAL + selected HIGH findings** из Plan 02 audit (`AUDIT.md`) перед TestFlight Internal Distribution upload. Each fix — atomic commit с build verify + targeted test, чтобы regression на любом шаге был визуально изолируем.

**Out of scope (defer to Phase 13+ Plan 04 или v1.1+):**
- All MEDIUM findings (56) — tracking issue, fix iteratively post-TestFlight
- All LOW findings (42) — cleanup backlog
- Phase 8 W7 actual closure (real Ed25519 key publish + .srs signing pipeline live) — separate operational task, требует server-side work

---

## Scope — Findings to Close

### Tier A — CRITICAL (must close before TestFlight)

**7 fix tasks closing 18 CRITICAL findings:**

| # | Fix Task | Closes Findings | Effort | Risk |
|---|----------|----------------|--------|------|
| **T-A1** | RulesEngine — pubkey + path traversal + sha256 + atomic write | A5-001..005, C5-001..006 (10 CRITICAL+HIGH) | 4-6h | HIGH (signing pipeline) |
| **T-A2** | Protocols/* — JSON template path audit + fix | C8-001..011 (6 CRITICAL) | 4-16h (depends if dead vs live) | HIGH (security boundary) |
| **T-A3** | ValidatedHTTPSFetcher actor — unified SSRF | A4-001, C4-001, C4-002, C5-001 (3 CRITICAL) | 4-6h | MED (URL handling) |
| **T-A4** | MainScreenViewModel `deinit` — observer cleanup | A3-001 (1 CRITICAL) | 30min | LOW |
| **T-A5** | DiagnosticsExporter IPv6 masking | C6-001 (1 CRITICAL) | 1-2h | LOW (privacy improvement) |
| **T-A6** | Boundary input limits — body / JSON / base64 sizes | A4-002, A4-004, A4-005, C4-003 (1 CRITICAL + 3 HIGH) | 2-3h | LOW |
| **T-A7** | JSON injection через `tag` field + SubscriptionPinManager placeholder | A4-003, A4-007 (2 CRITICAL) | 1-2h | LOW |

**Tier A total:** 7 commits, ~16-37 hours work.

### Tier B — HIGH (highly recommended pre-TestFlight)

**8 fix tasks closing ~20 HIGH findings:**

| # | Fix Task | Closes Findings | Effort | Risk |
|---|----------|----------------|--------|------|
| **T-B1** | TUIC reparse keychain handler — add `"tuic"` case | C3-003 (1 HIGH) | 30min-1h | LOW |
| **T-B2** | TunnelController.disconnect() ManagerSelector filter | C3-002 (1 HIGH) | 15min | LOW |
| **T-B3** | KeychainStore — separate base/add query + Synchronizable=false | A2-001, A2-002, C2-001 (3 HIGH) | 1-2h | MED (Keychain risk) |
| **T-B4** | killSwitchObserver `queue: .main → nil` | A3-004 (1 HIGH) | 15min | LOW |
| **T-B5** | ConfigImporter modelContainer isolation | A3-005 (1 HIGH) | 2-3h | MED (SwiftData concurrency) |
| **T-B6** | killSwitchEnabled defaults consistency | A6-001, A6-002 (2 HIGH) | 30min-1h | LOW |
| **T-B7** | ImportHandler path prefix tightening + URL log redaction | A6-003, C7-004 (2 HIGH) | 1h | LOW |
| **T-B8** | MainScreenViewModel state machine fixes | A3-002, A3-003, C3-001 (3 HIGH) | 3-5h | MED (NEVPN reactive flow) |

**Tier B total:** 8 commits, ~10-15 hours work.

### Tier B-deferred (after Tier A+B, before TestFlight if time permits)

| # | Fix Task | Closes Findings | Effort |
|---|----------|----------------|--------|
| T-B9 | PacketTunnelKit HIGH (validate accepts non-dialable group, commandServer leak, @unchecked Sendable platform interface) — A1-001..003, C1-001..003 | 6 HIGH | 4-6h |
| T-B10 | CDN adapters allowlist (FrontingEngine) — C7-001, C7-002 | 2 HIGH | 2h |
| T-B11 | Protocols/* buildOutbound validation parity — C8-002, 004, 006, 008, 010, 012 | 6 HIGH | 3-4h (если T-A2 уже centralized validation) |

**Combined total (Tier A + B + B-deferred):** ~35-65 hours work. **Recommend split:** Tier A immediately (~16-37h), Tier B + B-deferred parallel work over 2-3 sessions.

---

## Success Criteria

- ✅ All 18 CRITICAL findings closed с code fix + commit
- ✅ All 8 Tier B HIGH findings closed (extended Tier B-deferred — if time permits)
- ✅ Каждый fix = atomic commit (one finding cluster per commit; никакого batching multiple unrelated fixes)
- ✅ Каждый commit verified green: `xcodebuild -scheme BBTB build` + relevant `swift test --filter`
- ✅ No regression на existing tests (SingBoxConfigLoaderTests 57/57; MainScreenFeatureTests; ConfigParserTests; etc.)
- ✅ User device UAT (real iPhone) для T-A1, T-A2, T-A4, T-B1 после implementation — connect/disconnect golden path не сломан
- ✅ Re-audit pass after Tier A closure: re-dispatch CRITICAL-only reviewers (A4 + A5 + C4 + C5 + C8) verify все Tier A closed (~30min cost)
- ✅ AUDIT.md updated с inline ✓ markers и closure commit refs

---

## Execution Approach

### Per-fix discipline (mandatory)

Каждая fix task следует pattern:
1. **Read findings** для этой task из `audit-findings/*-{file}.md` (file:line, why-it-matters, suggested-fix)
2. **Read affected code** — full context, не trust только finding excerpt
3. **Plan one specific fix** — what changes, what tests verify
4. **Implement** — minimal diff, не refactor surroundings
5. **Verify locally:** `xcodebuild -scheme BBTB -destination 'generic/platform=iOS Simulator' build`
6. **Run relevant tests** if exist (`swift test --filter <suite>` или through xcodebuild)
7. **Commit atomically** — commit message refers to finding IDs (`fix(13-03/T-A1): RulesEngine path traversal validation (closes A5-002, C5-004)`)
8. **Mark closure в AUDIT.md** — inline ✓ marker after finding ID
9. **Update STATE.md** prog incrementally

### Verification approach per task

| Task | Build verify | Test verify | UAT verify |
|------|-------------|------------|-----------|
| T-A1 (RulesEngine) | `xcodebuild build` | RulesEngine package tests + add new path-traversal/sha256 tests | Real device: app starts, RulesEngine bootstraps, no signature errors |
| T-A2 (Protocols) | `xcodebuild build` | Each protocol package tests | UAT: import 1 server per protocol, verify connect |
| T-A3 (SSRF) | `xcodebuild build` | ConfigParser tests + RulesEngine tests + add SSRF unit tests | UAT: subscription import normal URL works; manual `127.0.0.1` subscription URL blocked |
| T-A4 (deinit) | `xcodebuild build` | MainScreenFeatureTests | None (defensive) |
| T-A5 (IPv6 mask) | `xcodebuild build` | SettingsFeatureTests + add IPv6 mask regex test | UAT: trigger diagnostics export, check log contains masked IPv6 |
| T-A6 (size limits) | `xcodebuild build` | ConfigParser tests + add boundary tests | UAT: paste huge subscription URL, verify graceful rejection |
| T-A7 (tag+SubscriptionPin) | `xcodebuild build` | ConfigParser tests | None |
| T-B1..B8 | Per-package build + tests | Targeted | Per-fix UAT for state machine fixes |

### Codex consultation for high-risk fixes

Per CLAUDE.md «Всегда консультируйся с CODEX» rule, делегируем Codex для **multi-turn review** на следующие fixes:
- **T-A1 RulesEngine** — Codex Plan Reviewer expert validates fix approach **before implementation**
- **T-A2 Protocols** — verify dict-based migration не сломает existing tests
- **T-A3 ValidatedHTTPSFetcher** — Security Analyst expert reviews threat model
- **T-B5 ConfigImporter isolation** — Architect expert reviews Sendable refactor

Codex запрос pattern: 7-section delegation + `developer-instructions` с expert prompt из `~/.claude/plugins/cache/.../prompts/{security-analyst,architect,plan-reviewer,code-reviewer}.md`.

### Re-audit gate

After Tier A closure (before proceeding к TestFlight):
- Re-dispatch CRITICAL-only reviewer subset: A4 + A5 + C4 + C5 + C8 (5 parallel reviewers, ~15-20 min wall time)
- Goal: verify все Tier A closed; surface any newly-introduced issues
- Если re-audit вернёт CRITICAL — extend Tier A scope, repeat
- Если clean → proceed к Apple Developer Portal NE capability + App Store Connect record creation

---

## Task Detail

### T-A1: RulesEngine — pubkey + path traversal + sha256 + atomic write

**Closes:** A5-001 (placeholder pubkey), A5-002 (path traversal), A5-003 (sha256 not verified), A5-004 (minAppVersion not enforced), A5-005 (non-atomic multi-file), C5-001 (SSRF), C5-002 (sha256 ignored), C5-003 (replay protection), C5-004 (path traversal), C5-005 (atomic), C5-006 (baseline not verified).

**Scope:**
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift` — replace placeholder OR document «v1.0 RulesEngine disabled, baseline-only» fallback
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift:374` — add SHA-256 verification of fetched SRS against `entry.sha256`
- `RulesEngineCoordinator.swift:381` — add path-traversal validation for `entry.name` / `entry.sigPath` (reject `/`, `\`, `..`, percent-encoded, abs paths; prefer fixed local filenames mapped from categories)
- `RulesEngineCoordinator.swift:400` — versioned cache dir + atomic swap via generation marker
- `RulesEngineCoordinator.swift:227` — verify baseline manifest+SRS signatures in `bootstrap()`
- `RulesManifest.swift` — add `updated_at: Date` field + freshness window enforcement

**Pre-implementation:** consult Codex Plan Reviewer expert (multi-turn) for fix approach validation.

**Risk:** HIGH — Phase 8 W7 status unclear. If real pubkey не published yet — either (a) ship without RulesEngine fetch (baseline-only mode) для v1.0, либо (b) block TestFlight pending W7 closure. Discuss с user before pick.

### T-A2: Protocols/* — JSON template path audit + fix

**Closes:** C8-001 (VLESSReality), C8-003 (VLESSTLS), C8-005 (Trojan), C8-007 (Shadowsocks), C8-009 (Hysteria2), C8-011 (TUIC).

**Step 1 (15min):** Find callers of `*ConfigBuilder.buildSingBoxJSON(...)` template paths via grep. If callers all in tests → mark API internal/deprecated. If live production callers → must migrate.

**Step 2 (per protocol):**
- If dead → mark `internal` или delete, update tests
- If live → replace string template substitution с dict-based `buildOutbound` + `JSONSerialization.data`

**Risk:** HIGH if template paths live (more refactor); LOW if dead. Codex consult on migration approach.

### T-A3: ValidatedHTTPSFetcher actor — unified SSRF

**Closes:** A4-001, C4-001 (SubscriptionURLFetcher SSRF bypass), C4-002 (JSONEndpointFetcher missing SSRF), C5-001 (RulesFetcher SSRF gap).

**Scope:**
- New file `BBTB/Packages/ConfigParser/Sources/ConfigParser/ValidatedHTTPSFetcher.swift` — actor с:
  - IP-parser based blocklist (NOT string-prefix): RFC1918, loopback, link-local, ULA, multicast/reserved, CGNAT, `.local`, IPv4-mapped IPv6, IPv6 loopback/link-local
  - URLSessionTaskDelegate с `willPerformHTTPRedirection` → re-validate target host
  - Post-DNS IP validation (resolve URL.host, check resolved addresses against blocklist)
  - Body size limits (configurable, default 5MB)
  - Timeout enforcement
- `SubscriptionURLFetcher.swift` — migrate to `ValidatedHTTPSFetcher`
- `JSONEndpointFetcher.swift` — migrate
- `RulesFetcher.swift` — migrate
- Centralize blocklist constants — shared между ConfigParser и RulesEngine

**Pre-implementation:** consult Codex Security Analyst expert.

**Risk:** MED — URL handling can have subtle edge cases (IPv6 zone IDs, percent-encoded hosts, internationalized domain names).

### T-A4: MainScreenViewModel `deinit` — observer cleanup

**Closes:** A3-001 (CRITICAL).

**Scope:**
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:110` — add `deinit` removing 3 observers: `rulesUpdateObserver`, `killSwitchObserver`, `nevpnStatusObserver`.

**Risk:** LOW. Defensive fix.

### T-A5: DiagnosticsExporter IPv6 masking

**Closes:** C6-001 (CRITICAL privacy).

**Scope:**
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsExporter.swift:70`, `:112` — extend IP-mask regex для IPv6 (compressed `::1`, expanded `fe80:0000:...`, IPv4-mapped `::ffff:1.2.3.4`, zone IDs `%en0`)
- Update tests: change «IPv6 unchanged» expectations к «IPv6 masked»

**Risk:** LOW.

### T-A6: Boundary input limits — body / JSON / base64

**Closes:** A4-002 (body unbounded), A4-004 (JSON depth unbounded), A4-005 (base64 unbounded), C4-003 (no public boundary limits).

**Scope:**
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift:58` — add max `rawInput` length cap (e.g. 1MB)
- `SubscriptionURLFetcher` — body size limit via `ValidatedHTTPSFetcher` (T-A3 dependency)
- `JSONSerialization` calls — pre-check size, depth limits
- Base64 decode in URI parsers — size cap

**Risk:** LOW (additive guards).

### T-A7: JSON injection через `tag` field + SubscriptionPinManager placeholder

**Closes:** A4-003 (JSON injection через tag), A4-007 (placeholder Ed25519 in SubscriptionPinManager).

**Scope:**
- Identify `tag` field path в ConfigParser → sing-box pipeline; sanitize или constrain charset
- `SubscriptionPinManager.swift:45-50` — either remove placeholder pubkey (если pinning dead code per memory `project_phase13_subscription_pins_prerequisite.md`) OR replace с real published cert SPKI

**Risk:** LOW.

### Tier B tasks — see table above; each ~30min-3h

Подобный per-task scope для T-B1..T-B8 + T-B9..T-B11 deferred.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Phase 8 W7 не actually closed → T-A1 RulesEngine fix может не работать без real pubkey | Discuss с user перед T-A1: ship baseline-only OR block on W7 |
| T-A2 protocol JSON migration breaks existing tests (template paths may be tested) | Codex Plan Reviewer consult; verify all callers; preserve test compatibility |
| T-A3 SSRF guard может block legitimate subscription URLs (false positives) | Comprehensive test suite + UAT before merge |
| T-B5 ConfigImporter Sendable refactor может deadlock SwiftData concurrent fetches | Architect expert review; gradual migration через @MainActor isolation |
| Total estimated 35-65 hours — может растянуться | Atomic commits позволяют partial progress; user может остановиться на любом Tier и продолжить позже |
| Re-audit cycle может найти newly-introduced issues | Tier A closure includes re-audit gate; не proceed к TestFlight без clean re-audit |

---

## Estimated Wall Time

- **Tier A:** 16-37 hours (зависит от T-A2 protocol path live/dead status)
- **Tier B:** 10-15 hours
- **Tier B-deferred:** 9-12 hours
- **Re-audit gate:** 30-45 min (5 parallel reviewers)
- **Total recommended scope:** 35-65 hours = 4-8 work days dedicated

Split across sessions:
- Session 1 (~6-8h): T-A4, T-A5, T-A7, T-A6, T-B1, T-B2, T-B4 (quick wins, low-risk)
- Session 2 (~8-12h): T-A1 RulesEngine + T-A3 ValidatedHTTPSFetcher (high-risk, needs Codex consult)
- Session 3 (~8-16h): T-A2 Protocols + T-B5 ConfigImporter (largest scope)
- Session 4 (~6-10h): T-B3, T-B6, T-B7, T-B8 + Re-audit gate
- Optional Session 5: T-B9..B11 deferred

---

## Estimated Cost

Per atomic fix commit cycle (read findings + read code + plan + implement + verify + commit + update docs):

- Quick fixes (T-A4, T-A5, T-A7, T-B1, T-B2, T-B4): ~30-50k tokens each
- Medium fixes (T-A6, T-B3, T-B6, T-B7, T-B8): ~80-120k tokens each
- Heavy fixes (T-A1, T-A2, T-A3, T-B5): ~150-250k tokens each (включая Codex consult)
- Re-audit gate: ~250k tokens (similar к Plan 02 cost, но subset)

**Total:** ~1.5-2.5M tokens для full Tier A + B + B-deferred + re-audit.

---

## Next Steps After Approval

1. **User approves** plan (или скорригует scope)
2. **Start with quick wins** (Session 1): T-A4 → T-A5 → T-A7 → T-A6 → T-B1 → T-B2 → T-B4
3. **Session 2 (Codex-consulted heavy fixes):** T-A1 RulesEngine, T-A3 ValidatedHTTPSFetcher
4. **Session 3 (larger refactors):** T-A2 Protocols, T-B5 ConfigImporter
5. **Session 4 (remaining Tier B + Re-audit gate):** T-B3, T-B6, T-B7, T-B8 + Re-audit verification
6. **Decision point после re-audit:** clean → mark Phase 13 Plan 03 ✅ DONE → proceed к Apple Developer Portal NE capability + App Store Connect record. Если CRITICAL re-introduced → extend Tier A.
7. **Optional Session 5:** T-B9..B11 deferred fixes (PacketTunnelKit HIGH, CDN allowlist, Protocols/* buildOutbound parity)
8. **Track в STATE.md:** Plan 03 progress per-task с commit refs.

---

## Verification (success of fix-up cycle itself)

- [ ] All 18 CRITICAL findings marked ✓ closed в AUDIT.md
- [ ] All 8 Tier B HIGH findings marked ✓ closed
- [ ] (Optional) Tier B-deferred 6 HIGH closed
- [ ] All atomic commits на `main` с clear commit messages referencing finding IDs
- [ ] `xcodebuild -scheme BBTB build` green после каждого commit
- [ ] Existing tests green (no regression on 57/57 SingBoxConfigLoaderTests; AppFeatures tests; ConfigParser tests)
- [ ] New tests added for each fix where applicable (path-traversal, SSRF guard, IPv6 mask, size limits)
- [ ] Real device UAT confirms no functional regression (connect/disconnect/import golden path)
- [ ] Re-audit gate: 5 CRITICAL-only reviewers re-dispatched, return 0 new CRITICAL
- [ ] STATE.md updated: Phase 13 Plan 03 ✅ DONE с commit list
- [ ] wiki/log.md chronological entry для Plan 03 closure
- [ ] Memory updated если новые architectural patterns обнаружены в процессе fix-up
