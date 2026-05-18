# BBTB BACKLOG — Deferred items post Plan 09 closure

**Last updated:** 2026-05-18 (после Plan 09 carved-scope closure, 23 PRs merged)
**Status:** TestFlight Internal Distribution unblocked. External Rollout / v1.1+ candidates listed below.

---

## §1 — Carved-out findings из Plan 09 scope

Эти конкретные findings были identified во время Plan 09 fix-up cycle но НЕ closed (либо because scope was too big, либо because audit lacked specifics).

| ID | Source | Severity | Reason carved | Action к закрытию |
|---|---|---|---|---|
| **A6-SET-3-002** | AUDIT-4 | MEDIUM | `routingRulesEnabled` toggle lacks live-apply — needs broader UserDefaults observer + reconnect-banner wiring matching killSwitch pattern (handleUserDefaultsChange:1128) | Mirror `app.bbtb.killSwitchEnabled` observer flow в MainScreenViewModel: add `lastRoutingRulesValue` field, fire `reconnectBannerState = .killSwitchReconfigure`-equivalent (e.g. `.routingRulesReconfigure` new case) on change while connected. ~2-3h. |
| **A4-4-005** | AUDIT-4 | LOW | VLESS+TLS transport-detection «differs from Trojan helper в subtle ways» — audit lacks specific code references | Read both transport-detection helpers через Codex parallel diff scan. Document differences. ~2h investigation. |
| **~21 Plan 06 carry-forward LOWs** | AUDIT-4 | LOW | "Mostly Plan 06 carry-forwards" — not enumerated в AUDIT-4 | Run Periphery scan via existing `.periphery.yml` baseline; compare к saved 489 findings (118 unused properties + 108 redundant public ACL + 70 unused functions). Triage actionable subset. ~4h. |

---

## §2 — Future-forward concerns acknowledged Codex'ом

Codex Code Reviewer caught эти items в PR reviews но классифицировал as «acceptable for this fix, address in v1.1+». Each marked **NOT a regression**.

| Concern | Where | Risk profile |
|---|---|---|
| **App Group identifier duplicated** | `KillSwitch.appGroupSuiteName` + `AppGroupContainer.identifier` + `TunnelController.ExternalVPNStopMarker` + `ConfigImporter` (5+ sites) | Silent drift breaks extension↔main-app UserDefaults exchange. Mitigated via dual pin tests (PR #18 + #22). True fix: extract к shared `CommonAppConfig` package or VPNCore. |
| **SSRF byte-classifier duplicated** | `ConfigParser.SubscriptionURLFetcher.isBlockedHost` (canonical) + `FrontingEngine.FrontingConfigApplier.isPrivateOrLoopback` (inlined PR #14) + `JSONEndpointFetcher` (uses canonical) + `PinnedSessionDelegate` (uses canonical) | Drift risk если canonical evolves but FrontingEngine inline copy doesn't follow. Documented в wiki R25 v1.1+. True fix: extract `NetworkUtils` shared package. |
| **TOCTOU symlink** | `SingBoxConfigLoader.validate` rule_set check (PR #10) | Attacker swaps file → symlink между validator и libbox open. Closing needs libbox-side `O_NOFOLLOW`. Out of BBTB code control. |
| **lastPersistedTransport stale** | `ServerDetailViewModel.applyTransportSelection` (PR #11) | Subscription background refresh could mutate `server.transportOverride` while VM open. Shadow becomes stale. Не present scenario today; flag if subscription auto-refresh added. |
| **VPNCore.version source-breaking** | `VPNCore.swift` (PR #23) | Restored as @available(deprecated) shim. Real removal at v1.1+ after one release window для consumers. |
| **TransportRegistry post-freeze register**  | `TransportRegistry.register()` (PR #18) | Silent no-op after freeze. Production has no re-register paths; if future plugin/extension scenario adds them, need to surface assertionFailure or os.Logger. |
| **Reconnect Task stale state** | `MainScreenViewModel.reconnectAfterSelectionChange` (PR #16) | If iOS never emits `.connected` event after `tunnel.connect()` success, `pendingReconnectTask` stays non-nil forever (completed Task reference). Не data leak; flag только если NE behaviour changes. |

---

## §3 — Systemic architectural patterns (AUDIT.md «Patterns Observed»)

7 systemic patterns identified в original AUDIT.md (pre Plan 09). Plan 09 closed individual instances but not the systemic root cause.

1. **Validation duplicated в `buildSingBoxJSON` template path vs `buildOutbound` dict path** (C8 cross-protocol). Template paths валидируют port/required-fields; dict paths trust public parsed structs. If template paths dead → delete. If live → centralize validation в shared helper. **Status:** не addressed.

2. **SSRF guard pattern copied 3+ times** — see §2 row 2 above.

3. **`@unchecked Sendable` без synchronization** в 3+ packages:
   - `BaseSingBoxTunnel` (A1-004) — fixed в Plan 09 PRs #5, #8, #9, #16
   - `ConfigImporter` (A3-005) — fixed в PR #7
   - `KillSwitch.appGroupSuiteName` (A6-016) — fixed в PR #18 (`let` instead of `var`)
   - `ExtensionPlatformInterface` (C1-002) — fixed в PR #8
   - **Systemic audit** of remaining `@unchecked Sendable` declarations not done.

4. **`UserDefaults(suiteName:)` hot-path reads** в multiple packages without caching (A1-002, A1-014, A3-008, A6-016). Cross-process eventual consistency может cause toggle staleness. **Action:** cache snapshot at tunnel start; explicit refresh trigger on settings change. ~3-4h.

5. **`fatalError` в production paths** (A1-011 AppGroupContainer when no App Group entitlement, C1-006 same). Especially в extension which has limited diagnosability. **Action:** map к throwing error, surface к user via state machine. ~2h.

6. **Replay protection через monotonic version + wallclock manipulation susceptibility** в RulesEngine (A5-007, C5-003). Fresh install resets version → any signed manifest accepted. **Fix:** signed `updated_at` field + freshness window. ~4-6h.

7. **Phase 8 W7 closure mismatch** despite ROADMAP showing Phase 8 ✅:
   - Placeholder Ed25519 pubkey (A5-001, A4-007 separate site)
   - `rules.bbtb.example` mirror URLs (A5-014)
   - Real cert/signing key never published
   - **Status:** Status mismatch — verify Phase 8 closure assumptions before External Rollout.

---

## §4 — Earlier audit findings not touched by Plan 09

Plan 09 scope was specifically AUDIT-4 «External TestFlight BLOCK» carved findings. Earlier audits (AUDIT.md, AUDIT-2.md, AUDIT-3.md) had additional findings что НЕ были revisited:

| Audit | Tier C (next iteration) | Tier D (cleanup) | Closed by Plan 09? |
|---|---|---|---|
| AUDIT.md | All MEDIUM + remaining HIGH (FrontingEngine, deep-link logging) | XrayFallback dead module, unused L10n, stale TODOs, force-cast cleanup | Partial — FrontingEngine NAT64 closed (#14); deep-link logging redaction was T-B7 (closed pre-Plan 09); unused L10n NOT scanned |
| AUDIT-2.md | ~30 MEDIUM + ~50 LOW backlog | Same theme — defensive coding, docs, code-style | NOT touched systematically |
| AUDIT-3.md | 45+ LOW findings (`PublicKey.swift` placeholder bytes drift, DEBUG trace log size, command.sock 103-char limit) | Same | NOT touched (overlap с AUDIT-4 partial) |

**Notable specific items от AUDIT-3:**
- `L-A5-3-09 / C5'-3-005` — `PublicKey.swift` doc claims placeholder bytes `0x00..0x1F` но actual bytes are `0xB5, 0x3F, 0xCF, 0xC3, ...`. **Needs project owner clarification** whether real keypair committed или non-trivial placeholder used.
- `A1'-3-008..013` — DEBUG trace log size, `fatalError` before logging, `print` vs TunnelLogger, subsystem name mismatch, command.sock 103-char limit assertion, dead `PacketTunnelKit.version = "0.1.0"` (closed similarly к VPNCore.version в PR #23 via deprecated shim — verify).

---

## §5 — Memory-tracked deferred items (per `memory/`)

Items already deferred с явным reason в auto-memory:

| ID | Memory entry | Scope |
|---|---|---|
| **libbox log privacy switch** | `feedback_libbox_log_privacy_external_rollout.md` | `.public` для Internal TestFlight OK; перед External Rollout сменить writeDebugMessage + send notification body privacy на `.private` (Plan 07 Q5) |
| **SPKI subscription pins** | `project_phase13_subscription_pins_prerequisite.md` | DOWNGRADED к v1.1+ — placeholder pins = dead code; `SubscriptionPinManager.performBackgroundRefresh` не вызывается из production. v1.0 uses standard HTTPS+ATS. |
| **Phase 9 Deep Links Wave 4** | `project_phase9_paused.md` | W1-W3 implemented (17/17 + 164/164 tests); paused on: AASA deployment `import.bbtb.app` + Apple Portal Associated Domains + device UAT |
| **Apple Distribution credentials** | `project_phase13_distribution_creds_prerequisite.md` | Automatic Xcode-managed signing достаточно для Internal TestFlight. Manual creds + External Testing → v1.1+ |

---

## §6 — UAT items pending

Test plans listed в PR descriptions что НЕ executed:

- **CV-2-H5 (PR #9):** «Device UAT: trigger startTunnel error path concurrent with stopTunnel — should not crash»
- **CV-2-H6 (PR #10):** symlink attack — manual device repro
- **CV-2-H4 (PR #8):** ExtensionPlatformInterface stateQueue audit — real-device verification
- **A3-H-03 (PR #16):** rapid C→B→C selection-change race verification on device
- **A6-SET-3-001 (PR #19):** STUN alert backdrop dismiss UX flow on device
- **A6-DL-3-001 (PR #21):** deep-link `bbtb://import?url=file://...` rejection — manual repro

**Status:** Plan 09 verified через CI + Codex peer review + CodeRabbit. Device UAT — separate gate.

---

## §7 — Architectural / v1.1+ refactor candidates

Items не critical для TestFlight но улучшат maintainability:

1. **Extract shared constants package** (`CommonAppConfig` or VPNCore) для App Group identifiers, key strings (§2 row 1).
2. **Extract shared `NetworkUtils` package** для IP byte-classifier (§2 row 2).
3. **Real Ed25519 keypair publication + signed manifest publishing infra** (§3 row 7).
4. **Periphery integration в CI** для systematic unused-code detection (§1 row 3).
5. **`@unchecked Sendable` systematic audit** (§3 row 3).
6. **UserDefaults caching layer** (§3 row 4).
7. **fatalError → throwing migration** (§3 row 5).
8. **Replay protection signed `updated_at`** (§3 row 6).
9. **Cross-package test harness** для integration-level checks (App Group constants, key drift, etc.) — currently each package tests are siloed.

---

## §8 — Metrics

**Closed in Plan 09 (23 PRs):**
- 13 HIGH (all carved AUDIT-4 HIGH)
- 9 MEDIUM (7 of 8 A6 cluster + T-C-B1 + implicit)
- 4 LOW (3 explicit + dead-code shim)
- **Total: 26 findings**

**Deferred (estimate):**
- 3 items carved-out in Plan 09 (§1)
- 7 future-forward future Codex review items (§2)
- 7 systemic patterns (§3)
- ~80+ unaddressed earlier-audit MEDIUM/LOW (§4)
- 4 memory-tracked items (§5)
- 6+ UAT items (§6)
- 9 v1.1+ refactor candidates (§7)
- **Estimated total: ~120 items deferred**

**Coverage:** ~25-30% of all audit-identified findings across all audits closed. Plan 09 scope «External TestFlight BLOCK» — 100% closed.

---

## §9 — Cross-references

- AUDIT-4: `.planning/phases/13-testflight-internal-distribution/AUDIT-4.md`
- AUDIT-3: `.planning/phases/13-testflight-internal-distribution/AUDIT-3.md`
- AUDIT-2: `.planning/phases/13-testflight-internal-distribution/AUDIT-2.md`
- AUDIT: `.planning/phases/13-testflight-internal-distribution/AUDIT.md`
- Wiki R25 (drift): `wiki/security-gaps.md`
- Phase 9 resume plan: `.planning/phases/09-deep-links/09-RESUME.md` (if exists)
- Memory: `~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/MEMORY.md`
