---
name: Kill switch
description: Системный kill switch через includeAllNetworks, по умолчанию включён, тоггл в Расширенных
type: project
---

# Kill switch

**Summary**: Системный kill switch через `includeAllNetworks = true` в `NEVPNProtocol`. Если туннель падает, ОС блокирует весь сетевой трафик до восстановления или ручного отключения. По умолчанию включён.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-12

---

## Что это

Kill switch — это страховка от утечки трафика мимо VPN. Если по какой-то причине туннель разорвался, kill switch блокирует **весь** сетевой трафик устройства до момента восстановления туннеля или ручного отключения VPN пользователем.

Без kill switch при разрыве туннеля трафик идёт напрямую через провайдера — то есть мимо VPN. Это раскрывает IP пользователя и его реальные DNS-запросы.

## Реализация

Системный, через NetworkExtension API:

- `NEVPNProtocol.includeAllNetworks = true` (iOS 14+, macOS 11+)
- `NEVPNProtocol.enforceRoutes = true` — гарантия, что split DNS не утечёт

Эти флаги делают kill switch системным — блокирует трафик сама ОС, а не приложение. Это надёжнее: даже если приложение зависнет или будет убито, kill switch остаётся активным.

> **Trade-off `enforceRoutes` на macOS — принятое решение.** Методика РКН называет `enforceRoutes` техническим признаком VPN (см. [[rkn-methodology-document]] раздел 8.4). Решение от 2026-05-11: **оставляем `enforceRoutes = true` по дефолту** — защита от DNS-leak приоритетнее снижения детектируемости (см. [[security-gaps]] R4). Tech-savvy пользователи смогут отключить через опцию в [[ux-specification|Расширенных]] начиная с v0.10 (см. [[security-gaps]] R5). В v1.x — пересмотреть с поиском альтернативной защиты от leak без выставления флага.

## Состояние

- **Включён по умолчанию**
- Тоггл для отключения — в разделе [[ux-specification|Расширенных]] настроек
- При активном kill switch и падении туннеля ОС блокирует весь сетевой трафик до восстановления или ручного отключения VPN

## Verification (DoD)

Проверяется вручную: отключаешь Wi-Fi на сервере (или иным образом ломаешь туннель) → проверяешь, что на устройстве нет интернета. Это часть Definition of Done для v0.1 (см. [[release-roadmap]]).

## Реализация v0.2 (2026-05-12)

✓ **Тоггл реализован** в разделе «Безопасность» (SettingsFeature). Пользователь может отключить kill switch без перезапуска туннеля — настройка применяется при следующем подключении.

✓ **ReconnectBanner** — жёлтый баннер появляется на главном экране, когда kill switch включён и туннель активен. Напоминает пользователю, что при разрыве VPN весь трафик будет заблокирован. Dismiss по тапу. UAT T9 PASS 2026-05-12.

## Roadmap

- ✓ **v0.1** — kill switch включён по дефолту (с `enforceRoutes=true`), без тоггла
- ✓ **v0.2** — тоггл «выключить kill switch» в Безопасность + ReconnectBanner при активном KS
- **v0.10** — финальные настройки безопасности: On-Demand rules + опция «отключить `enforceRoutes` на macOS» (см. [[security-gaps]] R5)

## Related pages

- [[architecture]]
- [[ux-specification]]
- [[dns-strategy]]
- [[ipv6-strategy]]
- [[release-roadmap]]
- [[apple-detection-surface]]
- [[rkn-methodology-document]]
- [[security-gaps]]
