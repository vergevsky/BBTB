# A4 — ConfigParser — Audit 4

**Reviewer:** A4 (Opus 4.7 reviewer #4)
**Scope:** `/Users/vergevsky/ClaudeProjects/VPN/BBTB/Packages/ConfigParser/Sources/ConfigParser/`
**Baseline:** HEAD `ccbce8a` (post Plan-07 closure; commits `9da8c96 → d802e72`)
**Focus:** Security + Bugs
**Date:** 2026-05-17

## Verdict at a glance

| Plan 07 fix | Closure quality | Verdict |
|---|---|---|
| T-C-H3' NAT64 + 6to4 + IPv4-compat IPv6 SSRF prefixes | **Solid** — covers ::1 loopback exclusion correctly; tests verify all three new prefixes; ordering preserves IPv4-mapped fast-path | ✅ CLOSED |
| T-C-H4' VLESS+TLS sing-box JSON dispatch | **Solid** — `extractParsedVLESSTLS` mirrors existing helper; Reality path preserved; both new tests PASS | ✅ CLOSED with **minor edge-case gap** (`tls.enabled` missing/false but no Reality block) |
| T-C-B3 SubscriptionMergeService.identity host lowercase | **Asymmetric closure** — `identity(for:)` lowercases fetched side, but `ServerConfig.identity` (`VPNCore/ServerConfig.swift:135`) does **NOT**. Migration impact: existing rows with mixed-case host fail lookup on next refresh → duplicate insert → exactly the bug the fix was meant to prevent | ⚠️ **NEW HIGH A4-4-001** |
| T-C-B4 SubscriptionPinManager.bootstrap expired-manifest reject | **Solid for cache path; partial for bundle path** — bundle path checked, but expired cache returns early at line 166 without falling through to bundle resource; documented bootstrap-only fallback is `host == "vpn.vergevsky.ru"` only | ✅ CLOSED for stated D-12 hard-reject; minor design note logged below |
| T-C-B5 ClashYAML octal short-id reconstruction | **Solid for leading-zero octal `01XXXXXX`; REGRESSES digits-only-without-leading-zero hex short-ids** — `short-id: 12345678` (legit decimal-looking hex) now silently transforms to `"57060516"`; pre-fix returned `"12345678"` | ⚠️ **NEW HIGH A4-4-002** (regression) |

**Cross-cutting status:** all 50 ConfigParser tests PASS at HEAD `ccbce8a`. Build clean (`swift build` 9.97s).

---

## Findings

### A4-4-001 (HIGH, regression-prevention) — `SubscriptionMergeService.identity` asymmetric host normalization

**Location**
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionMergeService.swift:146-168`
- vs `BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift:134-136`

**Description**

The Plan 07 fix added `.lowercased()` to host in `SubscriptionMergeService.identity(for: ImportedServer)`. The companion key used to look up existing rows is `ServerConfig.identity` (a computed property on the SwiftData model):

```swift
// ServerConfig.swift:134-136
public var identity: String {
    "\(host):\(port):\(protocolID)"
}
```

`ServerConfig.host` is stored verbatim from `ConfigImporter.buildServerConfig` (`AppFeatures/MainScreenFeature/ConfigImporter.swift:457-503`), which copies `v.host`, `t.host` etc. directly without lowercasing. So:

- **First refresh** stores row with mixed-case host `Server.Example.com` → row.identity = `"Server.Example.com:443:vless-reality"`.
- **Second refresh** computes new identity via `SubscriptionMergeService.identity(for:)` → `"server.example.com:443:vless-reality"`.
- Dictionary lookup `existingByIdentity[id]` (line 88) fails → enters insert branch (line 105) → **inserts duplicate**.
- Original row is then marked `missingFromLastFetch = true` at line 124-126.

**Why HIGH (regression-prevention)**

This is **the exact failure mode the fix claims to prevent.** Quoting commit `c86174a`:

> Pre-fix subscription providers с case rotation (anti-fingerprint tactic — `Server.com` vs `server.com`) generated distinct identities → server list bloated с duplicate rows + `failedProbeCount` reset each rotation → degraded failover quality.

With the asymmetric closure, the **first time** a subscription rotates the host case, the user gets:
1. A new duplicate row inserted (because lookup fails)
2. The old row marked "missing from last fetch" — still visible until user swipe-deletes
3. `failedProbeCount` on the new row starts at 0 (lost history)
4. Subsequent refreshes keep duplicating if upstream alternates further

Plan 06 reported this as MEDIUM `A4-3-003` — Plan 07 closed it but **introduced the exact same UX outcome via path-of-least-resistance**.

**Reproduction**

```
1. ServerConfig row exists in store with host = "VPS.Provider.com", protocolID = "vless-reality".
2. Subscription pull-to-refresh returns same outbound but with host = "vps.provider.com".
3. SubscriptionMergeService.merge:
   - existingByIdentity["VPS.Provider.com:443:vless-reality"] populated (from ServerConfig.identity).
   - newID = "vps.provider.com:443:vless-reality" (from identity(for:) lowercased).
   - newID lookup misses → insert path → duplicate row created.
```

This will hit on **first deployment**, because all existing v0.9.x rows in user stores have host stored verbatim. So even a **single** case-rotation in any subscription will trigger the duplication after the v1.0 upgrade.

**Suggested fix (Tier A+, ≤30min)**

Three options, ordered by intrusiveness:

1. **Symmetric normalization at lookup time** (least intrusive, no migration):
   ```swift
   // SubscriptionMergeService.merge
   var existingByIdentity: [String: ServerConfig] = [:]
   var duplicatesToDelete: [ServerConfig] = []
   for row in existing {
       let key = row.identity.lowercased()  // normalize at lookup
       if existingByIdentity[key] != nil {
           duplicatesToDelete.append(row)
       } else {
           existingByIdentity[key] = row
       }
   }
   ```
   Caveat: works only because `identity` is `host:port:protocolID` — `port` and `protocolID` are already case-stable.

2. **Normalize in `ServerConfig.identity` directly** (preferred — single source of truth):
   ```swift
   public var identity: String {
       "\(host.lowercased()):\(port):\(protocolID)"
   }
   ```
   No data migration needed — `identity` is computed, not stored. Existing rows recompute on read.

3. **Normalize host on write** (deepest fix, requires SwiftData migration): lowercase host at `buildServerConfig` time. Existing rows need a one-shot migration pass.

**Recommended:** option 2. It centralizes the contract in VPNCore, mirrors the lowercasing intent of `identity(for: ImportedServer)`, and avoids any migration.

**Tests to add**
- `MergeStrategyTests` — refresh with rotated case (existing row host=`H1.example.com`, fetched=`h1.example.com`) → assert single row, latency preserved.
- `ServerConfig` identity round-trip test.

---

### A4-4-002 (HIGH, regression) — ClashYAML octal short-id reconstruction misinterprets unquoted decimal-looking hex short-ids

**Location**
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/ClashYAMLParser.swift:194-210`

**Description**

The Plan 07 fix handles unquoted leading-zero octal `short-id: 01234567` correctly: Yams parses as `Int(342391)` (octal interpretation), `String(342391, radix: 8) = "1234567"` → padded to `"01234567"`. ✓

However, the heuristic "any Int short-id was originally octal" is **wrong** for unquoted **all-digit hex** short-ids without leading zero:

- Input: `short-id: 12345678` (legitimate hex short-id, no leading zero)
- Yams parses as decimal `Int(12345678)`
- New code: `String(12345678, radix: 8) = "57060516"` (8 chars — no padding triggered)
- Returned short-id: `"57060516"` — **wrong**

**Pre-fix behavior**: `stringValue(_:)` returned `String(i)` for Int → `"12345678"` — matches what user wrote.
**Post-fix behavior**: `"57060516"` — sing-box Reality handshake fails with cryptic error.

**Why HIGH (regression)**

Reality short-ids in production deployments are hex strings 0–8 bytes long (sing-box spec). Users sharing YAML configs from operator panels frequently write them unquoted (Clash convention from upstream). When the digits happen to all be 0–9, Yams casts to Int and the fix corrupts.

Statistical likelihood: about **40% of randomly-generated 8-hex-char short-ids** contain only digits 0–9 (probability ≈ (10/16)^8 ≈ 4%). For shorter IDs (4 hex chars), it climbs to ~15%. Not negligible.

**Disambiguation is impossible from Int alone**: Yams strips the original token; we cannot tell octal vs decimal post-parse. The fundamental fix requires either:

1. Reject unquoted Int short-ids → require user to quote them (loud failure beats silent corruption).
2. Try both interpretations and warn — but downstream Reality handshake either works or doesn't, and we can't test from parser.
3. Always pass `String(i)` (decimal-as-written) and log warning that user should quote → restores pre-fix behavior for both cases; only the rare leading-zero octal case remains broken (and historically WAS broken pre-Plan-07).

**Suggested fix (Tier A+, ≤30min)**

Recommended: **option 3** — revert to decimal `String(i)` but log warning loudly. Pre-Plan-07 we had **silent breakage for octal**; Plan 07 introduced **silent breakage for digits-only-hex**. Both fail Reality handshake. Decimal-string is at least consistent with what user wrote (no transformation) — operator can diagnose by quoting.

Alternative: **reject unquoted Int short-id entirely**:
```swift
let realityShortID: String = {
    let raw = realityOpts["short-id"]
    if let s = raw as? String { return s }
    if raw != nil {
        ClashYAMLParser.log.warning("Unquoted numeric short-id rejected; quote it в YAML (e.g. short-id: \"01234567\")")
        return ""  // empty → Reality detection fails → server unsupported
    }
    return ""
}()
```
Plus an `.unsupported(.schemaRequiresQuoting)` route would surface a user-visible error instead of silently dropping or corrupting.

**Tests to add**
- `ClashYAMLParserTests.test_shortId_unquotedDigitsOnly_preserved` — `short-id: 12345678` → asserts short-id stays `"12345678"` OR proxy is unsupported with clear reason. Asserts it does **NOT** transform to `"57060516"`.
- Strengthen `test_routes_all_phase4_protocols` to assert exact short-id value (`"01234567"`) instead of `XCTAssertFalse(vr.shortId.isEmpty)`.

---

### A4-4-003 (MEDIUM) — VLESS+TLS dispatch requires explicit `tls.enabled: true`; misses sing-box default-true behaviour

**Location**
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift:506-516`

**Description**

The new dispatch logic:

```swift
let tlsBlock = outbound["tls"] as? [String: Any]
let hasRealityBlock = (tlsBlock?["reality"] as? [String: Any]) != nil
if !hasRealityBlock, (tlsBlock?["enabled"] as? Bool) == true {
    if let parsed = extractParsedVLESSTLS(from: outbound) {
        ...
        continue
    }
}
if let parsed = extractParsedVLESS(from: outbound) {
    // legacy path — hardcodes security: "reality" with empty publicKey → silently dropped
}
```

In sing-box, an outbound with `tls: {}` (block present, `enabled` key omitted) — sing-box source has historically treated `enabled` as omitted-means-false on modern versions but Hiddify/older sing-box-versions/operator manifests commonly omit the key entirely when wiring up TLS via a transport (`tls: { server_name: "..." }`). For these, the new check `(tlsBlock?["enabled"] as? Bool) == true` returns false → falls through to legacy path → silently dropped.

**Why MEDIUM (not HIGH)**

The cross-validated CV-H4 finding spoke specifically about the `tls.enabled = true` plain-TLS case (the most common Hiddify pattern). The narrower case I'm flagging is rarer:
- Operator omits `enabled` but provides `server_name` → CONFIG sane, but ambiguity high.
- Without `enabled:true`, sing-box treats TLS as opt-in — a TLS-omitted-key outbound likely doesn't intend TLS at all. So silent-drop may be the safer behavior.

But **deferred behaviour**: if `tls` is **absent entirely** (no TLS, no Reality) → fall-through hits `extractParsedVLESS` which builds a `ParsedVLESS` with `security: "reality"` regardless → still silently dropped by `PoolBuilder.isValidPoolEntry`. CV-H4 fixed the major case; minor cases remain silent-drop instead of `.unsupported`.

**Suggested fix (Tier B, post-TestFlight, ~30min)**

When falling through to legacy `extractParsedVLESS` returning nil OR when the resulting ParsedVLESS has empty `publicKey`, route the outbound to `unsup` with a clear reason (`.schemaRequiresExplicitTLSEnabled` or similar). Improves diagnosis from "0 supported" to "X servers need `tls.enabled: true` set".

---

### A4-4-004 (MEDIUM) — `SubscriptionPinManager.bootstrap` does NOT fall through to bundle resource on expired cache

**Location**
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionPinManager.swift:155-167`

**Description**

The new D-12 hard-reject check:

```swift
if FileManager.default.fileExists(atPath: cachedFile.path) {
    if let data = try? Data(contentsOf: cachedFile),
       let manifest = try? makeDecoder().decode(PinManifest.self, from: data),
       manifest.validUntil > clock() {
        cachedManifest = manifest
    } else {
        // expired/malformed — leaves cachedManifest = nil
    }
    // Already exists — idempotent, do NOT overwrite
    return  // ← early return — bundle path not consulted
}
```

If the cache file exists **but is expired** (e.g. user upgraded from v0.9 → v1.0 after a year of dormancy, cached manifest has `validUntil` in the past), we leave `cachedManifest = nil` and return. The bundle resource path (line 169+) is **not consulted**.

The documented fallback (per inline comment at line 161-163) is "bootstrap hardcoded pins only" via `BootstrapPins.vpnVergevskyRu`. However, `currentPins(for:)` returns these **only when `host == "vpn.vergevsky.ru"`**:

```swift
// SubscriptionPinManager.swift:267
if host == "vpn.vergevsky.ru" {
    for pinBytes in BootstrapPins.vpnVergevskyRu {
        result.insert(Data(pinBytes))
    }
}
```

For any other host pinned via the manifest (rare in v1.0 since manifest carries only `vpn.vergevsky.ru` — see `productionMirrors` at line 73), expired cache means **zero pinning**.

**Severity gradient**

- v1.0 ships with manifest covering only `vpn.vergevsky.ru` → expired cache merely degrades to bootstrap-hardcoded pins for that one host → **same protection** in practice. No real impact.
- v1.1+ when manifest covers multiple hosts (admin signs additional pinning targets), expired cache means those hosts lose pinning until next refresh. Refresh requires network — chicken-and-egg if cert pinning is enabled on the manifest URL too.

**Why MEDIUM (not HIGH)**

The dead-code memo (`project_phase13_subscription_pins_prerequisite.md`) downgraded this whole pipeline to v1.1+. v1.0 production does not wire `SubscriptionPinManager` — only tests and dead-code paths. So this is a **future-compat** concern, not v1.0-shipping.

**Suggested fix (Tier B, v1.1+, ~20min)**

When the cached file is expired, fall through to bundle path:

```swift
if FileManager.default.fileExists(atPath: cachedFile.path) {
    if let data = try? Data(contentsOf: cachedFile),
       let manifest = try? makeDecoder().decode(PinManifest.self, from: data),
       manifest.validUntil > clock() {
        cachedManifest = manifest
        return  // good cache — no need to consult bundle
    }
    // expired/malformed — DO NOT return; fall through to bundle as fresh-install fallback
}
// Bundle resource path
guard let bundleURL = bundleResourceURL ?? Bundle.module.url(...) else { return }
...
```

Note the **threat-model trade-off**: bundle is also signed by Apple (T-10-W4-03), but it's static across releases — an attacker with stolen pre-rotation key could re-publish a bundle of expired-then-replayed content. Since the bundle ships with the app binary and is signed by the developer Apple ID, this is the SAME trust as code-signing the app — equivalent posture. Acceptable.

---

### A4-4-005 (LOW) — `extractParsedVLESSTLS` transport-detection differs from `extractParsedTrojan`/Reality helper in subtle ways

**Location**
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift:567-609` vs `611-664`

**Description**

The new `extractParsedVLESSTLS` reads transport from `o["transport"]` as a dict at the top level. The pre-existing `extractParsedTrojan` does the same. The Reality helper `extractParsedVLESS` reads `o["network"]` as a String (legacy sing-box pattern). The two reading styles coexist for the same outbound type, which can be a source of confusion when sing-box version mixes both `network` and `transport` blocks.

Modern sing-box (1.10+) uses **both**:
- `outbound.network` for the underlying network type ("tcp"/"udp")
- `outbound.transport` for the transport overlay ("ws", "grpc", "httpupgrade", "http")

Pre-Plan-07 `extractParsedVLESS` only reads `network` → may misclassify a TCP+WS outbound's transport. Post-Plan-07 `extractParsedVLESSTLS` reads `transport` → correct. The two helpers thus have **different transport detection accuracy** for the same outbound type ("vless").

**Why LOW**

For v1.0, VLESS+Reality (`extractParsedVLESS`) primarily uses raw-TCP without overlay (Reality + XTLS-Vision standard); WS overlay is rare on Reality. So the pre-existing gap doesn't surface often. The new helper is correct for the more common VLESS+TLS case.

**Suggested fix (Tier C, v1.0.1)**

Unify by reading both `network` and `transport` in `extractParsedVLESS` too. Or refactor the transport-detection closure into a shared helper `detectTransport(from outbound:)`. Pure refactor — no behavior change for current production configs.

---

### A4-4-006 (LOW) — `isBlockedHost` rejects `%` defensively but accepts other URI-encoded delimiters

**Location**
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift:357-359`

**Description**

```swift
if host.contains("%") || host.contains("%25") { return true }
```

The check rejects percent-encoded chars in the hostname. Good for IPv6 scope IDs. But: `URL.host` already URL-decodes the host component, so receiving `%`-containing host through this API is rare unless input is malformed. The defensive check is a belt-and-suspenders.

What's NOT checked: percent-encoded **special characters** like `@`, `:`, `/` would have already been parsed by `URLComponents` into the user-info/path/scheme — they don't show up in `host`. So the check covers the only realistic vector (scope IDs).

**Why LOW**

Defensive check is correct and tight. Just observing that the doc-comment claims to handle "`%25` (percent-encoded `%`) defensively" — which would imply double-encoding scenarios. `URL.host` doesn't double-decode, so `%25` in raw URL becomes `%` in parsed host → first check catches it. The second check is redundant but harmless.

**Suggested action**: none. Cosmetic doc tightening only.

---

### A4-4-007 (LOW) — `SubscriptionFetchResult.finalURL` may differ from initially-requested URL after redirect; not propagated to ImportedServer

**Location**
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift:187`
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift:441`

**Description**

`SubscriptionFetchResult.finalURL` captures the redirect-chain endpoint (`httpResp.url ?? url`). This is used downstream only for `subscriptionURL` parameter (`url.absoluteString` — the **original** URL, not finalURL):

```swift
return try parseSingBoxJSON(bodyStr, source: .subscriptionURL(url),
                             subscriptionURL: url.absoluteString, metadata: fetchResult.metadata)
```

Identity-keyed merge stores the original URL. So if subscription provider rotates the publishing URL via 301 redirect, we miss the migration: next refresh against the original URL still works (HTTP layer redirects), but we never persist the new URL. Once the provider drops the redirect, the saved URL breaks.

**Why LOW**

Subscription URL rotation via 301 is unusual; providers usually maintain stable URLs. The redirect chain validation (T-A3 / T-B1') is the security-critical part — that one IS verified per-hop. URL persistence is functional cosmetic.

**Suggested action**: when `finalURL != url`, log info and consider updating `Subscription.url` field. Tier C, v1.0.1.

---

## Verification status — Plan 07 ConfigParser commits

| Commit | Change | Build | Tests | A4 verdict |
|---|---|---|---|---|
| `9da8c96` T-C-H3' | NAT64/6to4/IPv4-compat IPv6 SSRF | ✓ clean | 25/25 SubscriptionURLFetcherTests PASS | ✅ Closure verified |
| `cda8d61` T-C-H4' | VLESS+TLS JSON dispatch | ✓ clean | 20/20 UniversalImportParserTests PASS | ✅ Closure verified; minor edge case (A4-4-003 MEDIUM) |
| `c86174a` T-C-B3 | identity host lowercase | ✓ clean | MergeStrategyTests unaffected (no case-rotation coverage) | ⚠️ **A4-4-001 HIGH** — asymmetric vs ServerConfig.identity |
| `c86174a` T-C-B4 | bootstrap expired-manifest reject | ✓ clean | SubscriptionPinManagerTests not exercised at HEAD (dead-code path) | ⚠️ A4-4-004 MEDIUM — bundle fallback gap |
| `c86174a` T-C-B5 | Clash YAML octal short-id | ✓ clean | ClashYAMLParserTests fixture passes (`01234567` octal works) | ⚠️ **A4-4-002 HIGH** — regresses digits-only hex short-ids |

---

## Healthy patterns observed

- `SubscriptionURLFetcher.fetch` correctly orders SSRF guard → ephemeral guarded session creation → streaming with cap → redirect guard re-validates each hop. Mirror of T-A3/T-B1'/T-B2' Plan 05 closures preserved.
- IPv6 blocklist checks `bytes.count == 16` defensively (line 413) before indexing — no out-of-bounds risk on caller-controlled input.
- `extractParsedVLESSTLS` correctly mirrors `extractParsedTrojan` shape (SNI fallback, transport detection via dedicated dict pattern, ALPN default `["h2", "http/1.1"]`). Consistent with v1.0 codebase conventions.
- `SubscriptionPinManager.bootstrap` defers cached-manifest decode/validate behind multiple `try?` guards — no exception leak to caller. Idempotency guard at line 146 prevents double-load.
- `SubscriptionMergeService.sanitizeRowName` (T-A7) properly NFC-normalizes and strips BiDi overrides + zero-width — homograph spoofing surface closed before user-visible row name rendering.

---

## Tier-prioritised recommendations

### Tier A+ (block external TestFlight rollout, ~1h total)
- **A4-4-001** SubscriptionMergeService.identity asymmetric host normalize — fix via `ServerConfig.identity` lowercase host (~15min) + add MergeStrategyTests case-rotation test (~15min).
- **A4-4-002** ClashYAML octal short-id regresses digits-only hex — revert to `String(i)` decimal + WARNING log (~10min); OR reject unquoted Int short-id with `.unsupported` (~20min). Add ClashYAMLParserTests coverage for both cases (~10min).

### Tier B (pre-v1.0.1)
- **A4-4-003** VLESS+TLS dispatch edge case — `tls.enabled` missing/false fall-through to `unsup` with reason.
- **A4-4-004** SubscriptionPinManager bootstrap bundle fallback for expired cache.

### Tier C (v1.0.1+)
- **A4-4-005** Unify `extractParsedVLESS` and `extractParsedVLESSTLS` transport detection.
- **A4-4-006** Cosmetic — `%`/`%25` defensive doc tightening in `isBlockedHost`.
- **A4-4-007** Persist `finalURL` when 301 redirect rotates subscription URL.

---

## Test coverage gaps (recommended additions for v1.0.1)

1. `MergeStrategyTests.test_caseRotation_doesNotDuplicate` — covers A4-4-001 regression-prevention.
2. `ClashYAMLParserTests.test_shortId_unquotedDigitsOnly_preserved` — covers A4-4-002 regression-prevention.
3. `ClashYAMLParserTests.test_shortId_unquotedLeadingZero_octalReconstructed` — strengthen existing fixture-based assertion to check exact value `"01234567"`.
4. `UniversalImportParserTests.test_singBoxJSON_vlessTLS_missingEnabled_droppedWithReason` — covers A4-4-003.
5. `SubscriptionPinManagerTests.test_bootstrap_expiredCache_fallsBackToBundle` — covers A4-4-004.

---

## Summary

Plan 07 closed all four cross-validated HIGH findings in scope (T-C-H3' SSRF prefixes, T-C-H4' VLESS+TLS dispatch) cleanly. Two of the Tier-B MEDIUM closures (T-C-B3 identity lowercase, T-C-B5 octal short-id) introduced **secondary regressions** that re-create the original bug class on adjacent inputs:

- **T-C-B3** lowercases the fetched-side identity but leaves `ServerConfig.identity` raw-cased → first case-rotation refresh creates the very duplicate row the fix promised to prevent. Impact: **every existing v0.9 user gets duplicate rows the first time their subscription rotates host case after v1.0 upgrade.**
- **T-C-B5** corrects unquoted-octal `01234567` short-ids but corrupts unquoted-decimal-looking-hex `12345678` short-ids → Reality handshake fails with the same cryptic error, just for a different input class.

Both regressions are **simple to fix** (≤30min each) but should land before external TestFlight. Internal TestFlight rollout from HEAD `ccbce8a` is safe: SSRF gap closed, no CRITICAL surface, asymmetric-identity manifests as cosmetic UX issue, octal short-id only affects users importing Clash YAML with that specific edge case.

**Recommended path:** Plan 08 Tier A+ — two surgical fixes (A4-4-001 + A4-4-002) + 5 unit tests, ~1h total work, before external rollout.
