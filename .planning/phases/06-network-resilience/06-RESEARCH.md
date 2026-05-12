# Phase 6: Network Resilience — Research

**Researched:** 2026-05-13
**Domain:** DNS strategy, IPv6 blackhole, auto-reconnect, failover (NET-01..11)
**Confidence:** HIGH (Apple NetworkExtension/Network framework APIs verified via Context7; sing-box 1.13 DNS schema verified via official docs; libbox 1.13.11 ObjC API verified directly from xcframework headers in repo)

---

## Summary

Phase 6 builds the **network reliability layer** on top of the Phase 1–5 tunnel: leak-proof DNS (DoH inside the tunnel, encrypted bootstrap with no Russian-DNS dependency), IPv6 blackhole (no leak path), `NWPathMonitor`-driven auto-reconnect with exponential backoff (3 attempts: 2s → 4s → 8s), and round-robin failover to the next subscription server after 3 failed reconnects to the current server.

Three architectural changes are non-trivial:

1. **DNS rewrite.** Current `PoolBuilder.dnsBlock()` hardcodes Yandex `tcp://77.88.8.8` as bootstrap (`[CITED: BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift:146]`). D-01 demands removal. The legacy sing-box DNS schema (used today: `address: "https://..."`, `address_resolver`, `detour`) is **deprecated in 1.12 and removed in 1.14** `[CITED: https://sing-box.sagernet.org/configuration/dns/server/legacy/]`. Phase 6 should keep legacy for now (still works in 1.13.11) but document the 1.14 migration as a follow-up; otherwise we'd be doing two schema rewrites simultaneously.
2. **IPv6 blackhole via `NEIPv6Settings`.** The trap: nil ipv6Settings = iOS lets IPv6 leak around the tunnel. The fix: instantiate `NEIPv6Settings(addresses:["fd00::1"], networkPrefixLengths:[128])`, add `NEIPv6Route.default()` to `includedRoutes`, and configure sing-box TUN inbound to include an IPv6 prefix in `address` plus `route_address: ["::/0"]`. The packets enter the tunnel and die there (no IPv6 outbound on the server side).
3. **Auto-reconnect runs in the main app, not the extension.** The PacketTunnelProvider extension is often suspended/killed by iOS on path changes; `sleep()`/`wake()` are unreliable on iOS `[CITED: NEPacketTunnelProvider doc + sing-box-for-apple canonical pattern]`. The retry state machine lives in `TunnelController` in the main app, driven by `NEVPNStatusDidChange` notifications and main-app `NWPathMonitor` + foreground/wake notifications. The extension itself only sets `self.reasserting = true/false` on tear-down/recovery if it detects internal failures (libbox `LibboxCommandClient` status subscription, see §6).

**Primary recommendation:** Build a new `VPNCore/DNSConfig.swift` struct passed through `ConfigImporter → PoolBuilder.buildSingBoxJSON(from:dnsConfig:)`, refactor `dnsBlock()` to take `DNSConfig` (remove the hardcoded `77.88.8.8`), build a separate `NetworkReachability` actor in MainScreenFeature that owns `NWPathMonitor` + wake/foreground observers, and extend `TunnelController` from a passive command runner into a stateful actor that owns the retry/failover state machine. Update `TunnelSettings.makeR6Safe` to emit IPv6 blackhole settings.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| DNS resolver config (DoH, bootstrap, AdBlock) | sing-box (inside extension) | sing-box TUN inbound | `dns` block in JSON is fully evaluated by sing-box; main app only authors the JSON |
| IPv6 blackhole at OS level | iOS/macOS NetworkExtension (extension) | — | `NEPacketTunnelNetworkSettings.ipv6Settings` configured in `openTun` (`TunnelSettings.makeR6Safe`); the OS makes the blackhole real |
| IPv6 blackhole at engine level | sing-box TUN inbound (extension) | — | sing-box's TUN inbound needs an IPv6 prefix in `address` for `getInterfaces`/socket-binding correctness even though no real v6 gateway exists upstream |
| NWPathMonitor (Wi-Fi↔LTE) | Main app `TunnelController` | Extension `ExtensionPlatformInterface` (already exists for libbox interface-update listener) | Trigger for retry state machine lives in main app where retries can be scheduled; extension's monitor only informs sing-box about default interface |
| Sleep/Wake/Foreground triggers | Main app | — | `UIApplication.didBecomeActiveNotification` / `NSWorkspace.didWakeNotification` only fire in main app; extension lifecycle is OS-managed |
| Retry state machine | Main app `TunnelController` (actor) | — | Needs cancellation, Task-isolated state, observable for UI banner; extension would lose this state across kills |
| Failover index | Main app `TunnelController` | SwiftData `ServerConfig` ordering | Persistent retry state belongs in the controller; the failover *target list* comes from SwiftData |
| Reconnect banner UI | MainScreenFeature `ReconnectBanner` | `MainScreenViewModel.reconnectState: ReconnectState` | UI binds to a published enum, controller drives state transitions |
| Local notification (3-fails) | Main app `UNUserNotificationCenter` | — | Extensions cannot present UN notifications directly `[CITED: WebFetch UNUserNotificationCenter, also Apple developer forums]` |

## Standard Stack

### Core (already in project — do not re-add)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `NetworkExtension` | iOS 18 / macOS 15 SDK | NEPacketTunnelProvider, NETunnelProviderManager, NEVPNStatus | Apple-only path for VPN clients |
| `Network` (Network.framework) | iOS 18 / macOS 15 SDK | `NWPathMonitor`, `NWPath`, `NWInterface.InterfaceType` | Apple's modern reachability API (Reachability.h is deprecated) |
| `libbox.xcframework` | 1.13.11 | sing-box engine, `LibboxCommandServer`, `LibboxCommandClient` | Already vendored at `BBTB/Vendored/libbox.xcframework` |
| `UserNotifications` | iOS 18 / macOS 15 SDK | `UNUserNotificationCenter` for local notifications on 3-fail | Built-in; no third-party deps |
| `SwiftUI`, `Combine`, `SwiftData` | — | Already in use | — |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `OSLog` | system | `Logger(subsystem: "app.bbtb.client.ios", category: "reconnect")` | Already used (`TunnelLogger`); add `reconnect` category |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Pure Swift retry state machine | Combine `Publisher` chain (debounce + retry) | Combine works but mixes badly with `async/await`; actor + `Task.sleep` is simpler and testable |
| `NWPathMonitor` in main app | `Reachability.h` from SystemConfiguration | Deprecated since iOS 12; do not use |
| Local `UNUserNotificationCenter` for 3-fail message | In-app banner only (no notification) | Banner only works if app is foregrounded; iOS users frequently leave VPN running with app backgrounded — need notification |
| Round-robin failover | Latency-weighted next-server | Phase 11 (smart auto-select v1.1); MVP wants simple, predictable |

**Installation:** No new packages required. All Apple frameworks; libbox already vendored.

**Version verification:**
- libbox: `1.13.11` confirmed at `BBTB/Vendored/libbox.xcframework/tvos-arm64/Libbox.framework/Headers/Libbox.objc.h` (this build's `LibboxCommandServer` + `LibboxCommandClient` API verified `[VERIFIED: codebase grep]`).
- sing-box config schema: 1.13 line `[VERIFIED: https://sing-box.sagernet.org/configuration/dns/server/legacy/ — "deprecated in sing-box 1.12.0 and removed in sing-box 1.14.0"]` — legacy DNS server form still works in 1.13.11 but is on the deprecation path.

---

## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01: Bootstrap DNS strategy (NET-01)**
- 3-tier: server IP first → AdGuard `94.140.14.14` second → Cloudflare `1.1.1.1` reserve.
- Remove hardcoded Yandex `tcp://77.88.8.8` from `PoolBuilder.dnsBlock()`.

**D-02: Tunnel DNS**
- Default — Cloudflare DoH (`https://cloudflare-dns.com/dns-query`).
- Override hierarchy: customDNS > adBlockEnabled (AdGuard) > Cloudflare default.

**D-03: Custom DNS (NET-02)**
- Text field "Свой DNS-сервер (IP)" in Advanced Settings DNS section.
- If filled → used instead of Cloudflare for tunnel DNS.
- If filled, AdBlock toggle is **ignored** (custom DNS wins).

**D-04: AdBlock DNS toggle (NET-03)**
- Toggle "Блокировать рекламу" in Advanced Settings DNS section.
- When on → tunnel DNS = AdGuard `94.140.14.14` (or AdGuard DoH endpoint).

**D-05: DNS scope (NET-04)**
- DNS settings are **global**, not per-server. Stored in `AppStorage` in `SettingsViewModel`.
- Per-server override → Phase 11 (ServerDetailView extension).

**D-06: IPv6 mode (NET-05..07)**
- Always block IPv6 when VPN is on (no adaptive detection in MVP).
- `NEIPv6Settings` configured (not nil) with `NEIPv6Route.default()` included.
- sing-box TUN inbound: include IPv6 prefix in `address` + `route_address: ["::/0"]`.

**D-07: Auto-reconnect (NET-08..10)**
- Up to 3 attempts, exponential backoff (2s → 4s → 8s).
- Triggers: `NWPathMonitor` Wi-Fi↔LTE; foreground/wake; sing-box ping timeout (via `LibboxCommandClient` status subscription).
- UI: existing `ReconnectBanner` reused.
- After 3 fails: local notification "Не удалось подключиться к [server]"; state → `.disconnected`.

**D-08: Failover (NET-11)**
- After 3 failed reconnects to current server → auto-switch to next in subscription list (round-robin). Banner: "Переключаюсь на резервный сервер".
- 1-server list → notify "Сервер недоступен", do not failover.
- Full cycle (all servers tried) → notify "Все серверы недоступны", stop.
- Reset failover index on manual disconnect or successful 30s+ session.

### Claude's Discretion

- Exact field names of `NEIPv6Settings` for blackhole → see §1.
- `NWPathMonitor` queue placement and throttling → see §3.
- Exact `DNSConfig` struct shape and `PoolBuilder` API → see §7 + §8.
- Retry state machine implementation (actor vs class) → see §9.
- sing-box disconnect signaling mechanism → see §6.

### Deferred Ideas (OUT OF SCOPE)

- Per-server DNS override → Phase 11.
- Adaptive IPv6 detection (runtime probe) → Phase 7+.
- Captive portal detection → Phase 7.
- Bootstrap-DNS-blocked recovery (e.g. AdGuard blocked) → Phase 7.

---

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| NET-01 | DoH inside tunnel to whitelisted providers | §7 sing-box DNS schema; §8 PoolBuilder rewrite |
| NET-02 | Custom DNS option | §7 priority logic; §8 `DNSConfig.customDNS` plumbing |
| NET-03 | AdBlock-via-DNS toggle | §7 AdGuard endpoint; §8 `DNSConfig.adBlockEnabled` |
| NET-04 | Encrypted bootstrap DNS | §7 D-01 3-tier (server IP → AdGuard → Cloudflare); §8 removal of Yandex |
| NET-05 | IPv6 tunneled by default | §1 NEIPv6Settings; §2 sing-box TUN — for Phase 6, "tunneled" means "blackholed inside the tunnel" (D-06) |
| NET-06 | IPv6 block fallback | §1, §2 — primary path in Phase 6 |
| NET-07 | IPv6 mode option in Advanced | Deferred to Phase 10 per ROADMAP; in Phase 6 it's just "block always" without UI toggle |
| NET-08 | Auto-reconnect on Wi-Fi↔LTE | §3 NWPathMonitor; §9 retry state machine |
| NET-09 | Auto-reconnect on sleep/foreground | §4 UIApplication; §5 NSWorkspace; §9 retry state machine |
| NET-10 | Auto-reconnect on IP change | §3 NWPathMonitor `pathUpdateHandler`; §6 libbox status subscription |
| NET-11 | Failover to next server | §10 TunnelController state machine extension |

---

## System Architecture Diagram

```
┌─────────────────────────────── Main App ─────────────────────────────────┐
│                                                                          │
│   ┌─ SettingsViewModel ───────────────────────────────────────┐         │
│   │  @AppStorage customDNS, adBlockEnabled                    │         │
│   └────────────────────┬──────────────────────────────────────┘         │
│                        │  read at connect time                            │
│                        ▼                                                  │
│   ┌─ ConfigImporter ──────────────────────────────────────────┐         │
│   │  provisionTunnelProfile(for: id)                          │         │
│   │    1. Build DNSConfig from SettingsViewModel              │         │
│   │    2. PoolBuilder.buildSingBoxJSON(parsed, dns:)          │         │
│   │    3. tunnelProvisioner.provisionTunnelProfile(...)       │         │
│   └────────────────────┬──────────────────────────────────────┘         │
│                        │ writes providerConfig                            │
│                        ▼                                                  │
│   ┌─ TunnelController (actor) ────────────────────────────────┐         │
│   │  - connect() / disconnect()  (existing)                   │         │
│   │  + ReconnectStateMachine                                  │         │
│   │     attempt: 0|1|2|3, backoff: 2s|4s|8s                   │         │
│   │  + FailoverIndex (ordered server list cursor)             │         │
│   │  + NetworkReachability (NWPathMonitor)                    │         │
│   │  + WakeForegroundObserver (UIScene/NSWorkspace)           │         │
│   │  + LibboxCommandClient subscriber (status, optional)      │         │
│   └────────────────────┬──────────────────────────────────────┘         │
│        publishes ▼                                                       │
│   ┌─ MainScreenViewModel ─────────────────────────────────────┐         │
│   │  @Published reconnectState: .idle | .retrying | .failover │         │
│   │      | .allFailed                                          │         │
│   └────────────────────┬──────────────────────────────────────┘         │
│                        ▼                                                  │
│   ┌─ ReconnectBanner UI ──────────────────────────────────────┐         │
│   │  shows retrying / failover / all-failed text             │         │
│   └───────────────────────────────────────────────────────────┘         │
│                                                                          │
│   NEVPNStatusDidChange ───┐                                              │
│   NWPathMonitor ──────────┼─► TunnelController.handle(...)               │
│   didBecomeActive / wake ─┘                                              │
└──────────────────────────────────────────────────────────────────────────┘
                                  │ manager.connection
                                  ▼
┌─────────────────────────── PacketTunnel Extension ──────────────────────┐
│                                                                          │
│  BaseSingBoxTunnel                                                      │
│    └─ ExtensionPlatformInterface                                        │
│         openTun → TunnelSettings.makeR6Safe                             │
│            ├─ NEIPv4Settings(default route)                             │
│            └─ NEIPv6Settings(blackhole route ::/0)   ← Phase 6 NEW      │
│                                                                          │
│  libbox sing-box engine                                                 │
│    └─ inbounds.tun                                                      │
│         address: ["198.18.0.1/28", "fd00::1/126"]    ← Phase 6 NEW      │
│         route_address: ["::/0"]                       ← Phase 6 NEW      │
│    └─ dns.servers                                                       │
│         dns-remote (DoH, dynamic provider)            ← Phase 6 NEW      │
│         dns-bootstrap (server IP or AdGuard plain)    ← Phase 6 NEW      │
│         dns-fakeip                                                       │
│    └─ outbounds → vless/trojan/etc (unchanged)                          │
└──────────────────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | File | Phase 6 Change |
|-----------|------|----------------|
| `SettingsViewModel` | `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:1-9` | Add `customDNS: String`, `adBlockEnabled: Bool` via `@AppStorage` |
| `AdvancedSettingsView` | new file under `SettingsFeature/` | DNS section: text field + toggle (UX-06 partial) |
| `DNSConfig` | new file `BBTB/Packages/VPNCore/Sources/VPNCore/DNSConfig.swift` | Struct: bootstrap list, tunnel DNS provider, adBlock |
| `PoolBuilder.dnsBlock()` | `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift:133-168` | Accept `DNSConfig`; remove `77.88.8.8`; emit dynamic bootstrap+remote |
| `PoolBuilder.buildSingBoxJSON` | same file lines 39-115 | Accept optional `dnsConfig:` param; thread to `dnsBlock` |
| `PoolBuilder.buildSingleOutboundJSON` | same file lines 127-129 | Same signature change |
| `ConfigImporter.provisionTunnelProfile` | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (and surrounding callsites) | Read `SettingsViewModel` at provision time, build `DNSConfig`, pass to `PoolBuilder` |
| `TunnelSettings.makeR6Safe` | `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift:42-61` | Set `settings.ipv6Settings` to blackhole (no longer nil) |
| `SingBoxConfigLoader.expandConfigForTunnel` | `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift:163-172` | Add IPv6 prefix to TUN `address` array + `route_address: ["::/0"]` |
| `TunnelController` | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift:1-55` | Convert to actor; add reconnect state machine + reachability + wake observers + failover cursor |
| `MainScreenViewModel` | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` | Subscribe to `TunnelController.reconnectState`; rename `needsReconnectForKillSwitch` mapping for new banner variants |
| `ReconnectBanner` | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift:7-36` | Add states: `.retrying(attempt: Int, delaySec: Int)`, `.failover(toServer: String)`, `.allFailed`. Keep existing kill-switch variant |
| `NetworkReachability` (new) | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/NetworkReachability.swift` | Wraps `NWPathMonitor`, debounces, publishes `.satisfied/.unsatisfied/.changed(from:to:)` events |
| Local-notification helper (new) | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/UserNotifications.swift` | Wraps `UNUserNotificationCenter.requestAuthorization` + `.add(request)` |
| `LibboxStatusSubscriber` (optional, new) | `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/LibboxStatusSubscriber.swift` | Optional: subscribe via `LibboxNewCommandClient` to status/connections messages for "ping timeout" signal. See §6 |

---

## §1 NEIPv6Settings — Blackhole on iOS / macOS

### Source of truth

`[CITED: https://developer.apple.com/documentation/networkextension/neipv6settings — Context7 query 2026-05-13]`

```swift
class NEIPv6Settings {
    init(addresses: [String], networkPrefixLengths: [NSNumber])
    var includedRoutes: [NEIPv6Route]?
    var excludedRoutes: [NEIPv6Route]?
}
class NEIPv6Route {
    init(destinationAddress: String, networkPrefixLength: NSNumber)
    class func `default`() -> NEIPv6Route    // returns ::/0 route
}
```

### Trap (D-06 referenced)

If `settings.ipv6Settings == nil`, iOS uses the **system default route table** for IPv6 — so any v6-reachable destination bypasses the tunnel entirely. The Apple convention is: **to control v6, you must configure it**. There is no implicit blackhole.

### Correct pattern (Phase 6)

```swift
// TunnelSettings.swift — Phase 6 rewrite
public static func makeR6Safe(_ inputs: Inputs) -> NEPacketTunnelNetworkSettings {
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: inputs.serverAddress)

    // IPv4 — unchanged from Phase 1
    let ipv4 = NEIPv4Settings(addresses: [inputs.tunnelIP],
                              subnetMasks: [inputs.tunnelSubnetMask])
    ipv4.includedRoutes = [NEIPv4Route.default()]
    // R6: NEVER set ipv4.destinationAddresses (P2P flag)
    settings.ipv4Settings = ipv4

    // IPv6 blackhole (D-06) — NEW in Phase 6
    // Address from ULA range (RFC 4193); no real upstream gateway. The route covers ::/0,
    // so all v6 traffic enters the tunnel and dies inside sing-box (since no v6 outbound).
    let ipv6 = NEIPv6Settings(addresses: ["fd00::1"], networkPrefixLengths: [NSNumber(value: 128)])
    ipv6.includedRoutes = [NEIPv6Route.default()]  // ::/0 → TUN
    ipv6.excludedRoutes = []
    settings.ipv6Settings = ipv6

    // DNS — unchanged
    let dns = NEDNSSettings(servers: inputs.dnsServers)
    dns.matchDomains = [""]
    settings.dnsSettings = dns

    settings.mtu = NSNumber(value: inputs.mtu)
    return settings
}
```

### iOS 18 / macOS 15 specifics

- All four properties (`addresses`, `networkPrefixLengths`, `includedRoutes`, `excludedRoutes`) are stable since iOS 9 / macOS 10.11 — no platform-version branching needed `[VERIFIED: Context7 query — "iOS 9.0+ iPadOS 9.0+ Mac Catalyst 13.1+ macOS 10.11+"]`.
- `NEIPv6Route.default()` returns `::/0` `[VERIFIED: Context7 — "default IPv6 route"]`.
- No known iOS 18 changes to this surface.

### Decision: ULA address `fd00::1/128`?

Why not `::1/128`? `::1` is link-local loopback; routing rules around `::1` are implementation-defined. ULA (`fd00::/8`) is the RFC 4193 unique-local prefix — safe to use as a synthetic tunnel-local address. sing-box's own canonical sample uses `fdfe:dcba:9876::1/126` `[CITED: sing-box docs Inbound TUN]`. Either works; pick ULA to match sing-box convention.

---

## §2 sing-box TUN — `inet6_address` / `route_address` in 1.13.11

### Source of truth

`[CITED: https://sing-box.sagernet.org/configuration/inbound/tun/ — fetched 2026-05-13]`

**Important schema migration:** As of sing-box 1.10, `inet6_address` / `inet6_route_address` are **deprecated** in favor of the unified `address` and `route_address` arrays. The deprecated fields were planned for removal in 1.12 but are still accepted in 1.13. Our project uses 1.13.11, so prefer the new unified syntax to avoid a forced migration in Phase 7.

### Old (deprecated, do NOT use)

```json
{
  "type": "tun",
  "tag": "tun-in",
  "inet4_address": "198.18.0.1/28",
  "inet6_address": "fdfe:dcba:9876::1/126",
  "inet6_route_address": ["::/0"]
}
```

### New (1.13 canonical, USE THIS)

```json
{
  "type": "tun",
  "tag": "tun-in",
  "address": ["198.18.0.1/28", "fdfe:dcba:9876::1/126"],
  "route_address": ["::/0"],
  "mtu": 1500,
  "auto_route": false,
  "stack": "gvisor"
}
```

### Patch to `SingBoxConfigLoader.expandConfigForTunnel` (`BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift:159-172`)

Current Phase 1 code injects:
```swift
inbounds.append([
    "type": "tun",
    "tag": "tun-in",
    "address": ["\(tunIP)/28"],
    "mtu": mtu,
    "auto_route": false,
    "stack": "gvisor",
])
```

Phase 6 patch:
```swift
inbounds.append([
    "type": "tun",
    "tag": "tun-in",
    "address": ["\(tunIP)/28", "fd00::1/126"],     // ← add IPv6 ULA
    "route_address": ["::/0"],                      // ← v6 blackhole inside TUN
    "mtu": mtu,
    "auto_route": false,
    "stack": "gvisor",
])
```

Keep idempotency check (`hasTun`) unchanged. The post-expand `validate(json:)` call (line 171 in `BaseSingBoxTunnel.swift`) is fine — the inbound is still `tun`, still on the allow-list.

### How sing-box handles the blackhole

1. v6 packet arrives at `utun` interface (iOS routes it because `NEIPv6Settings.includedRoutes = [::/0]`).
2. sing-box TUN inbound reads it from the FD (gvisor stack).
3. sing-box matches against `route.rules`. Since no outbound is configured to handle v6 destinations (our `vless`/`trojan` outbounds use `server` hostnames that get resolved IPv4-only via `dns.strategy: "ipv4_only"`), the packet falls through to the `direct` outbound — which on Apple platforms is bound to the physical interface via `IP_BOUND_IF` (see `ExtensionPlatformInterface.autoDetectControl`). The physical interface may or may not have v6; if it doesn't, the packet dies in the OS. If it does — **this is a leak.**

**Important nuance** (added to pitfalls): if the physical interface has IPv6 and `dns.strategy` is `prefer_ipv4` (not `ipv4_only`), AAAA queries could resolve and the outbound dials IPv6. To make blackhole watertight, the sing-box config must use `dns.strategy: "ipv4_only"` **and** `route.rules` should add an explicit drop rule for v6 destinations. See §7 final example.

---

## §3 NWPathMonitor in main app — Wi-Fi ↔ LTE detection

### Source

`[CITED: https://developer.apple.com/documentation/network/nwpathmonitor — Context7 + WebFetch 2026-05-13]`

### Trap A: queue placement

If `pathUpdateHandler` is called on the main queue, every minor radio twitch blocks the UI. Use a dedicated background queue.

### Trap B: callback frequency

iOS sends `pathUpdateHandler` callbacks for many micro-events: link-up/link-down, DNS-state changes, IPv6 RA refresh, "expensive" → "constrained" flips, captive-portal probe completions, *and* changes triggered by our own tunnel coming up/down (the tunnel adds an interface). Without throttling, a single Wi-Fi-to-LTE handoff produces 4–10 callbacks within 2–3 seconds. We must:

1. Throttle to ~1 callback per 500ms.
2. Compare logical state, not raw `NWPath` (which is non-Equatable).
3. **Ignore changes caused by our own tunnel.** Filter `availableInterfaces` to physical types (`.wifi`, `.cellular`, `.wiredEthernet`) — same trick already used in `ExtensionPlatformInterface.isPhysical` (`BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift:303-310`).

### Code example

```swift
// BBTB/Packages/AppFeatures/Sources/MainScreenFeature/NetworkReachability.swift — new file

import Foundation
import Network
import OSLog

public actor NetworkReachability {
    public enum Event: Equatable {
        case satisfied(physical: NWInterface.InterfaceType?)   // .wifi / .cellular / nil
        case unsatisfied                                       // truly no network
        case changed(from: NWInterface.InterfaceType?, to: NWInterface.InterfaceType?)
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.bbtb.reachability", qos: .userInitiated)
    private var lastPhysicalType: NWInterface.InterfaceType?
    private var lastEmittedAt: Date = .distantPast
    private let throttle: TimeInterval = 0.5

    public typealias Listener = @Sendable (Event) -> Void
    private var listener: Listener?

    public init() {}

    public func start(_ listener: @escaping Listener) {
        self.listener = listener
        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.handle(path) }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
        listener = nil
    }

    private func handle(_ path: NWPath) {
        let now = Date()
        guard now.timeIntervalSince(lastEmittedAt) >= throttle else { return }

        // Filter out our own TUN (.other) — only physical interfaces count
        let physical = path.availableInterfaces.first { iface in
            iface.type == .wifi || iface.type == .cellular || iface.type == .wiredEthernet
        }

        let event: Event
        switch path.status {
        case .unsatisfied, .requiresConnection:
            if lastPhysicalType != nil {
                event = .unsatisfied
            } else {
                return  // already unsatisfied, no-op
            }
        case .satisfied:
            if let phys = physical {
                if lastPhysicalType == nil {
                    event = .satisfied(physical: phys.type)
                } else if lastPhysicalType != phys.type {
                    event = .changed(from: lastPhysicalType, to: phys.type)
                } else {
                    return  // same type, no-op
                }
            } else {
                // satisfied but no physical iface? Treat as unsatisfied for our purposes.
                if lastPhysicalType != nil { event = .unsatisfied } else { return }
            }
        @unknown default:
            return
        }

        lastEmittedAt = now
        lastPhysicalType = physical?.type
        listener?(event)
    }
}
```

### Initialization point

In `MainScreenViewModel.init`, create one shared `NetworkReachability` and inject it into `TunnelController`. Lifecycle: `start()` on app launch; `stop()` only on app termination (the actor is cheap, no need to start/stop per-connection).

---

## §4 iOS wake / foreground notifications

### Source

`[CITED: https://developer.apple.com/documentation/uikit/uiapplication/didbecomeactivenotification — WebFetch 2026-05-13]`

### Notification semantics

| Notification | Fires on | iOS version |
|-------------|----------|-------------|
| `UIApplication.didBecomeActiveNotification` | App becomes foreground active; lock-screen unlock while app foregrounded; user switches back to app | all |
| `UIScene.willEnterForegroundNotification` | Scene transitions to foreground (slightly earlier than `didBecomeActive`) | iOS 13+ |
| `UIScene.didActivateNotification` | Scene becomes active | iOS 13+ |

### Recommendation

The project already uses `@Environment(\.scenePhase)` (`BBTB/App/iOSApp/BBTB_iOSApp.swift:91` and `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift:70`). Pattern: in `TunnelController`, subscribe to `scenePhase` transitions via a closure injected from `BBTBRootView`. When `.active` is reached, call `controller.handleForeground()`.

Why not `didBecomeActiveNotification` directly? Because scene-based apps may have multiple scenes (iPad Slide Over). Using `\.scenePhase` ensures we don't double-fire if iPad multitasking activates two scenes. For VPN reconnect this is mostly academic — the UX-relevant event is "user came back to look at the app" — but `scenePhase` is the modern idiom.

```swift
// In BBTBRootView (BBTB/App/iOSApp/BBTB_iOSApp.swift)
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .active {
        Task { await viewModel.importer.runIsSupportedUpgrade() }  // existing
        Task { await viewModel.tunnelController.handleForeground() }  // NEW Phase 6
    }
}
```

### Trap

`scenePhase == .active` also fires on initial app launch. The `TunnelController.handleForeground()` should be idempotent and self-check: "am I currently in `.connected` state? If yes — verify health (poll status); if disconnected, do nothing (user is opening app, not reconnecting)."

---

## §5 macOS wake notifications

### Source

`[CITED: https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification — WebFetch 2026-05-13]`

### Notification semantics

| Notification | Fires on |
|-------------|----------|
| `NSWorkspace.didWakeNotification` | System fully woke from sleep (display + CPU) |
| `NSWorkspace.willSleepNotification` | System about to sleep — useful to pre-emptively mark tunnel as suspended |
| `NSWorkspace.screensDidWakeNotification` | Display wake only (less reliable trigger; CPU may already be running) |
| `NSWorkspace.didChangeOcclusionStateNotification` | Window occlusion changed (irrelevant for VPN) |

### Recommendation

Use `didWakeNotification` only. Pattern:

```swift
// macOS branch in TunnelController.swift
#if os(macOS)
import AppKit

private func subscribeMacOSWake() {
    NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        Task { await self?.handleWake() }
    }
}
#endif
```

### Trap

Observer goes on `NSWorkspace.shared.notificationCenter`, **not** `NotificationCenter.default`. Putting it on `.default` silently never fires — this is a famous AppKit gotcha `[CITED: https://developer.apple.com/documentation/appkit/nsworkspace — Context7 docs]`.

### iOS-macOS unified API

There is no Apple-provided unified wake notification. Hide behind a small abstraction:

```swift
public protocol WakeNotifying: Sendable {
    func subscribe(_ handler: @escaping @Sendable () -> Void) -> Any  // returns observer for cancel
}

#if os(iOS)
public struct IOSScenePhaseWake: WakeNotifying { /* uses NotificationCenter.didBecomeActive */ }
#elseif os(macOS)
public struct MacOSWorkspaceWake: WakeNotifying { /* uses NSWorkspace.didWakeNotification */ }
#endif
```

---

## §6 sing-box / libbox — detecting tunnel-internal disconnect

### Source

`[VERIFIED: BBTB/Vendored/libbox.xcframework/tvos-arm64/Libbox.framework/Headers/Libbox.objc.h — direct read 2026-05-13]`

### Mechanism: `LibboxCommandClient`

libbox 1.13.11 ships a `LibboxCommandClient` API parallel to `LibboxCommandServer`. The server already runs inside our extension (`BaseSingBoxTunnel.commandServer` — line 60). A `CommandClient` can subscribe to events the server emits.

Available subscription topics (from header):

```objc
FOUNDATION_EXPORT const int32_t LibboxCommandClashMode;        // unused
FOUNDATION_EXPORT const int32_t LibboxCommandConnections;       // per-conn events
FOUNDATION_EXPORT const int32_t LibboxCommandGroup;             // urltest group switches
FOUNDATION_EXPORT const int32_t LibboxCommandLog;               // log lines
FOUNDATION_EXPORT const int32_t LibboxCommandStatus;            // memory, conn counts, traffic
```

The `LibboxStatusMessage` carries:
```
int64_t memory;
int32_t goroutines;
int32_t connectionsIn;
int32_t connectionsOut;
BOOL trafficAvailable;
int64_t uplink, downlink, uplinkTotal, downlinkTotal;
```

### What this gives us for Phase 6

`trafficAvailable == false` for an extended period (say >15 seconds) while `connectionsOut > 0` is a strong "outbound stalled" signal. Combined with `NEVPNStatus == .connected`, this lets us distinguish:

- "iOS thinks tunnel is up, but no real traffic flowing" → trigger reconnect.
- "iOS reports `.disconnected`" → trigger reconnect (already handled by `NEVPNStatusDidChange`).

### Implementation choice for Phase 6 MVP

**Recommended:** Implement two independent triggers and pick the most reliable one in the planner discussion:

1. **Simple (MVP):** Just rely on `NEVPNStatusDidChange` + `NWPathMonitor` + wake. No libbox subscription. When the OS reports `.disconnected`, retry. This catches 90% of real-world cases.

2. **Advanced (defer to Phase 7):** Add `LibboxCommandClient` status subscription for "silent stall" detection. Requires the client to talk to the extension's command server — over what transport? The header doesn't expose a TCP port on the command server (it's gomobile-internal IPC). The main app cannot reach it. **The CommandClient must run inside the extension itself** and either set `reasserting = true` (to trigger reconnect via NEVPNStatus path) or stop the tunnel.

For Phase 6, recommend **option 1** plus a hook stub in the extension (`LibboxStatusSubscriber.swift`) that's a no-op in v0.6 but documents the integration point for Phase 7.

### `reasserting` property usage

`[CITED: Context7 — NETunnelProvider reasserting]`

```swift
// Inside extension on detected stall
self.reasserting = true   // OS keeps tunnel alive, emits NEVPNStatus.reasserting to main app
// ...internal recovery attempt...
self.reasserting = false  // recovery succeeded
```

When `reasserting = true`, iOS broadcasts `NEVPNStatus.reasserting` to all main-app observers — this is the bridge between extension and main app for "I'm working on it". The existing `ExtensionPlatformInterface.clearDNSCache` (line 375) already uses `reasserting=true/false` during DNS settings reapply — same pattern.

---

## §7 sing-box DNS configuration (1.13.11)

### Source

`[CITED: https://sing-box.sagernet.org/configuration/dns/ — fetched 2026-05-13]`
`[CITED: https://sing-box.sagernet.org/configuration/dns/server/legacy/ — fetched 2026-05-13]`
`[CITED: https://sing-box.sagernet.org/configuration/dns/server/https/ — fetched 2026-05-13]`

### Schema status

Two DNS server formats coexist in sing-box 1.13.11:

| Format | Status in 1.13 | Status in 1.14 |
|--------|---------------|----------------|
| Legacy (`address: "https://..."`, `address_resolver`, `address_strategy`, `detour`) | Works, deprecated | **Removed** |
| New (`type: "https"`/`tcp`/`udp`, `server`, `server_port`, `path`, `domain_resolver`) | Works, recommended | Only option |

**Phase 6 decision:** Keep legacy format (matches existing `PoolBuilder.dnsBlock()` and template `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json`). Migration to new format is a Phase 7 follow-up; doing both DNS rewrite (D-01) and schema migration in one phase doubles the test surface. [ASSUMED: planner may decide to do both at once if test coverage is acceptable — see Open Questions]

### Final DNS block (D-01..D-04 priority resolved)

For a single-server pool with `serverIP = "1.2.3.4"`, default settings:

```json
{
  "dns": {
    "servers": [
      {
        "tag": "dns-remote",
        "address": "https://cloudflare-dns.com/dns-query",
        "address_resolver": "dns-bootstrap",
        "address_strategy": "ipv4_only",
        "detour": "vless-0"
      },
      {
        "tag": "dns-bootstrap",
        "address": "tcp://1.2.3.4",
        "detour": "direct",
        "strategy": "ipv4_only"
      },
      {
        "tag": "dns-fakeip",
        "address": "fakeip"
      }
    ],
    "rules": [
      { "outbound": "any", "server": "dns-bootstrap" },
      { "query_type": ["HTTPS", "SVCB"], "action": "predefined", "rcode": "NXDOMAIN" },
      { "query_type": ["A", "AAAA"], "server": "dns-fakeip" }
    ],
    "fakeip": {
      "enabled": true,
      "inet4_range": "100.64.0.0/10",
      "inet6_range": "fc00::/18"
    },
    "final": "dns-remote",
    "strategy": "ipv4_only",
    "independent_cache": true
  }
}
```

### Priority logic for `dns-remote.address`

```
customDNS non-empty?
  YES → address = "https://\(customDNS)/dns-query"        (assume user gave a DoH host; if user gave plain IP, see fallback below)
  NO  → adBlockEnabled?
          YES → address = "https://dns.adguard-dns.com/dns-query"
          NO  → address = "https://cloudflare-dns.com/dns-query"   (default)
```

**Fallback for plain-IP custom DNS:** if `customDNS` matches an IPv4 regex (and not a hostname), build `tcp://<ip>` instead of `https://<ip>/dns-query` because plain IPs don't have valid TLS certs for DoH. Document this in the UI text field placeholder: "IP-адрес или DoH-хост". Validation: reject input that's neither a valid IPv4 nor a valid hostname.

### Priority logic for `dns-bootstrap.address` (D-01 3-tier)

Bootstrap is used *only* to resolve the hostname in `dns-remote.address` (e.g., `cloudflare-dns.com` → IP). For our pool, we know the VLESS server IPs from `ServerConfig.host` (it's typically an IP, or a hostname that should ALSO be in the bootstrap chain).

```
Bootstrap chain (D-01):
  1. tcp://<serverIP>       — the server IP we already know; zero DNS lookup needed
  2. tcp://94.140.14.14     — AdGuard fallback
  3. tcp://1.1.1.1          — Cloudflare reserve
```

sing-box's legacy DNS server only supports ONE address per server tag. We have two options:

**Option A (simple):** A single `dns-bootstrap` with `address: "tcp://<serverIP>"`. If the IP is unreachable, the DoH chain fails. Acceptable for MVP because if the server IP is unreachable, the tunnel is dead anyway.

**Option B (defense-in-depth):** Three bootstrap servers; the routing rule uses an outbound `urltest`-like fallback. sing-box doesn't natively chain DNS servers, but rules can route different query types to different servers. **However** — for Phase 6, the simplest and safest approach is **Option A with one bootstrap = server IP, and the failover layer (D-08) handles "server IP unreachable" by switching servers, which rebuilds DNS bootstrap with the next server's IP.**

**Decision:** Option A. If we need true bootstrap fallback, that's a Phase 7 hardening task.

### AAAA handling

To match D-06 (block IPv6), the `dns.strategy: "ipv4_only"` is critical — it forces sing-box to never emit AAAA in response to user queries. Combined with the fakeip rule `query_type: ["A", "AAAA"]`, AAAA queries return a fakeip-range v4 address (clients get an A-fake for AAAA), which then routes through v4 outbound. No real AAAA leak.

---

## §8 `PoolBuilder.dnsBlock()` current state and required changes

### Current state

`[CITED: BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift:133-168]`

```swift
private static func dnsBlock(detour: String) -> [String: Any] {
    return [
        "servers": [
            ["tag": "dns-remote",  "address": "https://cloudflare-dns.com/dns-query",
             "address_resolver": "dns-bootstrap", "address_strategy": "ipv4_only",
             "detour": detour] as [String: Any],
            ["tag": "dns-bootstrap", "address": "tcp://77.88.8.8",     // ← Yandex hardcoded (D-01 violation)
             "detour": "direct", "strategy": "ipv4_only"] as [String: Any],
            ["tag": "dns-fakeip", "address": "fakeip"] as [String: Any],
        ],
        "rules": [
            ["outbound": "any", "server": "dns-bootstrap"],
            ["query_type": ["HTTPS", "SVCB"], "action": "predefined", "rcode": "NXDOMAIN"],
            ["query_type": ["A", "AAAA"], "server": "dns-fakeip"],
        ],
        "fakeip": ["enabled": true, "inet4_range": "100.64.0.0/10", "inet6_range": "fc00::/18"],
        "final": "dns-remote",
        "strategy": "ipv4_only",
        "independent_cache": true,
    ]
}
```

Same hardcoded `tcp://77.88.8.8` appears in `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json:17`. The template is only used for Phase 1 legacy single-config path; production path goes through `PoolBuilder.buildSingBoxJSON`. Still — for hygiene, the template should be updated too (or removed if no longer referenced; `grep` shows it's loaded via `SingBoxConfigLoader.loadVLESSRealityTemplate()` which is dead code in Phase 3+).

### Required Phase 6 API

```swift
// New file: BBTB/Packages/VPNCore/Sources/VPNCore/DNSConfig.swift
public struct DNSConfig: Equatable, Sendable {
    /// Address to use as bootstrap DNS (resolves dns-remote's hostname).
    /// D-01 priority: server IP → AdGuard → Cloudflare. Resolved by ConfigImporter at build time.
    public let bootstrapAddress: String           // e.g. "tcp://1.2.3.4" or "tcp://94.140.14.14"

    /// DoH endpoint or plain DNS for tunnel queries.
    /// D-02..D-04 priority: custom > adBlock > Cloudflare default.
    public let tunnelDNS: TunnelDNSProvider

    public enum TunnelDNSProvider: Equatable, Sendable {
        case cloudflare                            // "https://cloudflare-dns.com/dns-query"
        case adguard                               // "https://dns.adguard-dns.com/dns-query"
        case custom(address: String)               // user-provided; ConfigImporter validates IP-vs-host
    }

    public init(bootstrapAddress: String, tunnelDNS: TunnelDNSProvider) {
        self.bootstrapAddress = bootstrapAddress
        self.tunnelDNS = tunnelDNS
    }

    /// Default for tests / fallback when SettingsViewModel is unavailable.
    public static let `default` = DNSConfig(
        bootstrapAddress: "tcp://1.1.1.1",        // safe default; ConfigImporter overrides
        tunnelDNS: .cloudflare
    )

    public func dohAddress() -> String {
        switch tunnelDNS {
        case .cloudflare:        return "https://cloudflare-dns.com/dns-query"
        case .adguard:           return "https://dns.adguard-dns.com/dns-query"
        case .custom(let addr):  return addr   // ConfigImporter must validate before constructing
        }
    }
}

// Modified: PoolBuilder.swift
public static func buildSingBoxJSON(
    from supportedConfigs: [AnyParsedConfig],
    dns: DNSConfig = .default                      // NEW param, default keeps existing tests passing
) throws -> String { /* threads dns to dnsBlock(detour:dns:) */ }

private static func dnsBlock(detour: String, dns: DNSConfig) -> [String: Any] {
    return [
        "servers": [
            [
                "tag": "dns-remote",
                "address": dns.dohAddress(),
                "address_resolver": "dns-bootstrap",
                "address_strategy": "ipv4_only",
                "detour": detour
            ] as [String: Any],
            [
                "tag": "dns-bootstrap",
                "address": dns.bootstrapAddress,    // D-01: no more 77.88.8.8
                "detour": "direct",
                "strategy": "ipv4_only"
            ] as [String: Any],
            [
                "tag": "dns-fakeip",
                "address": "fakeip"
            ] as [String: Any],
        ],
        // rules/fakeip/final/strategy/independent_cache unchanged from current
        ...
    ]
}
```

### `ConfigImporter` call site

`ConfigImporter.importFromRawInput` (`BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:240`) currently does:

```swift
let poolJSON = try PoolBuilder.buildSingBoxJSON(from: supportedParsed)
```

Phase 6 patch:

```swift
let dnsConfig = buildDNSConfig(for: supportedParsed)   // see below
let poolJSON = try PoolBuilder.buildSingBoxJSON(from: supportedParsed, dns: dnsConfig)
```

Where `buildDNSConfig`:

```swift
private func buildDNSConfig(for parsed: [AnyParsedConfig]) -> DNSConfig {
    // Read SettingsViewModel at build time. Since ConfigImporter is non-MainActor,
    // read AppStorage via UserDefaults directly (same key).
    let defaults = UserDefaults.standard
    let customDNS = (defaults.string(forKey: "app.bbtb.customDNS") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let adBlock   = defaults.bool(forKey: "app.bbtb.adBlockEnabled")

    // D-01: prefer server IP for bootstrap
    let firstServerHost = parsed.first.map(extractHost) ?? "1.1.1.1"
    let bootstrap = looksLikeIPv4(firstServerHost)
                    ? "tcp://\(firstServerHost)"
                    : "tcp://94.140.14.14"                       // D-01 step 2: AdGuard fallback

    let provider: DNSConfig.TunnelDNSProvider
    if !customDNS.isEmpty {
        // D-03: custom wins
        provider = .custom(address: validateAndFormatCustomDNS(customDNS))
    } else if adBlock {
        provider = .adguard                                       // D-04
    } else {
        provider = .cloudflare                                    // D-02 default
    }

    return DNSConfig(bootstrapAddress: bootstrap, tunnelDNS: provider)
}

private func looksLikeIPv4(_ s: String) -> Bool {
    let parts = s.split(separator: ".")
    return parts.count == 4 && parts.allSatisfy { Int($0).map { $0 >= 0 && $0 <= 255 } == true }
}

private func validateAndFormatCustomDNS(_ s: String) -> String {
    // If looks like IP → tcp://; else assume DoH host → https://.../dns-query
    looksLikeIPv4(s) ? "tcp://\(s)" : "https://\(s)/dns-query"
}

private func extractHost(_ parsed: AnyParsedConfig) -> String {
    switch parsed {
    case .vlessReality(let v): return v.host
    case .vlessTLS(let v):     return v.host
    case .trojan(let t):       return t.host
    case .shadowsocks(let s):  return s.host
    case .hysteria2(let h):    return h.host
    }
}
```

**Plumbing note:** The same logic must run in `MainScreenViewModel.performToggleImpl` → `importer.provisionTunnelProfile(for: id)` path. `ConfigImporter.provisionTunnelProfile(for:)` is the Phase 3 single-server path; it also calls `PoolBuilder.buildSingleOutboundJSON`. That must also take `dns:`. So `provisionTunnelProfile(for:)` becomes `provisionTunnelProfile(for:, dnsOverride:)` or — cleaner — reads `DNSConfig` internally from settings + selected server. Recommend the latter (encapsulation).

---

## §9 Retry state machine — Swift pattern

### Recommendation: Actor with cancellable `Task`

```swift
// BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift — new file

import Foundation
import OSLog

public enum ReconnectStateMachineState: Equatable {
    case idle
    case retrying(attempt: Int, delaySeconds: Int)
    case failover(toServerName: String)
    case allFailed                           // 3 fails on every server in the list
}

public actor ReconnectStateMachine {
    public typealias AttemptHandler = @Sendable () async throws -> Date
    public typealias FailoverHandler = @Sendable () async throws -> (serverName: String, attempt: AttemptHandler)
    public typealias StateObserver = @Sendable (ReconnectStateMachineState) -> Void

    private var currentTask: Task<Void, Never>?
    private var state: ReconnectStateMachineState = .idle { didSet { observer?(state) } }
    private let observer: StateObserver?
    private let log = Logger(subsystem: "app.bbtb.client", category: "reconnect")

    // Tunable (D-07)
    public let backoffSeconds: [Int] = [2, 4, 8]
    public let maxAttemptsPerServer: Int = 3

    public init(observer: StateObserver?) {
        self.observer = observer
    }

    /// Drives one cycle: retry current server up to 3 times, then failover, then retry next, etc.
    /// `attempt` is called for each retry — it MUST `try await tunnel.connect()` and throw on failure.
    /// `failoverNext` is called after maxAttemptsPerServer fails to get the next attempt closure.
    /// `failoverNext` returns nil when no more servers remain → state becomes `.allFailed`.
    public func run(
        firstAttempt: @escaping AttemptHandler,
        failoverNext: @escaping @Sendable () async -> (serverName: String, attempt: AttemptHandler)?
    ) {
        cancel()
        currentTask = Task { [weak self] in
            await self?.driveLoop(attempt: firstAttempt, failoverNext: failoverNext)
        }
    }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        state = .idle
    }

    /// External event: the OS reports tunnel back up. Reset state.
    public func reportConnected() {
        cancel()
        state = .idle
    }

    private func driveLoop(
        attempt: AttemptHandler,
        failoverNext: @escaping @Sendable () async -> (serverName: String, attempt: AttemptHandler)?
    ) async {
        var currentAttempt = attempt
        var currentServerName: String? = nil

        while !Task.isCancelled {
            // Per-server retry budget
            for attemptIdx in 0..<maxAttemptsPerServer {
                if Task.isCancelled { return }
                let delay = backoffSeconds[min(attemptIdx, backoffSeconds.count - 1)]
                state = .retrying(attempt: attemptIdx + 1, delaySeconds: delay)
                log.notice("reconnect attempt \(attemptIdx + 1)/\(self.maxAttemptsPerServer) after \(delay)s")

                do { try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000) }
                catch { return }                                  // cancelled

                do {
                    _ = try await currentAttempt()
                    state = .idle
                    return                                        // success
                } catch {
                    log.error("attempt \(attemptIdx + 1) failed: \(error.localizedDescription)")
                }
            }

            // Exhausted attempts for current server — try failover
            guard let next = await failoverNext() else {
                state = .allFailed
                return
            }
            currentAttempt = next.attempt
            currentServerName = next.serverName
            state = .failover(toServerName: next.serverName)
            log.notice("failover to \(next.serverName)")
            // Small breath before first attempt of new server
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
        }
    }
}
```

### Testing

- Easy to test: inject a synthetic `attempt` closure that fails the first N calls then succeeds. Use `Task.sleep` with `nanoseconds: 0` in tests (mock the clock by injecting a `Clock` protocol if needed).
- Actor isolation prevents data races on `state`.
- Cancellation: `cancel()` synchronously kills the loop's `Task.sleep`.

### Trap: `observer` re-entry

`state` setter triggers observer; observer might call back into the actor → deadlock. Solution: observer is `@Sendable` and the actor only calls it during `didSet` *after* mutation; the observer must `Task { await ... }` if it wants to call back. The pattern is: observer publishes to a `@Published` on `MainScreenViewModel`, which is `@MainActor`-isolated. No deadlock as long as observer doesn't synchronously await the actor.

---

## §10 `TunnelController` evolution

### Current state

`[CITED: BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift:1-55]`

Stateless `final class TunnelController: TunnelControlling`:
- `connect() async throws -> Date` — loads first manager, sets enabled, calls `startVPNTunnel`, polls status 30 times with 1s sleep.
- `disconnect() async throws` — calls `stopVPNTunnel`, polls for `.disconnected` up to 5s.

No reconnect, no failover, no path monitoring.

### Phase 6 target

```swift
// BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift

import Foundation
import NetworkExtension
import SwiftData
import VPNCore
import OSLog

public protocol TunnelControlling: AnyObject, Sendable {
    func connect() async throws -> Date
    func disconnect() async throws
    /// Phase 6 — main-app starts reachability + observers + reconnect machine.
    func startReachability() async
    func stopReachability() async
}

public actor TunnelController: TunnelControlling {

    // MARK: existing API (preserved for Phase 1-5 compat)
    public func connect() async throws -> Date { /* unchanged from current */ }
    public func disconnect() async throws { /* unchanged from current */ }

    // MARK: Phase 6 additions
    public typealias ReconnectStateObserver = @Sendable (ReconnectStateMachineState) -> Void

    private let reachability: NetworkReachability
    private let stateMachine: ReconnectStateMachine
    private let provisioner: TunnelProvisioning              // injected from ConfigImporter
    private let failoverProvider: FailoverProviding          // ordered list from SwiftData
    private var nevpnObserver: NSObjectProtocol?
    private var wakeObserver: Any?
    private var manualDisconnectInProgress: Bool = false
    private var lastSuccessfulConnectAt: Date?

    public init(
        reachability: NetworkReachability,
        provisioner: TunnelProvisioning,
        failoverProvider: FailoverProviding,
        stateObserver: ReconnectStateObserver?
    ) {
        self.reachability = reachability
        self.provisioner = provisioner
        self.failoverProvider = failoverProvider
        self.stateMachine = ReconnectStateMachine(observer: stateObserver)
    }

    public func startReachability() async {
        await reachability.start { [weak self] event in
            Task { await self?.handleReachability(event) }
        }
        nevpnObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: nil
        ) { [weak self] note in
            Task { await self?.handleStatusChange(note) }
        }
        #if os(macOS)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.handleWake() }
        }
        #endif
    }

    public func stopReachability() async {
        await reachability.stop()
        if let obs = nevpnObserver { NotificationCenter.default.removeObserver(obs) }
        #if os(macOS)
        if let obs = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        #endif
    }

    public func handleForeground() async {
        // iOS scenePhase = .active hook from BBTBRootView
        guard !manualDisconnectInProgress else { return }
        if await currentVPNStatus() == .disconnected {
            return  // user disconnected manually or app starting up
        }
        // Lightweight liveness check — if libbox-based stall detector exists, ping it.
        // MVP: no-op (rely on NEVPNStatus path).
    }

    private func handleWake() async {
        // macOS NSWorkspace.didWakeNotification
        guard await currentVPNStatus() == .connected || (await currentVPNStatus()) == .reasserting else { return }
        // Wake often triggers NWPathMonitor anyway; defensive trigger.
        await triggerRecoveryIfNeeded(reason: "wake")
    }

    private func handleReachability(_ event: NetworkReachability.Event) async {
        switch event {
        case .satisfied, .changed:
            await triggerRecoveryIfNeeded(reason: "network-change")
        case .unsatisfied:
            // Don't preemptively tear down; let kill switch hold the line.
            break
        }
    }

    private func handleStatusChange(_ note: Notification) async {
        let status = await currentVPNStatus()
        switch status {
        case .connected:
            lastSuccessfulConnectAt = Date()
            await stateMachine.reportConnected()
            // D-08: reset failover index after 30s+ stable session — done in a deferred task.
            scheduleFailoverResetAfterStableSession()
        case .disconnected where !manualDisconnectInProgress:
            await triggerRecoveryIfNeeded(reason: "status-disconnected")
        default:
            break
        }
    }

    private func triggerRecoveryIfNeeded(reason: String) async {
        guard await currentVPNStatus() != .connected else { return }
        await stateMachine.run(
            firstAttempt: { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.connect()
            },
            failoverNext: { [weak self] in
                guard let self else { return nil }
                return await self.failoverProvider.nextServerAttempt(provisioner: self.provisioner)
            }
        )
    }

    // ... (manualDisconnect override sets manualDisconnectInProgress to suppress recovery during user-driven disconnect)
}
```

### `FailoverProviding` protocol

```swift
public protocol FailoverProviding: Sendable {
    /// Returns the next-server attempt closure, or nil when the cycle is exhausted.
    /// Implementation: reads SwiftData supported ServerConfigs, sorted by `id.uuidString`
    /// (same sort as ConfigImporter), tracks a cursor, increments on each call, resets
    /// to nil after a successful 30s+ session OR manual disconnect.
    func nextServerAttempt(provisioner: TunnelProvisioning) async -> (serverName: String, attempt: @Sendable () async throws -> Date)?
    func resetCycle() async
}
```

The implementation lives in `MainScreenFeature` (depends on SwiftData `ServerConfig` and the `provisioner`). It owns the `failoverIndex: Int` cursor and a `currentCycleServers: [UUID]` snapshot.

---

## §11 Local notifications (UNUserNotificationCenter)

### Source

`[CITED: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter — WebFetch 2026-05-13]`
`[CITED: Apple developer forums consensus — extensions cannot present UN notifications directly]`

### Authorization timing

**Recommendation: ask on demand**, not at first launch. The project's UX principle (CLAUDE.md) is "one tap to VPN" — surprise permission prompts during onboarding contradict that. Ask the first time auto-reconnect actually fails (state machine reaches `.allFailed`) and we want to notify the user. If the user denies, fall back to in-app banner only.

```swift
// BBTB/Packages/AppFeatures/Sources/MainScreenFeature/UserNotificationsHelper.swift
import UserNotifications

public enum UserNotificationsHelper {
    /// Schedules a local notification immediately. Requests auth on first call.
    @MainActor
    public static func notifyReconnectFailed(serverName: String?) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return                                  // user denied or system error; bail silently
            }
        }
        guard (await center.notificationSettings()).authorizationStatus == .authorized else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = L10n.notificationReconnectFailedTitle           // "VPN не удалось подключиться"
        content.body  = serverName.map { L10n.notificationReconnectFailedBody($0) }
                                  ?? L10n.notificationReconnectFailedBodyGeneric
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let req = UNNotificationRequest(identifier: "app.bbtb.reconnect-failed", content: content, trigger: trigger)
        try? await center.add(req)
    }
}
```

### Extension limitation

`UNUserNotificationCenter` works **in the main app**, not in the PacketTunnel extension. Since our retry state machine runs in the main app (§10), this is naturally fine.

### Localization

Add keys to `BBTB/Packages/Localization/Sources/Localization/L10n.strings.xcstrings`:
- `notificationReconnectFailedTitle` — "VPN не удалось подключиться"
- `notificationReconnectFailedBody("%@")` — "Не удалось подключиться к серверу %@"
- `notificationReconnectFailedBodyGeneric` — "Не удалось подключиться к серверу"

---

## §12 Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Reachability monitoring | Custom socket-poll loop / Reachability.h | `NWPathMonitor` (Network.framework) | Reachability.h is deprecated since iOS 12; NWPathMonitor handles cellular/Wi-Fi/Ethernet/constrained/expensive correctly |
| Detecting "tunnel up?" | Polling `manager.connection.status` in a Task | `NEVPNStatusDidChange` notification | Apple's first-class observable; polling wastes CPU and misses fast transitions |
| Wake on macOS | `IOPMSleepSystem` / `IOKit` SMC observers | `NSWorkspace.didWakeNotification` | High-level API; works without root |
| Local notifications scheduling | DispatchQueue + custom UI overlay | `UNUserNotificationCenter` | OS handles delivery, persistence, sound, badge, lock-screen presentation |
| DNS resolution inside tunnel | Custom DoH client (URLSession + DNS wire format) | sing-box `dns.servers` block | sing-box already implements DoH, DoT, fakeip, query type rules, EDNS client subnet — billion lines of Go we shouldn't replicate |
| Retry / backoff | Hand-rolled timers + flags | Swift actor + `Task.sleep` + cancellation | Built-in cancellation semantics; testable; race-free |
| Failover ordering | Random server selection | Round-robin via SwiftData fetch sorted by `id.uuidString` | Deterministic, testable, matches existing `ConfigImporter` sort convention `[CITED: ConfigImporter.swift:227]` |
| IPv6 leak prevention | Custom packet filter / NEFilterDataProvider | `NEIPv6Settings` with blackhole route | Filter Provider is separate entitlement + separate target; v6 blackhole at the routing layer is one struct |

**Key insight:** Every component the user gets in Phase 6 already exists either in `NetworkExtension`, `Network.framework`, `UserNotifications`, or sing-box's own DNS engine. Our work is **wiring and configuration**, not implementation.

---

## §13 Runtime State Inventory

This is **not a rename/refactor phase** — it's a feature addition. The classic checklist (stored data, OS-registered tasks, secrets) does not apply broadly. However, **two state-aware items** matter:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data (SwiftData) | `ServerConfig` — Phase 6 does not change schema; reads existing rows for failover ordering. No migration needed. | None |
| Stored data (UserDefaults / AppStorage) | `app.bbtb.killSwitchEnabled`, `app.bbtb.selectedServerID` exist. Phase 6 adds: `app.bbtb.customDNS` (String), `app.bbtb.adBlockEnabled` (Bool). | Add new keys; default values are empty/false |
| Live service config | The sing-box config JSON is rebuilt from scratch on every `provisionTunnelProfile` call — DNS changes apply on next reconnect. **No stored config to migrate.** | None |
| OS-registered state | `NETunnelProviderManager.providerConfiguration["configJSON"]` is overwritten on every import / connect. **The stored manager profile contains the old DNS block until next reprovision.** After Phase 6 deploys, user's existing tunnel profile still has Yandex bootstrap until they reconnect. | Add a `runDNSConfigRefresh()` migration in `BBTBRootView.onChange(scenePhase: .active)` (similar to existing `runIsSupportedUpgrade`) that rebuilds the active profile's `configJSON` with the new `DNSConfig`. Or simpler: force reprovision on next connect. |
| Secrets / env vars | Keychain stores VLESS UUIDs; no DNS secrets. | None |
| Build artifacts | No build/install state to refresh. | None |

**Migration plan for live `configJSON`:** Recommend a one-shot upgrade task in `ConfigImporter.runIsSupportedUpgrade()` (already a hook called from `BBTBRootView` on `scenePhase = .active`, `BBTB/App/iOSApp/BBTB_iOSApp.swift:93`). Add a follow-up `runDNSConfigUpgrade()` that:

1. Loads the current `NETunnelProviderManager`.
2. Reads its `providerConfiguration["configJSON"]`.
3. If the JSON still contains `"address":"tcp://77.88.8.8"` → rebuild from `supportedConfigs` with new `DNSConfig` and re-save.

---

## §14 Common Pitfalls

### Pitfall 1: nil `NEIPv6Settings` causes IPv6 leak

**What goes wrong:** Setting `settings.ipv6Settings = nil` leaves iOS using the system default route for IPv6. Sites reachable by v6 (Google, Facebook, Cloudflare) bypass the tunnel; the user's real public v6 address leaks.

**Why it happens:** Apple's API requires you to **opt in** to v6 control. The default is "OS does what it likes". Wi-Fi networks at residential ISPs in Russia mostly don't have v6; LTE often does. The leak appears only when the user is on LTE.

**How to avoid:** Always configure `NEIPv6Settings` (see §1). Even if you want to "block v6 entirely", you must instantiate the object and route `::/0` into the TUN.

**Warning signs:** `ipv6-test.com` shows a non-tunneled v6 address; `whoer.net` IPv6 row is your real ISP.

---

### Pitfall 2: NWPathMonitor fires during our own tunnel bring-up

**What goes wrong:** When the OS adds the `utun` interface (because we called `setTunnelNetworkSettings`), `NWPathMonitor` in the main app fires `pathUpdateHandler` with the new interface set. If our reconnect logic naively reads "interfaces changed → trigger reconnect", we'll reconnect-during-connect, causing an infinite loop.

**Why it happens:** `NWPathMonitor` doesn't distinguish "user-relevant network changes" from "our own VPN interface changed".

**How to avoid:** Filter `availableInterfaces` to physical types only (`isPhysical` from `ExtensionPlatformInterface.swift:303`). Track `lastPhysicalType` and emit `.changed(...)` only when the physical type changes (not when only counts change). Throttle to 500ms minimum between events.

**Warning signs:** `TunnelLogger` shows recurring "network-change recovery" events when the user is on a stable Wi-Fi.

---

### Pitfall 3: Manual disconnect races with auto-reconnect

**What goes wrong:** User taps "Disconnect". The view model calls `tunnel.disconnect()`. While the OS is propagating `.disconnecting → .disconnected`, the `NEVPNStatusDidChange` handler in `TunnelController` sees `.disconnected`, thinks the tunnel died unexpectedly, and kicks off the reconnect state machine. The user sees the VPN immediately try to reconnect.

**Why it happens:** No distinguishing signal between "user wanted out" and "OS terminated the tunnel".

**How to avoid:** `TunnelController` maintains a `manualDisconnectInProgress: Bool` flag. Set true at the start of `disconnect()`, clear after the status reaches `.disconnected` for at least 1s. The `NEVPNStatusDidChange` handler must check the flag before triggering recovery (see `handleStatusChange` in §10).

**Warning signs:** Tapping Disconnect causes an immediate "Переподключение..." banner.

---

### Pitfall 4: Failover index reset timing

**What goes wrong:** D-08 says "Reset failover index on manual disconnect or 30s+ successful session". If reset happens *every time* status becomes `.connected`, we lose the round-robin guarantee — e.g., the first server reconnects briefly, fails again, but we restart from index 0 instead of advancing.

**Why it happens:** "Connected" can be transient (handshake succeeds, then ALPN fails 5s later).

**How to avoid:** Reset the failover cursor only after **30s of stable `.connected`** (verified by `lastSuccessfulConnectAt`). Track this with a deferred `Task` that fires after 30s and re-checks status; if still `.connected`, reset; otherwise leave the cursor alone.

**Warning signs:** Server A flaps; user observes the app re-trying server A 4+ times in 2 minutes instead of moving to server B.

---

### Pitfall 5: Bootstrap DNS chicken-and-egg when server is a hostname

**What goes wrong:** Some subscription configs give a hostname (e.g. `vps.provider.com`) instead of an IP. D-01 step 1 ("use server IP for bootstrap") doesn't apply — we don't have the IP yet. If we fall to AdGuard `94.140.14.14` and AdGuard is blocked at the user's ISP, the VLESS server hostname never resolves, the tunnel never comes up.

**Why it happens:** Subscriptions vary in format; some give hostnames, some IPs. Our existing parsers (`extractHost`) return whatever the URI carries.

**How to avoid:** Two options:
1. **Pre-resolve at import time.** In `ConfigImporter.importFromRawInput`, after parsing, do a synchronous `getaddrinfo()` for each hostname and store the resolved IP alongside in `ServerConfig` (new field `resolvedIP: String?`). Pros: bootstrap always has a numeric IP; cons: rebuilds on every reconnect since IPs can rotate.
2. **Accept the AdGuard / Cloudflare fallback.** If the server entry is a hostname, bootstrap = AdGuard; if blocked, bootstrap = Cloudflare. Accept that some users will need to pre-resolve manually.

**Recommendation:** Option 2 for Phase 6 simplicity. Document the case in code comments. Phase 7 (Anti-DPI suite) can revisit with pre-resolved IPs cached in SwiftData.

**Warning signs:** Users report "imported subscription, tunnel never connects, no other config from same subscription works either".

---

### Pitfall 6: sing-box config size — DNS additions push past iOS 256KB limit

**What goes wrong:** `PoolBuilder` already truncates to 50 servers (`PoolBuilder.swift:40`) to stay under the iOS NETunnelProviderProtocol 256KB providerConfiguration limit `[CITED: code comment "RESEARCH §9.5 — iOS 256KB limit"]`. Adding multiple DNS entries with long custom URIs (e.g. NextDNS DoH path with 64-char path components) could push some users over.

**How to avoid:** DNS additions in Phase 6 are minimal — 3 server entries per config (`dns-remote`, `dns-bootstrap`, `dns-fakeip`). Estimated +400 bytes per config. With 50-server cap, +20KB total. Stay well under 256KB. **No action needed** unless the truncation cap is raised in a future phase.

**Warning signs:** Logs show `tunnelProvisioner.provisionTunnelProfile` fails with "providerConfiguration exceeded maximum size".

---

### Pitfall 7: `LibboxCommandClient` requires a working command channel

**What goes wrong:** If we add a libbox status subscriber to detect "no traffic but tunnel says connected" (§6), the subscriber needs to connect to the extension's `LibboxCommandServer`. If the channel is misconfigured (wrong port, wrong path), the subscriber silently never receives events — and we think the tunnel is healthy when it's stalled.

**How to avoid:** **Defer this to Phase 7** (per §6 recommendation). For Phase 6, rely on `NEVPNStatusDidChange` + `NWPathMonitor` + wake notifications. These cover 90% of "user-perceptible" disconnects without the extra complexity.

**Warning signs:** Phase 7 — if we add this and it silently fails, the user reports "tunnel says connected but Safari hangs" without any auto-recovery.

---

### Pitfall 8: `scenePhase` triggers `runIsSupportedUpgrade` on every wake — don't add expensive reconnect logic to the same path

**What goes wrong:** `BBTBRootView.onChange(scenePhase)` in `BBTB/App/iOSApp/BBTB_iOSApp.swift:91` runs `runIsSupportedUpgrade` on every `.active` transition (including initial launch, lock-screen unlock, app switch). Adding a heavy reconnect check there would run on every screen unlock.

**How to avoid:** `handleForeground()` must self-check: if `NEVPNStatus == .connected`, do nothing. If `.disconnected` and user didn't manually disconnect — trigger recovery. If `.connecting`/`.reasserting` — leave alone (already in progress).

**Warning signs:** Battery drain logs show NWPathMonitor / NEVPNConnection access every time user unlocks phone.

---

### Pitfall 9: Custom DNS field accepts garbage — sing-box config validation fails silently

**What goes wrong:** User types "8.8.8.8 google" in the Custom DNS field. The string flows through to `DNSConfig.custom("8.8.8.8 google")` → `dohAddress() = "https://8.8.8.8 google/dns-query"` (invalid URL with space). sing-box rejects the JSON, the tunnel fails to start, and the user sees a generic error.

**How to avoid:** Validate input at the UI layer (the Advanced Settings text field) AND at the model layer (`ConfigImporter.buildDNSConfig`). Validation: must be a valid IPv4 address or a valid hostname (RFC 1123 subset: letters/digits/hyphens, max 253 chars). Reject otherwise. Show inline error in the text field.

**Warning signs:** "Connection failed" alert appears with no usable error detail.

---

### Pitfall 10: Wake notification fires before network is actually ready

**What goes wrong:** macOS `NSWorkspace.didWakeNotification` fires the moment the CPU resumes — but Wi-Fi may take 2-5 seconds to associate after wake. If we immediately trigger reconnect, the very first attempt fails (no DNS resolution possible), counter advances to attempt 2, etc.

**How to avoid:** After wake, **wait for `NWPathMonitor` to report `.satisfied`** before scheduling the first reconnect attempt. The state machine should consume reachability events in addition to wake events — wake alone doesn't trigger a connect; wake + reachable-satisfied does. In code: `handleWake()` just sets a "wake pending" flag; the next `handleReachability(.satisfied)` clears the flag and triggers recovery.

**Warning signs:** macOS users report "VPN takes 30s to come back after laptop wakes" (one failed attempt + 4s backoff + retry).

---

## §15 Code Examples

### Building the sing-box DNS block from `DNSConfig`

```swift
// PoolBuilder.swift — Phase 6 rewrite (extracted)
// Source: sing-box docs (legacy DNS server form, still supported in 1.13.11)

private static func dnsBlock(detour: String, dns: DNSConfig) -> [String: Any] {
    return [
        "servers": [
            [
                "tag": "dns-remote",
                "address": dns.dohAddress(),
                "address_resolver": "dns-bootstrap",
                "address_strategy": "ipv4_only",
                "detour": detour
            ] as [String: Any],
            [
                "tag": "dns-bootstrap",
                "address": dns.bootstrapAddress,
                "detour": "direct",
                "strategy": "ipv4_only"
            ] as [String: Any],
            [
                "tag": "dns-fakeip",
                "address": "fakeip"
            ] as [String: Any],
        ] as [Any],
        "rules": [
            ["outbound": "any", "server": "dns-bootstrap"] as [String: Any],
            ["query_type": ["HTTPS", "SVCB"], "action": "predefined", "rcode": "NXDOMAIN"] as [String: Any],
            ["query_type": ["A", "AAAA"], "server": "dns-fakeip"] as [String: Any],
        ] as [Any],
        "fakeip": [
            "enabled": true,
            "inet4_range": "100.64.0.0/10",
            "inet6_range": "fc00::/18",
        ] as [String: Any],
        "final": "dns-remote",
        "strategy": "ipv4_only",
        "independent_cache": true,
    ]
}
```

### IPv6 blackhole in `TunnelSettings.makeR6Safe`

```swift
// TunnelSettings.swift — Phase 6 patch
public static func makeR6Safe(_ inputs: Inputs) -> NEPacketTunnelNetworkSettings {
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: inputs.serverAddress)

    let ipv4 = NEIPv4Settings(addresses: [inputs.tunnelIP],
                              subnetMasks: [inputs.tunnelSubnetMask])
    ipv4.includedRoutes = [NEIPv4Route.default()]
    settings.ipv4Settings = ipv4

    // Phase 6 — D-06 IPv6 blackhole
    let ipv6 = NEIPv6Settings(addresses: ["fd00::1"], networkPrefixLengths: [NSNumber(value: 128)])
    ipv6.includedRoutes = [NEIPv6Route.default()]   // ::/0 → TUN
    ipv6.excludedRoutes = []
    settings.ipv6Settings = ipv6

    let dns = NEDNSSettings(servers: inputs.dnsServers)
    dns.matchDomains = [""]
    settings.dnsSettings = dns

    settings.mtu = NSNumber(value: inputs.mtu)
    return settings
}
```

### TUN inbound with IPv6 (in `SingBoxConfigLoader.expandConfigForTunnel`)

```swift
// SingBoxConfigLoader.swift — Phase 6 patch (replace lines 162-171)
if !hasTun {
    inbounds.append([
        "type": "tun",
        "tag": "tun-in",
        "address": ["\(tunIP)/28", "fd00::1/126"],    // ← Phase 6: add IPv6 ULA
        "route_address": ["::/0"],                     // ← Phase 6: v6 blackhole
        "mtu": mtu,
        "auto_route": false,
        "stack": "gvisor",
    ])
    root["inbounds"] = inbounds
}
```

### `NWPathMonitor` actor wrapper

See full code in §3.

### `ReconnectStateMachine` actor

See full code in §9.

### Subscribing to NEVPNStatus changes in main app

```swift
// TunnelController.swift — partial
private var nevpnObserver: NSObjectProtocol?

private func subscribeNEVPNStatus() {
    nevpnObserver = NotificationCenter.default.addObserver(
        forName: .NEVPNStatusDidChange,
        object: nil,
        queue: nil
    ) { [weak self] _ in
        Task { await self?.handleStatusChange() }
    }
}

private func currentVPNStatus() async -> NEVPNStatus {
    let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
    return managers.first?.connection.status ?? .invalid
}
```

### Local notification on 3-fail

See full code in §11.

---

## §16 State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `SystemConfiguration.SCNetworkReachability` | `Network.framework` `NWPathMonitor` | iOS 12 / macOS 10.14 (2018) | Use `NWPathMonitor`; SCNetworkReachability is soft-deprecated |
| sing-box legacy DNS server (`address: "https://..."`) | New typed DNS servers (`type: "https"`) | sing-box 1.12.0 deprecation, 1.14.0 removal | Phase 6 stays legacy; Phase 7 should migrate |
| sing-box `inet6_address` / `inet6_route_address` | Unified `address` + `route_address` arrays | sing-box 1.10 deprecation | Phase 6 uses unified syntax |
| `UIBackgroundTask` for long-running app work | Background Tasks framework (`BGTaskScheduler`) | iOS 13 | N/A — VPN runs in extension; main app does not need background tasks for reconnect |
| Manual KVO of `NEVPNConnection.status` | `NEVPNStatusDidChange` notification | iOS 8 | Use notification, not KVO (KVO was iOS 8 path) |

**Deprecated / outdated:**

- `NWUDPSession.hasBetterPath` — deprecated; use `nw_connection_set_better_path_available_handler` (Network framework). Not directly relevant for Phase 6 (we don't manage UDP sessions in main app), but worth noting.
- `Reachability.h` (CocoaPods/Reachability) — do not use.

---

## §17 Validation Architecture

> nyquist_validation is enabled (`workflow.nyquist_validation: true` in `.planning/config.json` — verified).

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (Phase 4+ tests use `@Test`/`#expect`; legacy XCTest in some packages) |
| Config file | per-package `Package.swift` + Xcode test targets in `BBTB.xcodeproj` |
| Quick run command | `swift test --package-path BBTB/Packages/AppFeatures --filter <Suite>` |
| Full suite command | `cd BBTB && xcodebuild test -workspace BBTB.xcworkspace -scheme BBTB-iOS -destination 'platform=iOS Simulator,name=iPhone 15'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| NET-01 | DNSConfig builds correct sing-box JSON for cloudflare default | unit | `swift test --package-path BBTB/Packages/ConfigParser --filter PoolBuilderDNSConfigTests` | ❌ Wave 0 |
| NET-02 | `customDNS` user input → tunnel DNS uses custom; rejected on garbage input | unit | `swift test --package-path BBTB/Packages/AppFeatures --filter ConfigImporterDNSTests` | ❌ Wave 0 |
| NET-03 | `adBlockEnabled=true` + customDNS empty → AdGuard DoH | unit | same as NET-02 | ❌ Wave 0 |
| NET-04 | bootstrap = server IP if numeric; falls back to AdGuard for hostname | unit | same | ❌ Wave 0 |
| NET-05 | sing-box config has IPv6 in TUN inbound address + route_address `::/0` | unit | `swift test --package-path BBTB/Packages/PacketTunnelKit --filter SingBoxConfigLoaderIPv6Tests` | ❌ Wave 0 |
| NET-06 | `TunnelSettings.makeR6Safe` produces non-nil ipv6Settings with default route | unit | `swift test --package-path BBTB/Packages/PacketTunnelKit --filter TunnelSettingsIPv6Tests` | ❌ Wave 0 |
| NET-07 | (Phase 10 — deferred) | manual | n/a | n/a |
| NET-08 | NetworkReachability emits `.changed(from:wifi, to:cellular)` after debounce | unit | `swift test --package-path BBTB/Packages/AppFeatures --filter NetworkReachabilityTests` | ❌ Wave 0 |
| NET-09 | TunnelController.handleForeground is no-op when manually disconnected | unit | `swift test --package-path BBTB/Packages/AppFeatures --filter TunnelControllerStateTests` | ❌ Wave 0 |
| NET-10 | ReconnectStateMachine retries 3x with 2/4/8s backoff | unit (with injected clock) | `swift test --package-path BBTB/Packages/AppFeatures --filter ReconnectStateMachineTests` | ❌ Wave 0 |
| NET-11 | After 3 fails, FailoverProviding returns next server; cursor advances | unit | `swift test --package-path BBTB/Packages/AppFeatures --filter FailoverProviderTests` | ❌ Wave 0 |
| NET-05+06 leak | dnsleaktest.com shows only tunnel-side resolvers | manual | n/a | manual |
| NET-05+06 leak | ipv6-test.com shows no public v6 OR shows tunnel-side v6 | manual | n/a | manual |
| NET-08 device | Toggle Wi-Fi off → cellular kicks in → tunnel reconnects within 10s | manual on iPhone | n/a | manual |
| NET-09 device | Lock phone for 60s → unlock → tunnel resumes | manual on iPhone | n/a | manual |

### Sampling Rate

- **Per task commit:** `swift test --package-path BBTB/Packages/<relevant>` for the package touched
- **Per wave merge:** Full SwiftPM `swift test` from `BBTB/` directory
- **Phase gate:** Full Xcode `xcodebuild test` + manual leak tests (dnsleaktest, ipv6-test) before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderDNSConfigTests.swift` — covers NET-01, NET-04
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConfigImporterDNSTests.swift` — covers NET-02, NET-03
- [ ] `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderIPv6Tests.swift` — covers NET-05
- [ ] `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/TunnelSettingsIPv6Tests.swift` — covers NET-06
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/NetworkReachabilityTests.swift` — covers NET-08
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift` — covers NET-09 (manual disconnect race)
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReconnectStateMachineTests.swift` — covers NET-10 (3-retry exp backoff with injected clock)
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/FailoverProviderTests.swift` — covers NET-11

**Existing infra reused:** ServerListFeatureTests uses in-memory `ModelContainer` (see `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/*Tests.swift`) — same pattern works for FailoverProvider tests. PoolBuilder tests exist; extend with DNS-specific assertions.

---

## §18 Security Domain

> `security_enforcement` is enabled by default. CLAUDE.md and project decisions emphasize R1/R6 invariants.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no (no Phase 6 auth surface) | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes | Custom DNS field — validate IPv4 / RFC 1123 hostname (Pitfall 9) |
| V6 Cryptography | yes | DoH transport security; use `cloudflare-dns.com` (Let's Encrypt-signed cert) — sing-box handles TLS validation |
| V7 Error Handling | yes | DNS misconfig must throw clear user-facing error (not silent fail in extension) |
| V8 Data Protection | no | DNS preferences are not sensitive (no secrets) |
| V11 Business Logic | yes | Reconnect/failover state must be tamper-proof from outside the actor |
| V12 File / Resources | no | — |
| V13 API | no | — |
| V14 Configuration | yes | sing-box JSON validated post-build (`SingBoxConfigLoader.validate`) — Phase 6 must extend validator to check DNS block has no listen-on-localhost servers (already covered by inbound allow-list) |

### Known Threat Patterns for {iOS NetworkExtension + sing-box stack}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Custom DNS field XSS / command injection in sing-box JSON | Tampering | Strict input validation (IPv4 regex or RFC 1123 hostname); reject otherwise. Pitfall 9 above. |
| Bootstrap DNS used by ТСПУ to enumerate connecting VPN users | Information Disclosure | D-01 prefers server IP (zero DNS lookup); AdGuard fallback is российский-friendly but non-state |
| IPv6 leak revealing real ISP IP | Information Disclosure | D-06 blackhole — see §1, Pitfall 1 |
| `LibboxCommandClient` exposed network port | Tampering / Elevation | libbox CommandServer uses gomobile-internal IPC (no TCP port); SingBoxConfigLoader continues to reject `clash_api`/`v2ray_api`/HTTP inbounds (R1 invariant) |
| Reconnect storm — attacker forces 1000 reconnects/min via fake network changes | Denial of Service | 500ms NWPathMonitor throttle (§3); max-3-attempts cap before failover (D-07); 30s stable-session requirement before failover-cursor reset (D-08) |
| Local notification spoofing | Spoofing | iOS UN notifications carry app identifier; user sees BBTB icon; no malicious actor can post in our name without app entitlement |
| ULA `fd00::/8` collision with user's home LAN | Tampering (routing) | ULA is RFC 4193 site-local; we use `fd00::1/126` inside the tunnel; user's LAN ULA prefix (if any) is a different `fd**::/64` per RFC 4193 random assignment — collision astronomically unlikely |

**R1 invariant check:** Phase 6 DNS additions introduce no new inbound types. `dns.servers` with `address: "fakeip"` is a DNS server type, not an inbound listener. The `SingBoxConfigLoader.validate` allow-list (`tun`, `direct`) is sufficient.

**R6 invariant check:** `TunnelSettings.makeR6Safe` Phase 6 patch adds `ipv6Settings` but does NOT touch `ipv4.destinationAddresses`. R6 invariant (no P2P flag) preserved. The DEBUG assertion `InterfaceFlagsInspector.assertNoPointToPointOnUtun` still applies and should still pass.

---

## §19 Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| libbox.xcframework | sing-box engine | ✓ | 1.13.11 | — (vendored) |
| iOS Simulator (for tests) | unit tests | ✓ | iOS 18+ (Xcode 16) | — |
| Real iPhone (iOS 18+) | manual UAT NET-08, NET-09 | (user's device) | — | Skip device tests in CI |
| dnsleaktest.com | manual leak validation | ✓ (web) | — | — |
| ipv6-test.com | manual leak validation | ✓ (web) | — | — |
| LTE-enabled device with Wi-Fi for Wi-Fi↔LTE testing | NET-08 UAT | (user's iPhone) | — | Manually toggle Wi-Fi in dev simulator approximates the event |

No missing dependencies block execution.

---

## §20 Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Legacy sing-box DNS server format (`address: "https://..."`, `address_resolver`, `detour`) still works in 1.13.11 | §7 | If sing-box silently rejects: tunnel fails to start. Test in Wave 0 by building a Phase 6 JSON and running `SingBoxConfigLoader.validate` + integration test. Backup plan: migrate to new `type: "https"` format in same wave. |
| A2 | `dns.adguard-dns.com` is the canonical AdGuard DoH host (vs `dns.adguard.com` or others) | §7, D-04 | Wrong host = AdBlock toggle does nothing or fails to resolve. Verify by quick `curl https://dns.adguard-dns.com/dns-query?dns=...` before locking in. |
| A3 | `NEIPv6Settings` with `fd00::1/128` address + `::/0` route reliably blackholes traffic on iOS 18 and macOS 15 (no path-discovery quirks) | §1, §14 Pitfall 1 | Unverified on device. Manual UAT step: run `ipv6-test.com` after Phase 6 ships. |
| A4 | sing-box TUN `address: ["...IPv4/28", "fd00::1/126"]` + `route_address: ["::/0"]` is the correct 1.13 invocation for IPv6 blackhole | §2 | If sing-box requires `inet6_address` (deprecated form) for our 1.13.11 build: tunnel start fails. Test in Wave 0 with a real validate+expand pipeline; if fails, revert to deprecated `inet6_address`/`inet6_route_address` form (still works in 1.13). |
| A5 | `NWPathMonitor`'s `pathUpdateHandler` reliably fires within 1-2s of a Wi-Fi→LTE handoff in iOS 18 | §3, §14 Pitfall 2 | If iOS batches notifications differently in 18: NET-08 UAT fails to reconnect within reasonable time. Mitigation: also subscribe to `NEVPNStatusDidChange` — the OS itself usually tears the tunnel on path loss, which is the more reliable trigger. |
| A6 | `LibboxCommandClient` for stall detection is NOT needed for Phase 6 (rely on NEVPNStatus + reachability) | §6 | Some "silent stall" scenarios (sing-box thinks fine, no traffic) won't auto-recover. User must manually disconnect. Acceptable for MVP per §6 recommendation; revisit Phase 7. |
| A7 | UNUserNotificationCenter auth prompt on first failure (vs at onboarding) is the right UX | §11 | User may dismiss the prompt and never see it again — losing the "all servers failed" notification. Mitigation: in `.allFailed` state, show a stronger in-app banner that doesn't require notification permission. |
| A8 | sing-box `dns.strategy: "ipv4_only"` makes AAAA queries return fakeip-range IPv4 (no leak path) | §7 | If strategy doesn't constrain fakeip output: AAAA queries could escape the fakeip pool. Wave 0 test: build a Phase 6 JSON, run sing-box in simulator (or dev environment), send AAAA query, confirm response is in `100.64.0.0/10`. |
| A9 | Phase 6 won't push providerConfiguration past 256KB | §14 Pitfall 6 | If a future config combo (e.g. 50 servers × 600 bytes each) hits the cap with DNS additions, provisioning silently fails. Add a Wave 0 test that asserts JSON size ≤ 200KB for a synthetic 50-config pool. |
| A10 | `runIsSupportedUpgrade`-style migration hook is the right place to refresh existing managers' DNS config | §13 Runtime State | If the existing manager's `providerConfiguration` is overwritten correctly only on next reprovision: user must manually disconnect and reconnect after Phase 6 ships to get the new DNS. Acceptable degradation if migration hook complicated; document in release notes. |
| A11 | sing-box 1.13.11 in our `libbox.xcframework` actually corresponds to upstream sing-box 1.13.x (not a fork or rebrand) | §7, §2 | If our libbox vendor (forked? snapshot?) differs from upstream schema, the docs we cite may be misleading. Trace: check `BBTB/Vendored/libbox.xcframework/Info.plist` and any `VERSION` file. Mitigation: validate config locally in Wave 0 via the actual extension's validator. |

---

## §21 Open Questions

1. **Should Phase 6 do the 1.13→1.14 sing-box DNS schema migration at the same time as removing Yandex hardcode?**
   - What we know: Legacy format works in 1.13.11; will break in 1.14.
   - What's unclear: When will the project upgrade libbox to 1.14+? If soon (e.g., Phase 7), doing both DNS changes at once is efficient but doubles risk. If much later (Phase 10+), keep them separate.
   - Recommendation: **Keep legacy format in Phase 6.** Add a follow-up task to ROADMAP for "DNS schema migration to sing-box 1.14 typed servers" when libbox bumps. Reduces Phase 6 test surface.

2. **Should we pre-resolve hostname-form server entries to IPs at import time?**
   - What we know: D-01 wants server IP as first bootstrap. Some subscriptions give hostnames.
   - What's unclear: How many real-world subscriptions in our target audience give hostnames vs IPs?
   - Recommendation: Defer to Phase 7. In Phase 6, fallback to AdGuard for hostname entries. Document in code.

3. **Where does `NWPathMonitor` live — in `MainScreenViewModel.init` or as a singleton in `BBTBRootView`?**
   - What we know: One global instance is enough; lifecycle = app lifetime.
   - What's unclear: Whether tests should be able to inject a mock. ViewModel-injection style is the project's convention.
   - Recommendation: Create `NetworkReachability` actor as a property of `TunnelController` (injected at init). Tests inject a fake `NetworkReachability` via DI. App-level singleton created in `BBTB_iOSApp.init` and passed down.

4. **For the local notification on `.allFailed`, what's the deep-link target?**
   - What we know: D-07 says "push notification" but Phase 6 deferred actual push (FCM/APNs) to v1.6. We use local notifications instead.
   - What's unclear: When user taps the notification, should it open the app on a specific screen?
   - Recommendation: Just open the app (no deep link in Phase 6). Phase 9 (Deep Links) can add `bbtb://reconnect-failed` if needed.

5. **Sing-box config caching — does `libbox` itself cache anything that survives `commandServer.closeService()`?**
   - What we know: `BaseSingBoxTunnel.stopTunnel` closes the service and nils platform interface.
   - What's unclear: If `cache_file` is implicitly enabled by sing-box defaults (we explicitly disallow `cache_file` in R1 validator), does sing-box still keep an in-memory DNS cache that survives reload?
   - Recommendation: Phase 6 doesn't depend on cache state. The `dns.independent_cache: true` we already emit ensures cache isolation per-server. No action needed.

---

## §22 Sources

### Primary (HIGH confidence)

- **Context7 — Apple NetworkExtension**: `mcp__context7__get-library-docs /websites/developer_apple_networkextension`
  - NEIPv6Settings: https://developer.apple.com/documentation/networkextension/neipv6settings
  - NEIPv6Route: https://developer.apple.com/documentation/networkextension/neipv6route
  - NEVPNStatus: https://developer.apple.com/documentation/networkextension/nevpnstatus/*
  - NEVPNStatusDidChange: https://developer.apple.com/documentation/networkextension/nevpnstatusdidchangenotification
  - NETunnelProvider.reasserting: https://developer.apple.com/documentation/networkextension/netunnelprovider/reasserting
- **Apple docs (WebFetch)**:
  - https://developer.apple.com/documentation/network/nwpathmonitor
  - https://developer.apple.com/documentation/uikit/uiapplication/didbecomeactivenotification
  - https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification
  - https://developer.apple.com/documentation/usernotifications/unusernotificationcenter
- **sing-box docs (WebFetch)** — fetched 2026-05-13:
  - https://sing-box.sagernet.org/configuration/dns/
  - https://sing-box.sagernet.org/configuration/dns/server/legacy/
  - https://sing-box.sagernet.org/configuration/dns/server/https/
  - https://sing-box.sagernet.org/configuration/dns/fakeip/
  - https://sing-box.sagernet.org/configuration/inbound/tun/
- **libbox.xcframework headers (direct file read)**:
  - `BBTB/Vendored/libbox.xcframework/tvos-arm64/Libbox.framework/Headers/Libbox.objc.h` — `LibboxCommandClient`, `LibboxStatusMessage`, `LibboxCommandStatus` constants, `LibboxConnectionEvents`
- **Project source files (direct read)**:
  - `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift`
  - `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift`
  - `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift`
  - `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift`
  - `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift`
  - `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json`
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift`
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift`
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift`
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift`
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift`
  - `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift`
  - `BBTB/App/iOSApp/BBTB_iOSApp.swift`
  - `BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift`
  - `BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift`
- **Wiki references**:
  - `wiki/dns-strategy.md` — high-level strategy
  - `wiki/dns-pipeline-decisions.md` — Phase 1 W5 fakeip pattern
  - `wiki/ipv6-strategy.md` — IPv6 leak prevention rationale
  - `wiki/security-gaps.md` (R6, R10) — referenced by `TunnelSettings.swift` comments

### Secondary (MEDIUM confidence)

- General Swift Concurrency patterns (actor + Task + cancellation) — Swift evolution proposals SE-0306, SE-0304 (training-data knowledge, verified against current Swift 6 docs).
- Apple developer forums consensus on "UNUserNotificationCenter in PacketTunnelProvider" — `[CITED: WebFetch UNUserNotificationCenter explanation + canonical sing-box-for-apple repository pattern]`. Not from Apple's official docs but consistent with extension sandbox limitations.

### Tertiary (LOW confidence)

- Specific AdGuard DoH host (`dns.adguard-dns.com`) — A2 in Assumptions Log; manual verification needed before Phase 6 freeze.

---

## §23 Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All Apple-shipped, no third-party packages. libbox 1.13.11 already vendored.
- Architecture: HIGH — Patterns match Apple's documentation directly; no exotic constructs.
- IPv6 blackhole: HIGH-MEDIUM — API verified, but on-device behavior needs UAT step (A3).
- DNS rewrite: HIGH — Schema understood; A1, A2, A8 are minor unknowns easily validated in Wave 0.
- Auto-reconnect / retry / failover: HIGH for pattern, MEDIUM for tuning (3-attempt × exp-backoff numbers from D-07 are reasonable but not measured against ТСПУ behavior in real Russia conditions).
- Pitfalls: HIGH — 10 documented, traceable to either Apple docs, project source, or sing-box behavior.

**Research date:** 2026-05-13
**Valid until:** 2026-06-13 (30 days; revisit if libbox is upgraded to 1.14+ or if iOS 19 / macOS 16 ships)
