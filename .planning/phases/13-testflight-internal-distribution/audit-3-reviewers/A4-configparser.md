# A4 — ConfigParser (Opus 4.7)

**Baseline:** `fb2ff54`
**Files reviewed:** 17
- `ClashYAMLParser.swift`
- `ConfigImporting.swift` (protocol only)
- `Hysteria2URIParser.swift`
- `ImportedServer.swift` (re-export only)
- `JSONEndpointFetcher.swift`
- `PinManifest.swift`
- `PinStore.swift`
- `PinnedSessionDelegate.swift`
- `PoolBuilder.swift`
- `ShadowsocksURIParser.swift`
- `StubParsers.swift`
- `SubscriptionMergeService.swift`
- `SubscriptionPinManager.swift`
- `SubscriptionURLFetcher.swift`
- `TUICURIParser.swift`
- `TransportOverride.swift`
- `TransportParamParser.swift`
- `TrojanURIParser.swift`
- `UniversalImportParser.swift`
- `VLESSURIParser.swift`
- `Resources/subscription-pins-bootstrap.json`

**Total findings:** 12 (C: 0 / H: 2 / M: 4 / L: 6)

**Scope reminders honored:**
- T-A3' closed: `isBlockedHost` numeric IP parser via `Network.IPv4Address` / `IPv6Address`. Verified mapped-IPv6 reclassification works for `::ffff:127.0.0.1`, `::ffff:7f00:1`, `0:0:0:0:0:ffff:127.0.0.1` (lines 412-433). **However** found residual SSRF gap in NAT64/6to4 prefix space — reported below as A4-3-001 HIGH.
- T-B1' closed: `PinnedSessionDelegate.willPerformHTTPRedirection` re-applies `isBlockedHost` + HTTPS check (lines 98-114). Verified.
- T-B2' closed: `JSONEndpointFetcher` streams via `bytes(for:)` with per-byte cap (lines 78-115). Verified.
- T-C5' closed: `HTTPSRedirectGuard` marked `@unchecked Sendable` (line 445). Verified.
- T-C3' closed: All 5 URI parsers validate `(1...65535).contains(port)`. Verified file-by-file.
- T-C4' closed: `parseSingBoxJSON` caps outbound.tag at 256 chars (lines 492-494). Verified.
- A4'-001 (DNS-rebinding) wiki documented — not re-reported.

---

## Critical

No CRITICAL findings in scope. T-A3' did NOT introduce regressions; the new numeric parser correctly classifies all IPv4-mapped IPv6 notations against the IPv4 blocklist (verified by tracing `IPv6Address("::ffff:7f00:1").rawValue` → 16-byte form `[00…00, ff, ff, 7f, 00, 00, 01]` → `isMapped` path → `isBlockedIPv4Bytes([7f, 00, 00, 01])` → `b0 == 127` → true). The Plan 05 closure is correct.

---

## High

### A4-3-001: `isBlockedHost` misses NAT64/6to4 IPv6 prefixes — residual SSRF
- **Location:** `SubscriptionURLFetcher.swift:412-433` (`isBlockedIPv6Bytes`)
- **Dimension:** security
- **Description:**
  The post-T-A3' classifier detects IPv4-mapped IPv6 via the `::ffff:0:0/96` prefix (lines 426-431). This correctly closes Codex C4'-001. However two adjacent IPv6 prefixes embed IPv4 addresses by design but are not recognised by the classifier:

  1. **NAT64 well-known prefix `64:ff9b::/96`** (RFC 6052). Any iOS device on a DNS64/NAT64 cellular link (Apple-required since 2016; ubiquitous on T-Mobile US, Reliance Jio, many MVNOs) silently translates `64:ff9b::7f00:1` to `127.0.0.1` at the carrier level. URL host `64:ff9b::7f00:1` parses as a valid IPv6Address with bytes `[00, 64, ff, 9b, 00…00, 7f, 00, 00, 01]`. `isBlockedIPv6Bytes`:
     - `allSatisfy {$0 == 0}` → false (skip unspecified).
     - prefix(15) all zero check → false (skip `::1`).
     - `bytes[0]==0xFE && bytes[1]∈0x80..0xBF` → bytes[0] is `0x00`, fails (skip fe80::/10).
     - `bytes[0]∈{0xFC, 0xFD}` → false (skip fc00::/7).
     - `bytes[0]==0xFF` → false (skip multicast).
     - `isMapped` (prefix(10)==0, [10..11]==0xFFFF) → bytes[1] = 0x64 ≠ 0, fails.
     - Falls through → `return false` → **NOT blocked**.

     On a NAT64-network user, a hostile subscription URL with host `[64:ff9b::7f00:1]` (or `[64:ff9b::a9fe:a9fe]` → 169.254.169.254 AWS IMDS, or `[64:ff9b::a00:1]` → 10.0.0.1 RFC1918) successfully reaches the carrier-translated target. **Real-world SSRF on cellular networks.**

  2. **6to4 prefix `2002::/16`** (RFC 3056). Hosts `2002:wxyz::/48` where `wxyz` decodes to embedded IPv4 `w.x.y.z`. Less prevalent today (6to4 deprecated by RFC 7526) but Apple iOS still honours 6to4 routes through pre-existing tunnels. `2002:7f00:0001::` would reach 127.0.0.1 via 6to4 anycast.

  3. **IPv4-compatible IPv6 `::w.x.y.z`** (deprecated by RFC 4291 but Apple parser may still accept). bytes `[00…00, 7f, 00, 00, 01]` — prefix(12) all zero, last 4 = IPv4. `isMapped` check expects bytes[10..11]==0xFFFF, so fails. Falls through. **NOT blocked.**

  All three are well-known address-translation tactics for SSRF bypass that the standard Python `ipaddress` module, Go `net.IP.IsPrivate`, and Rust `IpAddr::is_private` similarly miss unless extended.

- **Why HIGH:**
  Direct SSRF bypass on real iOS networks (NAT64 ubiquity on cellular). The threat model matches C4'-001 — a hostile subscription URL given to the user reaches loopback / RFC1918 / link-local from the user's device. Severity scales with deployment of NAT64 (very high on Western European LTE/5G and most US carriers as of 2026). Same blast radius as the closed C4'-001: HTTPS server can reach internal services if the device's network supports the translation.

- **Suggested fix:**
  Extend `isBlockedIPv6Bytes` with three additional checks BEFORE the fall-through `return false`:
  ```swift
  // RFC 6052 NAT64 well-known prefix 64:ff9b::/96 — embedded IPv4 in low 32 bits
  let isNAT64 = bytes[0]==0x00 && bytes[1]==0x64
      && bytes[2]==0xFF && bytes[3]==0x9B
      && bytes[4..<12].allSatisfy({ $0 == 0 })
  if isNAT64 {
      let v4 = Data(bytes[12...15])
      return isBlockedIPv4Bytes(v4)
  }
  // RFC 3056 6to4 prefix 2002::/16 — embedded IPv4 in bytes [2..5]
  if bytes[0] == 0x20 && bytes[1] == 0x02 {
      let v4 = Data(bytes[2...5])
      return isBlockedIPv4Bytes(v4)
  }
  // RFC 4291 deprecated IPv4-compatible IPv6 ::w.x.y.z — bytes[0..11]==0, last 4 = IPv4
  let isCompat = bytes.prefix(12).allSatisfy({ $0 == 0 })
      && (bytes[12] != 0 || bytes[13] != 0)  // exclude `::1` already handled
  if isCompat {
      let v4 = Data(bytes[12...15])
      return isBlockedIPv4Bytes(v4)
  }
  ```
  Add unit tests with `host = "64:ff9b::7f00:1"`, `"64:ff9b::a00:1"`, `"2002:7f00:1::"`, `"::7f00:1"`. The NAT64 case is the operationally-critical one.

  Alternative containment: post-resolution defence-in-depth via `URLSessionTaskMetrics.remoteAddress` numeric IP check after fetch completes (already mentioned in `wiki/dns-rebinding-mitigation.md` as v1.1+ TODO; this would also catch NAT64 translation post-fact).

### A4-3-002: `parseSingBoxJSON` silently drops legitimate VLESS+TLS outbounds (constructs `.vlessReality` with empty `publicKey` → `isValidPoolEntry` rejects)
- **Location:** `UniversalImportParser.swift:481-502, 541-561` (`extractParsedVLESS`) + `PoolBuilder.swift:282-285` (`isValidPoolEntry`)
- **Dimension:** bug (correctness / data loss)
- **Description:**
  When the user pastes / fetches a sing-box JSON manifest containing a plain VLESS+TLS outbound (no Reality block):
  ```json
  {"type": "vless", "tag": "tls-server", "server": "host.com", "server_port": 443,
   "uuid": "…", "flow": "xtls-rprx-vision",
   "tls": {"enabled": true, "server_name": "host.com",
           "utls": {"enabled": true, "fingerprint": "chrome"}}}
  ```
  the parseSingBoxJSON switch (line 496) takes the `case "vless"` branch and calls `extractParsedVLESS`. That helper hard-codes `security: "reality"` (line 558) and reads `reality["public_key"]` which is missing → defaults to `""` (line 553). The reconstructed `.vlessReality` is appended to `supported`. Later in `PoolBuilder.buildSingBoxJSON`, `isValidPoolEntry` rejects this entry because `v.publicKey.isEmpty` is true (PoolBuilder.swift:283). The outbound is silently dropped with a `poolBuilderLogger.warning(…)` — no UI feedback, no `failed.invalid`, no `unsupported.schemaUnsupportedInPhase4`.

  Net effect: legitimate VLESS+TLS sing-box JSON imports lose all `vless` outbounds with no user-visible reason. The user sees "0 supported servers" or only Trojan entries from the same manifest.

  By contrast, URI imports (`VLESSURIParser`) correctly dispatch into `.vlessReality` vs `.vlessTLS` via D-02 branching. Only the sing-box JSON path is broken.

- **Why HIGH:**
  Silent data loss on a common import path (operator-published sing-box JSON manifests, e.g. Hiddify-style profile sharing) violates the user expectation that imported configs either become usable or surface in the "unsupported" / "failed" UI list. Diagnosing the loss requires reading extension logs. Affects every VLESS+TLS deployment that distributes via JSON instead of URI lists — a non-trivial slice of real-world ops.

- **Suggested fix:**
  Two options:
  1. **Detection-first** (preferred): in `parseSingBoxJSON` case `"vless"`, inspect `outbound["tls"]?["reality"]` presence. If absent and `outbound["tls"]?["enabled"] == true`, call a new `extractParsedVLESSTLS(from:)` helper that builds `.vlessTLS(ParsedVLESSTLS(...))` from the same dict (mirroring the existing `extractParsedTrojan` shape with `ws-opts` mapping).
  2. **Surface-on-skip**: in `extractParsedVLESS`, if `pbk.isEmpty`, return `nil` (instead of constructing an invalid `ParsedVLESS`). Then in the case branch, when nil, append `.unsupported(reason: .schemaUnsupportedInPhase4)` with `name = tag ?? "vless \(host):\(port)"`. User sees the entry in the "unsupported" list with a clear scheme.

  Option 1 is the correct fix because the manifest IS supported (VLESS+TLS works in URI paths). Add a `parseSingBoxJSON_vlessTLS` test fixture in `IntegrationTests.swift`.

---

## Medium

### A4-3-003: `SubscriptionMergeService.identity` is case-sensitive on hostname → cosmetic duplicates on subscription provider re-cases
- **Location:** `SubscriptionMergeService.swift:138-160` (`identity(for:)`)
- **Dimension:** bug
- **Description:**
  Identity composite key is `"\(v.host):\(v.port):vless-reality"` (and variants per protocol) without normalisation. A subscription operator who serves the same physical server with `Server.Example.com` in one refresh and `server.example.com` in the next (case rotation is a known anti-fingerprint tactic — see Phase 5 transport rotation notes) generates two distinct identities. The merge logic then:
  1. Existing row (`Server.Example.com:443:vless-reality`) not in new set → marked `missingFromLastFetch=true`.
  2. New row (`server.example.com:443:vless-reality`) inserted with fresh KeychainPersistResult, fresh UUID, fresh `lastLatencyMs=nil`, `failedProbeCount=0`.

  Across multiple refreshes with case-rotating providers, the server list bloats with duplicated/missing rows. Worse: `failedProbeCount` resets each rotation, defeating Phase 6 failover backoff.

  DNS hostnames are case-insensitive per RFC 4343. Identity should normalise host to lowercase.

- **Why MEDIUM:**
  Cosmetic on stable providers (most), real on rotation-friendly providers. Slow growth of duplicate rows + reset of probe state will degrade auto-failover quality over weeks. No security impact.

- **Suggested fix:**
  Normalise host in `identity(for:)`:
  ```swift
  case let .supported(_, parsed, _):
      switch parsed {
      case .vlessReality(let v):
          return "\(v.host.lowercased()):\(v.port):vless-reality"
      // … repeat lowercased() for all branches incl. unsupported's host
      }
  ```
  Migrate existing rows by re-computing identity on `ServerConfig.identity` getter (VPNCore-side, similar lowercase). Caveat: changes identity key for existing installations → one-time merge collapse where `Server.com` and `server.com` rows would be deduplicated. Acceptable for v1.1+ migration.

### A4-3-004: `SubscriptionPinManager.bootstrap()` loads expired cached manifest without `validUntil` check — D-12 hard-reject violated on cold-start path
- **Location:** `SubscriptionPinManager.swift:142-174` (`bootstrap()`) + `currentPins(for:)` lines 248-269
- **Dimension:** security
- **Description:**
  `performBackgroundRefresh` enforces D-12 hard-reject (`guard decoded.validUntil > clock() else { throw .manifestExpired }`, line 227). `bootstrap()` does NOT mirror that check — it `try?`-decodes the cached manifest from disk and assigns to `cachedManifest` regardless of expiry. After cold-start, `currentPins(for:)` returns the UNION of bootstrap pins AND expired-manifest pins (lines 259-265).

  Scenario:
  1. Admin issues manifest valid for 7 days; user fetches refresh on day 6.
  2. App backgrounded; manifest expires on day 8.
  3. User cold-starts on day 10. `bootstrap()` runs, loads cached file, finds `validUntil < now`, but PROCEEDS to set `cachedManifest = manifest`.
  4. `PinnedSubscriptionURLFetcher` calls `currentPinStore()` → returns expired pins as if valid.
  5. If the admin has rotated the SPKI on day 8 (legitimate cert renewal) AND an attacker has obtained the OLD private key during overlap, the attacker can MITM with the pre-rotation key. Replay window = (cold-start date – manifest expiry).

  This is exactly the threat model D-12 was written to defeat. The bootstrap path silently grants the attacker an arbitrary post-expiry window proportional to user app inactivity.

- **Why MEDIUM (would be HIGH if pin path were live):**
  Per memory `project_phase13_subscription_pins_prerequisite.md`, `SubscriptionPinManager.performBackgroundRefresh` is **dead code** in v1.0 — `DefaultSubscriptionURLFetcher` is wired instead. So today this gap has zero exploit surface. **However** v1.1+ enhancement plan explicitly wires `PinnedSubscriptionURLFetcher`, at which point this gap reopens C5'-001-class severity. Best to fix now before v1.1+ ships and the bug becomes exploitable.

- **Suggested fix:**
  In `bootstrap()`, after `decode(PinManifest.self, from: data)`, gate assignment:
  ```swift
  if let manifest = try? makeDecoder().decode(PinManifest.self, from: data),
     manifest.validUntil > clock() {
      cachedManifest = manifest
  }
  // else: keep cachedManifest = nil → currentPins falls back to bootstrap pins only
  ```
  Same gate for the bundle-resource path (lines 171-173). Add test: cold-start with cached manifest where `validUntil < clock()` → `currentPins` returns ONLY bootstrap hardcoded pins.

### A4-3-005: Clash YAML `mapVLESS` octal-bug for unquoted numeric `short-id`
- **Location:** `ClashYAMLParser.swift:181-184` + `stringValue(_:)` lines 417-423
- **Dimension:** bug
- **Description:**
  Clash YAML field `short-id: 01234567` (unquoted) is parsed by Yams as `Int(342391)` because Yams honours YAML 1.1 octal literals (leading zero with digits 0-7). The code's `stringValue` helper converts back via `String(i) = "342391"`. The original short-id was the 7-character hex string `01234567`, which sing-box expects byte-by-byte for Reality handshake — `342391` is wrong.

  Code acknowledges this in the comment ("`01234567` → Int (342391, восьмеричное!)") but does NOT preserve original textual form. The mapVLESS path passes `realityShortID = "342391"` into `ParsedVLESS.shortId`, which then propagates to sing-box JSON. Server rejects handshake → connection fails with cryptic "reality handshake error".

  Also affects:
  - VLESS Reality `public-key` if a panel emits unquoted (impossible — pbk is base64 alphabet so always quoted).
  - VMess UUID (unsupported anyway).

  Reality short-id is the most common occurrence — Sub-Hub, Hiddify panels sometimes emit unquoted short-ids if user configures hex-only values.

- **Why MEDIUM:**
  Silent connection failure for one subset of Clash YAML inputs. No security impact (sing-box rejects). UX impact: user sees "connection failed" with no actionable diagnostic; their YAML is technically valid per Clash spec.

- **Suggested fix:**
  Two options:
  1. **At parse time:** load YAML with a custom Yams resolver that disables YAML 1.1 octal/hex literal interpretation, forcing all unquoted bare-word numerics to remain `String`. (Yams does not expose this directly — would require fork or patch.)
  2. **At Yams.dump round-trip:** since `raw = try? Yams.dump(object: proxy)` (line 54) preserves the original semantics, we could parse `raw` line-by-line for the specific `short-id:` field with a regex `^\s*short-id:\s*([^\s#]+)` and override `realityShortID`. Ugly but correct.
  3. **Recommended:** document the limitation in `wiki/clash-yaml-quirks.md` (new page) and surface a warning in the UI when `short-id` round-trip differs from raw bytes. Defer fix to v1.1+. Add unit test asserting that a `short-id: 01234567` YAML produces ERROR (rejected as malformed) rather than silently wrong value.

### A4-3-006: `SubscriptionURLFetcher.maxBodyBytes` (5 MB) accumulated in 1-byte chunks under `bytes(for:)` is GC-thrashy and can be sustained-attack-amplified
- **Location:** `SubscriptionURLFetcher.swift:172-182`
- **Dimension:** bug / performance
- **Description:**
  The fix for T-A6 / C4'-003 streams via `bytes(for:)` and accumulates per byte:
  ```swift
  for try await chunk in byteStream {
      body.append(chunk)
      accumulated += 1
      if body.count > maxBodyBytes { throw FetchError.bodyTooLarge(body.count) }
  }
  ```
  `URLSession.AsyncBytes` is a per-byte async sequence (not per-chunk). For a 5 MB body, this materialises ~5 million Swift continuation hops and `Data.append(_: UInt8)` calls, each of which may reallocate. On iOS NE (50 MB ceiling), back-pressure plus allocator churn can slow legitimate refresh from ~150 ms to ~5-10 s depending on device. JSONEndpointFetcher has the same pattern (line 105-110).

  Worse for attack: a hostile server can serve exactly `maxBodyBytes + 1` over slow-write (e.g. 1 byte every 100 ms): cap not triggered until byte 5,000,001 → throws → connection torn down. Repeat. Per-request slot-locking the URL session = denial-of-refresh for the user's subscription pull.

- **Why MEDIUM:**
  No memory-DoS (cap works). Throughput/UX degradation under either large legitimate manifests OR slow-write attacks. Sustained-attack amplification is a real concern for the manifest fetch pattern (background refresh every few hours could be hijacked).

- **Suggested fix:**
  Iterate over `URLSession.AsyncBytes` directly is suboptimal but iOS does not expose a chunked variant for `bytes(for:)`. Mitigate with:
  1. Pre-reserve full `maxBodyBytes` capacity for `body` (single allocation) instead of `min(maxBodyBytes, expectedContentLength)`. Trades worst-case 5 MB allocation for elimination of reallocation churn. Acceptable on iOS (main app + extension both have several hundred MB headroom in practice).
  2. Add a request-time wall-clock budget (`URLRequest.timeoutInterval = 10` already set — verify that `bytes(for:)` honours it for inter-byte gaps; per Apple docs, `timeoutInterval` is "no bytes received" reset, so slow-write 1-byte-per-100ms WOULD reset the timer and never trip). Switch to `URLSession.AsyncBytes`-friendly bound: track `startDate` and throw if elapsed > 30s (subscription refresh should be fast).
  3. Long-term: replace `bytes(for:)` with a custom URLSession download-to-memory delegate that uses `urlSession(_:dataTask:didReceive:)` (chunked `Data` per network read) + manual size accumulation. Drops per-byte continuation overhead by ~3 orders of magnitude.

  Recommended minimum: option (1) + option (2). Option (3) is v1.1+.

---

## Low

### A4-3-L1: SNI fallback to IP literal produces invalid TLS ClientHello
- **Location:** `TrojanURIParser.swift:62`, `Hysteria2URIParser.swift:102`, `TUICURIParser.swift:96`, `VLESSURIParser.swift:141`, `ClashYAMLParser.swift:131, 186, 275, 350`
- **Description:**
  All TLS-based URI parsers fall back to `host` for SNI if query/options don't specify (`q["sni"] ?? host`). If `host` is an IP literal (`192.0.2.1`), the resulting sing-box outbound has `tls.server_name: "192.0.2.1"`. TLS ClientHello with `server_name` extension containing an IP literal violates RFC 6066 §3 ("[SNI] is intended for use in scenarios where the server has multiple virtual hosts" — must be a DNS hostname). Most servers accept anyway but compliant proxies / strict middleboxes reject. Reality protocol specifically rejects IP SNI.
- **Suggested fix:** Detect IP-literal host (`IPv4Address` or `IPv6Address` numeric parse) and either:
  - leave SNI nil/empty (sing-box default), or
  - log warning + accept (current behavior).

  Either way add a test case verifying behavior is intentional, not accidental.

### A4-3-L2: `Hysteria2URIParser` multi-port pre-scan misses URIs without `@` (no auth) — error class loss
- **Location:** `Hysteria2URIParser.swift:50-64`
- **Description:**
  Pre-scan uses `trimmed.split(separator: "@", maxSplits: 1).last` to find the host:port substring. If URI has no `@` (no auth) like `hy2://example.com:443,8443/`, `split` returns single component `hy2://example.com:443,8443/`, and `.last` becomes the whole URI. The subsequent split-by-`/` first-component path picks up `hy2:` which does NOT have multi-port syntax → no `multiPortNotSupported` error thrown. Then `URLComponents(string:)` fails on the URI (multi-port spec invalid in standard URL grammar) → `malformedURI` fallback. User sees generic "Malformed hy2:// URI" instead of "Hysteria2 multi-port not supported".
- **Suggested fix:** Replace `split(separator: "@", maxSplits: 1).last` with: if `@` not present, use substring after `://`. Add fixture without auth `hy2://example.com:443,8443/`. Cosmetic UX only.

### A4-3-L3: `PinStore.init` does not validate manifest pin hex length (only validity)
- **Location:** `PinStore.swift:90-103`, `Data.init?(hex:)` lines 124-137
- **Description:**
  Manifest pin hex is described as "64 chars each (32 bytes)" (PinManifest.swift line 33), but `PinStore.init` accepts any even-length hex via `Data(hex:)`. A manifest with `spki_sha256_pins: ["AB"]` (1-byte pin) would silently insert a 1-byte `Data` into the pin set. `isValid(spkiHash:for:)` compares 32-byte hashes against the set; 1-byte entries can never match → effectively harmless but wastes Set capacity and hides manifest authoring bugs.
- **Suggested fix:** In `Data.init?(hex:)`, after parsing, `guard data.count == 32 else { return nil }` (or accept a length parameter). Or in `PinStore.init`, add explicit length check before insert.

### A4-3-L4: `parseSingBoxJSON` outbound iteration silently skips entries with `tag.count > 256` — no user feedback
- **Location:** `UniversalImportParser.swift:492-494`
- **Description:**
  T-C4' closure dropped overlong-tag outbounds via `continue`. Defensive but no `.unsupported` / `.failed` entry produced — user has no visibility that the manifest was rejected in part. For a legitimate (non-attack) manifest with one accidentally-long tag, this silently corrupts the import.
- **Suggested fix:** Replace `continue` with `unsup.append(.unsupported(name: "<oversized tag>", scheme: type, …, reason: .schemaUnsupportedInPhase4))`. Surface in UI.

### A4-3-L5: `extractParsedVLESS` and `extractParsedTrojan` set `fingerprint = "chrome"` default whereas Phase 7a smart default is "random"
- **Location:** `UniversalImportParser.swift:551, 576`
- **Description:**
  Phase 7a Wave 2 DPI-01 switched URI parsers to "random" smart default. The two `extractParsed*` helpers for sing-box JSON imports still default to "chrome" (lines 551, 576). The PoolBuilder later applies `utlsPickerOverride` ONLY to outbounds whose current fingerprint is "random" (PoolBuilder.swift:186) — `chrome`-fingerprint outbounds from JSON imports are NEVER affected by user picker preference. Inconsistency: URI imports respect user picker, JSON imports do not.
- **Suggested fix:** Change `(utls["fingerprint"] as? String) ?? "chrome"` to `?? "random"` in both `extractParsedVLESS` (line 551) and `extractParsedTrojan` (line 576). Add round-trip test (JSON import → uTLS picker change → confirm fingerprint propagates).

### A4-3-L6: `decodeBase64` accepts arbitrary content if base64 decodes — no UTF-8 / printability gate on early-return
- **Location:** `SubscriptionURLFetcher.swift:236-251`
- **Description:**
  After `Data(base64Encoded: padded)`, the function returns `String(data: data, encoding: .utf8)` — which can be nil (decoded bytes not UTF-8) or any arbitrary UTF-8 string (e.g. random binary that happens to be valid UTF-8). Caller `UniversalImportParser.classify` line 179 wraps with `isPrintableURIList(decoded)`, which checks for known URI scheme prefixes. But there's also a direct caller in `detectFormat` (line 222) for subscription body classification — same `isPrintableURIList` gate (line 223) is applied. OK in current callers.

  **However** in `UniversalImportParser.fetchAndParseSubscription`, `decodeBase64(bodyStr)` is called WITHOUT the printable check (line 428) when `format == .base64URIList` was already classified. The classification path checks `isPrintableURIList(decoded)`, so by the time format is `.base64URIList`, the decode succeeded. But classify and decode are called separately and re-decoded — the second decode could in theory produce different output if the input changed between calls. In current code paths, body is captured upfront so no race. Minor robustness gap.
- **Suggested fix:** Optionally: have `decodeBase64` return `(String, isPrintable: Bool)` tuple to avoid duplicate work + drift. Not security-critical.

---

## Confirmed-closed-against scope (no re-report)

- **T-A3'** (1883035) verified by tracing all named bypass forms — fix correct for IPv4-mapped IPv6 (Codex C4'-001). Residual NAT64/6to4/IPv4-compat gap reported as A4-3-001 — separate, not regression.
- **T-B1'** (515f8dc) verified — `PinnedSessionDelegate.urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)` correctly rebuilds the same HTTPS-plus-blocklist check as `HTTPSRedirectGuard`. Both check `newURL.scheme?.lowercased() == "https"`, both call `SubscriptionURLFetcher.isBlockedHost(host)`.
- **T-B2'** (515f8dc) verified — `JSONEndpointFetcher` now uses `bytes(for:)` + per-byte cap + Content-Length fast-path. (Performance concern about per-byte iteration noted as A4-3-006 MEDIUM, applies equally to subscription path.)
- **T-C5'** (515f8dc) verified — `HTTPSRedirectGuard` declared `@unchecked Sendable` (SubscriptionURLFetcher.swift:445).
- **T-C3'** (6244b8b) verified file-by-file:
  - VLESSURIParser.swift:51 — `(1...65535).contains(port)` in URLComponents guard. ✓
  - TrojanURIParser.swift:36 — same. ✓
  - ShadowsocksURIParser.swift:73 — `comps.port, (1...65535).contains(port)`. ✓
  - TUICURIParser.swift:73 — `(1...65535).contains(port) else { throw TUICURIError.invalidPort(port) }`. ✓ (explicit typed error)
  - Hysteria2URIParser.swift:76 — `(1...65535).contains(port) else { throw Hysteria2URIError.malformedURI }`. ✓
- **T-C4'** (6244b8b) verified — `parseSingBoxJSON` line 492-494 skips outbounds where `tag.count > 256` (concern about silent skip noted as A4-3-L4 LOW).

---

## Cross-cutting observations

### O1: SSRF defense is now host-string + numeric-IP only; no post-resolution check
The closure of C4'-001 via `Network.IPv4Address`/`IPv6Address` parsers correctly handles IP-literal hosts but DNS-rebinding (A4'-001 wiki-documented carry-forward) plus NAT64/6to4 (A4-3-001) plus DNS-A-record-pointing-to-RFC1918 are all unaddressed. Defense-in-depth via `URLSessionTaskMetrics.remoteAddress` post-connection check (documented as v1.1+ TODO in `wiki/dns-rebinding-mitigation.md`) would close all three families with a single mitigation. Recommend prioritising for v1.1+.

### O2: sing-box JSON parse path is structurally divergent from URI parse path
The `parseSingBoxJSON` helpers (`extractParsedVLESS`, `extractParsedTrojan`) duplicate-but-don't-mirror the URI parsers' logic. Differences caught:
- VLESS+TLS dispatch missing (A4-3-002 HIGH).
- Fingerprint default mismatch (A4-3-L5 LOW).
- No `ShadowsocksURIParser.supportedSSMethods` validation in JSON path (only URI path validates).
- No `Hysteria2` / `TUIC` JSON extraction at all (only VLESS + Trojan handled; line 510-519 buckets all others to `.unsupported`).

A future refactor pass could unify URI-parsed and JSON-parsed configurations through a single `dictToParsed(_:)` helper. Out of scope for TestFlight.

### O3: `PoolBuilder.isValidPoolEntry` is a duplicate validator
Each protocol package's `ConfigBuilder.buildOutbound` already enforces port/host/non-empty-key invariants. `PoolBuilder.isValidPoolEntry` duplicates them as a defensive secondary gate (T-B11 closure). Drift risk if one validator updates and the other doesn't. Not a bug today — pure tech-debt observation.

### O4: `BootstrapPins.vpnVergevskyRu` ships placeholder 0x00/0x01 bytes
Confirmed dead code in v1.0 per memory `project_phase13_subscription_pins_prerequisite.md`. The Release-build empty `defaultPublicKeyBytes` (`#else`) is the right guard — Ed25519 init throws → preconditionFailure if anyone wires the manager. Solid defense.

---

## Recommendations summary

**Pre-TestFlight (block):** None. Scope is clean for ship.

**Tier B (recommended before v1.0 release):**
- A4-3-001 NAT64/6to4 IPv6 SSRF gap — ~30 minutes to extend `isBlockedIPv6Bytes` + tests. Recommend including before v1.0 GA.
- A4-3-002 VLESS+TLS JSON import silent-drop — ~1 hour to add `extractParsedVLESSTLS` helper + integration test. Affects subset of users but silent failure is hard to debug.

**Tier C (v1.1+):**
- A4-3-003 hostname case normalisation (migration overhead).
- A4-3-004 SubscriptionPinManager bootstrap expiry check (currently dead code).
- A4-3-005 Clash YAML octal short-id (rare panel emission).
- A4-3-006 5MB per-byte iteration (UX/throughput).

**Tier D (LOW backlog):** A4-3-L1 through L6 — cosmetic / robustness / consistency. Roll into a single LOW batch commit similar to Tier-D in Plan 05.
