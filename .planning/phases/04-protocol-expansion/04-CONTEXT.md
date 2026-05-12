# Phase 4: Protocol expansion — Context

**Gathered:** 2026-05-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Финализировать поддержку протоколов в v0.4:

1. **VLESS+TLS (без Reality)** — handler для всех `vless://` URI с `security=tls` (без `pbk`/`sid`). Vision (`flow=xtls-rprx-vision`) — частный случай, `flow` опциональный. Максимально широкое покрытие.
2. **Shadowsocks-2022** — handler для `ss://` SIP002 URI со всеми `2022-blake3-*` методами (`aes-128-gcm`, `aes-256-gcm`, `chacha20-poly1305`), а также legacy SS методами (`aes-256-gcm`, `chacha20-ietf-poly1305` и т.д.).
3. **Hysteria2** — handler для `hy2://` / `hysteria2://` URI. Единственное исключение из R1: `insecure=1` передаётся в `tls.insecure: true` sing-box конфига.
4. **IMP-04 finish** — URI-парсеры для всех трёх новых схем в `ConfigParser`.
5. **IMP-05 finish** — парсинг Outline access keys (стандартный SIP002 `ss://`, уже покрывается SS-handler'ом) и Clash YAML подписок (только секция `proxies:`, маппинг в `AnyParsedConfig`).
6. **isSupported auto-upgrade** — при запуске приложения перепаршиваются все `ServerConfig` с `isSupported=false` + непустым `rawURI` через новые handler'ы; обновляется флаг без реимпорта пользователем.

### Не в скоупе Phase 4

- Транспорты XHTTP, gRPC, HTTPUpgrade для VLESS — Phase 5.
- UI выбора протокола в Расширенных — Phase 10.
- WireGuard, AmneziaWG, TUIC v5, OpenVPN — Phase 7.
- VMess handler — не в roadmap (stub-парсинг уже есть).
- SSH, SOCKS5, NaïveProxy — не в roadmap MVP.

</domain>

<decisions>
## Implementation Decisions

### VLESS без Reality (PROTO-03)

- **D-01:** Новый `AnyParsedConfig.vlessTLS(ParsedVLESSTLS)` case. Охватывает весь спектр VLESS+TLS — и Vision (`flow=xtls-rprx-vision`) и plain VLESS без flow. Решение в пользу максимального покрытия.
- **D-02:** Роутинг в `VLESSURIParser`: если URI содержит `pbk` или `security=reality` → `case vlessReality` (Phase 1, без изменений). Если `security=tls` и нет `pbk`/`sid` → `case vlessTLS`. Если `security=none` → `isSupported=false` (no-TLS VLESS нарушает R1).
- **D-03:** `ParsedVLESSTLS` содержит: `uuid`, `host`, `port`, `flow: String?` (nil если отсутствует), `sni`, `fingerprint`, `alpn`, транспорт (на Phase 4 только `tcp`/`raw` — остальные транспорты Phase 5). Новый Package: `Protocols/VLESSTLSHandler/`.

### Shadowsocks-2022 (PROTO-04)

- **D-04:** Один `ShadowsocksURIParser` для всех `ss://` URI (SIP002: `ss://base64(method:password)@host:port#tag`). Поддерживаемые методы: все `2022-blake3-*` (`aes-128-gcm`, `aes-256-gcm`, `chacha20-poly1305`) + legacy (`aes-128-gcm`, `aes-256-gcm`, `chacha20-ietf-poly1305`, `xchacha20-ietf-poly1305`). Неизвестный метод → `isSupported=false`.
- **D-05:** `AnyParsedConfig.shadowsocks(ParsedShadowsocks)`. `ParsedShadowsocks`: `host`, `port`, `method`, `password`. Новый Package: `Protocols/ShadowsocksHandler/`.
- **D-06:** В sing-box outbound: `type: "shadowsocks"`, `method`, `password`. Для SS-2022 методов — те же поля, sing-box различает их по строке метода.

### Hysteria2 (PROTO-05)

- **D-07:** `AnyParsedConfig.hysteria2(ParsedHysteria2)`. `ParsedHysteria2`: `host`, `port`, `auth` (password), `sni`, `fingerprint: String?`, `obfs: String?`, `obfsPassword: String?`, `allowInsecure: Bool`, `pinSHA256: String?`.
- **D-08:** **Исключение из R1:** `insecure=1` / `allowInsecure=1` / `skip-cert-verify=1` в URI → `allowInsecure: true` в `ParsedHysteria2` → `tls.insecure: true` в sing-box JSON. Единственный протокол с таким исключением — обусловлено реальностью self-hosted Hysteria2 серверов с self-signed сертификатами.
- **D-09:** Поддержка обеих схем: `hy2://` и `hysteria2://` (короткая официальная форма). Multi-port формат в порте (`123,5000-6000`) → `isSupported=false` на Phase 4 (sing-box требует одного порта; multi-port = Phase 7 или позже).
- **D-10:** Новый Package: `Protocols/Hysteria2Handler/`. Sing-box outbound: `type: "hysteria2"`, `server`, `server_port`, `password`, `tls.server_name`, `obfs`.

### Outline access keys (IMP-05 — часть)

- **D-11:** Outline access keys — стандартный SIP002 `ss://` формат. Покрывается `ShadowsocksURIParser` из D-04 без дополнительной логики. `ssconf://` (ссылка на JSON с SS-конфигом) — не в скоупе Phase 4 (обрабатывается как неизвестная схема → `isSupported=false`).

### Clash YAML (IMP-05 — часть)

- **D-12:** Новый `ClashYAMLParser` в `ConfigParser`. Разбирает только секцию `proxies:`. Маппит поддерживаемые типы: `vless` → `ParsedVLESSTLS` (или `ParsedVLESSReality` если есть `reality-opts`), `trojan` → `ParsedTrojan`, `ss` → `ParsedShadowsocks`, `vmess` → `isSupported=false`, `hysteria2` / `hy2` → `ParsedHysteria2`. Секции `rules:`, `proxy-groups:`, `dns:` игнорируются.
- **D-13:** Детектирование Clash YAML в `UniversalImportParser`: строка начинается с `proxies:` или содержит yaml-маркеры (`mixed-port:`, `allow-lan:`) → передаётся в `ClashYAMLParser`. Иначе — обычный URI-пайплайн.

### isSupported auto-upgrade

- **D-14:** При запуске приложения (foreground) `ConfigImporter` сканирует все `ServerConfig` с `isSupported=false` и `rawURI != nil`. Каждый `rawURI` прогоняется через `UniversalImportParser`. Если теперь парсится в `supported` → `isSupported=true` + `outboundJSON` обновляется. Паттерн: запускается как background Task, не блокирует UI. Это решение из Phase 2 D-04 («флаг снимается без реимпорта»).

### Claude's Discretion

- Конкретные sing-box JSON-шаблоны для VLESSTLSHandler, ShadowsocksHandler, Hysteria2Handler — по образцу существующих `SingBoxConfigTemplate.trojan-tcp.json` / `vless-reality.json`.
- Структура тестов — по образцу `VLESSURIParserTests`, `TrojanURIParserTests`, `PoolBuilderSingleOutboundTests`.
- Порядок регистрации handler'ов в `AppDelegate` / startup — по образцу Phase 1/2.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Планирование и требования
- `.planning/ROADMAP.md` — Phase 4 scope, success criteria, requirements mapping
- `.planning/REQUIREMENTS.md` — PROTO-03, PROTO-04, PROTO-05, IMP-04, IMP-05 детали

### Спецификация форматов URI
- `https://github.com/Leadaxe/singbox-launcher/blob/main/docs/ParserConfig.md` — эталонная спецификация URI-форматов (VLESS, SS, Hy2, Trojan, Clash YAML). Алгоритмы и edge cases портируются в Swift по нашей архитектуре (не как dependency). **Обязательно читать перед реализацией парсеров.**

### Существующий ConfigParser (точки расширения)
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/ImportedServer.swift` — `AnyParsedConfig` enum (добавить `.vlessTLS`, `.shadowsocks`, `.hysteria2`); `UnsupportedReason`
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/StubParsers.swift` — `knownSchemes` (ss, hy2, hysteria2 уже есть); Phase 4 заменяет stub-парсинг реальными handler'ами
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift` — точка входа; добавить детектирование Clash YAML
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` — добавить case'ы для трёх новых `AnyParsedConfig` вариантов

### Существующие protocol handler'ы (образцы)
- `BBTB/Packages/Protocols/Trojan/Sources/Trojan/TrojanHandler.swift` — паттерн для новых handler packages
- `BBTB/Packages/Protocols/VLESSReality/` — паттерн + sing-box JSON-шаблон
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json` — образец шаблона

### Существующие URI-парсеры (образцы)
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift` — паттерн для VLESS-роутинга (reality vs tls); `${VLESS_FLOW}` placeholder
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift` — паттерн для URI-парсера

### Архитектурные решения
- `.planning/phases/02-trojan-import-flow/02-CONTEXT.md` — D-04 (isSupported=false + rawURI для upgrade), D-08 (R1: allowInsecure=1 ignored for Trojan; Phase 4 делает исключение только для Hysteria2)
- `wiki/security-gaps.md` — R1 принцип (TLS strict), R8 (libbox integration)

### Data model (SwiftData)
- `BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift` — `isSupported: Bool`, `rawURI: String?`, `outboundJSON: String?` — поля для auto-upgrade

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `StubParsers.knownSchemes` уже включает `"ss"`, `"hy2"`, `"hysteria2"` — Phase 4 заменяет stub на реальные парсеры
- `StubParsers.parseAsUnsupported(_:)` — fallback для неизвестных схем остаётся без изменений
- `PoolBuilder.buildSingBoxJSON(from:)` — добавить 3 новых `case` в `switch parsed { ... }`; degenerate path (1 outbound) и urltest path уже работают
- `ServerConfig.rawURI` + `isSupported` — уже в схеме; Phase 4 использует для auto-upgrade (D-14)

### Established Patterns
- **Package-per-handler** — `Protocols/Trojan/`, `Protocols/VLESSReality/` → Phase 4 добавляет `VLESSTLSHandler`, `ShadowsocksHandler`, `Hysteria2Handler` по той же структуре
- **JSON-шаблоны** — `SingBoxConfigTemplate.*.json` в Resources bundle каждого Protocol package
- **URI-парсер тесты** — `VLESSURIParserTests.swift`, `TrojanURIParserTests.swift` → образцы для новых тестов
- **SwiftData lightweight migration** — уже применялась в Phase 1→2→3; Phase 4 не меняет схему (только заполняет `isSupported` + `outboundJSON` для ранее stub-записей)

### Integration Points
- `UniversalImportParser` → добавить Clash YAML detection branch
- `PoolBuilder` → добавить `.vlessTLS`, `.shadowsocks`, `.hysteria2` case'ы
- `AnyParsedConfig` enum → 3 новых case'а
- `ConfigImporter.importFromRawInput` (или startup hook) → запуск auto-upgrade Task при foreground

</code_context>

<specifics>
## Specific Ideas

- **Leadaxe парсер** — использовать как спецификацию форматов и edge cases (не как dependency): `docs/ParserConfig.md` разделы VLESS, SS, Hysteria2. Алгоритмы портировать в Swift.
- **Максимальное покрытие VLESS** — явный приоритет пользователя: не ограничивать только Vision, брать любой VLESS+TLS без Reality.
- **Hysteria2 insecure** — единственный протокол с исключением из R1, прецедент для других протоколов не создаётся.

</specifics>

<deferred>
## Deferred Ideas

- `ssconf://` (Outline JSON config URL) — обрабатывается как неизвестная схема → `isSupported=false`. Возможно Phase 6+ если появится запрос.
- Multi-port Hysteria2 (`port: 123,5000-6000`) — `isSupported=false` на Phase 4. Phase 7 или отдельный тикет.
- VMess handler — не в roadmap MVP, stub остаётся.
- VLESS транспорты (XHTTP, gRPC, HTTPUpgrade, WebSocket для VLESS) — Phase 5.

</deferred>

---

*Phase: 4-protocol-expansion*
*Context gathered: 2026-05-12*
