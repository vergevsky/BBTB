---
name: Дистрибуция через TestFlight
description: External Testing с публичной invite-ссылкой, до 10 000 тестировщиков, 90-дневный цикл сборки
type: project
---

# Дистрибуция через TestFlight

**Summary**: Раздача через TestFlight (External Testing) с публичной invite-ссылкой, до 10 000 тестировщиков. Никакого публичного App Store на MVP. Срок жизни сборки — 90 дней, после нужен новый build.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-11

---

## Что это и почему

TestFlight — система Apple для бета-распространения приложений. Два режима:

- **Internal Testing** — до 100 человек с Apple Developer аккаунта, мгновенное распространение, без ревью
- **External Testing** — до 10 000 человек по invite-ссылке, **требуется Beta App Review** (более мягкий, чем App Store Review), 90 дней жизни сборки

**v1.0 strategy (2026-05-16 update):** старт через **Internal Testing only** —
до 100 testers, нет Beta App Review, instant access после processing
(~10-30 мин). Это minimum viable distribution path для friends-and-family
beta. External testers + public invite link перенесены на v1.1+ когда
будет реальный feedback от internal cycle.

Skip'ается в Internal-only path:
- Beta App Review (для External — 1-2 дня первый раз)
- Privacy Policy URL (не required для internal-only)
- Full App Store metadata (description, screenshots, categories)
- Pricing & availability

Полный App Store launch отложен — Phase 13 закрывает только TestFlight
Internal distribution; App Store submission будет в Phase 14+.

## Цикл жизни сборки

- Сборка живёт **90 дней**
- После — TestFlight перестаёт её раздавать новым пользователям, существующие не могут обновиться
- Это **не баг, а фича** для нашего use case (узкий круг друзей и знакомых, никакого публичного App Store)
- Регулярные новые билды через TestFlight — нормальный процесс

## Как обновляется приложение у пользователя

- TestFlight автоматически обновляет приложение при выходе новой версии
- При выпуске Phase 1 build пользователь нажмёт «обновить» один раз через TestFlight
- Дальше — автообновление, без ручных действий
- Поле `min_app_version` в [[rules-engine|rules.json]] даёт возможность отображать экран «обновитесь», если пользователь застрял на устаревшей версии

## Apple Developer аккаунт

- Зарегистрирован **за пределами РФ** на физлицо (Individual)
- Юр.лица как такового нет
- Подробности юр-аспектов — [[licensing]]

## Beta App Review

Submission-ready конфигурация — требование v1.0 (см. [[release-roadmap]]).

Принципиальные риски ревью в проекте:

- **NetworkExtension entitlements** — требуют обоснования в App Review notes
- **MAX-detection** через `canOpenURL:` — описывается как «проверка наличия конфликтующих VPN-приложений для совместимости» (см. [[max-messenger]])
- **VPN-функциональность как таковая** — Apple обычно пропускает legitimate VPN-клиенты, но требует декларации в App Privacy

## Связь с Deep Links

Universal Links с landing page для тех, у кого приложение не установлено — отправляют пользователя на TestFlight invite. См. [[deep-links]].

## Связь с публичной invite-ссылкой

В v1.0 — публичная invite-ссылка через TestFlight + сайт лендинга. См. [[release-roadmap]] (v1.0).

## Internal-only TestFlight walkthrough (Phase 13)

**Project config (verified 2026-05-16):**
- Team ID: `UAN8W9Q82U`
- Bundle ID (app): `app.bbtb.client.ios`
- Bundle ID (extension): `app.bbtb.client.ios.tunnel`
- Code signing: Automatic (Xcode auto-manages cert + profile)

**Steps:**

1. **Apple Developer Program — verify active.** [developer.apple.com/account](https://developer.apple.com/account) → войти → Team `UAN8W9Q82U` → Membership tab → status «Active».

2. **Network Extension capability на 2 App IDs.** Apple Portal → Certificates, Identifiers & Profiles → Identifiers → `app.bbtb.client.ios` и `.tunnel` → Edit → ✅ Network Extensions. Если App IDs ещё нет → ➕ Register New App ID → Bundle ID → Network Extensions checkbox.

3. **Create App Store Connect record.** [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → My Apps → ➕ New App. Минимум: Platform iOS, Name «BBTB», Primary Language, Bundle ID dropdown → `app.bbtb.client.ios`, SKU `bbtb-ios-client-001`, User Access Full Access.

4. **Xcode Archive + Upload.** Open `BBTB.xcworkspace` → scheme `BBTB`, destination **Any iOS Device (arm64)** → Product → Archive. Organizer открывается → Distribute App → App Store Connect → Upload → Automatically manage signing → Upload.

5. **TestFlight Internal Testing.** App Store Connect → app → TestFlight tab → Internal Testing → Create New Group → add team members by Apple ID. Tester получают email invite + redeem code → открывают TestFlight iOS app → Redeem → install build.

6. **Export Compliance — one-time.** При первом build в App Store Connect prompt: «Does app use encryption?» Yes → «Standard cryptography exemption» (HTTPS/TLS only — Apple's annual self-classification covers это).

**Apple processing time:** ~10-30 минут после Upload → status changes from «Processing» to «Ready to Submit / Test».

**Total interactive time:** 2-3 часа first time (Apple Portal navigation + App Store Connect setup); subsequent builds ~30 минут (Xcode Archive → Upload → wait → distribute).

## Related pages

- [[product-overview]]
- [[licensing]]
- [[deep-links]]
- [[release-roadmap]]
- [[max-messenger]]
