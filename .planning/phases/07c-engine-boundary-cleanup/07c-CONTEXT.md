# Phase 7c: Engine Boundary Cleanup — Context

**Gathered:** 2026-05-14
**Status:** Ready for execute
**Input:** User invoked Claude.md scaling principle (line 112): «Всегда предлагай и ставь такие варианты в приоритет, которые в будущем помогут проще маштабироваться (20 протоколов, 50+ транспортов)». User confirmed HYBRID variant per Codex deep research recommendation.

<domain>
## Phase Boundary

**Lightweight architectural cleanup** для PacketTunnelKit чтобы будущая интеграция второго engine (AmneziaWG / Partout / etc — when reach buildable spike) была plug-and-play, **без полного pre-built abstraction layer**.

**Что доставляет:**
1. **Sing-box код переезжает в `Sources/PacketTunnelKit/SingBox/` namespace** — explicit boundary вокруг libbox-specific логики. Файлы:
   - `BaseSingBoxTunnel.swift` (397 lines, 59 sing-box mentions)
   - `ExtensionPlatformInterface.swift` (546 lines, 85 sing-box mentions — libbox callback implementations)
   - `SingBoxConfigLoader.swift` (256 lines, 30 sing-box mentions)
   - `Resources/SingBoxConfigTemplate.vless-reality.json` → `SingBox/Resources/`
   - Package.swift `resources:` path обновлён.
2. **Engine-agnostic utilities остаются at top level** (`AppGroupContainer`, `TunnelSettings`, `TunnelLogger`, `ExternalVPNStopMarker`, `InterfaceFlagsInspector`, `PacketTunnelKit.swift`) — это plumbing applicable к любому engine.
3. **`PacketTunnelKit/Docs/EngineAbstractionDecision.md`** — decision log + триггеры для введения `protocol TunnelEngine` в будущем (когда AWG/Partout reach buildable spike, либо два engine'а одновременно нужны, либо PacketTunnelProvider gains second concrete lifecycle path).
4. **Migration breadcrumbs** в `BaseSingBoxTunnel.swift` — короткий комментарий «when adding second engine, this is where TunnelEngine protocol goes».
5. **Wiki sync:** `wiki/architecture.md` обновлена с новой структурой PacketTunnelKit; новая страница `wiki/engine-abstraction-decision-2026.md` параллельно с openvpn / wireguard / amneziawg deferral logs.

**НЕ доставляет:**
- ❌ `protocol TunnelEngine` — НЕ создаём (premature abstraction, см. Codex research)
- ❌ `TunnelEngineFactory` — НЕ создаём
- ❌ `AmneziaWGEngine.swift placeholder` / `OpenVPNEngine.swift placeholder` — НЕ создаём
- ❌ Никакого Go bridge / `libwg-go.a` / `amneziawg-apple` — НЕ трогаем
- ❌ Поведенческих изменений — это **pure rename + reorganization**, regression smoke = подтверждение

</domain>

<decisions>
## Implementation Decisions

### D-01: HYBRID variant — boundary cleanup без protocol abstraction

**Decision:** Move sing-box-specific files в `SingBox/` namespace + write decision document. НЕ создавать `protocol TunnelEngine` пока нет реального второго engine.

**Rationale (Codex deep research thread `019e2802-ed23-7f21-bd6a-138edea62528`):**
- Production iOS VPN evidence: ни один production app не использует pre-built `TunnelEngine` protocol с одной реализацией. Hiddify-iOS = mega-engine sing-box (как у нас); IVPN = separate PacketTunnel extension targets per engine; Amnezia = switch-dispatch с protocol-specific extension files; Mullvad/Proton = single WireGuard family; **никакого «protocol abstraction with one implementation» паттерна не найдено**.
- Без живого второго engine `protocol TunnelEngine` неизбежно encode'ит sing-box assumptions → когда AWG/Partout придёт, придётся рефакторить shape всё равно.
- iOS NetworkExtension dominant complexity = memory limit (~50MB), routing semantics, includeAllNetworks behavior — НЕ engine abstraction. Codex Risk #2.
- Three Strikes rule (Robert Martin): первый раз делай напрямую, второй duplicate, третий refactor в abstraction. У нас один engine = первый раз.

### D-02: Файлы которые переезжают в `SingBox/`

**Heavy sing-box-specific (move):**
- `BaseSingBoxTunnel.swift` — sing-box tunnel base class.
- `ExtensionPlatformInterface.swift` — libbox callback implementations (`LibboxPlatformInterfaceProtocol` + `LibboxCommandServerHandlerProtocol`).
- `SingBoxConfigLoader.swift` — sing-box config validation.
- `Resources/SingBoxConfigTemplate.vless-reality.json` → `SingBox/Resources/`.

**Engine-agnostic (stay at top level):**
- `AppGroupContainer.swift` — App Group paths utility.
- `TunnelSettings.swift` — NEPacketTunnelNetworkSettings helpers (R6 P2P=false invariant — applicable к любому engine).
- `TunnelLogger.swift` — OSLog category constants.
- `ExternalVPNStopMarker.swift` — Phase 6d App Group marker (Settings-disable detection — applicable к любому engine).
- `InterfaceFlagsInspector.swift` — utun flags utility.
- `PacketTunnelKit.swift` — module entry.
- `PlatformSpecific/iOS.swift` + `macOS.swift` — pure platform glue (zero sing-box mentions).

### D-03: Package.swift — minimal change

Только ОДНА строка меняется: `Resources/SingBoxConfigTemplate.vless-reality.json` → `SingBox/Resources/SingBoxConfigTemplate.vless-reality.json`. Swift compiler собирает все `.swift` под `Sources/PacketTunnelKit/**` независимо от subdirectory — никаких других Package.swift изменений не нужно.

### D-04: EngineAbstractionDecision.md — short decision document

**File:** `BBTB/Packages/PacketTunnelKit/Docs/EngineAbstractionDecision.md`

**Содержание (на основе Codex Q4 + Q5):**
- Текущее состояние: mono-engine sing-box.
- Триггеры для введения `protocol TunnelEngine` (любой ИЗ):
  1. AWG/Partout/другой engine reaches **buildable iOS spike** с реальным config.
  2. Два engine'а одновременно нужны в TestFlight build.
  3. PacketTunnelProvider gains **second concrete lifecycle path** с разными setup/stop/error semantics.
  4. Sing-box config generation перестаёт быть dominant complexity, и engine lifecycle становится dominant complexity.
- При triggering: choose между **Amnezia-style switch-dispatch** (один PacketTunnelProvider, protocol-specific extension files) либо **IVPN-style separate extensions** (отдельный target per engine, если memory/crash isolation критично).
- Reference: Codex thread `019e2802-ed23-7f21-bd6a-138edea62528` (production iOS VPN architecture survey).
- Anti-pattern: НЕ называть классы generic именами (`VPNEngine`, `CoreManager`, `ProtocolService`) пока есть только sing-box.

### D-05: Migration breadcrumbs

В `BaseSingBoxTunnel.swift` (или `ExtensionPlatformInterface.swift`) — короткий комментарий:

```swift
// MARK: - Engine boundary marker (Phase 7c, 2026-05-14)
//
// Sing-box specific code lives under PacketTunnelKit/SingBox/.
// When introducing a second engine (AmneziaWG / Partout / etc), see
// `BBTB/Packages/PacketTunnelKit/Docs/EngineAbstractionDecision.md`
// for the trigger criteria and recommended pattern.
```

### Claude's Discretion

- Точная структура `EngineAbstractionDecision.md` (markdown sections, длина) — researcher / executor определит.
- Order of file moves в одном или нескольких commits — discretion (рекомендую один atomic commit за весь rename + один commit за docs/wiki).
- Wiki page `engine-abstraction-decision-2026.md` структура — по образцу `openvpn-deferral-2026.md` / `wireguard-deferral-2026.md` / `amneziawg-deferral-2026.md` (decision log pattern).

</decisions>

<canonical_refs>
## Canonical References

### Внутри проекта
- `.planning/PROJECT.md` — R20 row, Out of Scope (PROTO-06/07/09 + DPI-04 deferred с условиями возврата)
- `.planning/REQUIREMENTS.md` — strikethrough секции для PROTO-07 + DPI-04
- `.planning/ROADMAP.md` — Phase 7 mother entry ✅ Closed; Phase 7b cancellation note
- `.planning/STATE.md` — Active Phase 8, previous-previous Phase 7b cancellation block
- `.planning/phases/07-anti-dpi-suite-wireguard-family/07-CONTEXT.md` — главный Phase 7 contract + cancellation note
- `wiki/amneziawg-deferral-2026.md` — Phase 7b cancellation decision log (linked from this Phase 7c)

### Codex research artefacts
- Thread `019e26cb-cf49-78c3-af80-d437a5b22f28` — sing-box 1.13.x ground truth (Phase 7 discuss)
- Thread `019e26d8-0397-7fa0-91b3-312e7e3e3ca9` — OpenVPN РФ 2026 deep research
- Thread `019e26f2-55e1-79d3-af9f-3d89fdc93647` — WireGuard / AmneziaWG РФ 2026 deep research
- Thread `019e27d9-f49b-7f72-abb0-9b0ccdb94aae` — amneziawg-apple library state + Amnezia VPN multi-engine reference
- Thread `019e2802-ed23-7f21-bd6a-138edea62528` — **production iOS VPN multi-engine architecture survey + HYBRID recommendation для Phase 7c (this phase)**

### Existing PacketTunnelKit structure (target of refactor)
- `BBTB/Packages/PacketTunnelKit/Package.swift` — `resources:` path обновится
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` — moves to `SingBox/`
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift` — moves to `SingBox/`
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift` — moves to `SingBox/`
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json` — moves to `SingBox/Resources/`

### Existing tests (must continue to pass без изменений)
- `Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift`
- `Tests/PacketTunnelKitTests/SingBoxConfigLoaderIPv6Tests.swift`
- `Tests/PacketTunnelKitTests/TunnelSettingsTests.swift`
- `Tests/PacketTunnelKitTests/TunnelSettingsIPv6Tests.swift`
- `Tests/PacketTunnelKitTests/ValidatedAtGuardTests.swift`
- Baseline: 66/66 pass.

</canonical_refs>

<code_context>
## Existing Code Insights

### Что меняем (move + rename)
- 3 sing-box-specific Swift файла → `Sources/PacketTunnelKit/SingBox/`
- 1 JSON template → `Sources/PacketTunnelKit/SingBox/Resources/`
- Package.swift `resources:` path → одна строка
- Comment добавляется в один из файлов как breadcrumb marker

### Что НЕ меняем
- Внутренности файлов — поведение, public API, имена классов остаются идентичны
- Imports — `import SingBoxBridge`, `import VPNCore`, `import Network` остаются
- Tests — sing-box-specific test files остаются `Tests/PacketTunnelKitTests/SingBox*Tests.swift` (rename test files можно делать в этом же commit'е либо отложить — discretion)
- ProtocolEngine package (`SingBoxBridge` + `LibboxBootstrap`) — отдельный пакет, не трогаем
- Все остальные packages (AppFeatures, ConfigParser, Protocols/*) — не трогаем

### Integration risk
- **Tuist project** возможно надо regenerate чтобы Xcode подхватил новые file paths (для Tuist-generated targets which sources Sources/PacketTunnelKit/**). Verify через `tuist generate` после move.
- **iOS + macOS xcodebuild** — финальная gate.
- **PacketTunnelKit swift test** baseline 66/66 → должно остаться 66/66.

</code_context>

<specifics>
## Specific Ideas

- **Codex production-evidence-driven**: HYBRID — это эмпирический recommendation на основе survey 7+ production iOS VPN apps (Amnezia, Hiddify, IVPN, Mullvad, Proton, WireGuard.app, OpenVPNAdapter). Никакого premature abstraction.
- **Decision Document как long-term memory**: `EngineAbstractionDecision.md` живёт в `BBTB/Packages/PacketTunnelKit/Docs/` чтобы быть рядом с кодом — будущий разработчик (либо Claude в новой сессии) сразу увидит decision при изучении PacketTunnelKit.
- **Mirror в wiki** (`engine-abstraction-decision-2026.md`) для project-level discoverability.

</specifics>

<deferred>
## Deferred Ideas

- **`protocol TunnelEngine`** — defer до триггеров в `EngineAbstractionDecision.md`.
- **`TunnelEngineFactory`** — same.
- **AmneziaWG engine integration** — Phase 7b cancelled, см. `wiki/amneziawg-deferral-2026.md`.
- **OpenVPN/Partout engine integration** — Phase 7 D-01 deferred, см. `wiki/openvpn-deferral-2026.md`.
- **Generic-named classes** (`VPNEngine`, `CoreManager`, `ProtocolService`) — anti-pattern пока один engine. Anti-recommendation в `EngineAbstractionDecision.md`.

</deferred>

---

*Phase: 7c-engine-boundary-cleanup*
*Context gathered: 2026-05-14*
*Discuss-phase method: HYBRID variant (Codex thread `019e2802-...` recommendation, user confirmed)*
*Downstream: execute waves W1-W5 → iOS+macOS xcodebuild + AppFeatures/ConfigParser/PacketTunnelKit/TUIC regression smoke → atomic commits → wiki sync → closure*
