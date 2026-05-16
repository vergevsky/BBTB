# Phase 13 — TestFlight Internal Distribution (v0.13)

**Status:** ⚪ Planned
**Started:** 2026-05-16
**Scope:** Распространение BBTB через TestFlight Internal Testing (до 100 testers, friends-and-family beta).

## Решения (locked)

### D-01 — Internal Testing only для v1.0 launch

User decision 2026-05-16: «Мне достаточно Internal testers».

**Rationale:**
- Internal Testing skip'ает Beta App Review (External — 1-2 дня первый раз)
- Не нужен Privacy Policy URL (для External required)
- Не нужны full App Store metadata (description, screenshots в App Store sizes, categories)
- Faster path к live testing: Apple processing ~10-30 мин → tester install
- 100 testers достаточно для friends-and-family validation cycle

External Testing + public invite link → отложено на v1.1+ когда будет
реальный feedback от internal cycle.

### D-02 — SPKI subscription pinning deferred to v1.1+

Verified 2026-05-16 (commit `eb44740`): placeholder pins в `PinStore.swift`
это dead code в текущей production wiring. Subscription URL fetch использует
`DefaultSubscriptionURLFetcher` (URLSession.shared, standard HTTPS) by default.

**v1.0 security model:** TLS 1.2+ ATS + public CA validation + HTTPS-only.
Эквивалент банковским apps в App Store без custom pinning.

См. `BBTB/Packages/ConfigParser/Sources/ConfigParser/PinStore.swift` doc
comments + memory `project_phase13_subscription_pins_prerequisite.md`.

### D-03 — Apple Distribution credentials = Xcode automatic

Project уже настроен с `CODE_SIGN_STYLE = Automatic`. Xcode auto-manages
Distribution cert + provisioning profiles. Достаточно для Internal TestFlight.

**Project config (verified 2026-05-16):**
- Team ID: `UAN8W9Q82U`
- Bundle ID (app): `app.bbtb.client.ios`
- Bundle ID (extension): `app.bbtb.client.ios.tunnel`

## Open prerequisites

| # | Prereq | Status | Action |
|---|---|---|---|
| 1 | Apple Developer Program subscription active | ⚪ verify | Apple Portal → Membership tab |
| 2 | Network Extension capability на 2 App IDs (main + tunnel) | ⚪ verify/add | Apple Portal → Identifiers → Edit |
| 3 | App Store Connect record для `app.bbtb.client.ios` | ⚪ create | App Store Connect → ➕ New App |
| 4 | Export Compliance one-time answer (Standard cryptography exemption) | ⚪ pending | App Store Connect prompt on first build |
| 5 | ~~SPKI subscription pins replacement~~ | ✅ Deferred | v1.1+ (D-02) |
| 6 | ~~Privacy Policy URL~~ | ✅ N/A для Internal | v1.1+ когда External Testing |
| 7 | ~~DETECT-03 admin handoff (rules.json sign)~~ | ⚪ deferred | Not blocker для Internal testing |
| 8 | (Optional) Subscription quota fields в model | ⚪ deferred | Nice-to-have, не блокер |

## Walkthrough (см. `wiki/distribution-testflight.md` для full detail)

**Phase 13 plan tasks:**

1. **13-01 Apple Portal setup** (~30-60 мин interactive)
   - Verify Apple Developer Program active
   - Add Network Extension capability на 2 App IDs
   - (Auto) Distribution cert generation via Xcode

2. **13-02 App Store Connect record** (~15 мин)
   - Create app record (Platform iOS, Name BBTB, Bundle ID, SKU, Russian primary)
   - Skip Privacy Policy / App Description / Screenshots (не required для Internal)

3. **13-03 First Archive + Upload** (~30 мин + 30 мин processing)
   - Xcode → Product → Archive → Distribute App → App Store Connect → Upload
   - Auto-manage signing
   - Wait Apple processing

4. **13-04 Internal Testing rollout** (~5-15 мин)
   - App Store Connect → TestFlight → Internal Testing → Create Group → add testers
   - Testers получают email → install via TestFlight iOS app
   - Export Compliance answer (Standard cryptography exemption)

5. **13-05 Smoke test on tester device** (~30 мин)
   - Install built TestFlight app
   - Run through UAT items из `12-UAT.md` (network resilience N.1-N.6)
   - Verify Connecting/Connected/Error flows работают на production-signed build

## Success criteria

- App Store Connect record exists и build «Ready to Test»
- ≥1 internal tester installed via TestFlight и smoke-tested core flow (Empty → Import → Connect → Verify tunnel works via [whatismyipaddress.com](https://whatismyipaddress.com/))
- Export Compliance answered
- Tester feedback captured (если есть)

## Carry-forward (v1.1+ enhancements)

- External Testing (до 10,000 testers + Beta App Review + Privacy Policy URL)
- SPKI subscription pin replacement (D-02)
- DETECT-03 admin handoff (rules.json sign + MAX-domains)
- App Store submission (full App Store Review)
- Subscription quota fields + conditional progress bar (Figma 3064:1154)
- macOS pixel-perfect rebuild + macOS TestFlight track
- Full Light mode (designer должен дорисовать Light versions всех экранов)
