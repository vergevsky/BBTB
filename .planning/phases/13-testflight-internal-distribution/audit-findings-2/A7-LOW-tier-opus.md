# A7' — LOW tier re-audit (Opus 4.7)

**Baseline:** commit `55523dd` (Plan 03 final fix — `fix(13-03/T-A2): remove unsafe template paths in all 6 protocols`).
HEAD at audit time: `c260e69` (docs(13-04) re-audit plan — no code change).

**Scope:** 5 packages, 12 source files, ~1134 LOC total.
- `BBTB/Packages/DesignSystem/Sources/DesignSystem/` (6 files, 572 LOC)
- `BBTB/Packages/ProtocolEngine/Sources/` (3 files, 47 LOC — XrayFallback + SingBoxBridge + LibboxBootstrap)
- `BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/` (1 file, 26 LOC)
- `BBTB/Packages/Localization/Sources/Localization/L10n.swift` (412 LOC)
- `BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift` (81 LOC)

**Plan 03 cross-impact assessment:** None of the 18 Tier-A/B fix commits between `cc88712` и `55523dd` touched any файл из LOW tier scope (`git log --oneline -- BBTB/Packages/{DesignSystem,ProtocolEngine,ProtocolRegistry,Localization,CrashReporter}` returns ONLY pre-Plan-03 commits; самый поздний — `bbe2493 feat(13-01)` Plan 01 D-04 routing toggle, который добавил 2 keys in L10n.swift и помечен здесь как closure-verified). Transitive risk → effectively zero: эти 5 пакетов либо leaf utility (Localization, CrashReporter, DesignSystem), либо low-coupling registry (ProtocolEngine/SingBoxBridge façade, ProtocolRegistry). Plan 03 правки касались RulesEngine, ConfigParser, VPNCore, PacketTunnelKit, FrontingEngine, AppFeatures, и шести protocol handlers — все находятся выше по стеку.

## Closure Verification (Plan 02 original A7 / C9 LOW findings)

Из 17 original LOW findings (A7-DS-01..05, A7-PE-01..03, A7-PR-01..02, A7-LC-01..02, A7-CR-01..03 + C9-001..008) **ни одна не была закрыта** между Plan 02 audit и `55523dd` — Plan 03 fix-плана для LOW tier не существует (см. `13-03-AUDIT-FIX-PLAN.md` — там только Tier A + Tier B). Все 17 остаются open / accepted-as-deferred. Это ожидаемое поведение per Plan 03 charter (LOW tier — backlog candidate, не блокирует TestFlight). Re-audit подтверждает что severity ratings всех 17 findings остаются корректными — НИ ОДНА не должна повышаться до MEDIUM/HIGH.

Дополнительно проверено:
- `XrayFallback.swift` остаётся placeholder enum с `placeholder = true` (3 строки, 0 consumer references); ships as public library product per `ProtocolEngine/Package.swift:9` — A7-PE-01/C9-002 confirmed open.
- `SingBoxBridge.singBoxVersion = "1.13.11"` — `grep` подтверждает 0 references outside declaration — A7-PE-02 confirmed open.
- `ProtocolRegistry.registeredIdentifiers` — 0 references in production code (только Tests refers to `TransportRegistry.shared.registeredIdentifiers`, не ProtocolRegistry) — C9-005 confirmed open.
- `DS.accent` deprecated alias всё ещё в `DesignSystem.swift:24` — grep подтверждает 0 production call-sites (только self-ref); A7-DS-03 confirmed open.
- `CrashReporter` зависит от PacketTunnelKit (Package.swift:9 + linker carve-out для libbox transitive resolv/bsm) — C9-007 MEDIUM confirmed open; dependency используется ради single symbol `AppGroupContainer.crashReportsURL`.

## New Findings (Plan 03 D-04 + new code)

### Localization

#### A7'-001 (LOW) — D-04 routing-rules keys verified, no drift
**File:** `BBTB/Packages/Localization/Sources/Localization/L10n.swift:181-182` + `Resources/Localizable.xcstrings`.
**Status:** Clean ✓. Plan 01 D-04 добавил `settingsRoutingRulesLabel` / `settingsRoutingRulesFooter` через `static var` (lazy, per Theme A pattern) и обе keys присутствуют в xcstrings JSON. Consumer (`AdvancedSettingsView.swift:77,80`) подключён корректно. No new findings.

### ProtocolEngine

#### A7'-002 (LOW) — `LibboxBootstrap.SetupError` not wrapped at PacketTunnelKit boundary
**File:** `BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/LibboxBootstrap.swift:6-32`.
**Observation:** `setup()` throws `SetupError.failure(NSError?)` с `localizedDescription` от libbox в plain text (без redaction). На iOS extension boundary это попадает в Logger через `BaseSingBoxTunnel.startTunnel`. Если libbox embedds в error path-строки (`basePath` / `workingPath` / `tempPath`), App Group container path может leak в os_log unified buffer.
**Risk:** Low. Container UUID — не secret, но добавляет surface к diagnostic exports. Уже covered by Plan 03 T-A5 IPv6 masking pattern (DiagnosticsExporter) — этот finding ниже что-либо актуального; recommend backlog-defer.

#### A7'-003 (LOW) — `@_exported import Libbox` в `SingBoxBridge.swift:1` leaks libbox surface
**File:** `BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/SingBoxBridge.swift:1`.
**Observation:** Любой consumer делающий `import SingBoxBridge` автоматически получает весь Libbox C-bridge API (LibboxNewService, LibboxBoxService, LibboxPlatformInterface и т.д.). PacketTunnelKit это use-case — но широкий surface area увеличивает риск что вышестоящие features случайно вызовут low-level libbox API в обход façade. Underscored `@_exported` — known SPM stable, but architectural smell.
**Mitigation:** v1.x — выделить explicit re-exports вместо blanket. v1.0 — accept (façade documented).

### DesignSystem

#### A7'-004 (LOW) — `BBTBSpinner` race на reduce-motion runtime toggle (subset of A7-DS-02)
**File:** `BBTB/Packages/DesignSystem/Sources/DesignSystem/Spinner.swift:78-90`.
**Observation:** Confirmed original A7-DS-02 — `.onAppear` triggered ONCE; switch между `accessibilityReduceMotion=true/false` mid-flight (например, пользователь меняет setting во время `.connecting`) НЕ перезапускает animation closure. View остаётся в стейте предыдущего mode пока не unmount/remount. Battery guard rationale (RESEARCH §9 Pitfall 3) гарантирует unmount on `.connected` — что де-факто closes window. Re-audit confirms severity LOW (edge case + auto-recovery on next mount).

#### A7'-005 (LOW) — `BBTBTopBar` doesn't propagate `.accessibilityElement` grouping
**File:** `BBTB/Packages/DesignSystem/Sources/DesignSystem/BBTBTopBar.swift:52-68`.
**Observation:** HStack с leading + title + trailing slots не имеет `.accessibilityElement(children: .contain)` — VoiceOver swipe-order через 3 элемента + title как separate focus, что в Figma BBTB v3 spec не явно прописано но в Apple HIG guidance для navigation bars рекомендуется grouping. На iOS 26 native `.toolbar` делает это автоматически; custom BBTBTopBar — нет.
**Risk:** Low. Не блокирует TestFlight (functional VoiceOver работает), но a11y polish.

### ProtocolRegistry

#### A7'-006 (LOW) — `register()` без override-protection (subset of A7-PR-01)
**File:** `BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift:12-15`.
**Observation:** Confirmed A7-PR-01. `handlers[H.identifier] = handlerType` молча overrides previous registration. Production регистрирует 6 уникальных identifier в init-time (BBTB_iOSApp.swift:74-79). Race-free через NSLock. Не наблюдается active misuse. Re-audit confirms LOW severity — assert-on-duplicate помог бы tests, но Phase 13 not blocking.

### CrashReporter

#### A7'-007 (LOW) — `_test_inject` API leak в release builds avoided ✓ confirmed
**File:** `CrashReporter.swift:74-80`.
**Observation:** Method wrapped in `#if DEBUG` — release binary НЕ exports symbol. Confirmed by inspection. C9-008 (public init) и A7-CR-01 (public _test_inject) остаются open but technically безопасны: init() doc даёт singleton-discipline guidance, _test_inject not in release.

## Notes

**Severity floor unchanged.** All 17 Plan 02 LOW findings remain LOW; 5 new findings (A7'-002..A7'-006) all LOW; 1 closure verified (A7'-001); 1 confirmed safe (A7'-007). No new MEDIUM or HIGH findings emerged from Plan 03 transitive analysis.

**TestFlight readiness for these 5 packages:** GREEN. None of LOW findings блокирует Internal TestFlight upload или Apple review. CrashReporter MEDIUM (C9-007 PacketTunnelKit dep) уже compensated by linker carve-out in test target — production app already имеет PacketTunnelKit linked.

**Recommend backlog parking:** 22 LOW + 1 MEDIUM (C9-007) findings → `v1.x backlog` группа `LOW-pre-tf-deferred`. None требует Plan 03 follow-up fix commit.

**One read-only verification suggestion (no code change):** add `XCTAssertEqual(ProtocolRegistry.shared.registeredIdentifiers.count, 6)` smoke test в App-level boot test, чтобы registry mis-config (Plan 03 не трогал но регистрация — 12 lines in BBTB_iOSApp.swift + BBTB_macOSApp.swift, легко drift) выявлялся в CI. Не блокер TestFlight.
