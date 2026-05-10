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

Для нашего проекта (см. [[product-overview]]) **TestFlight External** — оптимальный канал:

- 10 000 пользователей хватает с большим запасом для «друзей и знакомых разработчика»
- Никакого публичного App Store — минимум поводов для РКН
- Публичная invite-ссылка позволяет делиться приложением через Telegram и аналогичные каналы
- Beta App Review проще полного App Store Review

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

## Related pages

- [[product-overview]]
- [[licensing]]
- [[deep-links]]
- [[release-roadmap]]
- [[max-messenger]]
