# Independent Audit Tooling — Setup & Activation

Status: configured 2026-05-17 в response to Plan 07 regression rate.

Plan 07 (autonomous fix-up) had **3 outright failures + 6 partial closures из 24 fixes**.
Root cause analysis: insufficient per-commit verification discipline. Independent
AI tooling + runtime sanitizers compensate без adding more human discipline burden.

---

## Tier 1 — Active now (configured, runs automatic)

### Dependabot (`.github/dependabot.yml`)

**Что делает:** automatic dependency update + CVE alerts. Weekly check для
SwiftPM packages, monthly для GitHub Actions.

**Когда сработает:** уведомит про новую CVE в swift-crypto / Yams / SnapshotTesting /
other SwiftPM deps как только опубликован.

**Action needed:** none — autopilot.

### GitHub CodeQL (`.github/workflows/codeql.yml`)

**Что делает:** semantic SAST. Строит call graph + dataflow для Swift codebase.
Detects:
- Injection paths (untrusted input → sensitive sink)
- Hardcoded secrets
- Crypto API misuse
- Path traversal patterns
- Many Swift security antipatterns

**Когда runs:** every push, every PR, weekly Monday 03:00 UTC scheduled.

**Стоимость:** **free для public repos**.

**Action needed:** push к GitHub repo. Results появятся в Security tab → Code scanning alerts.

### TSAN Tests (`.github/workflows/tsan-tests.yml`)

**Что делает:** runtime Thread Sanitizer + Undefined Behavior Sanitizer на
test suites для PacketTunnelKit / VPNCore / ConfigParser / RulesEngine.
**Catches concurrency races at test time.**

Конкретно поймал бы **Plan 08 cross-validated regressions:**
- CV-2-H2 NEVPN observer `nonisolated(unsafe)` race
- CV-2-H4 ExtensionPlatformInterface stateQueue gaps
- CV-2-H5 BaseSingBoxTunnel pi.reset() outside queue

**Когда runs:** PRs к main + nightly 04:00 UTC.

**Cost:** GitHub Actions macOS minutes (slow — TSAN 5-15× normal speed). Free
~2000 min/month для public repos.

**Action needed:** push к GitHub. Failed TSAN runs block PR merge.

---

## Tier 2 — Configured, needs activation

### CodeRabbit (`.coderabbit.yaml`)

**Что делает:** AI-powered PR review. Reads codebase context, suggests
inline fixes, generates sequence diagrams для complex flows. Config includes
path-specific instructions targeting our historical hot spots
(PacketTunnelKit lifecycle, MainScreenFeature reactive paths, ConfigParser
input boundary, RulesEngine trust chain).

**Это прямой ответ на discipline gap который убил Plan 07.** Every PR
gets independent second-opinion before merge.

**Activation:**
1. Login через GitHub в https://app.coderabbit.ai/
2. Install CodeRabbit GitHub App на repo
3. PRs автоматически review'ятся; config из `.coderabbit.yaml` picked up

**Cost:** **free для public OSS repos**. $12-15/user/mo для private.

### Periphery (`.periphery.yml`)

**Что делает:** Swift-specific dead code detection.

**Initial scan results (baseline saved к `.planning/phases/13-testflight-internal-distribution/periphery-baseline.txt`):**
- 489 findings categorized:
  - 118 unused properties
  - 108 redundant public ACL (could be internal/private)
  - 70 unused functions
  - 32 redundant public enums
  - 30 redundant public initializers
  - 22 redundant public functions
  - 16 unused enums
  - 15 assign-only properties
  - 12 unused initializers
  - 11 unused structs
  - 6 unused imports
  - + tail

Большая часть — это `VPNProtocolHandler` protocol с unused conformance в каждом из 6 protocol packages (legacy Wave 0 contract что never got wired). Cleanup pass would close 40-60 LOW findings catalogued в audits.

**Run:** `periphery scan` (from project root).
**CI integration:** add к pre-commit hook OR PR check workflow.

### SwiftLint (`.swiftlint.yml`)

**Что делает:** style + correctness + custom rules. Configured с три custom security-focused rules:
1. `no_print_in_packages` — enforces CLAUDE.md rule «no print()» (caught A1'-3-010)
2. `prefer_app_group_suite` — flags `UserDefaults.standard` в tunnel paths (memory: extension can't access .standard)
3. `no_unchecked_sendable_without_justification` — flags `@unchecked Sendable` (Plan 06/08 found multiple races behind this)

**Install:** `brew install swiftlint`. Run: `swiftlint` from project root.
**CI:** integrate as build phase script (Xcode) или GitHub Action.

---

## Tier 3 — Pre-TestFlight upload (manual)

### MobSF (Mobile Security Framework)

**Что делает:** scans final `.ipa` для:
- ATS exemptions (Apple Transport Security)
- Hardcoded secrets / API keys
- Insecure entitlements
- Cert pinning misconfig
- Jailbreak detection robustness
- Insecure data storage

**Setup:** Docker `docker pull opensecurity/mobile-security-framework-mobsf`
**Run:** upload built `.ipa` к localhost:8000 web UI.
**Time:** ~30 min setup + 5 min scan.

**Когда:** перед каждым TestFlight upload.

---

## Tier 4 — Pre-v1.0 production (paid security audit)

### Trail of Bits

- Audited Signal, Zoom, Pico crypto libraries
- Focused VPN audit estimate: $25k-100k

### Cure53

- Berlin-based; audited ProtonVPN, Mullvad VPN, ProtonMail
- Focused audit estimate: $20k-50k

### Radically Open Security

- Dutch; ethical hacking focus; works с pen-test budget projects
- Estimate: $15k-40k

**Когда:** перед public production launch (post-TestFlight External).

---

## CI Activation Checklist

Когда push к GitHub:

- [ ] Verify `.github/dependabot.yml` recognized — GitHub UI shows Dependabot alerts tab populated
- [ ] CodeQL workflow runs after first push к main — check Actions tab
- [ ] TSAN workflow runs on first PR к main — check Actions tab
- [ ] (Optional) Install CodeRabbit GitHub App
- [ ] (Optional) Enable GitHub Security Advisories (Settings → Security)

## Local activation (immediate)

```bash
# Install missing tools
brew install swiftlint periphery

# Run linter
swiftlint

# Run dead code scan
periphery scan

# Run tests with TSAN (manual)
cd BBTB
xcodebuild test -scheme PacketTunnelKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -enableThreadSanitizer YES
```

## Cost summary

| Tool | Tier | Cost |
|---|---|---|
| Dependabot | 1 | $0 |
| CodeQL | 1 | $0 (public repo) |
| TSAN GitHub Actions | 1 | $0 first 2000 min/mo |
| CodeRabbit | 2 | $0 (public) или $12/mo (private) |
| Periphery | 2 | $0 |
| SwiftLint | 2 | $0 |
| MobSF | 3 | $0 (self-hosted) |
| Trail of Bits / Cure53 | 4 | $20k-100k (когда public production) |

**Tier 1+2 total: $0 (для public repo).** Этот tooling stack должен был быть с самого начала. Plan 07 regression rate показывает что мы платили эту цену вручную через autonomous human discipline — и проиграли.
