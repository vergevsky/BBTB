# Индекс wiki

Структурированный knowledge base для проекта VPN-клиента под macOS и iOS с фокусом на обход ТСПУ. Все страницы maintainятся автоматически на основе документов в `raw/`. Подробности процесса — в `CLAUDE.md` в корне проекта.

**Связанные артефакты вне wiki:**
- `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` — авторитетный системный промт для Claude Code (актуальная версия, v2)
- `.planning/ROADMAP.md` — оперативный план реализации (12 фаз, GSD)
- `.planning/PROJECT.md` — описание проекта и key decisions
- `.planning/REQUIREMENTS.md` — детальный список v1-требований с REQ-IDs

---

## Архитектура и продукт

- [[product-overview]] — что строим, для кого, как раздаём
- [[architecture]] — SwiftPM-структура, Network Extension таргеты, plugin-pattern
- [[tech-stack]] — Swift 6, sing-box, xray-core, WireGuardKit, swift-crypto
- [[release-roadmap]] — версии v0.1 → v2.1 с Definition of Done
- [[ux-specification]] — поведение онбординга, главного экрана, списка серверов, настроек

## Протоколы и транспорты

- [[protocols-overview]] — 9 протоколов, порядок реализации, auto-fallback
- [[vless-reality]] — главный anti-ТСПУ протокол проекта (v0.1 ✓)
- [[trojan]] — Trojan TCP+TLS и WS+TLS, ALPN-правило для WS (v0.2 ✓)
- [[transports]] — XHTTP, gRPC, WebSocket, HTTPUpgrade

## Anti-DPI и ТСПУ

- [[tspu]] — что такое ТСПУ и как она угрожает проекту
- [[anti-dpi-techniques]] — uTLS, фрагментация ClientHello, padding, mux, CDN-фронтинг

## Безопасность

- [[kill-switch]] — системный kill switch через includeAllNetworks
- [[dns-strategy]] — DoH, encrypted bootstrap, whitelist провайдеров (планирование)
- [[dns-pipeline-decisions]] — имплементированный DNS pipeline после Phase 1 W5 (fakeip + Yandex bootstrap + route.resolve)
- [[auto-reconnect]] — Apple's NEOnDemandRule reconnect (Phase 6c) — sliding session window между Connect и любым session-closing событием. Заменяет custom state machine из Phase 6.
- [[ipv6-strategy]] — туннелирование IPv6 или fallback на блок
- [[rules-engine]] — централизованный rules.json с Ed25519-подписью
- [[deep-links]] — bbtb:// + Universal Links через import.bbtb.app
- [[max-messenger]] — мессенджер MAX, детект и блокировка
- [[security-gaps]] — открытые вопросы и темы для обсуждения

## Детект VPN на устройстве (методика РКН и её реализации)

- [[rkn-methodology-document]] — первоисточник: официальная методика РКН, четыре этапа, матрица решений
- [[apple-detection-surface]] — конкретные API детекта на iOS и macOS, что мы можем скрыть
- [[geoip-detection]] — этап 1 методики: главный фронт защиты — GeoIP
- [[snitch-rtt-detection]] — RTT-триангуляция, ОС-независимый сетевой метод
- [[false-positives]] — что методика считает «не VPN» (потенциальные «прикрытия»)
- [[rkn-detection-methodology]] — Android-имплементация методики (репо xtclovver/RKNHardering)
- [[vpn-detection-by-apps]] — 22 из 30 приложений в РФ детектят VPN, 19 отправляют на сервер
- [[xray-localhost-vulnerability]] — критическая уязвимость локального SOCKS5 в xray/sing-box

## Дистрибуция и юр-аспекты

- [[distribution-testflight]] — TestFlight External, 10k тестировщиков, 90-дневный цикл
- [[licensing]] — гибрид AGPL-3.0 ядро + closed-source GUI

## Референсы и внешние документы

- [[config-parser-singbox-launcher]] — документация парсера URI/подписок из singbox-launcher

## Сервис

- `log.md` — журнал изменений wiki (append-only)

---

## Карта связей по темам

**Главная угроза → защита:**
- [[tspu]] → [[vless-reality]] + [[anti-dpi-techniques]] + [[transports]]

**Stack безопасности на устройстве:**
- [[kill-switch]] + [[dns-strategy]] + [[ipv6-strategy]] + [[rules-engine]]

**Локальный детект VPN (отдельная угроза от ТСПУ):**
- Первоисточник: [[rkn-methodology-document]]
- Применимость к нам: [[apple-detection-surface]] (iOS+macOS специфика)
- Главный фронт: [[geoip-detection]]
- ОС-независимая сетевая угроза: [[snitch-rtt-detection]]
- Что не считается VPN: [[false-positives]]
- Практическая Android-имплементация для понимания: [[rkn-detection-methodology]]
- Конкретная уязвимость нашего движка: [[xray-localhost-vulnerability]]
- Кто это делает в РФ: [[vpn-detection-by-apps]]
- Открытые вопросы: [[security-gaps]]

**Импорт и доставка конфигов:**
- [[config-importer]] — универсальный pipeline (subscription URL / QR / JSON endpoint), PoolBuilder, urltest (v0.2 ✓)
- [[server-management]] — server list UI, multi-subscription, pull-to-refresh, auto-select, merge-by-identity (v0.3 ✓)
- [[deep-links]] + [[distribution-testflight]] + [[rules-engine]] + [[config-parser-singbox-launcher]]

**Юридический слой:**
- [[licensing]] + [[distribution-testflight]]

---

## Что ещё хочется проработать

Помимо [[security-gaps]]:

- Три Instagram-reels из `raw/Дыры в безопасности, которые нужно обсудить.md` — нужен пересказ от пользователя
- Verification по поводу localhost-SOCKS5 на iOS — обязательный пункт до v0.1
- `enforceRoutes` на macOS — поиск способа защиты от DNS leak без выставления именно этого флага
- Серверная инфраструктура: hosting vs resident IP, география exit-серверов (упоминание в [[geoip-detection]])
- Детальные страницы по каждому из остальных 8 протоколов (после [[vless-reality]]) — по мере появления новых источников
