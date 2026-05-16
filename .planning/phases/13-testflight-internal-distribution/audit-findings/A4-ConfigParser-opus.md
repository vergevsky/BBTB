# A4 — ConfigParser audit (Opus 4.7)

**Scope:** BBTB/Packages/ConfigParser/Sources/ConfigParser/
**Files audited:** 20 swift files (full package, ~110 KB of source)
**Total findings:** 19 (CRITICAL: 1, HIGH: 6, MEDIUM: 8, LOW: 4)

---

## Findings

### [CRITICAL] A4-001: SSRF blocklist bypassable via DNS — public hostname resolves to RFC-1918

- **Location:** `SubscriptionURLFetcher.swift:259-301` (`isBlockedHost`) + `:113` (call site in `fetch`)
- **Dimension:** security
- **Description:** `isBlockedHost(_:)` performs a *string* match against the raw host component. An attacker controlling DNS for a public hostname (e.g. `internal.attacker.com → 169.254.169.254` or `→ 192.168.1.1`) trivially passes the textual blocklist, after which `URLSession.data(for:)` resolves the name and connects to the internal address. AWS-metadata exfiltration, router admin panels, internal services, etc., become reachable from a paste-bar subscription URL. The comment at line 254 acknowledges this as "Accepted risk → carry-forward Phase 7" but Phase 7 has now closed and the v1.0 ship is imminent; the gap is real, exploitable, and unguarded.
- **Why it matters:** The whole purpose of the blocklist (CR-03 / T-03-06) is SSRF defence. A textual filter alone provides *no* defence against an active attacker — only against the user accidentally pasting `http://192.168.0.1/router`. For TestFlight this means any malicious subscription link can pivot through the user's iPhone into their LAN or to cloud metadata services.
- **Suggested fix:** After DNS resolution, re-check the resolved IP before the HTTP connect. Either (a) use a custom `URLSession` with a connection handler that fetches `URLSessionTaskMetrics` post-resolve and aborts on private IP, or (b) resolve the host via `getaddrinfo` ahead of the connect, run each resulting `sockaddr` through a numeric block check (covers v4 RFC-1918/loopback/link-local/multicast + v6 ::1/fe80::/fc00::/7), and pass the validated IP literal to `URLSession`. Option (b) is simpler and exactly what RulesEngine `RulesFetcher` should also use. At minimum, gate `fetch` behind a feature flag and document the risk on the UI when accepting paste-bar subscription URLs.

---

### [HIGH] A4-002: Subscription body size unbounded — memory-exhaustion DoS

- **Location:** `SubscriptionURLFetcher.swift:122` (`session.data(for: request)`); also `JSONEndpointFetcher.swift:40`
- **Dimension:** security / bugs (DoS)
- **Description:** The fetcher uses `URLSession.data(for:)`, which buffers the entire response into memory before returning. There is no `Content-Length` cap, no streaming limit, no max-response policy. A malicious or compromised subscription endpoint can return a `chunked` stream of 500 MB+ — the Network Extension and app are running with iOS memory ceilings (~50 MB for NE, ~1 GB for app on modern devices). A 200 MB response is enough to OOM-kill either process.
- **Why it matters:** v1.0 ships with `DefaultSubscriptionURLFetcher` (memory `feedback_phase13_subscription_pins_prerequisite`). Users will paste subscription URLs from forums and Telegram; a single hostile link crashes the app on every refresh until the row is deleted, which is hard for non-technical users to debug.
- **Suggested fix:** Switch to `URLSession.bytes(for:)` and accumulate into `Data` with a hard cap (e.g. 5 MB — comfortably above any realistic plain-text URI list or sing-box JSON). Throw `FetchError.bodyTooLarge(Int)` once cap exceeded. Cap also reduces decode-side risks for findings A4-004/A4-005.

---

### [HIGH] A4-003: JSON injection through `tag` field reaches sing-box config

- **Location:** `UniversalImportParser.swift:455, 462, 471` (`outbound["tag"] as? String`) + `PoolBuilder.swift` (tag handling via per-protocol builders) + `SubscriptionMergeService.swift:90` (`sanitizeRowName`)
- **Dimension:** security / bugs
- **Description:** When import comes from an *operator-pre-built* sing-box JSON (subscription endpoint returning `{outbounds: [...]}`), `parseSingBoxJSON` reads `outbound["tag"]` and uses it verbatim as `name` for `ImportedServer.supported(name:…)`. From there it flows into `PoolBuilder` as the per-outbound tag, which becomes a literal key inside the generated sing-box JSON (e.g. `"tag": "vless-0"`). Although `PoolBuilder` re-tags as `vless-\(index)` (PoolBuilder.swift:74), the user-controlled `name` ends up in `ServerConfig.name` via `SubscriptionMergeService.sanitizeRowName`. That sanitizer strips only `\n\r\t` and clamps length; it leaves Unicode RTL override (`U+202E`), zero-width chars, control bytes other than CR/LF/TAB, and quote characters in place.
- **Why it matters:** (1) For sing-box JSON the worst case is the tag containing characters that, while passing `JSONSerialization.data(withJSONObject:)`, render badly in the in-app server list (homograph spoofing, RTL flip of host names → user sees `evil.com` displayed as `moc.live`). (2) `Profile-Title` header decoding (`SubscriptionURLFetcher.swift:202-206`) does base64 decode with `String(data:encoding:.utf8)` — if the title contains nulls or invalid UTF-8 sequences they survive into the UI.
- **Suggested fix:** Extend `sanitizeRowName` to strip the full `CharacterSet.controlCharacters`, drop BiDi override codepoints (`U+202A..U+202E`, `U+2066..U+2069`), reject zero-width joiners, and Unicode-normalise to NFC before clamp. Apply the same sanitiser to *every* user-supplied display string: `Profile-Title`, `remarks`, `tag`, fragment of URI. Add a unit test feeding `"evil\u{202E}com"` and asserting display string is sanitised.

---

### [HIGH] A4-004: Unbounded JSON decode in `parseSingBoxJSON` — DoS via deeply-nested input

- **Location:** `UniversalImportParser.swift:435-440` (`JSONSerialization.jsonObject`), `:104-114` (classify branch) and `SubscriptionURLFetcher.swift:141-150`
- **Dimension:** security
- **Description:** `JSONSerialization.jsonObject(with:)` is called on untrusted input with no `options` and no size pre-check. Apple's parser is reasonably robust but a hostile 4 MB JSON with `[[[[…]]]]` nesting depth pushes the call stack deep and burns CPU; combined with A4-002 (no body cap), the import flow gives an attacker arbitrary parse-time DoS. Additionally, `JSONSerialization.data(withJSONObject:)` is called at line 456 and 472 to re-emit the same dict — quadratic on large outbound dicts, and any non-`Sendable` types in nested values can throw exceptions that surface only at runtime.
- **Why it matters:** Cold-start path: user opens app → background refresh of subscription → 30 s of CPU thrashing → watchdog kill or UX freeze. Hard to debug for end users.
- **Suggested fix:** Pre-check `body.count < 5_000_000` before `JSONSerialization`. Limit `outbounds.count` to `≤ 200` after decode and refuse the whole import if exceeded. Wrap `data(withJSONObject:)` in `do/try/catch` (currently `try?` silently swallows — losing visibility).

---

### [HIGH] A4-005: Base64 decode without size cap — DoS

- **Location:** `SubscriptionURLFetcher.swift:172-183` (`decodeBase64`), called from `UniversalImportParser.swift:159, 408`
- **Dimension:** security
- **Description:** `decodeBase64` happily accepts a 100 MB base64 blob, expands it ~75 % to ~75 MB, then `String(data:encoding:.utf8)` allocates another copy. Combined with no body cap (A4-002), a 50 MB base64 subscription crashes the app's memory.
- **Why it matters:** Same DoS surface as A4-004 but cheaper to construct (subscription endpoints commonly return base64).
- **Suggested fix:** Guard `padded.count < 4 * 5_000_000` early-return `nil`; reject if decoded data > 5 MB.

---

### [HIGH] A4-006: `PoolBuilder` reads cross-process `UserDefaults` without thread-safety annotation

- **Location:** `PoolBuilder.swift:63-67` (`utlsPickerOverride`)
- **Dimension:** thread-safety / logic
- **Description:** `PoolBuilder.buildSingBoxJSON` is a static `throws` function callable from any actor. Inside it, line 64 reads `UserDefaults(suiteName: "group.app.bbtb.shared")?.string(forKey:)`. `UserDefaults` reads are documented thread-safe but the *value* obtained here is then used to mutate `outbound` dictionaries. There is no isolation guarantee that the picker doesn't change mid-build (App Group writes from Settings tab while PacketTunnel calls `buildSingBoxJSON`). In practice this won't crash because the value is captured once per call, but if `PoolBuilder` is ever invoked twice concurrently for the same pool (e.g. auto-select race with manual override), one call may read "random" and the other "firefox", producing different JSONs from the same input — non-deterministic.
- **Why it matters:** Auto-select winner JSON ≠ manual-select winner JSON ⇒ XPC trip churn, possible NetworkExtension restart loops. Phase 6c memory mentions reconnect-race issues.
- **Suggested fix:** Pass `utlsFingerprint` as an explicit parameter to `buildSingBoxJSON(from:dns:fingerprint:)`. Have `ConfigImporter` read the App Group once and inject. Removes hidden global state from a pure JSON builder. As bonus, makes it testable without `UserDefaults` patching.

---

### [HIGH] A4-007: Ed25519 placeholder public key still in production manifest verifier

- **Location:** `SubscriptionPinManager.swift:45-50` (`defaultPublicKeyBytes`) — comment at line 44 says *"PLACEHOLDER — same as RulesEngine placeholder. Phase 12 replaces with real admin public key."*
- **Dimension:** security
- **Description:** The 32-byte Ed25519 verifier key shipped to TestFlight is still a placeholder. Anyone who knows the corresponding *private* key for this placeholder can sign manifests that the app will accept. The placeholder value is reused across projects/repos and is well known (or trivially discoverable via grep of public AI sample code). Even though memory indicates `SubscriptionPinManager.performBackgroundRefresh` is not currently invoked from production code paths (subscription-pins gap downgraded to v1.1+), the module is reachable, and any future wiring (or test artifact left in the binary) accepts a fake manifest. Same key mirrored in `RulesEngine/PublicKey.swift` — broader risk.
- **Why it matters:** Even though phase 13 memory says pinning is dead code for v1.0, the App Store binary will contain the key bytes. A future point release that flips the toggle inherits a known-compromised key. Also: ATTACK SCENARIO — an attacker MITM's subscription-pins.json, signs with their own key, the signature passes (because their key derived from the same placeholder) → updates `cachedManifest` → blocks legitimate certs via stale pin → DoS or pin substitution.
- **Suggested fix:** Before TestFlight upload: replace `defaultPublicKeyBytes` with the real admin's Ed25519 public key, OR replace with all-zero bytes and add `preconditionFailure("placeholder Ed25519 key still in build")` in DEBUG; in RELEASE refuse to compile via `#error` if a build flag isn't set. Track in the v1.1 plan that wiring `PinnedSubscriptionURLFetcher` is blocked on real-key + real-pin generation.

---

### [MEDIUM] A4-008: `URLComponents` allows IPv4 `0` / oversized port — uncaught

- **Location:** Every URI parser using `comps.port` without range validation: `VLESSURIParser.swift:50`, `TrojanURIParser.swift:35`, `Hysteria2URIParser.swift:74`, `TUICURIParser.swift:67`, `ShadowsocksURIParser.swift:73`.
- **Dimension:** bugs / security
- **Description:** `URLComponents.port` returns `Int?`. The parsers accept *any* non-nil `Int`, including `0` (invalid port) and theoretically `99999` (URLComponents will reject > 65535 at string-parse, but a port of `0` parses successfully). The value flows into `ParsedXxx.port` → sing-box JSON. sing-box may refuse to start, leading to "tunnel won't connect" with no obvious user feedback.
- **Why it matters:** Defence-in-depth — silently bad servers in the list produce poor UX. Also, attacker-crafted ports may be used for fingerprinting (e.g. probing localhost-only services if combined with A4-001).
- **Suggested fix:** After `let port = comps.port`, `guard (1...65535).contains(port) else { throw .malformedURI }`. Same in `defaultPortForScheme` callers.

---

### [MEDIUM] A4-009: URI length unbounded — crash via very long input

- **Location:** All `*.parse(_:)` entry points; primarily `UniversalImportParser.swift:58-83`
- **Dimension:** security / bugs
- **Description:** None of the parsers (or the `import` entry point) enforces an upper bound on `rawInput.count`. A pasted 10 MB string flows into `trimmingCharacters`, `URLComponents`, `Yams.load`, `split(whereSeparator:)`, `lowercased`, `removingPercentEncoding`, etc. Each is linear or worse — combined cost is multi-second blocking on the main actor.
- **Why it matters:** Paste-bar accidental paste of a huge text file freezes the UI. QR-scanned text is bounded by QR capacity (≤ 3 KB) but file/url-scheme isn't.
- **Suggested fix:** Top of `UniversalImportParser.import`: `guard rawInput.count <= 1_000_000 else { throw .unknownInputFormat(snippet: ...) }`. Reasonable: longest legitimate input is a large sing-box JSON ~ 300 KB.

---

### [MEDIUM] A4-010: Empty-pbk Reality marker collides with empty-string `security=tls` URI

- **Location:** `VLESSURIParser.swift:68-72`
- **Description:** Phase 4 D-02 / Pitfall 3 logic: `hasReality = (!pbk.isEmpty) || (security == "reality")`. The comment correctly says "пустой `pbk=` НЕ считается Reality". However, the *encryption* check inside the Reality branch is `q["encryption"] ?? "none"` (line 74) — meaning a URI with `security=reality&pbk=` (literally empty) won't enter the Reality branch and falls through to `security == "tls"` test (line 98) — which then fails, throws `unsupportedSecurity("reality")`. The URI is rejected as "VLESS without TLS" instead of "Reality missing public key" → user-visible error is misleading.
- **Dimension:** logic / UX
- **Suggested fix:** Add explicit branch: `if security == "reality" && pbk.isEmpty { throw .malformedURI }` before line 98. Better error message; less head-scratching for testers.

---

### [MEDIUM] A4-011: `TransportConfig.ws` empty path tolerated when URI omits path entirely

- **Location:** `TransportParamParser.swift:48-52` + `ClashYAMLParser.swift:142-147, 224-228`
- **Description:** `TransportParamParser` *throws* `.wsMissingPath` when `path` is empty — but the Clash YAML branch uses `(wsOpts["path"] as? String) ?? "/"` (line 143 / 226), accepting an empty `path:` field by silently substituting `"/"`. URI vs YAML have different validation surfaces for the *same* logical input; subscription provider mistakes get caught for URI but auto-corrected for YAML (or vice versa). Behavioural drift makes round-trip testing hard.
- **Dimension:** logic
- **Suggested fix:** Make YAML branch route through `TransportParamParser` (it already takes a `[String: String]` query dict — can pass `["type": "ws", "path": ws.path ?? "", "host": …]`). Single source of truth.

---

### [MEDIUM] A4-012: `Hysteria2URIParser` multi-port detection mis-fires on IPv6 literal

- **Location:** `Hysteria2URIParser.swift:50-64`
- **Description:** The multi-port pre-scan walks `afterAt` looking for `:` to separate host from port, then checks if port part contains `,` or `-`. For an IPv6 literal `hy2://auth@[2001:db8::1]:443/?…`, `afterAt = "[2001:db8::1]:443/?…"`. Split by `:` (maxSplits: 1) gives `["[2001", "db8::1]:443/?…"]` → portParts[1] contains `-`? No (`db8::1]:443` has no `-` typically). But it *does* contain `:` characters that aren't a port. Worse, splitting by `/`, `?`, `#` first yields `[2001:db8::1]:443` → second-level split gives portParts[1] = `db8::1]:443` — if any IPv6 host contains a literal `-` (rare but valid in some implementations — none actually, OK) it falsely throws `multiPortNotSupported`. More plausible: hostname like `my-host.example.com:443,8443` — but a legitimate non-multiport `my-host.example.com` (no port specified) shouldn't trigger; comment at line 56-58 says it won't but the actual logic uses `split(separator: ":", maxSplits: 1)`, which produces `count == 1` for no-port case → safe. So the *current* bug is only IPv6 mis-classification.
- **Dimension:** bugs / IPv6 support
- **Suggested fix:** Wrap port-region extraction: if `afterAt.hasPrefix("[")`, find `]:` separator and extract port substring from `]:port` only. Bonus: matches the IPv6 escaping used in `URLComponents`.

---

### [MEDIUM] A4-013: Per-line error in multiline import propagates raw URI into the error message

- **Location:** `UniversalImportParser.swift:209-211, 222-226, 258-262, etc.` — `failed: [.invalid(rawURI: trimmed, error: error.localizedDescription)]`
- **Description:** `error.localizedDescription` is forwarded to UI. For Trojan, "Trojan URI missing password" combined with `rawURI: trimmed` produces a UI string that *includes the raw URI* (which contains password / UUID). If user takes screenshot to ask support, secrets leak.
- **Dimension:** security (logging hygiene)
- **Suggested fix:** Strip userinfo from `rawURI` before placing it in `.invalid(...)`: helper that takes URI, replaces `user[:pass]@` with `***@`. Apply uniformly.

---

### [MEDIUM] A4-014: `Yams.load` parses untrusted YAML with no size/depth limits

- **Location:** `ClashYAMLParser.swift:40` (`Yams.load(yaml: body)`)
- **Description:** Yams uses libyaml under the hood; no explicit billion-laughs or alias-bomb defence. A maliciously crafted YAML with deeply nested anchors can exhaust memory in O(n²) or worse.
- **Dimension:** security
- **Suggested fix:** Check `body.count` before Yams.load (cap ~ 2 MB). Yams doesn't expose anchor-expansion limits directly, but a size cap caps the worst case at memory ∝ size.

---

### [MEDIUM] A4-015: Duplicate URI in import is not deduplicated before persistence

- **Location:** `UniversalImportParser.swift:378-393` (`parseMultiline`) and `SubscriptionMergeService.swift:80-121` (`merge`)
- **Description:** If a subscription returns the same URI twice (e.g. by mistake or by malicious flood), `parseMultiline` parses each as a separate `ImportedServer.supported`. Identity dedup only happens later in `merge` via `existingByIdentity` — first wins, duplicates *within the same fetch* are NOT deduped because the merge loop appends all to `newIdentities` set but doesn't notice that two combined entries share an identity. Resulting state: only one row inserted (correct), but the per-call log says "fetched 100 total" when really only 1 was unique. Worse, when `existingByIdentity` doesn't have an entry, the loop *can* insert the same identity twice in the same pass.
- **Dimension:** logic
- **Suggested fix:** Build `newIdentities` Set *first*, dedupe `combined` against it, then process.

---

### [LOW] A4-016: `PinStore.init` debug log emits invalid hex pin to stdout — info leak in dev builds

- **Location:** `PinStore.swift:96-99`
- **Description:** `print("[PinStore] WARNING: invalid hex pin '\(hexPin)' for host '\(host)' — skipping")`. Uses `print` not `os.log`; appears in Console.app for anyone capturing logs from a connected dev device. Hex pin is not sensitive per se but `print` is the wrong tool.
- **Suggested fix:** Use `Logger(subsystem:category:)` with `privacy: .private`. Same change suggested for any other `print` in package (none in audited files, but the pattern matters).

---

### [LOW] A4-017: `extractTitle` is case-sensitive on header lookup

- **Location:** `SubscriptionURLFetcher.swift:194-200`
- **Description:** Only checks `"Profile-Title"` and `"profile-title"`. HTTP headers are case-insensitive; some servers return `PROFILE-TITLE`. Title is silently lost.
- **Suggested fix:** Iterate header keys, lowercase-compare to `"profile-title"`.

---

### [LOW] A4-018: `comps.user` (and `comps.password`) may contain percent-encoded null bytes

- **Location:** `VLESSURIParser.swift:51-54`, `TrojanURIParser.swift:36, 42`, `TUICURIParser.swift:54, 59-63`, `ShadowsocksURIParser.swift:76-89`
- **Description:** `removingPercentEncoding` on `"%00"` yields a `String` containing a NUL byte. Swift's String tolerates this, but downstream sing-box (Go) treats `password = "secret\x00extra"` differently than expected (Go strings can contain NULs but JSON serialisation does too — could produce JSON that confuses log scrapers).
- **Suggested fix:** After `removingPercentEncoding`, reject password/UUID containing `String.containsControlCharacter`.

---

### [LOW] A4-019: `Profile-Title` base64 decode does not validate UTF-8 after decode

- **Location:** `SubscriptionURLFetcher.swift:202-206`
- **Description:** `Data(base64Encoded: …)` returns arbitrary bytes; `String(data:encoding:.utf8)` may return nil — handled. But if a server returns malformed base64 that happens to decode to bytes interpretable as e.g. Windows-1251 (Cyrillic), the function passes back the original `"base64:..."` literal instead of decoding. Acceptable but undocumented; users see raw `"base64:eAAA..."` in their subscription list as the row name.
- **Suggested fix:** Add a comment, or sanitize down to ASCII subset for display.

---

## Notes

**Strongest points of the package:**
- Per-URI error isolation in `parseMultiline` — one bad URI doesn't kill the import. Good.
- D-08 R1 exception (Hy2 `allowInsecure`) is *type-level enforced* — `ParsedTrojan/ParsedVLESS` have no `allowInsecure` field, so a Trojan with `skip-cert-verify` can't accidentally produce an insecure outbound. Excellent invariant.
- `SubscriptionMergeService` uses fetch-all + Swift filter (line 51-52) per the documented SwiftData UUID? predicate bug. Memory-pattern correctly applied.
- Sendable conformance for `ImportResult`, `SubscriptionFetchResult`, `PinStore`, `PinManifest` looks correct; actor isolation on `UniversalImportParser` and `SubscriptionPinManager` is appropriate.

**No stale `SingBoxRule` / `extraRules` references found** (commit f1eab97 cleanup verified — `PoolBuilder.swift` has no rules-related parameter).

**Resource limits status:**
- `supportedConfigs.prefix(50)` capping in PoolBuilder.swift:49 is enforced. Good.
- Max URI size — NOT enforced (A4-009).
- Max servers per import in `parseMultiline` — NOT enforced; only the downstream PoolBuilder cap. A subscription returning 10 000 servers parses all 10 000 and persists them to SwiftData, only the first 50 are pool-built. Wasted parse + DB pressure.

**Top 3 priorities for TestFlight upload:**
1. A4-007 — replace placeholder Ed25519 key (CRITICAL trust artifact in binary even if dead code).
2. A4-001 — at least gate behind a debug flag or warn user, ideally implement DNS resolve + IP check.
3. A4-002 + A4-005 — add hard body cap (5 MB) before decode; one-line change with large blast-radius reduction.

The package is overall well-structured: validation is layered, errors are typed, comments explicitly mark R1 invariants. Most findings are *defensive hardening*, not "this is currently broken". The CRITICAL finding (A4-001) is acknowledged technical debt; the v1.0 ship plan should either close it or document the residual risk in the wiki security-gaps section.
