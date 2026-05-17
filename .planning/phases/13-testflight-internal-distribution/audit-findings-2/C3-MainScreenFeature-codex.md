# C3' — MainScreenFeature Re-Audit (Codex 5.5)

**Scope:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/`
**Baseline:** `55523dd`

## Closure Verification

| ID | Fix | Verdict | Evidence |
|---|---|---:|---|
| A3-001 / C3-005 | VM `deinit` removes 3 observers | PASS | `MainScreenViewModel.swift:1125` removes `rulesUpdateObserver`, `killSwitchObserver`, `nevpnStatusObserver`. |
| A3-002 | `.connected` uses `min(connectedDate, state.connectionStart)` | PASS с caveat | `MainScreenViewModel.swift:533`; see `C3'-002`. |
| A3-004 | `killSwitchObserver queue:nil` | PASS | `MainScreenViewModel.swift:233`. |
| A3-005 | `ProvisionSerializer` actor wrap | **PARTIAL** | Wrapper exists at `ConfigImporter.swift:66` and call at `:501`, but actor reentrancy means не full async mutex. See `C3'-001`. |
| C3-001 | `handleForegroundReentry` calls VM `handleForeground()` | PASS | `MainScreenViewModel.swift:710` then `:720`. |
| C3-002 | `disconnect()` filters via `ManagerSelector` | PASS | `TunnelController.swift:484-486`. |
| C3-003 | TUIC reparse cases added | PASS | scalar path `ConfigImporter.swift:796`; explicit path `:928`; payload source `:1010`. |
| T-B6 | kill switch default `true` | PASS | Main package reads `?? true` at multiple sites; Settings side also default `true`. |

## New Findings

### [HIGH] C3'-001: `ProvisionSerializer.run` is actor-reentrant; не serializes full async provisioning operation
- **Location:** `ConfigImporter.swift:67`
- **Description:** Swift actors release isolation at `await`. `_provisionTunnelProfileInternal` awaits during auto-mode keychain TaskGroup AND at `tunnelProvisioner.provisionTunnelProfile(...)`. Another `provisionTunnelProfile(for:)` call can enter while первый suspended.
- **Why it matters:** Two callers can still overlap downstream provider config build/save/load — exact class of reconnect/failover provisioning race T-B5 был meant to eliminate.
- **Suggested fix:** Use real async mutex/task-chain inside `ProvisionSerializer`, OR explicitly narrow serializer к pre-await SwiftData section + document NE provisioning may overlap.

### [MEDIUM] C3'-002: `min(connectedDate, state.connectionStart)` may reuse stale previous-session date
- **Location:** `MainScreenViewModel.swift:533`
- **Description:** If app missed background `.disconnected` and later observes new `.connected`, fall back к existing `connectionStart` could be from earlier session.
- **Why it matters:** Timer can include downtime from previous session (Settings/VPN off/on while backgrounded, only final connected observed on foreground).
- **Suggested fix:** Only keep earlier date when plausibly same session; prefer `connectedDate` when newer than `connectionStart` by session-boundary threshold.

### [LOW] C3'-003: `handleForegroundReentry()` calls both `tunnel.handleForeground()` AND VM's
- **Location:** `MainScreenViewModel.swift:710`
- **Description:** Production OK today because `TunnelController.handleForeground()` explicit no-op at `TunnelController.swift:613`. Latent footgun if tunnel hook later regains real `loadAllFromPreferences()` behavior.
- **Suggested fix:** Keep `TunnelController.handleForeground()` permanently documented no-op, OR collapse foreground status resync into one owner.

## Regressions Checked

| Risk | Verdict |
|---|---|
| `nonisolated(unsafe)` observer tokens — Swift 6 violations | No concrete violation found. |
| `min(connectedDate, state.connectionStart)` stale-session | Confirmed edge issue: `C3'-002`. |
| `provisionSerializer.run { [self] }` retain cycle | No retain cycle (closure не stored). |
| `handleForegroundReentry` duplicate XPC trips | No duplicate in production today; latent only. |
| TUIC reparse trusts payload | `PoolBuilder.isValidPoolEntry` rejects empty TUIC uuid/password/sni и invalid `congestionControl`/`udpRelayMode` before JSON build. No blocker. |

## Verdict

**Not a clean TestFlight pass** до resolution или explicit acceptance C3'-001. Serializer fix exists, но docs overstate synchronization guarantee — actor reentrancy allows overlap after suspension points. Other findings medium/low edge cases.
