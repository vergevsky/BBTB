---
phase: 05-transports
plan: 07
status: complete
commit: d9038a3
verified: 2026-05-13
---

# Wave 7 SUMMARY — PoolBuilder coordinator + buildOutbound per protocol + App registration

## What was accomplished

### 5 Protocol packages now have `buildOutbound`

Each protocol package gained `public static func buildOutbound(from:transport:tag:) -> [String: Any]`:

| Package | Transport-aware | Notes |
|---------|-----------------|-------|
| VLESSTLS | YES (uses TransportRegistry) | ALPN h2-strip, R1 insecure=false hardcoded |
| Trojan | YES (uses TransportRegistry) | ALPN h2-strip, SNI fallback for empty WS host |
| VLESSReality | NO (D-03: ignored, Reality-only TCP) | Mirrors existing PoolBuilder semantics |
| Shadowsocks | NO (D-16: no transport layer) | R1 trivial — no TLS block |
| Hysteria2 | NO (D-16: QUIC-based) | D-08 R1 EXCEPTION — insecure=parsed.allowInsecure |

**R1 invariant**: `tls.insecure: false` hardcoded in VLESSTLS and Trojan; D-08 EXCEPTION isolated to Hysteria2 package with multi-layer comment + test + type-level enforcement.

**ALPN h2-strip**: WS transport strips "h2" from alpn array (Phase 2 W4 backward-compat invariant), fallback to ["http/1.1"] if array becomes empty.

### PoolBuilder coordinator pattern

**Before (Wave 6)**: 5 private static methods (`buildVLESSOutbound`, `buildVLESSTLSOutbound`, etc.) = ~170 lines

**After (Wave 7)**: 5 one-liner calls to protocol packages + dnsBlock = ~30 lines in the switch

Lines delta: `-170` private builders, `+7` coordinator switch (net -163 lines in PoolBuilder.swift).

### TransportOverride.swift (new file in ConfigParser)

`public func applyTransportOverride(_ parsed: AnyParsedConfig, _ override: TransportConfig?) -> AnyParsedConfig`:
- `.vlessTLS` and `.trojan`: replaces `transport` field with override (fresh struct construction)
- `.vlessReality`, `.shadowsocks`, `.hysteria2`: returns unchanged (D-03/D-16)
- Uses fresh struct construction to avoid requiring `let` → `var` migration in ParsedConfigs.swift

### Bootstrap registration (Pitfall 8 mitigation)

Both `BBTB_iOSApp.swift` and `BBTB_macOSApp.swift` register all 5 handlers after ProtocolRegistry block:
```
TCPTransportHandler, WSTransportHandler, HTTPTransportHandler,
HTTPUpgradeTransportHandler, GRPCTransportHandler
```
Registration happens before `provisionTunnelProfile` can be called — Pitfall 8 satisfied.

### ConfigImporter Wave 8 stub

`private func transportOverride(for cfg: ServerConfig) -> TransportConfig?` returns `nil`.
Wave 8 replaces with `cfg.transportOverride` (SwiftData field + lightweight migration).
`applyTransportOverride` is called in both explicit-selection and auto-mode paths.

## Test counts

| Package | Before | After | Delta | Notes |
|---------|--------|-------|-------|-------|
| VPNCore | 41 | 41 | 0 | 1 skip (Keychain CLI) |
| TransportRegistry | 41 | 42 | +1 | bootstrap smoke test |
| VLESSTLS | 7 | 19 | +12 | BuildOutboundTests |
| Trojan | 7 | 16 | +9 | BuildOutboundTests |
| ConfigParser | ~194 | 200 | +6 | TransportOverride (6) + WS integration smoke (+1 in PoolBuilderTests) |
| AppFeatures | 49 | 49 | 0 | all existing pass |
| **Total** | **~339** | **~367** | **+28** | |

All tests pass. R1 invariant test (`test_nonHy2_outbounds_neverHaveInsecureTrue`) PASS.

## Key invariants verified

- VLESSTLS.buildOutbound(.tcp) → no `transport` key in outbound dict
- VLESSTLS.buildOutbound(.ws("/buy","cdn")) → `transport: {type:ws, path:/buy, headers:{Host:cdn}}`
- VLESSTLS.buildOutbound(.grpc("svc")) → `transport: {type:grpc, service_name:svc}` (snake_case)
- Trojan.buildOutbound(.ws("/x","")) → SNI substituted as Host header (Phase 2 backward-compat)
- ALPN h2-strip applied for WS in both VLESSTLS and Trojan
- D-08 R1 EXCEPTION: Hysteria2 is the ONLY package with `insecure: parsed.allowInsecure`
- D-03: VLESSReality buildOutbound ignores transport param (Reality-only TCP)
- D-16: Shadowsocks + Hysteria2 buildOutbound ignores transport param

## Next

Wave 8 — UI plan: ServerDetailView transport picker + ServerConfig.transportOverride SwiftData
lightweight migration + ServerListSheet chevron + Wave 7 stub replacement with real field read.
