# C7 — FrontingEngine + DeepLinks + KillSwitch + TransportRegistry (Codex 5.5)
**Baseline:** fb2ff54
**Total findings:** 2 (0/1/1/0)

## Critical
No critical findings found in this infra/policy pass.

## High
### C7'-3-001: Fronting profile SSRF guard still trusts string forms instead of canonical IP parsing
- **Location:** `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingConfigApplier.swift:132`
- **Dimension:** Security / CDN fronting overlay profile validation
- **Description:** `validateProfile(_:)` checks `connectHost`, `sniHost`, and `httpHost`, but the actual blocker is still string-prefix logic (`FrontingConfigApplier.swift:148`). It blocks dotted IPv4 prefixes and `::ffff:a.b.c.d` (`FrontingConfigApplier.swift:163`, `FrontingConfigApplier.swift:197`), but it does not canonicalize IPv6 literals before classification. Examples that pass the current guard include hex IPv4-mapped loopback/private forms like `::ffff:7f00:1`, NAT64 well-known-prefix literals like `64:ff9b::7f00:1`, and 6to4/private encodings like `2002:0a00:0001::`. The adapter then writes the accepted `connectHost` directly into the outbound dial target (`CloudflareAdapter.swift:55`, same pattern in Fastly/Custom).
- **Why HIGH:** This is the same class of canonical-literal bypass that Plan 05 fixed in ConfigParser, but FrontingEngine kept an inline string implementation. A hostile/admin-supplied fronting profile can make the tunnel dial loopback, RFC1918, or link-local destinations on networks that translate these IPv6 forms, bypassing the intended private/loopback profile rejection.
- **Suggested fix:** Replace `isPrivateOrLoopback(_:)` with numeric parsing equivalent to the fixed `SubscriptionURLFetcher` path: parse IPv4 and IPv6 literals with `Network.IPv4Address` / `Network.IPv6Address`, normalize IPv4-mapped IPv6, explicitly reject NAT64/6to4/Teredo encodings that map to blocked IPv4 ranges, and keep `.local`/hostname checks as a separate string-only layer. Add FrontingEngine tests for `::ffff:7f00:1`, `[::ffff:7f00:1]`, `64:ff9b::a9fe:a9fe`, and `2002:0a00:0001::`.

## Medium
### C7'-3-002: Transport handlers still emit unvalidated path/host values into sing-box transport blocks
- **Location:** `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/WSTransportHandler.swift:56`
- **Dimension:** Security / transport dispatch input validation
- **Description:** `TransportParamParser` accepts non-empty `path` for WS/HTTP/HTTPUpgrade and optional `host` without enforcing a leading slash, max length, or rejecting control characters (`TransportParamParser.swift:47`, `TransportParamParser.swift:56`, `TransportParamParser.swift:61`). The handlers then emit those associated values directly into sing-box JSON: WS `path` and `headers.Host` (`WSTransportHandler.swift:57`, `WSTransportHandler.swift:69`), HTTP `path` (`HTTPTransportHandler.swift:51`), and HTTPUpgrade `path`/`host` (`HTTPUpgradeTransportHandler.swift:52`, `HTTPUpgradeTransportHandler.swift:60`). Plan 05 `PoolBuilder.isValidPoolEntry` validates top-level host/port and required fields, but not transport path/host syntax.
- **Why MEDIUM:** User-provided URI query values can produce malformed transport handshakes or make sing-box reject otherwise valid imported servers. If sing-box or a future transport implementation forwards these values into HTTP/WS request construction before strict validation, CR/LF/NUL or authority-shaped host values become header/path injection risk.
- **Suggested fix:** Validate at parse time and at the handler boundary: `path` must start with `/`, be length-bounded, and contain no NUL/CR/LF; `host` must be empty or a valid hostname/IP authority without control characters, whitespace, scheme, path, or port unless the schema intentionally allows it. Add negative tests in `TransportRegistryTests` and parser tests for `%0d%0a`, missing leading `/`, oversized path, and `host=example.com%0d%0aX: y`.

## Low
No low findings found in this pass.

## Notes
- I read `AUDIT-2.md` first and did not re-report the closed C7 Plan 05 items: C7'-001/T-B6' tag-scoped fronting apply is present at `FrontingConfigApplier.swift:46` and the ConfigImporter call passes `targetTag` at `ConfigImporter.swift:732`; C7'-002 TUIC metadata is now documented as intentionally omitted at `TCPTransportHandler.swift:16`; C7'-003 drift risk is documented at `FrontingConfigApplier.swift:122`.
- DeepLinks URL logging remains redacted to scheme/host at `DeepLinkRouter.swift:104` and `ImportHandler.swift:61`; the tightened universal-link route rejects `/important`/`/importevil` via the segment boundary check at `ImportHandler.swift:48`.
- KillSwitch package-local enforcement remains consistent: enabled sets `includeAllNetworks=true` and `enforceRoutes` according to the macOS hook, disabled clears both, and `excludeLocalNetworks=false` / `disconnectOnSleep=false` are always applied (`KillSwitch.swift:26`).
