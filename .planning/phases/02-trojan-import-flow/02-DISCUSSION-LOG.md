# Phase 2: Trojan + Import flow — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents. Decisions are captured in `02-CONTEXT.md` — this log preserves the alternatives considered and the path that led to each decision.

**Date:** 2026-05-11
**Phase:** 2-trojan-import-flow
**Workflow:** `/gsd-discuss-phase 2` (default mode, interactive)
**Areas discussed:** Auto-fallback / Import foundation, UI entry для трёх способов импорта, KILL-03 — toggle и Settings page, Trojan URI schema (Claude-defaults)

---

## Auto-fallback / Import foundation

### Q1.1 PROTO-10 — где живёт логика авто-переключения VLESS+Reality → Trojan?

| Option | Description | Selected |
|---|---|---|
| sing-box `urltest` outbound | Один configJSON с двумя outbound'ами + третий `urltest` selector, sing-box сам гоняет HTTP-пробы и переключает. Покрывает «молчаливый ТСПУ». Стандартная практика Hiddify/Leadaxe. | ✓ |
| Два NETunnelProviderManager profiles | Два отдельных VPN-профиля, Swift-watchdog следит за статусом и переключает. Прозрачно в UI, но 4-8 сек пауза на свитче, два разрешения iOS при импорте, нужна отдельная HTTP-проба против «молчаливого ТСПУ». | |
| Один профиль, перезаписываем configJSON | Один VPN-профиль, при failure перезаписываем `providerConfiguration` и поднимаем заново. Та же пауза. Не ясно, спросит ли iOS повторное разрешение. | |
| Пусть Claude выберет | Claude-default. | |

**User's choice:** sing-box `urltest` outbound.

**Notes:** Перед этим вопросом пользователь попросил детальное объяснение варианта «два VPN-профиля» в плане для не-программиста. Раскрыли разницу между «резкая блокировка TCP-reject» и «молчаливый ТСПУ» (TLS-handshake passed, traffic mangled). Объяснили что `urltest` в sing-box умеет HTTP-пробу через каждый outbound и проверяет не только TCP-connect но и end-to-end response — это покрывает «молчаливый ТСПУ» встроенным механизмом, в Swift-варианте пришлось бы это писать с нуля.

---

### Q1.2 Откуда берётся пара/пул протоколов (изначальная формулировка) → как разрешаем конфликт между реальными форматами ссылок и исходным распределением фаз

**Поворотный момент дискуссии.** Пользователь показал три реальных формата раздачи ссылок:
1. Subscription URL (`https://vpn.vergevsky.ru/sub/<token>`).
2. Multi-line plain-text с 6 разными серверами (4 VLESS+Reality, 2 Trojan-over-WS-TLS).
3. JSON endpoint (`https://1.2.3.4:port/json/...`).

И спросил: «Разве Leadaxe/singbox-launcher не для этого предназначен? Прям со всеми протоколами. Чтобы сразу покрыть все возможные потребности на будущее.»

Это вскрыло, что исходное понимание PROTO-10 как «пара VLESS+Trojan одного сервера» было неверным — фактически PROTO-10 это **переключение между всеми outbound'ами всего загруженного пула**. И это противоречит исходному ROADMAP'у (IMP-04/05 — Phase 4, SRV-* — Phase 3, TRANSP-03 — Phase 5).

Объяснили: Leadaxe нельзя «вендорнуть как есть» в наш Swift-стек по трём причинам — язык (JS/Node), архитектура (CLI-file-output vs in-memory Swift), лицензия (GPL-совместимая, конфликт с AGPL-ядро+closed-GUI). НО можно использовать как **спецификацию форматов и edge cases**, и портировать concepts в Swift по нашей архитектуре.

| Option | Description | Selected |
|---|---|---|
| Подход A — парсер всё ест | В v0.2 поддерживаем все 3 формата (subscription URL + multi-URI + JSON endpoint). Trojan-WS — да. SwiftData массив. UI «активный». ROADMAP пересборка: IMP-04/05/TRANSP-03 (ws) + SRV-* foundation переезжают в Phase 2. | ✓ |
| Подход C — multi-URI да, subscription/JSON нет | Multi-line URI через буфер/QR/файл, subscription URL и JSON отложены. Минимум работоспособности, но «вот ссылка на обновляемый sub» — нет до Phase 3. | |
| Подход B — жёсткий ROADMAP | Один URI за раз, без subscription/multi/JSON/ws. Пользователь не сможет тестировать v0.2 на своей реальной инфре. | |
| Свой вариант | Предложить разбиение по фазам словами. | |

**User's choice:** Подход A + Leadaxe как спецификация-референс (не вендоринг).

**Notes:** Это самое значимое решение фазы — Phase 2 scope расширяется и затрагивает IMP-04, IMP-05, TRANSP-03 (partial), SRV-* (foundation). REQUIREMENTS.md и ROADMAP.md потребуют синхронизации.

---

### Q1.3 Импорт subscription с unsupported протоколами — как ведём?

| Option | Description | Selected |
|---|---|---|
| Graceful skip + инфо | Парсятся в SwiftData с флагом `isSupported=false`. В urltest не попадают. UI: «X рабочих, Y будут включены». При добавлении handler в Phase 4/7 — флаг снимается автоматически. | ✓ |
| Skip без упоминания | Импортируем supported, про остальные молчим. Пользователь будет недоумевать «где 7-й сервер». | |
| Reject весь импорт | Если хотя бы один протокол не поддержан — отказ. «Требуется BBTB v0.4». Не позволяет делиться смешанной подпиской. | |
| Hybrid: видимая секция «Недоступны» | Аналогично A, плюс отдельная greyed-out секция в UI. На v0.2 UI минимален — это Phase 3 ревизия. | |

**User's choice:** Graceful skip + инфо.

---

## UI entry для трёх способов импорта

### Q2.1 Где живёт вход в импорт на v0.2?

**Ход дискуссии:** изначально предложил empty-state с 4 кнопками / один-button-with-sheet / top-bar-«+»-с-нуля. Пользователь дал точное описание: «Справа сверху всегда есть плюсик. При нажатии стандартное iOS-меню. В нём: Добавить из буфера, Сканировать QR (при необходимости в будущем дополним). В пустом состоянии плюсик тоже справа сверху, посередине область "Список конфигураций пуст" и две кнопки.» Плюс приложил два скриншота v2raytune.

**User's choice:** Иконка «+» в правом верхнем углу top bar. Тап → стандартное iOS-меню (SwiftUI Menu) с двумя пунктами: «Сканировать QR» + «Добавить из буфера». IMP-03 (file picker) отложен.

**Notes:** Это автоматически отложило IMP-03 (file picker) в Phase 11 — поскольку меню «+» содержит только 2 пункта, отдельной точки входа для импорта файла нет. Subscription URL и JSON endpoint всё равно поддерживаются — через буфер обмена (parser распознаёт URL → HTTP GET).

---

### Q2.2 TabBar и Settings location

| Option | Description | Selected |
|---|---|---|
| TabBar с двумя вкладками (Подключение/Настройки) | По образцу v2raytune. Решает где живёт KILL-03 toggle. | |
| Без TabBar в v0.2 | Single-screen MainScreen. KILL-03 живёт где-то иначе. | |
| TabBar с одной вкладкой | Структура есть, но одна вкладка. Компромисс. | |
| Иконка меню в LEFT верхнем углу top bar → Settings page (NavigationStack push) | Без TabBar, без поиска. (Это ответ пользователя через Other.) | ✓ |

**User's choice:** «Нет, таб-бар вообще не нужен. В верхнем левом углу, где у v2RayTune иконка поиска, будет иконка меню, ведущая на страницу настроек.»

---

### Q2.3 Поиск (лупа) в левом верхнем углу — что с ней?

**User's choice:** «Поиск вообще не нужен.» (Слот занят меню-иконкой.)

---

### Q2.4 Pill «Отключено ›» — что делает тап?

| Option | Description | Selected |
|---|---|---|
| Pill без стрелки | Показывает статус, без disclosure arrow. Phase 3 вернёт стрелку с раскрытием в server-list. | ✓ |
| Pill со стрелкой → server-list | Тап открывает server-list уже в v0.2. Расширение Phase 2 scope в сторону SRV-*. | |
| Простой текст без pill | Голый текст под кнопкой. Меньше расхождения с Phase 1. Отход от v2raytune. | |

**User's choice:** Pill без стрелки.

---

### Q2.5 Empty-state layout — что внутри

**Ход дискуссии:** Сначала предложил три варианта (полная копия v2raytune empty-state с timer+power+pill / только карточка / гибрид). Пользователь ответил Other: «Хочу оставить минимализм. Верхнее меню. Под ним таймер. Под ним статус. Поднимем кнопку. А в самом низу — сервер или авто выбор.» Я интерпретировал как «empty-state = только текст "Нет конфигурации"», что оказалось неверным — пользователь поправил: empty-state это **карточка** с заголовком, подзаголовком и двумя кнопками (как в v2raytune, но без timer/power/pill вокруг карточки).

**Финальное решение:** Empty-state — центральная карточка:
- Заголовок: «Нет конфигурации»
- Подзаголовок: «Добавьте первую конфигурацию с помощью кнопок ниже»
- Кнопка 1 (primary): «Добавить из буфера»
- Кнопка 2 (secondary): «Отсканировать QR-код»

Timer / power-кнопка / status pill / server-line — скрыты в empty-state. Иконка «+» в top bar остаётся.

В состояниях с конфигом — полный layout: top bar → timer → pill → power-кнопка → server-line.

---

### Q2.6 Текст empty-state карточки

| Option | Description | Selected |
|---|---|---|
| Дословно как v2raytune | «Список конфигураций пуст / Добавьте первую конфигурацию с помощью кнопок ниже». Финал Phase 11 переформулирует под BBTB-бренд. | ✓ (адаптировано в финале на «Нет конфигурации» в Q2.5) |
| Адаптировать под BBTB-тон | «Пока пусто — давайте "вернём жука" в эфир» или похожее. Риск: не понятно нетехническому пользователю. | |
| Other | Свои формулировки. | |

**Финальный текст** (после Q2.5): «Нет конфигурации» (заголовок) + «Добавьте первую конфигурацию с помощью кнопок ниже» (подзаголовок).

---

## KILL-03 — toggle и Settings page contents

### Q3.1 Что внутри Settings page на v0.2 кроме KILL-03?

| Option | Description | Selected |
|---|---|---|
| Только «Безопасность» → Kill Switch toggle | Один раздел, один toggle. Остальные разделы — позже. | ✓ |
| Безопасность + О приложении (версия) | Toggle + раздел с версией, build, GitHub-ссылка на ядро. | |
| Безопасность + Подписки | Toggle + базовый список конфигов с swipe-to-delete и кнопкой «Обновить из источника». Расширение в сторону SRV-02. | |
| Other | Своё. | |

**User's choice:** Только «Безопасность» → Kill Switch toggle.

---

### Q3.2 UX самого toggle KILL-03

| Option | Description | Selected |
|---|---|---|
| Toggle + footer + alert при выключении | Стандартный SwiftUI Toggle, при выключении confirmation «Без kill switch ваш трафик может утечь...». | |
| Toggle без confirmation | Просто переключается, без всплывающего окна. | ✓ |
| Destructive confirmation с вводом фразы | Красный destructive button + ввод «я понимаю риск». Overkill. | |

**User's choice:** Toggle без confirmation.

---

### Q3.3 Когда применяется изменение toggle?

| Option | Description | Selected |
|---|---|---|
| Сразу — перезаписываем profile | KillSwitch.apply() перевызывается, saveToPreferences. При активном туннеле — баннер или авто-reconnect. | |
| Только на следующем connect | Toggle меняет UserDefaults флаг, profile обновляется при следующем подключении. Баннер «Переподключитесь для применения». | ✓ |
| Сразу + auto-reconnect | disconnect → перезапись → reconnect. 4-8 сек пауза ломает stream/звонки. | |

**User's choice:** Только на следующем connect.

---

## Trojan URI schema (Claude-defaults)

| Option | Description | Selected |
|---|---|---|
| Фиксируем Claude-defaults, пишем CONTEXT.md | Trojan URI поля и правила (TLS-only, fingerprint default, allowInsecure игнорируется) зафиксированы как Claude-defaults в CONTEXT.md. | ✓ |
| Обсудить детали Trojan URI | Спросить по каждому полю. | |
| Развернуть ещё грей-зоны | Придумать 2-3 дополнительных грей-зон. | |
| Пересмотреть ранее решённое | Перерешать что-то. | |

**User's choice:** Фиксируем Claude-defaults, пишем CONTEXT.md.

**Notes:** Trojan URI schema задокументирована в `02-CONTEXT.md` D-08. Базируется на реальном примере пользователя `trojan://LN8x95...@185.237.218.81:2087?security=tls&type=ws&path=/...&sni=vpn.vergevsky.ru&fp=chrome#Латвия — Trojan`. R1 принцип: `allowInsecure=1` игнорируется.

---

## Claude's Discretion

Решения, принятые Claude без явного обсуждения (зафиксированы в `02-CONTEXT.md`, можно пересмотреть до `/gsd-plan-phase`):

- HTTP-probe URL для urltest: рекомендован `cp.cloudflare.com/generate_204` (вместо Google-домена). Окончательно — planner+research.
- urltest interval, tolerance, idle_timeout — sing-box defaults (1m / 50ms / 30m).
- Subscription parser fallback chain (JSON → base64 → plain-text).
- Subscription User-Agent: `BBTB/0.2`.
- Re-import того же subscription URL — replace pool (merge / multi-source — Phase 3).
- Server identity для дедупликации: `host+port+protocolID+sni`.
- TLS certificate-pinning для subscription URL: НЕ на v0.2 (DPI-08 — Phase 7).
- SF Symbol меню-иконки: `line.3.horizontal` (гамбургер) — финал Phase 11.
- SF Symbol для empty-state иконки: `tray` или `shippingbox` — финал Phase 11.
- macOS Settings: SwiftUI `Settings { ... }` Scene (Cmd+,) + дублирующий entry-point через menu icon.
- Camera permission copy: «BBTB использует камеру для сканирования QR-кодов с конфигурациями VPN-серверов».
- Trojan template — новый файл `Resources/SingBoxConfigTemplate.trojan.json` с conditional WebSocket-секцией.
- ConfigBuilder refactor: per-protocol Config Builder + общий PoolBuilder для urltest-обёртки. Финальная архитектура — planner+research.
- Trojan URI fields default: `fp=chrome` если пусто; `sni → host` fallback если пусто; `alpn=h2,http/1.1` default.

---

## Deferred Ideas

(См. полный список в `02-CONTEXT.md` `<deferred>`.)

- IMP-03 (file picker) → Phase 11 (UX-01 onboarding).
- Server-list UI (UX-04, SRV-*) → Phase 3.
- Multiple subscription URLs (SRV-02) → Phase 3.
- Pull-to-refresh / background-fetch → Phase 3.
- Финальный onboarding (UX-01) → Phase 11.
- Финальный Settings со всеми разделами → Phase 4/10/11.
- Анимации (UX-08) → Phase 11.
- macOS R5 «Отключить enforceRoutes» (KILL-04) → Phase 10.
- Auto-reconnect при изменении kill switch — отказались (баннер).
- Certificate pinning (DPI-08) → Phase 7.
- Anti-DPI suite (TLS-fragmentation, padding, delay, mux) → Phase 7.
- Custom HTTP-probe URL на свой VPS — опционально, planner.
- xray-core fallback (CORE-09) → Phase 4+.

---

*Generated: 2026-05-11*
