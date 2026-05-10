---
name: Лицензирование и юр-аспекты
description: Гибридная модель — ядро AGPL-3.0, GUI закрытый, Apple Developer вне РФ
type: project
---

# Лицензирование и юр-аспекты

**Summary**: Гибридная модель — ядро под AGPL-3.0 (обёртка sing-box, парсеры, network logic) в публичном репозитории, GUI и pro-фичи закрытые. Это юридически корректно по отношению к GPL-3 sing-box.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-11

---

## Зачем гибрид

Sing-box (главный движок проекта — см. [[tech-stack]]) лицензирован под **GPL-3 (General Public License 3)**. Это значит, что любой код, который **линкуется с sing-box**, должен быть тоже под GPL-совместимой лицензией.

Решение:

| Часть проекта | Лицензия | Причина |
|---------------|----------|---------|
| **Ядро**: обёртка sing-box, парсеры конфигов, network logic | AGPL-3.0 (Affero General Public License 3.0) | Линкуется с GPL-3 sing-box → должно быть GPL-совместимо. AGPL — расширенная GPL для сетевых сервисов. |
| **GUI и pro-фичи** | Closed-source | Не линкуется напрямую с sing-box (взаимодействует через Swift-обёртки и App Group), даёт контроль над продуктом. |

Это **юридически корректно** по отношению к sing-box и даёт контроль над продуктом.

## Что в публичном репозитории

- Обёртка sing-box (SingBoxBridge)
- Парсеры конфигов (vless://, ss://, trojan://, JSON, Outline, Clash YAML)
- Network logic (kill switch, DNS-стратегия, IPv6-стратегия)
- Protocol implementations
- Transport implementations
- Реестры (ProtocolRegistry, TransportRegistry)

## Что закрыто

- GUI (SwiftUI-экраны, дизайн)
- DesignSystem
- AppFeatures (модули по экранам)
- Pro-фичи (потенциально, в v2.0+)

## Apple Developer аккаунт

- **Зарегистрирован вне РФ** на физлицо (Individual)
- Юр.лица как такового нет — никакого ООО / ИП
- Серверов в РФ нет (см. [[distribution-testflight]])

## Юридические соображения

- Открытое ядро под AGPL — производное от sing-box, юридически чистое
- GUI как closed-source — нормальная практика для гибридной модели (аналогично Hiddify, NekoBox и др.)
- Никакого хостинга в РФ
- Apple Developer Individual вне РФ снижает риски персональной ответственности

## Open questions

См. [[security-gaps]] — раздел про юридические риски Apple Developer аккаунта.

## Related pages

- [[product-overview]]
- [[tech-stack]]
- [[distribution-testflight]]
- [[security-gaps]]
