# C8 — Protocols/* audit (Codex 5.5)

**Scope:** 6 protocol packages × `ConfigBuilder.swift`
**Files audited:** 18 present files: 6 builders, 6 handlers, 5 package-local templates, plus shared VLESSReality template in `PacketTunnelKit`
**Total findings:** 12 (CRITICAL: 6, HIGH: 6, MEDIUM: 0, LOW: 0)

## Findings (grouped by protocol)

### VLESSReality

#### [CRITICAL] C8-001: Raw string substitution writes user-controlled values into quoted JSON placeholders
- **Location:** `BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift:58`
- **Dimension:** security
- **Description:** `host`, `uuid`, `flow`, `sni`, `fingerprint`, `publicKey`, and `shortId` are inserted without JSON escaping into a quoted template string.
- **Why it matters:** a quote/control character can produce malformed sing-box JSON or inject sibling fields before validation.
- **Suggested fix:** build the config through dictionaries/Codable + `JSONSerialization`, or at minimum JSON-escape every substituted string.

#### [HIGH] C8-002: buildOutbound silently omits tls.reality when publicKey empty
- **Location:** `BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift:119`
- **Dimension:** logic | security
- **Description:** `buildOutbound` silently omits `tls.reality` when `publicKey` is empty and does not validate host/port/SNI/fingerprint/shortId.
- **Why it matters:** a malformed Reality parsed value can degrade into a non-Reality VLESS outbound shape, and can also become mux-compatible downstream if `flow` is not Vision.
- **Suggested fix:** make Reality `buildOutbound` reject missing `publicKey`, invalid port, empty host/SNI, and invalid `shortId`/fingerprint instead of emitting a partial outbound.

### VLESSTLS

#### [CRITICAL] C8-003: Raw replacement into JSON string fields
- **Location:** `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift:58`
- **Dimension:** security
- **Description:** `buildSingBoxJSON` performs raw replacement into JSON string fields.
- **Why it matters:** host/SNI/fingerprint/flow values containing quotes or control characters can corrupt or inject JSON.
- **Suggested fix:** replace template substitution with structured JSON mutation/serialization.

#### [HIGH] C8-004: buildOutbound omits validations present in buildSingBoxJSON
- **Location:** `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift:148`
- **Dimension:** security
- **Description:** `buildOutbound` emits `server`, `server_port`, `server_name`, `flow`, ALPN, and uTLS fingerprint without validating them, while the single-template path validates port and SNI at lines 50-54.
- **Why it matters:** PoolBuilder uses `buildOutbound`; public `ParsedVLESSTLS` initializers can create invalid values that bypass the builder's stricter single-server checks.
- **Suggested fix:** share a validation helper between `buildSingBoxJSON` and `buildOutbound`, or make `ParsedVLESSTLS` construction enforce invariants.

### Trojan

#### [CRITICAL] C8-005: Raw-substitutes password/host/SNI/fingerprint/WS path/host into JSON
- **Location:** `BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift:63`
- **Dimension:** security
- **Description:** `buildSingBoxJSON` raw-substitutes password, host, SNI, fingerprint, WS path, and WS host into JSON.
- **Why it matters:** Trojan password and WS fields are user-controlled and commonly allow arbitrary characters; unescaped quotes can break or inject config.
- **Suggested fix:** build the outbound as `[String: Any]` and serialize, including WS transport fields.

#### [HIGH] C8-006: buildOutbound skips validations
- **Location:** `BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift:151`
- **Dimension:** security
- **Description:** `buildOutbound` does not enforce the validations present in `buildSingBoxJSON` lines 52-54: valid port, non-empty password, and non-empty SNI.
- **Why it matters:** PoolBuilder uses this path, so invalid Trojan credentials/SNI can reach sing-box as malformed runtime config.
- **Suggested fix:** centralize validation or make `buildOutbound` throwing.

### Shadowsocks

#### [CRITICAL] C8-007: Raw-substitutes host/method/password into quoted JSON
- **Location:** `BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ConfigBuilder.swift:52`
- **Dimension:** security
- **Description:** `buildSingBoxJSON` raw-substitutes `host`, `method`, and `password` into quoted JSON.
- **Why it matters:** Shadowsocks passwords may contain arbitrary UTF-8; unescaped quotes/control characters can corrupt JSON.
- **Suggested fix:** construct the JSON object structurally and serialize it.

#### [HIGH] C8-008: buildOutbound skips method whitelist + non-empty password checks
- **Location:** `BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/ConfigBuilder.swift:115`
- **Dimension:** security
- **Description:** `buildOutbound` emits method/password/port without checking non-empty values or method whitelist consistency.
- **Why it matters:** the single-template path checks method/password non-empty, parser comments say method whitelist is parser-enforced, but `ParsedShadowsocks` has a public initializer and PoolBuilder trusts it.
- **Suggested fix:** enforce `supportedSSMethods`, non-empty password, valid host/port in a shared validation layer.

### Hysteria2

#### [CRITICAL] C8-009: Template substitution raw-inserts host/auth/SNI
- **Location:** `BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/ConfigBuilder.swift:92`
- **Dimension:** security
- **Description:** template substitution raw-inserts host, auth password, and SNI into JSON.
- **Why it matters:** Hy2 auth is user-controlled; malformed JSON can be produced before the optional-field JSONSerialization round-trip runs.
- **Suggested fix:** avoid raw template replacement for string fields.

#### [HIGH] C8-010: buildOutbound skips port/auth/SNI validation
- **Location:** `BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/ConfigBuilder.swift:221`
- **Dimension:** security
- **Description:** `buildOutbound` does not enforce valid port, non-empty auth, or non-empty SNI, while `buildSingBoxJSON` does at lines 76-78.
- **Why it matters:** Hy2 is the only allowed `insecure` exception, so malformed TLS identity/auth inputs should be rejected consistently on the PoolBuilder path.
- **Suggested fix:** share validation across both paths; keep the D-08 `allowInsecure` exception explicit.

### TUIC

#### [CRITICAL] C8-011: Template substitution raw-inserts host/UUID/password/SNI/etc
- **Location:** `BBTB/Packages/Protocols/TUIC/Sources/TUIC/ConfigBuilder.swift:95`
- **Dimension:** security
- **Description:** template substitution raw-inserts host, UUID, password, congestion control, UDP relay mode, SNI, and fingerprint into quoted JSON.
- **Why it matters:** invalid quoting can corrupt sing-box JSON; password is user-controlled.
- **Suggested fix:** serialize structured JSON instead of string replacement.

#### [HIGH] C8-012: buildOutbound skips congestion-control + UDP relay mode whitelist checks
- **Location:** `BBTB/Packages/Protocols/TUIC/Sources/TUIC/ConfigBuilder.swift:177`
- **Dimension:** security
- **Description:** `buildOutbound` skips all validations present in `buildSingBoxJSON` lines 78-87, including congestion-control and UDP relay mode whitelist checks.
- **Why it matters:** this is the sharpest cross-protocol inconsistency: TUIC's single path rejects unsupported enum values, but PoolBuilder path can emit invalid sing-box fields.
- **Suggested fix:** call the same whitelist/required-field validation before returning the outbound, or constrain `ParsedTUIC` construction.

## Cross-protocol patterns observed

All six `buildOutbound` methods return dictionaries, so the PoolBuilder serialization path is structurally safe from JSON string injection. The injection issue is concentrated in the public `buildSingBoxJSON` template paths, which raw-replace quoted placeholders.

Validation is inconsistent between single-template builders and PoolBuilder builders. Single-template paths validate at least port and some required fields; `buildOutbound` paths mostly trust public parsed structs. TUIC is the clearest mismatch because enum whitelist validation exists only in the template path.

uTLS fingerprint is not whitelisted in any protocol builder. That is consistent, but risky: invalid values can reach sing-box. If DPI-09 allows global picker values, the picker should also be constrained to the same whitelist.

Transport handling is consistent with current design: Reality, Shadowsocks, Hysteria2, and TUIC ignore transport; VLESSTLS/Trojan delegate overlays and apply WS ALPN/SNI fallback. No thread-safety issue found: builders are static enums with no mutable static state.

## Notes

I did not modify code and did not run build/tests. Current `ConfigImporter` appears to use `PoolBuilder.buildSingleOutboundJSON`, so the dictionary `buildOutbound` path is likely the active path for both single and pool configs; the template methods still remain public security-sensitive code.

**Verdict:** fix before TestFlight, primarily by centralizing validation and removing raw JSON template substitution.
