# Журнал изменений wiki

Хронологическая запись всех операций над wiki. Append-only.

---

## 2026-05-12 — Phase 2 wiki update (полный пакет)

**Новые страницы:**
- `wiki/trojan.md` — Trojan протокол: TCP+TLS и WS+TLS, ALPN h2 правило (R12), URI-парсинг, sing-box конфиг, urltest multi-server
- `wiki/config-importer.md` — универсальный import pipeline: 3 формата, ConfigImporter, PoolBuilder, serverHost/tunnelRemoteAddress, безопасность

**Обновлённые страницы:**
- `wiki/protocols-overview.md` — Trojan → ✓ v0.2; auto-fallback → реализован через urltest (было «появится»); добавлены ссылки [[trojan]], [[config-importer]]
- `wiki/kill-switch.md` — добавлена секция «Реализация v0.2»: тоггл в Безопасность + ReconnectBanner; roadmap обновлён (✓ v0.1, ✓ v0.2)
- `wiki/architecture.md` — добавлены реальные подмодули Phase 2: Protocols/Trojan, ConfigParser/(TrojanURIParser, PoolBuilder), AppFeatures/(MainScreenFeature, SettingsFeature, QRScanner)
- `wiki/release-roadmap.md` — v0.1 → ✓ Complete 2026-05-11 с DoD; v0.2 → ✓ Complete 2026-05-12 с DoD
- `wiki/index.md` — добавлены [[trojan]], [[config-importer]]; секция «Импорт и доставка конфигов» обновлена

## 2026-05-12 — Phase 2 UAT closure

**Операции:**
- `wiki/security-gaps.md` — добавлены R12 (Trojan-WS ALPN), R13 (tunnelRemoteAddress), R14 (Phase 2 security audit)
- `wiki/security-gaps.md` — обновлена дата Last updated

**Phase 2 итог:** UAT T0-T9 PASS. Три архитектурных решения зафиксированы. Три новых `[x]` требования в REQUIREMENTS.md (PROTO-02, PROTO-10, IMP-02, KILL-03). ROADMAP Phase 1 + Phase 2 отмечены Complete.

---

## 2026-05-11 — Первичный ингест

**Источники:**
- `raw/VPN-клиент для macOS и iOS — Промт для Claude Code.md` — главный системный промт / ТЗ на проект (~1050 строк)
- `raw/Дыры в безопасности, которые нужно обсудить.md` — список открытых вопросов и внешних ссылок (~20 строк)

**Внешние материалы, проанализированные в рамках ингеста:**
- https://github.com/xtclovver/RKNHardering — Android-приложение, реализующее методику РКН по детекту VPN (1231★, обновлён 2026-05-10). Изучены: архитектура, модули проверки, верификация по матрице сигналов.
- https://habr.com/ru/articles/1020080/ — статья «Из-за критической уязвимости VLESS клиентов скоро все ваши VPN будут заблокированы», автор runetfreedom, опубликовано 7 апреля 2026. Изучены: механизм уязвимости localhost-SOCKS5 в xray/sing-box, список затронутых клиентов, рекомендации.

**Созданные страницы (19):**

Архитектура и продукт:
- `product-overview.md`
- `architecture.md`
- `tech-stack.md`
- `release-roadmap.md`
- `ux-specification.md`

Протоколы и транспорты:
- `protocols-overview.md`
- `vless-reality.md`
- `transports.md`

Anti-DPI и ТСПУ:
- `tspu.md`
- `anti-dpi-techniques.md`

Безопасность:
- `kill-switch.md`
- `dns-strategy.md`
- `ipv6-strategy.md`
- `rules-engine.md`
- `deep-links.md`
- `max-messenger.md`
- `vpn-detection-by-apps.md` — из второго источника (22/30 приложений)
- `rkn-detection-methodology.md` — из внешнего репо xtclovver/RKNHardering
- `xray-localhost-vulnerability.md` — из внешней статьи Habr 1020080
- `security-gaps.md` — открытые вопросы из второго источника

Дистрибуция и юр-аспекты:
- `distribution-testflight.md`
- `licensing.md`

Сервис:
- `index.md`
- `log.md`

**Ключевые открытия для проекта:**

1. **Критическая угроза**: `libbox.xcframework` (sing-box, который мы планируем использовать) на Android запускает локальный SOCKS5 без авторизации — любое приложение на устройстве может это детектировать. На iOS sandbox теоретически изолирует loopback, но это требует обязательной верификации перед v0.1. См. `xray-localhost-vulnerability.md`.

2. **22 из 30 приложений** в РФ детектят VPN, 19 отправляют статус на сервер — банки, маркетплейсы, Яндекс, MAX. Это `known limitation` для primary-аудитории. См. `vpn-detection-by-apps.md`.

3. **Методичка РКН по детекту** (RKNHardering) — публичная и хорошо документированная. Используется и оптимизируется. Параллельно автор открыт к contributions по обратной задаче (антидетект). См. `rkn-detection-methodology.md`.

4. Три Instagram-reels из второго источника **не разобраны** — нужен пересказ от пользователя или альтернативный источник.

---

## 2026-05-11 — Второй ингест (методика РКН + парсер подписок)

**Новые источники:**
- `raw/ocr_methodika_vpn_proxy.md` (~47KB) — OCR-копия официальной методики РКН по выявлению VPN/Proxy на пользовательских устройствах. Структура: 10 разделов, 4 этапа внедрения, матрица решений из трёх сигналов.
- `raw/Документация парсера подписок singbox-launcher.md` — ссылка на документацию парсера из репо `Leadaxe/singbox-launcher`.

**Внешние материалы, проанализированные:**
- https://github.com/Leadaxe/singbox-launcher/blob/main/docs/ParserConfig.md — изучена документация парсера URI-схем и подписок.

**Уточнение от пользователя:**
- Фокус только на iOS и macOS — Android-специфика отрезана из ингеста.

**Созданные страницы (6):**

Детект VPN на устройстве:
- `rkn-methodology-document.md` — первоисточник методики, матрица решений, фокус на iOS/macOS-релевантные части
- `apple-detection-surface.md` — конкретные API детектирования на iOS (`CFNetworkCopySystemProxySettings`, `__SCOPED__`, `NWPathMonitor`, `NEVPNManager`, `utun*`) и macOS (`getifaddrs()`, маршруты, `Transparent Proxy API`, `enforceRoutes`)
- `geoip-detection.md` — Этап 1 как главный фронт защиты, hosting/ASN сигналы, resident-IP стратегии
- `snitch-rtt-detection.md` — метод задержек как ОС-независимая сетевая угроза, контрмеры через географическую близость exit'а
- `false-positives.md` — раздел 4 методики: корпоративный VPN, антивирусы, виртуализация, iCloud Private Relay

Референсы:
- `config-parser-singbox-launcher.md` — URI-схемы (vless, vmess, trojan, ss, hy2, ssh, socks, naive, wireguard), форматы подписок, edge cases для ConfigParser

**Обновлены страницы (6):**
- `rkn-detection-methodology.md` — переориентирована как «Android-имплементация», явно ссылается на новый первоисточник и apple-detection-surface
- `kill-switch.md` — добавлено предупреждение о конфликте `enforceRoutes` vs детектируемости на macOS
- `security-gaps.md` — добавлены 4 новых пункта: enforceRoutes-конфликт, iCloud Private Relay edge case, поверхность macOS шире iOS, hosting-IP exit-серверов
- `xray-localhost-vulnerability.md` — добавлены ссылки на первоисточник методики; уточнено, что список SOCKS-портов идёт прямо из методики (раздел 6.4)
- `vpn-detection-by-apps.md` — добавлен раздел «Когда они проверяют» (логин, оплата, ключевое действие); ссылки на методику и apple-detection-surface
- `index.md` — новый раздел «Детект VPN на устройстве», обновлена карта связей, добавлены новые пункты для проработки

**Ключевые открытия:**

1. **Главный фронт защиты — GeoIP**. Если серверный GeoIP не выявил аномалию, никакая комбинация прямых/косвенных сигналов **сама по себе** не приводит к жёсткому вердикту «обход выявлен» (Таблица 2 методики). Hosting-IP exit-серверов мгновенно ставит GeoIP в «выявлен» — это **главная архитектурная угроза** для нашего проекта.

2. **iOS защищён архитектурно sandbox'ом**. Из методики прямо: «доступ к системным данным существенно ограничен» (6.5), «анализ таблиц маршрутизации не применим для iOS» (7.6). На iOS детектируется только `utun*`-интерфейс и параметр P2P — но скрыть это без jailbreak невозможно.

3. **macOS уязвимее iOS**. Доступны `getifaddrs()`, маршруты, `Transparent Proxy API`. И — критически — методика прямо называет `enforceRoutes` техническим признаком, а мы его используем в kill switch. Это open trade-off.

4. **SNITCH — отдалённая, но реальная сетевая угроза**. RTT-триангуляция работает по физике задержек и не обходится никакими anti-DPI техниками. Единственный ответ — географическая близость exit'а к пользователю.

5. **Когда приложения детектят**: на login/payment/ключевом действии, не непрерывно (методика 6.3). Это объясняет реальный пользовательский опыт с банковскими и маркетплейс-приложениями.

6. **iCloud Private Relay юридически защищён** в методике от автоматической классификации как «обход блокировок». Это edge case для пользователей, у которых Private Relay одновременно с нашим VPN.

**Всего в wiki после второго ингеста:**
- 28 концептуальных страниц
- 1 index.md
- 1 log.md

---

## 2026-05-11 — Попытка ингеста Instagram-reels (неудача)

**Цель**: получить содержимое трёх Instagram-reels из `raw/Дыры в безопасности, которые нужно обсудить.md`.

**Попытки**:
- Firecrawl scrape: Instagram явно не поддерживается провайдером
- WebFetch на оригинальные URL: возвращает login-стену
- WebFetch через зеркало `ddinstagram.com`: ECONNREFUSED

**Решение пользователя**: оставить статус «недоступно», вернуться позже при наличии пересказа или скриншота. Зафиксировано в `security-gaps.md` пункт 4.

---

## 2026-05-11 — Аудит и фиксы

**Источник**: запрос пользователя «сделай аудит вики».

**Формальные проверки** (без правок, всё чисто):
- 30 файлов в wiki/
- 0 dangling links
- frontmatter и обязательные поля (Summary/Sources/Last updated/Related pages) на месте везде
- 0 orphan'ов в строгом смысле

**Применённые фиксы**:

1. **`protocols-overview.md`** — устранено терминологическое противоречие между «Phase 1» и «v0.1». Группы Phase 1/2/3 теперь явно описаны как «приоритетные группы», а не «релизы». В каждую таблицу добавлен столбец «Появляется в» с указанием конкретной версии (v0.1, v0.2, v0.4, v0.7). Summary переписан.

2. **`architecture.md`** — добавлена cross-ссылка на `[[config-parser-singbox-launcher]]` рядом с модулем `ConfigParser/` и в Related pages. Устранена слабая интеграция референс-страницы.

3. **`rules-engine.md`** — дата примера `rules.json` обновлена с `2025-01-15` (прошлое) на `2026-05-11`. Добавлена явная пометка «иллюстративные значения».

**Не сделано**: переименование `rkn-detection-methodology.md` → `rknhardering-android.md` отложено — требует подтверждения, ломает ~9 inbound-ссылок.

---

## 2026-05-11 — Инициализация GSD-планирования (.planning/)

**Источник**: запрос пользователя «Используя skill GSD спланируй реализацию приложения» → подтверждение варианта 1+B (`.planning/` живёт в корне проекта рядом с wiki, GSD-роадмап основан на промте v2).

**Конфигурация GSD** (`.planning/config.json`):
- Mode: YOLO (автоматический режим, без подтверждений на каждом шаге)
- Granularity: Fine (12 фаз = 12 релизов v0.1–v0.12+v1.0)
- Parallelization: Yes
- Git Tracking: Yes (планирующие документы под git)
- Workflow agents: Research + Plan Check + Verifier — все включены
- AI Models: Quality (Opus 4.7 для research/synthesizer/roadmapper)

**Созданные артефакты GSD**:
- `.planning/PROJECT.md` — описание проекта, core value, requirements (Active/OoS), context, constraints, key decisions (R1–R6 + остальные)
- `.planning/REQUIREMENTS.md` — ~130 v1-требований с REQ-IDs (CORE, SEC, KILL, PROTO, TRANSP, DPI, IMP, UX, SRV, NET, RULES, DEEP, DETECT, TELEM, BIO, ONDEMAND, LOC, DIST) + v2 (post-MVP)
- `.planning/ROADMAP.md` — 12 фаз, каждая = один релиз. Требования замаплены, success criteria сформулированы
- `.planning/STATE.md` — текущее состояние, активная фаза = Phase 1 (v0.1 Foundation)
- `.gitignore` создан (исключения `.DS_Store`, `.obsidian/`, `.firecrawl/`)
- `Claude.md` → `CLAUDE.md` (переименование линтером), расширен секцией «GSD Workflow (operational planning)» — wiki rules сохранены, добавлены GSD-инструкции
- `git init` выполнен — проект под версионным контролем

**Авторитет источников**:
1. `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` — авторитетный источник по составу релизов и архитектуре
2. `.planning/ROADMAP.md` производный, согласован с промтом v2
3. Wiki — справочник + long-term decision log

**Принцип «wiki как decision log»** зафиксирован в auto memory и продублирован в `CLAUDE.md` (раздел GSD Workflow). При каждой фазе важные решения, новые открытия, изменения подхода переносятся в wiki — чтобы знание было долговременным, а не оставалось только в `.planning/`.

**Следующий шаг**: `/gsd-discuss-phase 1` — обсудить контекст Phase 1 (Foundation, v0.1) перед планированием.

**Источник**: запрос пользователя «давай разрешим спорные вопросы по архитектуре».

**Принятые решения** (зафиксированы в `security-gaps.md` секции «Закрытые / принятые решения»):

| # | Вопрос | Решение |
|---|--------|---------|
| R1 | Локальный SOCKS5 в sing-box на iOS/macOS | Security-блокер до v0.1: проверить конфиг libbox, отключить SOCKS5 и gRPC, написать iOS-тест |
| R2 | Sing-box vs WireGuardKit как основной движок | Sing-box. Без Reality проект бессмыслен |
| R3 | WebRTC STUN-блок по умолчанию | Выкл по дефолту, тоггл в Расширенных. Текущий план финальный для MVP |
| R4 | `enforceRoutes` на macOS | Оставляем `true` по дефолту. Защита от DNS-leak приоритетнее. TODO на v1.x — поиск альтернативы без выставления флага |
| R5 | «Stealth mode» на macOS | Одна опция в Расширенных «Отключить принудительную маршрутизацию» в v0.10. Не отдельный режим |
| R6 | Параметр `P2P` интерфейса на iOS | Проверить и не выставлять в v0.1 (30 мин работы) |

**Обновлены страницы**:
- `security-gaps.md` — переструктурирована: «Активные вопросы» (A1–A5) и «Закрытые / принятые решения» (R1–R6) с обоснованиями
- `kill-switch.md` — блок-предупреждение про `enforceRoutes` переведён из «trade-off открыт» в «принятое решение»; roadmap v0.10 расширен опцией
- `apple-detection-surface.md` — обновлены разделы про `enforceRoutes`, `P2P`, локальный SOCKS5; сводная таблица отражает резолюции
- `ux-specification.md` — в раздел Расширенных добавлен тоггл `enforceRoutes` (macOS only) с черновой формулировкой
- `release-roadmap.md` — v0.1 получил блок «Security review до релиза»; v0.10 — упоминание macOS-тоггла

**Открытые архитектурные вопросы** (после этого раунда):
- Только инфраструктурно-юридические: A1 (что делать с 19 приложениями), A2 (юр-риски аккаунта), A3 (iCloud Private Relay edge case), A4 (hosting-IP exit-серверов), A5 (Instagram-reels).
- Чистых вопросов «как кодить приложение» — нет.

---

## 2026-05-11 — Доработка промта Claude Code → v2

**Источник**: запрос пользователя «доработать промт-файл под принятые решения».

**Метод**: оригинал в `raw/` immutable (правило CLAUDE.md). Создана новая папка `prompts/` и скопирован файл как `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md`. Точечные правки через Edit, без переписывания с нуля.

**Применённые изменения** (12 правок в одном проходе):

| # | Раздел | Изменение |
|---|--------|-----------|
| 1 | header | Добавлен HTML-комментарий `<!-- v2 (2026-05-11) -->` с перечнем изменений |
| 2 | `<role>` | Упомянута методика РКН и поверхность детекта на iOS/macOS как часть экспертизы |
| 3 | `<protocols>` | Phase 1 переформулировано в «приоритетная группа» с явным указанием «появляется в v0.1/v0.7/etc» для каждого протокола. Исправляет противоречие с release_roadmap |
| 4 | `<security>` Kill switch | Добавлен явный trade-off-блок про `enforceRoutes` (R4); добавлен пункт про `P2P=false` на интерфейсе (R6); добавлен блок «Sing-box engine — обязательные проверки до v0.1» (R1) |
| 5 | `<rules_engine>` пример | Дата обновлена с `2025-01-15` на `2026-05-11` |
| 6 | новый `<threat_model>` | Вставлен большой раздел между `<features>` и `<ux_specification>`: матрица решений РКН, поверхность детекта iOS vs macOS, что мы можем скрыть, SNITCH, known limitations (22 приложения) |
| 7 | новый `<server_infrastructure_requirements>` | Вставлен раздел с требованиями к exit-серверам: избегать hosting-IP, гео-близость, не покупать «засвеченные» IP, рекомендации против localhost-SOCKS5 уязвимости |
| 8 | `<advanced_screen>` | Добавлен macOS-only тоггл «Отключить принудительную маршрутизацию» (R5) |
| 9 | `<mvp_scope>` included_in_v0_1 | Добавлен блок «Security review до релиза» с конкретными чек-пунктами |
| 10 | `<phase_1>` | В цели и DoD добавлен security review (sing-box SOCKS5/gRPC, P2P) |
| 11 | `<release_roadmap>` v0.1 | Аналогично — security review в фичах и DoD |
| 12 | `<release_roadmap>` v0.10 | Упомянут тоггл `enforceRoutes` (R5) |
| 13 | `<definition_of_done>` | Добавлен пункт «Security review sing-box engine» + пункт про FAQ с known limitations |
| 14 | `<final_notes>` | Добавлена таблица «Архитектурные решения, принятые на этапе планирования» (R1–R6) |

**Файлы**:
- Создан: `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md`
- Оригинал `raw/VPN-клиент для macOS и iOS — Промт для Claude Code.md` — не тронут (immutable по правилу CLAUDE.md)

**Замечания**:
- Формулировка тоггла `enforceRoutes` в Расширенных — черновая, помечена «уточнить с дизайнером в Figma»
- При следующем обновлении промта — синхронизировать с актуальным состоянием wiki, особенно `security-gaps.md`

---

## 2026-05-11 — Аудит и фиксы промта v2

**Источник**: запрос пользователя «проверь промт v2 на логичность и противоречия» → «фиксим всё».

**Применённые исправления** (8 правок):

| # | Категория | Что |
|---|-----------|-----|
| 1 | Опечатка | `Gerpc API sing-box` → `gRPC API sing-box` в таблице `<threat_model>` |
| 2 | Противоречие наследия | `<excluded_from_v0_1>`: «Биометрия (отложено в v0.2)» → «в v0.10» (release_roadmap кладёт биометрию именно в v0.10) |
| 3 | Противоречие наследия | `<settings_screen>` «Безопасность» — убрано «тоггл kill switch (вкл по дефолту)». Тоггл живёт в Расширенных, согласно `<security>` и `<release_roadmap>` v0.2. Оставлен указатель |
| 4 | Уточнение | Блок «Sing-box engine — обязательные проверки» в `<security>` явно расширен на iOS **и** macOS (раньше упоминался только iOS, но DoD требовал проверки на обеих) |
| 5 | Иерархия источников | В начало `<release_roadmap>` добавлена явная пометка «Авторитет источников»: release_roadmap — истина по релизам, `<phases>` — высокоуровневая группировка по этапам разработки. При расхождении приоритет за release_roadmap |
| 6 | Косметика | Пример `rules.json` помечен как «иллюстративный; конкретные домены — на этапе серверной конфигурации» |
| 7 | Косметика | `<onboarding>`: `vless://ss://trojan://` → `vless://`, `ss://` или `trojan://` с разделителями |
| 8 | Косметика | `<analytics>`: переформулирован тоггл «Отключить аналитику» (убрано двойное отрицание; явно: сбор включён по умолчанию, тоггл выключает) |

**Кросс-чек**: после правок противоречий в файле не осталось. Опечаток нет. Согласованность с принятыми решениями R1–R6 сохранена.

**Что НЕ исправлялось** (намеренно):
- Избыточность security review v0.1 (упомянут в 5 местах). Сейчас согласовано; пометка для будущих авторов в `security-gaps.md`. Это не баг, а дублирование для надёжности — Claude Code прочитает в любой из секций.

---

## 2026-05-11 — Phase 1 discuss + rebrand YourVPN → BBTB

**Источник**: запрос пользователя `/gsd-discuss-phase 1` → в процессе обсуждения, при закрывающем вопросе «фиксируем дефолты?», пользователь переименовал проект.

**Артефакты GSD**:
- `.planning/phases/01-foundation/01-CONTEXT.md` — контекст Phase 1 (Foundation, v0.1): 4 обсуждённых серых зоны, 7 Claude-defaults, черновая структура 6 wave'ов для planner.
- `.planning/phases/01-foundation/01-DISCUSSION-LOG.md` — лог диалога для аудита.

**Ключевые решения Phase 1** (зафиксированы в CONTEXT.md):
1. Идентификаторы: префикс `app.bbtb.*`, App Group `group.app.bbtb.shared`, Team ID `UAN8W9Q82U`.
2. Тест-сервер VLESS+Reality: уже есть у разработчика, server setup вне скоупа фазы.
3. PacketTunnelExtension iOS↔macOS: общий Swift Package `PacketTunnelKit` + два тонких NSExtension target shell (новое — расширение `prompts/v2 <swift_package_layout>`).
4. Security review R1+R6: security-first как первый wave (sing-box JSON без SOCKS5/mixed inbound, без gRPC API; standalone `SocksProbe` test-app — отдельный bundle `app.bbtb.tools.socksprobe`).

**Rebrand YourVPN → BBTB** (в одном проходе):
- Project codename: `BBTB` (Bring Back The Bug, аббревиатура).
- Display name: «Верни жука» (ru) / «Bring Back the Bug» (en).
- Универсальная замена `yourvpn` → `bbtb`, `YourVPN` → `BBTB`, `yourvpn.app` → `bbtb.app` во всех файлах планирования, спецификации, и wiki.

**Обновлены файлы** (10):
- `Claude.md` — путь Xcode-проекта.
- `.planning/config.json` — блок `project` расширен display names, bundle prefix, app group, universal links domain, team_id.
- `.planning/PROJECT.md` — title + display names + DEEP refs + Key Decisions row про rebrand.
- `.planning/REQUIREMENTS.md` — title + DEEP-01..03.
- `.planning/ROADMAP.md` — title + Phase 9 DEEP scheme.
- `.planning/STATE.md` — project codename + Active Phase status (Context gathered).
- `Wiki/index.md` — deep-links description.
- `Wiki/architecture.md` — root folder + DeepLinks scheme.
- `Wiki/deep-links.md` — все вхождения (custom scheme + домен + appIDs пример обновлён с реальным Team ID).
- `Wiki/release-roadmap.md` — v0.9 секция.
- `Wiki/product-overview.md` — новый раздел «Имя и идентификаторы» с полной таблицей bundle IDs.
- `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` — `<product_overview>` (финальное имя + Team ID), `<swift_package_layout>` root, deep links формат + домен + AASA appIDs, `<phase_4>` и v0.9 в release_roadmap, DoD.

**Сохранённые упоминания YourVPN** (как историческая запись):
- `.planning/PROJECT.md` — строка Key Decisions про rebrand.
- `Wiki/deep-links.md` — frontmatter description с пометкой «ранее yourvpn://».
- `Wiki/log.md` — этот журнал (история).

**Авторитет**: с момента этого commit'а `BBTB` — единственное каноническое имя. Любое появление `YourVPN`/`yourvpn` в новых артефактах считается багом, кроме исторических ссылок.

**Следующий шаг**: `/clear` → `/gsd-plan-phase 1`.

---

## 2026-05-11 — R7: Build system Tuist 4.x

**Источник**: Phase 1 execution checkpoint, пользователь споткнулся на Xcode 16 «Add Files → Create folder references» — этой опции больше нет (Xcode 15+ Synchronized Folders заменили старый dichotomy).

**Решение**: вместо Xcode UI flow генерировать xcodeproj через Tuist 4.x декларативно. См. `security-gaps.md` R7.

**Созданные артефакты**:
- `BBTB/Project.swift` — основной project с 5 targets
- `BBTB/Workspace.swift` — workspace declaration
- `BBTB/Tools/SocksProbe/Project.swift` — отдельный SocksProbe project (R1 invariant — изолированный sandbox)

**Обновлены страницы**:
- `security-gaps.md` — добавлено R7 (Build system: Tuist 4.x) в секции «Закрытые / принятые решения»
- `.planning/PROJECT.md` — Key Decisions table расширена строкой R7

**Что меняется в инструкции Phase 1**: бывший шаг 2 (создание xcodeproj через Xcode UI, ~50 мин) → новые шаги A+B+C (~10 мин через `tuist generate`). Бывший шаг 4 (SocksProbe.xcodeproj через UI) → одна команда `tuist generate` в `Tools/SocksProbe/`.

---

## 2026-05-11 — R10: TUN inbound runtime expansion (gap-closure W3.1)

**Источник**: Phase 1 W3 hack postmortem. В W3 добавили приватный `injectTunInbound` в `BaseSingBoxTunnel` (без тестов, runtime-инжект в extension). Gap-closure W3.1 перенёс это в `SingBoxConfigLoader.expandConfigForTunnel` + ослабил R1.

**Решение**: см. `security-gaps.md` R10.

**Изменённые файлы**:
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift` — relaxed R1 (`forbiddenInboundTypes` = {socks, http, mixed, redirect, tproxy}) + новый публичный метод `expandConfigForTunnel(json:mtu:tunIP:)`.
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` — удалён приватный hack `injectTunInbound`; вызов `SingBoxConfigLoader.expandConfigForTunnel` после `validate`.
- `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift` — 7 новых tests; fixture `valid-tun-inbound.json` (был invalid), новый `legacy-dns-outbound.json`.
- `BBTB/Packages/PacketTunnelKit/Package.swift` — linker settings на testTarget (libbox transitive deps: resolv, bsm, SystemConfiguration, AppKit/UIKit) — побочный fix чтобы `swift test` запускался.
- `Wiki/security-gaps.md` — R10 добавлен.

**Архитектурное правило**, зафиксированное навсегда: bundled template не содержит inbounds; TUN/WireGuard PacketTunnel inbound добавляется на runtime через expand loader'а. Это сохраняет принцип «минимальная shipped attack surface».

---

## 2026-05-11 (вечер) — Phase 1 W5 device test, partial pass + Vision incompatibility candidate

**Контекст**: Продолжение device debug session 2026-05-11. Серия из 5+ фиксов довела до partial pass — туннель и DNS работают, но Safari/HTTPS user-facing destinations всё ещё обрываются.

**Закрытое (commit `0299af6`)**:
- sing-box log injection + main-app→Documents bridge для извлечения через Xcode Devices GUI (App Group containers не выкачиваются напрямую)
- sing-box 1.13 sniff требование: `expandConfigForTunnel` теперь инжектит `{action: sniff}` первым правилом route (без него `protocol: dns` matcher не работает и DNS UDP падает на `vless-out` с "UDP not supported")
- DNS pipeline rebuild (Hiddify-canonical): fakeip CGNAT 100.64.0.0/10 + Yandex bootstrap (`tcp://77.88.8.8` direct) + DoH cloudflare-dns.com fallback + NXDOMAIN на HTTPS/SVCB queries
- `route.rules action: resolve` (sing-box v1.9+) — client-side pre-resolve через bootstrap, чтобы VLESS header нес IP, не hostname
- Outbound tuning: убран `packet_encoding: xudp` (Hiddify экспортирует empty для Vision+TCP, см. hiddify-app#758); MTU TUN 1400→9000 (Hiddify default)

**Что работает**: туннель `connected`, DNS pipeline, ~50% VLESS соединений завершаются `download/upload finished`, Apple iCloud / Telegram backbone трафик.

**Что НЕ работает**: Safari → user HTTPS-сайты (Cloudflare-anycast) обрывается до TLS completion. Подозрение — sing-box client Vision implementation incompatibility с Xray-core server Vision. Happ (форк с собственными патчами) с тем же URI работает.

**Архитектурное решение, зафиксированное**: DNS pipeline — fakeip + route.resolve + Hiddify-canonical — это **базовый working pattern** для sing-box+VLESS+Reality+Vision на iOS NE. См. [[dns-pipeline-decisions]] для деталей и обоснований.

**Открытый issue** (отслеживается в memory + wiki/vless-reality.md): «sing-box client Vision incompatibility candidate». Следующие шаги — trace log (Опция Б) → Hiddify-Next bit-by-bit diff (Опция В) → fallback partial-pass acceptance с SagerNet/sing-box bug report.

**Новые/обновлённые wiki-страницы**: [[dns-pipeline-decisions]] (новая), [[vless-reality]] (секция Vision short-stream issue добавлена).

---

## 2026-05-11 (поздний вечер) — Phase 1 W5 RESOLVED — 7 раундов device-debug + control test

**Контекст**: Продолжение partial-pass session. 7 раундов гипотез + 8 коммитов в день. Финал — `9aa3e93`.

**Реальный root cause (выяснен в раунде 6+7)**:
Template `SingBoxConfigTemplate.vless-reality.json` hardcode'ил `"flow": "xtls-rprx-vision"` независимо от того что в VLESS URI пользователя. Сервер пользователя в исходном тесте имел `flow: ""` (без Vision). Server-client frame format mismatch → server закрывал каждое соединение через ~30мс детерминированно (1 RTT). Симптом «оба направления close в одну мс» = server FIN, оба goroutine в bidirectional pipe sing-box'а получают EOF одновременно — нормальное поведение для server-initiated close.

**Что попробовали безуспешно (false leads из-за неверной гипотезы про Vision incompatibility)**:
1. MTU 9000→1500 (Codex hypothesis) — identical teardown
2. Снять `route.resolve` (Gemini hypothesis) — hostname теперь в VLESS, но teardown остался
3. TUN `stack: gvisor→mixed` (Hiddify default) — crash-loop в **нашей** libbox build (Hiddify собирает с другими build tags)
4. Subnet mask `/30→/28` (Hiddify alignment) — identical teardown

**Диагностический раунд (раунд 6)**: `flow: ""` → connections survive (126 conn, 44% >500ms, MAX 26.14 сек). Vision-mismatch локализован.

**Control test (раунд 7)**: `flow: "xtls-rprx-vision"` + URI от Vision-enabled сервера → connections работают (149 conn, 25% >2 сек, 15% >10 сек, 100 XtlsFilterTls events). Sing-box Vision сам по себе **работает корректно**.

**Финальный фикс (раунд 8, commit `9aa3e93`)**:
- `SingBoxConfigTemplate.vless-reality.json` template: `"flow": "${VLESS_FLOW}"` (placeholder)
- `ConfigBuilder.VLESSRealityInputs`: новое поле `flow: String` + substitution
- `ConfigImporter`: передаёт `parsed.flow` через
- `VLESSURIParser` default: `"xtls-rprx-vision"` → `""` (per Leadaxe ParserConfig spec — отсутствие `?flow=` в URI = без Vision)
- 3 новых теста: missing flow → "", explicit flow preserved, empty flow valid JSON

**Финальный dual-config test (раунд 8)**: оба типа URI (Vision-enabled + non-Vision) работают на iPhone 16 iOS 26 — пользователь подтвердил.

**Wiki-обновления**:
- [[vless-reality]] — раздел «РЕШЕНИЕ Phase 1 W5» переписан (server-client flow mismatch, не Vision bug)
- [[security-gaps]] R10 — TUN inbound параметры (mtu=1500, subnet /28, stack=gvisor)
- [[dns-pipeline-decisions]] — `route.resolve` снят
- [[index]] — нет изменений

**Lessons learned**:
1. Hardcoded template values — не делать; параметры из user URI должны flow through.
2. «Both directions close in same ms» — это **нормальное** sing-box поведение для server-initiated close, не сложный race condition.
3. Cross-AI consult (Codex+Gemini) был полезен для генерации гипотез, но none из них не предложили проверить server-side flow config.
4. **Спрашивать про server config раньше** — пользователь упомянул `flow: ""` на сервере только после 6 раундов.
5. `gh api` для OSS comparison (Hiddify-app + sing-box-for-apple) — полезный метод research, но в этом случае не вёл напрямую к решению.

**Открытый TODO** (`project_phase1_w5_resolved.md` memory): UI hint при импорте URI показывать обнаруженный flow — опциональное улучшение, не блокер.

**Использованная reference docs**: [Leadaxe singbox-launcher ParserConfig](https://github.com/Leadaxe/singbox-launcher/blob/main/docs/ParserConfig.md) — отличная карта VLESS URI query → sing-box JSON mapping.

---

## 2026-05-11 — Phase 1 security audit (`/gsd-secure-phase 1`)

**Что произошло**: запущен retroactive аудит мита́ций для 37 трэтов из PLAN.md W0..W5. 36 closed на первом проходе, 1 BLOCKER найден и закрыт в том же цикле.

**Изменённые страницы**:
- [[security-gaps]] — добавлен раздел **R11. Phase 1 security audit — 37/37 threats closed** с группами контролов (R1/R6/KILL/SEC-03/SEC-05/OSLog/CrashReporter), списком 9 accepted risks, описанием remediated W5-02 (`.gitignore` repo-root build artifacts), TODO для Phase 11 FAQ (W2-05 promote из RESEARCH.md) и Phase 12 (W3-05 codesign в CI; W5-01 crash UI отправка).

**Артефакты вне wiki**:
- `.planning/phases/01-foundation/01-SECURITY.md` — полный audit report (171 строка) со ссылками на каждую evidence-line в impl-файлах. status: verified, threats_open: 0.
- `/Users/vergevsky/ClaudeProjects/VPN/.gitignore` — добавлены `build/`, `*.xcarchive`, `*.dSYM`, `*.ipa` для root-scope (W5-02 mitigation).

**Commit**: `5b897a5` — docs(phase-1): close security audit — 37/37 threats verified, fix W5-02 .gitignore gap.

**Memory entries**:
- `project_phase1_security_audit_complete.md` — добавлено в MEMORY.md index. Phase 1 security gate пройден; перед Phase 12 нужен refresh аудит (supply-chain переходит из accept в mitigate).

**Lessons learned**:
1. **Scope mismatch в `.gitignore`**: PLAN.md писал «уже исключает build/», но это правило было в `BBTB/.gitignore`. После того как `archive-ios.sh` зафиксили на запись в repo-root `build/` (commits `b253ce1` + `b11196b`), правило перестало действовать — но никто не заметил, пока auditor не сделал `git check-ignore`. **Правило**: если меняешь output path script'а, проверяй что соответствующий ignore-rule всё ещё покрывает.
2. **Accepted risks log оптимизирует ре-аудиты**: 9 accepted без verification — это не «слабая защита», это документированные системные ограничения. Будущие аудиты не должны их пере-проверять.
3. **R6 на iOS 26**: Apple unconditionally ставит IFF_POINTOPOINT на utun независимо от destinationAddresses=nil. Code-side mitigation в `TunnelSettings.makeR6Safe` всё равно ценен — на случай если Apple вернёт настраиваемость в будущих iOS.


---

**Дата**: 2026-05-12
**Источник**: Phase 3 — server-management (GSD execution complete)
**Что произошло**: Phase 3 закрыта — 6 планов (5 основных + 1 gap-closure), 162 теста PASS, верификация PASSED.

**Изменённые страницы**:
- [[architecture]] — добавлены: ServerListFeature модуль, SwiftData-схема v0.3 (Subscription @Model + FK + cascade delete + idempotent migration), TCP-пробы/auto-select (ServerProbeService actor, score formula, ProbeAggregate.failures Int), новые ConfigParser-компоненты (ConfigImporting protocol, SubscriptionMergeService, SubscriptionURLFetcher)
- [[ux-specification]] — раздел «Список серверов» переписан под реализованные решения Phase 3: sheet+detents, ячейка «Авто», lazy scroll вместо List, latency badge тиры, pull-to-refresh 2-шага, merge-стратегия missingFromLastFetch, cascade delete, автореконнект без алерта
- [[security-gaps]] — добавлен R15: Phase 3 security audit (T-03-01 name sanitization, T-03-06 SSRF isBlockedHost, T-03-07 TCP accept, T-03-08 cascade correct, T-03-09 migration idempotent); CR-01/CR-04 code-review fixes; accepted T-G1-05 DNS-rebinding → Phase 7

**Ключевые решения, зафиксированные для будущих фаз**:
- `ConfigImporting` protocol живёт в `ConfigParser`, не в `MainScreenFeature` — иначе circular dependency с `ServerListFeature`
- `List` несовместим с прогрессивными async latency updates → использовать `ScrollView + LazyVStack + Section`
- `ProbeAggregate.failures: Int` (raw count) вместо `Int(lossRate * 3)` — IEEE-754 truncation bug
- `selectedID` guard в `provisionTunnelProfile` — silent fallback к другому серверу нарушает D-09 явного выбора пользователя
