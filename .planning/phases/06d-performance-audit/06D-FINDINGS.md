# Phase 6d — Multi-AI Audit Findings (synthesis)

**Status:** SKELETON — заполняется в Wave 06D-02b (synthesis).
**Date:** 2026-05-14 (Wave 06D-01 closure)
**Sources:**
- `06D-FINDINGS-OPUS.md` (40 findings — 6 HIGH / 19 MEDIUM / 15 LOW)
- `06D-FINDINGS-CODEX.md` (17 findings — 7 HIGH / 8 MEDIUM / 2 LOW)
- `06D-FINDINGS-GEMINI.md` (6 findings — 4 HIGH / 2 MEDIUM / 0 LOW)
- Total raw inputs: **63 findings** (до dedup).

**Synthesizer:** Opus 4.7 (anti-bias rule: when Opus's own finding conflicts with another AI's, other wins by default per RESEARCH Open Question #5).

---

## 1. Executive synthesis
*[TBD Wave 06D-02b Task 1 — будет наполнено после merge + dedup + invariant filter]*

---

## 2. Consolidated findings

| # | Title | Dimension | Severity | File:Line | Description | Opus | Codex | Gemini | Consensus | Recommended fix |
|---|---|---|---|---|---|---|---|---|---|---|

*[TBD Wave 06D-02b — populated via dedup/synthesis of 63 raw findings. Каждая строка — unique issue с пометкой какие AI нашли (FOUND/NOT FOUND) + consensus класс (3/3 strong / 2/3 moderate / 1/3 unique).]*

---

## 3. Rejected findings (Phase 6c invariant violations — D-09)

| # | Finding | Source AI | Invariant violated | Why dropped |
|---|---|---|---|---|

*[Pre-filter result: **0 finding-ов нарушили D-09** в трёх raw passes (verified Wave 01 — grep ReconnectStateMachine|NetworkReachability|ReconnectStateObserverRelay = 0 на каждом файле). Если synthesis в 02b обнаружит более скрытые violations — записать сюда.]*

---

## 4. Filtered findings (out-of-scope D-02a, abstract beauty, false uniqueness)

| # | Finding | Source AI | Reason |
|---|---|---|---|

*[TBD Wave 06D-02b — фильтр на: (a) libbox/sing-box rewrite proposals, (b) new dependency proposals без user-impact justification, (c) UI redesigns, (d) abstract-beauty без measurable impact, (e) false uniqueness (same root cause, different file:line).]*

---

## 5. Coverage matrix (per-AI per-dimension)

| AI | Performance | Energy | Simplicity | Memory | Launch |
|---|---|---|---|---|---|
| Opus | TBD | TBD | TBD | TBD | TBD |
| Codex | TBD | TBD | TBD | TBD | TBD |
| Gemini | TBD | TBD | TBD | TBD | TBD |

*[TBD Wave 06D-02b — для каждой клетки указывается finding count + один representative finding ID. Цель: убедиться, что каждый AI покрыл все 5 dimensions; пустая клетка = либо чистая зона, либо blind spot.]*

---

## 6. Notes for CHECKPOINT 1

*[TBD Wave 06D-02b Task 3 — counts by severity (после dedup), top-5 critical, recommended budget options:*
- *Option A (minimal): только HIGH findings — ожидаемый бюджет N waves*
- *Option B (balanced): HIGH + MEDIUM — ожидаемый бюджет M waves*
- *Option C (thorough): HIGH + MEDIUM + selected LOW — ожидаемый бюджет K waves*
- *Option D (custom): user указывает явный список IDs]*

---

## Preliminary consensus highlights (Wave 06D-01 quick-scan, before formal dedup)

> Эта секция — surface-level pattern observation от Opus после writing FINDINGS-OPUS.md и reading FINDINGS-CODEX.md / FINDINGS-GEMINI.md. Это **не synthesis**, это **дегустация** для Wave 02 priorities.

**3/3 strong consensus (все три AI нашли):**

1. **`logLevel: "trace"` в `BaseSingBoxTunnel.swift`** — leftover Phase 5 debug toggle. Все три pass-а отметили как HIGH (Opus MEDIUM, Codex HIGH, Gemini HIGH). Это вероятно главная причина «приложение тяжело грузится с Phase 5».
2. **`AppGroupContainer.exportSingBoxLogToDocuments()` в `BBTB_iOSApp.init()`** — синхронное копирование trace-log на cold start. Все три pass-а HIGH (или contributing-to-HIGH).
3. **Redundant XPC trips в `TunnelController.connect()`** — двойной save/load preferences (intent + isEnabled). Все три pass-а HIGH/MEDIUM.

**2/3 moderate consensus (два AI нашли):**

4. **Auto-mode pre-connect probe blocks tap** — Codex HIGH, Gemini HIGH (через MainActor SwiftData fetch); Opus отметил similar finding в другом ракурсе.
5. **SwiftData synchronous fetches on @MainActor в `refresh()` / `performPreConnectAutoSelect()`** — Codex + Gemini.
6. **`ConnectionTimer` keeps 1Hz publisher alive when idle** — Opus HIGH + Codex MEDIUM (Gemini не зафиксировал, но не противоречит).

**1/3 unique-but-valuable (только один AI, имеет смысл):**

7. **`startDefaultInterfaceMonitor` semaphore.wait без timeout** — Codex HIGH. Корректность баг в extension hot path.
8. **`autoDetectControl` ignores `currentInterfaceIndex == 0`** — Codex HIGH. Possible cause of failed connects in include-all-networks mode.
9. **Опус-уникальные паттерны:** 6 fire-and-forget XPC tasks at cold start (HIGH), 5-second disconnect polling sleep (HIGH), `fetch().count` vs `fetchCount()` (HIGH), oversized `applyVPNStatus` function (LOW), 4× loadFromStore per pullToRefresh (MEDIUM).

**Preliminary CHECKPOINT 1 forecast (placeholder — финал в 02b):**

- **Likely consensus HIGH after dedup:** 5-7 findings (trace logging, log export, XPC trips, auto-probe blocking, MainActor fetches, ConnectionTimer, semaphore.wait).
- **Likely consensus MEDIUM after dedup:** 10-15 findings.
- **Likely LOW after dedup:** ~10-15 findings.
- **Total dedup estimate:** ~35-45 unique findings из 63 raw.

---

*Phase: 06d-performance-audit*
*Wave: 06D-01 closure*
*Next: Wave 06D-02b — formal synthesis, dedup, invariant filter, coverage matrix, CHECKPOINT 1 budget summary.*
