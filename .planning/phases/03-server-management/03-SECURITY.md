---
phase: 03-server-management
audit_date: 2026-05-12
auditor: gsd-security-auditor (Opus 4.7) + manual review
asvs_level: 1
register_source: 03-01-PLAN.md..03-05-PLAN.md + 03-G1-PLAN.md STRIDE registers
phase1_carry_forward: 01-SECURITY.md — 37 closed threats
phase2_carry_forward: 02-SECURITY.md — 13 closed threats, 2 open carry-forward (W-02-09, W-02-10)
status: verified
threats_total: 14
threats_covered: 11
threats_accepted: 3
threats_blocker: 0
phase_invariants_regressions: 0
new_findings: 11
code_review_warnings: 11
remediation_commits:
  - 84192a1  # SwiftData UUID? predicate + identity dedup
  - 2077fa7  # SNI rotation fix
  - b5d3120  # TunnelController disconnect race
---

# Phase 3 — Security Audit Report

## Executive Summary

- **Phase 3 threat register (14 threats across 5 plans + G1):** 11 COVERED, 3 ACCEPT. 0 BLOCKER.
- **Phase 1/2 carry-forward invariants (R1, R6, R10/R11, KILL-01/02, SEC-03/05):** 0 regressions.
- **Code review (gsd-code-reviewer):** 11 warnings (WR-01..WR-11). Non-blocking. Deferred to Phases 4/7/11.
- **UAT:** T1-T8 PASS 2026-05-12.

**Phase 3 ships.** No BLOCKER findings.

---

## Threat Register

| ID | STRIDE | Description | Status | Evidence |
|----|--------|-------------|--------|----------|
| T-03-01 | T | Subscription name injection (control chars / oversized) | COVERED | `ConfigImporter.sanitizeSubscriptionName()` — strip `\n\r\t`, clamp 100 chars |
| T-03-02 | — | (not declared in register) | N/A | — |
| T-03-03 | — | (not declared in register) | N/A | — |
| T-03-04 | — | (not declared in register) | N/A | — |
| T-03-05 | — | (not declared in register) | N/A | — |
| T-03-06 | E | Subscription URL SSRF (loopback, RFC-1918, link-local) | COVERED | `SubscriptionURLFetcher.isBlockedHost()` — blocklist loopback, link-local, RFC-1918, multicast, ULA; HTTPS-only enforced |
| T-03-07 | I | TCP SYN probes ТСПУ-risk (pre-connect probe leaks IP to all servers) | ACCEPT | TCP SYN к 443 неотличим от HTTPS; user IP раскрывается subscription servers — accepted, out of scope for MVP |
| T-03-08 | T | Cascade delete data loss | COVERED | `@Relationship(deleteRule: .cascade)` — корректно; только ServerConfig данной подписки |
| T-03-09 | T | SwiftData migration idempotency | COVERED | `migratePhase2ToPhase3()` guarded via `UserDefaults app.bbtb.phase3.migrationDone` |
| T-03-23 | T | Stale `selectedServerID` UserDefaults при удалении сервера | COVERED | `MainScreenViewModel.reconcileSelectionWithStore()` в refresh()/onAppear; graceful fallback на full pool |
| T-03-24 | I | Pre-connect probe IP leak (все серверы видят client IP) | ACCEPT | Документировано как known limitation; proxy-pre-tunnel out of scope |
| T-03-25 | D | Reconnect race (быстрые тапы по разным серверам) | COVERED | `if case .connecting = state { return }` в reconnect Task; UAT T6 PASS |
| T-03-26 | T | `.connecting` stuck при throw mid-flow | COVERED | `catch` в `performToggleImpl` и reconnect Task устанавливает `state = .error(message:)` |
| T-03-27 | E | JSON injection через `NETunnelProviderManager.providerConfiguration` | COVERED | Phase 1 SEC-06 carry-forward — ConfigImporter validates schema before persist; PoolBuilder produces verified JSON structure |

---

## Phase 1/2 Carry-forward Invariants

| Control | Evidence | Status |
|---------|----------|--------|
| R1 — no listen-on-localhost | `SingBoxConfigLoader.allowedInboundTypes = {tun, direct}` — unchanged | NO REGRESSION |
| R6 — no IFF_POINTOPOINT | `TunnelSettings.swift` — `destinationAddresses` never assigned | NO REGRESSION |
| KILL-01/02 | `KillSwitch.swift` single mutator — unchanged | NO REGRESSION |
| SEC-05 Keychain | `KeychainStore.kSecAttrAccessibleWhenUnlocked` — unchanged | NO REGRESSION |
| W-02-09 | Subscription fetcher body-size/redirect cap — still open → Phase 7 | CARRY-FORWARD |
| W-02-10 | macOS `network.server` entitlement — still open → Phase 10 | CARRY-FORWARD |

---

## Code Review Warnings (WR-01..WR-11)

All non-blocking. Deferred as follows:

| ID | Issue | Target phase |
|----|-------|-------------|
| WR-01 | `pingAllServers` mutates fetched `@Model` rows without re-fetching in same context | Phase 4 |
| WR-02 | NotificationCenter observer never removed → potential leak + stale callback | Phase 7 |
| WR-03 | `SubscriptionURLFetcher.decodeBase64` returns `Data` for empty padded input | Phase 11 |
| WR-04 | `selectedServerID` UserDefaults restore in `init` triggers immediate writeback | Phase 11 |
| WR-05 | `MainScreenViewModel.init` spawns unstructured `Task { await refresh() }` race | Phase 4 |
| WR-06 | `subscriptionFetchErrors.count == subscriptions.count` edge-case incorrect | Phase 11 |
| WR-07 | `applySelection(nil)` during cascade delete of selected server triggers reconnect-to-deleted | Phase 4 |
| WR-08 | `silentForegroundRefresh` ignores cancellation when committing `context.save` | Phase 11 |
| WR-09 | `provisionTunnelProfile(for:)` uses `parsedList[0]` host even in full-pool fallback | Phase 11 |
| WR-10 | `getOrCreateSubscription` allows duplicate URL when normalization differs | Phase 11 |
| WR-11 | `decodeMaybeBase64` does not handle URL-safe base64 in Profile-Title header | Phase 7 |

---

## Accepted Risks

- **T-G1-05: DNS-rebinding** — `isBlockedHost()` works on hostname string, не резолвит DNS. Атакующий с контролем DNS может обойти. Mitigated in Phase 7 (DPI-08 cert pinning + safe DNS resolver callback).
- **T-03-07 / T-03-24** — probe IP leak и TCP SYN exposure. Документировано как known limitation.

---

## UAT Security Evidence

- T1-T8 PASS 2026-05-12. Все security controls протестированы через E2E.
- SNI rotation fix (commit `2077fa7`) — устранил дублирование серверов из-за Reality anti-fingerprint.
- SwiftData UUID? fix (commit `84192a1`) — предотвращает silent data loss в merge queries.
- TunnelController race fix (commit `b5d3120`) — T6 PASS (reconnect при смене сервера).

---

*See also: `wiki/security-gaps.md` R15 (T-03-01..T-03-09) and R16 (T-03-23..T-03-27) for long-term decision log.*
