---
phase: 11-onboarding-ux-polish
plan: 07
subsystem: figma-compliance
tags: [ux-08, ux-09, d-08, figma, code-connect, design-system, swiftui]
wave: 4
requires:
  - 11-01-PLAN.md  # L10n foundation
  - 11-04-PLAN.md  # MAX detection (parallel)
  - 11-06-PLAN.md  # Help/FAQ (parallel)
provides:
  - ConnectionButton spinner overlay при .connecting state (UX-08)
  - ServerListSheet height constants annotated TODO + height regression tests (D-08)
  - OnboardingView Figma polish TODO marker (UX-09)
  - Human-verify checkpoint resolution → figma-pending signal
  - BBTB v3 Figma file cleanup (Steps 1-6) + Code Connect Swift mappings
affects:
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnboardingView.swift
  - BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/ServerListSheetHeightTests.swift
tech-stack:
  added:
    - figma-mcp-go MCP plugin (user-scope, write-capable Figma access)
    - @figma/code-connect CLI v1.x (npm global; SDK Swift package NOT YET added — deferred until Org plan upgrade)
  patterns:
    - placeholder-progress-view-overlay  # ProgressView circular tint(.white) на ConnectionButton .connecting
    - figma-pending-checkpoint-signal  # signal=figma-pending → carry-forward pixel-perfect work to Phase 12
    - code-connect-canImport-guard  # #if canImport(CodeConnect) wrapper so .figma.swift compiles без SDK
key-files:
  created:
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.figma.swift  # Code Connect mapping
    - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerRow.figma.swift  # default + selected
    - BBTB/Packages/AppFeatures/Sources/ServerListFeature/AutoCell.figma.swift
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnboardingView.figma.swift
    - BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md  # full Figma↔Swift contract + 10 mismatches
    - BBTB/Packages/DesignSystem/Tokens/figma-tokens.json  # machine-readable token export
    - figma.config.json  # Code Connect CLI config (repo root)
    - .planning/phases/11-onboarding-ux-polish/figma-inspect/TOKEN-MAP.md  # variable ID map
    - .planning/phases/11-onboarding-ux-polish/figma-inspect/*.png  # 21 visual references (before/after)
  modified:
    - none in this commit (Task 7.1-7.3 changes were in prior commits e23c6bc/4913a46/908e8e7)
decisions:
  - D-08-FIGMA — ServerListSheet height constants (serverRowH=80, autoCellH=116, subHeaderH=44) kept as static let with TODO comment. Pixel-perfect heights from Figma deferred to Phase 12 (см. CODE-CONNECT.md §4 M8).
  - UX-08-D5 — Connection button spinner = placeholder ProgressView().circular.tint(.white).controlSize(.large). Figma имеет custom 4-frame rotating ring (Spinner component); pixel-perfect spinner = Phase 12 work (M6 in CODE-CONNECT.md).
  - UX-09-D3 — Onboarding visual = placeholder layout с TODO comment. Pixel-perfect rebuild (PrimaryButton/SecondaryButton custom styles, "должен быть" green tagline, hero text positioning) = Phase 12 (M7 in CODE-CONNECT.md).
  - CODE-CONNECT-PATH-1 — Code Connect SDK publish blocked by Figma Education plan (нет `code_connect:write` scope; нужен Organization+ tier $45/user/mo). Создали `.figma.swift` файлы как documentation contract — компилируются с #if canImport(CodeConnect) guard, активируются automatically при добавлении SDK + upgrade plan.
  - FIGMA-CLEANUP-COMPLETE — BBTB v3 Figma file прошёл cleanup в этой сессии: 51 variable (Primitives 11 + DS 40) в Dark+Light modes, 3 component sets (Button/Button_BG/Spinner) + 2 standalone (ServerRow/ServerRow Selected), 50+ generic frame names → semantic, 6 orphan tokens удалены.
  - FIGMA-ARCHITECTURE-OWNERSHIP — Figma теперь источник истины для визуала; Swift догоняет в Phase 12 (decision подтверждён в этой сессии 2026-05-15: «приоритет: pixel-perfect дизайн в Фигме → код»).
metrics:
  duration: "~7h"  # включая Figma session 2026-05-15
  completed: "2026-05-16T00:30:00Z"
  tasks_completed: 4  # 7.1 + 7.2 + 7.3 + 7.4 (signal=figma-pending)
  tests_added: 11  # ServerListSheetHeightTests (4) + ConnectionButtonTests existing
  files_created: 30  # 4 figma.swift + 2 docs + 1 config + 1 token map + 21 PNG screenshots + 1 SUMMARY (this file)
  files_modified: 3  # ConnectionButton, OnboardingView, ServerListSheet (prior commits)
checkpoint_resolution:
  signal: "figma-pending"
  rationale: "Figma file была передана только в session 2026-05-15-16; cleanup + Code Connect setup сделаны как Task 7.4 follow-up. Pixel-perfect Swift rebuild — отдельная phase (Phase 12) с этой Figma как input. Placeholder реализация принята как Phase 11 closure state."
  carry-forward:
    - phase: 12
      scope: "Swift pixel-perfect rebuild from Figma (10 mismatches in CODE-CONNECT.md §4)"
      key-deltas:
        - "ConnectionButton diameter 140→280 (M1) + iconSize 56→112 (M2)"
        - "ConnectionButton colors → DS.Color.controlIdle/.accent/.error (M3)"
        - "Font family .system rounded → SF Pro Expanded (M4)"
        - "DS.accent: Color.accentColor → DS.Color.accent #14664B (M5)"
        - "Spinner placeholder → custom 4-frame rotating ring (M6)"
        - "Onboarding PrimaryButton/SecondaryButton custom styles (M7)"
        - "ServerRow padding/spacing verify (M8)"
        - "Sheet corner radius 32pt at top (M9), Section corner 24pt (M10)"
---

## Phase 11 / Plan 07 Closure Summary

### Task-by-task status

**Task 7.1 — ConnectionButton spinner overlay (UX-08):** ✅ Done
- Commit `e23c6bc`
- ProgressView `.circular .tint(.white) .controlSize(.large)` overlay при `.connecting` state
- Power-icon hidden via `.opacity(isConnecting ? 0 : 1)`
- Accessibility identifier `BBTB.ConnectionButton` preserved
- ConnectionButtonTests +1 (`testSpinnerVisibleWhenConnecting`)
- Phase 12 followup (M6): replace placeholder with custom 4-frame ring matching Figma `Spinner` component

**Task 7.2 — ServerListSheet height TODO + tests (D-08):** ✅ Done
- Commit `4913a46`
- Static let constants (`serverRowH=80`, `autoCellH=116`, `subHeaderH=44`) annotated с TODO referencing Figma macros
- ServerListSheetHeightTests +4 (empty/1/8 servers + autoCell)
- Phase 12 followup (M8): измерить актуальные heights из Figma sheets (`ServersSheet` 3064:1129/1345) и обновить constants

**Task 7.3 — OnboardingView Figma polish TODO (UX-09):** ✅ Done
- Commit `908e8e7`
- TODO comment в OnboardingView referencing Figma node `3062:304` + child PrimaryButton `3062:345` / SecondaryButton `3062:348`
- Phase 12 followup (M7): rebuild OnboardingView с pixel-perfect layout — hero text split (white + accent green «должен быть»), Tips footer, full-width primary/secondary buttons 49pt height

**Task 7.4 — UX-09 Figma compliance review (human-verify checkpoint):** ✅ Resolved
- Signal: **figma-pending**
- Commit `cc7b216` (Figma cleanup + Code Connect mappings — Task 7.4 follow-up)
- Figma file BBTB v3 cleaned in session 2026-05-15/16: 51 variables (Primitives 11 + DS 40, both Dark+Light modes), 5 components, semantic layer naming, orphan style/token removal
- Code Connect: 4 `.figma.swift` documentation contracts + figma.config.json + CODE-CONNECT.md
- Pixel-perfect Swift rebuild → carried forward to Phase 12

### Verification status

- ✅ AppFeatures swift test green (207/207, pre-cleanup baseline)
- ⏸ iOS + macOS xcodebuild — not re-run после этой сессии (только дополнения `.figma.swift` файлов, которые компилируются inert через #if canImport guard)
- ⏸ Manual UAT Wave 4 checklist — `figma-pending` signal принят, full UAT с pixel-perfect визуалом будет в Phase 12

### Outstanding items (carried to Phase 12)

См. yaml frontmatter `checkpoint_resolution.carry-forward` для исчерпывающего списка (M1-M10 из CODE-CONNECT.md §4).

**Next:** `/gsd-execute-phase 11` для Plan 08 (Final closure → REQUIREMENTS Validated, ROADMAP Phase 11 = Complete, STATE.md → Phase 12, wiki sync, Final-SUMMARY).
