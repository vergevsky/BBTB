# Phase 7c — Final Summary (HYBRID Engine Boundary Cleanup) ✅ Closed 2026-05-14

**Status:** ✅ **Closed 2026-05-14**
**Type:** Internal architectural refactor (no version bump, v0.7.1 stays)
**Authority:** User confirmation 2026-05-14 «Окей, делаем. Вариант B» + Codex deep research thread `019e2802-ed23-7f21-bd6a-138edea62528` (production iOS VPN multi-engine architecture survey)
**Scope:** Sing-box-specific code containment into `SingBox/` namespace + decision document for future `protocol TunnelEngine` triggers. NO new protocols, NO new engines, NO behavior changes.

---

## Что сделано (атомарно в одном commit)

### Code reorganization (`git mv` preserves history)

4 files relocated:
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` → `.../SingBox/BaseSingBoxTunnel.swift` (+breadcrumb-marker comment)
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift` → `.../SingBox/ExtensionPlatformInterface.swift`
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift` → `.../SingBox/SingBoxConfigLoader.swift`
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json` → `.../SingBox/Resources/SingBoxConfigTemplate.vless-reality.json`

### Engine-agnostic files (stayed at top level)

- `AppGroupContainer.swift` — App Group paths utility
- `TunnelSettings.swift` — R6-safe `NEPacketTunnelNetworkSettings` builder (applicable к любому engine)
- `TunnelLogger.swift` — OSLog category constants
- `ExternalVPNStopMarker.swift` — Phase 6d App Group marker (Settings-disable detection)
- `InterfaceFlagsInspector.swift` — utun flags utility (R6 assertion)
- `PacketTunnelKit.swift` — module entry
- `PlatformSpecific/iOS.swift` + `macOS.swift` — pure platform glue

### Package.swift updated

```swift
resources: [
    // Phase 7c (2026-05-14) — sing-box-specific files relocated to SingBox/ namespace.
    // See BBTB/Packages/PacketTunnelKit/Docs/EngineAbstractionDecision.md.
    .process("SingBox/Resources/SingBoxConfigTemplate.vless-reality.json")
]
```

### Breadcrumb-marker added

В `BaseSingBoxTunnel.swift` — короткий comment block после imports:
```
// MARK: - Engine boundary marker (Phase 7c, 2026-05-14)
//
// Sing-box specific code is contained under `Sources/PacketTunnelKit/SingBox/`.
// When introducing a second engine (AmneziaWG / Partout / etc), refer to
// `BBTB/Packages/PacketTunnelKit/Docs/EngineAbstractionDecision.md` for the
// trigger criteria and recommended architectural pattern.
// Do NOT preemptively introduce a `protocol TunnelEngine` while there is only
// one production engine.
```

### Decision document created

`BBTB/Packages/PacketTunnelKit/Docs/EngineAbstractionDecision.md` — code-level long-term memory:
- Current state (mono-engine sing-box)
- Why no `protocol TunnelEngine` yet (Codex production evidence — Hiddify/Amnezia/IVPN/Mullvad/Proton survey)
- Three Strikes rule rationale
- Triggers for introducing abstraction (4 conditions)
- Pattern selection при trigger: Path A (Amnezia-style switch-dispatch) vs Path B (IVPN-style separate extensions)
- Anti-patterns (generic naming запрещён, placeholder engine files запрещены, premature protocol запрещён)
- Migration breadcrumbs (where to look first when arrival)

### Cross-references updated

| File | Change |
|---|---|
| `BBTB/scripts/validate-r1-r6.sh` | R1 + R6 invariant gate paths updated to `SingBox/...` — **критично**, иначе static gate был бы broken |
| `wiki/security-gaps.md` § R10 + R11 | File references updated to `SingBox/...` paths |
| `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` | Doc comment path updated |
| `BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift` | Doc comment path updated |
| `BBTB/Packages/VPNCore/Tests/VPNCoreTests/ParsedConfigsTests.swift` | **Pre-existing Phase 7a Wave 1 bug закрыт** — `.tuic` case добавлен в exhaustiveness gate (был 9-й switch site, я пропустил в Wave 1) |

### Wiki long-term memory

- `wiki/engine-abstraction-decision-2026.md` (new) — full decision log параллельно с openvpn / wireguard / amneziawg deferral pages.
- `wiki/architecture.md` — updated с описанием SingBox/ namespace + ссылкой на decision page.
- `wiki/security-gaps.md` — § R10 + R11 file references обновлены.
- `wiki/index.md` — engine-abstraction-decision-2026 page registered.
- `wiki/log.md` — Phase 7c Closed entry placed before Phase 7b Cancelled entry.

### Planning updates

- `.planning/STATE.md` — Active Phase 8; previous phase = Phase 7c с full outcome block.
- `.planning/PROJECT.md` — Evolution last-updated line обновлена.
- `.planning/phases/07c-engine-boundary-cleanup/07c-CONTEXT.md` — discuss-phase contract (создан в начале Phase 7c).
- `.planning/phases/07c-engine-boundary-cleanup/07c-Final-SUMMARY.md` — this file.

---

## Verification (тройная проверка перед commit)

### Pass 1 — code references

- ✅ Никаких hardcoded paths к старым локациям не осталось в production code (search all `.swift` files).
- ✅ Tuist `Project.swift` не имеет file-level path references к moved files (только module-level `package(product: "PacketTunnelKit")`).
- ✅ Test files unchanged (existing SingBoxConfigLoaderTests/IPv6Tests/etc живут в `Tests/PacketTunnelKitTests/` — rename test files в SingBox subdir тоже defer; они работают по module name, не по filesystem path).

### Pass 2 — build + test regression

| Package | Tests | Status |
|---|---|---|
| PacketTunnelKit | 66/66 | ✅ PASS |
| ConfigParser | 228/228 | ✅ PASS |
| AppFeatures | 143/143 | ✅ PASS |
| TUIC | 26/26 | ✅ PASS |
| Trojan | 16/16 | ✅ PASS |
| VLESSTLS | 20/20 | ✅ PASS |
| VLESSReality | (all existing) | ✅ PASS |
| Hysteria2 | 14/14 | ✅ PASS |
| Shadowsocks | (all existing) | ✅ PASS |
| VPNCore | (after .tuic fix) | ✅ PASS |
| KillSwitch | (all existing) | ✅ PASS |
| Localization | 3/3 | ✅ PASS |
| CrashReporter | (all existing) | ✅ PASS |

Plus build verifications:
- ✅ All 17 SwiftPM packages — clean `.build` artifacts → fresh build green
- ✅ `tuist generate` clean
- ✅ iOS xcodebuild scheme BBTB destination=generic/iOS Debug → **SUCCEEDED**
- ✅ macOS xcodebuild scheme BBTB-macOS destination=generic/macOS (ad-hoc signing) Debug → **SUCCEEDED**

### Pass 3 — security invariants gate

`BBTB/scripts/validate-r1-r6.sh` — 11/11 PASS:
- R1: template has no 'inbounds' key ✓
- R1: template has empty experimental {} ✓
- R6: no destinationAddresses assignment in PacketTunnelKit Sources ✓
- R6: assertNoPointToPointOnUtun is invoked ✓
- KILL-01: includeAllNetworks=true in KillSwitch.apply ✓
- KILL-01: enforceRoutes set via PlatformHooks negation ✓
- KILL-01: ConfigImporter zovet KillSwitch.apply ✓
- SEC-03: SocksProbe iOS entitlements БЕЗ application-groups ✓
- SEC-03: SocksProbe iOS entitlements БЕЗ keychain-access-groups ✓
- SEC-03: SocksProbe macOS entitlements БЕЗ application-groups ✓
- SEC-05: kSecAttrAccessibleWhenUnlocked в KeychainStore ✓

---

## Что НЕ сделано (intentionally — anti-pattern enforcement)

- ❌ `protocol TunnelEngine` — НЕ создан (premature abstraction)
- ❌ `TunnelEngineFactory` / `TunnelEngineKind` enum — НЕ создан
- ❌ Placeholder engine файлы (`AmneziaWGEngine.swift`, `OpenVPNEngine.swift`) — НЕ создавались
- ❌ Generic-named classes (`VPNEngine`, `CoreManager`, `ProtocolService`) — anti-recommendation в EngineAbstractionDecision.md
- ❌ Refactor `BaseSingBoxTunnel` to «engine-agnostic shape» — defer до real second engine constraints

---

## Триггеры для будущего введения `protocol TunnelEngine`

Возвращаемся к этому вопросу когда выполняется **одно из** (см. `BBTB/Packages/PacketTunnelKit/Docs/EngineAbstractionDecision.md`):

1. **Buildable iOS spike для второго engine** — AmneziaWG (`amneziawg-apple`) или OpenVPN-Partout reaches state где actually starts/stops внутри real `NEPacketTunnelProvider` extension с real config.
2. **Два engines coexist в одном TestFlight build** — concrete product requirement.
3. **`PacketTunnelProvider` gains second concrete lifecycle path** — different setup/teardown/error semantics.
4. **Engine lifecycle становится dominant complexity** — overtakes sing-box config generation в LOC + cognitive load.

При triggering — выбираем между Path A (Amnezia switch-dispatch) либо Path B (IVPN separate extensions) на основе memory profile / Go runtime / crash isolation requirements.

---

## Что мы выиграли

✅ **Соответствие principle (Claude.md line 112)** — sing-box код теперь **явно extractable**, namespace чистый, breadcrumbs для будущего разработчика проложены.
✅ **Не нарушили YAGNI** — никакой premature abstraction, никаких placeholder файлов, никаких generic names.
✅ **Поведение приложения идентично** — pure rename + reorganization, regression smoke = подтверждение.
✅ **Pre-existing bug найден и зафикшен** — VPNCore exhaustiveness gate (Phase 7a Wave 1 missed update).
✅ **Decision document как long-term memory** — будущий разработчик (либо Claude в новой сессии) видит decision рядом с кодом + в wiki.

---

## Что мы НЕ выиграли (честное disclosure)

- **Real engine integration cost не снизился.** Когда AWG/Partout реально придёт, всё равно потребуется substantial work — Codex estimates стоят (5-7 engineer-weeks для AWG full quality).
- **Не доказали что abstraction shape correct** — без реального второго consumer мы не знаем, какой будет final `protocol TunnelEngine` shape. Decision doc даёт guidance, но real test = real second engine.

---

## Phase 7 финал (cumulative)

| Phase | Status | Result |
|---|---|---|
| Phase 7a (v0.7.1) | ✅ Closed | TUIC v5 + anti-DPI smart defaults + DPI-07. iPhone UAT PASS на Trojan. |
| Phase 7b (v0.7.2) | ❌ Cancelled | AmneziaWG + engine abstraction → v2.0+ backlog. |
| Phase 7c (internal) | ✅ Closed | Engine boundary cleanup (HYBRID) — sing-box код в `SingBox/`, decision doc + триггеры. |
| **Phase 7 итог** | ✅ **Closed** | 6 in-scope протоколов в финальном MVP-наборе. Architecture: mono-engine sing-box с **clean extension point** для будущих engines. |

---

## Wave / commit hash table (Phase 7 cumulative — для git navigation)

```
9130e3c — docs(phase-07): capture phase context via discuss-phase
444a09e — docs(phase-07): sync ROADMAP / REQUIREMENTS / PROJECT to Phase 7 decisions
bb63101 — docs(wiki): add Phase 7 deferral decision logs (openvpn, wireguard)
92b051d — docs(wiki): register Phase 7 deferral pages in index + log
8ca1014 — feat(07a-w1): TUIC v5 protocol package (PROTO-08) +1418 lines
1d98abc — feat(07a-w2): anti-DPI smart defaults — uTLS=random + tls.record_fragment
cb6140b — feat(07a-w4): register TUICHandler in apps + Tuist project
49c40d5 — docs(07a-w5): pre-UAT wiki sync + closure summary
674409b — docs(07a): finalize Phase 7a closure after iPhone UAT PASS (rename PRE-UAT → Final)
e923e60 — docs(07a): closure content updates (REQUIREMENTS/ROADMAP/STATE/PROJECT/wiki)
531feed — docs(phase-07b): cancel Phase 7b — AmneziaWG 2.0 + engine abstraction → v2.0+ backlog
[this commit] — feat(07c): engine boundary cleanup — relocate sing-box code to SingBox/ namespace + decision doc
```

---

*Phase 7c implementation autonomous run completed 2026-05-14. Next: `/gsd-discuss-phase 8` (Rules Engine + Split tunneling, v0.8).*
