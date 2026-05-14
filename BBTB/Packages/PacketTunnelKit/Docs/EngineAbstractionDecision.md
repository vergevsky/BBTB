# Engine Abstraction — Decision Document

**Status:** HYBRID boundary cleanup applied (2026-05-14, Phase 7c). NO `protocol TunnelEngine` introduced yet.

**Decision authority:** User confirmation 2026-05-14 «Окей, делаем. Вариант B» based on Codex deep research thread `019e2802-ed23-7f21-bd6a-138edea62528` (production iOS VPN multi-engine architecture survey).

---

## Current state (2026-05-14)

BBTB ships with **mono-engine architecture**: one `NEPacketTunnelProvider` extension, one sing-box runtime via `libbox.xcframework` v1.13.11. Six in-scope protocols (VLESS+Reality, VLESS+TLS+Vision, Trojan, Shadowsocks-2022, Hysteria2, TUIC v5) are exposed through sing-box outbound types; no second engine exists.

**Engine boundary in code:** sing-box-specific files are contained under `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/`:
- `BaseSingBoxTunnel.swift` — sing-box tunnel base class
- `ExtensionPlatformInterface.swift` — libbox callback implementations (`LibboxPlatformInterfaceProtocol`, `LibboxCommandServerHandlerProtocol`)
- `SingBoxConfigLoader.swift` — sing-box config validation + R10 expandConfigForTunnel
- `Resources/SingBoxConfigTemplate.vless-reality.json` — Reality-specific bundled template

Engine-agnostic utilities stay at top level (applicable to any future engine):
- `AppGroupContainer.swift`
- `TunnelSettings.swift` (R6 `makeR6Safe(_:)` invariant)
- `TunnelLogger.swift`
- `ExternalVPNStopMarker.swift` (Phase 6d App Group marker)
- `InterfaceFlagsInspector.swift`
- `PlatformSpecific/iOS.swift` + `macOS.swift`

---

## Why no `protocol TunnelEngine` yet

Codex deep research surveyed production iOS VPN apps with potential multi-engine support (Amnezia, Hiddify, IVPN, Mullvad, Proton, WireGuard.app, OpenVPNAdapter). Key empirical findings:

| App | Multi-engine pattern observed |
|---|---|
| **Hiddify-iOS** | Mega-engine sing-box (same as BBTB) — no second engine, no abstraction layer. |
| **Amnezia VPN** | Switch-dispatch in `PacketTunnelProvider.startTunnel` over `providerConfiguration` keys (`ovpn`/`wireguard`/`xray`), with protocol-specific extension files (`+OpenVPN.swift`, `+WireGuard.swift`, `+Xray.swift`). NOT a `protocol TunnelEngine` abstraction. |
| **IVPN iOS** | Multiple `NEPacketTunnelProvider` extension targets (one per heavy engine: openvpn-tunnel-provider, wireguard-tunnel-provider). |
| **Mullvad iOS** | Single WireGuard family + transports (no OpenVPN engine on iOS — removed Jan 15, 2026). |
| **ProtonVPN iOS** | WireGuard + Stealth only (OpenVPN delegated to external app). |

**Critical observation:** No production iOS VPN app uses a pre-built `protocol TunnelEngine` abstraction with a single implementation. Either they're mono-engine (Hiddify/BBTB style) OR they use simple switch-dispatch (Amnezia) OR separate extensions (IVPN). Premature `protocol TunnelEngine` would encode sing-box assumptions that may not fit a real second engine when one arrives.

**Three Strikes rule (Robert Martin):** abstraction is appropriate after the third concrete instance, not before the second.

---

## Triggers for introducing `protocol TunnelEngine`

Introduce abstraction when **at least one** of these is true:

1. **Buildable iOS spike for a second engine** — AmneziaWG (`amneziawg-apple` library) or OpenVPN-Partout reaches a state where it actually starts/stops inside a real `NEPacketTunnelProvider` extension with a real config. NOT just «we might add it someday».

2. **Two engines need to coexist in one TestFlight build** — not «in the future maybe», but a concrete product requirement that ships within one release cycle.

3. **`PacketTunnelProvider` gains a second concrete lifecycle path** — different setup/teardown/error semantics that can no longer share the current sing-box-shaped code path.

4. **Engine lifecycle becomes the dominant complexity** — currently sing-box config generation and sing-box JSON validation are the dominant complexity. When engine bring-up/teardown/health-check overtakes config generation in lines-of-code and cognitive load, abstraction value rises.

---

## When triggered: pattern selection

Choose between two production-proven paths (Codex Q5 recommendation):

### Path A — Amnezia-style switch-dispatch (cheaper, less isolation)

- One `NEPacketTunnelProvider` extension shell.
- `startTunnel` reads `providerConfiguration` keys, dispatches to engine-specific entry point.
- Engine-specific files live in protocol-specific subdirectories (e.g., `SingBox/`, `AmneziaWG/`).
- Lifecycle code per engine is independent; no formal `TunnelEngine` protocol required.
- **Pros:** simplest to add; no premature abstraction; matches Amnezia VPN production.
- **Cons:** no crash isolation between engines (Go panic in one engine kills the whole extension); difficult to test engines in isolation.

### Path B — IVPN-style separate `NEPacketTunnelProvider` extension targets (more isolation)

- One extension target per heavy engine (e.g., `BBTB-Tunnel-iOS-SingBox`, `BBTB-Tunnel-iOS-AmneziaWG`).
- Each extension has its own provisioning profile, App Group access, entitlements.
- iOS schedules each as a separate process — true crash isolation.
- **Pros:** crash isolation; engines can use different memory profiles; failures don't cross-contaminate.
- **Cons:** provisioning + App Group + logging + TestFlight complexity multiplied; user sees two VPN profiles in Settings → VPN unless `manager.localizedDescription` discipline; disproportionate for friends-and-family TestFlight.

### Decision criteria between A and B:

- If the second engine is **memory-light** (~10MB additional RSS) and **doesn't run a Go runtime** → Path A.
- If the second engine **embeds a Go runtime** (e.g., `amneziawg-go` via `amneziawg-apple`) OR has known crash patterns → Path B (crash isolation matters).
- For our 50-friends TestFlight specifically: Path A is acceptable until proven otherwise on real device memory measurements.

---

## Anti-patterns (do not do these)

- ❌ **Generic-named classes while there is one engine.** Don't name things `VPNEngine`, `CoreManager`, `ProtocolService`. Use sing-box-specific names: `SingBoxConfigBuilder`, `SingBoxRuntimeOptions`, `SingBoxLifecycle`. (Generic naming with one implementation = pretending the abstraction exists; future engine will fight the wrong shape.)
- ❌ **Pre-built `TunnelEngine` protocol with one implementation.** No production iOS VPN does this. Codex couldn't find a single example. The shape will be wrong.
- ❌ **Placeholder `AmneziaWGEngine.swift` / `OpenVPNEngine.swift` files** without real implementation. They become dead code and lie about what's actually shippable.
- ❌ **Refactoring `BaseSingBoxTunnel` to «engine-agnostic shape»** before there's a second engine. Save that refactor for when it's informed by real second-engine constraints.

---

## Migration breadcrumbs

When you arrive at the trigger condition, here's what to look at first:

1. **Read this document** for context on why we deferred.
2. **Re-read** Codex thread `019e2802-ed23-7f21-bd6a-138edea62528` for the original survey of production iOS VPN architectures.
3. **For AmneziaWG specifically:** Codex thread `019e27d9-f49b-7f72-abb0-9b0ccdb94aae` covers `amneziawg-apple` library state, Go bridge gotchas, AWG 2.0 config format, server-side support matrix, real-device memory measurement requirements.
4. **For OpenVPN specifically:** Codex thread `019e26d8-0397-7fa0-91b3-312e7e3e3ca9` covers OpenVPN status in Russia 2026 + obfuscation techniques + Partout library state.
5. Inspect:
   - `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/BaseSingBoxTunnel.swift` for the current `NEPacketTunnelProvider` lifecycle.
   - `BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift` and `.../macOS/PacketTunnelProvider.swift` for the extension shells.
   - `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/ExtensionPlatformInterface.swift` for libbox callback patterns (memory- and threading-sensitive code that another engine's runtime must match).

---

## Long-term memory location

This decision is also documented in:
- `wiki/engine-abstraction-decision-2026.md` — project-level decision log (parallel to `openvpn-deferral-2026.md`, `wireguard-deferral-2026.md`, `amneziawg-deferral-2026.md`).
- `.planning/PROJECT.md` § R20 row — Phase 7 closure context.
- `.planning/phases/07c-engine-boundary-cleanup/07c-CONTEXT.md` — Phase 7c discuss-phase output.

---

*Document created: 2026-05-14, Phase 7c (Engine Boundary Cleanup, HYBRID variant).*
*Authority: Codex deep research thread `019e2802-ed23-7f21-bd6a-138edea62528` + user confirmation.*
*Revisit: when at least one trigger condition is true (see «Triggers» section).*
