# Phase 1 W5 Device Debug — Session 2026-05-11

**Status**: Partial pass. Commit `0299af6`.
**Tests**: 39/39 PacketTunnelKit green.

## Scope

Manual device test (W5-T4 DoD #1) — VLESS+Reality+Vision на iPhone 16 iOS 26, сервер `185.237.218.81:25871` (Latvia, Friendhosting).

## Что починено (5+ closed blockers)

1. **sing-box log injection + App Group bridge.** Diagnostic `log.output` пишется в App Group. Main app копирует в свой Documents/ на старте через `AppGroupContainer.exportSingBoxLogToDocuments()`, чтобы Xcode "Download Container" мог его подцепить (App Group containers не выкачиваются напрямую через Devices GUI).

2. **sing-box 1.13 `action: sniff` обязателен.** `expandConfigForTunnel` теперь инжектит `{action: sniff}` первым правилом в route.rules. Без него `protocol: dns` matcher не работает → DNS UDP падает на `vless-out (network=tcp)` → `"UDP is not supported"` → весь резолв мёртв.

3. **DNS pipeline rebuild — Hiddify-canonical.** См. `wiki/dns-pipeline-decisions.md` для деталей. Структура:
   - `fakeip` server (CGNAT `100.64.0.0/10`, не конфликтует с TUN `198.18.0.1/30`)
   - `dns-bootstrap` (`tcp://77.88.8.8` Yandex direct — TSPU-safe в РФ)
   - `dns-remote` (DoH `cloudflare-dns.com` через `vless-out` как fallback)
   - Rules: `outbound:any→bootstrap` + `HTTPS/SVCB→NXDOMAIN` + `A/AAAA→fakeip`

4. **`route.rules action: resolve`** (sing-box v1.9+). Sing-box делает client-side resolve через bootstrap **до** VLESS serialization. VLESS header теперь несёт IP, не hostname (identical к Apple Push working path).

5. **Outbound tuning.** Убран `packet_encoding: xudp` (hiddify/hiddify-app#758: Hiddify экспортирует empty для Vision+TCP); MTU TUN 1400→9000 (Hiddify default; лучше доставка cert chains).

## Что работает ✓

- Туннель стабильно `NEVPNStatus.connected` на iPhone iOS 26
- DNS pipeline резолвит через fakeip + bootstrap
- Reality+Vision handshake к серверу Latvia проходит
- ~50% VLESS соединений (117/240 в последнем тесте) завершаются полным `download finished` + `upload finished`
- Apple iCloud, Telegram, Google services backbone трафик ходит через туннель

## Что НЕ работает ✗

- **Safari → любой user HTTPS** (`api.ipify.org`, любые Cloudflare-anycast destinations) → ошибка «не удалось установить безопасное соединение»
- TCP к destination через VLESS открывается, **TLS handshake между app↔site через туннель не доходит до завершения**
- ~50% соединений закрывается без полного data exchange

## Главная гипотеза (неподтверждённая)

**sing-box client Vision implementation incompatibility с Xray-core server-side Vision.**

Доказательство: **Happ** (форк sing-box-for-apple с собственными Hiddify-патчами) с **тем же VLESS URI**, на **том же iPhone**, в **той же сети** — работает корректно. Значит:
- Сервер OK
- Reality keys OK
- ТСПУ не виноват
- Сеть OK
- → проблема **в клиентской реализации Vision**

Related GitHub issues 2025-2026:
- [SagerNet/sing-box#4023](https://github.com/SagerNet/sing-box/issues/4023) — Reality/VLESS handshake OK, TLS не завершается
- [XTLS/Xray-core#5966](https://github.com/XTLS/Xray-core/issues/5966) — TLS EOF после успешного Vision setup
- [hiddify/hiddify-app#758](https://github.com/hiddify/hiddify-app/issues/758) — Hiddify config workarounds

## Что исключено (быстрые гипотезы)

- ❌ Не TSPU (Happ работает с тем же URI)
- ❌ Не DNS (fakeip pipeline работает, real IPs приходят)
- ❌ Не сервер (TCP connect OK, Reality handshake OK, Apple traffic работает)
- ❌ Не MTU (9000 не дал значимого изменения relative to 1400)
- ❌ Не `packet_encoding: xudp` (его удаление не помогло)
- ❌ Не DoH (плейн TCP/53 даёт идентичный паттерн)

## Следующие шаги — три опции

Зафиксированы в `~/.claude/projects/.../memory/project_phase1_next_options_2026-05-11.md`.

### Опция А — pause, accept partial pass
Закоммитить (✓ сделано — `0299af6`), open issue в Phase 5 backlog, использовать Happ как short-term VPN-client.

### Опция Б — trace-level sing-box log [ВЫБРАНА ПОЛЬЗОВАТЕЛЕМ ПЕРВОЙ]
Поменять `log.level` с `"debug"` на `"trace"` в `expandConfigForTunnel`. Собрать огромный лог (десятки MB). Grep на `vless`/`reality`/`tls`/`EOF`/`ERROR`/`closed`/`reset`. Сравнить trace для рабочего Apple destination vs неработающего Cloudflare. Effort: 30-60 минут + 1 device cycle.

### Опция В — Hiddify-Next bit-by-bit diff [FALLBACK ПОСЛЕ Б]
Clone `github.com/hiddify/hiddify-next` (или `hiddify-app`). Найти Dart/Flutter код, генерирующий sing-box JSON для VLESS+Reality+Vision. Сгенерировать на их side тот же URI. Diff с нашим. Применить все расхождения. Effort: 2-4 часа research + 1-2 device cycles.

## Files modified (commit 0299af6)

- `BBTB/App/iOSApp/BBTB_iOSApp.swift` — вызов `exportSingBoxLogToDocuments()` в init
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift` — `singBoxLogPath` + `exportSingBoxLogToDocuments()`
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` — передача `logPath` в expand
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json` — DNS+route blocks rebuild, убран `packet_encoding`
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift` — `logPath` param, sniff injection, default MTU 9000
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift` — default MTU 9000
- Тесты: SingBoxConfigLoaderTests + TunnelSettingsTests
- `wiki/dns-pipeline-decisions.md` (new)
- `wiki/vless-reality.md` (Vision incompatibility candidate section)
