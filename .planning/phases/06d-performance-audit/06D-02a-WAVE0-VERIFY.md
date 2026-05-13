# Wave 06D-02a — Wave 0 gaps atomic commit verification

**Date:** 2026-05-14
**Base SHA (pre-wave):** `e2c9ac6`
**Phase:** 06d-performance-audit
**Wave:** 02a (Wave 0 gaps decomposed into 3 atomic commits per checker WARNING fix)

---

## 1. Atomic commit cadence

| # | SHA | Commit message prefix | Files changed | Regression gate result | Status |
|---|---|---|---|---|---|
| 1 | `7ffb398` | `chore(06d-02a): install Periphery 3.7.4 + jq + ripgrep verification` | 1 file (`06D-02a-PREFLIGHT.md`) | AppFeatures 133/133 + iOS BUILD SUCCEEDED + macOS BUILD SUCCEEDED | PASS |
| 2 | `64368c6` | `feat(06d-02a): add PerfSignposter + inject ColdLaunch/ConnectTap/PreConnectProbe/ProvisionProfile/LibboxStart spans` | 7 files (PerfSignposter + 2 App + TunnelController + 2 PacketTunnelProvider shells + BaseSingBoxTunnel) | AppFeatures 133/133 + iOS BUILD SUCCEEDED + macOS BUILD SUCCEEDED | PASS |
| 3 | _(this commit)_ | `docs(06d-02a): scaffold Instruments baseline templates + .gitignore *.trace + ASSUMED-claim verification log` | 6 baseline templates + `.gitkeep` + `.gitignore` + extended PREFLIGHT + WAVE0-VERIFY + SUMMARY | AppFeatures 133/133 + iOS BUILD SUCCEEDED + macOS BUILD SUCCEEDED (run before commit; see SUMMARY) | PASS |

**Cadence invariant:** между каждым из 3 commits регрессионный gate D-08 (`swift test --package-path BBTB/Packages/AppFeatures` + `xcodebuild iOS Simulator` + `xcodebuild macOS`) был зелёным. Никакие из этих 3 commits **не бандлят** друг с другом — каждый можно revert'ить independently без потери других.

---

## 2. D-09 invariant grep audit (after Commit 2)

| Check | Required | Actual | Status | Notes |
|---|---|---|---|---|
| Forbidden symbols `ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay` в **production code** (non-comment lines) | ≤ 7 carve-out | **0** | PASS | 13 occurrences total, все в `///` doc-comments или `//` inline комментариях — historical context для будущих разработчиков. См. `git grep -n -E "ReconnectStateMachine|NetworkReachability|ReconnectStateObserverRelay" BBTB/Packages/AppFeatures/Sources` для list. |
| `NEVPNStatusDidChange` observer `queue: .main` / `queue: OperationQueue.main` | 0 | **0** | PASS | Phase 6c invariant — observer queue остаётся `nil`. TunnelController.swift строка 223 — `queue: nil`. |
| `#Predicate` с `UUID?` parameter в production code | 0 | **1** | KNOWN-PREEXISTING | `ConfigImporter.swift:179` — `subOptID: UUID?` затем `#Predicate { $0.subscriptionID == subOptID ... }`. **Не введено в Commit 2** (instrumentation-only). Carry-over из Phase 3+. Логировано в Wave 02b backlog (synthesis). |
| `OSSignposter` declarations + intervals (post-injection) | ≥ 3 | **11 declarations + 16+ interval calls** | PASS | См. PREFLIGHT.md §4 A7 для полного breakdown. |

**Verdict:** D-09 invariants preserved. Pre-existing `#Predicate UUID?` finding deferred to Wave 02b synthesis — это **не regression** от текущей волны.

---

## 3. Build commands actually used (canonical for Phase 6d)

Эти команды зафиксированы в PREFLIGHT.md §3 и должны использоваться всеми последующими волнами:

```bash
swift test --package-path BBTB/Packages/AppFeatures
xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB \
    -destination 'generic/platform=iOS Simulator' build
xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB-macOS \
    -destination 'platform=macOS' build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

**Delta vs план (фиксируется здесь для непрерывности):**

- План указывал `-project BBTB/BBTB.xcodeproj` — iOS scheme требует workspace для SPM resolution.
- План требовал Periphery scheme через `--workspace` + `--targets` — Periphery 3.x использует `--project` + `--schemes` (без `--targets` для scheme-driven indexing).
- macOS build падает на code-signing без активного Developer ID cert → `CODE_SIGNING_ALLOWED=NO` для CI / dev окружения.

---

## 4. Scaffolding deliverables (Commit 3)

Все артефакты Wave 0 gaps созданы:

- `.gitignore` — добавлены `*.trace` + `.planning/phases/06d-performance-audit/traces-local/`. Бинарные Instruments-traces не попадают в VCS.
- `baselines/cold-launch-iphone-pre-fix.md` — пустой skeleton (Role K shape).
- `baselines/cold-launch-macbook-pre-fix.md` — пустой skeleton.
- `baselines/connect-tap-iphone-pre-fix.md` — пустой skeleton с per-span таблицей (ConnectTap / PreConnectProbe / ProvisionProfile / LibboxStart).
- `baselines/energy-iphone-pre-fix.md` — пустой skeleton с Wakeups breakdown.
- `baselines/allocations-iphone-host-pre-fix.md` — пустой skeleton.
- `baselines/allocations-iphone-extension-pre-fix.md` — пустой skeleton с 50 MB iOS extension hard-limit reference.
- `baselines/screenshots/.gitkeep` — пустой sentinel для git directory tracking.
- `06D-02a-PREFLIGHT.md` — extended с полной ASSUMED-claim verification (A1 / A2 / A6 / A7 / A8 + Open Q #3 + sing-box template count).
- `06D-02a-WAVE0-VERIFY.md` — этот документ.
- `06D-02a-SUMMARY.md` — closure record (Role M shape).

Wave 06D-02c будет заполнять baseline шаблоны реальными числами.
