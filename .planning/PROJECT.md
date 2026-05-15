# BBTB

**Display name:** «Верни жука» (ru) / «Bring Back the Bug» (en)
**Project codename:** `BBTB` (Bring Back The Bug)

## What This Is

VPN-клиент для macOS 15+ и iOS 18+, ориентированный на обход ТСПУ (Технические Средства Противодействия Угрозам — российская инфраструктура DPI у магистральных операторов). Аудитория — нетехнические пользователи в РФ из круга «друзей и знакомых» одного разработчика. Распространение через TestFlight External Testing с публичной invite-ссылкой, без публичного App Store.

## Core Value

В один тап получить VPN-соединение, обходящее ТСПУ, без необходимости разбираться в протоколах. Главный экран — таймер, кнопка «Подключиться» и выбор сервера. Всё остальное (9 протоколов, 4 транспорта, anti-DPI, kill switch, DNS, rules engine) спрятано в «Расширенные».

## Requirements

### Validated

- ✓ **Базовое подключение через VLESS+Vision+Reality** на iOS и macOS — Phase 1 (UAT 2026-05-11: import + connect + IP swap на iPhone)
- ✓ **Kill switch системный** (`includeAllNetworks=true` + `enforceRoutes=true`) — Phase 1 (UAT T3: airplane mode → traffic blocked)
- ✓ **Security review до v0.1** (R1, R6): нет SOCKS5 на localhost у нашего PacketTunnelProvider; sing-box gRPC API отключён; P2P=false code-side (iOS 26 unconditionally сетает флаг — accepted as Apple platform limit) — Phase 1 (`.planning/phases/01-foundation/01-SECURITY.md` 37/37 threats closed)
- ✓ **SwiftPM monorepo** с модулями VPNCore, ProtocolRegistry, ProtocolEngine, Protocols, KillSwitch, PacketTunnelKit, CrashReporter, DesignSystem, Localization, AppFeatures — Phase 1 (`BBTB/Packages/`)
- ✓ **Импорт через буфер обмена** (VLESS+Reality) — Phase 1 (UAT T2)
- ✓ **Locale ru** (партиальная) — Phase 1 (`BBTB/Packages/Localization`)
- ✓ **Crash reporter** (MXMetricManager → App Group) — Phase 1 (UI-отправка deferred к Phase 12)
- ✓ **Release build без debug-логов** — Phase 1 (UAT T6)
- ✓ **Импорт конфигов** — subscription URL, multi-line URI, JSON endpoint, QR-код — Phase 2 (UAT T1-T4 2026-05-12)
- ✓ **Trojan handler + auto-fallback** (urltest outbound) при блокировке VLESS+Reality — Phase 2 (UAT T5-T6 2026-05-12)
- ✓ **Kill switch toggle** в Settings → Безопасность, баннер при активном тоннеле — Phase 2 (UAT T7-T9 2026-05-12)
- ✓ **Server list** (UX-04) — секции по подпискам, кнопка «Авто», latency, флаги стран — Phase 3 (UAT T1-T5 2026-05-12)
- ✓ **Несколько subscription URL** (SRV-02) — multi-subscription, секции в UI, cascade delete — Phase 3 (UAT T1-T2 2026-05-12)
- ✓ **Pull-to-refresh** (SRV-03) — 2-phase fetch+ping, перепинговывает все серверы — Phase 3 (UAT T3 2026-05-12)
- ✓ **Auto-select по latency** (SRV-01) — pre-connect probe, выбор минимального latency — Phase 3 (UAT T3-T5 2026-05-12)
- ✓ **Ручной выбор сервера + reconnect on change** — Phase 3 (UAT T6-T8 2026-05-12)
- ✓ **Все 5 первых протоколов — VLESS+Reality, Trojan, Shadowsocks-2022, Hysteria2, VLESS+XTLS-Vision** + URI parsers + Outline subscription + Clash YAML — Phase 4 (151+49 tests PASS 2026-05-12)
- ✓ **4 транспорта — XHTTP, gRPC, WebSocket, HTTPUpgrade** (TransportConfig + TransportRegistry + per-protocol buildOutbound) — Phase 5 (~376 tests PASS 2026-05-13)
- ✓ **DNS pipeline (NET-01..04)** — DoH within tunnel + encrypted bootstrap, Yandex полностью искоренён из shipping code (`grep` = 0) — Phase 6 (2026-05-13)
- ✓ **IPv6 strategy (NET-05..07)** — full-tunnel default + block fallback + Advanced Settings — Phase 6 (2026-05-13)
- ✓ **Auto-reconnect + failover (NET-08..11)** — Apple's `NEOnDemandRuleConnect(.any)` + `TunnelWatchdog` actor (mid-session) + `SwiftDataFailoverProvider` (initial-connect); custom `ReconnectStateMachine` + `NetworkReachability` deleted — Phase 6c (re-UAT PASS 2026-05-13)
- ✓ **Performance baseline + 6 architectural patterns (PERF-01..05, QUAL-01..03)** — Triple-AI peer review (Opus + Codex + Gemini) → 19 closed findings + 7 post-fix correctness commits + ExternalVPNStopMarker (Settings-disable invariant) — Phase 6d (UAT regression smoke PASS 2026-05-14)

### Active

См. `.planning/REQUIREMENTS.md` для детального списка с REQ-IDs. Высокоуровнево:
- [ ] **6 in-scope протоколов** (after Phase 7 closure 2026-05-14): VLESS+Reality, VLESS+XTLS-Vision (handler покрывает и plain VLESS+TLS), Trojan, Shadowsocks-2022, Hysteria2, TUIC v5. _(PROTO-06 WireGuard plain + PROTO-07 AmneziaWG + PROTO-09 OpenVPN/TLS → Out of Scope, v2.0+ backlog conditional on demand.)_
- [ ] **4 транспорта**: XHTTP, gRPC, WebSocket, HTTPUpgrade
- [ ] **Kill switch системный** (`includeAllNetworks=true` + `enforceRoutes=true`)
- [ ] **Anti-DPI suite**: uTLS, фрагментация TLS ClientHello, packet padding, random delay, mux, CDN-фронтинг
- [x] **Rules Engine** с Ed25519-подписью rules.json — Phase 8 ✓ implementation complete 2026-05-15 (UAT pending M-04/M-05/M-07/M-08)
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

- **WireGuard plain (PROTO-06)** — Out of Scope, v2.0+ backlog conditional on TestFlight demand _(Phase 7 discuss 2026-05-14 D-02; ТСПУ blocks plain WG behaviorally since Feb 2026; UDP closed in RU summer 2025; AmneziaWG 2.0 покрывала WG-нишу но тоже отложена; см. `wiki/wireguard-deferral-2026.md`)_
- **OpenVPN/TLS (PROTO-09)** — Out of Scope, v2.0+ backlog conditional on TestFlight demand _(Phase 7 discuss 2026-05-14 D-01; ТСПУ blocks OpenVPN полностью с Feb 2026; OpenVPN+Cloak phased out from Amnezia Premium 2026; sing-box не умеет OpenVPN, требует second engine Partout + GPLv3 commercial licensing; см. `wiki/openvpn-deferral-2026.md`)_
- **AmneziaWG 2.0 (PROTO-07) + DPI-04 random delay** — Out of Scope, v2.0+ backlog conditional on demand _(Phase 7b cancellation 2026-05-14 после Codex deep research состояния `amneziawg-apple` library: 5-7 engineer-weeks full quality, manual `libwg-go.a` build chain, Go runtime memory unknown на iOS 18 NetworkExtension 50MB limit, no crash isolation, AWG 2.0 backward-incompat с v1.5 серверами. User-base — friends-and-family с уже работающим Reality+Trojan+Hy2+TUIC стеком, AWG demand не подтверждён реальными запросами. Engine abstraction layer тоже не строим — ради одного нового движка не оправдан в MVP. См. `wiki/amneziawg-deferral-2026.md`)_
- **Multi-hop / chain proxy** — отложено на v1.3
- **Виджеты iOS, Apple Watch, Live Activity, Shortcuts** — отложены на v1.4–v1.7
- **Speed test, полные логи соединений** — отложены на v1.2
- **Push notifications** — отложены на v1.6
- **Stealth/Panic режим** (маскировка иконки, decoy-конфиги) — отложен на v1.8
- **iCloud-синхронизация** — отложена на v1.9
- **RULES-11: macOS per-app routing via NEAppProxyProvider** — Out of Scope v0.10+ conditional on demand (Phase 8 D-08/D-09: L4↔L3 mismatch + NETunnelProviderManager mutual exclusivity + R1 break; AppProxyExtension-macOS target deleted; workaround = `never_through_vpn` rule_set; see `wiki/appproxy-deferral-2026.md`)
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
| **R10: TUN inbound runtime expansion + sing-box 1.13 DNS-hijack** (decided 2026-05-11, gap-closure W3.1) | Hiddify-импорт приходит без `inbounds[]` — клиент сам конфигурирует PacketTunnel inbound на runtime. R1 = default-deny white-list `{tun, direct}`. `SingBoxConfigLoader.expandConfigForTunnel` публичный + idempotent с post-expand re-validation (defense-in-depth). sing-box 1.13 убрал `{type:"dns"}` outbound — теперь `action:"hijack-dns"`. Полное обоснование MTU/stack/subnet — `wiki/security-gaps.md` R10. | ✓ Закрыто |
| **R11: Phase 1 security audit — 37/37 threats closed** (decided 2026-05-11) | Retroactive аудит мита́ций для STRIDE-register из 6 PLAN.md W0..W5. 28 mitigate verified в коде через grep + UAT cross-evidence; 9 accepted risks документированы (iOS 16.1+ Apple leak, App Group sandbox, libbox supply-chain Phase 1, остальные UX/operational). 1 BLOCKER (T-W5-02: repo-root `build/` не gitignored) zerпрожен в том же audit-цикле — root `.gitignore` patch. Phase 12 prerelease делает refresh аудит — supply-chain переходит accept→mitigate (codesign в CI). | ✓ Закрыто |
| **`${VLESS_FLOW}` placeholder в template** (decided 2026-05-11, commit `9aa3e93`) | Template имел hardcoded `flow: "xtls-rprx-vision"` независимо от server-side config. После 7 раундов device-debug (8 commits в день) root cause локализован как server-client flow mismatch, не Vision bug. Решение — `${VLESS_FLOW}` placeholder + parser default `""`. Поддерживает dual-config (Vision-enabled + non-Vision серверы). | ✓ Закрыто |
| **D-14: SNI исключён из identity key** (decided 2026-05-12, Phase 3) | Subscription-серверы с Reality намеренно ротируют SNI между запросами (anti-fingerprint). Если SNI в identity key (`host:port:protocolID:SNI`) — каждый refresh даёт INSERT вместо UPDATE → дублирование серверов. Решение: `identity = host:port:protocolID`; SNI обновляется в UPDATE-ветке merge. | ✓ Закрыто |
| **SwiftData #Predicate с UUID? — fetch-all + in-memory filter** (decided 2026-05-12, Phase 3) | `#Predicate { $0.optionalUUID == someUUID }` молча возвращает empty на части SwiftData runtime (реальные устройства; in-memory тесты могут работать — маскирует проблему). Везде в проекте заменено на `context.fetch(all).filter { ... }`. | ✓ Закрыто |
| **TunnelController: disconnect() поллит до .disconnected** (decided 2026-05-12, Phase 3, commit `b5d3120`) | `stopVPNTunnel()` fire-and-forget; немедленный `startVPNTunnel()` видит `.disconnecting` и бросает ошибку. `disconnect()` теперь поллит (max 5s, 0.5s шаг); `connect()` трактует `.disconnecting` как transient (continue, не throw). | ✓ Закрыто |
| **R18: Phase 6c — Apple's NEOnDemandRule + sliding session window + reactive UI** (decided 2026-05-13, Phase 6c cutover commits `19f3fe7` + `5b0e28c` + `69b8ae8` + Round 6 follow-up `44a5630`) | Phase 6 UAT выявил 4 класса багов в custom auto-reconnect machinery (phantom reconnect, EXC_RESOURCE/PORT_SPACE crash на iOS 26, fight-back с другими VPN, Settings auto-reactivation). Решение — переход на iOS-нативный `manager.isOnDemandEnabled` + `NEOnDemandRuleConnect(.any)` с инвариантом `isOnDemandEnabled = autoReconnectToggle && userIntendedConnected` (sliding session window между явным Connect и любым session-closing событием). Custom machinery (ReconnectStateMachine + NetworkReachability + recovery branches) полностью удалена; mid-session failover — через новый `TunnelWatchdog` actor. UI стал реактивным: `applyVPNStatus(_:)` — единственный источник правды для main `state` + `reconnectBannerState` на NEVPNStatus events. Round 6 follow-up закрыл VM UI desync во время Settings round-trip (observer `queue: .main → nil` + foreground-resync hook) + ввёл `connectedDate` authority для таймера. TunnelController 909 → 316 строк. AppFeatures 133/133. NET-08..11 validated. Полная wiki — `wiki/auto-reconnect.md` + `wiki/security-gaps.md` R18. UAT report — `.planning/phases/06c-on-demand-migration/06C-UAT.md`. | ✅ **Closed 2026-05-13** — re-UAT pair PASS (F-reverse + Settings-disable + G passive on iPhone iOS 26.5). NET-08..11 promoted to Validated. NET-12 (active liveness probe) carve-out для Phase 7-8. |
| **R19: Phase 6d — Performance & Code Quality Audit + 6 architectural patterns DEC-06d-01..06** (decided 2026-05-14, Phase 6d Final-b closure commits `0a9d1af` + `e2e72ab` + `d777548`) | После Phase 5 пользователь сообщил «приложение тяжело грузится». Triple-AI peer review (Claude Opus 4.7 + Codex GPT-5.2 + Gemini 3.1 Pro) дал 45 findings; Option-B (HIGH + selected MEDIUM) + Variant D (без pre-fix Instruments baseline, accept descriptive comparison) закрыли 19 атомарными commits + 7 post-fix correctness commits (cold-start UI freeze block + Settings-disable saga). Установлены 6 архитектурных decisions: (1) cold-start init defer pattern, (2) XPC consolidation в TunnelController ≤ 2 trips, (3) event-driven NEVPNStatus polling (AsyncStream вместо sleep loops), (4) bounded probe concurrency limit 4-8 + cancellation-safe defer, (5) Apple-canonical `options["manualStart"]` discriminator + sticky `ExternalVPNStopMarker` App Group marker (open-source-research-derived from WireGuard iOS `activationAttemptId`), (6) PerfSignposter spans в production code для будущих Instruments capture без re-injection. Cold-start ~−500-1100мс, connect-tap ~−1000-3000мс, disconnect −2.5 сек. PERF-01..05 + QUAL-01..03 → Validated. 26 carved-out findings (6 MEDIUM + 20 LOW) → Phase 6e backlog. Полная wiki — `wiki/performance-baseline.md`. SUMMARY — `.planning/phases/06d-performance-audit/06D-Final-SUMMARY.md`. UAT — `06D-UAT.md`. | ✅ **Closed 2026-05-14** — UAT regression smoke PASS на iPhone iOS 26.5 (hard-blockers A, F-direct, F-reverse, G, I, Settings-disable; E deferred → NET-12; C macOS skipped — carry-over). 6d-NEW-1 (cold-start ≤2sec) + 6d-NEW-2 (connect-tap responsive) PASS. AppFeatures 133/133. PERF/QUAL Validated. |
| **R20: Phase 7 — РФ 2026 reality + Phase 7b cancellation + anti-DPI smart defaults** (decided 2026-05-14, evolved from initial split-decision into 7a-only after Codex deep research on amneziawg-apple integration cost) | **Initial discuss-phase 2026-05-14** дал 5 решений (D-01 OpenVPN → Out of Scope, D-02 plain WG → Out of Scope, D-03 AmneziaWG 2.0 в Phase 7b, D-04 split 7a/7b релизов, D-05 anti-DPI smart defaults). Phase 7a выполнена автономно + iPhone UAT PASS на Trojan subscription. **Phase 7b cancellation 2026-05-14** (после Phase 7a closure, на основании Codex deep research thread `019e27d9-...` состояния `amneziawg-apple`): integration cost — 5-7 engineer-weeks full quality (manual `libwg-go.a` build chain Go 1.26 + Makefile patches GOROOT, Go runtime memory unknown на iOS 18 NetworkExtension 50MB limit, no crash isolation от Go panic, AWG 2.0 backward-incompat с v1.5 серверами); user-base — 50 friends-and-family с уже работающим Reality+Trojan+Hy2+TUIC стеком, AWG demand не подтверждён реальными запросами. Решение пользователя: «отложим амнезию вообще на версию 2 или позднее». PROTO-07 + DPI-04 → Out of Scope, v2.0+ conditional. Engine abstraction layer тоже не строим — ради одного нового движка не оправдан в MVP, архитектура остаётся mono-engine sing-box. **Финал Phase 7:** только Phase 7a ✅ Closed (TUIC v5 + anti-DPI smart defaults + DPI-07 port diversity). 6 in-scope протоколов в финальном MVP-наборе. CONTEXT.md — `.planning/phases/07-anti-dpi-suite-wireguard-family/07-CONTEXT.md`. Wiki decision logs: `wiki/openvpn-deferral-2026.md`, `wiki/wireguard-deferral-2026.md`, `wiki/amneziawg-deferral-2026.md`. | ✅ **Phase 7 Closed 2026-05-14** (Phase 7a only — commits `8ca1014` + `1d98abc` + `cb6140b` + `49c40d5` + `674409b` + `e923e60` + closure). Phase 7b cancelled. PROTO-06/07/09 + DPI-04 → Out of Scope (v2.0+ conditional on demand). Wave 3 mux infra → Phase 10 unified PR. TUIC connection device-UAT carved-out. **Next:** Phase 8 (Rules Engine + Split tunneling, v0.8). |

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

| **R21: Phase 8 — Rules Engine + Split tunneling (D-01..D-13)** (decided 2026-05-15, Codex threads `019e2841` Area A + `019e284c` Area D) | D-01: sing-box `route.rule_set` binary SRS pipeline (server-compiled, auto-reload since 1.10.0) — единственный performant option без client MMDB. D-04: server-side country→CIDR expand (no MaxMind на клиент). D-07: two-file Ed25519 detached sig. **D-08/D-09**: RULES-11 (macOS per-app routing via NEAppProxyProvider L4) → Out of Scope v0.10+ conditional: L4↔L3 mismatch + NETunnelProviderManager/NEAppProxyProviderManager mutual exclusivity + R1 break (SOCKS5 bridge). AppProxyExtension-macOS target deleted. D-12: cold-start non-blocking (DEC-06d-01 pattern). D-13: sequential mirror failover (DEC-06d-04). Invariant gates: R8 (no inline rule_set in template), R12 (no placeholder pubkey bytes), D-08 (no NEAppProxyProvider). Full decision log: `wiki/rules-engine.md` § D-01..D-13. Deferral doc: `wiki/appproxy-deferral-2026.md`. | ✅ **Phase 8 implementation complete 2026-05-15** — UAT pending (M-04 BGAppRefreshTask wall-time; M-05 real domain blocking; M-07 split-tunnel country resolve; M-08 min_app_version sheet UX) — all on iPhone iOS 18+ test device. RULES-01..10 + CORE-05: implementation complete. RULES-11: Out of Scope per D-08. **Next:** `/gsd-verify-work 8` after UAT, then Phase 9 Deep Links. |

---
*Last updated: 2026-05-15 — Phase 8 ✅ **Implementation complete** (Rules Engine + Split tunneling). RULES-01..10 + CORE-05: implementation complete, UAT pending. RULES-11: Out of Scope per D-08 (AppProxy L4↔L3 mismatch, `wiki/appproxy-deferral-2026.md`). New SwiftPM package `RulesEngine`: swift-crypto Ed25519 + HTTPS mirror failover + SRS atomic write + BGAppRefreshTask/NSBackgroundActivityScheduler. Wiki synced: `rules-engine.md` полная перезапись (D-01..D-13), `architecture.md`, `security-gaps.md` R20. `validate-r1-r6.sh` extended: R8/R8b/RULES-02/R12/D-08 gates.*

*Phase 7 history: Phase 7 fully ✅ **Closed** (Phase 7a Closed + Phase 7b Cancelled + Phase 7c Engine Boundary Cleanup Closed). PROTO-08 + DPI-01 + DPI-02 + DPI-07 → Validated. PROTO-06 + PROTO-07 + PROTO-09 + DPI-04 → Out of Scope (v2.0+ conditional). 6 in-scope протоколов в финальном MVP-наборе. **Phase 7c (HYBRID per Codex production-evidence):** sing-box код контейнеризован в `PacketTunnelKit/SingBox/` namespace + decision document `EngineAbstractionDecision.md` с триггерами для будущего `protocol TunnelEngine` (без premature abstraction); архитектура остаётся mono-engine sing-box. См. [[engine-abstraction-decision-2026]] + R20. Next: Phase 8 (Rules Engine + Split tunneling, v0.8).*
