---
phase: 06c-on-demand-migration
plan: 05
type: execute
wave: 5
depends_on: ["06c-on-demand-migration:04"]
files_modified:
  - .planning/STATE.md
  - .planning/PROJECT.md
  - .planning/REQUIREMENTS.md
  - .planning/ROADMAP.md
  - .planning/phases/06c-on-demand-migration/06C-UAT.md
  - wiki/index.md
  - wiki/log.md
  - wiki/auto-reconnect.md
autonomous: false
requirements: [NET-08, NET-09, NET-10, NET-11]
must_haves:
  truths:
    - "Phase 1-6 success criteria все re-validated после Phase 6c cutover — UAT regression smoke documented"
    - "Phase 6c два новых success criteria validated: bug-class-3 (other VPN switch), bug-class-4 (no EXC_RESOURCE)"
    - "NET-08, NET-09, NET-10, NET-11 marked validated through на-demand evaluation path в REQUIREMENTS.md (или указано where через UAT confirmed)"
    - "STATE.md обновлён: Phase 6c complete; next phase ready"
    - "PROJECT.md обновлён: 4 NET-* requirements moved to Validated/Complete сегмент"
    - "wiki/auto-reconnect.md создан/обновлён с архитектурным решением «on-demand вместо custom state machine», ссылка на 06C decisions"
    - "wiki/index.md содержит ссылку на новый/обновлённый page"
    - "wiki/log.md содержит запись о Phase 6c completion"
    - "Memory entry обновлён о Phase 6c completion (для cross-conversation persistence)"
  artifacts:
    - path: ".planning/phases/06c-on-demand-migration/06C-UAT.md"
      provides: "Полный UAT report со всеми 9 сценариями + Phase 1-6 regression smoke results"
      min_lines: 80
    - path: "wiki/auto-reconnect.md"
      provides: "Wiki page documenting on-demand architecture decision"
      min_lines: 50
  key_links:
    - from: "REQUIREMENTS.md NET-08..11"
      to: "Phase 6c validation"
      via: "Status update [x] with validation note"
      pattern: "NET-08\\|NET-09\\|NET-10\\|NET-11"
    - from: "ROADMAP.md Phase 6c entry"
      to: "Completed marker"
      via: "Status update"
      pattern: "Phase 6c"
    - from: "wiki/index.md"
      to: "wiki/auto-reconnect.md"
      via: "navigation link"
      pattern: "auto-reconnect"
---

<objective>
Wave 4 / Regression + Phase 6c UAT validation + Documentation — Закрыть фазу formally: задокументировать UAT results всех 9 сценариев + Phase 1-6 regression smoke, обновить planning artifacts, синхронизировать wiki, mark requirements как validated.

Это **document-and-close wave**. Никаких code changes. UAT уже прошёл в Plan 06C-04 Task 2; Wave 4 формализует results и переносит project state.

Purpose:
- D-22 (полный UAT smoke на iPhone iOS 26.5 + macOS) — formal record. Не оставлять без UAT.md как Phase 6 сделал.
- ROADMAP-уровневая регрессия (Phase 6c SC 7) — explicit confirmation что Phase 1-6 success criteria продолжают выполняться.
- CLAUDE.md GSD rule: «архитектурные решения фиксировать в wiki» — on-demand vs custom state machine это огромное архитектурное решение, должно быть в wiki.
- Memory hygiene: следующая conversation/instance Claude должна знать что Phase 6c complete, custom-reconnect machinery gone, on-demand принят как pattern.

Output:
- New: `.planning/phases/06c-on-demand-migration/06C-UAT.md` — full UAT report.
- New: `wiki/auto-reconnect.md` (или обновлённый existing если есть).
- Modified: `.planning/STATE.md` (current phase advanced); `.planning/PROJECT.md` (NET requirements migrated to Validated); `.planning/REQUIREMENTS.md` (NET-08..11 marked complete with validation note); `.planning/ROADMAP.md` (Phase 6c status updated); `wiki/index.md` (link to auto-reconnect page); `wiki/log.md` (Phase 6c entry).
- Updated: project memory entry (через Claude's memory.md mechanism if available, или explicit reminder в SUMMARY).

**Что НЕ делается:**
- Никаких code changes (всё уже сделано в Plan 06C-04).
- Нет UI tweaks.
- Нет дополнительных tests.
- Phase 7 planning — отдельный workflow (`/gsd-discuss-phase 7`).
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/REQUIREMENTS.md
@.planning/phases/06c-on-demand-migration/06C-CONTEXT.md
@.planning/phases/06c-on-demand-migration/06C-04-PLAN.md

<interfaces>
<!-- ROADMAP.md Phase 6c entry (lines 151-165): -->
<!-- Status currently «in progress» implicit. After Wave 4 → mark «✓ Complete YYYY-MM-DD». -->
<!-- Success criteria list проходим по checked-boxes. -->

<!-- REQUIREMENTS.md NET-08..11 (lines 109-112): -->
<!-- Currently: -->
<!-- - [ ] NET-08: Auto-reconnect при смене Wi-Fi ↔ LTE -->
<!-- - [ ] NET-09: Auto-reconnect после выхода из sleep -->
<!-- - [ ] NET-10: Auto-reconnect при смене IP -->
<!-- - [ ] NET-11: Failover на другой сервер при падении -->
<!-- After Wave 4: -->
<!-- - [x] NET-08: validated via Apple on-demand evaluation (Phase 6c UAT-Task A 2026-05-XX) -->
<!-- ... -->

<!-- PROJECT.md: ищет секцию «Validated requirements» или эквивалент — обычно table mapping. Phase 1 mover precedent: -->
<!-- «Phase 1 — Foundation ✓ COMPLETE — 8 validated requirements: CORE-01..04..06..07..08..10, KILL-01..02, SEC-01..05, LOC-01». -->

<!-- STATE.md current_phase pointer — update to 7 (or whatever next phase number is per ROADMAP). -->

<!-- wiki/index.md format (per CLAUDE.md): table of contents с one-line descriptions. -->
<!-- Pattern: «[auto-reconnect](auto-reconnect.md) — Apple's on-demand механизм, заменяет custom state machine Phase 6». -->

<!-- wiki/log.md append-only: format «- 2026-05-XX: Phase 6c complete — on-demand migration → see wiki/auto-reconnect.md». -->

<!-- wiki/auto-reconnect.md format (per CLAUDE.md): -->
<!-- # Auto-reconnect -->
<!-- **Summary**: On-demand механизм Apple вместо custom reconnect state machine. Phase 6c (2026-05-XX). -->
<!-- **Sources**: ... -->
<!-- **Last updated**: 2026-05-XX -->
<!-- --- -->
<!-- Контекст (зачем), решение (что выбрали), обоснование (почему on-demand), trade-offs, что становится TODO. -->

<!-- Phase 1 SECURITY.md pattern для phase-level closing — UAT.md идентичен по структуре: -->
<!-- - Test results table -->
<!-- - Regression check table (Phase 1-6 success criteria status) -->
<!-- - Decisions confirmed -->
<!-- - Issues found (and dispositions: fixed / accepted / deferred) -->
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Compile 06C-UAT.md — record 9 Phase 6c scenarios + Phase 1-6 regression smoke</name>
  <files>.planning/phases/06c-on-demand-migration/06C-UAT.md</files>
  <read_first>
    - .planning/phases/06c-on-demand-migration/06C-04-PLAN.md (uat_checklist section — 9 scenarios + criteria)
    - .planning/phases/06c-on-demand-migration/06C-04-SUMMARY.md (если уже создан в Plan 06C-04 — copy UAT result records out)
    - .planning/phases/06-network-resilience/06-06-SUMMARY.md (для понимания Phase 6 final state)
    - .planning/ROADMAP.md Phase 1, 2, 3, 4, 5, 6 success criteria sections — для compile regression list
  </read_first>
  <action>
    Создать `.planning/phases/06c-on-demand-migration/06C-UAT.md` с тремя секциями:

    ### Section 1 — Phase 6c сценарии (A-I)
    Markdown table с колонками: Scenario | Platform | Expected | Actual | Status (PASS/FAIL/PARTIAL/N/A) | Notes.
    9 строк (A-I) скопированных из Plan 06C-04 uat_checklist + actual results.
    Если планер не имеет UAT results под рукой — оставить ровно placeholder structure с указанием «to be filled by executor after running Plan 06C-04 Task 2». **Это OK** — executor этого plan может finalize после running UAT в Plan 06C-04.

    ### Section 2 — Phase 1-6 success criteria regression smoke
    Table mapping каждого SC из Phase 1..6 → re-validated status в Phase 6c environment.

    Источник списка SC:
    - Phase 1 SC: см. ROADMAP.md Phase 1 success criteria (8 SCs).
    - Phase 2 SC: см. ROADMAP.md Phase 2 (UAT T0-T9 from memory entry).
    - Phase 3 SC: 8/8 UAT PASS из memory entry.
    - Phase 4 SC: 151+49 tests из memory entry.
    - Phase 5 SC: 376 tests, UAT 5 checks из memory entry (5 deferred manual checks).
    - Phase 6 SC: 6 success criteria (DNS leak, IPv6 leak, Wi-Fi↔LTE, wake, failover) — все carry-over.

    Format pattern: `| Phase | SC# | Description | Phase 6c status | Note |`.

    Phase 6c environment changes affecting any prior SC?
    - Phase 6 SC 1 (DNS leak) — НЕ затронут (D-18). Status: PASS by carry-over.
    - Phase 6 SC 2 (IPv6 leak) — НЕ затронут (D-18). Status: PASS by carry-over.
    - Phase 6 SC 3 (Wi-Fi↔LTE) — теперь validated via on-demand (D-19). Status: PASS via UAT-Task A/D.
    - Phase 6 SC 4 (wake) — теперь iOS on-demand + macOS hybrid (D-20). Status: PASS via UAT-Task B/C.
    - Phase 6 SC 5 (failover initial-connect) — preserved (D-21). Status: PASS by carry-over.
    - Phase 6 SC 6 (TLS) — irrelevant в Phase 6c scope. Status: PASS by carry-over.

    Phase 1 KILL-01..03, SEC-01..05 — все validated, никакого касания в Phase 6c. Status: PASS by carry-over.

    ### Section 3 — Decisions confirmed + issues
    - Какие decisions из CONTEXT (D-01..D-25) validated через UAT?
    - Какие issues всплыли в UAT? Disposition?
    - Pitfall 5 (watchdog vs on-demand race) — UAT-Task E result: validated не race или mitigation applied?
    - Any deferred items?

    ### Section 4 — Phase 6c metrics
    - Lines removed: ReconnectStateMachine (182) + NetworkReachability (168) + TunnelControllerStateTests (~X) + TunnelController slim (~300 lines) ≈ Total ~570+ lines removed.
    - Lines added: OnDemandRulesBuilder + Tests + Migration + Tests + Watchdog + Tests + Settings UI + Tests ≈ Total ~Y lines.
    - Net code change: negative (target ~570 removed minus ~Y added = net reduction).

    Header doc-comment ссылающийся на Phase 6c / D-22 / Plan 06C-05.
  </action>
  <verify>
    <automated>test -s .planning/phases/06c-on-demand-migration/06C-UAT.md && grep -c "PASS\\|FAIL\\|N/A\\|PARTIAL" .planning/phases/06c-on-demand-migration/06C-UAT.md | awk '{ if ($1 >= 15) print "OK: " $1 " result rows"; else exit 1 }'</automated>
  </verify>
  <acceptance_criteria>
    - File exists и не пуст.
    - Contains все 9 Phase 6c scenarios (A-I) в Section 1.
    - Contains Phase 1-6 regression table в Section 2.
    - Decisions section ссылается на минимум 5 D-XX numbers.
    - Total ≥ 80 строк.
  </acceptance_criteria>
  <done>06C-UAT.md существует — formal phase-completion record.</done>
</task>

<task type="auto">
  <name>Task 2: Update planning artifacts — STATE.md, PROJECT.md, REQUIREMENTS.md, ROADMAP.md</name>
  <files>.planning/STATE.md, .planning/PROJECT.md, .planning/REQUIREMENTS.md, .planning/ROADMAP.md</files>
  <read_first>
    - .planning/STATE.md полностью (понять current_phase pointer + active phase)
    - .planning/PROJECT.md секция «Validated requirements» (если есть; иначе main requirement table)
    - .planning/REQUIREMENTS.md строки 100-120 (NET-* requirements)
    - .planning/ROADMAP.md строки 140-170 (Phase 6c entry)
    - .planning/phases/06c-on-demand-migration/06C-UAT.md (Task 1 output — для citation)
  </read_first>
  <action>
    **STATE.md:**
    - Update current phase: `current_phase: 07-anti-dpi-suite` (или whatever next phase is — see ROADMAP).
    - Update last_completed: `last_completed: 06c-on-demand-migration`.
    - Add decision/note: «Phase 6c on-demand migration complete — 06C-UAT.md».

    **PROJECT.md:**
    - Если есть «Validated requirements» секция: переместить NET-08, NET-09, NET-10, NET-11 туда with note «Validated 2026-05-XX via on-demand evaluation + watchdog mid-session failover».
    - Если есть «Phase status» summary: add `Phase 6c — Complete 2026-05-XX`.

    **REQUIREMENTS.md:**
    - Lines 109-112 (NET-08, NET-09, NET-10, NET-11): mark `[x]` with validation suffix:
      ```
      - [x] NET-08: Auto-reconnect при смене Wi-Fi ↔ LTE — Phase 6c UAT-Task A PASS 2026-05-XX (via NEOnDemandRuleConnect)
      - [x] NET-09: Auto-reconnect после выхода из sleep — Phase 6c UAT-Task B/C PASS 2026-05-XX (iOS on-demand + macOS hybrid)
      - [x] NET-10: Auto-reconnect при смене IP — Phase 6c UAT-Task D PASS 2026-05-XX
      - [x] NET-11: Failover на другой сервер при падении — Phase 6c UAT-Task E PASS 2026-05-XX (watchdog + SwiftDataFailoverProvider)
      ```
    - Замените даты на actual UAT date.

    **ROADMAP.md:**
    - Phase 6c entry (lines 151-167): add header `**Status:** ✓ Complete YYYY-MM-DD`.
    - Add to success criteria checkmarks `[x]` on each criterion that validated.
    - Note: «Custom auto-reconnect machinery removed; ~570 lines deleted».
    - Не помечать Phase 6c как «next» если он done — точечно сделать это завершённым.
  </action>
  <verify>
    <automated>grep -c "\\[x\\] NET-08\\|\\[x\\] NET-09\\|\\[x\\] NET-10\\|\\[x\\] NET-11" .planning/REQUIREMENTS.md | awk '{ if ($1 >= 4) print "OK"; else exit 1 }' && grep -c "Phase 6c.*Complete\\|on-demand-migration.*Complete" .planning/ROADMAP.md .planning/STATE.md .planning/PROJECT.md | awk -F: '{sum += $2} END { if (sum >= 1) print "OK: " sum; else exit 1 }'</automated>
  </verify>
  <acceptance_criteria>
    - All 4 NET-* requirements marked `[x]` в REQUIREMENTS.md.
    - ROADMAP.md Phase 6c entry помечена `Complete`.
    - STATE.md current_phase advanced past 06c.
    - PROJECT.md содержит note о Phase 6c completion.
  </acceptance_criteria>
  <done>Planning artifacts отражают completion Phase 6c.</done>
</task>

<task type="auto">
  <name>Task 3: Create/Update wiki/auto-reconnect.md + wiki/index.md + wiki/log.md</name>
  <files>wiki/auto-reconnect.md, wiki/index.md, wiki/log.md</files>
  <read_first>
    - wiki/index.md (структура — как организованы links)
    - wiki/log.md последние 50 строк (формат entries)
    - CLAUDE.md секция «Page format» и «Ingest workflow»
    - Любой existing wiki page для pattern reference (например wiki/security-gaps.md или wiki/tspu.md если такая есть)
  </read_first>
  <action>
    Per CLAUDE.md «архитектурные решения фиксировать в wiki».

    **wiki/auto-reconnect.md** — создать (или обновить если уже существует):

    ```markdown
    # Auto-reconnect

    **Summary**: Apple's on-demand механизм (`NETunnelProviderManager.isOnDemandEnabled` + `NEOnDemandRuleConnect`) — основа auto-reconnect в BBTB. Custom state machine, написанная в Phase 6, удалена в Phase 6c после того как UAT выявил 4 класса bugs из её хрупкости.

    **Sources**: `.planning/phases/06c-on-demand-migration/06C-RESEARCH.md`, `.planning/phases/06c-on-demand-migration/06C-CONTEXT.md`, `.planning/phases/06c-on-demand-migration/06C-UAT.md`, `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md`.

    **Last updated**: 2026-05-XX (Phase 6c completion).

    ---

    ## Контекст

    Phase 6 реализовал custom auto-reconnect: ReconnectStateMachine (3 attempts × exp backoff) + NEVPNStatusDidChange observer pipeline + NWPathMonitor triggers + 4 manual флага intent tracking. Phase 6 UAT выявил 4 bug classes:
    1. Phantom reconnect на fresh install (Reachability fires `.satisfied` без user intent).
    2. Phantom reconnect после import (saveToPreferences raises `.disconnected`).
    3. Mach port exhaustion на iOS 26 (EXC_RESOURCE/PORT_SPACE craш).
    4. Fight-back с другими VPN-приложениями.

    Корень всех 4 — мы реализовали поведение, которое iOS уже умеет.

    ## Решение

    Phase 6c migration на iOS-нативный mechanism:
    - `NETunnelProviderManager.isOnDemandEnabled = true` (master toggle).
    - `onDemandRules = [NEOnDemandRuleConnect(.any)]` (один rule: «любой interface available → connect»).
    - Apple's evaluation loop срабатывает на network change, wake, app launch — без нашего observer pipeline.

    Дополнительно сохранён узко-целевой **TunnelWatchdog**: реагирует ТОЛЬКО на «сервер умер» (stable session ≥ 30s + `.disconnected` + manager.isEnabled snapshot + user intent), вызывает `SwiftDataFailoverProvider.nextServerAttempt()` для swap к следующему серверу. Apple's on-demand параллельно retry'ит — но retry'ит TOT же (теперь dead) сервер; наш swap config обгонит.

    macOS hybrid: on-demand как primary + `NSWorkspace.didWakeNotification` observer что вызывает идемпотентный `startVPNTunnel()` после wake (Apple staff thread/688021 — known macOS edge case).

    ## Обоснование

    1. **Reliability**: Apple's on-demand протестирован MDM/enterprise 10+ лет. Custom code = race conditions + actor reentrance + Mach port pressure.
    2. **Code reduction**: ~570 строк custom logic удалены (ReconnectStateMachine 182 + NetworkReachability 168 + ~220 строк TunnelController flags/observers).
    3. **Future extensibility**: `OnDemandRulesBuilder` API — single source of truth. Phase 8 Rules Engine добавит `NEOnDemandRuleEvaluateConnection` (per-SSID/per-domain) без изменения callsites.
    4. **Bug class elimination**: все 4 Phase 6 UAT bug classes уходят by design — нет observer hot path → нет XPC storm; нет Reachability triggering → нет phantom reconnect; iOS управляет VPN-приоритетом → нет fight-back.

    ## Trade-offs

    - **Меньше control**: мы не можем кастомизировать retry policy (backoff curve, jitter). Apple's evaluation opaque. Acceptable для нашего use case.
    - **Debugging hard**: когда Apple's on-demand не fires — мало инструментов (logs `subsystem:com.apple.networkextension`). UAT критичен для каждого release.
    - **macOS edge cases**: wake observer нужен — Apple staff confirms.

    ## TODO

    - Phase 8 — Rules Engine (per-SSID, per-domain) добавит rules в `OnDemandRulesBuilder.buildRules()` без breaking changes.
    - Phase 10 — Advanced settings («подключаться только в публичных Wi-Fi») использует ту же architecture.

    ## Related pages

    - [[security-gaps]] — Phase 1 security audit (R1, R6, KILL контролы)
    - [[server-failover]] (если existing) или новая страница про SwiftDataFailoverProvider
    - [[apple-vpn-api]] (если existing) для NetworkExtension API surface
    ```

    Если какая-то [[link]] referenced page не существует, ОК — это normal для нового pages add'ed by other phases.

    **wiki/index.md** — обновить:
    Найти секцию (например «# Architecture» или «# Networking»). Add line:
    ```
    - [auto-reconnect](auto-reconnect.md) — Apple's on-demand механизм, замена custom state machine Phase 6 (Phase 6c)
    ```

    **wiki/log.md** — append:
    ```
    - 2026-05-XX: Phase 6c on-demand migration complete; created wiki/auto-reconnect.md; ~570 lines of custom auto-reconnect code deleted. См. `.planning/phases/06c-on-demand-migration/06C-UAT.md`.
    ```
  </action>
  <verify>
    <automated>test -s wiki/auto-reconnect.md && grep -c "auto-reconnect" wiki/index.md | awk '{ if ($1 >= 1) print "OK"; else exit 1 }' && grep -c "Phase 6c" wiki/log.md | awk '{ if ($1 >= 1) print "OK"; else exit 1 }'</automated>
  </verify>
  <acceptance_criteria>
    - wiki/auto-reconnect.md существует, не empty, содержит секции Summary/Контекст/Решение/Обоснование/Trade-offs.
    - wiki/index.md содержит link на auto-reconnect.md.
    - wiki/log.md содержит entry о Phase 6c completion.
    - All edits в pure markdown (никакого исполняемого кода в wiki).
  </acceptance_criteria>
  <done>Wiki sync per CLAUDE.md GSD rule. Long-term knowledge persisted.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 4 (Checkpoint): Final review — phase closure</name>
  <what-built>
    Phase 6c полностью закрыт:
    - All 5 plans (06C-01..05) executed.
    - Custom auto-reconnect machinery deleted (~570 lines).
    - Apple's on-demand + TunnelWatchdog wired.
    - 9 UAT scenarios validated.
    - Phase 1-6 regression smoke documented.
    - Planning artifacts updated (STATE/PROJECT/REQUIREMENTS/ROADMAP).
    - Wiki updated.
  </what-built>
  <how-to-verify>
    Перед closing review:

    1. Прочитать `.planning/phases/06c-on-demand-migration/06C-UAT.md` целиком. Проверить:
       - Все 9 Phase 6c сценариев имеют результат (PASS/FAIL/PARTIAL/N/A).
       - Phase 1-6 regression — все SC accounted for.
       - Декисии validated/closed.

    2. Открыть Settings → Подключение → toggle «Авто-переподключение». PASS если:
       - Default ON.
       - Toggle переключается без crash.
       - Footer text читаемый, на ru + en.

    3. Открыть `wiki/auto-reconnect.md`:
       - Понятно ли неинженеру (CLAUDE.md «non-programmer»)? Если нет — refine.
       - Линки [[xxx]] корректны.

    4. Run `swift test --package-path BBTB/Packages/AppFeatures` локально — full green.

    5. Optional: пройти UAT-Task G ещё раз (30+ min background) на physical device — подтвердить zero EXC_RESOURCE crash logs.

    PASS if all 5 confirmed.
  </how-to-verify>
  <resume-signal>
    Type one of:
    - `closed` — Phase 6c officially complete; proceed to `/gsd-discuss-phase 7`.
    - `revisions: <details>` — what to fix in 06C-UAT.md / wiki / planning artifacts.
  </resume-signal>
  <files>n/a — final closure checkpoint; no executor file changes</files>
  <action>Pause execution and wait for human reviewer signal (see what-built + how-to-verify).</action>
  <verify>Human reviewer types one of the resume-signal phrases.</verify>
  <done>Phase 6c officially closed; user proceeds to next phase planning.</done>
</task>

</tasks>

<verification>
- `cd BBTB && swift test --package-path Packages/AppFeatures` — full suite green (final regression).
- `.planning/phases/06c-on-demand-migration/06C-UAT.md` — exists, ≥ 80 lines, contains all 9 sceneries + regression table.
- `.planning/REQUIREMENTS.md` lines 109-112 — `[x]` for all 4 NET-* requirements.
- `.planning/ROADMAP.md` Phase 6c — marked Complete.
- `wiki/auto-reconnect.md` — exists.
- `wiki/index.md` — contains link to auto-reconnect.
- `wiki/log.md` — contains Phase 6c entry.
- Memory entry: planner notes for executor — после Task 4 closed, suggest user add memory: «Phase 6c — on-demand migration ✓ Complete YYYY-MM-DD; custom auto-reconnect gone; OnDemandRulesBuilder + TunnelWatchdog established».
</verification>

<success_criteria>
1. 06C-UAT.md документирует все 9 Phase 6c UAT scenarios.
2. 06C-UAT.md документирует Phase 1-6 regression smoke (carry-over).
3. NET-08, NET-09, NET-10, NET-11 marked `[x]` в REQUIREMENTS.md с UAT citation.
4. ROADMAP.md Phase 6c entry — Complete.
5. STATE.md — current_phase advanced past 06c.
6. PROJECT.md — NET requirements moved to validated (если такая структура есть).
7. wiki/auto-reconnect.md — содержит full контекст / решение / обоснование / trade-offs per CLAUDE.md «Page format».
8. wiki/index.md + wiki/log.md updated.
9. Final UAT review checkpoint passed.
10. No code changes в этой wave — только docs + planning artifacts.
11. CLAUDE.md соблюдён: документация на русском.
</success_criteria>

<output>
After completion, create `.planning/phases/06c-on-demand-migration/06C-05-SUMMARY.md`. Include:
- Files modified (planning + wiki).
- File counts: 1 new UAT report + 1 new wiki page + 3-5 modified planning artifacts + 2 modified wiki files.
- Final phase metrics:
  - Total LOC removed: ~570+.
  - Total LOC added: (count from previous summaries).
  - Net delta: negative (target).
- UAT result summary: X/9 passed.
- Reference: D-18, D-19, D-20, D-21, D-22.
- Phase 6c officially marked complete in SUMMARY.

**Important memory note**: after this plan executes, user should manually add a memory entry:
  «Phase 6c — on-demand migration ✓ Complete YYYY-MM-DD; custom auto-reconnect machinery gone; OnDemandRulesBuilder + TunnelWatchdog established; wiki/auto-reconnect.md документирует architecture decision.»

Next user step: `/gsd-discuss-phase 7` (Anti-DPI suite + WireGuard family).
</output>
