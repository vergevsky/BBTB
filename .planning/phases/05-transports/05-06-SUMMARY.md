# Wave 06 SUMMARY — Relocate ParsedXxx Types to VPNCore

**Status:** COMPLETE  
**Commit:** `3885b64`  
**Date:** 2026-05-13

## Objective

Break the potential cyclic dependency before Wave 7 (PoolBuilder coordinator):
- **Before:** `ParsedXxx` types lived in ConfigParser. Protocol packages (VLESSTLS, Trojan, etc.) would need to import these types → but they also need to be importable by ConfigParser → cycle.
- **After:** `ParsedXxx` types live in VPNCore. Both ConfigParser and Protocol packages import VPNCore (one-way DAG).

## Types Moved to VPNCore

All relocated to `BBTB/Packages/VPNCore/Sources/VPNCore/ParsedConfigs.swift`:

| Type | Kind | Notes |
|------|------|-------|
| `AnyParsedConfig` | enum (5 cases) | vlessReality / vlessTLS / trojan / shadowsocks / hysteria2 |
| `UnsupportedReason` | enum (6 cases) | includes .transportUnsupported |
| `ParsedVLESS` | struct | Reality branch; `networkType: String` retained |
| `ParsedVLESSTLS` | struct | TLS branch; `transport: TransportConfig` (D-05) |
| `ParsedTrojan` | struct | `transport: TransportConfig` (D-06) |
| `ParsedShadowsocks` | struct | SS-2022 + legacy AEAD |
| `ParsedHysteria2` | struct | `allowInsecure: Bool` D-08 R1 exception preserved |
| `ImportedServer` | enum (3 cases) | supported / unsupported / invalid |
| `ImportSource` | enum (5 cases) | pasteboard / subscriptionURL / jsonEndpoint / qrCode / multilineText |

## ConfigParser Files Modified

**Source files — declarations removed, `import VPNCore` added/retained:**
- `ImportedServer.swift` — all types removed; file now just re-exports via `import VPNCore`
- `TrojanURIParser.swift` — `ParsedTrojan` struct removed
- `VLESSURIParser.swift` — `ParsedVLESS` struct removed
- `ShadowsocksURIParser.swift` — `import VPNCore` added (uses `ParsedShadowsocks`)
- `Hysteria2URIParser.swift` — `import VPNCore` added (uses `ParsedHysteria2`)
- `PoolBuilder.swift` — `import VPNCore` added
- `StubParsers.swift` — `import VPNCore` added

**Test files — `import VPNCore` added:**
- `ClashYAMLParserTests.swift`
- `DualProtocolSmokeTests.swift`
- `IntegrationTests.swift`
- `PoolBuilderSingleOutboundTests.swift`
- `UniversalImportParserTests.swift`
- `VLESSURIParserTests.swift`

## Dependency Graph (Post Wave 6)

```
App (BBTB.xcodeproj)
  └─▶ AppFeatures
        └─▶ ConfigParser
              └─▶ VPNCore  ◀─── Protocols (VLESSTLS, Trojan, Shadowsocks, Hysteria2)
                                            │
                                            └── TransportRegistry
                                                  └─▶ VPNCore
```

One-way DAG. No cycles. PoolBuilder in Wave 7 can safely call Protocol packages without creating a cycle.

## Test Counts

| Package | Before | After | Delta |
|---------|--------|-------|-------|
| VPNCore | 38 | 41 | +3 (ParsedConfigsTests) |
| ConfigParser | 188 | 188 | 0 (baseline preserved) |
| TransportRegistry | 41 | 41 | 0 |
| AppFeatures | builds | builds | — |

## Zero Behavior Change Verified

- All 188 ConfigParser tests pass unchanged
- All 41 VPNCore tests pass (38 prior + 3 new smoke tests)
- All 41 TransportRegistry tests pass
- AppFeatures builds cleanly
- No transport block logic changed
- No PoolBuilder output changes

## Next Wave

**Wave 7 — PoolBuilder coordinator + per-protocol buildOutbound**

PoolBuilder will delegate outbound construction to Protocol packages
(VLESSRealityProtocol, VLESSTLSProtocol, TrojanProtocol, etc.) via
`TransportRegistry`. The cyclic dependency block is now resolved.
