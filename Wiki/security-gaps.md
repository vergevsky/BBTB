---
name: Открытые вопросы безопасности
description: Список архитектурных развилок — активные, закрытые с резолюцией и отложенные на будущее
type: project
---

# Открытые вопросы безопасности

**Summary**: Аккумулятор архитектурных развилок и тем, требующих обсуждения. Содержит три раздела — активные вопросы, закрытые/принятые решения и отложенные TODO. Резолюции принимаются явным решением, фиксируются с обоснованием.

**Sources**: Дыры в безопасности, которые нужно обсудить.md, VPN-клиент для macOS и iOS — Промт для Claude Code.md, ocr_methodika_vpn_proxy.md

**Last updated**: 2026-05-12

---

## Активные вопросы

### A1. Что делать с 19 приложениями, отправляющими VPN-статус на сервер

**Контекст**: См. [[vpn-detection-by-apps]] — 22 из 30 приложений детектят VPN, 19 отправляют на сервер. Среди них — банки (Сбербанк, Т-Банк, ВТБ, Альфа), маркетплейсы (Wildberries, Ozon), MAX, Яндекс, ВК.

**Вопрос**:
- Какие именно из 19 что отправляют и куда?
- Документировать как «known limitation» в FAQ?
- Расширять список `never_through_vpn` в [[rules-engine|rules.json]] для критичных приложений (банки)?
- Можно ли скрыть `utun*` интерфейс от `NetworkInterface` на iOS без jailbreak? (Скорее всего — нет.)

### A2. Юридические риски Apple Developer аккаунта

**Контекст**: Apple Developer аккаунт зарегистрирован вне РФ на физлицо, юр.лица нет. См. [[licensing]].

**Открыто**:
- Что произойдёт, если РКН попросит Apple удалить приложение?
- Каковы реальные риски для разработчика-физлица?
- План на случай блокировки TestFlight в РФ (вряд ли реализуем, но обсуждаемо)?

### A3. iCloud Private Relay как edge case

**Контекст**: Методика РКН (см. [[rkn-methodology-document]] раздел 7.5) прямо запрещает приложениям автоматически классифицировать iCloud Private Relay как «обход блокировок». Это юридически защищённый сервис Apple.

**Open question**:
- Что произойдёт у пользователей с **одновременно включёнными** Private Relay и нашим VPN?
- Может ли пересечение наших сигналов с Apple-сигналами случайно увеличить риск ложноположительного срабатывания, или наоборот — снизить за счёт «маскировки» под Private Relay?
- Стоит ли в FAQ упомянуть отключение Private Relay при использовании нашего VPN?

### A4. Hosting-IP exit-серверов как главная угроза GeoIP

**Контекст**: [[geoip-detection]] — главный фронт детекта. Hosting-IP exit-серверов мгновенно ставит GeoIP-сигнал «выявлен».

**Open question**:
- Какая инфраструктура exit-серверов? Hetzner / DigitalOcean / Vultr — всё это hosting-диапазоны.
- Резидентные прокси — слишком дорого для MVP. Но имеет смысл оценить стоимость и юр-аспекты.
- Возможно ли использовать «нестандартные» хостинги (мелкие провайдеры в небольших юрисдикциях) — снизит ли это hosting-сигнал в БД?

### A5. Внешние материалы для дальнейшего анализа

- [https://github.com/xtclovver/RKNHardering](https://github.com/xtclovver/RKNHardering) — изучен, см. [[rkn-detection-methodology]]
- [https://habr.com/ru/articles/1020080/](https://habr.com/ru/articles/1020080/) — изучен, см. [[xray-localhost-vulnerability]]
- https://www.instagram.com/reels/DXIjyQHiLKD/ — **«что это за метод/протокол?»** — статус: **недоступно автоматическими средствами**
- https://www.instagram.com/reels/DW9wBIByL-S/ — статус: **недоступно автоматическими средствами**
- https://www.instagram.com/reels/DXO7ii5ChkW/ — статус: **недоступно автоматическими средствами**

**Попытки извлечения, предпринятые 2026-05-11**:
- Firecrawl: Instagram не поддерживается провайдером
- WebFetch напрямую: login-стена, OpenGraph недоступен
- Зеркало `ddinstagram.com`: ECONNREFUSED

**Действия**: ждём пересказа от пользователя, скриншота caption или альтернативного источника. Пока не возвращаемся.

---

## Закрытые / принятые решения

### R1. Локальный SOCKS5 в sing-box на iOS/macOS — security review перед v0.1 [решено 2026-05-11]

**Контекст**: [[xray-localhost-vulnerability]] — на Android sing-box запускает SOCKS5 на 127.0.0.1, любое приложение его сканирует. На iOS sandbox теоретически изолирует loopback, но это не верифицировано.

**Решение**: Зафиксировать как **обязательный security-блокер до v0.1**. План проверки:

1. Прочитать конфиг sing-box, который мы передаём в `libbox.xcframework`. Убедиться, что секции `inbounds` с `type: socks` или `mixed` **отсутствуют**. На iOS sing-box работает через packet-level туннелирование NetworkExtension — локальный SOCKS5 архитектурно не нужен.
2. Явно отключить gRPC API sing-box в production-сборке.
3. Написать iOS-тест: второе приложение пытается TCP-connect к `127.0.0.1:N` диапазона 1024–65535 (с фокусом на стандартные порты SOCKS — 1080, 9000, 5555, 16000–16100). Проверить, что ни один порт нашего PacketTunnelProvider не отвечает.
4. То же на macOS — там sandbox слабее, проверка важнее.

**Обоснование**: SOCKS5 на Android — остаток pattern'а, на iOS он архитектурно не нужен. Стоимость проверки — 1–2 часа. Риск пропустить — критический.

### R2. Sing-box vs WireGuardKit как основной движок [решено 2026-05-11]

**Контекст**: Если выявится, что sing-box на iOS уязвим — рассматривать ли смену движка на WireGuardKit?

**Решение**: **Sing-box остаётся** как основной движок, точка. Без Reality и anti-DPI suite проект бессмыслен — ТСПУ блокирует обычный WireGuard. Уязвимости sing-box (если найдутся) — решаются настройкой конфига, не сменой движка.

**Обоснование**: Без [[vless-reality]] — нет защиты от ТСПУ; без sing-box — нет Reality. Альтернатив нет.

### R3. WebRTC STUN-блок — выкл по умолчанию [решено 2026-05-11]

**Контекст**: WebRTC может раскрыть реальный IP через STUN (Session Traversal Utilities for NAT — утилиты обхода NAT для сессий).

**Решение для MVP**:
- В Расширенных тоггл «Блокировать STUN-трафик» — **выкл по умолчанию**
- При включении блокируются UDP-порты **3478, 5349**
- Предупреждение: «Это сломает звонки в браузерных мессенджерах (Google Meet, Discord Web, Zoom Web)»
- Описание в FAQ — что такое WebRTC leak и как защититься, если важно

**Обоснование**: Primary-аудитория — нетехнические пользователи. Сломанные браузерные звонки — критический UX-провал, перевешивает риск WebRTC leak (который в современных браузерах редко даёт **полное** раскрытие IP).

**Возможное будущее**: при появлении «режима повышенной приватности» (v1.x post-MVP) — STUN-блок может включаться автоматически в этом режиме.

### R4. `enforceRoutes` на macOS — оставляем `true` по дефолту [решено 2026-05-11, с TODO]

**Контекст**: В [[kill-switch]] мы используем `NEVPNProtocol.enforceRoutes = true` как защиту от split DNS-leak. Методика РКН (см. [[rkn-methodology-document]] раздел 8.4) прямо называет `enforceRoutes` техническим признаком VPN на macOS.

**Решение**: **Оставляем `enforceRoutes = true`** как дефолт. Защита от DNS-leak приоритетнее снижения детектируемости. Дополнительно реализуется опциональный тоггл в Расширенных для tech-savvy пользователей (см. R5).

**Обоснование**: 
1. DNS leak-test — обязательный пункт DoD v0.6
2. Детектируемость на macOS снижается через GeoIP-маскировку (см. [[geoip-detection]]), не через ручное отключение защит
3. Полностью отрицать сигнал нельзя — `getifaddrs()` всё равно показывает `utun*`

**TODO на будущее**: В v1.x пересмотреть — возможно ли получить эффект `enforceRoutes` другим способом (через явный `NEPacketTunnelNetworkSettings.dnsSettings.matchDomains = [""]` + `excludeRoutes`). Если да — выключить флаг и снизить сигнал. На MVP не вкладываемся.

### R5. macOS «снижение детектируемости» — одна опция в Расширенных [решено 2026-05-11]

**Контекст**: Поверхность детекта на macOS шире, чем на iOS (см. [[apple-detection-surface]]). Был вопрос: делать отдельный «Stealth mode» или единичную опцию.

**Решение**: **Одна опция в Расширенных** для tech-savvy пользователей. Черновая формулировка:

> **Отключить принудительную маршрутизацию (только macOS)** — выкл по умолчанию.
> Снижает детектируемость VPN сторонними приложениями на macOS за счёт отключения `enforceRoutes`. **Внимание**: может привести к утечке DNS — используйте только если понимаете последствия.

Опция появляется в v0.10 (Advanced settings, см. [[release-roadmap]]).

**Обоснование**: Отдельный «Stealth mode» как режим — лишний UX-узел и обманчивая метафора (полную невидимость на macOS дать нельзя). Одна явная опция честнее. Финальная формулировка — уточнить с дизайнером в Figma.

### R8. Интеграция libbox.xcframework — рецепт сборки и линковки [решено 2026-05-11 в Phase 1 build]

**Контекст**: libbox.xcframework собирается из `github.com/SagerNet/sing-box` (v1.13.11) через `make lib_apple` (gomobile bind). Готового артефакта в release-ах нет — нужно собирать локально. Полученный xcframework требует постобработки и явных linker-флагов, чтобы Xcode проект собрался.

**Известные проблемы libbox v1.13.11 → решения**:

1. **API: нет `LibboxBoxService`/`LibboxNewService`.** Сервис управляется через `LibboxCommandServer` + `commandServer.startOrReloadService(configContent, options:)`. Канонический паттерн — `SagerNet/sing-box-for-apple/Library/Network/ExtensionProvider.swift`.

2. **API: `LibboxSetup` принимает `LibboxSetupOptions` object**, не три позиционных String'а. См. `Libbox.objc.h` для актуальной сигнатуры.

3. **Protocol `LibboxPlatformInterface` (без `Protocol` suffix)** имеет 15 методов в v1.13.11. Один объект обычно конформит и `LibboxPlatformInterface`, и `LibboxCommandServerHandler` (передаётся в `LibboxNewCommandServer(handler:platformInterface:)` дважды).

4. **iOS/iOS Simulator/tvOS slices внутри xcframework — deep bundle с пустым Info.plist.** Apple требует shallow bundle для iOS. Решение — postprocess скрипт `BBTB/scripts/fix-libbox-xcframework.sh`:
   - Перенести содержимое `Versions/Current/*` в root.
   - Сгенерировать валидный Info.plist с `CFBundleExecutable=Libbox`, `CFBundlePackageType=FMWK`, `MinimumOSVersion=18.0`, `CFBundleSupportedPlatforms=[iPhoneOS|iPhoneSimulator|...]`.
   - Удалить symlinks и `Versions/`.

5. **Linker flags для extension/main app targets** (Tuist 4 фильтрует `.sdk()` для App Extension — выставляем через `settings.base["OTHER_LDFLAGS"]`):

   | Target | Required flags | Reason |
   |---|---|---|
   | BBTB-Tunnel-iOS | `-lresolv -framework UIKit` | libbox использует `res_9_*` BIND-9 resolver; `scoped_critical_action.o` тянет `UIApplication` для background tasks |
   | BBTB-Tunnel-macOS | `-lresolv -framework AppKit -framework SystemConfiguration` | resolver + `base::MessagePumpNSApplication` использует `NSApp/NSEvent`; `net::ProxyConfigServiceMac` использует `SCDynamicStore/SCErrorString/kSCPropNet*` |
   | BBTB (main iOS app) | `-lresolv` | libbox транзитивно линкуется через `CrashReporter → PacketTunnelKit → SingBoxBridge` |
   | BBTB-macOS (main app) | `-lresolv -framework SystemConfiguration` | то же транзитивно + macOS proxy config |

**Workflow при пересборке libbox**:
1. В sing-box репо: `make lib_apple` → создаётся `Libbox.xcframework`.
2. Скопировать в `BBTB/Vendored/libbox.xcframework` (lowercase).
3. Запустить `bash BBTB/scripts/fix-libbox-xcframework.sh`.
4. `tuist generate` в `BBTB/`.
5. `xcodebuild build` — оба scheme должны пройти.

### R7. Build system — Tuist 4.x [решено 2026-05-11 в Phase 1 execution]

**Контекст**: Xcode 15+ ввёл Synchronized Folders и убрал «Create folder references» опцию из Add Files dialog. Multi-target NSExtension setup через Xcode UI (workspace → project → 5 targets → 11 SPM packages → entitlements → xcconfig) хрупкий, требует ~50 минут кликов и не воспроизводим.

**Решение**: использовать Tuist 4.x с declarative `Project.swift` (Swift DSL) и `Workspace.swift` в корне `BBTB/`. Команда `tuist generate` создаёт `.xcodeproj` + `.xcworkspace` за секунды.

**Файлы**:
- `BBTB/Project.swift` — основной project с 5 targets (BBTB, BBTB-macOS, BBTB-Tunnel-iOS, BBTB-Tunnel-macOS, BBTB-AppProxy-macOS)
- `BBTB/Workspace.swift` — workspace declaration
- `BBTB/Tools/SocksProbe/Project.swift` — отдельный SocksProbe project (изолированный sandbox для R1 device proof)

**Что в git**: `Project.swift`, `Workspace.swift`, `.mise.toml` (если используется), `Config/*.xcconfig`, entitlements, source files. Не в git: generated `.xcodeproj`, `.xcworkspace`, `Derived/` папка Tuist.

**Обоснование**:
1. Воспроизводимость — кто угодно клонирует репо + `tuist generate` → identical project.
2. Plain-text diff — изменения в Project.swift видны в git diff (vs binary project.pbxproj).
3. Декларативность — добавление module = 5 строк Swift, не 30 кликов.
4. Подходит для роста проекта до 12 фаз с расширением модулей.

**Альтернативы рассмотрены**:
- **XcodeGen** (YAML) — рабочий, но менее мощный для модульных приложений; Swift DSL Tuist выразительнее.
- **Прямая работа в Xcode UI** — хрупкая, не воспроизводимая, плохо документируемая.

**Tooling**:
- `mise` для version-pinning Tuist (`mise use --global tuist@latest`).
- Или Homebrew для глобальной установки.

### R6. Параметр `P2P` интерфейса на iOS — не выставлять [решено 2026-05-11]

**Контекст**: Методика РКН (см. [[apple-detection-surface]]) называет параметр `P2P` на сетевом интерфейсе косвенным признаком VPN.

**Решение**: При настройке `NEPacketTunnelNetworkSettings` в PacketTunnelProvider **проверить и не выставлять P2P=true**. Работа на 30 минут, чистый плюс — закрывает один косвенный сигнал.

**Действия**:
- В v0.1 при разработке PacketTunnelProvider проверить дефолтное поведение `NEIPv4Settings`/`NEIPv6Settings` на предмет P2P
- Если выставляется через какой-то setter — не вызывать
- Если выставляется автоматически и не убирается — открывается новый вопрос (вернуть в активные)

### R10. TUN inbound runtime expansion + sing-box 1.13 DNS-hijack migration [решено 2026-05-11, gap-closure W3.1]

**Контекст**: В Phase 1 W3 Hiddify-импорт приходит **без `inbounds[]`** — это корректное поведение импортёра (клиент сам должен сконфигурировать PacketTunnel inbound). R1-валидатор первой версии запрещал любые `inbounds` целиком, поэтому изначальная попытка добавить TUN inbound в шаблон ломала валидацию. Параллельно sing-box 1.13 удалил `{type:"dns"}` outbound — старый паттерн `route.rules[outbound:"dns-out"]` больше не работает, нужен `action:"hijack-dns"` (см. [sing-box migration note](https://sing-box.sagernet.org/migration/#dns-outbound)).

В первой версии W3 это «починили» приватным `injectTunInbound` в `BaseSingBoxTunnel` (хак без тестов, runtime-инжект прямо в extension). W3.1 переносит это в loader.

**Решение**:

1. **R1 = default-deny white-list** `allowedInboundTypes = {tun, direct}` (изначально 2026-05-11 утром был default-allow black-list `{socks, http, mixed, redirect, tproxy}`, но это давало проблему «если sing-box добавит новый опасный тип, мы не знаем» — переписано на white-list ниже в тот же день). TUN и direct разрешены, потому что security-смысл R1 (см. [[xray-localhost-vulnerability]]) — защита от **listen-on-localhost** SOCKS-style API, а TUN на utun-интерфейсе loopback не слушает; direct — pass-through без exposed порта.
2. **`SingBoxConfigLoader.expandConfigForTunnel(json:mtu:tunIP:)`** — публичный, чисто функциональный, идемпотентный. Вызывается из `BaseSingBoxTunnel.startTunnel` сразу после `validate(json:)`.
3. **Post-expand re-validation (defense-in-depth)** — `BaseSingBoxTunnel.startTunnel` вызывает `validate(expandedJSON)` ВТОРОЙ раз перед `startOrReloadService`. Если когда-нибудь `expand` начнёт добавлять что-то запрещённое (регрессия) — поймаем здесь, до запуска engine.
4. **TUN inbound** добавляется с фиксированными полями: `tag="tun-in"`, `address=["198.18.0.1/30"]`, `mtu=1500`, `auto_route=false`, `stack="gvisor"`. (`sniff=true` removed in sing-box 1.13 — теперь делается через route.rules action:sniff).
5. **DNS-hijack migration**: при наличии `{type:"dns"}` outbound — удаляется; при наличии `route.rules[outbound:"dns-out"]` или `route.rules[protocol:"dns" + outbound: nonNil]` — выписывается `action:"hijack-dns"` (поле `outbound` стирается).

**Default-deny rationale**: white-list устойчивее чем black-list к будущим расширениям sing-box. Если завтра выйдет sing-box 1.14 с inbound типом `dns-server` (или любым другим listen-on-localhost), наш валидатор автоматически отвергнет — без правок кода. При расширении (например, Phase 7 WireGuard inbound) — `allowedInboundTypes` нужно явно расширить с code review.

**Обоснование выбранных полей TUN inbound**:

| Поле | Значение | Почему |
|------|----------|--------|
| `auto_route` | `false` | Routes УЖЕ настроены в `NEPacketTunnelNetworkSettings.includedRoutes` (`ExtensionPlatformInterface.openTun`). `auto_route: true` перетянул бы их и выставил флаг `POINTOPOINT` на utun — нарушение R6 (см. [[apple-detection-surface]]). |
| `stack` | `"gvisor"` | gVisor user-space netstack. Phase 1 W5 round-3 (2026-05-11) пытались переключить на `mixed` (Hiddify-default) — это привело к crash-loop'у при `creating stack` в нашей сборке libbox 1.13.11. Гипотеза: Hiddify собирает libbox с правильными build tags для system stack на iOS, мы — нет. Откатились на gvisor; рефактор build-системы libbox — задача отдельной фазы (TASK-Phase1.W6 или Phase 5). |
| `address` | `["198.18.0.1/30"]` | RFC 2544 benchmarking range — не пересекается ни с RFC 1918 LAN, ни с CGNAT. Маска `/30` — минимальная P2P подсеть (4 адреса), достаточно для UTUN. |
| `mtu` | `1500` | Standard Ethernet. Phase 1 W5 trace-log debug 2026-05-11 (вечер): MTU 9000 (Hiddify default) приводил к тому что **все 152 соединения через туннель умирали за <500мс** — паттерн «обе стороны закрываются в один и тот же мс» = iOS NEPacketTunnelProvider.writePacketObjects дропает IP-пакеты >1500 байт, gVisor эмитит response от сервера как один большой IP packet → TLS handshake виснет на ServerHello+Certificate. Codex consult рекомендовал 1280 как «conservative», но `wiki/rkn-detection-methodology.md §3` помечает MTU 1..1499 как RKN VPN-detection trigger → выбран 1500 как safe upper-bound (не jumbo + не triggering detection). NE settings.mtu должен совпадать с этим значением. |
| `sniff` | `true` | Нужен для domain-based route rules (`geosite:.com` или `domain_suffix:`). |

**Архитектурное правило**: bundled template (`SingBoxConfigTemplate.vless-reality.json`) **не** содержит inbounds. TUN inbound добавляется только на runtime в extension (`expandConfigForTunnel`). Это сохраняет принцип «минимальная shipped attack surface» и оставляет place для будущих impl'ов другого PacketTunnel inbound (напр. WireGuard runtime injection в Phase 7).

**Файлы**:
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift` — white-list validate (`allowedInboundTypes = {tun, direct}`) + `expandConfigForTunnel`.
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` — `validate` → `expandConfigForTunnel` → `validate` (defense-in-depth) → `startOrReloadService`.
- `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift` — 11 assertions: 2 для allowed (tun, direct), 4 для rejected (socks/http/mixed + unknown white-list miss), 2 для no-type + malformed, 5 для expand (idempotent, rewrites DNS, preserves fields, output passes re-validate × 2 inputs).

**Что становится TODO**: на Phase 7 при добавлении WireGuard inbound — параметризовать `expandConfigForTunnel` для разных типов inbound (передавать enum), не дублировать метод.

---

### R11. Phase 1 security audit — 37/37 threats closed [решено 2026-05-11]

**Контекст**: `/gsd-secure-phase 1` запустил retroactive аудит мита́ций для 37 трэтов, объявленных в `<threat_model>` блоках W0–W5 PLAN.md. Из них 9 — accepted risks (документированы в PLAN), 28 — mitigate, которые нужно было verify в коде.

**Решение**: 27 мита́ций verified в импле; одна (T-01-W5-02) оказалась open и закрыта в том же audit-цикле (см. ниже).

**Закрытые controls по группам**:

| Группа | Threats | Точка контроля | Evidence |
|--------|---------|----------------|----------|
| R1 — no listen-on-localhost | W1-01..04, W3-01..02, W4-08, W5-03 | `SingBoxConfigLoader.swift:53-72` default-deny white-list `{tun, direct}`; runtime validate в `BaseSingBoxTunnel.swift:94-100` ДО `LibboxNewCommandServer`; post-expand re-validation `:170-176` | UAT T1+T2+T4 PASS; commit 74605f8/9aa3e93 |
| R6 — no IFF_POINTOPOINT (code side) | W2-01..02, W3-03 | `TunnelSettings.swift:42-61` — единственный builder NEPacketTunnelNetworkSettings; `destinationAddresses` никогда не присваивается; `validate-r1-r6.sh` R6 grep PASS | UAT T5 SKIPPED (Apple unconditionally sets flag на iOS 26 — accepted via commit 74605f8) |
| KILL-01/02 | W2-03..04, W4-05..06 | `KillSwitch.swift:19` — `includeAllNetworks = true`; `ConfigImporter.swift:165` — единственная wiring точка; `TunnelController.swift:25-37` — 30s timeout | UAT T3 PASS |
| SEC-03 — SocksProbe isolation | W1-05..06 | `BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbe-iOS.entitlements` пустой dict; `SocksProbe-macOS.entitlements` только `app-sandbox` + `network.client`; bundle ID `app.bbtb.tools.socksprobe.*` отдельный namespace | UAT T4 — SocksProbe сам по себе detected localhost услуги других процессов (AdGuard / iCloud Private Relay), но НЕ принадлежащие BBTB extension |
| SEC-05 — Keychain | W4-03 | `KeychainStore.swift:42` — `kSecAttrAccessibleWhenUnlocked`; access-group computed from team prefix | `validate-r1-r6.sh` SEC-05 PASS |
| OSLog privacy | W3-07, W4-02 | `TunnelLogger.swift:7-12` — secret поля никогда не передаются логгеру; библиотечные сообщения помечены `privacy: .public` только для non-secret payload (basePath, libbox status) | UAT T6 PASS (Release-mode — нет debug entries) |
| Crash reporter | W3-06 | `CrashReporter.swift:15` — `MXMetricManagerSubscriber`; install в `BBTB_iOSApp.swift:18` + `BBTB_macOSApp.swift:18`; payload пишется в App Group, без upload (Phase 12 управляет отправкой) | — |

**Accepted risks** (9 штук, не реактуализируются в будущих аудитах):

1. W0-03 — Bundle ID mismatch ловится W0-T1 checkpoint + W0-T5 build failure
2. W2-05 — iOS 16.1+ Apple traffic leak (системное ограничение через `includeAllNetworks=true`) — текст в `.planning/phases/01-foundation/01-RESEARCH.md:277,982`; **TODO Phase 11**: promote в `wiki/security-gaps.md` отдельной страницей FAQ
3. W3-04 — App Group container compromise (iOS sandbox защищает между bundles, внутри team — OK)
4. W3-05 — libbox.xcframework supply-chain (Phase 12 добавит codesign verification в CI)
5. W4-04 — remarks-based социалка (UX decision: пользователь сам копировал URI)
6. W4-07 — iOS pasteboard banner (Phase 11 заменит на UIPasteControl)
7. W5-01 — crash payload stack-trace exposure (Apple обрабатывает; UI send deferred Phase 12)
8. W5-05 — manual smoke screenshot spoofing (solo developer trust)
9. W5-06 — api.ipify.org screenshots показывают server IP (publicly known)

**Remediated в audit cycle**:

**T-01-W5-02 — `.gitignore` repo-root build artifacts** [closed 2026-05-11 в audit, commit 5b897a5]

Контекст: PLAN.md W5 утверждал «`BBTB/.gitignore` уже исключает `build/`». В реальности `BBTB/.gitignore:6` scoped только под `BBTB/`-subdirectory, а `archive-ios.sh` после фиксов commit `b253ce1` пишет архив в repo-root (`/Users/vergevsky/ClaudeProjects/VPN/build/`). UAT T7 показал `git status` с `?? build/` (untracked `BBTB-iOS.xcarchive` лежит exposed). Stray `git add .` запушил бы .dSYM с символами + `.xcarchive` структуру.

Решение: добавлено в root `.gitignore`:

```gitignore
# Build artifacts (Phase 1 SEC T-01-W5-02 — root-scope archive output)
build/
*.xcarchive
*.dSYM
*.ipa
```

Verify: `git check-ignore -v build/BBTB-iOS.xcarchive` → matches `.gitignore:7:build/`. `git status` чист.

**Архитектурное правило**: archive scripts пишут в repo-root `build/`, не в `BBTB/build/`. Не менять output path — это просто значит, что root `.gitignore` должен покрывать build artifacts (а не BBTB/`.gitignore`).

**Что становится TODO**:

1. **Phase 12 (Pre-release)**: refresh аудит — W3-05 (libbox supply-chain) переходит из accept в mitigate (codesign verification в CI); W5-01 (crash payload) переходит в mitigate (UI отправки крашей с user consent — TELEM-03/04).
2. **Phase 11 FAQ**: promote W2-05 (iOS 16.1+ Apple leak) doc → отдельная wiki-страница либо новая секция в `wiki/security-gaps.md` (текст уже в `.planning/phases/01-foundation/01-RESEARCH.md:277,982`).

**Файлы**:

- `.planning/phases/01-foundation/01-SECURITY.md` — полный audit report со ссылками на каждую evidence-line
- `/Users/vergevsky/ClaudeProjects/VPN/.gitignore:7-10` — root build artifacts ignore
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift` — R1 контролы
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift` — R6-safe builder
- `BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift` — KILL-01/02 единственная точка
- `BBTB/scripts/validate-r1-r6.sh` — static invariants gate

---

### R12. Trojan-WS ALPN — h2 несовместим с WebSocket upgrade [решено 2026-05-12, Phase 2 UAT T5]

**Контекст**: При импорте Trojan-WS URI с дефолтным ALPN `["h2", "http/1.1"]` (параметр `alpn=` не задан) TLS handshake negotiates h2 — сервер отвечает `ALPN: h2` (подтверждено `openssl s_client`). sing-box отправляет HTTP/1.1 WebSocket upgrade request, но сервер ожидает h2 framing → framing mismatch → соединение закрывается или таймаутится через 15 секунд (`read tcp ... i/o timeout`). VLESS+Reality этим не затронут (Reality строит собственный handshake поверх TLS).

Обнаружено в UAT T5: sing-box.log показывал `i/o timeout` на всех Trojan соединениях, в то время как `nc` и `openssl s_client` подтверждали доступность сервера.

**Решение**: Для WS-транспорта фильтровать `h2` из ALPN; если после фильтрации пусто — `["http/1.1"]`.

**Файлы**:
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` — `buildTrojanOutbound` фильтрует h2 при `case .ws` (commit `4255a77`)
- `BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-ws.json` — `alpn: ["http/1.1"]`
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderTests.swift` — regression-тесты `test_trojanWS_alpnExcludesH2` + `test_trojanTCP_alpnPreserved`

**Архитектурное правило**: WS transport = HTTP/1.1 upgrade. ALPN для WS-outbound никогда не должен включать `h2`.

---

### R13. NETunnelNetworkSettings.tunnelRemoteAddress — только валидный IP/hostname [решено 2026-05-12, Phase 2 UAT T5]

**Контекст**: `NETunnelProviderProtocol.serverAddress` прокидывается iOS в `NEPacketTunnelNetworkSettings(tunnelRemoteAddress:)` через цепочку `BaseSingBoxTunnel.startTunnel → ExtensionPlatformInterface(serverAddressHint:) → TunnelSettings.makeR6Safe`. iOS отвергает произвольные строки (например `"BBTB"`) — extension падает на `openTun` с ошибкой `Invalid NETunnelNetworkSettings tunnelRemoteAddress`, sing-box engine не стартует, лог остаётся пустым.

Обнаружено в UAT T5: Phase 2 W3 rewrite заменил `server.host` на literal `"BBTB"` как display-метку, не осознав роль поля.

**Решение**: Использовать `host` первого supported outbound из пула как `serverAddress`. Для display (заголовок VPN в iOS Settings) — `manager.localizedDescription`.

**Файлы**:
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — `provisionTunnelProfile(configJSON:serverHost:)`, `proto.serverAddress = serverHost` (commit `39356a4`)

**Архитектурное правило**: `proto.serverAddress` = IP/hostname. Никаких пользовательских меток, enum-имён или произвольных строк.

---

### R14. Phase 2 security audit — 13/13 threats, 0 BLOCKER [решено 2026-05-12]

**Контекст**: Retroactive security audit Phase 2 (gsd-security-auditor, Opus 4.7).

**Результат**: 11 COVERED · 1 PARTIAL (T-02-04 rawURI → зафикшен в `ConfigImporter.swift:285-288`, `rawURI: nil` для supported рядов) · 1 ACCEPT (T-02-03 audit log → Phase 12). 0 BLOCKER. Phase 1 carry-forward invariants (R1/R6/R10/R11/KILL-01/02/SEC-03/05): 0 regressions.

**Открытые carry-forward**:
- W-02-09 — fetcher body-size limit / redirect cap → Phase 7 (вместе с cert pinning DPI-08)
- W-02-10 — macOS `com.apple.security.network.server = true` orphan entitlement → Phase 10 (macOS hardening pass)

**Файл**: `.planning/phases/02-trojan-import-flow/02-SECURITY.md`

---

## Принцип ведения

- Активные вопросы — нет резолюции, ждут решения
- Закрытые — резолюция принята с обоснованием. Не удаляем — оставляем для аудита
- Прошлые сомнения по тому же вопросу — оставляем в истории резолюции

## Related pages

- [[xray-localhost-vulnerability]]
- [[rkn-detection-methodology]]
- [[rkn-methodology-document]]
- [[apple-detection-surface]]
- [[geoip-detection]]
- [[snitch-rtt-detection]]
- [[false-positives]]
- [[vpn-detection-by-apps]]
- [[max-messenger]]
- [[kill-switch]]
- [[licensing]]
- [[rules-engine]]
