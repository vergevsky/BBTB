# A1' — PacketTunnelKit re-audit (Opus 4.7)

**Baseline:** commit `55523dd` (main, Plan 03 closure)
**Scope:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/` — 11 swift files + 1 JSON resource
**Re-audit mode:** Plan 04 verification of Plan 02 CRITICAL/HIGH closures + regression scan + new-issue sweep.

---

## Plan 02 CRITICAL/HIGH Closure Verification

| Plan 02 Finding | Plan 03 Fix Commit | Re-audit Status | Notes |
|---|---|---|---|
| A1-001 STUN-block `tag` field schema mismatch | T-B9 (`78e216f`) | ✅ Closed | `SingBoxConfigLoader.swift:412-418` — idempotency check теперь fingerprints на `action=="reject" && network=="udp" && ports==[3478,5349]`. Rule injection (`:424-429`) no longer emits `"tag"` field. Schema-compliant с sing-box 1.13 `route.rules[]` (where `tag` is not a valid key). Comment block (`:405-411`) explicitly documents rationale. Verified: повторный вызов `expandConfigForTunnel` после schema normalize не дублирует STUN rule. |
| C1-001 commandServer leak on validate failure | T-B9 (`78e216f`) | ✅ Closed | `BaseSingBoxTunnel.swift:312-319` (expand fail) + `:331-336` (post-expand validate fail) теперь mirror step-6 cleanup pattern (`:275-277`): `server.close()` + `self.commandServer = nil` + `self.platformInterface = nil` + `endLibboxStart()` ДО `completionHandler`. Libbox resource lifecycle полностью симметричен между success и failure paths. |
| A1-002 UserDefaults toggle staleness | — (carry-fwd Tier C) | ⏸️ Carry-forward | Still 3 separate `UserDefaults(suiteName:)` instantiations внутри `expandConfigForTunnel` (`:325`, `:400`, `:451`). Per-call cost acceptable для startTunnel hot path (~1×/session), no regression introduced. |
| A1-003 idempotent contract | — (carry-fwd Tier C) | ⏸️ Carry-forward | Idempotency для blocks 5+6+7 sound. Block 6 fingerprint approach (T-B9) — stronger than previous tag-based check. |
| C1-002 ExtensionPlatformInterface `@unchecked Sendable` | — (carry-fwd Tier C) | ⏸️ Carry-forward | Still relies on documented "Go runtime serializes callbacks" contract. No synchronization primitives added; deferred к v1.1+. |
| C1-003 validate accepts non-dialable group | — (carry-fwd Tier C) | ⏸️ Carry-forward | `proxyOutboundTypes` whitelist (`SingBoxConfigLoader.swift:69-73`) unchanged. sing-box engine rejects downstream. |

**Closure verdict:** Оба HIGH (A1-001, C1-001) — **valid closures**. No regression in T-B9 fix paths.

---

## Regressions Detected

### None from PacketTunnelKit-targeted Plan 03 fixes.

**SRSCacheStore `commitTransaction` impact assessment (Plan 04 prompt item 2):**
PacketTunnelKit reads SRS files via sing-box `route.rule_set[].path` declarations injected in `SingBoxConfigLoader.swift:344-351`. These paths are explicit (`bbtb-baseline-block.srs`, etc.), not glob patterns. Plan 03 T-A1 introduced `*.bbtb-staging` suffix transient files in the same directory — but because sing-box `type: "local"` rule_sets resolve by exact path, the staging files do NOT pollute the reader path. `FileManager.replaceItemAt` atomically renames staging → final, so reader (libbox `fswatch.Watcher`) sees old-or-new, never partial. **No regression.**

One minor cosmetic note (LOW): the staging suffix files могут оставаться на диске after partial failures (`SRSCacheStore.swift:77-80` documents this) — these aren't read by sing-box, but slowly accumulate. Not security-relevant.

---

## New Findings

### [LOW] A1'-001: `UserDefaults(suiteName:)` instantiated 3× in single `expandConfigForTunnel` call
- **Location:** `SingBoxConfigLoader.swift:325`, `:400`, `:451`
- **Dimension:** performance (minor) | code-smell
- **Description:** `expandConfigForTunnel` создаёт separate `UserDefaults(suiteName: AppGroupContainer.identifier)` instances для каждого of three feature toggles (`routingRulesEnabled`, `stunBlockEnabled`, `muxEnabled`). Each instantiation touches CFPreferences plist cache. Cheap (~10-100µs each), but pattern multiplies if more toggles added in Phase 14+.
- **Why it matters:** Strictly cosmetic now (3 calls per startTunnel, <1ms total). Becomes meaningful if future phases add more block-N toggles. Also creates inconsistency: block 5 uses `object(forKey:)` для default-true semantic, blocks 6/7 use `bool(forKey:)` (which silently defaults к false even if key absent — opposite default). Easy footgun for new toggles.
- **Suggested fix:** Hoist single `let appGroup = UserDefaults(suiteName: AppGroupContainer.identifier)` at function top. Or add typed helper `static func toggle(_ key: String, default: Bool) -> Bool` to centralize default-semantic choice. Defer к Phase 14 если новые toggles вводятся; standalone fix не nét value.

---

### [LOW] A1'-002: `singBoxLogPath` directory may not exist on first cold launch (extension side)
- **Location:** `AppGroupContainer.swift:95-97` + consumer `BaseSingBoxTunnel.swift:296`
- **Dimension:** bugs (DEBUG-only) | edge case
- **Description:** `singBoxLogPath` возвращает `url.appendingPathComponent("sing-box.log").path` — это путь напрямую в App Group **root**, not в subdir. `rulesCacheDirectory` / `crashReportsURL` / `certPinManifestDirectory` все идемпотентно создают свои subdirs. Root уже существует (libbox creates it during `LibboxBootstrap.setup`), но если sing-box engine tries to open `sing-box.log` before libbox setup completes — fail silently. На практике порядок в `BaseSingBoxTunnel.startTunnel` правильный (setup at step 3, line ~236, logPath used at step 7, line ~302), so this is theoretical only.
- **Why it matters:** DEBUG-only path. Release builds set `singBoxLogPath: String? = nil` (`BaseSingBoxTunnel.swift:299`). Not a TestFlight issue.
- **Suggested fix:** None for v1.0 (Release path nullifies). If staying в Phase 13 — add `singBoxLogPath` precondition check в DEBUG-only assertion.

---

### [LOW] A1'-003: `firstProxyTag` fallback к hardcoded `"vless-out"` when no proxy outbound found
- **Location:** `SingBoxConfigLoader.swift:278` (block 3) + `:368` (block 5)
- **Dimension:** logic | bugs (defensive fallback violates validate contract)
- **Description:** Both block 3 (`route.final` fix) and block 5 (rule_set always→outbound) fall back на literal `"vless-out"` string when `outbounds` array doesn't contain a proxy outbound type. **But** `validate(json:)` (which runs before `expandConfigForTunnel` в production path — `BaseSingBoxTunnel.startTunnel:224`) уже throws `noProxyOutbound` если no `proxyOutboundTypes` matched (`SingBoxConfigLoader.swift:113-117`). So this fallback should be unreachable in production. Если кто-то когда-то вызовет `expandConfigForTunnel` без предварительного `validate` (e.g., test paths, future API consumer) — мы тихо инжектим reference на несуществующий tag, и post-expand validate at `:121-130` poolу throws `unresolvedOutboundRef(ref: "vless-out", in: "selector")` (если есть urltest/selector group), OR sing-box engine startService later рейзит cryptic error.
- **Why it matters:** Low — production path validates first. Defence-in-depth: defaulting к non-existent tag is worse than `precondition` failure (silent corruption vs. loud crash). Pre-TestFlight: no exploit, no crash в normal flow.
- **Suggested fix:** Replace fallback с `preconditionFailure("expandConfigForTunnel called without prior validate — no proxy outbound found")`, OR — safer — make `expandConfigForTunnel` internally call `try validate(json:)` first as defensive prefix (idempotent с external validate; cost negligible).

---

### [LOW] A1'-004: `expandConfigForTunnel` block 5 + 6 + 7 read App Group UserDefaults inside loops без snapshot
- **Location:** `SingBoxConfigLoader.swift:324-332` (routingRulesEnabled), `:400-401` (stunBlockEnabled), `:451-452` (muxEnabled)
- **Dimension:** performance | thread-safety (defence-in-depth)
- **Description:** Re-statement of Plan 02 A1-002 carry-forward, no fix applied. Each read is a separate process-level cross-process CFPreferences lookup. На extension cold-start sandbox preferences plist потенциально not yet loaded → first read может тригернуть disk fetch (~ms). Subsequent reads cached. Acceptable now (3 reads × 1 startTunnel = 3 disk fetches max on cold), but reading toggles inside `expandConfigForTunnel` means future re-expand calls (which currently don't happen but could be added для config hot-reload) would repeatedly hit IPC.
- **Why it matters:** Today, low. Becomes meaningful if Phase 14+ introduces config hot-reload or per-network-change re-expand.
- **Suggested fix:** Snapshot all 3 toggles at function entry, pass as parameters внутрь helper. Aligns с DEC-06d-01 cold-start defer pattern (memory feedback) and DEC-06d-02 ≤2 XPC trips pattern.

---

### [MEDIUM] A1'-005: `BaseSingBoxTunnel.startTunnel` does NOT clear `physicalInterfaceSeeded` on error-paths before retry
- **Location:** `BaseSingBoxTunnel.swift:312-319, :331-336, :361-368` + `ExtensionPlatformInterface.swift:58-59, :76-81`
- **Dimension:** bugs | thread-safety (Swift 6 strict concurrency)
- **Description:** `ExtensionPlatformInterface.physicalInterfaceSeeded: Bool` (`:59`) plus `physicalInterfaceReady: DispatchSemaphore(value: 0)` (`:58`) form the M9/06D-03g seed-wait protocol. The comment at `:71-75` claims "instance lives exactly one startTunnel/stopTunnel cycle". This is **mostly** true — `BaseSingBoxTunnel.startTunnel` creates a fresh `pi = ExtensionPlatformInterface(...)` at `:249` and `stopTunnel` sets `platformInterface = nil` at `:406`. **However**, T-B9 closure introduced 3 new failure paths (`:316`, `:333`, `:364`) that explicitly set `self.platformInterface = nil` and `self.commandServer = nil`. If on-demand iOS retries startTunnel rapidly (within same extension process — before sandbox refresh), a stale `physicalInterfaceReady` semaphore from a *previous* failed start could be re-signaled. Actually re-examining: new `pi` is instantiated each call, so the semaphore is per-instance. **Verified safe.** Withdraw to LOW.
- **Why it matters:** No actual bug — per-instance semaphore makes this immune. Documenting for posterity since cleanup pattern was new.
- **Suggested fix:** None. Re-classify as LOW informational; comment on `:71-75` could be tightened to explicitly mention error-path cleanup also re-creates instance.

(Downgraded to LOW — no actionable fix.)

---

### [MEDIUM] A1'-006: `SingBoxConfigLoader.validate` does not check `route.rule_set` paths for traversal
- **Location:** `SingBoxConfigLoader.swift:75-131` (`validate`) + `:344-351` (rule_set inject)
- **Dimension:** security (defence-in-depth) | bugs
- **Description:** `expandConfigForTunnel` block 5 injects `route.rule_set[].path` values of the form `"\(rulesDir)/\(file)"` where `file ∈ {"bbtb-baseline-block.srs", "bbtb-baseline-never.srs", "bbtb-baseline-always.srs"}` — all hardcoded. **However**, `validate(json:)` does not enforce that any user-supplied JSON (i.e., the freshly-imported `configJSON` before expand) does NOT already contain its own `route.rule_set[]` entries with path-traversal payloads. If a malicious subscription / paste introduces e.g. `{"type":"local","path":"/etc/passwd","format":"binary"}`, sing-box would try to mmap that path for rule-set lookup. R10 invariants only check inbounds and experimental APIs — not rule_set paths. Today, `ConfigImporter` produces sing-box JSON via `PoolBuilder.buildSingleOutboundJSON` which never emits rule_set entries (those are added by `expandConfigForTunnel`), but ANY adversarial templates / future raw-JSON imports could carry them. Plan 02 closed cluster 1 (raw template removal via T-A2), reducing this surface, but `validate` itself doesn't enforce.
- **Why it matters:** Low immediate risk (no production path emits adversarial `rule_set`). Defense-in-depth gap. Sing-box reading `/etc/passwd` would fail (wrong format), but the attempt itself is undesirable. With Phase 8 future signed-manifest rules pipeline pulling from server-controlled manifests, this surface widens.
- **Suggested fix:** Add к `validate(json:)` post-section: if `route.rule_set` array present, verify each entry's `path` (if any) is bare-filename or starts с `AppGroupContainer.rulesCacheDirectory.path` prefix. Reject otherwise. Mirrors T-A1 RulesEngine path-traversal guard.

---

### [LOW] A1'-007: `BaseSingBoxTunnel` stores credentials-like config in providerConfiguration without encryption note
- **Location:** `BaseSingBoxTunnel.swift:187-192`
- **Dimension:** security (informational)
- **Description:** `providerConfiguration["configJSON"]` extracted from `NETunnelProviderProtocol`. This dictionary является unencrypted в `NEVPNManager` preferences and persistent across reboots (per Apple's NEVPNManager documentation, although stored in protected Keychain wrapper for the manager itself). The configJSON contains UUIDs, Reality public keys, fingerprints, SNI — sensitive enough that если device passcode bypass occurs, `defaults read` (or `security find-generic-password` for the NEVPN service) could expose. KeychainStore.swift Plan 03 fix (T-B3) addressed credentials surface; provider config remains in NEVPNManager. **This is Apple-standard practice** (WireGuard iOS, OutlineVPN, sing-box-for-apple all do the same), but worth noting в audit trail. No code change recommended for v1.0.
- **Why it matters:** Informational only. NEVPNManager prefs encrypted-at-rest by iOS (Data Protection class `NSFileProtectionCompleteUntilFirstUserAuthentication` per Apple); if attacker has root + post-FU passcode-unlocked device, they have everything anyway.
- **Suggested fix:** None for v1.0. Document в `wiki/security-gaps.md`: «config secrets stored в NEVPNManager prefs — standard NE pattern, encrypted by iOS Data Protection».

---

### [LOW] A1'-008: `openTun` semaphore-on-error 2s timeout can racing with iOS deadlock
- **Location:** `ExtensionPlatformInterface.swift:115-135`
- **Dimension:** thread-safety | bugs
- **Description:** `openTun` waits 2s on `setTunnelNetworkSettings` completion. Если completion fires **after** timeout but **before** `pi` deinit (e.g., 2.5s later) — the closure captured `semaphore` calls `semaphore.signal()` on dead semaphore, which is benign, AND writes к `errorBox.value.error` — also benign (struct value already gone из scope). But `provider.setTunnelNetworkSettings` may NOT call its completion at all if iOS provider queue truly deadlocks (Phase 1 hypothesis). На production iPhone 13+ — never observed. Safe modulo M9 retry-throw via `autoDetectControl`.
- **Why it matters:** Low — production-tested through Phases 6c/6d. T-B9 didn't alter this code.
- **Suggested fix:** None. Already documented well в comments.

---

## Notes

- **Verified files (read end-to-end):** `SingBoxConfigLoader.swift` (490 lines), `BaseSingBoxTunnel.swift` (423 lines), `ExtensionPlatformInterface.swift` (547 lines), `AppGroupContainer.swift`, `ExternalVPNStopMarker.swift`, `TunnelSettings.swift`, `InterfaceFlagsInspector.swift`, `TunnelLogger.swift`, `PacketTunnelKit.swift`, `PlatformSpecific/iOS.swift`, `PlatformSpecific/macOS.swift`, `Resources/SingBoxConfigTemplate.vless-reality.json`.
- **T-B9 quality verdict:** Clean, minimal-diff fix. STUN injection теперь fingerprint-based (sturdier than tag-based). commandServer cleanup correctly mirrors step-6 throw path. No collateral damage.
- **SRSCacheStore staging suffix regression check:** Negative. sing-box reads explicit paths, not globs. `.bbtb-staging` transient files invisible к extension read path.
- **Counts:** 0 CRITICAL · 0 HIGH · 1 MEDIUM (A1'-006 — `validate` rule_set path-traversal gap, defence-in-depth) · 7 LOW (mostly informational).
- **TestFlight gate verdict для PacketTunnelKit:** ✅ Clear. Plan 02 PacketTunnelKit cluster (A1-001 + C1-001) successfully closed. A1'-006 — recommended but not blocking; baseline RulesEngine produces no adversarial `rule_set` entries в production path. Tier C/D backlog acceptable.

**Word count:** ~1900 words (under 3000 ceiling).
