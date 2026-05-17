# Phase 13 / Plan 05 — Re-Audit Fix-Up Cycle (Autonomous)

**Type:** Implementation (autonomous code fixes)
**Status:** ⚪ EXECUTING
**Created:** 2026-05-17
**Phase:** 13 (TestFlight Internal Distribution v0.13)
**Preconditions:**
- Plan 04 (Re-audit) ✅ DONE — `AUDIT-2.md` 16-reviewer report
- Baseline: HEAD `2f7e244` (post-Plan-04 docs)

---

## Goal

Закрыть автономно ВСЕ findings из Plan 04 re-audit (от CRITICAL до LOW), не требующие user discussion.

**Skipped (require user decision):**
- A6'-006 testFlightInviteURL "PLACEHOLDER" — operational URL decision

**Skipped (already accepted Tier C carry-forward):**
- A5'-009 productionMirrors `.example` TLD (covered by A5-014 acceptance)
- Phase 8 W7 real key publish

---

## Scope by Tier

### Tier A++ — CRITICAL + closures of partial T-A* (4 tasks, ~5-7h)

| Task | Closes | Effort | Codex consult |
|---|---|---|---|
| **T-A1'** sha256 empty bypass reject | C5'-001 CRITICAL + A5'-005 + C5'-005 (validation) | 30min | No |
| **T-A3'** IPv6 numeric parser SSRF | C4'-001 CRITICAL | 2-3h | **YES — Security Analyst** |
| **T-A5'** IPv6 mask compressed forms | C6'-001 HIGH | 1-2h | No |
| **T-B5'** ProvisionSerializer real mutex | A3'-001 + C3'-001 + A3'-002 (rethrows dead) | 1-2h | **YES — Architect** |

### Tier B — HIGH non-CRITICAL (6 tasks, ~6-8h)

| Task | Closes | Effort |
|---|---|---|
| **T-B1'** PinnedSubscriptionURLFetcher redirect guard | C4'-002 | 30min |
| **T-B2'** JSONEndpointFetcher streaming + cap | C4'-003 | 1h |
| **T-B3'** commitTransaction generation atomic swap | C5'-002 + A5'-004 + C5'-003 | 2-3h |
| **T-B4'** RulesEngine path traversal allowlist | A5'-001 + C5'-005 + A5'-003 + A5'-011 | 1-1.5h |
| **T-B5'-extra** commitTransaction staging cleanup | A5'-002 | 30min |
| **T-B6'** FrontingEngine tag-scoped apply | C7'-001 | 1.5-2h |

### Tier C — MEDIUM (15 tasks, ~5-8h)

| Task | Closes | Effort |
|---|---|---|
| **T-C1'** Keychain AccessibleAfterFirstUnlock | C2'-001 | 15min |
| **T-C2'** Synchronizable cleanup one-time sweep | C2'-003 | 30min |
| **T-C3'** SubscriptionURLFetcher port=0 rejection | A4'-004 | 30min |
| **T-C4'** parseSingBoxJSON tag size cap | A4'-005 | 20min |
| **T-C5'** HTTPSRedirectGuard @unchecked Sendable | A4'-002 + C4'-004 | 10min |
| **T-C6'** SingBoxConfigLoader route.rules outbound ref check | C1'-001 + A1'-006 | 30min |
| **T-C7'** ServerListVM loadFromStore(force:) | C6'-002 | 30min |
| **T-C8'** Delete dead SingBoxConfigTemplate.json files | A6'-001 | 30min |
| **T-C9'** Connected timer min() future-clock guard | A3'-004 | 15min |
| **T-C10'** disconnect cachedManager XPC saving | A3'-006 | 30min |
| **T-C11'** sigPath preserved в cache write | C5'-004 | 30min |
| **T-C12'** bytes() streaming throw cleanup | A4'-003 | 15min |
| **T-C13'** RulesEngine notification queue | A5'-007 | 15min |
| **T-C14'** physicalInterfaceSeeded clear | A1'-005 | 30min |
| **T-C15'** Wiki DNS-rebinding doc | A4'-001 | 15min |

### Tier D — LOW cleanup (batched, ~3-4h total)

Single batched commit для:
- A1'-001/002/003/004/007/008 (PacketTunnelKit polishing)
- A3'-002 (rethrows already in T-B5')
- A3'-007..011 (MainScreen LOW)
- A4'-006..012 (ConfigParser LOW)
- A5'-008/010 (RulesEngine LOW)
- A6'-002..005, 007..014 (MEDIUM-tier LOW from A6')
- A7'-002..006 (LOW tier)
- C2'-002 (Keychain pre-delete throw)
- C3'-003 (handleForegroundReentry contract doc)
- C5'-006 (RulesFetcher redirect guard doc)
- C7'-002/003/004 (TransportRegistry + FrontingEngine + ImportHandler subpath LOW)
- C8'-001 (TUIC comment)
- C9'-001 (Localizable duplicate key)

---

## Execution Strategy

### Discipline
- **Atomic commits per fix-cluster** — never batch unrelated fixes.
- **Build verify per commit** via `xcodebuild -scheme BBTB build`.
- **Relevant tests** after fix touching tested code (`swift test --package-path Packages/X`).
- **Codex consults** для T-A3' (Security Analyst) и T-B5' (Architect).
- **Update AUDIT-2.md** inline ✓ markers after each closure.

### Order

1. **Codex consults FIRST** (parallel) — get expert input before implementing T-A3' и T-B5'.
2. **Tier A++** (CRITICAL first, then HIGH closures).
3. **Tier B** (HIGH non-CRITICAL).
4. **Tier C** (MEDIUM — group by file to minimize churn).
5. **Tier D** (LOW — batched cleanup commit).

### Success Criteria
- All CRITICAL marked ✅ в AUDIT-2.md
- All HIGH (10) marked ✅
- ≥80% MEDIUM closed (15+ of 25)
- Most LOW closed (clear cleanup gains)
- `xcodebuild -scheme BBTB build` PASS after every commit
- No test regressions

### Estimated Total Effort
**~15-20 hours of focused work.** Tier A++ first (most user-visible quality gate), then B/C/D.

---

## Risk Mitigation
- **T-A3' IPv6 parser:** Codex Security Analyst consults design BEFORE I write code — IPv6 parsing has many edge cases, want second opinion.
- **T-B5' actor mutex:** Codex Architect consults pattern (async lock, task chain, or `pending: [CheckedContinuation]` queue).
- **T-B3' generation atomic swap:** larger refactor; if breaks tests substantially → fall back к simpler «cleanup orphans on init» (closes A5'-002 partially).
- **T-B6' Fronting tag-scoped:** API change in `apply(json:)` may break callers; verify ConfigImporter integration point.
