# Roadmap: BBTB

**Source of truth:** `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` `<release_roadmap>` section.

**Phases:** 12 (one per release v0.1–v0.12 + v1.0 merged into Phase 12).
**Mode:** Each phase is `mvp` — vertical slice that compiles and tests end-to-end.

Phase numbering follows the release numbering. Sub-phases are not used at this granularity.

---

### Phase 1: Foundation ✓ Complete 2026-05-11
**Goal:** Минимально жизнеспособная сборка с VLESS+Vision+Reality, kill switch и базовой архитектурой SwiftPM. Версия — **v0.1**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** CORE-01, CORE-02, CORE-04, CORE-06, CORE-07, CORE-08, CORE-10, SEC-01, SEC-02, SEC-03, SEC-04, SEC-05, SEC-06, KILL-01, KILL-02, PROTO-01, IMP-01, UX-02, UX-03, UX-07, TELEM-01, LOC-01, DIST-01, DIST-02
**Success Criteria:**
1. На реальном iPhone и MacBook можно импортировать VLESS+Reality конфиг через буфер обмена → подключиться по одной кнопке → IP меняется на проверке `https://api.ipify.org`.
2. При разрыве туннеля kill switch блокирует весь трафик до восстановления или ручного отключения.
3. Security review passed: тест-приложение не находит отвечающих SOCKS-портов на `127.0.0.1` нашего PacketTunnelProvider; gRPC API sing-box отключён; `P2P=false` на интерфейсе (R1 + R6).
4. В release-режиме нет debug-логов в консоли.
5. Базовый SwiftPM-скелет соответствует структуре из `prompts/v2 <swift_package_layout>`: модули для VPNCore, ProtocolRegistry, ProtocolEngine, Protocols, KillSwitch созданы и компилируются.

---

### Phase 2: Trojan + Import flow ✓ Complete 2026-05-12
**Goal:** Расширить v0.1 до universal-парсера всех трёх форматов раздачи ссылок (subscription URL / multi-line plain-text URI / JSON endpoint), второго протокола (Trojan-TCP/TLS + Trojan-WS/TLS), auto-fallback через sing-box `urltest` outbound, toggle отключения kill switch. Версия — **v0.2**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** PROTO-02, PROTO-10, IMP-02, KILL-03 + foundation: IMP-04 (partial — universal URI parser + subscription URL fetch), IMP-05 (partial — все URI-схемы распознаются), TRANSP-03 (partial — WebSocket transport для Trojan), SRV-* (foundation — SwiftData массив `ServerConfig` с `isSupported` + `subscriptionURL` полями)
**Scope shifts (vs original ROADMAP, согласованы в `/gsd-discuss-phase 2` 2026-05-11):**
- IMP-03 (file picker) → **переезжает в Phase 11** (UX-01 onboarding) как угловая ссылка «У меня уже есть конфиг файл».
- IMP-04/IMP-05/TRANSP-03/SRV-* в Phase 2 — только foundation (parser + storage). UI выбора серверов / pull-to-refresh / multi-subscription / полная поддержка Outline+Clash YAML — остаются в Phase 3-4.
**Success Criteria:**
1. Пользователь импортирует конфигурацию через буфер обмена (URI / multi-line блок URI / subscription URL / JSON endpoint URL) или QR-код. Все три формата раздачи ссылок принимаются. Неподдержанные протоколы в подписке (например Shadowsocks в v0.2) парсятся с флагом `isSupported=false` без отказа всего импорта.
2. При блокировке VLESS+Reality sing-box `urltest` outbound автоматически переключается на Trojan (или другой работающий outbound из пула) без действий пользователя.
3. Trojan handler (PROTO-02) подключается на TCP+TLS и WebSocket+TLS транспорте.
4. Toggle «Kill Switch» появляется в Settings page → раздел «Безопасность», применяется при следующем connect (баннер «Переподключитесь для применения»).
5. Камера запрашивает permission корректно на iOS (NSCameraUsageDescription) и macOS.
6. Главный экран переписан под новый layout: top bar (≡ слева → Settings, + справа → меню QR/буфер), idle = timer → status pill → power-кнопка → server-line; empty = центральная карточка с двумя кнопками.
7. SwiftData массив `ServerConfig` — Phase 1 singleton успешно мигрирован.
8. Unit-test suite зелёный (ConfigParser форматы, Trojan template, urltest config builder, kill switch параметризация).

---

### Phase 3: Server management ✓ Complete 2026-05-12
**Goal:** Управление серверами — auto-select по latency, список серверов с pull-to-refresh, поддержка нескольких подписок. Версия — **v0.3**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** SRV-01, SRV-02, SRV-03, UX-04
**Success Criteria:**
1. Список серверов обновляется по pull-to-refresh, latency пересчитывается. ✓
2. Auto-select переключает на сервер с наименьшим latency + минимальными потерями пакетов. ✓
3. При подключении timer считает с момента установки туннеля. ✓
4. Если подписки несколько — секции в списке. ✓
**UAT**: T1-T8 PASS 2026-05-12. 3 бага закрыты: SwiftData UUID? predicate, SNI rotation в identity, TunnelController disconnect race. Подробности — `wiki/server-management.md`.

---

### Phase 4: Protocol expansion
**Goal:** Добавить ещё 3 протокола (VLESS+XTLS-Vision без Reality, Shadowsocks-2022, Hysteria2). Парсер URI-форматов уже работает с Phase 2 (foundation) — Phase 4 финализирует handler'ы для всех схем и полные subscription-форматы (Outline access keys, Clash YAML). Версия — **v0.4**.
**Mode:** mvp
**UI hint:** no
**Requirements:** PROTO-03, PROTO-04, PROTO-05, IMP-04 (finish — все URI handler'ы), IMP-05 (finish — Outline + Clash YAML)
**Success Criteria:**
1. Импортируется любой формат: `vless://`, `ss://`, `trojan://`, `hy2://`, subscription URL v2ray, Outline access keys.
2. Все 5 протоколов (Reality, Vision, SS-2022, Hysteria2, Trojan) подключаются на тестовых серверах.
3. ConfigParser написан с юнит-тестами для каждого формата.

**Plans:** 6 plans (waves 1-6)

Plans:
**Wave 1**
- [x] 04-01-PLAN.md — Wave 0 foundation: Yams 6.2.1 + AnyParsedConfig 5 cases + test scaffolds + 11 fixtures

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 04-02-PLAN.md — VLESS+TLS vertical slice (PROTO-03): VLESSURIParser D-02 + Protocols/VLESSTLS package + PoolBuilder branch

**Wave 3** *(blocked on Wave 2 completion)*
- [ ] 04-03-PLAN.md — Shadowsocks vertical slice (PROTO-04): ShadowsocksURIParser dual-decoder + Protocols/Shadowsocks + PoolBuilder branch

**Wave 4** *(blocked on Wave 3 completion)*
- [ ] 04-04-PLAN.md — Hysteria2 vertical slice (PROTO-05): D-08 R1 EXCEPTION + D-09 dual scheme + Protocols/Hysteria2 + R1 invariant test

**Wave 5** *(blocked on Wave 4 completion)*
- [ ] 04-05-PLAN.md — Clash YAML + universal routing finish (IMP-04, IMP-05): ClashYAMLParser + UniversalImportParser classify

**Wave 6** *(blocked on Wave 5 completion)*
- [ ] 04-06-PLAN.md — Integration: ConfigImporter 5-case switches + runIsSupportedUpgrade (D-14) + App registration + Tuist

---

### Phase 5: Transports
**Goal:** Финализация 4 транспортов поверх VLESS/VMess (WebSocket уже partial в Phase 2 для Trojan), ручной выбор транспорта в Расширенных. Версия — **v0.5**.
**Mode:** mvp
**UI hint:** no
**Requirements:** CORE-03, TRANSP-01, TRANSP-02, TRANSP-03 (finish — расширить за пределы Trojan-WS), TRANSP-04, TRANSP-05
**Success Criteria:**
1. VLESS работает поверх каждого из четырёх транспортов (XHTTP, gRPC, WebSocket, HTTPUpgrade).
2. TransportRegistry регистрирует транспорты по аналогии с ProtocolRegistry.
3. В Расширенных можно вручную выбрать транспорт для дебага.

---

### Phase 6: Network resilience
**Goal:** DNS-стратегия (DoH + bootstrap + whitelist), IPv6-туннелирование с fallback на блок, auto-reconnect, failover. Версия — **v0.6**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** NET-01, NET-02, NET-03, NET-04, NET-05, NET-06, NET-07, NET-08, NET-09, NET-10, NET-11
**Success Criteria:**
1. DNS leak-test пройден на iOS и macOS (через dnsleaktest.com и аналогичные).
2. IPv6 leak-test пройден (через ipv6-test.com).
3. Смена сети Wi-Fi ↔ LTE не приводит к утечкам трафика, реконнект автоматический.
4. Выход из sleep — реконнект происходит без вмешательства пользователя.
5. При падении сервера failover переключает на следующий из подписки.

---

### Phase 7: Anti-DPI suite + WireGuard family
**Goal:** Полный набор anti-DPI техник и оставшиеся 4 протокола (WireGuard, AmneziaWG, TUIC v5, OpenVPN/TLS). Версия — **v0.7**.
**Mode:** mvp
**UI hint:** no
**Requirements:** PROTO-06, PROTO-07, PROTO-08, PROTO-09, DPI-01, DPI-02, DPI-03, DPI-04, DPI-05, DPI-07
**Success Criteria:**
1. Все 9 протоколов из спецификации подключаются на тестовых серверах.
2. uTLS-fingerprint работает и переключается между Chrome/Firefox/Safari/random.
3. Тестовый DPI-сценарий (имитация ТСПУ-блокировки по SNI) проходится без вмешательства пользователя.
4. WireGuard через WireGuardKit и AmneziaWG со своей обфускацией работают параллельно.

---

### Phase 8: Rules Engine + Split tunneling
**Goal:** Централизованные правила с Ed25519-подписью, split-tunneling по доменам/IP/странам, AppProxyProvider на macOS. Версия — **v0.8**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** CORE-05, RULES-01, RULES-02, RULES-03, RULES-04, RULES-05, RULES-06, RULES-07, RULES-08, RULES-09, RULES-10, RULES-11
**Success Criteria:**
1. Подмена `rules.json` на сервере → клиент применяет новые правила в течение 6 часов.
2. Битая Ed25519-подпись → приложение игнорирует обновление, использует кешированную версию.
3. На macOS AppProxyProvider позволяет роутить отдельные приложения через VPN.
4. Просмотр правил (read-only) в Расширенных отражает актуальный rules.json.
5. Кнопка «Принудительно обновить правила» в Расширенных работает.

---

### Phase 9: Deep links
**Goal:** Custom URL Scheme `bbtb://` и Universal Links через `import.bbtb.app` с landing page. Версия — **v0.9**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** DEEP-01, DEEP-02, DEEP-03, DEEP-04, DEEP-05
**Success Criteria:**
1. Тап в Telegram на `bbtb://import?config=...` открывает приложение и импортирует конфиг.
2. Тап на `https://import.bbtb.app/c/{token}` делает то же самое.
3. При отсутствии приложения Universal Link открывает landing page со ссылкой на TestFlight invite.
4. `DeepLinkRouter` корректно парсит и connect, и disconnect, и import URLs.

---

### Phase 10: Advanced settings + Security polish
**Goal:** Полные Расширенные настройки, биометрия, STUN-блок toggle, CDN-фронтинг, cert pinning, ручной выбор протокола, On-Demand rules, **macOS-тоггл enforceRoutes** (R5). Версия — **v0.10**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** UX-06, BIO-01, BIO-02, BIO-03, BIO-04, DPI-06, DPI-08, DPI-09, ONDEMAND-01, KILL-04
**Success Criteria:**
1. Все опции в Расширенных функциональны и сохраняются между запусками.
2. Биометрия защищает приложение при backgrounding (при включённой опции).
3. STUN-блок при включении блокирует UDP 3478/5349 и показывает предупреждение про сломанные браузерные звонки.
4. CDN-фронтинг через Cloudflare/Fastly доступен как fallback transport.
5. Cert pinning защищает соединение с панелью подписок.
6. **macOS:** тоггл «Отключить принудительную маршрутизацию» работает корректно — `enforceRoutes=false` применяется к туннелю при выборе пользователя (R5).

---

### Phase 11: Onboarding + UX polish
**Goal:** Финальный дизайн всех экранов по Figma, полная локализация ru/en, MAX-detection в логи, FAQ, **file picker импорт** (IMP-03, переехал из Phase 2 после `/gsd-discuss-phase 2` 2026-05-11). Версия — **v0.11**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** UX-01, UX-08, UX-09, DETECT-01, DETECT-02, DETECT-03, TELEM-02, LOC-02, LOC-03, LOC-04, IMP-03
**Notes:**
- `ServerListSheet` использует статические константы высоты строк (`serverRowH=80`, `autoCellH=116`, `subHeaderH=44`) для расчёта `presentationDetents`. **При применении Figma-макетов эти константы нужно пересмотреть** — они в `ServerListSheet.swift` (приватные `static let`). Иначе шит может открываться на неправильной высоте.

**Success Criteria:**
1. Visual review всех экранов соответствует Figma-макетам.
2. Локализация-аудит не находит «hardcoded English strings» ни в одном экране.
3. FAQ в Help содержит секции про WebRTC leak и про известные ограничения детектирования VPN (22 приложения).
4. MAX-detection отрабатывает корректно — без UI, только в локальный лог.
5. Кнопка «Отправить лог разработчику» собирает 24ч логов и отправляет на endpoint разработчика.
6. Анимации переходов состояний главной кнопки плавные.

---

### Phase 12: Pre-release + Public TestFlight (v0.12 + v1.0)
**Goal:** Telemetry, performance audit, Beta App Review submission, public invite link, лендинг. Финальная сборка для публичного TestFlight. Версии — **v0.12** и **v1.0**.
**Mode:** mvp
**UI hint:** yes
**Requirements:** TELEM-03, TELEM-04, TELEM-05, TELEM-06, TELEM-07, TELEM-08, TELEM-09, SEC-07, DIST-03, DIST-04, DIST-05, DIST-06, DIST-07, DIST-08
**Success Criteria:**
1. Privacy-respecting аналитика батчем долетает до собственного VPS, агрегация работает.
2. Crash reporter с UI отправки запускается при следующем запуске после краша.
3. Performance audit (Instruments: CPU, memory, energy) пройден — нет утечек памяти при многочасовом подключении.
4. App Privacy declaration в App Store Connect заполнена корректно.
5. **Beta App Review пройден** — приложение одобрено для External Testing.
6. Public invite link через TestFlight работает; пользователь из Telegram может установить приложение и импортировать конфиг без помощи разработчика.
7. Сайт лендинга с invite-ссылкой опубликован.
8. About-screen содержит версию, ссылку на open-source ядро (GitHub), лицензии (AGPL-3.0 ядра).
9. Documentation для пользователей опубликована (как импортировать, как поделиться, как сообщить о баге).

---

## Global Definition of Done (после Phase 12)

- [ ] iOS-сборка работает на iPhone 11+ (минимальное устройство для iOS 18).
- [ ] macOS-сборка работает на Apple Silicon.
- [ ] Все 9 протоколов подключаются успешно.
- [ ] Kill switch блокирует утечки.
- [ ] IPv6 leak-test пройден.
- [ ] DNS leak-test пройден.
- [ ] WebRTC leak-test пройден (с дефолтным выключенным STUN-блоком, пользователь предупреждён через FAQ).
- [ ] **Security review sing-box engine** (R1): нет SOCKS5 на localhost, gRPC API отключён, P2P=false. Тест-приложение подтверждает.
- [ ] Rules Engine: подмена `rules.json` на сервере → приложение применяет в течение 6 часов; битая подпись → откат на кеш.
- [ ] Deep links работают (custom scheme + Universal Links).
- [ ] Аналитика батч долетает до сервера.
- [ ] Crash reporter ловит и отправляет крашлоги.
- [ ] Локализация ru/en полная.
- [ ] App Privacy declaration корректна.
- [ ] FAQ содержит известные ограничения детектирования VPN.
- [ ] Beta App Review пройден.

## Beyond v1.0

После v1.0 — внутри публичного TestFlight, расширение фичами в v1.1–v1.9 (smart auto-select, stats pro, multi-hop, widgets, watch, push, shortcuts, stealth, iCloud sync). Мажорное изменение бизнес-модели — v2.0 (managed servers + биллинг). См. `prompts/v2 <release_roadmap>` секции v1.1–v2.1 для детализации.

---
*Created: 2026-05-11 from prompts/v2 release_roadmap.*
*Coverage: ~130 v1 requirements, all mapped to one of 12 phases.*
