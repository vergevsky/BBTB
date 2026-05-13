# Phase 06D-01 — Pre-flight

**Date:** 2026-05-14
**Wave:** 06D-01 (audit briefing + 3 parallel AI passes)
**Source:** Plan `06D-01-PLAN.md` Task 0

---

## 1. MCP availability check

| Tool | Status | Notes |
|---|---|---|
| `mcp__codex__codex` | ✅ Available | Schema loaded via ToolSearch |
| `mcp__codex__codex-reply` | ✅ Available | For multi-turn retries (delegator.md retry policy) |
| `mcp__gemini__gemini` | ✅ Available | Schema loaded via ToolSearch |
| `mcp__gemini__gemini-reply` | ✅ Available | For thread continuity if needed |

**Conclusion:** все три pass-а возможны (Opus internal + Codex via MCP + Gemini via MCP). Никакого ESCALATE на pre-flight.

---

## 2. Codebase signpost grep — ASSUMED A7 verification

Команда:
```bash
grep -rn "OSSignposter\|os_signpost\|signposter" BBTB --include="*.swift"
```

Результат: **0 matches** в production-коде.

**Conclusion:** RESEARCH ASSUMED A7 verified — никаких существующих OSSignposter / os_signpost / signposter usage в codebase. Wave 06D-02a Task 2 (signpost injection) будет green-field — никаких merge-conflicts с существующими instrumented spans.

---

## 3. Code-reviewer prompt 4-level fallback discovery

| Level | Path | Result |
|---|---|---|
| 1 | `${CLAUDE_PLUGIN_ROOT}/prompts/code-reviewer.md` | ❌ `CLAUDE_PLUGIN_ROOT` env var не установлен в этой сессии |
| 2 | `~/.claude/plugins/cache/*/prompts/code-reviewer.md` (glob) | ✅ **Found:** `/Users/vergevsky/.claude/plugins/cache/jarrodwatts-claude-delegator/claude-delegator/1.1.0/prompts/code-reviewer.md` |
| 3 | `~/.claude/get-shit-done/references/code-reviewer*.md` | ❌ Не существует |
| 4 | ESCALATE | ⏸ Не требуется — Level 2 hit |

**Selected:** Level 2 path. 100 LOC, проверен на shape (Summary / Critical Issues / Recommendations / Verdict).

---

## 4. Frozen brief skeleton (verbatim из RESEARCH § Multi-AI Audit Brief Template)

> **D-03 invariant:** identical text для всех 3 passes. Только одна substitution: filename в EXPECTED OUTCOME (`{OPUS|CODEX|GEMINI}` → конкретное имя) + OUTPUT header (`# Phase 6d Audit — {OPUS|CODEX|GEMINI} Pass`).

```text
1. TASK: Independent multi-AI peer-review audit of the BBTB iOS+macOS Swift codebase
   on five dimensions (performance, energy, simplicity, memory, launch) with a primary
   focus on two user-reported pain paths: cold start (icon tap → interactive MainScreen)
   and connect tap (power-button tap → .connected + ticking timer).

2. EXPECTED OUTCOME: A markdown table of findings using the exact column set:
   `# | Title | Dimension | Severity | File:Line | Description | Recommended fix`
   Saved to: `.planning/phases/06d-performance-audit/06D-FINDINGS-{OPUS|CODEX|GEMINI}.md`.
   Severity rubric (D-05a):
     HIGH = measurable user pain (>200ms perceived lag on cold start or connect tap),
            security/correctness concern, or active bug;
     MEDIUM = measurable sub-perception impact (50-200ms), maintenance debt with concrete
              cost, or energy regression on typical session;
     LOW = cosmetic / future-friction (<50ms), simplification without measurable impact.
   Maximum 40 findings per pass; quality over quantity.

3. CONTEXT:
   - Current state: BBTB is a VPN client targeting iOS 18+ and macOS 15+. Tech stack:
     SwiftUI + Swift Concurrency + SwiftData + NetworkExtension + sing-box via
     libbox.xcframework + Tuist-managed Xcode project.
   - Relevant code paths (read these in full before producing findings):
     * App entry: `BBTB/App/iOSApp/BBTB_iOSApp.swift` (156 LOC)
     * App entry: `BBTB/App/macOSApp/BBTB_macOSApp.swift` (149 LOC)
     * Hot-path package: `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/`
       (TunnelController.swift 316 LOC, MainScreenViewModel.swift 593 LOC,
        ConfigImporter.swift 1071 LOC, TunnelWatchdog.swift 267 LOC,
        OnDemandRulesBuilder.swift 180 LOC, plus ~12 smaller files)
     * Tunnel: `BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift`
     * sing-box build: `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/`
     * Parsers: `BBTB/Packages/ConfigParser/Sources/`
     * Protocol registry: `BBTB/Packages/ProtocolRegistry/Sources/`
     * Transport registry: `BBTB/Packages/TransportRegistry/Sources/`
     * Protocol packages: `BBTB/Packages/Protocols/{VLESSReality,VLESSTLS,
       Shadowsocks,Hysteria2,Trojan}/Sources/`
     * VPNCore types: `BBTB/Packages/VPNCore/Sources/`
   - Background: Phase 6c just landed a major refactor that took TunnelController
     from 909 → 316 LOC and deleted 5 files (ReconnectStateMachine, NetworkReachability,
     and their tests). Phase 6c invariants MUST be preserved (see CONSTRAINTS).
     The user reports the app "feels heavy" since Phase 5. Audit must localize the
     cause through specific findings.

4. CONSTRAINTS:
   - Technical: Swift 6 mode, Xcode 16+, iOS 18+, macOS 15+, no new third-party
     dependencies unless a finding has explicit user-impact justification.
   - Patterns: Apple-blessed concurrency (actors, structured Task), SwiftUI native,
     SwiftData (no Core Data fallback), NEOnDemandRule for reconnect (no custom
     state machines).
   - Limitations (Phase 6c invariants — NEVER recommend rolling back):
     * `TunnelController.handleStatusChange` intent-closing path UNCHANGED.
     * No XPC inside `NEVPNStatusDidChange` observer hot path.
     * No reintroduction of ReconnectStateMachine / NetworkReachability / custom
       retry loops.
     * `applyVPNStatus(_:connectedDate:)` remains SINGLE authority for
       MainScreenViewModel.state + reconnectBannerState.
     * Sliding session window invariant:
       `manager.isOnDemandEnabled = autoReconnectToggle && userIntendedConnected`.
     * Observer registration on `queue: nil` (NEVER `.main` — Phase 6c Round 6).
     * Никаких `#Predicate` с optional UUID (memory feedback).
   - Out of scope (do NOT propose):
     * Rewriting libbox.xcframework or sing-box internals.
     * Replacing the backend (Rust sing-box, alternative engines).
     * Migrating off SwiftPM (Bazel, etc.).
     * UI redesigns (Phase 11 territory).
     * Adding new dependencies as a general refactor — only with explicit
       user-impact justification.

5. MUST DO:
   - Read every file under the paths listed in CONTEXT before emitting findings.
   - Trace every finding to one of: cold start path, connect tap path, or indirect
     improvement that helps one of those (binary size reduction, hot-path complexity
     reduction, etc.).
   - For each finding, cite exact File:Line in the codebase. "Unknown" or "various"
     is not acceptable.
   - Mark severity per the D-05a rubric and justify it briefly.
   - For each finding, propose a concrete fix with files to change. "Refactor X"
     is not acceptable — say "extract method Y from file Z lines A-B into helper W".

6. MUST NOT DO:
   - Do not propose any change that violates a Phase 6c invariant (CONSTRAINTS).
   - Do not propose adding new dependencies unless explicit user-impact justification
     is given.
   - Do not propose UI redesigns or new features.
   - Do not emit abstract-beauty findings ("this could be more functional") without
     measurable user impact or maintenance cost reduction.
   - Do not propose libbox / sing-box / gomobile-binding rewrites.
   - Do not exceed 40 findings per pass — quality over quantity.

7. OUTPUT FORMAT: Markdown file at the path specified in EXPECTED OUTCOME.
   First line of body: `# Phase 6d Audit — {OPUS|CODEX|GEMINI} Pass`.
   Section 1: Executive summary (3-5 bullets — top patterns observed).
   Section 2: Findings table (column set above).
   Section 3: Methodology — what you read, what you skipped, why.
   Closing: estimated pass duration + your confidence level (HIGH/MEDIUM/LOW)
   per dimension.
```

---

## 5. Substitution map для Tasks 1/2/3

| Task | AI | Filename | OUTPUT header |
|---|---|---|---|
| 1 | Opus 4.7 | `06D-FINDINGS-OPUS.md` | `# Phase 6d Audit — OPUS Pass` |
| 2 | Codex GPT-5.2 | `06D-FINDINGS-CODEX.md` | `# Phase 6d Audit — CODEX Pass` |
| 3 | Gemini 3.1 Pro | `06D-FINDINGS-GEMINI.md` | `# Phase 6d Audit — GEMINI Pass` |

---

## 6. Gemini fallback chain (D-03, memory feedback)

1. `gemini-3.1-pro-preview` (primary)
2. `deep-research-preview-04-2026`
3. `gemini-3-pro-preview`
4. `gemini-3-flash-preview`
5. `gemini-2.5-pro`

При 503 / любой error — switch на next, retry с тем же prompt. После 5 fails → пауза 5-10 мин → повтор с primary. После повторного 5-fail → skip-record в `06D-FINDINGS-GEMINI.md` + продолжение с 2-pass synthesis (Opus + Codex).

---

## Pre-flight status: ✅ GREEN

Wave 06D-01 готова к запуску Tasks 1 / 2 / 3 параллельно.
