# BBTB

**Display name:** «Верни жука» (ru) / «Bring Back the Bug» (en)
**Project codename:** `BBTB` (Bring Back The Bug)

## What This Is

VPN-клиент для macOS 15+ и iOS 18+, ориентированный на обход ТСПУ (Технические Средства Противодействия Угрозам — российская инфраструктура DPI у магистральных операторов). Аудитория — нетехнические пользователи в РФ из круга «друзей и знакомых» одного разработчика. Распространение через TestFlight External Testing с публичной invite-ссылкой, без публичного App Store.

## Core Value

В один тап получить VPN-соединение, обходящее ТСПУ, без необходимости разбираться в протоколах. Главный экран — таймер, кнопка «Подключиться» и выбор сервера. Всё остальное (9 протоколов, 4 транспорта, anti-DPI, kill switch, DNS, rules engine) спрятано в «Расширенные».

## Requirements

### Validated

(None yet — ship to validate)

### Active

См. `.planning/REQUIREMENTS.md` для детального списка с REQ-IDs. Высокоуровнево:

- [ ] **Базовое подключение через VLESS+Vision+Reality** на iOS и macOS (Phase 1)
- [ ] **Импорт конфигов** (буфер обмена → QR-код → файл, поэтапно)
- [ ] **Все 9 протоколов**: VLESS+Reality, WireGuard, VLESS+XTLS-Vision, Shadowsocks-2022, Hysteria2, Trojan, AmneziaWG, TUIC v5, OpenVPN/TLS
- [ ] **4 транспорта**: XHTTP, gRPC, WebSocket, HTTPUpgrade
- [ ] **Kill switch системный** (`includeAllNetworks=true` + `enforceRoutes=true`)
- [ ] **Anti-DPI suite**: uTLS, фрагментация TLS ClientHello, packet padding, random delay, mux, CDN-фронтинг
- [ ] **Rules Engine** с Ed25519-подписью rules.json
- [ ] **DNS-стратегия**: DoH внутри туннеля + encrypted bootstrap + IPv6 туннелирование/блок
- [ ] **UX**: онбординг → главный → список серверов → настройки → расширенные. Локализация ru + en
- [ ] **Deep links**: `bbtb://` + Universal Links через `import.bbtb.app`
- [ ] **Security review** до v0.1 (R1, R6): нет SOCKS5 на localhost, gRPC API sing-box отключён, P2P=false
- [ ] **Auto-fallback** между протоколами одного сервера при DPI-блокировке
- [ ] **MAX-detection** без UI, в локальный лог (R3-related)
- [ ] **Privacy-respecting analytics** на собственном VPS + crash reporter
- [ ] **Биометрия** (Face ID / Touch ID) для входа в приложение, опционально
- [ ] **Beta App Review** submission и публичный TestFlight invite link (v1.0)

### Out of Scope

- **Multi-hop / chain proxy** — отложено на v1.3
- **Виджеты iOS, Apple Watch, Live Activity, Shortcuts** — отложены на v1.4–v1.7
- **Speed test, полные логи соединений** — отложены на v1.2
- **Push notifications** — отложены на v1.6
- **Stealth/Panic режим** (маскировка иконки, decoy-конфиги) — отложен на v1.8
- **iCloud-синхронизация** — отложена на v1.9
- **Managed-серверы и биллинг через App Store** — отложены на v2.0 (мажорное изменение бизнес-модели)
- **Modular UI Pro** (Basic/Pro режимы) — отложено на v2.1
- **Resident-IP exit-инфраструктура** — на MVP не делаем (дорого, юр-вопросы), направление для v1.x
- **Защита от таргетированной слежки** — приложение не позиционируется как решение для журналистов под прицельной слежкой; только массовый DPI
- **Smart-метрика auto-select по DPI-успеху** — отложена на v1.1 (на MVP простой ping + losses)
- **Анализ маршрутизации/getifaddrs скрытие на macOS** — невозможно без root, документируется как known limitation в FAQ

## Context

- **Подготовка**: уже создан полный системный промт `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` (1204 строки) и knowledge base в `wiki/` (~28 страниц): архитектура, протоколы, anti-DPI, ТСПУ, поверхность детекта на iOS/macOS, методика РКН, security-gaps, threat_model, server requirements. Wiki ведётся параллельно как long-term decision log.
- **Прецеденты**: Hiddify, NekoBox, FoXray, V2Ray-клиенты — изучены как референсы, особенно UX-pattern «список серверов» из Hiddify.
- **Угрозы**: задокументированы в `wiki/threat_model` (в промте), `wiki/apple-detection-surface.md`, `wiki/rkn-methodology-document.md`, `wiki/xray-localhost-vulnerability.md`, `wiki/snitch-rtt-detection.md`.
- **Архитектурные решения R1–R6** приняты на этапе планирования (2026-05-11), зафиксированы в `wiki/security-gaps.md` и в промте v2.

## Constraints

- **Tech stack**: Swift 5.10+/6 mode, SwiftUI, Swift Concurrency, SwiftData, Keychain, NetworkExtension, sing-box через `libbox.xcframework`, xray-core как fallback, WireGuardKit от ZX2C4, swift-crypto от Apple, OSLog. Никаких сторонних SDK (Crashlytics, Mixpanel, Sentry).
- **Минимальные версии**: iOS 18.0, macOS 15.0, Xcode 16+
- **Платформа разработки**: Apple Silicon
- **Лицензия**: гибрид — ядро (обёртка sing-box, парсеры, network logic) под AGPL-3.0 в публичном репозитории, GUI и pro-фичи closed-source. Юридически корректно по отношению к GPL-3 sing-box.
- **Дистрибуция**: TestFlight (External Testing) до 10 000 пользователей, 90-дневный цикл сборки. Никакого публичного App Store на MVP.
- **Apple Developer**: Individual, зарегистрирован вне РФ. Никакого хостинга в РФ.
- **Серверная инфраструктура**: exit-серверы не на стандартных hosting-провайдерах (Hetzner/DigitalOcean/Vultr дают сигнал GeoIP `hosting=true`). Сервер для rules.json и telemetry — отдельный VPS, может быть стандартным.
- **Стиль разработки**: один разработчик + Claude Code as co-pilot. Workflow GSD. Жёстких сроков нет, приоритет — качество архитектуры.
- **Авторитет источников**: `prompts/v2` — авторитетный по релизам и архитектуре. `.planning/ROADMAP.md` производный. Wiki — справочник + decision log.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| **R1**: Security review до v0.1 (нет SOCKS5 на localhost, gRPC API sing-box отключён) | Уязвимость xray/sing-box на Android позволяет любому приложению детектировать VPN через сканирование 127.0.0.1. На Apple-платформах потенциально та же проблема, требует верификации. | — Pending (заблокирует v0.1) |
| **R2**: Sing-box как основной движок (не WireGuardKit) | Без Reality нет защиты от ТСПУ; sing-box даёт Reality. WireGuardKit — отдельный модуль для нативного WireGuard в v0.7. | ✓ Закрыто |
| **R3**: WebRTC STUN-блок выкл по дефолту | Primary-аудитория — нетехнические юзеры, ломать им Google Meet / Discord Web нельзя. Тоггл в Расширенных. | ✓ Закрыто |
| **R4**: `enforceRoutes = true` остаётся как дефолт | Защита от DNS-leak приоритетнее снижения детектируемости. На macOS пользователь может опционально отключить через тоггл. TODO на v1.x — искать альтернативу. | ⚠️ Revisit в v1.x |
| **R5**: На macOS — одна опция «Отключить принудительную маршрутизацию» в Расширенных, не отдельный «Stealth mode» | Полную невидимость на macOS не дать; одна явная опция честнее искусственного режима. | ✓ Закрыто (реализуется в v0.10) |
| **R6**: Параметр P2P интерфейса iOS — не выставлять | Закрывает один косвенный сигнал детекта VPN методикой РКН. Стоимость — 30 минут разработки в v0.1. | — Pending (v0.1) |
| **Sing-box через libbox.xcframework** | Стандартный путь интеграции sing-box на Apple-платформах через gomobile-биндинги. | ✓ Закрыто |
| **Distribution: TestFlight External only на MVP** | 10k тестировщиков достаточно для «друзей»; никакого публичного App Store — меньше поводов для РКН. | ✓ Закрыто |
| **Лицензия: AGPL-3.0 ядро + closed GUI** | Юридически корректно к GPL-3 sing-box, даёт контроль над продуктом. | ✓ Закрыто |
| **Apple Developer Individual вне РФ** | Снижает риски персональной ответственности; никакого юр.лица в РФ. | ⚠️ Revisit если РКН попросит Apple удалить app |
| **Rebrand: YourVPN → BBTB** (decided 2026-05-11 in `/gsd-discuss-phase 1`) | `YourVPN` был workname. Финальное имя проекта — `BBTB` (Bring Back The Bug, аббревиатура), display name «Верни жука» (ru) / «Bring Back the Bug» (en). Bundle prefix `app.bbtb.*`, App Group `group.app.bbtb.shared`, Universal Links `import.bbtb.app`. Team ID `UAN8W9Q82U`. | ✓ Закрыто |
| **R7: Build system — Tuist 4.x** (decided 2026-05-11 в Phase 1 execution) | Xcode UI flow для multi-target NSExtension setup из-за Xcode 15+ Synchronized Folders и отсутствия «Create folder references» опции стал хрупким и нерекомендуемым. Tuist даёт declarative `Project.swift` + `Workspace.swift`, воспроизводимый xcodeproj через `tuist generate`. Подходит для роста проекта до Phase 12 с расширением модулей. | ✓ Закрыто |
| **R8: libbox.xcframework integration recipe** (decided 2026-05-11) | libbox v1.13.11 API requires `LibboxCommandServer` (не `LibboxBoxService`); iOS/tvOS slices xcframework требуют flatten к shallow bundle с непустым Info.plist; extension/main app targets требуют explicit linker flags (`-lresolv`, `-framework UIKit/AppKit/SystemConfiguration` в зависимости от target). Постпроцессинг автоматизирован в `BBTB/scripts/fix-libbox-xcframework.sh`. Полная инструкция — `wiki/security-gaps.md` R8. | ✓ Закрыто |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions **and** в `wiki/security-gaps.md` или подходящую wiki-страницу
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-11 after initialization from `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md`*
