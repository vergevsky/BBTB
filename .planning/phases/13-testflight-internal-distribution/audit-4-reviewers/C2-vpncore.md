# C2 — VPNCore (Codex 5.5)
**Baseline:** ccbce8a
**Total findings:** 1 (0/1/0/0)

## Plan 07 closure verification
- T-C-A2H1' LockedBool typed lock: PASS
- T-C-A2H2' probe cancellation aggregate: PARTIAL

## Critical
No critical findings in this VPNCore pass.

## High

### C2-4-001: Cancellation during the final probe attempt can still return a selectable partial aggregate
- **Location:** `BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift:201`
- **Dimension:** Logic / cancellation semantics
- **Description:** The Plan 07 fix only marks a probe round conservative when cancellation is observed at the top of a later loop iteration (`ServerProbeService.swift:197-199`) and `iterationsCompleted < 3` (`ServerProbeService.swift:211`). If the task is cancelled while the third `probeOnce` is suspended, `probeOnce` maps the cancellation callback to `.timeout` (`ServerProbeService.swift:50-84`), the caller increments `iterationsCompleted` to 3 (`ServerProbeService.swift:201-202`), records one failure (`ServerProbeService.swift:203-206`), and exits the loop without ever setting `cancelledMidRound`. With two earlier `.ok` samples, the returned aggregate has non-nil `avgLatencyMs`, `failures: 1`, and `lossRate: 1/3` (`ServerProbeService.swift:219-227`).
- **Why HIGH:** This is the same persistence/selection class T-C-A2H2' was meant to close, just in a narrower timing window. `ProbeAggregate.score` is non-nil whenever `avgLatencyMs` is non-nil (`ProbeResult.swift:45-47`), and `ServerScore.autoSelect` filters only nil scores before choosing the minimum (`ServerScore.swift:17-20`). A cancelled final attempt after two fast successes can therefore still beat a clean 3/3 slower server, and refresh paths can persist `lastLatencyMs` plus `failedProbeCount = 1` (`MainScreenViewModel.swift:1063-1069`, `ServerListViewModel.swift:455-460`).
- **Fix:** Preserve explicit cancellation identity across `probeOnce` instead of collapsing it into `.timeout`, or re-check `Task.isCancelled` immediately after each `await probeOnce(...)` and before returning the aggregate. If cancellation is observed at any point before a fully completed 3-attempt round is trusted, return `ProbeAggregate(avgLatencyMs: nil, failures: 3, lossRate: 1.0, ...)`.

## Medium
No medium findings in this VPNCore pass.

## Low
No low findings in this VPNCore pass.

## Notes
- T-C-A2H1' is structurally closed: `LockedBool` has no unprotected mutable stored state, uses `OSAllocatedUnfairLock<Bool>(initialState: false)` (`ServerProbeService.swift:244-245`), mutates state only inside `withLock` (`ServerProbeService.swift:247-252`), and no longer uses `@unchecked Sendable`.
- The conservative aggregate values introduced by T-C-A2H2' are safe when that branch is reached: `avgLatencyMs: nil`, `failures: 3`, and `lossRate: 1.0` (`ServerProbeService.swift:211-217`) produce `score == nil` (`ProbeResult.swift:45-47`), so `autoSelect` excludes the server rather than making it "always picked" (`ServerScore.swift:17-20`).
- Existing VPNCore tests cover basic stream cancellation duration only (`ServerProbeServiceTests.swift:127-150`); they do not assert that cancelled partial probe rounds produce the conservative aggregate.
