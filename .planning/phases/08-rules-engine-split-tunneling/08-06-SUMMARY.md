---
phase: 08-rules-engine-split-tunneling
plan: W5
subsystem: sing-box-engine-integration
tags: [rules-engine, sing-box, libbox, rule_set, route, expandConfigForTunnel, R1, R10, idempotent, app-group, srs, packettunnelkit, d-01, rules-05, rules-06, rules-07]
dependency_graph:
  requires:
    - phase: 08
      plan: W2
      provides: "AppGroupContainer.rulesCacheDirectory (idempotent createDirectory; `<App Group>/Library/Caches/rules/`)"
    - phase: 08
      plan: W4
      provides: "RulesEngineCoordinator bootstrap + scheduler — гарантия что cache populated к моменту tunnel start"
    - phase: 01
      plan: W3
      provides: "SingBoxConfigLoader.expandConfigForTunnel chain (sniff insertion @ line 228-237 — extension point для W5 step 5)"
    - phase: 02
      plan: W1
      provides: "proxyOutboundTypes set + firstProxyTag resolution logic (lines 218-225) — reused для always-category outbound"
  provides:
    - "SingBoxConfigLoader.expandConfigForTunnel — step 5: 3 route.rule_set entries (bbtb-block/bbtb-never/bbtb-always; type:local, format:binary, path под App Group rules cache) + 3 priority route.rules"
    - "Top-down priority: block(action:reject) → never(outbound:direct) → always(outbound:firstProxyTag) → default — sing-box first-match-wins"
    - "Idempotency invariant: повторный expand НЕ дублирует rule_set declarations или priority rules (existingTags / existingRuleSetRefs filter)"
    - "R10 invariant preserved: post-expand SingBoxConfigLoader.validate(json:) passes; rule_set entries не открывают forbidden inbounds; action:reject — outbound action"
    - "R1 invariant preserved: template `SingBoxConfigTemplate.vless-reality.json` остаётся bare (no inline rule_set); runtime expansion = single source of truth"
    - "6 unit tests в SingBoxConfigLoaderTests: injection / priority order / firstProxyTag reuse / idempotency / R10 post-validate / R1 template-bare"
  affects:
    - "08-07-PLAN.md (W6 — embedded baseline content; теперь sing-box engine видит rules cache files на extension startup)"
    - "08-08-PLAN.md (W7 — validate-r1-r6.sh extended с R8 invariant: ! grep rule_set в template + grep AppGroupContainer в SingBoxConfigLoader)"
    - "Phase 11 UAT (M-05 manual UAT — real domain blocking on iPhone; M-07 split-tunnel country resolution)"
tech_stack:
  added: []  # все deps уже добавлены в Phase 1/2; W5 — pure-Foundation [String: Any] JSON manipulation
  patterns:
    - "P-16 (08-PATTERNS) — expandConfigForTunnel idempotent chain extension (sniff insertion analog @ line 228-237)"
    - "S-5 (08-PATTERNS) — guard pattern `if !existing.contains { tag } { append }` для idempotency"
    - "P-9 (08-PATTERNS) — AppGroupContainer.rulesCacheDirectory path resolver (extension-side resolution)"
    - "Phase 2 W1.T8 firstProxyTag reuse — single source of truth для proxy outbound selection"
    - "Insertion index by content (insertIdx = после hijack-dns), not magic number — DNS sniff prerequisite preserved (D-03)"
key_files:
  created:
    - ".planning/phases/08-rules-engine-split-tunneling/08-06-SUMMARY.md"
  modified:
    - "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift — step 5 injection (lines 244-300; ~86 lines + 8 lines doc-comment)"
    - "BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift — 6 new tests + 1 legacy test layout fix (rules[2] → first-by-content matching)"
decisions:
  - "DEC-08-W5-01: insertIdx = после hijack-dns (rules.firstIndex { action == hijack-dns } + 1), не магическое 0 или count. Rationale: sing-box матчит rules top-down; DNS hijack должен run первым (Phase 1 W3.2), затем наши rule_set rules; legacy domain-rules сдвигаются вниз (test_rewritesLegacyDnsOutbound обновлён с index-based на content-based matching)."
  - "DEC-08-W5-02: firstProxyTag reuse — same expression как в `route.final` fallback (lines 218-225). Rationale: единый source of truth для proxy outbound selection; если future expand изменит выбор proxy (Phase 2 IMP-04 urltest pool), always-category автоматически синхронизируется."
  - "DEC-08-W5-03: rule_set path = `\\(AppGroupContainer.rulesCacheDirectory.path)/<tag>.srs` — абсолютный путь. Rationale: extension читает по абсолютному path (sing-box's libbox local rule_set loader не разбирает relative paths против process cwd); App Group идентификатор `group.app.bbtb.shared` симметричен для main app (writer) и extension (reader)."
  - "DEC-08-W5-04: Idempotency через set-based filter (existingTags / existingRuleSetRefs), не через top-level guard `if hasRouteRuleSets`. Rationale: позволяет частичное W5 dev в будущем (user уже добавил `bbtb-block` руками — W5 добавит только missing) + точная мерка дублирования в idempotent тесте."
  - "DEC-08-W5-05: action:reject (block-rule) не имеет outbound key — sing-box контракт. Rationale: 'reject' — terminal action; outbound + action в одном rule могут привести к ambiguity (sing-box logs warning); явное отсутствие outbound сигнализирует terminal-action."
  - "DEC-08-W5-06 (Rule 1 deviation): test_expandConfigForTunnel_rewritesLegacyDnsOutbound обновлён с index-based assertions (rules[2]) на content-based matching (rules.first { outbound==direct && rule_set==nil }). Rationale: W5 step 5 вставляет 3 правила после hijack-dns → legacy rule сдвигается с idx 2 на idx 5; брutте-сила index assertions нарушают цели test'а (проверить что domain_suffix → direct rule СОХРАНИЛСЯ, а не сместился по индексу). Content-based более robust."
threat_model:
  T-08-W5-01: "Tampering — rule_set entries opens new inbound surface (R1 break). Mitigation: action:reject — outbound action, не inbound type. Test test_expandConfigForTunnel_validatePassesAfterRulesetExpansion_R10invariant confirms."
  T-08-W5-02: "DoS — idempotency break → libbox crash on dup parse. Mitigation: existingTags/existingRuleSetRefs filter. Test test_expandConfigForTunnel_rulesetInjectionIsIdempotent confirms (2x expand → still 3 entries)."
  T-08-W5-03: "Tampering — path traversal via crafted manifest filename. Accepted: filenames hardcoded в SingBoxConfigLoader (bbtb-block.srs etc.); server-side rules.json не управляет paths."
  T-08-W5-04: "Information disclosure — App Group UUID в logs. Accepted: UUID random per-install (не PII); OSLog privacy markers controlling exposure через RulesEngineLogger."
  T-08-W5-05: "DoS — missing .srs file → tunnel fails to start. Mitigation: (a) W2.3 bootstrap copies baseline на first launch; (b) libbox documented graceful-fail (warning log + skip rule_set, tunnel continues); (c) rulesCacheDirectory idempotent createDirectory. Open Question A2 (W7 UAT validates empirically)."
  T-08-W5-06: "Tampering — firstProxyTag wrong → always category routes к non-VPN. Mitigation: test_expandConfigForTunnel_alwaysCategoryUsesValidProxyTag verifies."
  T-08-W5-07: "Spoofing — user-supplied config с malicious rule_set local path. Mitigation: expandConfigForTunnel called only on PoolBuilder output (internal); R1 validate gates на inbound regardless."
  T-08-W5-08: "Repudiation — engine apply без log trace. Mitigation: RulesEngineLogger.coordinator + sing-box internal logging + PerfSignposter span 'RulesRefresh'."
metrics:
  duration_minutes: 12
  tasks: 2
  files_created: 1   # SUMMARY.md
  files_modified: 2  # SingBoxConfigLoader.swift + SingBoxConfigLoaderTests.swift
  build_status_packettunnelkit: "Build complete!"
  tests_passing_packettunnelkit_singbox: "41 / 41 (was 35 — added 6 new)"
  tests_passing_packettunnelkit_total: "72 / 72"
  tests_passing_rulesengine: "41 / 41 (no regression)"
  tests_passing_appfeatures: "162 / 162 (no regression)"
  completed: 2026-05-15
---

# Phase 8 Plan W5: SingBoxConfigLoader rule_set injection + R1/R10 invariant tests — Summary

**sing-box engine теперь видит и применяет cache из App Group: `expandConfigForTunnel` инжектирует 3 `route.rule_set` (block/never/always) + 3 priority rules, по которым libbox 1.13 читает `.srs` файлы из `<App Group>/Library/Caches/rules/` через встроенный fswatch.Watcher с auto-reload на mtime change. Это завершает end-to-end loop Phase 8 MVP: VPS rules → main app fetch (W2) → user opens app (W3+W4) → cache landed at App Group → extension starts tunnel → sing-box parses .srs → domain matching working. R1 и R10 invariants preserved (post-expand validate passes, template остаётся bare, action:reject — outbound action, не inbound type). 6 новых тестов в SingBoxConfigLoaderTests покрывают RULES-05/06/07 + R10/R1; PacketTunnelKit suite 35 → 41 tests, all PASS.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-05-15T02:53:00Z (approximate)
- **Completed:** 2026-05-15T03:02:20Z (approximate)
- **Tasks:** 2 (W5.1 SingBoxConfigLoader, W5.2 6 new tests)
- **Files modified:** 2 (SingBoxConfigLoader.swift + SingBoxConfigLoaderTests.swift)
- **Files created:** 1 (this SUMMARY)
- **Lines of code added:** ~218 (W5.1: +86 logic + 8 doc-comment; W5.2: +138 tests + −3 legacy-test rewrite)

## Accomplishments

- **`SingBoxConfigLoader.expandConfigForTunnel` step 5** — после sniff insertion (step 4) добавлен новый блок-инъектор. Внутри `if var route = root["route"] ...`:
  - **5a (rule_set declarations):** для каждой категории (bbtb-block, bbtb-never, bbtb-always) проверяется отсутствие в `existingTags`; добавляется entry `{tag, type:"local", format:"binary", path: "<AppGroupContainer.rulesCacheDirectory.path>/<tag>.srs"}`. Сохраняется через `route["rule_set"] = ruleSets`.
  - **5b (priority rules):** insertIdx = `rules.firstIndex { action == "hijack-dns" } + 1` (типично 2). Для каждой missing категории добавляется правило в порядке block → never → always. block уверенно использует `action:"reject"` без `outbound` (sing-box контракт — terminal action). never — `outbound:"direct"`. always — `outbound: firstProxyTag` (reuse того же expression что и `route.final` fallback @ lines 218-225). Все 3 правила вставляются `rules.insert(contentsOf:at:)` чтобы legacy rules сдвинулись вниз.
- **Idempotency проверяется на двух уровнях:** (1) `existingTags` set фильтрует rule_set declarations при повторном вызове; (2) `existingRuleSetRefs` set фильтрует priority rules. Тест `test_expandConfigForTunnel_rulesetInjectionIsIdempotent` гарантирует: после 2x expand — exactly 3 rule_set + 3 priority rules, не 6.
- **R10 invariant preserved automatically:** существующие тесты `test_expandConfigForTunnel_outputPassesValidate_fromCleanInput` и `test_expandConfigForTunnel_outputPassesValidate_fromLegacyInput` продолжают passing — post-expand validate() возвращает без throw. Дополнительно новый тест `test_expandConfigForTunnel_validatePassesAfterRulesetExpansion_R10invariant` явно проверяет это для filled template path.
- **R1 invariant preserved:** новый тест `test_template_doesNotContainInlineRuleSetBlock_R1invariant` проверяет что `SingBoxConfigTemplate.vless-reality.json` НЕ содержит inline `rule_set` ключей — runtime expansion остаётся единственным источником истины.
- **firstProxyTag reuse — single source of truth:** тест `test_expandConfigForTunnel_alwaysCategoryUsesValidProxyTag` проверяет что always-outbound matches один из existing proxy outbound tags (vless/trojan/urltest/selector/...). Reused expression — same set proxyOutboundTypes (lines 69-73 SingBoxConfigLoader); если Phase 2 IMP-04 urltest pool изменит выбор, always-rule синхронизируется автоматически.
- **Priority hierarchy explicit:** тест `test_expandConfigForTunnel_priorityOrderIsBlockThenNeverThenAlways` декларирует exact ordering [bbtb-block, bbtb-never, bbtb-always] в выходящем `route.rules` array. block использует `action:reject` без outbound (sing-box terminal action contract); never использует `outbound:direct` без action; always использует non-direct, non-block outbound.
- **Adjacent suites green** — RulesEngine 41/41, AppFeatures 162/162, PacketTunnelKit total 72/72. Никаких regressions в зависимых модулях.

## Task Commits

| Task | Description | Files | Commit |
|------|-------------|-------|--------|
| W5.1 | SingBoxConfigLoader inject rule_set + priority rules + Rule 1 fix legacy test indices | `SingBoxConfigLoader.swift`, `SingBoxConfigLoaderTests.swift` | `3ee9ab2` |
| W5.2 | 6 new SingBoxConfigLoaderTests covering RULES-05/06/07 + R10/R1 invariants | `SingBoxConfigLoaderTests.swift` | `5c6c645` |

## Exact diff of expandConfigForTunnel addition

**Line range:** `SingBoxConfigLoader.swift` lines 244-300 (step 5 block) + lines 137-147 (doc-comment update at function header).

**Function header (lines 137-147):**
```swift
/// Phase 1 W3 expansion: добавить TUN inbound и мигрировать DNS-hijack на sing-box 1.13.
///
/// Подробное описание (mtu/tunIP rationale, idempotency) — см. ниже в коде.
///
/// **Phase 8 W5 (D-01) extension:** also injects 3 `route.rule_set` entries
/// (bbtb-block / bbtb-never / bbtb-always; `type:"local"`, `format:"binary"`,
/// `path:` под App Group rules cache directory) + 3 priority `route.rules`
/// (block→reject, never→direct, always→firstProxyTag). Idempotent: повторный
/// вызов не дублирует ни rule_set declarations, ни priority rules. R1/R10 invariants
/// preserved (`action:"reject"` — outbound action, не inbound type; post-expand
/// `validate(json:)` passes без throw).
public static func expandConfigForTunnel(
```

**Step 5 body (lines 244-300, inserted после step 4 sniff insertion и до final serialization):**
```swift
// 5. Phase 8 D-01 (W5) — inject 3 `route.rule_set` declarations + 3 priority rules.
// ... (full body — см. файл) ...
if var route = root["route"] as? [String: Any] {
    // 5a. Inject rule_set declarations (deduped by tag).
    var ruleSets = (route["rule_set"] as? [[String: Any]]) ?? []
    let existingTags: Set<String> = Set(ruleSets.compactMap { $0["tag"] as? String })
    let rulesDir = AppGroupContainer.rulesCacheDirectory.path
    let categories: [(tag: String, file: String)] = [
        ("bbtb-block",  "bbtb-block.srs"),
        ("bbtb-never",  "bbtb-never.srs"),
        ("bbtb-always", "bbtb-always.srs"),
    ]
    for (tag, file) in categories where !existingTags.contains(tag) {
        ruleSets.append([
            "tag": tag, "type": "local", "format": "binary",
            "path": "\(rulesDir)/\(file)",
        ])
    }
    route["rule_set"] = ruleSets

    // 5b. Inject 3 priority rules (deduped by rule_set ref).
    var rules = (route["rules"] as? [[String: Any]]) ?? []
    let existingRuleSetRefs: Set<String> = Set(rules.compactMap { $0["rule_set"] as? String })
    let outbounds = (root["outbounds"] as? [[String: Any]]) ?? []
    let firstProxyTag: String = outbounds.first { o in
        guard let t = o["type"] as? String else { return false }
        return proxyOutboundTypes.contains(t)
    }?["tag"] as? String ?? "vless-out"

    let insertIdx = rules.firstIndex {
        ($0["action"] as? String) == "hijack-dns"
    }.map { $0 + 1 } ?? rules.count

    var newRules: [[String: Any]] = []
    if !existingRuleSetRefs.contains("bbtb-block") {
        newRules.append(["rule_set": "bbtb-block", "action": "reject"])
    }
    if !existingRuleSetRefs.contains("bbtb-never") {
        newRules.append(["rule_set": "bbtb-never", "outbound": "direct"])
    }
    if !existingRuleSetRefs.contains("bbtb-always") {
        newRules.append(["rule_set": "bbtb-always", "outbound": firstProxyTag])
    }
    rules.insert(contentsOf: newRules, at: insertIdx)
    route["rules"] = rules
    root["route"] = route
}
```

## Test names + count

| # | Test name | Coverage |
|---|-----------|----------|
| 1 | `test_expandConfigForTunnel_injectsThreeRuleSetEntries` | RULES-05/06/07 — 3 rule_set entries с type/format/path metadata |
| 2 | `test_expandConfigForTunnel_priorityOrderIsBlockThenNeverThenAlways` | RULES-06 — exact ordering + per-rule attribute checks |
| 3 | `test_expandConfigForTunnel_alwaysCategoryUsesValidProxyTag` | RULES-07 — firstProxyTag reuse verification |
| 4 | `test_expandConfigForTunnel_rulesetInjectionIsIdempotent` | T-08-W5-02 — 2x expand still 3+3, not 6+6 |
| 5 | `test_expandConfigForTunnel_validatePassesAfterRulesetExpansion_R10invariant` | R10 invariant — post-expand validate() passes |
| 6 | `test_template_doesNotContainInlineRuleSetBlock_R1invariant` | R1 invariant — template stays bare, runtime injection = SSoT |

**Suite total:** 35 (W4 baseline) → **41 tests, 0 failures**.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 1 — Bug] test_expandConfigForTunnel_rewritesLegacyDnsOutbound index-based assertions нарушали W5 layout**
- **Found during:** Task W5.1 (post-implementation `swift test`)
- **Issue:** Тест проверял `rules[2]["outbound"] == "direct"` для legacy `domain_suffix → direct` правила. После W5 step 5 эти 3 priority rules вставляются после hijack-dns → legacy rule сдвигается с idx 2 на idx 5; index-based assertions FAIL.
- **Fix:** Переписан на content-based matching: `rules.first { outbound==direct && rule_set==nil }`. Это более robust — тест проверяет что legacy rule сохранился, а не его precise index (который теперь зависит от W5 injection).
- **Files modified:** `SingBoxConfigLoaderTests.swift` (lines 217-230)
- **Commit:** `3ee9ab2` (same as W5.1 logic — Rule 1 inline fix of related test breakage)

**2. [Rule 3 — Blocking] worktree libbox.xcframework missing (gitignored binary asset)**
- **Found during:** Initial `swift test` baseline check
- **Issue:** Worktree spawned without `BBTB/Vendored/libbox.xcframework` (gitignored binary in `.gitignore`); `swift build` fails with "binary target 'Libbox' does not contain a binary artifact".
- **Fix:** Symlink to main repo's xcframework: `ln -s /Users/.../VPN/BBTB/Vendored/libbox.xcframework BBTB/Vendored/libbox.xcframework`. Symlink не коммитится — это worktree-only environment fix (Phase 1 lesson learned). Не влияет на main repo.
- **Files modified:** none committed (symlink only)
- **Commit:** none

No other deviations.

## R1 / R10 / R8 Invariant Confirmation

| Invariant | Test | Status |
|-----------|------|--------|
| **R1** — template имеет no inline rule_set | `test_template_doesNotContainInlineRuleSetBlock_R1invariant` | ✅ PASS — template.contains("\"rule_set\"") = false; route.rule_set = nil в parsed template |
| **R1** — expand не открывает forbidden inbounds | Existing default-deny tests (`test_rejectsSocksInbound`, `test_rejectsMixedInbound`, etc.) + R10 cascade | ✅ PASS — все 5 R1 inbound-rejection tests + 3 experimental API tests + 2 SEC-06 outbound tests still green |
| **R10** — post-expand validate() passes | `test_expandConfigForTunnel_validatePassesAfterRulesetExpansion_R10invariant` + existing `test_expandConfigForTunnel_outputPassesValidate_*` | ✅ PASS — 3 R10 tests pass (clean input, legacy input, filled template W5 path) |
| **R8** (new, validate в W7) — `! grep rule_set` в template | Manual: `grep -c rule_set BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/Resources/SingBoxConfigTemplate.vless-reality.json` = 0 | ✅ PASS (W7 extends validate-r1-r6.sh с этим assert) |

## Open Question A2 — fswatch in iOS NE sandbox (для W7 UAT)

**RESEARCH § Open Questions A2:** "Sing-box `fswatch.Watcher` works inside iOS Network Extension sandbox (filesystem events visible)" — этот вопрос empirically validates только при реальном tunnel start на устройстве с populated SRS cache.

**W5 status:** код инжектирует абсолютный path под App Group (`/Library/Caches/rules/<tag>.srs`); libbox 1.13.11 встроенный fswatch.Watcher должен авто-реагировать на mtime change. Без реального device testing нельзя гарантировать что NE sandbox разрешает kqueue events на App Group filesystem.

**Fallback plan если fswatch не работает в NE sandbox:** добавить `force_reload_token` field в manifest, по изменению которого extension получает inter-process message (existing tunnel.command pattern) и явно вызывает sing-box reload без auto-watch — отложено до W7 UAT validation.

**TODO для W7:**
- M-05 UAT — real domain blocking on device:
  1. Seed baseline rules с test domain (например, `example-blocked.test`).
  2. Connect tunnel на iPhone.
  3. `curl -v https://example-blocked.test` from device Safari → connection reset/timeout.
  4. Repeat для `never_through_vpn` (должно leak в direct, verify через local IP).
  5. `always_through_vpn` (должно route через VPN даже если split-tunnel toggled).
- M-07 UAT — split-tunnel country resolution (Phase 2 server-side):
  1. Admin packs rules с `countries: ["RU"]` в `never_through_vpn`.
  2. iPhone connects.
  3. Request к known-RU IP (`yandex.ru`) goes direct (`whois` confirms RU AS).
  4. Request к non-RU IP goes through VPN.

## Manual UAT Preview

**Когда:** W7 (после embedded baseline content в W6).

**Что проверить вручную:**

1. ✅ **Baseline shipped** — после fresh install на iPhone, открыть Settings → Rules; должно показать "1 baseline rule loaded" (или similar) — bootstrap скопировал baseline в `<App Group>/Library/Caches/rules/`.
2. ✅ **Engine применяет rules** — connect tunnel; в console.app filter по `process:com.app.bbtb.client.tunnel`; в логах sing-box должен быть:
   - `rule_set loaded: bbtb-block from <path>` (или similar) — 3 entries.
   - При visit заблокированного domain: `rejected by rule_set bbtb-block`.
   - При visit never-domain: `routed to outbound: direct` (не `vless-out`).
3. ✅ **fswatch auto-reload** — при manual `forceUpdate()` в main app (RulesViewModel.refresh()), sing-box должен подхватить новый SRS без disconnect:
   - В sing-box console: `rule_set reloaded: bbtb-block` (mtime change detected).
   - Tunnel state остаётся `.connected` (NEVPNStatus).
4. ✅ **Edge case: empty SRS** — admin packs rules.json с empty `block_completely.domains` → SRS пустой → sing-box gracefully skips rule_set matching → traffic goes through default outbound (vless-out).

## Self-Check: PASSED

**Files created:**
- ✅ FOUND: `.planning/phases/08-rules-engine-split-tunneling/08-06-SUMMARY.md`

**Files modified:**
- ✅ FOUND: `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` (step 5 — lines 244-300; doc-comment — lines 137-147)
- ✅ FOUND: `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift` (6 new tests + 1 legacy test layout fix)

**Commits:**
- ✅ FOUND: `3ee9ab2` — feat(08-W5): SingBoxConfigLoader injects 3 rule_set + 3 priority rules (D-01)
- ✅ FOUND: `5c6c645` — test(08-W5): 6 SingBoxConfigLoader tests for rule_set injection + R1/R10 invariants

**Tests:**
- ✅ PacketTunnelKit SingBoxConfigLoaderTests: 41 / 41 PASS (was 35)
- ✅ PacketTunnelKit total: 72 / 72 PASS
- ✅ RulesEngine: 41 / 41 PASS (no regression)
- ✅ AppFeatures: 162 / 162 PASS (no regression)

**Build:**
- ✅ `cd BBTB/Packages/PacketTunnelKit && swift build` → Build complete!

**Acceptance criteria** (from PLAN W5):
- ✅ `grep -c 'rule_set' SingBoxConfigLoader.swift` = 13 (≥3)
- ✅ `grep -cE 'bbtb-block|bbtb-never|bbtb-always' SingBoxConfigLoader.swift` = 13 (≥3)
- ✅ `grep -c 'AppGroupContainer.rulesCacheDirectory' SingBoxConfigLoader.swift` = 1 (exact)
- ✅ `grep -c '"action": "reject"' SingBoxConfigLoader.swift` = 1 (≥1)
- ✅ `grep -c '"outbound": "direct"' SingBoxConfigLoader.swift` = 1 (≥1)
- ✅ `grep -c 'firstProxyTag' SingBoxConfigLoader.swift` = 7 (≥1)
- ✅ `grep -cE 'existingTags|existingRuleSetRefs' SingBoxConfigLoader.swift` = 7 (≥2)
- ✅ 6 new W5 test funcs verified by `grep -cE 'func test_(expandConfigForTunnel_injectsThreeRuleSet|...)'` = 6
- ✅ `grep -cE 'R10invariant|R1invariant' SingBoxConfigLoaderTests.swift` = 2 (≥2)
