---
phase: 06d-performance-audit
plan: 02b
type: summary
status: complete
date: 2026-05-14
commits:
  - "<pending> — docs(06d-02b): synthesis of 3 AI passes — consolidated FINDINGS with consensus markers + invariant filter"
---

# Plan 06D-02b — Wave 2.2 SUMMARY

## Status
✅ Synthesis complete. 06D-FINDINGS.md filled with consolidated table + invariant filter + coverage matrix + budget options preview. Synthesizer: Opus 4.7 (D-04 explicit). Anti-bias rule applied.

## Findings totals (post-filter, post-dedup)

| Severity | Count |
|---|---|
| HIGH | **9** |
| MEDIUM | **16** |
| LOW | **20** |
| **Total unique** | **45** |

Reduction: 63 raw → 45 unique (21 false-uniqueness merges, 0 rejected, 0 filtered out-of-scope).

## Filter breakdown

| Filter | Count moved out | Notes |
|---|---|---|
| Rejected by D-09 (Phase 6c invariant violations) | **0** | Все 3 AI honored CONSTRAINTS из брифа. Critical win. |
| Filtered as out-of-scope (D-02a — libbox rewrite / SwiftPM / new deps) | **0** | Все 3 AI proactively избегали этих категорий. |
| Filtered as abstract-beauty | **0** | Все findings имеют measurable impact rationale. |
| Merged as false-uniqueness (semantic duplicates → single consolidated row) | **21** | 6 SwiftData fetch overlaps + 3 ConnectionTimer downstream + 2 double-load + 2 probe storm + 3 cold-start XPC + 2 config validation + 2 MainActor SwiftData + 1 prettyPrinted cross-ref. |

## Coverage matrix

| AI | Performance | Energy | Simplicity / Maintainability | Memory | Launch / Cold start | Correctness | Total |
|---|---|---|---|---|---|---|---|
| **Opus 4.7** | 8 | 12 | 4 | 4 | 11 | 5 | **40** |
| **Codex GPT-5.2** | 7 | 3 | 1 | 2 | 6 | 3 | **17** |
| **Gemini 3.1 Pro** | 3 | 1 | 0 | 1 | 4 | 0 | **6** |

**Coverage observations:**
- Performance / Launch — все 3 AI sound; strongest consensus.
- Energy — Opus dominate (12 findings); Codex+Gemini caught the critical one (H1 trace logging).
- Simplicity / Maintainability — только Opus покрыл (expected blind spot для Codex/Gemini — они оптимизированы на CRITICAL issues, не на maintainability nits).
- Correctness — Codex unique (H9 NWPathMonitor + M9 autoDetectControl); валуа добавлена tri-pass design'ом.

## Consensus distribution

| Marker | Count | Notes |
|---|---|---|
| **3/3 strong** (все 3 AI нашли) | **5** | H1 (trace log), H2 (XPC trips), H4 (auto-probe), H6 (countSupportedConfigs), M1 (cold-start XPC fan-out) — это **anchor findings** для Wave 03. |
| **2/3 moderate** (2 AI нашли) | **6** | H3 (polling loop), H5 (ConnectionTimer), M2 (SwiftData migration), M3 (runIsSupportedUpgrade), M4 (refresh N+1), M7 (scenePhase), M8 (config validate ×3) — strong evidence, рекомендуется в Option B. |
| **1/3 unique-but-valuable** (1 AI) | **34** | Включая 2 Codex correctness bugs (H9, M9) + 1 Gemini unique (M5 Keychain) + Opus tail (LOW findings + 5 MEDIUM correctness). |

## Anti-bias check (RESEARCH Open Question #5)

**Прямых конфликтов между Opus's own findings и Codex/Gemini — 0.** Где есть overlap:
- H2 — Opus #16 (MEDIUM) overlaps с Codex #5 (HIGH) + Gemini #3 (HIGH) → severity upgraded к HIGH per Codex/Gemini consensus. **Opus's lower assessment overridden.**
- H4 — Opus #27 (MEDIUM) overlaps с Codex #1 (HIGH) + Gemini #4 (HIGH) → severity upgraded к HIGH. **Opus's lower assessment overridden.**
- H6 — Opus #4 (HIGH) overlaps с Codex #14 (MEDIUM) + implicit Gemini #6 → kept HIGH (Opus's higher held).

Other overlaps: Opus + Codex severities consistent в 3 cases (no override).

**Rejected my own findings: 0** (no rejected outright — но **2 Opus severity assessments overridden DOWN-to-HIGH (что correct upgrade)** в favor of Codex/Gemini consensus).

## Verification metrics

| Check | Required | Actual | Status |
|---|---|---|---|
| `06D-FINDINGS.md` exists | yes | created | ✅ |
| `06D-FINDINGS.md` > 4KB | yes | ~25KB | ✅ |
| Contains "Consolidated findings" header | yes | ✓ | ✅ |
| Contains "Rejected findings.*invariant" section | yes | ✓ | ✅ |
| Contains "Filtered findings" section | yes | ✓ | ✅ |
| Contains "Coverage matrix" section | yes | ✓ | ✅ |
| Contains consensus markers (3/3 / 2/3 / 1/3) | yes | 5+6+34 distribution | ✅ |
| D-09 rejected count documented | yes | 0 (preserved invariants) | ✅ |
| Anti-bias rule applied + documented | yes | 2 severity upgrades | ✅ |

## Top-5 critical (anchor для Wave 06D-03 fix-cycle)

| Anchor | Title | Consensus | Severity | Estimated user-impact closure |
|---|---|---|---|---|
| H1 | `logLevel: "trace"` + `exportSingBoxLogToDocuments` (Phase 5 leftover) | 3/3 strong | HIGH | ~50% «feels heavy since Phase 5» |
| H2 | Redundant XPC trips в `TunnelController.connect()` | 3/3 strong | HIGH | ~200ms+ saved per connect tap |
| H3 | Connect polling loop 1s false latency | 2/3 moderate | HIGH | Immediate UX win на connect tap |
| H4 | Auto-mode pre-connect probe blocks tap | 3/3 strong | HIGH | 500-1500ms saved (depends on pool size) |
| H6 | `countSupportedConfigs()` materialization | 3/3 strong | HIGH | Immediate cold-start win + memory reduction |

## Next

**Wave 06D-02c** — pre-fix Instruments baseline на iPhone (cold-launch / connect-tap / energy / allocations) + macOS cold-launch + Periphery scan + 06D-FINDINGS-SUMMARY.md (numerical baseline) + **🛑 CHECKPOINT 1** (user budget decision: Option A / B / C / custom).

Wave 06D-02c требует **физическое устройство iPhone + Mac** и **Xcode Instruments** — это **natural autonomous stop point**. После CHECKPOINT 1 → Wave 06D-03 fix-cycle materialization per chosen budget.
