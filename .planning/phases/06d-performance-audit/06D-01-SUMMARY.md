---
phase: 06d-performance-audit
plan: 01
type: summary
status: complete
date: 2026-05-14
---

# Plan 06D-01 — Wave 1 SUMMARY

## Status
Three independent audit passes (Opus, Codex, Gemini) **completed in parallel**. Все три AI прочитали указанные Swift файлы и выдали структурированные findings. Synthesis (объединение, dedup, invariant-filter, coverage matrix) — следующая wave (06D-02b).

## Pass results

| Pass | Source | Duration | Findings count | Severity breakdown | Status |
|---|---|---|---|---|---|
| Opus 4.7 | general-purpose Agent (internal thread) | ~6 min | **40** total | H/M/L = 6/19/15 | ✅ Complete |
| Codex GPT-5.2 | `mcp__codex__codex` (sandbox=read-only) | ~5 min | **17** total | H/M/L = 7/8/2 | ✅ Complete |
| Gemini 3.1 Pro | `mcp__gemini__gemini` (sandbox=read-only) | ~5 min | **6** total | H/M/L = 4/2/0 | ✅ Complete |
| **Total raw** | — | — | **63** | H/M/L = **17/29/17** | До dedup |

## Gemini fallback history
Primary model `gemini-3.1-pro-preview` **сработал с первой попытки** — fallback chain не задействован. Memory feedback про frequent 503 не подтвердился в этом случае.

## Invariant violations detected (preview for Wave 02 filter)
**0 violations** в трёх raw passes (verified through grep на каждом файле):

```bash
for f in .planning/phases/06d-performance-audit/06D-FINDINGS-{OPUS,CODEX,GEMINI}.md; do
  grep -v '^#' "$f" | grep -cE "ReconnectStateMachine|NetworkReachability|ReconnectStateObserverRelay"
done
# → 0 / 0 / 0
```

Никаких rollback-proposals для Phase 6c invariants. Все три AI honored CONSTRAINTS из брифа.

## Preliminary consensus highlights (informal scan)

**3/3 strong consensus:**
1. **`logLevel: "trace"` в `BaseSingBoxTunnel.swift:115/169`** — leftover Phase 5 debug. Likely главная причина «приложение тяжело грузится с Phase 5».
2. **`exportSingBoxLogToDocuments()` в `BBTB_iOSApp.init()`** — синхронное копирование multi-MB trace-log на cold start.
3. **Redundant XPC trips в `TunnelController.connect()`** — двойной save/load NEVPN preferences.

**2/3 moderate consensus:**
4. Auto-mode probe blocks Connect tap (Codex HIGH, Gemini HIGH).
5. SwiftData synchronous fetches на `@MainActor` в `refresh()` / `performPreConnectAutoSelect()` (Codex + Gemini).
6. `ConnectionTimer` keeps 1Hz publisher alive when idle (Opus HIGH + Codex MEDIUM).

**1/3 unique-but-valuable:**
7. `startDefaultInterfaceMonitor` semaphore.wait без timeout (Codex HIGH — correctness bug).
8. `autoDetectControl` ignores `currentInterfaceIndex == 0` (Codex HIGH).
9. Opus-уникальные паттерны (6 fire-and-forget XPC tasks at cold start, 5-second disconnect polling, `fetch().count` vs `fetchCount()`, oversized `applyVPNStatus`).

## Verification metrics

| Check | Required | Actual | Status |
|---|---|---|---|
| `06D-FINDINGS-OPUS.md` exists | yes | 39271 bytes | ✅ |
| `06D-FINDINGS-OPUS.md` > 2KB | yes | 39271 > 2000 | ✅ |
| `06D-FINDINGS-OPUS.md` header «OPUS Pass» | yes | line 1 ✓ | ✅ |
| `06D-FINDINGS-CODEX.md` exists | yes | 13061 bytes | ✅ |
| `06D-FINDINGS-CODEX.md` > 2KB | yes | 13061 > 2000 | ✅ |
| `06D-FINDINGS-CODEX.md` header «CODEX Pass» | yes | line 1 ✓ | ✅ |
| `06D-FINDINGS-GEMINI.md` exists | yes | 6716 bytes | ✅ |
| `06D-FINDINGS-GEMINI.md` > 2KB | yes | 6716 > 2000 | ✅ |
| `06D-FINDINGS-GEMINI.md` header «GEMINI Pass» | yes | line 1 ✓ | ✅ |
| `06D-FINDINGS.md` skeleton 6 sections | yes | 1/2/3/4/5/6 ✓ | ✅ |
| Forbidden symbols (D-09) across all 3 files | 0 | 0 / 0 / 0 | ✅ |
| Regression gate | N/A (audit-only wave) | not run | ✅ (per plan) |

## Decisions

- **Gemini fallback chain не понадобилась.** Primary model сработал. Wave 06D-02b synthesizer работает с тремя полными pass-ами.
- **Invariant violations = 0 во всех 3 pass-ах.** Wave 02b filter не нужно scanit'ить отдельно за violations — все три AI proactively honored CONSTRAINTS.
- **Финдинг counts асимметричны** (Opus 40, Codex 17, Gemini 6). Не нарушение — research предполагал, что разные AI выдадут разную глубину. Synthesis в 02b сделает dedup и поднимет 3/3-consensus наверх независимо от raw counts.
- **Preliminary consensus highlights** уже видны до formal synthesis. Это позволяет 02a (Wave 0 gaps) начать готовить сценарии fix-cycle (Periphery scan + signpost injection) пока 02b формализует FINDINGS.md.

## Next

Wave 06D-02a — **Wave 0 gaps** (Periphery 3.7.4 install + jq/ripgrep + PerfSignposter + 5 signpost injection sites + baseline templates + `.gitignore` *.trace + ASSUMED-claim verification log). 3 атомарных commit'а с regression gate между каждым.

Затем Wave 06D-02b — synthesis (consolidated FINDINGS table, dedup, invariant filter, coverage matrix), затем Wave 06D-02c (pre-fix Instruments baseline на iPhone + 🛑 CHECKPOINT 1 budget decision).
