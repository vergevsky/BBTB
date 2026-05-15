---
phase: 11
slug: onboarding-ux-polish
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-15
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (XCTestCase) |
| **Config file** | `BBTB/Packages/AppFeatures/Package.swift` (testTarget) |
| **Quick run command** | `cd BBTB/Packages/AppFeatures && swift test --filter MainScreenFeatureTests` |
| **Full suite command** | `cd BBTB/Packages/AppFeatures && swift test` |
| **Estimated runtime** | ~30s quick / ~2-3 min full |

---

## Sampling Rate

- **After every task commit:** Run `cd BBTB/Packages/AppFeatures && swift test --filter MainScreenFeatureTests`
- **After every plan wave:** Run `cd BBTB/Packages/AppFeatures && swift test`
- **Before `/gsd-verify-work`:** Full suite must be green + `swift build` + `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB iOS Simulator` + `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB-macOS`
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 11-UX01-01 | 01 | 1 | UX-01 | — | hasShownOnboarding flag set irrevocably | unit | `swift test --filter OnboardingViewModelTests/test_isPresented_whenFlagFalse` | ❌ W0 | ⬜ pending |
| 11-UX01-02 | 01 | 1 | UX-01 | — | Dismiss after import | unit | `swift test --filter OnboardingViewModelTests/test_dismiss_afterImport` | ❌ W0 | ⬜ pending |
| 11-UX01-03 | 01 | 1 | UX-01 | — | Flag persists | unit | `swift test --filter OnboardingViewModelTests/test_flagPersists` | ❌ W0 | ⬜ pending |
| 11-UX08-01 | 02 | 2 | UX-08 | — | Spinner only at connecting | unit | `swift test --filter ConnectionButtonTests/test_spinnerVisibleOnlyWhenConnecting` | ❌ W0 | ⬜ pending |
| 11-UX08-02 | 02 | 2 | UX-08 | — | symbolEffect preserved for non-connecting | manual | UAT — visual inspection on device | — | ⬜ pending |
| 11-UX09-01 | 02 | 2 | UX-09 | — | Pixel-perfect Figma compliance | manual | UAT side-by-side Figma + device | — | ⬜ pending |
| 11-DET01-01 | 03 | 1 | DETECT-01 | — | Silent detection — no UI | unit | `swift test --filter MAXDetectorTests/test_noUIEffect` | ❌ W0 | ⬜ pending |
| 11-DET01-02 | 03 | 1 | DETECT-01 | — | iOS logs not-detected for unknown scheme | unit | `swift test --filter MAXDetectorTests/test_iOS_logsNotDetected` | ❌ W0 | ⬜ pending |
| 11-DET02-01 | 03 | 1 | DETECT-02 | — | macOS iterates candidate bundles | unit | `swift test --filter MAXDetectorTests/test_macOS_iteratesCandidates` | ❌ W0 | ⬜ pending |
| 11-DET03-01 | 03 | 1 | DETECT-03 | — | Admin handoff doc created | manual | Check `wiki/max-domains-blocklist.md` exists | — | ⬜ pending |
| 11-TEL02-01 | 04 | 1 | TELEM-02 | InfoDisc | IP last octet masked | unit | `swift test --filter DiagnosticsExporterTests/test_maskIPv4_replacesLastOctet` | ❌ W0 | ⬜ pending |
| 11-TEL02-02 | 04 | 1 | TELEM-02 | InfoDisc | Non-IP preserved | unit | `swift test --filter DiagnosticsExporterTests/test_maskIPv4_preservesNonIP` | ❌ W0 | ⬜ pending |
| 11-TEL02-03 | 04 | 1 | TELEM-02 | Privacy | Anonymous device-id stable | unit | `swift test --filter DiagnosticsExporterTests/test_anonymousID_stable` | ❌ W0 | ⬜ pending |
| 11-TEL02-04 | 04 | 1 | TELEM-02 | — | prepareLog nil when no file | unit | `swift test --filter DiagnosticsExporterTests/test_prepareLog_returnsNilNoFile` | ❌ W0 | ⬜ pending |
| 11-TEL02-05 | 04 | 1 | TELEM-02 | — | prepareLog includes metadata | unit | `swift test --filter DiagnosticsExporterTests/test_prepareLog_includesHeader` | ❌ W0 | ⬜ pending |
| 11-TEL02-06 | 04 | 1 | TELEM-02 | — | Share Sheet presents (manual) | manual | UAT — tap button, see Share Sheet | — | ⬜ pending |
| 11-LOC02-01 | 05 | 1 | LOC-02 | — | No hardcoded Russian strings | lint | `! grep -rn '"[А-Яа-яЁё]' BBTB/Packages/AppFeatures/Sources --include="*.swift" \| grep -vE '(//|\*)' \| grep -v test` | ✅ ad-hoc | ⬜ pending |
| 11-LOC02-02 | 05 | 1 | LOC-02 | — | TransportPicker labels via L10n | unit | `swift test --filter TransportPickerLabelsTests/test_labels_useL10n` | ❌ W0 | ⬜ pending |
| 11-LOC03-01 | 06 | 2 | LOC-03 | — | HelpView renders 5 FAQ sections | unit | `swift test --filter HelpViewTests/test_renders5FAQItems` | ❌ W0 | ⬜ pending |
| 11-LOC04-01 | 06 | 2 | LOC-04 | — | FAQ contains 22 apps topic | unit | `swift test --filter HelpViewTests/test_faq_includesDetectionLimits` | ❌ W0 | ⬜ pending |
| 11-IMP03-01 | 07 | 1 | IMP-03 | AccessCtrl | fileImporter accepts .json | unit | `swift test --filter FileImporterTests/test_acceptsJSON` | ❌ W0 | ⬜ pending |
| 11-IMP03-02 | 07 | 1 | IMP-03 | AccessCtrl | fileImporter accepts .yaml | unit | `swift test --filter FileImporterTests/test_acceptsYAML` | ❌ W0 | ⬜ pending |
| 11-IMP03-03 | 07 | 1 | IMP-03 | AccessCtrl | Security-scoped resource handled | unit | `swift test --filter FileImporterTests/test_startStopSecurityScope` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/OnboardingViewModelTests.swift` — stubs for UX-01
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConnectionButtonTests.swift` — stubs for UX-08
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/MAXDetectorTests.swift` — stubs for DETECT-01/02 (requires `UIApplicationQueryable` + `NSWorkspaceQueryable` protocol abstractions)
- [ ] `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/FileImporterTests.swift` — stubs for IMP-03
- [ ] `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/DiagnosticsExporterTests.swift` — stubs for TELEM-02
- [ ] `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/HelpViewTests.swift` — stubs for LOC-03/04
- [ ] `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/TransportPickerLabelsTests.swift` — stubs for LOC-02

*Wave 0 requires no new SPM packages — all tests in AppFeatures testTarget.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Connection button states visual correctness | UX-08 | Requires visual device inspection vs Figma | Run app on iPhone, cycle through idle/connecting/connected/error states, compare with Figma mockup |
| Pixel-perfect Figma compliance | UX-09 | Requires side-by-side comparison | Open app on device, compare each screen with Figma in inspect mode |
| Share Sheet appears correctly on iOS + macOS | TELEM-02 | Platform UI — cannot automate | Tap "Отправить лог разработчику" on both platforms, verify Share Sheet appears with log file |
| MAX app detection on real device | DETECT-01/02 | Requires specific app installed | Install MAX app, run detection, verify log entry; uninstall, verify "not detected" log |
| FAQ content review | LOC-03/04 | Content quality judgment | Navigate Help, read each section, verify accuracy and completeness |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
