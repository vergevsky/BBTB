---
phase: 08-rules-engine-split-tunneling
plan: W0
subsystem: foundation
tags: [phase8, rules-engine, appproxy-carveout, tuist, ed25519-ssrf-helpers, wiki, deferral]

# Dependency graph
requires:
  - phase: 07-anti-dpi-suite-wireguard-family
    provides: "engine-abstraction-decision-2026 (mono-engine sing-box baseline) + DEC-06d patterns reused"
provides:
  - "Чистый Tuist Project.swift без BBTB-AppProxy-macOS target"
  - "macOS entitlements объявляют только packet-tunnel-provider capability"
  - "SubscriptionURLFetcher.isBlockedHost(_:) + normalizeHostForLog(_:) повышены до public для cross-package reuse"
  - "Долговременная decision log wiki/appproxy-deferral-2026.md с D-08/D-09 rationale"
  - "REQUIREMENTS.md RULES-11 + CORE-05 (AppProxy сторона) формально отмечены Out of Scope"
  - "Phase 8 baseline для downstream waves W1-W7 (RulesEngine package skeleton может стартовать)"
affects:
  - 08-02-PLAN.md  # W1 — RulesFetcher будет импортировать ConfigParser.SubscriptionURLFetcher.isBlockedHost
  - 08-03-PLAN.md  # W2 — RulesEngineCoordinator + SRSCacheStore — нет AppProxy конфликтов в Tuist
  - 08-06-PLAN.md  # W5 — SingBoxConfigLoader.expandConfigForTunnel — нет stale AppProxy в workspace
  - 08-08-PLAN.md  # W7 — validate-r1-r6.sh Phase 8 extension: check «D-08: No NEAppProxyProvider import» уже валиден (0 matches)

# Tech tracking
tech-stack:
  added: []   # нет новых dependencies в W0; swift-crypto придёт в W1
  patterns:
    - "Cross-package visibility promotion (internal → public) — впервые в monorepo (Risk #1 из 08-PATTERNS)"
    - "Long-term deferral wiki page жанр (4-й экземпляр: wireguard / openvpn / amneziawg / appproxy)"
    - "Tuist target deletion sequence: git rm files → edit Project.swift → tuist generate → xcodebuild smoke (8-RESEARCH Runtime State Inventory)"

key-files:
  created:
    - wiki/appproxy-deferral-2026.md  # 163 lines, D-08/D-09 long-term decision log
  modified:
    - .planning/REQUIREMENTS.md  # RULES-11 + CORE-05 strikethrough + rationale + 2026-05-15 footer
    - BBTB/Project.swift  # удалён target BBTB-AppProxy-macOS + dependency reference
    - BBTB/App/macOSApp/BBTB-macOS.entitlements  # убрано value app-proxy-provider
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift  # isBlockedHost + normalizeHostForLog public
    - wiki/index.md  # добавлен entry на appproxy-deferral-2026
    - wiki/log.md  # daily entry 2026-05-15
  deleted:
    - BBTB/App/AppProxyExtension-macOS/AppProxyProvider.swift
    - BBTB/App/AppProxyExtension-macOS/Info.plist
    - BBTB/App/AppProxyExtension-macOS/AppProxyExtension-macOS.entitlements

key-decisions:
  - "RULES-11 + Phase 8 SC #3 carve-out (D-08/D-09 per Codex thread 019e284c)"
  - "CORE-05 (AppProxyExtension target на macOS) wording adjusted к «Split-tunneling routing через sing-box route.rule_set» вместо delete (preserve coverage gate)"
  - "Visibility promotion (internal → public) для SubscriptionURLFetcher.isBlockedHost вместо extract в VPNCore/Net/HostBlocklist.swift (Risk #1 — простота для v0.8, refactor если потребуется third consumer)"
  - "Apple Developer Portal capability disable — manual step пользователя, не code change (documented в Plan 08-01 user_setup)"
  - "ROADMAP.md уже был обновлён планировщиком до старта W0 — в worktree mode shared-file правки не дублируются (оркестратор подтверждает после merge)"

patterns-established:
  - "Tuist target deletion: git rm directory → edit Project.swift → tuist generate --no-open → xcodebuild -list smoke → commit"
  - "Wiki long-term deferral log: 4th экземпляр, формат стабилизировался (см. wiki/appproxy-deferral-2026.md как канонический пример)"
  - "Cross-package visibility promotion с inline doc-comment маркером (Phase 8 W0 — promoted public для reuse из RulesEngine.RulesFetcher) — pattern для будущих visibility expansions"

requirements-completed: [RULES-11]  # carved-out: RULES-11 формально отмечен Out of Scope в REQUIREMENTS.md + ROADMAP.md → frontmatter mvp_slice исполнен

# Metrics
duration: 25min
completed: 2026-05-15
---

# Phase 8 Plan W0: Foundation (RULES-11 carve-out + AppProxyExtension-macOS deletion + isBlockedHost public + wiki long-term log) Summary

**RULES-11 + Phase 8 SC #3 формально вынесены в Out of Scope v0.10+; «зомби»-target BBTB-AppProxy-macOS удалён из Tuist/файловой системы/entitlements; SSRF helper isBlockedHost повышен до public для будущего reuse из RulesEngine package; долговременная decision-log страница wiki/appproxy-deferral-2026.md создана.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-05-15 (Plan 08-01 spawn)
- **Completed:** 2026-05-14T22:36:57Z (commit `fc7b095`)
- **Tasks:** 5/5 completed (W0.1 — W0.5 + 1 follow-up commit для case-mismatched git add)
- **Files modified:** 6 (.planning/REQUIREMENTS.md, BBTB/Project.swift, BBTB/App/macOSApp/BBTB-macOS.entitlements, BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift, wiki/index.md, wiki/log.md)
- **Files created:** 1 (wiki/appproxy-deferral-2026.md)
- **Files deleted:** 3 (AppProxyProvider.swift, Info.plist, AppProxyExtension-macOS.entitlements)

## Accomplishments

- **AppProxyExtension-macOS «зомби»-target полностью устранён из codebase** — 3 физических файла удалены (`git rm -r`), Tuist Project.swift очищен от target block + dependency reference, macOS entitlements объявляют только `packet-tunnel-provider` capability. `tuist generate` проходит за 12.1s без AppProxy schemes (`xcodebuild -list` подтверждает).
- **SSRF SSRF helpers повышены до public** — `SubscriptionURLFetcher.isBlockedHost(_:)` и `normalizeHostForLog(_:)` стали `public` с inline doc-comment маркером для будущего reuse из `RulesEngine.RulesFetcher` (8-RESEARCH § Validation Architecture Risk #1). 228 ConfigParser тестов PASS без regression.
- **Долговременная decision-log страница `wiki/appproxy-deferral-2026.md` создана** — 163 строки, формат wikipedia/deferral-pages (4-й экземпляр после wireguard/openvpn/amneziawg). Покрывает: L3 vs L4 архитектурный mismatch, NETunnelProviderManager и NEAppProxyProviderManager mutual exclusivity, три рассмотренных моста (SOCKS5 / multi-instance / plain TCP) с обоснованием почему каждый ломает invariants, workaround через `never_through_vpn`, условие возврата v0.10+, cost estimate, Apple HIG note про signing_identifier vs bundle IDs.
- **REQUIREMENTS.md amendment** — RULES-11 + CORE-05 strikethrough с детальным rationale block + 2026-05-15 footer; preserve coverage gate (не удаляем требования, помечаем как Out of Scope чтобы downstream traceability не разрушился).

## Task Commits

Each task was committed atomically:

1. **Task W0.1: Promote SubscriptionURLFetcher SSRF helpers to public** — `2f103cb` (feat)
2. **Task W0.2: Delete AppProxyExtension-macOS code + entitlements (D-09)** — `c38033e` (chore)
3. **Task W0.3: Remove BBTB-AppProxy-macOS target from Tuist manifest + regenerate** — `f71a868` (chore)
4. **Task W0.4: Update REQUIREMENTS.md (RULES-11 → Out of Scope)** — `0265b82` (docs)
5. **Task W0.5: Create wiki/appproxy-deferral-2026.md long-term decision log** — `eb5a700` (docs) + `fc7b095` (docs follow-up, см. Deviations)

## Files Created/Modified

### Created (1)

- `wiki/appproxy-deferral-2026.md` — 163 lines, long-term decision log для D-08/D-09 carve-out; ссылается на Codex thread `019e284c-4bf6-7f91-ada7-7e679692b5fb`; содержит rationale (L3 vs L4 mismatch + manager exclusivity + три моста), workaround description, условие возврата в v0.10+ + cost estimate.

### Modified (6)

- `.planning/REQUIREMENTS.md` — RULES-11 row → strikethrough + детальный rationale; CORE-05 wording → «Split-tunneling routing через sing-box route.rule_set»; footer обновлён датой 2026-05-15 + сохранена предыдущая Phase 6e строка.
- `BBTB/Project.swift` — удалён блок `.target(name: "BBTB-AppProxy-macOS", ...)` + строка `.target(name: "BBTB-AppProxy-macOS"),` в `BBTB-macOS` dependencies. `tuist generate` подтвердил clean (12.1s).
- `BBTB/App/macOSApp/BBTB-macOS.entitlements` — массив `com.apple.developer.networking.networkextension` теперь содержит только `<string>packet-tunnel-provider</string>` (без `app-proxy-provider`).
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` — `isBlockedHost(_:)` + `normalizeHostForLog(_:)` повышены с `internal` до `public`, добавлен doc-comment маркер «Phase 8 W0 — promoted public для reuse из RulesEngine.RulesFetcher».
- `wiki/index.md` — добавлен entry на `appproxy-deferral-2026` в Anti-DPI секцию между `amneziawg-deferral-2026` и `engine-abstraction-decision-2026`.
- `wiki/log.md` — append daily entry 2026-05-15 (Phase 8 W0) с описанием всех изменений + 5 ключевых решений для будущих фаз.

### Deleted (3)

- `BBTB/App/AppProxyExtension-macOS/AppProxyProvider.swift` (15 lines stub — `completionHandler(NSError(... "Phase 8"))`)
- `BBTB/App/AppProxyExtension-macOS/Info.plist` (29 lines — `com.apple.networkextension.app-proxy` extension point + principal class)
- `BBTB/App/AppProxyExtension-macOS/AppProxyExtension-macOS.entitlements` (18 lines — `app-proxy-provider` + App Group + sandbox)

## Decisions Made

1. **Visibility promotion vs shared module extraction (W0.1):** Выбрано `internal → public` промоушн вместо extract в `Packages/VPNCore/Sources/VPNCore/Net/HostBlocklist.swift` — для v0.8 простота важнее идеальной модульности, refactor можно сделать в Phase 11/12 если потребуется third consumer. Документировано в 08-PATTERNS Risk #1 и теперь в SUMMARY.

2. **`git rm -r` vs `mv → trash` для AppProxyExtension директории (W0.2):** Выбран `git rm -r` (полное удаление, не «backup в trash»). Rationale: код был стартовым placeholder'ом (Phase 1 W3), никакой history value, восстановление возможно через `git checkout <hash> -- BBTB/App/AppProxyExtension-macOS/` если придётся возвращаться в v0.10+.

3. **Tuist regenerate _в той же задаче_ что и delete (W0.3) vs отдельный шаг:** Выбрано inline (`cd BBTB && tuist generate --no-open` сразу после edit Project.swift). Rationale: атомарность W0.3 — после этого commit'а workspace consistent; если оркестратор остановится, нет orphan state «Tuist говорит target есть, файлов нет».

4. **Preserve RULES-11 + CORE-05 в REQUIREMENTS.md (strikethrough) vs delete (W0.4):** Выбран strikethrough (Phase 7 PROTO-06/07/09 pattern). Rationale: coverage gate (REQUIREMENTS.md содержит ~140 v1 requirements, все mapped) — удаление сломает downstream traceability. Strikethrough с rationale block сохраняет audit trail.

5. **Apple Developer Portal capability disable — manual step user'а, не auto (frontmatter `user_setup`):** Code-level entitlement removal достаточен для shipped binary, но Apple Portal capability flag — meta-state Apple-side, не controllable через repo. Документирован в Plan 08-01 frontmatter для пользователя.

## Deviations from Plan

### Operational Deviations (Rule 3 — blocking issues, fixed inline)

**1. [Rule 3 - Blocking] Libbox xcframework missing in worktree environment**

- **Found during:** Task W0.1 verify step (`cd BBTB/Packages/ConfigParser && swift test`)
- **Issue:** `BBTB/Vendored/libbox.xcframework` отсутствует в worktree (только `.gitkeep` + README); `BBTB/Vendored/` находится в `.gitignore`, поэтому Claude Code worktree spawning не копирует библиотеку из main репо. Swift test падал с `error: local binary target 'Libbox' at '...libbox.xcframework' does not contain a binary artifact`.
- **Fix:** Создан symlink `BBTB/Vendored/libbox.xcframework -> /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework`. Symlink не tracked (в .gitignore), не модифицирует main репо.
- **Files modified:** Только worktree filesystem (symlink), ничего в git.
- **Verification:** После symlink `swift test` PASS (228 tests / 0 failures / 0.181s).
- **Committed in:** Не закоммичено (symlink не tracked).
- **Impact on plan:** Никакого. Worktree-specific environment quirk, не блокирует downstream waves (которые в main репо имеют polный libbox).

### Order-of-operations Deviation (W0.5 follow-up commit)

**2. Case-sensitivity quirk with `git add wiki/` vs `Wiki/`**

- **Found during:** Task W0.5 commit step (`eb5a700`)
- **Issue:** macOS APFS case-insensitive filesystem accepted `git add wiki/index.md wiki/log.md`, но git internally tracks директорию как `Wiki/` (с заглавной W — историческое наследие проекта). В результате `eb5a700` commit зацепил только новый `Wiki/appproxy-deferral-2026.md`, но НЕ обновления к `Wiki/index.md` и `Wiki/log.md`.
- **Fix:** Дополнительный commit `fc7b095` с правильным `git add Wiki/index.md Wiki/log.md`. Task W0.5 теперь покрыт двумя commit'ами (eb5a700 — wiki page; fc7b095 — index + log wiring).
- **Impact on plan:** Никакого. Финальное состояние identical плану — все acceptance criteria выполнены. Просто atomic boundary стало 2 commit'а вместо 1.

### ROADMAP.md state at plan start

**3. ROADMAP.md уже был обновлён планировщиком до старта Plan 08-01**

- **Found during:** Task W0.4 (REQUIREMENTS+ROADMAP edit)
- **Issue:** Plan W0.4 frontmatter перечислял `ROADMAP.md` среди `files_modified`, но при чтении ROADMAP.md я обнаружил что Phase 8 entry уже содержит `~~RULES-11~~ (Out of Scope per D-08)`, `~~На macOS AppProxyProvider...~~ → **Out of Scope v0.8 per D-08/D-09 (2026-05-15)**` + ссылку на wiki/appproxy-deferral-2026.md.
- **Resolution:** Принял current state как «планировщик сделал ROADMAP.md правки в фазе планирования» + worktree spec `IMPORTANT: Do NOT modify STATE.md or ROADMAP.md. orchestrator commits them after merge` — нечего добавлять в ROADMAP.md из W0. REQUIREMENTS.md обновлён как требуется (мой commit `0265b82`). Все acceptance grep'ы проходят (см. Self-Check ниже).
- **Impact:** Sequential consistency между worktree agents в этой волне сохранена.

## Tests Run

- **ConfigParser** (W0.1 verify): `cd BBTB/Packages/ConfigParser && swift test` → 228 tests / 0 failures / 0.181s.
- **Tuist generate** (W0.3 verify): `cd BBTB && tuist generate --no-open` → Success (12.1s).
- **Xcodebuild smoke** (W0.3 verify): `xcodebuild -workspace BBTB/BBTB.xcworkspace -list` → schemes: BBTB, BBTB-macOS, BBTB-Tunnel-iOS, BBTB-Tunnel-macOS, BBTB-Workspace (no AppProxy schemes). `xcodebuild -scheme BBTB-macOS -showBuildSettings` → PRODUCT_NAME = BBTB_macOS (Tuist sanitizes hyphens in product name — expected behavior).
- **Source greps** (overall acceptance):
  - `grep -c BBTB-AppProxy-macOS BBTB/Project.swift` → 0
  - `grep -c app-proxy-provider BBTB/App/macOSApp/BBTB-macOS.entitlements` → 0
  - `grep -rE 'NEAppProxyProvider|app-proxy-provider' BBTB/App/macOSApp/ BBTB/Packages/AppFeatures/Sources/` → 0 matches
  - `grep -c 'public static func (isBlockedHost|normalizeHostForLog)' BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` → 2
  - `test ! -d BBTB/App/AppProxyExtension-macOS/` → OK (directory removed)

## Open Items (carry-forward в downstream waves)

- **W7 task: `validate-r1-r6.sh` extension** — добавить check «D-08: No NEAppProxyProvider import in main app sources» (`! grep -rE 'NEAppProxyProvider|app-proxy-provider' BBTB/App/macOSApp/ BBTB/Packages/AppFeatures/Sources/`). После W0 этот check уже валиден (0 matches), W7 формализует его в shell gate.
- **User manual step:** Apple Developer Portal capability disable («App Proxy Provider» снять для `app.bbtb.client.macos` App ID). Документировано в Plan 08-01 frontmatter `user_setup`. Без этого shipped binary не сломается (entitlement removed code-side), но Portal consistency желательно для будущей TestFlight upload.
- **Symlink workaround (worktree-only):** Перед swift test в worktree environment может потребоваться `ln -s /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework BBTB/Vendored/libbox.xcframework`. Downstream waves в main репо этого не требуют.

## Self-Check: PASSED

Verified after writing this SUMMARY.md:

- **Created files exist:**
  - `wiki/appproxy-deferral-2026.md` → FOUND (163 lines)
- **Modified files state:**
  - `.planning/REQUIREMENTS.md` contains `~~**RULES-11**: AppProxyProvider таргет на macOS` → grep returns 1 ✓
  - `BBTB/Project.swift` does NOT contain `BBTB-AppProxy-macOS` → grep returns 0 ✓
  - `BBTB/App/macOSApp/BBTB-macOS.entitlements` does NOT contain `app-proxy-provider` → grep returns 0 ✓
  - `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` contains `public static func isBlockedHost` AND `public static func normalizeHostForLog` → grep returns 2 ✓
- **Deleted files state:**
  - `BBTB/App/AppProxyExtension-macOS/` → FOUND (directory removed)
- **Commits exist (verified via `git log b0150d4..HEAD`):**
  - 2f103cb (W0.1) → FOUND
  - c38033e (W0.2) → FOUND
  - f71a868 (W0.3) → FOUND
  - 0265b82 (W0.4) → FOUND
  - eb5a700 (W0.5a) → FOUND
  - fc7b095 (W0.5b follow-up) → FOUND
- **Phase 8 baseline ready для W1:** ✓ (clean Tuist manifest + public SSRF helper + documented carve-out + wiki long-term log)

Phase 8 Plan W0 — COMPLETE.
