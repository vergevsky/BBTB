---
name: Открытые вопросы безопасности
description: Список архитектурных развилок — активные, закрытые с резолюцией и отложенные на будущее
type: project
---

# Открытые вопросы безопасности

**Summary**: Аккумулятор архитектурных развилок и тем, требующих обсуждения. Содержит три раздела — активные вопросы, закрытые/принятые решения и отложенные TODO. Резолюции принимаются явным решением, фиксируются с обоснованием.

**Sources**: Дыры в безопасности, которые нужно обсудить.md, VPN-клиент для macOS и iOS — Промт для Claude Code.md, ocr_methodika_vpn_proxy.md

**Last updated**: 2026-05-15 (Phase 10 closure — R21-R24 added: cert pinning, STUN block, enforceRoutes, CDN fronting)

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

**Файлы** _(Phase 7c, 2026-05-14: sing-box-specific files relocated to `SingBox/` namespace per HYBRID engine boundary cleanup)_:
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` — white-list validate (`allowedInboundTypes = {tun, direct}`) + `expandConfigForTunnel`.
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/BaseSingBoxTunnel.swift` — `validate` → `expandConfigForTunnel` → `validate` (defense-in-depth) → `startOrReloadService`.
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
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` — R1 контролы _(Phase 7c relocated to SingBox/ namespace)_
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

### R15. Phase 3 security — T-03-01/T-03-06/T-03-07/T-03-08/T-03-09 [решено 2026-05-12]

**Контекст**: Phase 3 (server-management) вводит HTTP-fetching subscription URL, новую `@Model Subscription`, TCP-пробы, cascade delete, SwiftData migration.

**Результат**: 5 угроз закрыты.

| Угроза | Решение |
|--------|---------|
| T-03-01: Subscription name injection (control chars / oversized name) | `ConfigImporter.sanitizeSubscriptionName()` — strip `\n\r\t`, clamp 100 chars |
| T-03-06: Subscription URL SSRF | `SubscriptionURLFetcher.isBlockedHost()` — blocklist loopback (`127.x`, `::1`), link-local (`169.254.x`, `fe80:`), RFC-1918 (`10.x`, `172.16-31.x`, `192.168.x`), multicast (`224-239.x`, `240-255.x`), ULA (`fc/fd:`). HTTPS-only scheme enforced. |
| T-03-07: TCP SYN probes ТСПУ-risk | TCP SYN к port 443 неотличим от HTTPS — риск минимален; accepted |
| T-03-08: Cascade delete data loss | `@Relationship(deleteRule: .cascade)` — корректное поведение: удаление Subscription удаляет только её ServerConfig |
| T-03-09: SwiftData migration idempotency | `migratePhase2ToPhase3()` guarded via `UserDefaults app.bbtb.phase3.migrationDone` |

**CR-01 / CR-04 (code review)**: `ConfigImporter.provisionTunnelProfile` — strict `selectedID` guard; детерминистичный `isActive` reset (sort by `id.uuidString`). Устраняют нарушение D-09 и UI-рассинхрон.

**Принятые risks (accepted)**:
- T-G1-05: DNS-rebinding — `isBlockedHost()` работает на hostname-string, не резолвит DNS; атакующий с контролем DNS может обойти. Mitigated in Phase 7 DPI-08 (cert pinning + safe DNS resolver callback).

**Открытые carry-forward**:
- WR-01..WR-11 (code review warnings) → Phase 4 (WR-01/05/07) / Phase 7 (WR-02/11) / Phase 11 (WR-03/04/06/08/09/10)

**Файл**: `.planning/phases/03-server-management/03-REVIEW.md`, `03-VERIFICATION.md`

### R16. Phase 3 Plan 05 threats — T-03-23..T-03-27 [закрыто 2026-05-12]

Угрозы из Plan 05 (reconnect flow, server selection, JSON boundary).

| ID | STRIDE | Описание | Резолюция |
|----|--------|----------|-----------|
| T-03-23 | T | `UserDefaults selectedServerID` не валидируется на существование в ModelContainer — при удалении сервера приложение пытается connect к несуществующему server | Mitigate: `MainScreenViewModel.reconcileSelectionWithStore()` в refresh()/onAppear; `provisionTunnelProfile(for:)` gracefully fallback на full pool если selectedID не найден. |
| T-03-24 | I | Pre-connect probe ВСЕХ supported серверов раскрывает client IP серверам, к которым пользователь не будет подключаться | Accept: TCP SYN к 443 неотличим от HTTPS; скрытие IP требует proxy-pre-tunnel (Tor-style) — out of scope. |
| T-03-25 | D | Reconnect race: быстрые тапы по разным серверам → несколько disconnect/connect sequence конкурируют | Mitigate: в начале reconnect Task `if case .connecting = state { return }` — новые selection игнорируются до завершения текущего. UAT T6 PASS 2026-05-12. |
| T-03-26 | T | `.connecting` state stuck если `provisionTunnelProfile` throws mid-flow | Mitigate: `catch` в `performToggleImpl` и reconnect Task всегда устанавливает `state = .error(message:)`. |
| T-03-27 | E | NETunnelProviderManager updates `providerConfiguration["configJSON"]` — если ConfigImporter path инжектит malformed JSON, extension может крашнуться | Mitigate: Phase 1 SEC-06 carry-forward — ConfigImporter валидирует схему до persist. Plan 05 не добавляет новой parsing surface. |

### R17. Phase 6 — DNS-стратегия + Yandex eradication + IPv6 blackhole + auto-reconnect + failover [реализовано 2026-05-13, частично superseded by R18 + Phase 6d UAT]

**Контекст**: Phase 6 (network resilience) закрывает требования NET-01..11 и устраняет хардкод Yandex DNS `77.88.8.8`, который ранее присутствовал в шаблонах sing-box и противоречил R1 (default-deny / минимум доверия к российской инфраструктуре).

**Принятые решения (D-01..D-08)**:
- **D-01 bootstrap DNS** — `ConfigImporter.buildDNSConfig(for:)` выбирает `tcp://<server-IP>` если первый parsed config имеет IPv4 host; иначе fallback `tcp://94.140.14.14` (AdGuard). Pitfall 5 (chicken-and-egg при hostname-only): hostname сначала надо резолвить — отсюда fallback. Yandex `77.88.8.8` полностью искоренён из shipping code: `grep -RIn "77.88.8.8" Packages/ | grep -v .build/ | grep -v Tests/` = 0.
- **D-02 tunnel DNS default** — Cloudflare DoH (`https://1.1.1.1/dns-query`).
- **D-03 priority** — non-empty validated `customDNS` overrides; AdBlock toggle ignored when custom set.
- **D-04 AdBlock toggle** — `customDNS` empty + `adBlockEnabled == true` → AdGuard (`94.140.14.14`/`94.140.15.15`).
- **D-05 IPv6 blackhole** — `NEIPv6Settings(addresses: ["fd00::1"], …)` + sing-box TUN inbound `inet6_address: "fd00::/8"` для inbound TUN, но БЕЗ NEIPv6Settings.includedRoutes (R6 invariant preserved — никаких destinationAddresses).
- **D-07 retry policy** — _(superseded by R18 — `ReconnectStateMachine` actor удалён в Phase 6c. Retry-policy теперь handled Apple's on-demand evaluator.)_ Original Phase 6 implementation: 3 attempts × 2/4/8 s exp backoff через `ReconnectStateMachine` actor; на исчерпании → `.allFailed` → `notifyReconnectFailed`.
- **D-08 failover** — `SwiftDataFailoverProvider` actor: round-robin cursor по `isSupported == true` server-ам, sorted by `id.uuidString`; cursor seeded at currently-selected server; full circle → nil → `.allFailed`; single-server pool → `notifySingleServerUnavailable` + nil; reset triggers: manual disconnect ИЛИ 30s+ stable `.connected` (с `startedAt` race guard).
- **D-12 carry-forward** — fetch-all + Swift filter (НЕ `#Predicate` с UUID lookups) сохранён в failover hot path; см. R15 + memory `feedback_swiftdata_uuid_predicate.md`.

**Реализация (6 waves)**:
1. **Wave 1 (06-01)** — `DNSConfig` + `AdvancedSettingsStore` (`@AppStorage`).
2. **Wave 2 (06-02)** — `PoolBuilder.buildSingBoxJSON(dns:)` API + 6 sing-box JSON templates: Yandex → AdGuard.
3. **Wave 3 (06-03)** — Settings → Advanced DNS UI с validation (IPv4 / hostname / DoH URL).
4. **Wave 4 (06-04)** — _(superseded by R18 — обе actor удалены в Phase 6c.)_ `NetworkReachability` + `ReconnectStateMachine` actors.
5. **Wave 5 (06-05)** — `TunnelController` promoted to `actor`; NEVPNStatusDidChange + (macOS) `NSWorkspace.didWakeNotification` observers; reconnect banner; on-demand `UNUserNotificationCenter` permission; manual-disconnect race (Pitfall 3); foreground hook (Pitfall 8). _(NetworkReachability observer removed in R18.)_
6. **Wave 6 (06-06)** — `SwiftDataFailoverProvider`; manual-disconnect resets cursor; 30s stable-session reset (Pitfall 4); single-server notification; two-phase init pattern для VM↔Controller cycle (`[weak tunnel]` connect closure).

**Тесты**: AppFeatures 120/120 PASS (FailoverProviderTests 11/11 + TunnelControllerStateTests 11/11 + DNS/banner/observer tests). VPNCore 57/57, ConfigParser 210/210, PacketTunnelKit 61/61, Localization 3/3. iOS + macOS Xcode builds green.

**R1/R6/R10 invariants** — все сохранены: R1 (default-deny outbound whitelist) не затронут; R6 (no destinationAddresses) — `grep -n "destinationAddresses" PacketTunnelKit/.../TunnelSettings.swift | grep -v '//' | wc -l` = 0; R10 (TUN inbound expansion + DNS-hijack) — `SingBoxConfigLoader.expandConfigForTunnel` не изменён.

**UAT** — субсумирован: Wi-Fi ↔ LTE / sleep wake / failover / manual disconnect race re-validated в R18 (Phase 6c re-UAT 2026-05-13) и Phase 6d regression smoke (2026-05-14, см. R19). DNS leak / IPv6 leak / single-server notification / R1+R6 regression — отдельные smoke checks могут потребоваться перед TestFlight (Phase 12); см. `.planning/phases/06-network-resilience/06-06-PLAN.md` Task 3.

**Carry-forwards в Phase 7**:
- LibboxCommandClient stall detection (RESEARCH §6) — опциональный hook для silent-stall failure modes.
- Per-server health signal — failover сейчас считает любой `.allFailed` cycle failure-ом; anti-DPI work в Phase 7 может потребовать finer-grained per-protocol probe history.

### R18. Phase 6c — Apple's NEOnDemandRule auto-reconnect (sliding session window) [решено 2026-05-13, re-UAT PASS]

**Контекст**: Phase 6 UAT на iPhone iOS 26.5 выявил 4 класса багов в custom auto-reconnect machinery (ReconnectStateMachine + NEVPNStatusDidChange recovery + NetworkReachability):
1. Phantom reconnect на fresh install (NEVPNStatusDidChange приходит после `saveToPreferences` → recovery видит .satisfied network + intent stub → запускает connect до явного тапа).
2. **EXC_RESOURCE / PORT_SPACE crash на iOS 26** под network churn — observer делал XPC `loadAllFromPreferences` в каждой из 40+/s notifications → Mach port exhaustion.
3. **Fight-back с другими VPN-приложениями** — при takeover'е другого VPN наш recovery path запускал reconnect, отбирая route.
4. Phantom reconnect на iOS Settings → VPN → toggle off (тот же recovery path).

**Решение R18 (заменяет автореконнект-часть R17)**: переход на iOS-нативный `manager.isOnDemandEnabled = true` + `[NEOnDemandRuleConnect(interfaceTypeMatch: .any)]`. Apple's on-demand evaluator владеет реконнектом через network changes / sleep-wake / короткие drops. Custom machinery полностью удалена. Mid-session failover (D-08/D-09 из Phase 6) сохранён через новый `TunnelWatchdog` actor.

**Sliding session window invariant** — главное архитектурное решение Phase 6c:
```
manager.isOnDemandEnabled = autoReconnectToggle && userIntendedConnected
```
On-demand активен **только между** явным BBTB Connect и любым session-closing событием (явный Disconnect, iOS Settings off, takeover другим VPN). Гейт реализован в `OnDemandRulesBuilder.applyCurrentState(to:)` — единственный entry point для записи on-demand state.

**Принятые решения (D-01..D-22 + Round 5 architect additions)**:
- **D-08/D-09 (failover preserved)** — `SwiftDataFailoverProvider` неизменён; mid-session failover теперь через `TunnelWatchdog` actor с 3s debounce + .reasserting cancellation (W-05).
- **D-10/D-14/D-15 (cleanup)** — `ReconnectStateMachine.swift` + `NetworkReachability.swift` + 3 тест-файла удалены; TunnelController.swift slim 909 → 316 строк.
- **D-11/D-12/D-13 (macOS wake)** — `NSWorkspace.didWakeNotification` observer сохранён; idempotent `startVPNTunnel()` nudge с 3 guards (W-06): `manager.isEnabled` + `isOnDemandEnabled` + `loadAutoReconnectEnabled`.
- **D-17 (NEVPNStatusDidChange narrow)** — observer остаётся только для (a) watchdog dispatch + (b) intent-closing on external disconnect. Никаких recovery branches.
- **D-17b/c (migration safety)** — `OnDemandMigrationTask.runIfNeeded()` мигрирует existing Phase 6 managers на on-demand при первом запуске Phase 6c build (idempotent, with B-05 transient-failure guard).
- **Round 5 architect — intent-closing on external `.disconnected`**: когда `manager.isEnabled == false` после external `.disconnected` (Settings-disable ИЛИ другой VPN takeover), `userIntendedConnected = false` (persisted); BBTB остаётся выключен до явного Connect tap. Замещает Round 4 fight-back patch + UI desync patch одной семантикой.
- **Round 5 architect — reactive UI driver**: `MainScreenViewModel.applyVPNStatus(_:)` — sole authority для main `state` + `reconnectBannerState` на NEVPNStatus events. `connect()`/`disconnect()` — command methods (request transitions, set `.error` on throw, не выставляют `.connected(since:)` изнутри).
- **B-03 (cachedManager fix)** — broken `lastKnownStatus != .invalid` proxy заменён на real `cachedManager?.isEnabled` gate; populated в startReachability + refreshed через `.bbtbProvisionerDidSave` observer.
- **B-04 wiring complement** — `connect()`/`disconnect()` после setUserIntent вызывают `applyCurrentStateToCachedManager` — `isOnDemandEnabled` flip немедленно (не на следующий provisioner save).

**Реализация (5 plans)**:
1. **Plan 06C-01** ✓ — `OnDemandRulesBuilder` (4 публичных метода + 11 тестов; AppFeatures 138/138).
2. **Plan 06C-02** ✓ — `ManagerSelector.ourManagers` + `DefaultTunnelProvisioner.provisionTunnelProfile` пишет `applyCurrentState` + posts `.bbtbProvisionerDidSave` (+7 тестов; AppFeatures 145/145).
3. **Plan 06C-03** ✓ — Settings toggle (D-04..D-07) + `ReconnectClock` extract (B-01) + `TestClocks` extract (B-02) + `OnDemandMigrationTask` (+18 тестов; AppFeatures 163/163).
4. **Plan 06C-04** ✓ Cutover — Task 1 wiring + UAT Round 1 partial + Round 4 hotfixes + Round 5 architect-driven Task 3a/3b/3c (AppFeatures **133/133 PASS** — пересчёт после deletes; iOS + macOS xcodebuild SUCCEEDED). См. `06C-04-SUMMARY.md`.
5. **Plan 06C-05** ✓ Closed 2026-05-13 (commit `ce5913d`) — re-UAT pair PASS (F-reverse + Settings-disable + G passive on iPhone iOS 26.5; Round 6 follow-up `44a5630` закрыл Settings-disable UI desync) + `06C-UAT.md` + REQUIREMENTS NET-08..11 → Validated + NET-12 (active liveness probe) backlog row для Phase 7-8.

**Lessons learned (commit history + reviewer rounds)**:
- **Triple-reviewer protocol работает**: gsd-plan-checker + Codex GPT-5.2 + Gemini 2.5 Pro поймали 10 blockers + 8 warnings в Round 1 ревью; единственный revision pass закрыл всё.
- **Parallel-run rollback path is bait**: original Plan 04 держал OLD machinery alive за UAT gate как "rollback safety". UAT discovered the parallel-run hybrid is itself the bug source (Bug A + Bug B). Codex R5 architect диагностировал и pulled cleanup forward.
- **iOS 26 Mach port exhaustion** — любой XPC trip (loadAllFromPreferences и т.п.) в observer callback под network churn → EXC_RESOURCE/PORT_SPACE crash. Правило: status reading только из `notification.object` (synchronous, no XPC); все XPC trips — out-of-band в Task or specific helpers.
- **NEVPNStatusDidChange — НЕ source of truth для UI**. Cached `manager.isEnabled` через `.bbtbProvisionerDidSave` observer + UserDefaults `userIntendedConnected` дают честные gates.

**R1/R6 invariants preserved**: kill switch flags `includeAllNetworks`/`enforceRoutes` неизменны. DNS pipeline неизменён. R10 (TUN inbound expansion) неизменён.

**Crashes verified eliminated (UAT Round 1 + Round 4)**: G scenario (30+ min background, iOS 26.5) → zero EXC_RESOURCE / PORT_SPACE.

**Re-UAT outcome (2026-05-13, iPhone iOS 26.5, Round 6 follow-up `44a5630`)** — все 3 hard-blocker scenarios PASS:
- F-reverse — BBTB → Happ takeover, BBTB stays off ✅.
- Settings-disable — iOS Settings VPN toggle off, BBTB stays off ✅ (после Round 6 `queue: nil` + foreground resync fix).
- G — 30+ min background pass-through, zero EXC_RESOURCE / PORT_SPACE ✅.

NET-08..11 promoted Active → Validated в REQUIREMENTS.md.

### R19. Phase 6d — Performance & Code Quality Audit + Settings-disable invariant укрепление [решено 2026-05-14]

**Контекст**: После Phase 5 пользователь сообщил «приложение тяжело грузится». Triple-AI peer review (Claude Opus 4.7 + Codex GPT-5.2 + Gemini 3.1 Pro) дал 45 findings; Option-B (HIGH + selected MEDIUM) + Variant D (без pre-fix Instruments baseline, accept descriptive comparison) закрыли **19 атомарными commits** + **7 post-fix correctness commits** (cold-start UI freeze block + Settings-disable saga).

**Settings-disable correctness saga (security-relevant)** — finalized via open-source-research-derived solution:

Phase 6c R18 закрыл Settings-disable через `MainScreenViewModel` observer queue=nil + intent-closing path. Однако Phase 6d UAT обнаружил остаточный race: iOS on-demand evaluator после Settings VPN-off мог reactivate тоннель *до* того, как host откроется (BBTB в background) — потому что host's intent-closing path требует foreground для срабатывания.

5 fix-попыток (commits `bc7bc26` → `cff3f46`) сошлись на **3-уровневой обороне**:

1. **Authoritative stop reason bridge** — extension's `stopTunnel(with reason:)` пишет `ExternalVPNStopMarker.mark()` в App Group UserDefaults при `.userInitiated` / `.providerDisabled`. Только extension видит `NEProviderStopReason`; host через NEVPNStatusDidChange — только `.disconnected` без reason. App Group `group.app.bbtb.shared` mostит information cross-process.

2. **Apple-canonical options discriminator** (pattern derived from **WireGuard iOS** `options["activationAttemptId"]`) — `TunnelController.connect()` передаёт `options["manualStart"]: NSNumber(true)` в `startVPNTunnel(options:)`. Extension's `startTunnel(options:)` различает app-initiated (options non-nil + manualStart key) vs OS-driven (options=nil).

3. **Sticky marker** — `ExternalVPNStopMarker.isPending(maxAge: 600)` peek-only (не consume). Original `consume()` имел cross-process race: host и extension оба consume'или → следующий iOS on-demand retry находил пустой marker и поднимал тоннель. Sticky model blocks ВСЕ iOS retry'и в окне 10 минут; clear только при explicit user Connect (host вызывает `clear()` в `connect()`) или auto-expire после 10 минут.

**Файл:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExternalVPNStopMarker.swift` — sticky marker + Apple-canonical options discriminator. **Не переписывать без понимания race semantics.**

**6 architectural decisions DEC-06d-01..06** (полный текст — `wiki/performance-baseline.md`):
1. **DEC-06d-01** — Cold-start init defer pattern (non-critical inits → `Task.detached(priority: .utility)` или `.onAppear`, не в `BBTB_iOSApp.init` body).
2. **DEC-06d-02** — XPC consolidation в TunnelController (≤ 2 trips через `applyCurrentStateToCachedManager()`).
3. **DEC-06d-03** — Event-driven NEVPNStatus polling (AsyncStream вместо sleep loops).
4. **DEC-06d-04** — Bounded probe concurrency (limit 4-8 + cancellation-safe defer cleanup).
5. **DEC-06d-05** — Apple-canonical `options["manualStart"]` + sticky `ExternalVPNStopMarker` App Group marker (см. выше).
6. **DEC-06d-06** — PerfSignposter spans (`ColdLaunch`, `ConnectTap`, `PreConnectProbe`, `ProvisionProfile`, `LibboxStart`) сохранены в production code как standard tooling.

**Verification**: UAT regression smoke на iPhone iOS 26.5 (2026-05-14, commit `cff3f46`) — hard-blockers A, F-direct, F-reverse, G, I, Settings-disable все PASS. 6d-NEW-1 (cold-start ≤ 2 sec) + 6d-NEW-2 (connect-tap responsive) PASS. AppFeatures 133/133. iOS + macOS xcodebuild SUCCEEDED. PERF-01..05 + QUAL-01..03 → Validated.

**Carry-forwards (26 findings + others)**: 6 MEDIUM (M6, M7, M8, M10, M11, M15) + 20 LOW + 3 trivial unused imports → Phase 6e backlog. NET-12 (active liveness probe) → Phase 7-8. macOS-specific UAT replay → Phase 11/12. Numerical Instruments baseline → опциональный single capture (PerfSignposter готов).

**R1/R6/R10/R17/R18 invariants preserved**: kill switch flags неизменны. DNS pipeline неизменён. R10 (TUN inbound expansion) неизменён. R18 (sliding window invariant + intent-closing path) укреплён через `ExternalVPNStopMarker`, не заменён.

**Full closure record**: `.planning/phases/06d-performance-audit/06D-Final-SUMMARY.md`. Long-term wiki record: `wiki/performance-baseline.md`. UAT: `06D-UAT.md`.

---

### R20. Phase 8 — Rules Engine signature trust path [реализовано 2026-05-15]

**Угроза**: Server-distributed rules.json + SRS files мутированы атакующим → клиент применяет вредоносные правила (блокирует легитимный трафик / маршрутизирует sensitive трафик через нужный attacker hop).

**Mitigation**: Ed25519 detached-signature verify via `swift-crypto/CryptoKit` (`Curve25519.Signing.PublicKey.isValidSignature(_:for:)`). Hardcoded 32-byte public key в `PublicKey.swift`. Two-file scheme: `manifest.json` + `manifest.json.sig`; каждый `.srs` + соответствующий `.srs.sig`. Coordinator verifies manifest sig first, then each SRS sig before atomic write.

**Invariants (validate-r1-r6.sh Phase 8 gates):**

| Check | Command | Gate |
|-------|---------|------|
| R8: template no inline rule_set | `! grep -q "rule_set" SingBoxConfigTemplate.vless-reality.json` | R8 |
| R8b: runtime injection via AppGroupContainer | `grep -q "AppGroupContainer" SingBoxConfigLoader.swift` | R8b |
| RULES-02: exactly 32 pubkey bytes | `grep -oE "0x[0-9A-Fa-f]{2}" PublicKey.swift | wc -l = 32` | RULES-02 |
| R12: no placeholder sequential bytes | `! grep -q "0x00, 0x01, 0x02, 0x03" PublicKey.swift` | R12 |
| D-08: no NEAppProxyProvider in main sources | `! grep -rE "NEAppProxyProvider" App/iOSApp App/macOSApp` | D-08 |

**RULES-11 + Phase 8 SC #3 carve-out (D-08/D-09):**
macOS per-app routing через `NEAppProxyProvider` (L4) ↔ sing-box L3 TUN mismatch + `NETunnelProviderManager`/`NEAppProxyProviderManager` mutual exclusivity → defer to v0.10+. `AppProxyExtension-macOS` target удалён из Tuist. Workaround: `never_through_vpn` rule_set (L3 IP-level split-tunnel by domain/CIDR). См. [[appproxy-deferral-2026]].

**Известные limitations:**
- v0.8: hardcoded pubkey не rotatable в runtime; rotation strategy v1.x — dual-key support → migration → drop old (документировано в [[rules-engine]] § Ротация ключей)
- `min_app_version` field может lock-out legitimate users при admin error → accept; mitigation = admin operational care + TestFlight invite revisit
- GeoIP точность зависит от admin data source (MaxMind / ip-api.com) — нет гарантии 100% coverage

**Codex consultations:**
- Thread `019e2841` (Area A — sing-box rule_set architectural review)
- Thread `019e284c` (Area D — AppProxy deferral architectural review)

**Файлы:**
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift` — 32-byte compile-time pubkey
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesSigner.swift` — verify API
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` — runtime rule_set injection
- `BBTB/scripts/validate-r1-r6.sh` — Phase 8 invariant gate (R8, R8b, RULES-02, R12, D-08)

**Cross-references:** [[rules-engine]], [[appproxy-deferral-2026]], R1 invariant (no SOCKS5), R10 invariant (post-expand validate), [[performance-baseline]] DEC-06d-04 (bounded concurrency)

---

### R21. Phase 10 — Cert pinning для subscription URL (DPI-08) [реализовано 2026-05-15]

**Угроза**: MITM атака на subscription URL (`vpn.vergevsky.ru/sub/...`) — attacker подменяет ответ subscription → клиент получает вредоносные VPN конфиги → leak трафика к attacker's server.

**Mitigation**: SPKI SHA-256 pinning через `PinnedSessionDelegate` + `PinStore` с bootstrap pins. Remote signed manifest (`subscription-pins.json`) Ed25519 подписан тем же admin ключом что и `rules.json` (D-12). `validUntil` hard reject — expired manifest отвергается.

**Phase 10 v0.10 статус**: code-validated. **Phase 12 prerequisite**: replace placeholder bytes в `PinStore.BootstrapPins.vpnVergevskyRu` через `scripts/generate-spki-pin.swift` перед TestFlight upload.

**Файлы:**
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/PinStore.swift` — bootstrap SPKI pins
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/PinnedSessionDelegate.swift` — URLSessionDelegate
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionPinManager.swift` — actor, remote manifest

**Cross-references:** [[cert-pinning-spki]], R20 (Rules Engine Ed25519 — same admin key)

---

### R22. Phase 10 — STUN UDP block (WebRTC leak protection) (BIO-04) [реализовано 2026-05-15]

**Угроза**: WebRTC API в браузерных мессенджерах (Google Meet, Zoom web) делает STUN (Session Traversal Utilities for NAT) запросы на UDP 3478/5349 напрямую, bypass'ая VPN tunnel → leak реального IP пользователя.

**Mitigation**: toggle «Блокировать STUN-трафик» в AdvancedSettingsView. При включении — `SingBoxConfigLoader` шаг 6 inject'ит reject rule для UDP 3478/5349 в `route.rules`. Destructive confirm alert при OFF→ON (D-16) — предупреждает что блокировка сломает WebRTC звонки.

**Tradeoff (D-16)**: блокировка WebRTC UDP — side effect. Default = OFF (не блокируем без явного consent). Toggle user opt-in.

**Phase 10 v0.10 статус**: code-validated; manual UAT pending (device smoke test).

**Файлы:**
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` — step 6 STUN inject

**Cross-references:** [[advanced-settings]] § STUN-block, [[anti-dpi-techniques]] § v0.10

---

### R23. Phase 10 — macOS enforceRoutes user opt-out (KILL-04) [реализовано 2026-05-15]

**Угроза (R5)**: на macOS без `enforceRoutes=true` system routing может leak трафик bypass'ая VPN при route table race или при специфичных сетевых конфигурациях (dual-NIC, VPN cascading).

**Mitigation**: `enforceRoutes=true` — default в Phase 1. Phase 10 добавляет macOS-only toggle «Отключить принудительную маршрутизацию» (D-17) — informed degradation. Пользователь может выключить если `enforceRoutes` ломает их network config (редкий edge case).

**D-17 решение**: toggle скрыт на iOS (`#if os(macOS)`). На iOS `enforceRoutes` не нужен — iOS network stack не позволяет routing bypass так же. Live-apply через `SettingsViewModel.applyEnforceRoutesToManager()` без reconnect.

**Phase 10 v0.10 статус**: code-validated; manual UAT pending.

**Файлы:**
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` — `applyEnforceRoutesToManager()`
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformHooks.swift` — reads App Group UserDefaults

**Cross-references:** [[advanced-settings]] § macOS enforceRoutes, R6 (P2P=false invariant)

---

### R24. Phase 10 — CDN fronting architecture (DPI-06) [infrastructure-ready 2026-05-15, activation Phase 11]

**Угроза**: ТСПУ блокирует прямые соединения к VPN серверу по IP (BGP blackhole / DPI signature / SNI block). CDN-фронтинг — mitigation layer, при котором клиент подключается к CDN edge (Cloudflare/Fastly), а не к VPN серверу напрямую.

**Архитектура (D-03..D-07)**: `FrontingEngine` SwiftPM пакет — 3 adapters (Cloudflare/Fastly/Custom), `FrontingConfigApplier` (pure static JSON overlay), `FrontingFailureCache` actor (score+cooldown persistence), `FrontingFallbackChain` actor (sequential cursor w/ pre-advance).

**D-05 blacklist**: Reality/TUIC/Hysteria2/Vision защищены от ошибочного overlay. CDN-фронтинг применяется только к VLESS+TLS/WS и Trojan/WS транспортам.

**Cloudflare classic fronting deferral**: cross-domain fronting (SNI ≠ Host) заблокирован Cloudflare с 2015. «Свой домен» через Cloudflare SaaS — наш подход (см. [[cdn-fronting-architecture-2026]]).

**Phase 10 v0.10 статус**: ⚙️ Infrastructure-ready. `extractFrontingProfile()` возвращает nil — server-side payload не доставляется. **Phase 11 activation**: admin rollout в Marzban (см. [[cdn-fronting-server-handoff]]).

**Файлы:**
- `BBTB/Packages/FrontingEngine/` — 10 source files, 20 unit tests
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — CDN hook в `provisionTunnelProfile`

**Cross-references:** [[cdn-fronting-architecture-2026]], [[cdn-fronting-server-handoff]], [[anti-dpi-techniques]] § CDN-фронтинг

---

### R25. Phase 13 / Plan 05 — SSRF blocklist hardening + DNS-rebinding residual [решено 2026-05-17]

**Контекст**: Re-audit Plan 04 (AUDIT-2.md) обнаружил, что `SubscriptionURLFetcher.isBlockedHost()` использовал prefix-string matching, что пропускало non-canonical IPv6-mapped формы (`::ffff:7f00:1`, `0:0:0:0:0:ffff:127.0.0.1` — оба эквивалентны `127.0.0.1`). Также redirect path не валидировался в Pinned варианте.

**Закрытые контролы (Plan 05 — T-A3'/T-B1'/T-B2'/T-C3'/T-C6'):**

| Контроль | Mitigation |
|---|---|
| **C4'-001 IPv4-mapped IPv6 SSRF bypass** (CRITICAL) | `isBlockedHost()` переписан на `Network.framework` `IPv4Address`/`IPv6Address` — numeric IP parsing. IPv4-mapped IPv6 (`::ffff:0.0.0.0/96`) детектится из 16-байтового представления, не из строки. Recursive check для `::ffff:` суффикса больше не нужен. |
| **C4'-002 PinnedSubscriptionURLFetcher redirect bypass** (HIGH) | `PinnedSessionDelegate` теперь реализует `urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)` через общий `HTTPSRedirectGuard`. До этого custom session обходил redirect-guard ветку shared session. |
| **C4'-003 JSONEndpointFetcher post-buffer DoS** (HIGH) | Replaced `data(for:)` на `bytes(for:)` streaming + Content-Length fast-path + accumulation cap (защита от hostile chunked body OOM). |
| **A4'-004 URI port=0 rejection** (MEDIUM) | Все 5 URI парсеров (VLESS/Trojan/Shadowsocks/TUIC/Hysteria2) теперь валидируют `(1...65535).contains(port)`. До: `port = 0` пропускался → sing-box auto-assign random ephemeral port → broken determinism. |
| **A4'-005 outbound tag DoS cap** (MEDIUM) | `parseSingBoxJSON` ограничивает `outbound.tag` 256 chars. Hostile manifest mб с 4 МБ tag → sub-cap log spam DoS. |
| **C1'-001 / A1'-006 route.rules outbound ref leak** (CRITICAL/HIGH) | `SingBoxConfigLoader.validate` теперь проверяет `route.rules[].outbound` и `route.final` против `outbounds[].tag` (plus reserved `dns-out`). До: typo (`outbound: "drect"`) тихо проваливался в sing-box default outbound → localhost/RFC1918/TSPU-DNS leak через proxy. |

**Принятый residual risk (T-G1-05 carry-forward):**

DNS-rebinding атака против `SubscriptionURLFetcher` остаётся: `isBlockedHost()` проверяет hostname **строкой** (или IP literal численно), но **не резолвит DNS**. Атакующий с контролем DNS:

1. Клиент запрашивает `evil.example.com` — DNS вернёт `1.1.1.1` (публичный IP, blocklist пропустит).
2. URLSession делает TCP connect к `1.1.1.1` (legitimate).
3. После TLS handshake, на следующий redirect / TTL=0 поворот, DNS возвращает `127.0.0.1` — клиент конектится к loopback **в обход guard**, т.к. hostname остался `evil.example.com`.

**Mitigation layers (defence-in-depth, ни один не идеален):**

1. **HTTPS+TLS pinning** — connection к `127.0.0.1` не пройдёт TLS handshake без cert match → fail. (`PinnedSessionDelegate` уже реализует это для subscriptions.)
2. **Redirect guard** — `HTTPSRedirectGuard.willPerformHTTPRedirection` валидирует destination host **строкой** при redirect. Не помогает против повторного DNS resolve по тому же hostname (атака на DNS TTL).
3. **Post-connection IP check** (NOT IMPLEMENTED) — `URLSessionTaskMetrics.remoteAddress` доступен post-completion. Можно проверить numeric IP против blocklist и отвергнуть response, если remote был loopback/private. Trade-off: extra metric collection overhead, late detection (после некоторых side-effects), не покрывает streaming case.

**Решение:** **Accepted residual risk** для Plan 05.

- Production subscription URLs всегда HTTPS (https://example.com/sub) → требуют валидный cert от CA. Атакующий не может выдать cert для loopback без compromising CA.
- Subscription flow rare (manual user action; not automated polling без user setup) → attack window narrow.
- Add post-connection check как **enhancement в v1.1+** если будем integrate'ить URLSession metrics для diagnostics anyway.

**Что становится TODO (v1.1+):**

- [ ] `URLSessionTaskMetrics.remoteAddress` post-check для defence-in-depth (low priority — TLS pinning уже primary mitigation).
- [ ] Документировать в README: «subscription URL должен быть HTTPS; HTTP не поддерживается by design».

**Файлы изменены (commits 1883035 + 515f8dc + 6244b8b + f909b5b):**
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift`
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/PinnedSessionDelegate.swift`
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/JSONEndpointFetcher.swift`
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/{VLESS,Trojan,Shadowsocks,TUIC,Hysteria2}URIParser.swift`
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift`

**Cross-references:** [[dns-rebinding-mitigation]] (детальный разбор), R15 (Phase 3 — original isBlockedHost), R21 (Phase 10 — DPI-08 cert pinning).

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
- [[auto-reconnect]] — R18 sliding-window invariant
- [[performance-baseline]] — R19 + DEC-06d-01..06 Phase 6d patterns
- [[rules-engine]]
