---
name: Engine Abstraction — decision May 2026
description: Решение Phase 7c (HYBRID variant) — sing-box код контейнеризован в SingBox/ namespace, но `protocol TunnelEngine` НЕ создаётся пока есть только один движок
type: project
---

# Engine Abstraction — решение Phase 7c (HYBRID)

**Summary**: По итогам Codex deep research состояния production iOS VPN multi-engine архитектуры (thread `019e2802-ed23-7f21-bd6a-138edea62528`) и принятого пользователем 2026-05-14 решения «делаем Вариант B» — выполнен **HYBRID engine boundary cleanup** в `PacketTunnelKit`: sing-box-specific код переехал в `SingBox/` namespace, sing-box-explicit naming сохранён, добавлена decision-документация с триггерами для введения `protocol TunnelEngine` в будущем. Полный protocol abstraction layer **НЕ построен** — premature abstraction is worse than late abstraction (no production iOS VPN app uses pre-built `TunnelEngine` protocol with single implementation; Codex evidence).

**Sources**: Phase 7c discuss + execute 2026-05-14, Codex thread `019e2802-...`, Claude.md scaling principle (line 112).

**Last updated**: 2026-05-14

---

## Контекст

После Phase 7a closure (TUIC v5 + anti-DPI smart defaults) и Phase 7b cancellation (AmneziaWG отложен в v2.0+ backlog), пользователь напомнил project core principle (Claude.md line 112): «Всегда предлагай и ставь такие варианты в приоритет, которые в будущем помогут проще маштабироваться (20 протоколов, 50+ транспортов)». Запрос: заложить основу для модульности и масштабируемости — чтобы будущая интеграция второго engine (AmneziaWG / OpenVPN-Partout / etc) была plug-and-play.

Запущен Codex deep research thread `019e2802-ed23-7f21-bd6a-138edea62528` для актуальной empirical reality production iOS VPN multi-engine архитектуры.

## Что показало исследование

### Production iOS VPN apps — actual patterns

| App | Engine architecture | Source |
|---|---|---|
| **Hiddify-iOS** | Mega-engine sing-box. Один `PacketTunnelProvider` subclass `ExtensionProvider`, импортирует `HiddifyCore`, вызывает `MobileSetup`, `LibboxSetMemoryLimit`, `MobileStart`, `MobileClose`. **Same as BBTB.** | [hiddify-app PacketTunnelProvider.swift](https://github.com/hiddify/hiddify-app/blob/main/ios/HiddifyPacketTunnel/PacketTunnelProvider.swift) |
| **Amnezia VPN** | Switch-dispatch в `PacketTunnelProvider.startTunnel(...)` over `providerConfiguration` keys (`ovpn` / `wireguard` / `xray`), с protocol-specific extension files `PacketTunnelProvider+OpenVPN.swift`, `+WireGuard.swift`, `+Xray.swift`. **NOT a `protocol TunnelEngine` abstraction.** | [amnezia-client iOS](https://github.com/amnezia-vpn/amnezia-client/tree/dev/client/platforms/ios) |
| **IVPN iOS** | **Multiple `NEPacketTunnelProvider` extension targets** — отдельные folders `openvpn-tunnel-provider`, `wireguard-tunnel-provider`. Process-level isolation per heavy engine. | [ivpn/ios-app](https://github.com/ivpn/ios-app) |
| **Mullvad iOS** | Single WireGuard family + transports (DAITA, multihop, WG-over-TCP, WG-over-Shadowsocks, WG-over-QUIC). OpenVPN полностью удалён 15 января 2026. | [mullvadvpn-app](https://github.com/mullvad/mullvadvpn-app) |
| **ProtonVPN iOS** | WireGuard + Stealth only. OpenVPN на iOS = external OpenVPN Connect manual setup, не встроено. | [ProtonVPN/ios-mac-app](https://github.com/ProtonVPN/ios-mac-app) |
| **WireGuard.app** | Single-engine reference (WireGuardKit + один PacketTunnelProvider). | [WireGuard/wireguard-apple](https://github.com/WireGuard/wireguard-apple) |
| **OpenVPNAdapter** | Single-engine reference (OpenVPN-only). Архивирован март 2022. | [ss-abramchuk/OpenVPNAdapter](https://github.com/ss-abramchuk/OpenVPNAdapter) |

**Critical observation:** **Ни один production iOS VPN client** не использует pre-built `protocol TunnelEngine` abstraction с **одной** реализацией. Либо mono-engine (как мы), либо switch-dispatch (Amnezia), либо separate extensions (IVPN). Premature `protocol TunnelEngine` encode'ит sing-box assumptions, которые могут не fit реальный второй engine.

### Three Strikes rule (Robert Martin)

«Первый раз делай напрямую, второй раз duplicate code и держи нос, третий раз refactor в abstraction.» У нас один engine = первый раз. Делать abstraction сейчас = нарушать правило.

### iOS NetworkExtension dominant complexity

Codex Risk #2: «iOS memory pressure is the main technical risk for "20 protocols, 50+ transports"; config size/rulesets may matter more than engine abstraction». Public references:
- Xray issue #4422: iOS network process limited to ~50MB; large geolocation files cannot be loaded normally.
- Mullvad blog: `includeAllNetworks` story — iOS Packet Tunnel behavior dominates design, не abstraction.

То есть: **engine abstraction не решает scaling problem.** Config size discipline + memory limits — вот что критично для «20 protocols, 50+ transports».

## Что сделано (HYBRID variant)

### Phase 7c outcome (2026-05-14)

✅ **Sing-box код контейнеризован в `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/`:**
- `BaseSingBoxTunnel.swift` (relocated)
- `ExtensionPlatformInterface.swift` (relocated)
- `SingBoxConfigLoader.swift` (relocated)
- `Resources/SingBoxConfigTemplate.vless-reality.json` (relocated)
- `Package.swift` `resources:` path обновлён
- Breadcrumb-marker comment добавлен в `BaseSingBoxTunnel.swift`

✅ **Engine-agnostic utilities остались at top level:**
- `AppGroupContainer.swift` — App Group paths (applicable к любому engine)
- `TunnelSettings.swift` — R6-safe `NEPacketTunnelNetworkSettings` builder
- `TunnelLogger.swift` — OSLog category constants
- `ExternalVPNStopMarker.swift` — Phase 6d App Group marker (Settings-disable detection)
- `InterfaceFlagsInspector.swift` — utun flags utility
- `PlatformSpecific/iOS.swift` + `macOS.swift` — pure platform glue

✅ **Decision document создан:**
- `BBTB/Packages/PacketTunnelKit/Docs/EngineAbstractionDecision.md` — триггеры + recommended patterns + anti-patterns + migration breadcrumbs

✅ **Cross-references обновлены:**
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` doc comment
- `BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift` doc comment
- `BBTB/scripts/validate-r1-r6.sh` — R1/R6 invariant gate с обновлёнными paths
- `wiki/security-gaps.md` § R10 + § R11 file references

### Что НЕ сделано (intentionally)

❌ `protocol TunnelEngine` — НЕ создан (premature abstraction, no production evidence)
❌ `TunnelEngineFactory` — НЕ создан
❌ `TunnelEngineKind` enum — НЕ создан
❌ `AmneziaWGEngine.swift` / `OpenVPNEngine.swift` placeholder файлы — НЕ создавались (становятся dead code)
❌ Generic-named classes (`VPNEngine`, `CoreManager`, `ProtocolService`) — anti-recommendation в decision doc
❌ Никаких поведенческих изменений — это pure rename + reorganization

### Verification

- ✅ PacketTunnelKit swift test 66/66 PASS
- ✅ ConfigParser 228/228 PASS
- ✅ AppFeatures 143/143 PASS
- ✅ TUIC 26/26 PASS
- ✅ Trojan / VLESSTLS / VLESSReality / Hysteria2 / Shadowsocks — все existing tests PASS
- ✅ VPNCore — pre-existing exhaustiveness test bug найден (Phase 7a Wave 1 missed update) и зафикшен в этом же commit'е (`.tuic` case добавлен)
- ✅ `validate-r1-r6.sh` — 11 invariants PASS (R1/R6/KILL-01/SEC-03/SEC-05)
- ✅ tuist generate — clean
- ✅ iOS xcodebuild — SUCCEEDED
- ✅ macOS xcodebuild (ad-hoc signing) — SUCCEEDED

## Триггеры для введения `protocol TunnelEngine` в будущем

Возвращаемся к этому вопросу когда выполняется **одно из**:

1. **Buildable iOS spike для второго engine** — AmneziaWG (`amneziawg-apple` library) или OpenVPN-Partout reaches a state где actually starts/stops внутри real `NEPacketTunnelProvider` extension с real config. NOT «we might add it someday».

2. **Два engines coexist в одном TestFlight build** — concrete product requirement что ships within one release cycle.

3. **`PacketTunnelProvider` gains second concrete lifecycle path** — different setup/teardown/error semantics что больше не могут share current sing-box-shaped code path.

4. **Engine lifecycle становится dominant complexity** — currently sing-box config generation + JSON validation = dominant. When engine bring-up/teardown/health-check overtakes config generation в LOC + cognitive load, abstraction value rises.

При триггере — выбираем между **Path A (Amnezia-style switch-dispatch)** или **Path B (IVPN-style separate extension targets)** на основе memory profile + Go runtime presence + crash isolation requirements нового engine. Подробности — `BBTB/Packages/PacketTunnelKit/Docs/EngineAbstractionDecision.md`.

## Anti-patterns (запретные паттерны при текущем состоянии)

❌ **Generic-named classes** (`VPNEngine`, `CoreManager`, `ProtocolService`) — пока есть один engine, generic naming = pretending abstraction exists; future engine fights wrong shape.
❌ **Pre-built `TunnelEngine` protocol с одной реализацией** — no production iOS VPN does this.
❌ **Placeholder engine files** без real implementation — становятся dead code.
❌ **Refactoring `BaseSingBoxTunnel` to «engine-agnostic shape»** перед тем как есть второй engine — сохраняем для будущего refactor informed by real second-engine constraints.

## Related pages

- [[architecture]] — обновлённая SwiftPM-структура с описанием `SingBox/` namespace
- [[amneziawg-deferral-2026]] — Phase 7b cancellation (PROTO-07 + DPI-04 + engine abstraction отложены)
- [[wireguard-deferral-2026]] — Phase 7 D-02 (PROTO-06 plain WG отложен)
- [[openvpn-deferral-2026]] — Phase 7 D-01 (PROTO-09 OpenVPN/TLS отложен)
- [[security-gaps]] — R10 + R11 sections с обновлёнными SingBox/ paths
- `BBTB/Packages/PacketTunnelKit/Docs/EngineAbstractionDecision.md` — code-level decision document (рядом с кодом, для будущего разработчика)

## Source URLs (Codex research thread `019e2802-ed23-7f21-bd6a-138edea62528`)

- Hiddify iOS PacketTunnelProvider: https://github.com/hiddify/hiddify-app/blob/main/ios/HiddifyPacketTunnel/PacketTunnelProvider.swift
- Hiddify ExtensionProvider: https://github.com/hiddify/hiddify-app/blob/main/ios/HiddifyPacketTunnel/SingBox/ExtensionProvider.swift
- Amnezia VPN client iOS multi-engine reference: https://github.com/amnezia-vpn/amnezia-client/tree/dev/client/platforms/ios
- IVPN iOS app: https://github.com/ivpn/ios-app
- Mullvad VPN app: https://github.com/mullvad/mullvadvpn-app
- ProtonVPN ios-mac-app: https://github.com/ProtonVPN/ios-mac-app
- WireGuard apple: https://deepwiki.com/WireGuard/wireguard-apple/2.2-network-extension-and-packet-tunnel-provider
- Xray iOS memory issue #4422: https://github.com/XTLS/Xray-core/issues/4422
- Mullvad includeAllNetworks writeup: https://mullvad.net/fr/blog/why-we-still-dont-use-includeallnetworks
- Mullvad force-all-app blog: https://mullvad.net/en/blog/force-all-app-traffic-into-the-tunnel
- NekoBox platform FAQ: https://nekobox.pro/zh-TW/faq/nekobox-windows-mac-ios/

*Decision logged 2026-05-14 in Phase 7c (Engine Boundary Cleanup, HYBRID variant). CONTEXT.md: `.planning/phases/07c-engine-boundary-cleanup/07c-CONTEXT.md`. Code-level mirror: `BBTB/Packages/PacketTunnelKit/Docs/EngineAbstractionDecision.md`.*
