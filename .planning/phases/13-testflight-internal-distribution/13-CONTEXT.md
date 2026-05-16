# Phase 13: TestFlight Internal Distribution — Context

**Gathered:** 2026-05-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 13 готовит iOS app к first TestFlight Internal distribution + любые правки которые user хочет до первого build. Включает:

1. **One new app feature:** «Правила маршрутизации» toggle в AdvancedSettings (default ON, off = full tunnel mode).
2. **Distribution setup:** Apple Portal NE capability verify, App Store Connect record creation, Xcode Archive→Upload, Internal testers invite, Export Compliance one-time answer.
3. **App metadata:** Version `0.1.0`, Build `1` (manual bump), localized display name EN/RU (already done in commit `30f7a89`).
4. **TestFlight rollout:** Internal Testing group с 5-20 friends-and-family testers (invited через App Store Connect → Users and Access; **Individual Apple Developer account работает**).

**Out of scope (deferred to v1.1+):** External Testing + public invite link + Privacy Policy URL + Beta App Review, SPKI subscription pin replacement, DETECT-03 admin handoff, App Store submission, Subscription quota fields + conditional progress bar, macOS pixel-perfect rebuild + macOS TestFlight track, Full Light mode.

</domain>

<decisions>
## Implementation Decisions

### Distribution strategy (carried forward from earlier session)
- **D-01:** Internal Testing only для v1.0. Skip Beta App Review, Privacy Policy URL, full App Store metadata. До 100 testers; processing ~10-30 мин после upload; faster path к live testing.
- **D-02:** SPKI subscription pinning deferred to v1.1+. Audit (commit `eb44740`) подтвердил placeholder pins это dead code — `SubscriptionPinManager.performBackgroundRefresh` не вызывается из production. v1.0 использует `DefaultSubscriptionURLFetcher` (standard HTTPS + ATS + public CA validation).
- **D-03:** Apple Distribution credentials = Xcode automatic signing. Project config: Team ID `UAN8W9Q82U`, Bundle IDs `app.bbtb.client.ios` + `.tunnel`, `CODE_SIGN_STYLE = Automatic`. Distribution cert + App Store provisioning profiles auto-generated при Archive→Upload.

### App fix in v1.0 build
- **D-04:** Add **Routing rules toggle** в AdvancedSettingsView (`@AppStorage("app.bbtb.routingRulesEnabled") Bool = true`). Default ON (routing rules применяются — split tunnel mode); off → bypass routing rules → full tunnel (all traffic via tunnel). Placement: рядом с `RulesViewerSection` (already в AdvancedSettings). Label: EN «Routing rules» / RU «Правила маршрутизации». Affects sing-box config generation в `ConfigImporter.provisionTunnelProfile` (when toggle off → skip RulesEngine rules; build full-tunnel sing-box config). Other backlog (Subscription quota / macOS rebuild / DETECT-03) — deferred to v1.1+.

### Version & Build numbering
- **D-05:** First TestFlight upload — `CFBundleShortVersionString = "0.1.0"` (beta-style semantic versioning communicates «early access»), `CFBundleVersion = "1"`. Subsequent builds — manual bump build number в Xcode перед каждым Archive (1 → 2 → 3 → ...). Public App Store launch — bump к 1.0.0.

### Internal testers list (Individual Apple Developer account)
- **D-06:** Internal Testing group = owner + **5-20 friends-and-family**. Invite через **App Store Connect → Users and Access** (top nav) → ➕ Add Users → Apple ID email + role «Developer» или «App Manager». Invited Apple ID's НЕ нуждаются в своём paid Apple Developer Program — они получают доступ к твоей team бесплатно. После accept → добавляются в TestFlight Internal Testing group в App Store Connect.

### TestFlight build description + feedback
- **D-07:** «What to Test» в TestFlight build — **brief generic invite** (1-3 строки): «BBTB — VPN для обхода ТСПУ. Попробуйте импорт конфига + подключение. Сообщите о багах через TestFlight feedback button.». Feedback channel — **TestFlight built-in** («Send Beta Feedback» в TestFlight iOS app → Apple email + App Store Connect inbox).

### Claude's Discretion
- Implementation детали `RulesEngine` integration с toggle (где hook'ить bypass): planner/researcher решит при review code в Phase 13-01 PLAN.
- Точный текст «What to Test» в TestFlight — refine before Archive based on feedback.
- App Store Connect record fields beyond required minimum (Bundle ID + Name + SKU + Primary Language) — planner может suggest defaults.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 13 source-of-truth (current phase)
- `.planning/phases/13-testflight-internal-distribution/13-CONTEXT.md` — this file
- `.planning/phases/13-testflight-internal-distribution/13-DISCUSSION-LOG.md` — discussion audit trail

### Project planning
- `.planning/PROJECT.md` — core value, target users (Russian-speaking, обход ТСПУ)
- `.planning/REQUIREMENTS.md` — full requirements list
- `.planning/ROADMAP.md` — phase boundaries (Phase 13 = «TestFlight & Distribution» renamed 2026-05-16)
- `.planning/STATE.md` — current milestone v0.13

### Phase 12 closure (immediately prior)
- `.planning/phases/12-swift-pixel-perfect-rebuild-from-figma-v0-12-design/12-UAT.md` — UAT signoff APPROVED on real device
- `wiki/swift-pixel-perfect-rebuild-2026.md` — Phase 12 closure summary (UI fix-loop + hardening)
- `wiki/log.md` — chronological commit list

### Distribution / TestFlight
- `wiki/distribution-testflight.md` — Internal-only walkthrough (Apple Portal NE capability → App Store Connect record → Archive→Upload → Internal testers invite → Export Compliance). Project config: Team ID `UAN8W9Q82U`, Bundle IDs `app.bbtb.client.ios` + `.tunnel`, Automatic signing.
- Memory `project_phase13_testflight_internal_path.md` — same walkthrough в persistent storage
- Memory `project_phase13_subscription_pins_prerequisite.md` — SPKI pinning downgrade rationale (audit findings, dead code analysis)

### Code references for D-04 (routing rules toggle)
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift` — host view для placement
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/RulesViewerSection.swift` — neighboring section (toggle placed рядом)
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` — add `routingRulesEnabled: Bool` @AppStorage
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — `provisionTunnelProfile` где hook для bypass routing rules при toggle off
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/` — RulesEngine module (определяет split tunnel rules)
- `BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings` — добавить `settings.advanced.routingRulesToggle.label` + `settings.advanced.routingRulesToggle.footer`

### Code references for distribution
- `BBTB/Project.swift` — Tuist config (bundle IDs, deployment targets, signing)
- `BBTB/App/iOSApp/Info.plist` — CFBundleShortVersionString + CFBundleVersion (bumped via D-05)
- `BBTB/App/iOSApp/BBTB-iOS.entitlements` — entitlements list (NE + App Groups + Keychain Sharing)
- `BBTB/App/iOSApp/en.lproj/InfoPlist.strings` + `ru.lproj/InfoPlist.strings` — localized display name (BBTB / Верни жука)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`SettingsViewModel.killSwitchEnabled`** (AppStorage Bool) — pattern для D-04 toggle: same `@AppStorage("app.bbtb.routingRulesEnabled") public var routingRulesEnabled: Bool = true` + Toggle binding в AdvancedSettingsView.
- **`AutoReconnectToggleSection.swift`** (existing toggle component) — реусаемый pattern для compact toggle UI с footer text.
- **BBTBTopBar** (DesignSystem) — уже migrated на все sub-screens.
- **`Project.swift`** Tuist config — automatic signing уже настроен; signing identity prompts появятся при Archive.
- **xcstrings + L10n codegen** — pattern для добавления 2 новых ключей (`settings.advanced.routing_rules_label` + `_footer`) + accessor в L10n.swift.

### Established Patterns
- **AppStorage bool toggles** — все Settings toggles используют `@AppStorage("app.bbtb.<feature>Enabled")`. Pattern: `@AppStorage` в `SettingsViewModel.swift`, `Toggle($isOn:)` binding в section view, `.onChange` hook для live-apply if needed.
- **RulesEngine pattern** — RulesEngineCoordinator управляет split tunnel rules; ConfigImporter.provisionTunnelProfile builds sing-box config с rules. D-04 hook: при `routingRulesEnabled == false` → skip RulesEngine rules (или передать empty rules) → ConfigImporter builds full-tunnel config.
- **Localized strings** — все user-facing texts через `L10n.xxx` (codegen из xcstrings). D-04 нужны 2 ключа.

### Integration Points
- **`SettingsViewModel`** ⇄ **`ConfigImporter`** — `routingRulesEnabled` читается ConfigImporter'ом при provisionTunnelProfile. Pattern: ViewModel exposes `@Published` или `@AppStorage`, ConfigImporter reads через `UserDefaults.standard.bool(forKey: "app.bbtb.routingRulesEnabled")` (decoupled).
- **App Store Connect ↔ Xcode** — Archive→Upload через automatic signing (D-03). Tuist regenerates pbxproj if Project.swift changes; iOS team `UAN8W9Q82U` already configured.
- **TestFlight ↔ Apple ID invite flow** — Internal testers получают invite по Apple ID email; не требует своего paid Apple Developer Program.

</code_context>

<specifics>
## Specific Ideas

- **Toggle UX:** «Правила маршрутизации» (D-04) живёт в AdvancedSettings рядом с уже существующим `RulesViewerSection`. User feedback: «там же, где описаны правила маршрутизации».
- **Version 0.1.0 (beta-style)** signals «early access» к testers; public App Store launch bump к 1.0.0.
- **Friends-and-family invite** через App Store Connect → Users and Access (Individual account works; не требует separate Apple Developer Program с их стороны).
- **Brief invite text** для TestFlight «What to Test» — user prefers лаконично, без длинного test plan.

</specifics>

<deferred>
## Deferred Ideas

### Carry-forward to v1.1+
- **Subscription quota fields** (Figma 3064:1154) — расширить `VPNCore.Subscription` model (`usedBytes`, `totalBytes`, `expiresAt`) + conditional progress bar в `SubscriptionHeader`. Backend support тоже needed.
- **macOS Figma rebuild** — macOS app сейчас использует pre-Phase 12 UI. Phase 12 закрыл только iOS BBTB v3 screens. macOS rebuild — отдельный phase.
- **DETECT-03 admin handoff** — sign `rules.json` + MAX-domains для anti-detection (проверка наличия конфликтующих VPN apps и blocked domains).
- **External Testing + public invite link** — up to 10,000 testers via public link, требует Beta App Review (~1-2 дня first time) + Privacy Policy URL + full App Store metadata. Open path beyond friends-and-family.
- **SPKI subscription pin replacement** — real cert SPKI hashes через `scripts/generate-spki-pin.swift` + wire `PinnedSubscriptionURLFetcher` в production. Defence-in-depth против compromised CA / custom root CA MITM.
- **App Store submission (full review)** — full App Store metadata (description, keywords, categories, screenshots в App Store sizes), Privacy Policy URL, full App Review (1-3 дня).
- **Full Light mode** — designer должен дорисовать Light versions всех экранов в Figma; сейчас Light functional но визуально не finalized.
- **Power-Glow effect восстановление** — отдельный design pass если решим вернуть (Phase 12 не включал).

### Reviewed and stayed in scope
- None — discussion stayed within Phase 13 boundary (1 new app feature + distribution setup).

</deferred>

---

*Phase: 13-testflight-internal-distribution*
*Context gathered: 2026-05-16*
