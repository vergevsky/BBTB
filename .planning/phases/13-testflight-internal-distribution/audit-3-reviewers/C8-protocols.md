# C8 — Protocols (Codex 5.5)
**Baseline:** fb2ff54
**Total findings:** 3 (0/1/2/0)

## Critical
No critical findings found in this Protocols pass. The Plan 05 template-path closures remain closed: the six protocol builders are dictionary-based `buildOutbound` implementations, not raw JSON substitution paths.

## High
### C8'-3-001: VLESS+TLS is the only TLS protocol whose pre-build gate does not enforce non-empty SNI
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift:291`, `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift:71`
- **Dimension:** Security / R1 strict TLS identity
- **Description:** T-B11 moved parsed-config validation to `PoolBuilder.isValidPoolEntry` before calling public `buildOutbound` methods. The validation matrix says VLESS+TLS requires non-empty `sni` (`PoolBuilder.swift:266-269`), but the actual VLESS+TLS branch only checks port and host (`PoolBuilder.swift:291-296`). The builder then emits `tls.server_name` directly from `parsed.sni` (`ConfigBuilder.swift:69-75`). By comparison, VLESS Reality, Trojan, Hysteria2, and TUIC all reject empty SNI in the same gate (`PoolBuilder.swift:286`, `:306`, `:340`, `:358`).
- **Why HIGH:** URI parsing usually falls back SNI to host, but T-B11 explicitly defends public/programmatic parsed constructors. VLESS+TLS can still reach sing-box with `tls.server_name: ""`, weakening the R1 “strict TLS with intended server name” invariant and making fronted/CDN or IP-address imports fail or validate against unintended defaults.
- **Suggested fix:** Add `guard !v.sni.isEmpty` to the `.vlessTLS` branch in `isValidPoolEntry`, with a warning matching the other protocol branches. Add a regression test that a programmatically constructed `ParsedVLESSTLS(sni: "")` is skipped.

## Medium
### C8'-3-002: HTTPUpgrade keeps `h2` ALPN while WebSocket strips it for the same HTTP/1.1 upgrade reason
- **Location:** `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift:46`, `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift:90`, `BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift:36`, `BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift:77`
- **Dimension:** Correctness / transport-specific ALPN
- **Description:** VLESS+TLS and Trojan strip `"h2"` only when `transport == .ws`, then pass `parsed.alpn` unchanged for every other transport. HTTPUpgrade is also an HTTP/1.1 upgrade transport, and `HTTPUpgradeTransportHandler` emits `type: "httpupgrade"` (`HTTPUpgradeTransportHandler.swift:51-63`), but the protocol builders do not apply the same h2-strip path to `.httpUpgrade`. The default parser ALPN for both protocols is `["h2", "http/1.1"]` (`VLESSURIParser.swift:105-113`, `TrojanURIParser.swift:72-78`), so HTTPUpgrade can negotiate h2 and then attempt an HTTP/1.1 upgrade.
- **Why MEDIUM:** This mirrors the documented WebSocket failure mode in the builder comments: if TLS negotiates h2, the HTTP/1.1 upgrade framing can fail. It affects both VLESS+TLS and Trojan and is easy to miss because tests cover HTTPUpgrade block shape but not HTTPUpgrade ALPN filtering.
- **Suggested fix:** Treat `.httpUpgrade` like `.ws` for ALPN filtering: remove `"h2"` and fall back to `["http/1.1"]` when filtering empties the list. Add tests next to the existing WS ALPN tests for both protocol packages.

### C8'-3-003: TUIC builder preserves arbitrary ALPN even though TUIC v5 comments declare `["h3"]` mandatory
- **Location:** `BBTB/Packages/Protocols/TUIC/Sources/TUIC/ConfigBuilder.swift:36`, `BBTB/Packages/ConfigParser/Sources/ConfigParser/TUICURIParser.swift:98`
- **Dimension:** Correctness / QUIC ALPN policy
- **Description:** TUIC `buildOutbound` emits `tls.alpn` from `parsed.alpn` unchanged (`ConfigBuilder.swift:36-40`). The parser comment says TUIC v5 ALPN is mandatory `["h3"]`, but parser code accepts any CSV and tests explicitly preserve unusual values such as `["h3", "http/1.1"]` or `["h3", "h3-29"]` (`TUICURIParser.swift:98-107`, `TUIC BuildOutboundTests.swift:51-53`, `:107-112`). Hysteria2, the other QUIC protocol, hardcodes `["h3"]` in its builder (`Hysteria2/ConfigBuilder.swift:43-48`).
- **Why MEDIUM:** For QUIC/TUIC, non-H3 ALPN values can produce configs that pass app-side validation but fail handshake or negotiate a protocol the TUIC outbound is not meant to speak. This is not an R1 `insecure` bypass, but it is a protocol-policy inconsistency across the two QUIC builders.
- **Suggested fix:** Decide the TUIC policy and enforce it in one place. If TUIC should be strict, ignore or reject non-H3 ALPN and emit `["h3"]`. If compatibility requires variants, whitelist only valid H3-family tokens and reject `h2` / `http/1.1`; then update comments and tests to match that policy.

## Low
No low findings in this pass.

## Notes
- I read `AUDIT-2.md` first and did not re-report closed Plan 05 findings: T-A2 template-path removal, T-C8' dead template resources, T-B11 broad parsed-entry pre-validation, or C8'-001 TUIC comment clarification.
- `tls.insecure` check: PASS. VLESS Reality omits it (`VLESSReality/ConfigBuilder.swift:34-45`), VLESS+TLS and Trojan hardcode `false` (`VLESSTLS/ConfigBuilder.swift:69-75`, `Trojan/ConfigBuilder.swift:58-64`), Shadowsocks has no TLS block (`Shadowsocks/ConfigBuilder.swift:31-40`), TUIC omits it (`TUIC/ConfigBuilder.swift:36-44`), and only Hysteria2 reads `parsed.allowInsecure` as the D-08 exception (`Hysteria2/ConfigBuilder.swift:43-47`).
- Fingerprint defaults are mostly consistent with Phase 7a smart default once parsed values are considered: VLESS Reality, VLESS+TLS, Trojan, and TUIC builders emit parsed fingerprints; Hysteria2 applies a builder-side fallback to `"random"` when the optional parsed fingerprint is nil/empty.
- Transport handling is intentionally split: VLESS+TLS and Trojan delegate overlays through `TransportRegistry`; Reality, Shadowsocks, Hysteria2, and TUIC ignore transport because their protocol semantics do not support the overlay path. The new transport issue found here is ALPN-specific to HTTPUpgrade, not transport block shape.
