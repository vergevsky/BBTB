# BBTB BACKLOG — Deferred items post Plan 09 closure

**Last updated:** 2026-05-18 (после Plan 09 carved-scope closure, 23 PRs merged + Tier prioritization)
**Status:** TestFlight Internal Distribution unblocked. External Rollout requires Tier 1 closure (см. §10).

**Quick navigation:**
- 📋 §1-§9 — inventory of all deferred items by source
- 🎯 §10 — **Tier prioritization** (read this первым при возобновлении работы)

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

---

## §10 — Tier prioritization (action plan)

**Critical path к External Rollout:** ~20-25h dev work + AASA deploy + 2-3h device UAT session.
**(Tier 1 #3 owner clarification ✓ completed 2026-05-18 — PublicKey.swift bytes confirmed non-trivial placeholder.)**

Prioritization criteria:
- **(а) Severity / user-impact**
- **(б) Blocking gate** (Internal TF → External Rollout → v1.0 → v1.1+)
- **(в) Effort**
- **(г) Dependencies** (что unblocks)

---

### 🚨 Tier 1 — Block External Rollout (must close before public release)

| # | Item | Effort | Why critical | Source |
|---|---|---|---|---|
| 1 | **Phase 8 W7 real Ed25519 key + signed manifest publishing infra** | 3-4h + infra | RulesEngine отказывается работать с placeholder pubkey; `rules.bbtb.example` URLs — заглушки. Без этого fetch broken в production. | §3 row 7, §4 AUDIT-3 |
| 2 | **libbox log privacy `.public` → `.private`** | 30 мин | Diagnostic exports могут leak sensitive sing-box state в Console/sysdiagnose. | §5 (memory `feedback_libbox_log_privacy_external_rollout.md`) |
| 3 | ~~**PublicKey.swift placeholder bytes clarification**~~ **✓ CLOSED 2026-05-18** | (0 — owner clarified) | Owner confirmed: **нетривиальная заглушка** (specially crafted to pass Ed25519 point validation), NOT real keypair. Plan 07 T-C-D2 уже addressed это; AUDIT-3 finding был stale. См. `wiki/rules-engine.md` § «Закрытые / принятые решения». | §4 AUDIT-3 L-A5-3-09 (stale) |
| 4 | **Phase 9 Deep Links Wave 4** | AASA deploy + 2h UAT | Code готов (17/17+164/164 тестов), но AASA `import.bbtb.app` не задеплоен → Universal Links не работают. Apple Portal Associated Domains + device UAT pending. | §5 (memory `project_phase9_paused.md`) |
| 5 | **Device UAT items (6+)** | 2-3h device session | CV-2-H4..H6, A3-H-03, SET-3-001, DL-3-001 — verified через CI + peer review, но реальный device-test не делался. Race conditions проявляются только under live network conditions. | §6 |

**Decision rule:** прежде чем подавать на External Testing в App Store Connect — закрыть всё в Tier 1.

---

### 🟠 Tier 2 — High-value correctness (significant risk reduction)

| # | Item | Effort | Why valuable | Source |
|---|---|---|---|---|
| 6 | **`@unchecked Sendable` systematic audit** | 4-6h | Plan 09 закрыл известные instances в 4 packages, но systematic grep всех `@unchecked Sendable` declarations не сделан. Hidden data races. | §3 row 3 |
| 7 | **`fatalError` → throwing migration** | 2h | `AppGroupContainer` fatalErrors если no App Group entitlement; extension не может surface это к user → silent crash. Especially diagnosable в Production. | §3 row 5 |
| 8 | **Replay protection signed `updated_at`** | 4-6h | Fresh install resets version → any signed manifest accepted (RulesEngine). Attacker с stale signed manifest + correct sig — accepted as fresh. | §3 row 6 |
| 9 | **A6-SET-3-002 routingRulesEnabled live-apply** | 2-3h | User toggles routing rules ON while connected — ничего не происходит до restart tunnel. UX inconsistency. Pattern уже есть для killSwitchEnabled. | §1 |
| 10 | **`UserDefaults(suiteName:)` caching layer** | 3-4h | Hot-path reads в 4+ packages без caching — cross-process eventual consistency может cause toggle staleness. Hidden bugs. | §3 row 4 |

**Decision rule:** закрыть для confidence в production stability under load.

---

### 🟡 Tier 3 — Architecture / maintainability (v1.1+ candidates)

| # | Item | Effort | Why useful | Source |
|---|---|---|---|---|
| 11 | **Extract `CommonAppConfig` shared package** | 3-4h | Single source of truth для App Group identifier, Bundle IDs, suite names. Replaces 3+ pin-test mitigations (PRs #18, #22). | §7 item 1, §2 row 1 |
| 12 | **Extract `NetworkUtils` shared package** | 2-3h | Single SSRF byte-classifier. Replaces 3+ inline copies (ConfigParser + FrontingEngine PR #14 + JSONEndpointFetcher). Eliminates R25 drift risk. | §7 item 2, §2 row 2 |
| 13 | **Validation dedup `buildSingBoxJSON` template vs dict** | 4-8h | Template paths валидируют port/required-fields; dict paths trust public structs. Either delete dead templates OR centralize. | §3 row 1 |
| 14 | **Periphery CI integration** | 2h | Systematic unused-code detection. Baseline уже сохранён (489 findings). CI lint to prevent regression. | §7 item 4 |
| 15 | **Cross-package integration test harness** | 4-6h | Tests for App Group constants drift, config end-to-end flow, etc. Currently each package siloed. | §7 item 9 |
| 16 | **PacketTunnelKit.version deprecated shim removal** | 30 мин | Mirror PR #23 pattern для остальных stale version strings (already removed via "Was:" comment). Audit residual. | §4 AUDIT-3 |

**Decision rule:** delayed к v1.1+ unless team capacity allows.

---

### 🟢 Tier 4 — Cleanup / cosmetic

| # | Item | Effort | Source |
|---|---|---|---|
| 17 | **A4-4-005 VLESS+TLS vs Trojan investigation** | 2h | §1 |
| 18 | **~21 Plan 06 carry-forward LOWs** | 4-6h (Periphery scan + triage) | §1 |
| 19 | **34 unused L10n accessors** | 1-2h (после Periphery) | §4 AUDIT.md |
| 20 | **XrayFallback cleanup decision** | 30 мин — либо delete либо confirm Phase 4+ scope | §7 item 5 |
| 21 | **VPNCore.version real removal** | 5 мин (v1.1+) | §2 row 5 |
| 22 | **TransportRegistry post-freeze noisy logging** | 30 мин | §2 row 6 |
| 23 | **Stale TODO comments / `Phase X` references к закрытым phases** | 1h | §4 |

**Decision rule:** address opportunistically когда трогаешь соседний код.

---

### 🔵 Tier 5 — Out of BBTB code control (track but don't fix)

- **TOCTOU symlink protection** — needs libbox-side O_NOFOLLOW (upstream sing-box change). Track upstream PR / fork.
- **Apple Distribution credentials (manual)** — only нужно если switching к External Testing. Currently Automatic signing для Internal TestFlight.
- **Apple Developer Portal AASA deployment** — manual portal step blocking Tier 1 #4.

---

### 📊 Tier counts

| Tier | Items | Total effort estimate |
|---|---|---|
| 🚨 Tier 1 (External Rollout block) | 5 (1 ✓ closed 2026-05-18) | ~8-10h + AASA deploy |
| 🟠 Tier 2 (high-value correctness) | 5 | ~14-22h |
| 🟡 Tier 3 (v1.1+ architecture) | 6 | ~16-25h |
| 🟢 Tier 4 (cleanup) | 7 | ~12-17h |
| 🔵 Tier 5 (out of control) | 3 | external/manual |
| **Total** | **26 priority items** | **~50-74h** + external deps |

(Tier 4 covers «~21 Plan 06 carry-forward LOWs» как 1 item; actual count after Periphery scan может exceed 26.)

---

### Recommended ship order

```
🟢 Internal TestFlight ship (NOW — already unblocked by Plan 09)
   ↓
🚨 Tier 1: items #1, #2, #4, #5 (~8-10h + AASA deploy) — #3 ✓ closed 2026-05-18
   ↓
🟠 Tier 2: items #6, #7, #8 (top 3 — ~10-14h)
   ↓
🚨 External Rollout (App Store Connect submission)
   ↓
🟠 Tier 2: items #9, #10 (если remaining)
   ↓
🟡 Tier 3: items #11-#16 (v1.1+ refactor — ~16-25h)
   ↓
🟢 Tier 4: opportunistic cleanup
```
