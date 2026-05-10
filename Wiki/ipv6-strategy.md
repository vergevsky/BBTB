---
name: IPv6-стратегия
description: Туннелирование IPv6 через VPN, fallback на блокировку если сервер не поддерживает, никаких leak'ов
type: project
---

# IPv6-стратегия

**Summary**: По умолчанию IPv6 туннелируется через VPN (full-tunnel). Если сервер не поддерживает IPv6 — автоматический fallback на блокировку на уровне ОС. Никакого «leak IPv6 напрямую».

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-11

---

## Зачем

IPv6 — частый источник утечки трафика в VPN-клиентах. Сценарий leak'а: VPN туннелирует IPv4, но IPv6 идёт напрямую через провайдера. Если сайт доступен по IPv6 — браузер выберет его, и реальный IP пользователя раскрывается.

Решение: либо туннелировать IPv6 тоже, либо полностью блокировать его на уровне ОС.

## Поведение

| Сценарий | Что делает приложение |
|----------|-----------------------|
| Сервер поддерживает IPv6 | Туннелирует через VPN (full-tunnel IPv6) — по умолчанию |
| Сервер не поддерживает IPv6 | Fallback на блокировку через `NEPacketTunnelNetworkSettings.ipv6Settings = nil` + `excludeRoutes` для всех IPv6 destinations |
| Пользователь хочет принудительный режим | Опция в Расширенных: `auto` / `tunnel` / `block` |

**Никогда не допускаем** прямой выход IPv6 мимо туннеля.

## Verification (DoD)

IPv6 leak-test пройден — часть Definition of Done для v0.6 (см. [[release-roadmap]]). Проверяется через сайты типа `ipv6-test.com`.

## Roadmap

- **v0.6** — IPv6 туннелирование с fallback на блок
- **v0.10** — выбор режима в Расширенных

## Related pages

- [[kill-switch]]
- [[dns-strategy]]
- [[anti-dpi-techniques]]
- [[ux-specification]]
