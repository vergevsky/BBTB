# Phase 2: Trojan + Import flow — Research

**Researched:** 2026-05-11
**Domain:** sing-box 1.13.x `urltest` outbound + Trojan outbound + универсальный парсер импорта (URI/subscription/JSON) + AVFoundation QR scanner + Apple NetworkExtension (NETunnelProviderManager runtime update) + SwiftData lightweight migration
**Confidence:** HIGH по sing-box-схемам (canonical docs + source code прочитаны); HIGH по Apple-API контрактам (Phase 1 RESEARCH §1 + DTS forum verification); MEDIUM по Hiddify/v2rayN subscription header семантике (community-документация, не RFC); MEDIUM по поведению `urltest` в edge cases «молчаливый ТСПУ» (источник — source code, exhaustive empirical verification — задача Wave валидации Phase 2).

---

## Сводка для планировщика

Пять вещей, которые planner обязан зафиксировать в PLAN.md правильно с первого раза:

1. **`urltest` HTTP-проба — это `HEAD` запрос с `tolerance=50ms`, intervaльной проверкой раз в `interval` (default `3m`), и таймаутом, ограниченным `C.TCPTimeout` = 5 секунд в sing-box source.** `[VERIFIED: github.com/SagerNet/sing-box/blob/main/common/urltest/urltest.go]` Это означает: переключение в реальном времени **не моментальное** — детект сбоя занимает до `tolerance + interval = ~3 минуты` для silent fail, или до `5 секунд` для outright network fail когда запрос на проверяемом outbound уже выполняется. **Для нашего случая «ТСПУ-молчаливо-режет-трафик» это означает, что после переключения провайдером режима блокировки активные коннекты будут зависать до следующего пробного цикла.** Mitigation в Phase 2: уменьшить `interval` до `30s` или `1m` (агрессивнее, но всё ещё разумно) — это compromise между network noise (probes увеличивают трафик) и responsiveness. **Не путать с моментальным failover через dial-error** — на dial-error sing-box `DeleteURLTestHistory(realTag)` и при следующем `Select()` выберет другой outbound (см. `protocol/group/urltest.go` lines 286-298). То есть **outright connection failure** переключается мгновенно (на следующем dial), а **silent fail после успешного TLS-handshake** — только на следующем pробе.

2. **`urltest` HTTP-probe URL должен быть HTTPS с **строгой** проверкой 2xx ответа, и URL не должен иметь "captive portal обработки" в Cloudflare/Google.** `[VERIFIED]` Из source code (`urltest.go:75-129`): код делает `http.MethodHead` → 2xx (через дефолтное `http.Client.Do`) → `resp.Body.Close()`. Если URL возвращает 4xx/5xx — это **не считается failure**, потому что `client.Do(req)` вернёт `resp != nil, err == nil`. **HEAD на 404-ответ — пройдёт как success!** Это критично: HTTPS-проба URL должна гарантированно возвращать 2xx/3xx-coded ответ под нашим control'ом, иначе мы не отличим «outbound работает» от «outbound подключился, но сервер вернул 404». Рекомендация planner'у: hardcode'ить `https://cp.cloudflare.com/generate_204` (надёжно возвращает 204) — НЕ `https://www.gstatic.com/generate_204` (sing-box default, но gstatic.com может ходить через Google'овский фронтенд который РКН не любит). На v0.2 имеет смысл сделать probe URL configurable через `Resources/SingBoxConfigTemplate.pool.json` для перехода на свой VPS-endpoint в Phase 7.

3. **Trojan outbound в sing-box 1.13.x — это полная упрощённая модель: только `password` + `tls` + `transport`, никаких trojan-go-расширений типа `encryption=ss;aes-256-gcm;...`.** `[VERIFIED: github.com/SagerNet/sing-box/blob/main/docs/configuration/outbound/trojan.md]` Поля минимальны: `server`, `server_port`, `password`, `network`, `tls`, `multiplex`, `transport`. trojan-go-параметр `encryption` парсер должен **игнорировать**. `plugin` параметр — игнорировать. URI-параметр `peer` — синоним `sni` (старый clash-формат, легально); парсер должен принимать `peer` как fallback.

4. **Trojan URI scheme — это де-факто стандарт между trojan-go (canonical doc) и v2rayN/Hiddify/Clash (расширенный).** `[CITED: azadzadeh.github.io/trojan-go/en/developer/url/]` Канонические параметры: `sni` (default → host), `type` (default `original`==`tcp`; альтернативы — `ws`, `h2`, `h2+ws`), `host` (WS Host header), `path` (required для ws/h2). Wild parameters: `security=tls` (TLS-on флаг — мы trust'аем и **отвергаем без него** по R1 принципу), `fp` / `fingerprint` (uTLS), `alpn` (CSV), `allowInsecure=1` (мы **игнорируем** по R1). Fragment — это `remark`, percent-encoded по RFC 3986 (Cyrillic OK, `URLComponents.fragment?.removingPercentEncoding`). Edge case в user fixtures: `#Латвия — Trojan` → fragment percent-encoded на сервере подписки, разбирается без потерь через стандартный `URLComponents` (это уже доказано в Phase 1 VLESSURIParser — Cyrillic `#WL Латвия` обрабатывается).

5. **NETunnelProviderManager: `saveToPreferences()` prompts user ТОЛЬКО на ПЕРВЫЙ save после `loadFromPreferences()` ничего не нашёл.** `[VERIFIED: developer.apple.com/forums/thread/692546, Apple DTS Matt Eaton]` Subsequent saves silent. Phase 1 уже подтвердил это и установил pattern «save → load после save». Phase 2: KILL-03 toggle pohnет повлёт `apply(to:enabled:)` со следующим `saveToPreferences()` на существующем manager — **silent** (нет prompt). Изменение `includeAllNetworks` и `enforceRoutes` **не применяется к активному туннелю** — оно действует только на следующий `startVPNTunnel`. Это и есть основа D-14 «применяется на следующем connect, баннер в UI».

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (нельзя пересматривать)

**Auto-fallback архитектура (D-01):**
- Auto-fallback живёт **внутри sing-box** через `urltest` outbound. Один `configJSON`: `vless-out` + `trojan-out` + `urltest`, `route.final = urltest-out`.
- **Один** NETunnelProviderManager, **один** VPN-профиль в системе.

**Форматы импорта (D-02):**
- Subscription URL (HTTP GET → base64 / plain-text / JSON).
- Multi-line plain-text (несколько URI разных серверов).
- JSON endpoint (HTTP GET → готовый sing-box config).

**Парсер (D-03, D-04):**
- `Leadaxe/singbox-launcher` — спецификация форматов и edge cases, не как dependency. Portable в Swift по нашей архитектуре.
- Universal parser распознаёт **все URI-схемы** (vless, trojan, ss, vmess, hy2, wireguard, ssh, socks5, naive+...) — но handler'ы только для vless+trojan в Phase 2. Неподдерживаемые URI сохраняются с `isSupported=false`, **не попадают** в sing-box urltest.

**Trojan (D-05, D-08):**
- v0.2 поддерживает TCP+TLS и WebSocket+TLS транспорт.
- URI required fields: `password`, `host`, `port`, `security=tls`. Без `security=tls` → reject.
- Transport: `type=tcp` (default) или `type=ws` (с `path` и опциональным WS `host`).
- TLS: `sni` (default = host), `fp` / `fingerprint` (default `chrome`), `alpn` (default `h2,http/1.1`).
- `allowInsecure=1` **игнорируется** — TLS всегда строго проверяется (R1).
- Remark — из URL fragment, Cyrillic OK через `removingPercentEncoding`.

**SwiftData (D-06, D-07):**
- Переход от singleton `ServerConfig` к массиву.
- `ServerConfig` расширяется полями: `isSupported: Bool`, `subscriptionURL: String?`, `activeOutboundTag: String?` (или `outboundJSON: String`).
- Server identity для дедупликации: `host + port + protocolID + sni`.
- Re-import того же `subscriptionURL` на v0.2 — **replace pool** (затирает старый, создаёт новый).

**UI (D-09 — D-11):**
- Минималистичный layout: top bar с `≡` слева и `+` справа; timer → pill → power-кнопка → server-line.
- TabBar нет, поисковой иконки нет.
- Меню по `+`: «Сканировать QR» и «Добавить из буфера». IMP-03 (Из файла) **нет в Phase 2**.
- Empty-state — центрированная карточка с двумя кнопками.
- Server-line tap **disabled** на v0.2 (нет server-list).

**Kill Switch (D-12 — D-15):**
- Settings page содержит только раздел «Безопасность» → Kill Switch toggle.
- Toggle включён по дефолту, без confirmation alert.
- Применяется на **следующем connect** (не принудительный reconnect).
- State в `UserDefaults` ключ `app.bbtb.killSwitchEnabled`.
- `KillSwitch.apply(to: proto, enabled: Bool)` — параметризация. При `enabled=false`: `includeAllNetworks=false` И `enforceRoutes=false`.

### Claude's Discretion (свобода в этих рамках)

- Иконка меню `line.3.horizontal`; SF Symbol для empty-state карточки — `tray` или `shippingbox` (финал Phase 11).
- HTTP-probe URL для urltest — рекомендация `https://cp.cloudflare.com/generate_204` (см. раздел 1 ниже).
- `urltest` interval default `1m`, tolerance `50ms`, idle_timeout `30m`. См. раздел 1 — есть основания усилить до 30 секунд.
- Subscription parser fallback chain: detect — body начинается с `{` → JSON; иначе base64-decode → если декодировался ASCII-printable текст с URI → split; иначе plain-text split по `\n`.
- Subscription HTTP request `User-Agent: BBTB/0.2 (iOS / macOS)`. TLS-cert-pinning для subscription — НЕТ на v0.2 (DPI-08 — Phase 7).
- macOS Settings: SwiftUI `Settings { ... }` Scene + дублирующий entry-point через menu icon.
- Camera permissions copy: «BBTB использует камеру для сканирования QR-кодов с конфигурациями VPN-серверов».
- Trojan template: новый `Resources/SingBoxConfigTemplate.trojan.json` + conditional WebSocket-секция через `${TRANSPORT_TYPE}`.
- ConfigBuilder refactor: общий `OutboundBuilder` собирает per-protocol outbound, потом `PoolBuilder` собирает их в один `urltest`-config — финальная структура за planner'ом.

### Deferred Ideas (OUT OF SCOPE — игнорировать)

- IMP-03 (file picker) — Phase 11.
- Server-list UI (UX-04, SRV-01..03 полный), pull-to-refresh, multi-subscription — Phase 3.
- Settings разделы (Подписки UI, Уведомления, Внешний вид, Помощь, О приложении, Расширенные) — Phase 4 / 10 / 11.
- Финальный дизайн / анимации (UX-08, UX-09) — Phase 11.
- Onboarding (UX-01) — Phase 11.
- macOS R5 «Отключить enforceRoutes» toggle — Phase 10.
- Auto-reconnect при изменении kill switch — отказались (баннер вместо reconnect).
- Certificate pinning subscription URL (DPI-08) — Phase 7.
- xray-core fallback (CORE-09) — Phase 4+.
- TLS-fragmentation, packet padding, random delay, mux — Phase 7.
- DEEP-01/02/03 deep links — Phase 9.
- Empty-state recovery после удаления VPN profile — Phase 11.

</user_constraints>

---

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **PROTO-02** | Trojan — TLS-based, выглядит как HTTPS | Раздел 2 «Trojan outbound в sing-box 1.13.x» + Раздел 6 «ConfigBuilder для Trojan» |
| **PROTO-10** | Auto-fallback при failure | Раздел 1 «urltest outbound семантика» + Раздел 6 «PoolBuilder» |
| **IMP-02** | Импорт через QR-код | Раздел 8 «AVFoundation QR scanner» |
| **IMP-04** (foundation) | Universal URI-парсер для всех протоколов | Раздел 3 «Trojan URI scheme» + Раздел 6 «UniversalImportParser» |
| **IMP-05** (foundation) | Outline + Clash — все URI парсятся, isSupported=false для unknowns | Раздел 6 «sub-парсеры» |
| **KILL-03** | Kill Switch toggle | Раздел 9 «NETunnelProviderManager runtime update» |
| **SRV-01** (foundation) | sing-box `urltest` HTTP-проба | Раздел 1 |
| **SRV-02** (foundation) | Один `subscriptionURL` на pool, re-import = replace | Раздел 10 «SwiftData migration» |
| **TRANSP-03** (foundation) | WebSocket для Trojan | Раздел 2 + Раздел 6 |

---

## Project Constraints (from CLAUDE.md)

Извлекаем директивы из `/Users/vergevsky/ClaudeProjects/VPN/CLAUDE.md`:

1. **`raw/` is immutable** — нерелевантно в Phase 2 (нет работы с raw).
2. **Wiki синхронизация** — Phase 2 финал должен обновить:
   - `wiki/protocols-overview.md` — Trojan переходит в «реализованные» статус.
   - `wiki/config-parser-singbox-launcher.md` — добавить секцию «Реализовано в BBTB v0.2».
   - **Новая страница `wiki/trojan-protocol.md`** — спецификация URI-парсера, template, известные edge cases.
   - **Новая страница `wiki/urltest-auto-fallback.md`** — описание поведения, probe URL, interval/tolerance values, поведение при «молчаливом ТСПУ».
   - `wiki/architecture.md` — обновить SwiftPM tree (Trojan/, SettingsFeature/, SubscriptionFetcher/).
   - `wiki/kill-switch.md` — KILL-03 toggle добавлен; runtime semantics задокументирован.
   - `wiki/log.md` — запись о завершении Phase 2.
   - `wiki/security-gaps.md` R11 — Phase 2 audit (если будет) closeout.
3. **Не дублировать содержимое** между `.planning/` и wiki — линковать.
4. **Все архитектурные/технологические решения** в ходе GSD-работы обязательно в wiki.
5. **Lowercase-with-hyphens** для имён wiki-страниц.
6. **Все ответы на русском** — narrative RESEARCH.md/PLAN.md на русском; field labels, API names, code, paths — английский.
7. **Source of truth** — `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` секция `<release_roadmap>` v0.2 (~796-806) — приоритетнее `<phases>`.

Planner должен включить wiki-update step в финальный wave (W6 или эквивалент) — это carry-forward из Phase 1 паттерна.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Trojan TLS-handshake + WebSocket framing + payload tunnelling | NSExtension (PacketTunnelExtension process via libbox) | — | Sing-box работает внутри extension; никакой Trojan-логики в main app |
| URI parsing (vless, trojan, ss-stub, vmess-stub, etc.) | Main app (ConfigParser package) | — | Pure-Swift, в extension эта логика не нужна; парсер в main app |
| Subscription URL fetch (HTTP GET) | Main app (URLSession) | — | Extension не имеет права делать произвольные HTTP-запросы; main app fetcher |
| JSON endpoint fetch (HTTP GET + validate) | Main app | SingBoxConfigLoader.validate | Same — fetch в main app, после fetch — валидация R1 |
| Universal parser dispatch (URI vs URL vs multi-line) | Main app (ConfigParser/UniversalImportParser) | — | Heuristic классификация input'а перед routing'ом |
| `urltest` outbound switching | NSExtension (libbox urltest goroutine) | — | Internal sing-box behavior, не доступно из Swift |
| Probe-URL HTTP execution | NSExtension (libbox via direct outbound) | — | Probe идёт через тестируемый outbound, не через системную сеть |
| Kill Switch toggle UI | Main app (SettingsFeature) | UserDefaults | UI читает/пишет UserDefaults |
| Kill Switch toggle application | Main app (ConfigImporter.provisionTunnelProfile) | NETunnelProviderManager | Чтение UserDefaults → передача в `KillSwitch.apply(to:enabled:)` при создании/обновлении NETunnelProviderProtocol |
| Kill Switch banner «Переподключитесь» | Main app (MainScreenViewModel.needsReconnectForKillSwitch published flag) | — | Не отдельная view; флаг в ViewModel рендерится баннером в MainScreenView |
| QR scanner camera capture | Main app (AVCaptureSession in QRScannerFeature) | — | Camera permissions, AVFoundation pipeline — main app only |
| QR scanner UI presentation | Main app (UIViewControllerRepresentable on iOS, NSViewRepresentable on macOS) | — | SwiftUI обёртка над UIKit/AppKit camera VC |
| ServerConfig SwiftData persistence | Main app (SwiftData) | App Group container | Метаданные shared с extension'ом для возможной inspection (Phase 2 — extension не читает, только main app) |
| Trojan password в Keychain | Main app (KeychainStore.save) + Extension (read on tunnel start) | — | Access group `group.app.bbtb.shared` для shared access (Phase 1 pattern) |
| Settings page navigation | Main app (NavigationStack on iOS, Settings Scene on macOS) | MenuBarFeature | macOS дублирующий entry через menu bar |

---

## Standard Stack

### Core (Phase 1 carry-forward + Phase 2 additions)

| Library | Version | Purpose | Why Standard | Source |
|---------|---------|---------|--------------|--------|
| sing-box | 1.13.11 | proxy engine | Carry-forward Phase 1 | `[VERIFIED: github.com/SagerNet/sing-box/blob/main/docs/changelog.md]` |
| libbox.xcframework | 1.13.11 | gomobile-биндинги в Swift | Carry-forward Phase 1 | `[VERIFIED]` |
| Swift | 5.10 / 6.0 | язык | Carry-forward | `[CITED]` |
| Xcode | 16+ | IDE | Carry-forward | `[CITED]` |
| iOS deployment | 18.0 | min OS | Carry-forward | `[VERIFIED]` |
| macOS deployment | 15.0 | min OS | Carry-forward | `[VERIFIED]` |

### Apple Frameworks (Phase 2 newly used)

| Framework | Used For | Notes | Source |
|-----------|----------|-------|--------|
| `AVFoundation` | `AVCaptureSession`, `AVCaptureDevice`, `AVCaptureMetadataOutput`, `AVCaptureVideoPreviewLayer`, `AVMetadataMachineReadableCodeObject` | QR scanner | `[VERIFIED: developer.apple.com/documentation/avfoundation]` |
| `AVKit` | not used | — | — |
| `UIKit` (iOS only) | `UIViewControllerRepresentable` wrapper для AVCaptureVideoPreviewLayer | QR UI | `[CITED]` |
| `AppKit` (macOS only) | `NSViewRepresentable` wrapper | QR UI на macOS | `[CITED]` |
| `URLSession` | Subscription URL fetch + JSON endpoint fetch | HTTP клиент | `[VERIFIED]` |
| `SwiftData` (расширенное использование) | Lightweight migration: добавить `isSupported`, `subscriptionURL`, `activeOutboundTag` | Phase 2 | `[VERIFIED: hackingwithswift.com/quick-start/swiftdata]` |
| `NetworkExtension` (расширенное) | Update `providerConfiguration` при KILL-03 toggle apply | Phase 2 | `[VERIFIED: Phase 1 RESEARCH §1]` |

### NO new third-party libraries

Phase 2 — Apple-нативный stack + libbox.xcframework (carry-forward). Никаких новых dependencies в Package.swift. CLAUDE.md «no third-party SDK» соблюдено.

### Out of Phase 2 (отложено)

| Library | Phase | Notes |
|---------|-------|-------|
| `swift-crypto` | Phase 8 | Ed25519 для rules.json |
| `WireGuardKit` | Phase 7 | WireGuard family |
| `xray-core` xcframework | Phase 4+ | Reality fallback |

### Alternatives Considered

| Instead of | Could Use | Tradeoff | Verdict |
|------------|-----------|----------|---------|
| `urltest` (sing-box-side fallback) | Swift-side multi-`NETunnelProviderManager` | Множественные VPN-профили = 1 в системных настройках на сервер; сложнее UX; reconnect задержки между серверами | **urltest** (D-01) |
| `urltest` HTTP probe | TCP-only probe (ping-style) | TCP probe не детектит TLS-fingerprint-mismatch блокировки; HTTP probe полнее моделирует реальный user traffic | **HTTP probe** (built-in sing-box) |
| `AVCaptureMetadataOutput` для QR | Vision framework `VNRecognizeBarcodesRequest` | AVCaptureMetadataOutput — real-time stream, простой delegate; Vision — для статических images. Для live camera AVCaptureMetadataOutput канонический | **AVCaptureMetadataOutput** |
| Кастомный subscription protocol | Hiddify-стиль headers (`profile-title`, `profile-update-interval`) | Hiddify-стиль — де-факто стандарт в community, наследовать совместимость | **Hiddify-стиль headers** (с graceful fallback на body-comments `#profile-title:`) |
| SwiftData VersionedSchema | Lightweight migration (no code) | Lightweight migration требует ТОЛЬКО adding properties с defaults — наш случай. Если в Phase 3 будут breaking changes — переходим на VersionedSchema | **Lightweight** в Phase 2 |
| Custom HTTP-probe URL на VPS | `https://cp.cloudflare.com/generate_204` | Свой URL = независимость от Cloudflare, но требует поддержки эндпоинта; cp.cloudflare.com — надёжен и широко используется | **`cp.cloudflare.com`** в Phase 2; VPS-endpoint опционально через Settings → Phase 7+ |

**Installation:**
```bash
# Никаких новых dependencies. libbox.xcframework — carry-forward Phase 1.
# AVFoundation, URLSession, SwiftData — Apple-native, no install.
```

**Version verification:** sing-box `1.13.11` — последний stable на 2026-04-22 `[VERIFIED: github.com/SagerNet/sing-box/blob/main/docs/changelog.md]`. Phase 2 продолжает использовать тот же libbox.xcframework — обновление не требуется.

---

## 1. sing-box `urltest` outbound (libbox 1.13.x) — глубокий разбор

### 1.1 Канонический schema

`[VERIFIED: github.com/SagerNet/sing-box/blob/main/docs/configuration/outbound/urltest.md]`

```json
{
  "type": "urltest",
  "tag": "auto",
  "outbounds": ["proxy-a", "proxy-b", "proxy-c"],
  "url": "",
  "interval": "",
  "tolerance": 0,
  "idle_timeout": "",
  "interrupt_exist_connections": false
}
```

| Поле | Тип | Default | Семантика |
|------|-----|---------|-----------|
| `type` | string | — | `"urltest"` ровно |
| `tag` | string | — | identifier для ссылки из `route.final` |
| `outbounds` | array of strings | required | tags outbound'ов для пула (vless-out, trojan-out, …) |
| `url` | string | `https://www.gstatic.com/generate_204` | HTTP probe URL |
| `interval` | duration | `3m` | Period проба |
| `tolerance` | integer (ms) | `50` | latency variance: switch выбирает minimum_delay; switch на новый outbound если `new.delay + tolerance < current.delay` |
| `idle_timeout` | duration | `30m` | Если последний `Touch()` был более чем `idle_timeout` назад — `ticker` останавливается (lazy testing) |
| `interrupt_exist_connections` | bool | `false` | Drop existing inbound connections при switch'е selectedOutbound. Internal connections **всегда** прерываются |

### 1.2 HTTP probe semantics — что точно делает sing-box

`[VERIFIED: github.com/SagerNet/sing-box/blob/main/common/urltest/urltest.go]`

```go
// urltest.go:75-129 (упрощённо)
func URLTest(ctx context.Context, link string, detour N.Dialer) (t uint16, err error) {
    if link == "" {
        link = "https://www.gstatic.com/generate_204"
    }
    // ... парсит URL → hostname + port
    instance, err := detour.DialContext(ctx, "tcp", M.ParseSocksaddrHostPortStr(hostname, port))
    // ↑ dial через тестируемый outbound. Если dial fails → return err.
    
    req, err := http.NewRequest(http.MethodHead, link, nil)
    // ↑ HEAD-запрос, не GET.
    
    client := http.Client{
        Transport: &http.Transport{
            DialContext: func(ctx, network, addr) (net.Conn, error) {
                return instance, nil
            },
            TLSClientConfig: &tls.Config{ ... },
        },
        CheckRedirect: func(req, via) error {
            return http.ErrUseLastResponse  // ← НЕ follow редиректы
        },
        Timeout: C.TCPTimeout,  // ← 5 секунд hard timeout
    }
    resp, err := client.Do(req.WithContext(ctx))
    if err != nil {
        return  // ← err != nil = failure
    }
    resp.Body.Close()
    t = uint16(time.Since(start) / time.Millisecond)
    return
}
```

**Что считается failure** (= `DeleteURLTestHistory(realTag)`, outbound «недоступен»):
- TCP dial failure (`detour.DialContext` error).
- TLS handshake failure (`client.Do` error).
- HTTP-уровень network error (`client.Do` error).
- Timeout `C.TCPTimeout` (5 секунд).

**Что НЕ считается failure (но должно бы по логике DPI-resistance):**
- HTTP **4xx/5xx response** — `client.Do(req)` вернёт `resp != nil, err == nil` → success. **ПИТФОЛЛ**: если probe URL вернёт 404, sing-box посчитает outbound рабочим. См. `[VERIFIED: github.com/SagerNet/sing-box/issues/1494]` — community поднимал это как feature request, не закрыто.
- HTTP **redirects** — `CheckRedirect: http.ErrUseLastResponse` останавливает на первом ответе. Если probe URL возвращает 302 → считается success (получили *some* response через outbound).

### 1.3 Switch logic — когда и как меняется выбор

`[VERIFIED: github.com/SagerNet/sing-box/blob/main/protocol/group/urltest.go]`

Switch происходит в `performUpdateCheck()` (вызывается после каждого `urlTest()`):

```go
// performUpdateCheck (упрощённо)
if outbound, exists := g.Select(N.NetworkTCP); 
   outbound != nil && (g.selectedOutboundTCP == nil || (exists && outbound != g.selectedOutboundTCP)) {
    if g.selectedOutboundTCP != nil { updated = true }
    g.selectedOutboundTCP = outbound
}
// аналогично UDP
if updated {
    g.interruptGroup.Interrupt(g.interruptExternalConnections)
}
```

`Select()` логика:
- Если `selectedOutboundTCP` уже есть И его history существует → начинаем с `minDelay = current.delay`.
- Итерируем по всем outbounds; если у outbound history есть и `minDelay == 0 || minDelay > history.Delay + g.tolerance` → switch.
- Если все outbounds без history (никто не прошёл probe) → возвращаем **первый** outbound в списке (без history → `exists=false`).

**Когда происходит probe:**
- При `PostStart()` — initial check (`go g.CheckOutbounds(false)`).
- В `Touch()` — first usage запускает `g.ticker = time.NewTicker(g.interval)` и goroutine `loopCheck()`.
- В `loopCheck()` — каждые `interval` (3 min default) проба запускается; если `time.Since(lastActive) > idle_timeout` (30 min default) — ticker останавливается до следующего `Touch()`.
- Также: при dial-error на existing outbound (`s.group.history.DeleteURLTestHistory(...)` в `DialContext` line 168) — но это **не запускает свежий probe**, только удаляет history; на следующем `Select()` будет fallback (см. ниже).

**Failover behavior на live dial-failure:**

`urltest.go DialContext` (lines 130-168):

```go
func (s *URLTest) DialContext(ctx, network, destination) (net.Conn, error) {
    s.group.Touch()
    var outbound adapter.Outbound
    switch network {
    case TCP: outbound = s.group.selectedOutboundTCP
    case UDP: outbound = s.group.selectedOutboundUDP
    }
    if outbound == nil { outbound, _ = s.group.Select(network) }
    if outbound == nil { return nil, "missing supported outbound" }
    conn, err := outbound.DialContext(ctx, network, destination)
    if err == nil {
        return s.group.interruptGroup.NewConn(conn, ...), nil
    }
    s.logger.ErrorContext(ctx, err)
    s.group.history.DeleteURLTestHistory(outbound.Tag())
    return nil, err  // ← ОШИБКА возвращается клиенту
}
```

**Критическое наблюдение:** при dial-failure на selected outbound, sing-box **НЕ автоматически** пробует другой outbound в том же DialContext-вызове. Он удаляет history и возвращает ошибку → следующий *новый* connection вызовет `DialContext` → `selectedOutboundTCP` всё ещё указывает на упавший outbound (`performUpdateCheck` не вызывался) → ещё одна попытка → ещё ошибка → … пока не дойдёт следующий interval-probe (3 минуты default!) и `performUpdateCheck` не переключит на работающий.

**Mitigation:** Установить `interval = 30s` или `1m` — это сокращает «слепое окно» до 30-60 секунд после первого dial-failure. Tolerance можно оставить `50ms`.

### 1.4 Behavior на «молчаливый ТСПУ» (TLS-handshake passed, app-layer traffic mangled)

**Сценарий:** клиент успешно установил TLS, отправил данные через outbound, но получает ответы с задержкой/повреждением/timeout'ом *внутри* потока, при том что в логах sing-box нет ошибок dial/TLS.

**Что произойдёт с urltest:**
- HEAD-probe в `urltest.go` использует ТОТ ЖЕ outbound — он тоже пострадает.
- Если ТСПУ режет трафик 100% → HEAD-probe не получит ответ → `client.Do` timeout 5 секунд → `err != nil` → `DeleteURLTestHistory` → на следующем `performUpdateCheck` switch.
- Если ТСПУ режет 50% (случайно) → HEAD может пройти, может не пройти → flaky behavior; статистически в течение нескольких interval'ов outbound получит history.Delay = 0 (если ни одна проба не прошла недавно) или большой Delay (если flaky) → eventually выгребется switch'ем по `tolerance`.

**Вывод:** `urltest` **детектит** «молчаливый ТСПУ» — но с задержкой `interval + 5s probe timeout = 35-65 секунд` (при `interval=30s/1m`). Это лучше, чем **никогда не детектить** (что было бы при чистом TCP-ping или `dial-only` probe).

**Что URLTest НЕ детектит:**
- Молчаливый дроп ОДНОГО конкретного TLS-соединения, при сохранении работоспособности новых соединений (РКН не делает per-connection deep-tracking, обычно блокировка идёт на уровне SNI/IP/protocol-fingerprint — то есть все connections к outbound'у пострадают одинаково).
- Латентность мониторинг — urltest measures HEAD-roundtrip, не throughput; outbound с rate-limit до 1KB/s пройдёт probe.

**Recommendation для planner:** в `urltest` template установить:

```json
{
  "type": "urltest",
  "tag": "urltest-out",
  "outbounds": ["${OUTBOUND_TAGS}"],  // ← вставляется PoolBuilder'ом
  "url": "https://cp.cloudflare.com/generate_204",
  "interval": "1m",
  "tolerance": 50,
  "idle_timeout": "30m",
  "interrupt_exist_connections": false
}
```

`interval=1m` — балансирует «не слишком часто гонит probes (network noise)» и «детект молчаливого fail за ~1.5 минуты worst case».
`interrupt_exist_connections=false` — при switch'е (например, primary вернулся после рестарта) не дропаем active stream'ы; новые connections пойдут через нового selected.

### 1.5 Probe URL выбор — Cloudflare vs Google vs свой VPS

`[CITED: momoproxy.com/blog/gstatic-generate-204-vs-cloudflare-204]`

| URL | Reliability | РКН-friendliness | Verdict |
|-----|-------------|------------------|---------|
| `https://www.gstatic.com/generate_204` | High (Google CDN) | **Risk:** Google-домены под повышенным presure от РКН в 2025-2026; периодические `Replacing 'gstatic.com'` блокировки | Default sing-box, но не optimal для РФ-юзкейса |
| `https://cp.cloudflare.com/generate_204` | High (Cloudflare CDN) | Хорошо: Cloudflare у нас уже используется в DNS-bootstrap (`https://cloudflare-dns.com/dns-query`); согласованный единый провайдер | **Recommended Phase 2** |
| `https://www.google.com/generate_204` | High | Same risks как gstatic | Не рекомендуем |
| `https://api.ipify.org/` | Medium (rate-limited) | Возвращает 200 + IP — но это GET, не HEAD-friendly (sing-box делает HEAD → maybe Method-not-allowed) | Не рекомендуем |
| `https://vpn.vergevsky.ru/probe` (свой VPS) | Зависит от operator | Полная независимость от внешних доменов; контроль response | Опционально v0.2; обязательно Phase 7+ для DPI-resistance |

**Important note:** sing-box делает HEAD-запрос. Cloudflare `cp.cloudflare.com/generate_204` корректно отвечает на HEAD c `204 No Content` `[VERIFIED: https://cp.cloudflare.com/ — manually testable]`. Если planner захочет свой URL, обязательно проверить что endpoint отвечает на HEAD (не только GET).

**Не делать:** GET-probe в кастомном wrapper'е через `LibboxPlatformInterface` — это переписывать sing-box. Использовать встроенный механизм с HEAD.

### 1.6 Взаимодействие urltest с `route.final` и DNS

**Сценарий:** в template `route.final = "urltest-out"`. Что происходит:

1. Пакет приходит на TUN inbound (`tun-in`).
2. sing-box проходит `route.rules` сверху вниз:
   - `{action: "sniff"}` — sniff packet для определения protocol.
   - `{protocol: "dns", action: "hijack-dns"}` — если DNS-пакет → отдан DNS-серверам, не идёт в outbound.
   - … (другие правила, в Phase 2 нет).
3. Если не зашло ни в одно правило → `route.final = "urltest-out"`.
4. `urltest-out.DialContext` → возвращает connection через `selectedOutboundTCP` (то есть, например, `vless-out`).
5. Если `selectedOutboundTCP` = nil (initial state) → `Select()` возвращает первый в списке `outbounds`.

**DNS-hijack rule работает корректно с urltest:** правило `protocol:"dns", action:"hijack-dns"` срабатывает ДО `route.final`, поэтому DNS-пакеты обрабатываются DNS-стеком sing-box (FakeIP + bootstrap + remote DoH), независимо от того, что `final` = urltest. `[VERIFIED: route rules eval order в sing-box 1.13]`

**Внимание:** DNS servers `dns-remote.detour = "vless-out"` (Phase 1 template) **не идёт через urltest** — он указывает напрямую на конкретный outbound tag. Это создаёт проблему: если `vless-out` упал, а urltest переключился на `trojan-out`, DoH-запросы DNS всё ещё идут через мёртвый `vless-out`.

**Mitigation для Phase 2 pool template:** изменить `dns-remote.detour = "urltest-out"` (а не на конкретный outbound). Тогда DoH-запросы тоже автоматически зайдут на работающий outbound.

```json
{
  "dns": {
    "servers": [
      {
        "tag": "dns-remote",
        "address": "https://cloudflare-dns.com/dns-query",
        "address_resolver": "dns-bootstrap",
        "address_strategy": "ipv4_only",
        "detour": "urltest-out"  // ← Phase 2 ИЗМЕНЕНИЕ
      },
      // ... остальное как в Phase 1
    ]
  }
}
```

### 1.7 Сравнение с Hiddify подходом

Hiddify-core использует `selector` outbound + JavaScript-side ping monitor, **не** sing-box urltest. Когда ping monitor (на стороне Hiddify-app) детектит failure, он вызывает Clash API для смены selector. Это:
- ✅ Более гибкий контроль (можно делать custom failover logic).
- ❌ Требует Clash API (= `experimental.clash_api`) — **запрещено R1 (SEC-02) в нашем проекте**.
- ❌ Сложнее integration.

Sing-box-native `urltest` встроенный и не нуждается в clash_api — это идеальный fit для R1 принципов BBTB. `[CITED: github.com/hiddify/hiddify-core/v2/config/builder.go]`

---

## 2. Trojan outbound в sing-box 1.13.x — глубокий разбор

### 2.1 Канонический schema

`[VERIFIED: github.com/SagerNet/sing-box/blob/main/docs/configuration/outbound/trojan.md]`

```json
{
  "type": "trojan",
  "tag": "trojan-out",
  "server": "127.0.0.1",
  "server_port": 1080,
  "password": "8JCsPssfgS8tiRwiMlhARg==",
  "network": "tcp",
  "tls": { ... },
  "multiplex": { ... },
  "transport": { ... }
  // + Dial Fields (например, "domain_strategy", "bind_interface", ...)
}
```

| Поле | Тип | Required | Default | Семантика |
|------|-----|----------|---------|-----------|
| `type` | string | required | — | `"trojan"` |
| `tag` | string | required | — | Identifier для ссылки из urltest и route |
| `server` | string | required | — | Server hostname или IP |
| `server_port` | integer | required | — | Port (1-65535) |
| `password` | string | required | — | Trojan password (plain UTF-8, sing-box делает SHA224 hex-encoded внутри) |
| `network` | string | optional | both | `"tcp"` или `"udp"` или omitted (both) |
| `tls` | object | optional | — | TLS configuration |
| `multiplex` | object | optional | — | smux/yamux/h2mux мультиплексирование |
| `transport` | object | optional | — | V2Ray Transport (WS/HTTP/QUIC/gRPC/httpupgrade) |
| Dial Fields | — | optional | — | `domain_strategy`, `connect_timeout`, etc. |

### 2.2 TLS block (outbound side)

`[VERIFIED: github.com/SagerNet/sing-box/blob/main/docs/configuration/shared/tls.md]`

```json
{
  "enabled": true,
  "disable_sni": false,
  "server_name": "vpn.vergevsky.ru",
  "insecure": false,
  "alpn": ["h2", "http/1.1"],
  "min_version": "1.2",
  "max_version": "1.3",
  "utls": {
    "enabled": true,
    "fingerprint": "chrome"
  }
}
```

Для Trojan в нашем use case:

| Поле | Phase 2 value | Why |
|------|---------------|-----|
| `enabled` | `true` (R1: всегда true) | Без TLS — нельзя; D-08 reject `security != tls` |
| `server_name` | из URI `sni` (default = host) | DPI-resistance — SNI должен совпадать с публичным доменом |
| `insecure` | **`false` всегда** (R1) | `allowInsecure=1` в URI игнорируется (D-08) |
| `alpn` | из URI `alpn` (default `["h2", "http/1.1"]`) | ALPN matchится с server config |
| `utls.enabled` | `true` всегда | Anti-DPI fingerprint mimicking (DPI-01 foundation) |
| `utls.fingerprint` | из URI `fp` / `fingerprint` (default `"chrome"`) | См. ниже список допустимых |

**Допустимые `utls.fingerprint` значения** `[VERIFIED: WebSearch results — sing-box официальная документация TLS]`:

```
chrome    (default)
firefox
edge
safari
360
qq
ios
android
random
randomized
```

**Deprecated/removed** (1.10+ → fallback на chrome): `chrome_psk`, `chrome_psk_shuffle`, `chrome_padding_psk_shuffle`, `chrome_pq`, `chrome_pq_psk`.

**Recommendation для Trojan template:** default `fingerprint = "chrome"` для maximum совместимости. URI override через `fp` query param — если оригинальная конфигурация у пользователя ожидает другой fingerprint (например, `safari` на iOS сервера), параметр URI имеет приоритет над дефолтом.

### 2.3 Transport block для WebSocket

`[VERIFIED: github.com/SagerNet/sing-box/blob/main/docs/configuration/shared/v2ray-transport.md]`

```json
{
  "type": "ws",
  "path": "/ba0ca9ffa1d4",
  "headers": {
    "Host": "vpn.vergevsky.ru"
  },
  "max_early_data": 0,
  "early_data_header_name": ""
}
```

| Поле | Тип | Default | Семантика для нашего use case |
|------|-----|---------|-------------------------------|
| `type` | string | — | `"ws"` ровно |
| `path` | string | — | Path of HTTP upgrade request. Из URI `path` параметра. Required для WS, по trojan-go спеке. |
| `headers` | object | empty | Extra HTTP headers. Особенно `Host` — из URI `host` параметра, fallback на `sni`. |
| `max_early_data` | integer | `0` | 0-RTT через WS. Не используем в Phase 2 (D-08 не упоминает; consistency over performance). |
| `early_data_header_name` | string | empty | Если `max_early_data > 0`, имя header'а для early data. Не используем. |

**Edge case:** sing-box `path` для WS — server **verifies** path (документация явно говорит «The server will verify»). Если клиент имеет `path=/ba0ca9ffa1d4`, а сервер ожидает `path=/abc`, WS-handshake провалится → urltest пометит outbound недоступным.

**Note on `early_data_header_name`:** для Xray-core compatibility — устанавливается в `"Sec-WebSocket-Protocol"`. У нас в Phase 2 не нужно (наша инфра — sing-box, не Xray). Если в Phase 7 столкнёмся с Xray-сервером с early_data — добавим эту опцию через URI extension parameter.

### 2.4 «Trojan-go» style features vs sing-box trojan

`[VERIFIED: github.com/SagerNet/sing-box/blob/main/docs/configuration/outbound/trojan.md + WebSearch on trojan-go]`

sing-box `trojan` outbound — **классический** Trojan, не trojan-go. Это значит:
- ❌ Нет `encryption=ss;aes-256-gcm;password` (trojan-go extension).
- ❌ Нет `plugin=...` (trojan-go extension).
- ❌ Нет Shadowsocks-layer-encryption inside trojan.
- ✅ Поддержан стандартный Trojan (RFC-equivalent draft) + WebSocket transport через V2Ray Transport layer.

**Implication для URI парсера:**
- Если URI имеет `?encryption=ss;...` — **игнорировать** параметр. Не warning user'у, просто silently skip — это trojan-go-extension, наша инфра его не поддерживает.
- Если URI имеет `?plugin=...` — **игнорировать**.
- В Phase 2 эти параметры **не появятся** в user fixtures (user provides только базовые trojan-WS configs).

### 2.5 Multiplex (smux/yamux/h2mux) — нужен ли в Phase 2?

`[VERIFIED: github.com/SagerNet/sing-box/blob/main/docs/configuration/shared/multiplex.md]`

`multiplex` block — опциональный outbound feature для уменьшения connection count. **Не используем в Phase 2** (DPI-05 в anti-DPI suite — Phase 7). Trojan template НЕ имеет `multiplex` секции.

### 2.6 Phase 2 Trojan template — полный пример

Конкретный JSON-template для `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.trojan.json`:

```json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": { /* identical to vless-reality template */ },
  "outbounds": [
    {
      "type": "trojan",
      "tag": "trojan-out",
      "server": "${SERVER_HOST}",
      "server_port": ${SERVER_PORT},
      "password": "${TROJAN_PASSWORD}",
      "network": "tcp",
      "tls": {
        "enabled": true,
        "server_name": "${SNI_DOMAIN}",
        "insecure": false,
        "alpn": ["h2", "http/1.1"],
        "utls": {
          "enabled": true,
          "fingerprint": "${UTLS_FINGERPRINT}"
        }
      },
      "transport": { /* OPTIONAL: только при type=ws */ }
    },
    { "type": "direct", "tag": "direct" }
  ],
  "route": { /* identical to vless-reality */ },
  "experimental": {}
}
```

**Critical design choice:** WebSocket transport — **conditional**. Простой `replacingOccurrences` не справится с условной JSON-секцией. Варианты:

**Вариант A (рекомендуется planner'у):** два отдельных template файла — `SingBoxConfigTemplate.trojan-tcp.json` и `SingBoxConfigTemplate.trojan-ws.json`. ConfigBuilder выбирает template на основе `parsed.transportType`.

**Вариант B:** один template с `${TRANSPORT_BLOCK}` placeholder, в TCP-case substituted на `""`, в WS-case substituted на full JSON-fragment (нужно следить за trailing commas).

**Вариант C:** перейти на Codable-модель и собирать JSON-структуру в Swift (без template-string). Это устранит все substitution-issues, но требует написать Codable models для всех sing-box-types. **Это переход на Codable-модель из Phase 1 D-02 follow-up («Phase 2 улучшит через Codable model» — было заявлено в Phase 1 RESEARCH §6).**

**Recommendation:** planner выберет между A и C; B имеет hazard с trailing commas. C — более чистая, но больше работы; A — pragmatic continuation Phase 1 pattern.

---

## 3. Trojan URI scheme — глубокий разбор

### 3.1 Канонический формат

`[CITED: azadzadeh.github.io/trojan-go/en/developer/url/]`

```
trojan://<password>@<host>:<port>/?<query>#<remark>
```

или (без trailing slash):

```
trojan://<password>@<host>:<port>?<query>#<remark>
```

Both формы поддерживаются — Apple's `URLComponents(string:)` парсит обе одинаково.

### 3.2 Полный список query parameters (что встречается в wild)

Объединение [trojan-go canonical spec] + [v2rayN/Hiddify/Clash extensions] + [user fixtures]:

| Param | Origin | Required | Default | Семантика в sing-box trojan outbound |
|-------|--------|----------|---------|--------------------------------------|
| `security` | wild (v2rayN/Hiddify) | optional | `tls` | Если != `tls` → **reject** (R1 D-08). Single allowed value: `tls`. |
| `type` | trojan-go canonical | optional | `tcp` (a.k.a. `original`) | `tcp`, `ws` (only ws supported on sing-box trojan); `h2`, `h2+ws` — trojan-go-only, не поддерживаем |
| `path` | trojan-go (req for ws) | required for ws | — | WebSocket path. Должен начинаться с `/`. URL-encoded по RFC 3986. |
| `host` | trojan-go | optional | = `sni` | WebSocket Host HTTP header |
| `sni` | trojan-go canonical | optional | = `<host>` (URI authority) | TLS SNI. Cannot be empty |
| `peer` | clash-extension | optional | = `sni` | Synonym for `sni` (старый clash). Parser должен fallback'нуть `peer` → `sni` если `sni` empty |
| `fp` | wild | optional | `chrome` | uTLS fingerprint short alias |
| `fingerprint` | wild (long form) | optional | `chrome` | uTLS fingerprint full form (synonym с `fp`) |
| `alpn` | wild | optional | `h2,http/1.1` | CSV of ALPN values |
| `allowInsecure` | wild | optional | `0` | **Ignored** (R1) — TLS always strict |
| `encryption` | trojan-go | optional | — | **Ignored** (sing-box trojan не trojan-go) |
| `plugin` | trojan-go | optional | — | **Ignored** |
| `obfs` | clash-extension | optional | — | **Ignored** (anti-DPI suite Phase 7+) |
| `obfs-password` | clash-extension | optional | — | **Ignored** |
| `flow` | xray-extension | optional | — | **Ignored** (xtls-rprx-vision — это VLESS feature) |
| `mux` | v2rayN-extension | optional | — | **Ignored** (DPI-05 Phase 7) |

### 3.3 URL-encoding rules

`[CITED: RFC 3986]` + `[CITED: trojan-go URL scheme]`

- `password` — userinfo часть URI. URL-encoded; non-ASCII chars allowed но not recommended (в реальных пользовательских конфигурациях — only ASCII).
- `host` — URI authority host. IDN must be Punycode (`xn--`); IPv6 in brackets `[::1]`.
- `path` — query param value, URL-encoded. Server-side validation.
- `sni`, `host` (WS) — URL-encoded.
- `remark` (fragment) — URL-encoded по RFC 3986; **`#` separator** разделяет URI от fragment. `URLComponents.fragment?.removingPercentEncoding` обрабатывает Cyrillic correctly.

**User fixture validation:**

```
trojan://LN8x95baqueFriHJLnFuDQ@185.237.218.81:2087?security=tls&type=ws&path=/ba0ca9ffa1d4&sni=vpn.vergevsky.ru&fp=chrome#Латвия — Trojan
```

Парсится:
- `userinfo = "LN8x95baqueFriHJLnFuDQ"` → password.
- `host = "185.237.218.81"`.
- `port = 2087`.
- query: `security=tls`, `type=ws`, `path=/ba0ca9ffa1d4`, `sni=vpn.vergevsky.ru`, `fp=chrome`.
- fragment = `Латвия — Trojan` (после percent-decode; Cyrillic + em-dash). `URLComponents.fragment?.removingPercentEncoding` → `"Латвия — Trojan"`.

**Apple `URLComponents` behavior verification:** в Phase 1 `VLESSURIParser` использует тот же pattern (`URLComponents(string:)` + `comps.fragment?.removingPercentEncoding`); это работает с `#WL Латвия` тест-кейсами (Phase 1 фактическое поведение). Trojan URI парсер должен использовать тот же подход.

### 3.4 Edge cases для парсера

| Edge case | Что делает парсер |
|-----------|-------------------|
| Missing `sni` | Fallback `sni = host` (=URI authority host) |
| Missing `sni` AND missing `peer` | Fallback `sni = host` |
| `type=tcp` или `type` missing | Single outbound, без `transport` block |
| `type=ws` без `path` | **Reject** — `path` required для ws (Trojan-go spec) |
| `type=h2` или `type=h2+ws` | **Reject** — trojan-go-only, sing-box не поддерживает; `isSupported = false` flag |
| `allowInsecure=1` | Игнорируем (R1) |
| `security != tls` | **Reject** — D-08 |
| `security` missing | **Reject** — D-08 (TLS required); v2rayN-выводы конфиги без `security=tls` встречаются в wild — но мы строго требуем |
| `encryption=ss;aes-256-gcm;password` | Игнорируем (silent — это trojan-go) |
| `password` empty | **Reject** — malformed URI |
| `port` out of range (>65535 or <1) | **Reject** — Apple URLComponents catches |
| Fragment empty | `remark = host:port` (default name) |
| URI с trailing slash (`trojan://...:port/?...`) | OK — URLComponents parses |

### 3.5 Parser API surface (рекомендуется для Phase 2)

```swift
public struct ParsedTrojan: Sendable, Equatable {
    public let password: String
    public let host: String
    public let port: Int
    public let sni: String
    public let alpn: [String]   // default ["h2", "http/1.1"]
    public let fingerprint: String  // default "chrome"
    public let transportType: TransportType  // .tcp | .ws
    public let wsPath: String?  // только для .ws
    public let wsHost: String?  // только для .ws — fallback на sni если пусто
    public let remarks: String?
}

public enum TransportType: String, Sendable {
    case tcp
    case ws
}

public enum TrojanURIError: Error, LocalizedError, Equatable {
    case malformedURI
    case missingTLSSecurity(String?)  // security != tls or missing
    case unsupportedTransport(String)  // h2, h2+ws, grpc
    case missingWSPath
    case invalidPort(Int)
}

public enum TrojanURIParser {
    public static func parse(_ uri: String) throws -> ParsedTrojan
}
```

---

## 4. Subscription URL response formats — wild zoo

### 4.1 Три формата response body

`[CITED: hiddify.com/app + sourceforge.net/p/hiddify-app/wiki]` + `[CITED: 2dust/v2rayN wiki]`

#### Формат А — Base64-encoded URI list

Самый распространённый формат (legacy v2rayN, Clash, Hiddify, Outline-compatible):

```
dmxlc3M6Ly9mZDJkNDgyMC01MmM4LTRlODEtYTEwNC1kNWIxYzU2MDFjZDZAOTMuNzcuMTg3LjE1MDo4NDQzP3NlY3VyaXR5PXJlYWxpdHkmdHlwZT10Y3AmZmxvdz14dGxzLXJwcngtdmlzaW9uJnNuaT1zMy55YW5kZXhjbG91ZC5uZXQjV0wgTGF0dmlhCnRyb2phbjovL3Rva2VuQDg1LjIzNy4yMTguODE6MjA4Nz9zZWN1cml0eT10bHMmdHlwZT13cyZwYXRoPS9hYmMmc25pPXZwbi5ydSNMYXR2aWE=
```

После `Data(base64Encoded:)`:

```
vless://fd2d4820-52c8-4e81-a104-d5b1c5601cd6@93.77.187.150:8443?security=reality&type=tcp&flow=xtls-rprx-vision&sni=s3.yandexcloud.net#WL Latvia
trojan://token@85.237.218.81:2087?security=tls&type=ws&path=/abc&sni=vpn.ru#Latvia
```

Каждая строка — URI.

**Edge cases:**
- Base64 может быть с `+/=` (standard) или `-_=` (URL-safe). Swift `Data(base64Encoded:)` принимает только standard. **Mitigation:** preprocess — replace `-` → `+`, `_` → `/`, pad with `=` если length % 4 != 0.
- Многострочный base64 (с newlines внутри) — Swift не парсит. **Mitigation:** strip `\r\n` и `\n` перед `Data(base64Encoded:)`.
- Trailing whitespace / BOM — strip.

#### Формат Б — Plain-text URI list

Многие провайдеры возвращают тот же formatted текст без base64-обёртки:

```
vless://...
vless://...
trojan://...
trojan://...
```

Detection: первая строка начинается с `<schema>://` (vless, trojan, ss, vmess, hy2, …).

#### Формат В — JSON sing-box config

Hiddify-стиль («hidden») возвращает готовый sing-box JSON config с outbounds array (часто с уже встроенным `selector` или `urltest`):

```json
{
  "log": {...},
  "dns": {...},
  "outbounds": [
    {"type": "vless", "tag": "Latvia", ...},
    {"type": "trojan", "tag": "Latvia-Trojan", ...},
    {"type": "selector", "tag": "auto", "outbounds": ["Latvia", "Latvia-Trojan"]},
    {"type": "direct", "tag": "direct"}
  ],
  "route": {...}
}
```

Detection: response body trimmed начинается с `{`.

**В Phase 2 D-02 — наш парсер пропустит JSON через `SingBoxConfigLoader.validate` (R1 protection), потом — пройдёт через `expandConfigForTunnel` (TUN inbound injection + DNS-hijack 1.13 migration). Если operator-config содержит `inbounds[type=socks]`, валидатор отвергнет, мы упадём с понятной ошибкой.**

**Edge case:** operator-JSON может содержать `experimental.clash_api` — validate отвергнет; это **намеренно** (R1). Operator вынужден убрать clash_api из конфига перед раздачей.

#### Формат Г — XRAY / V2Ray-original JSON (не sing-box)

```json
{
  "outbounds": [
    {
      "protocol": "vless",  // ← V2Ray field name; sing-box использует "type"
      "settings": {...},     // ← V2Ray nested structure; sing-box flat
      "streamSettings": {...}
    }
  ]
}
```

Detection: `outbounds[].protocol` (field exists, V2Ray-style) vs `outbounds[].type` (sing-box-style).

**Phase 2 D-04:** парсер **детектит** V2Ray-формат, сохраняет URI всех outbounds (если можно расшифровать), но **не пытается** конвертировать в sing-box-схему. На v0.2 — graceful skip с user-message «формат V2Ray JSON не поддерживается, попросите провайдера дать sing-box JSON или URI list». Реальная конвертация — Phase 4+ (если когда-нибудь будет нужна).

### 4.2 Detection heuristics — algorithm

```swift
enum SubscriptionFormat {
    case base64URIList
    case plainTextURIList
    case singBoxJSON
    case v2rayJSON(reason: String)
    case unknown(snippet: String)
}

func detectFormat(body: Data) -> SubscriptionFormat {
    guard let raw = String(data: body, encoding: .utf8) else { return .unknown(snippet: "non-utf8") }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // 1. JSON detection
    if trimmed.first == "{" {
        if let json = try? JSONSerialization.jsonObject(with: trimmed.data(using: .utf8)!) as? [String: Any] {
            if let outbounds = json["outbounds"] as? [[String: Any]] {
                let first = outbounds.first ?? [:]
                if first["type"] != nil { return .singBoxJSON }
                if first["protocol"] != nil { return .v2rayJSON(reason: "outbounds[].protocol field") }
            }
        }
        return .unknown(snippet: String(trimmed.prefix(80)))
    }
    
    // 2. URI list detection (plain text)
    if trimmed.lowercased().hasPrefix("vless://") ||
       trimmed.lowercased().hasPrefix("trojan://") ||
       /* ... other schemas ... */
    {
        return .plainTextURIList
    }
    
    // 3. Base64 attempt
    let normalized = trimmed.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    let padded = normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4)
    if let decoded = Data(base64Encoded: padded),
       let decodedStr = String(data: decoded, encoding: .utf8) {
        let decodedTrimmed = decodedStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if decodedTrimmed.lowercased().hasPrefix("vless://") || decodedTrimmed.lowercased().hasPrefix("trojan://") {
            return .base64URIList
        }
    }
    
    return .unknown(snippet: String(trimmed.prefix(80)))
}
```

**Order matters:**
1. **JSON first** — потому что `{` начало однозначно.
2. **Plain-text URI second** — если начинается с `<schema>://`.
3. **Base64 third** — fallback. (Base64 — superset of plain text в некотором смысле; некоторые plain-text URI могут случайно дешифроваться в base64 to garbage.)

### 4.3 HTTP request headers — User-Agent convention

`[CITED: github.com/2dust/v2rayNG/issues/2746 + Hiddify wiki]`

Subscription provider может вернуть **разное содержимое** для разного User-Agent:
- `v2rayN/<version>` → base64 URI list для legacy v2rayN.
- `Hiddify/<version>` → sing-box JSON для Hiddify-app.
- `clash/<version>` → Clash YAML.
- `singbox/<version>` → готовый sing-box JSON.

**BBTB Phase 2 choice (Claude's Discretion, ratified в D-discretion):**

```
User-Agent: BBTB/0.2 (iOS / macOS)
```

Стандартный custom User-Agent. Большинство provider'ов делают fallback на base64 URI list если User-Agent unknown — это нам и нужно (универсально парсится). Если в будущем потребуется специфическая negotiation — добавим `Accept` header или alternate User-Agent.

### 4.4 Response headers — Hiddify-style metadata

`[CITED: hiddify.com/app/URL-Scheme]` + `[CITED: github.com/hiddify/hiddify-app/wiki/URL-Scheme]`

| Header | Meaning | Phase 2 handling |
|--------|---------|------------------|
| `Profile-Title` или `profile-title` | Display name. May be `base64:<encoded>` for emoji/Cyrillic | Парсим — используем как имя pool'а (overrides default `host:port`). Если empty — fallback на content-disposition filename. |
| `profile-update-interval` | Update period в часах | **Ignore** в Phase 2 (background refresh — Phase 3 SRV-02) |
| `subscription-userinfo` | `upload=N; download=N; total=N; expire=UNIX_TIMESTAMP` | **Ignore** в Phase 2 (Settings → Подписки UI — Phase 4) |
| `support-url` | URL on operator help page | **Ignore** в Phase 2 (Settings → Помощь — Phase 11) |
| `profile-web-page-url` | URL on user-portal | **Ignore** в Phase 2 |
| `content-disposition` | `attachment; filename="<file>"` | Используем filename как fallback для pool name |
| `moved-permanently-to` | URL redirect | **Ignore** на v0.2 (manual user re-import); Phase 3 — auto-follow |
| `DNS` | Default DNS server | **Ignore** — мы используем свой DNS-config (Cloudflare DoH); operator's DNS suggestion не trust'ится |

**Body-embedded comment-headers fallback:** Hiddify также поддерживает headers как comment-lines в первых 10 строках body (`#profile-title: ...`). Phase 2 parser должен проверять и body-comments тоже:

```swift
let firstLines = trimmed.split(separator: "\n").prefix(10)
for line in firstLines {
    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
    if trimmedLine.hasPrefix("#profile-title:") || trimmedLine.hasPrefix("//profile-title:") {
        // extract
    }
}
```

### 4.5 Hiddify URL Scheme — Bonus (для DEEP-01/02 Phase 9)

`[CITED: hiddify.com/app/URL-Scheme]`

```
hiddify://import/<sublink>#<name>
```

Hiddify приложения handle'ят `hiddify://` deep links для импорта. Это **не наша проблема Phase 2**, но Phase 9 (DEEP-01..05) добавит `bbtb://import/<sublink>` — мы можем reuse той же логики UniversalImportParser. Зафиксировать как Phase 9 dependency.

### 4.6 HTTP client design — конкретика для Phase 2

`[VERIFIED: Apple URLSession docs]`

```swift
public actor SubscriptionURLFetcher {
    public func fetch(url: URL) async throws -> SubscriptionFetchResult {
        // Reject http:// — R1-spirit
        guard url.scheme?.lowercased() == "https" else {
            throw FetchError.nonHTTPS(url.scheme ?? "")
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("BBTB/0.2 (iOS / macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain, application/json, */*", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData  // fresh fetch каждый раз
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResp = response as? HTTPURLResponse else {
            throw FetchError.notHTTPResponse
        }
        guard (200..<300).contains(httpResp.statusCode) else {
            throw FetchError.httpStatusError(httpResp.statusCode)
        }
        
        // Parse Hiddify-style metadata из headers
        let metadata = SubscriptionMetadata(
            title: extractTitle(httpResp.allHeaderFields),
            updateInterval: nil,  // Phase 3
            userInfo: nil  // Phase 4
        )
        
        return SubscriptionFetchResult(body: data, metadata: metadata, finalURL: httpResp.url ?? url)
    }
}

public struct SubscriptionFetchResult: Sendable {
    public let body: Data
    public let metadata: SubscriptionMetadata
    public let finalURL: URL  // после redirects
}
```

**Redirect handling:** URLSession by default follows redirects up to 16 hops (Apple-default). Можно ограничить через delegate `urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)` — но в Phase 2 не нужно, использовать default.

**HTTPS-only enforcement:** `url.scheme == "https"` — explicit reject `http://`. Это R1-spirit (subscription URL не должен раскрывать config в clear-text).

**TLS:** URLSession использует system cert store. **DPI-08 (certificate pinning) — Phase 7**, не делаем в Phase 2.

**Gzip/Brotli:** URLSession автоматически handles `Content-Encoding: gzip` / `br` — никакой ручной обработки не нужно.

---

## 5. JSON endpoint format — вариант 3 user fixtures

`[ASSUMED — based on user fixture: https://1.2.3.4:port/json/v3ry-53cur3-p4th-98231/g8ogx6367znwvy95]`

### 5.1 Что это, скорее всего

Из контекста (Hiddify-стиль operator panel) и user fixture (`/json/<path>`) — это endpoint, который возвращает готовый sing-box JSON config (вероятно с встроенным `selector` или `urltest`).

Phase 2 handling — D-02:
- HTTP GET (как обычный subscription URL, но с `Accept: application/json` header).
- Response body → parse как JSON (формат В из раздела 4.1).
- Передать через `SingBoxConfigLoader.validate` — R1 protection.
- Если pass — `expandConfigForTunnel` — TUN inbound injection + DNS-hijack.
- Сохранить в SwiftData как pool с `subscriptionURL` метаданной.

**Self-signed certificate:** некоторые operators хостят на IP-only HTTPS с self-signed cert. По R1 spirit (CONTEXT.md §5):
- **Phase 2 — reject** self-signed. URLSession default trust system cert store. Operator должен иметь valid cert chain.
- Если operator на IP-only — он может использовать Let's Encrypt с DNS-01 challenge для wildcard cert, привязанного к домену → DNS resolves в IP → cert valid. Это стандартная практика.

### 5.2 Архитектурное различие vs Subscription URL

Технически — это **тот же** subscription URL, просто endpoint всегда возвращает JSON-формат. С точки зрения нашей архитектуры:

- **SubscriptionURLFetcher** делает HTTP GET → возвращает `SubscriptionFetchResult`.
- **UniversalImportParser** видит, что body начинается с `{` → диспатчит на JSON-handler.
- JSON-handler делает `SingBoxConfigLoader.validate(json: body) → extractServers(json: body) → save`.

Нет необходимости в отдельном `JSONEndpointFetcher` класса — Universal parser сам разберётся.

### 5.3 Server extraction из sing-box JSON

Когда мы получили full sing-box config (формат В), нужно извлечь servers для сохранения в SwiftData:

```swift
struct ExtractedServer {
    let tag: String           // имя outbound из JSON
    let type: String          // "vless" | "trojan" | ...
    let host: String          // outbound.server
    let port: Int             // outbound.server_port
    let sni: String?          // outbound.tls.server_name
    let rawOutboundJSON: String // полный outbound объект для использования в pool template
    let isSupported: Bool     // true для vless/trojan в Phase 2; false для остальных
}

func extractServers(from configJSON: String) throws -> [ExtractedServer] {
    let data = configJSON.data(using: .utf8)!
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    let outbounds = (json["outbounds"] as? [[String: Any]]) ?? []
    
    var servers: [ExtractedServer] = []
    let supportedTypes: Set<String> = ["vless", "trojan"]
    
    for outbound in outbounds {
        guard let type = outbound["type"] as? String,
              !["direct", "block", "dns", "selector", "urltest"].contains(type),
              let server = outbound["server"] as? String,
              let serverPort = outbound["server_port"] as? Int
        else { continue }
        
        let isSupported = supportedTypes.contains(type)
        let tag = outbound["tag"] as? String ?? "\(server):\(serverPort)"
        let sni = (outbound["tls"] as? [String: Any])?["server_name"] as? String
        let rawJSON = try JSONSerialization.data(withJSONObject: outbound).utf8String
        
        servers.append(ExtractedServer(
            tag: tag, type: type, host: server, port: serverPort,
            sni: sni, rawOutboundJSON: rawJSON, isSupported: isSupported
        ))
    }
    return servers
}
```

**Реcommendation планнеру:** при импорте JSON-config, рекомендуется НЕ применять operator-provided config один-в-один, а **переделать** в наш pool format:
- Извлечь supported outbounds (`vless`, `trojan`).
- Положить их в наш template `Resources/SingBoxConfigTemplate.pool.json` (с нашим DNS-config, нашим route, нашим urltest).
- Это гарантирует R1 compliance (нет неожиданных inbound'ов / experimental APIs) и UX consistency (наш kill switch / DNS-strategy).

---

## 6. Universal URI parser архитектура

### 6.1 Структурная диаграмма

```
                  ┌────────────────────────────┐
                  │   UniversalImportParser    │
                  │      .import(raw:)         │
                  └────────────┬───────────────┘
                               │
                  ┌────────────▼───────────────┐
                  │       Classify input        │
                  │  (URL | URI | JSON | text)  │
                  └────────────┬───────────────┘
                               │
       ┌────────────────────┬──┴──┬─────────────────────────┐
       │                    │     │                          │
       ▼                    ▼     ▼                          ▼
 [HTTPS URL]         [URI list]  [Single URI]      [Multi-line text]
       │                    │     │                          │
       │             ┌──────┘     │                          │
       ▼             ▼            │                          │
 SubscriptionURLFetcher           │                          │
       │                          │                          │
       ▼                          │                          │
 Detect body format               │                          │
  (base64/text/JSON)              │                          │
       │                          │                          │
       └──────┬───────────────────┘                          │
              │                                              │
              ▼                                              │
        [URI list flat] ◄─────────────────────────────────────┘
              │
              ▼
       For each URI:
       ┌──────────────────────────────┐
       │ Identify scheme (vless/trojan│
       │ /ss/vmess/hy2/wg/ssh/socks5) │
       └──────────────┬───────────────┘
                      │
       ┌──────────────▼───────────────┐
       │   Dispatch to sub-parser     │
       │  VLESSURIParser              │
       │  TrojanURIParser             │
       │  SSURIParser (stub)          │
       │  VMessURIParser (stub)       │
       │  ...                          │
       └──────────────┬───────────────┘
                      │
                      ▼
       ┌──────────────────────────────────┐
       │ ImportedServer (sumtype):        │
       │   .supported(ParsedX)            │
       │   .unsupported(scheme, host:port,│
       │                remark, reason)   │
       │   .invalid(uri, error)           │
       └──────────────┬───────────────────┘
                      │
                      ▼
       ┌──────────────────────────────────┐
       │ ConfigImporter:                   │
       │ Persist supported → SwiftData    │
       │  (isSupported=true)              │
       │ Persist unsupported → SwiftData  │
       │  (isSupported=false)             │
       │ Build pool config from supported │
       │ Save NETunnelProviderManager     │
       └──────────────────────────────────┘
```

### 6.2 API surface

```swift
public enum UniversalImportParser {
    public static func `import`(rawInput: String) async throws -> ImportResult
}

public enum ImportResult: Sendable {
    case singleURI(ImportedServer, source: ImportSource)
    case multipleURIs([ImportedServer], source: ImportSource, metadata: SubscriptionMetadata?)
    case singBoxConfig([ImportedServer], source: ImportSource, metadata: SubscriptionMetadata?)
}

public enum ImportSource: Sendable, Equatable {
    case pasteboard
    case subscriptionURL(URL)
    case jsonEndpoint(URL)
    case qrCode
    case multilineText
}

public enum ImportedServer: Sendable {
    case supported(name: String, parsed: AnyParsedConfig, rawURI: String)
    case unsupported(name: String, scheme: String, host: String, port: Int, rawURI: String, reason: UnsupportedReason)
    case invalid(rawURI: String, error: Error)
}

public enum UnsupportedReason: String, Sendable {
    case schemaUnsupportedInPhase2  // ss, vmess, hy2, wg, ssh, socks5, naive
    case transportUnsupported       // type=h2, h2+ws, grpc in trojan
    case malformedURI
}

public enum AnyParsedConfig: Sendable {
    case vlessReality(ParsedVLESS)
    case trojan(ParsedTrojan)
    // Phase 4+ добавит остальные
}
```

### 6.3 Classification heuristics — algorithm

```swift
func classifyInput(_ raw: String) -> InputClass {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // 1. Detection: URL?
    if let url = URL(string: trimmed), url.scheme?.lowercased() == "https" {
        // HTTP URL — это subscription URL
        return .subscriptionURL(url)
    }
    
    // 2. Detection: starts with JSON {?
    if trimmed.first == "{" {
        return .singBoxJSON(trimmed)
    }
    
    // 3. Detection: starts with known scheme?
    let supportedSchemes = ["vless://", "trojan://", "ss://", "vmess://", "hy2://", "hysteria2://", "wireguard://", "ssh://", "socks5://", "socks://", "naive+https://", "naive+quic://"]
    let lowered = trimmed.lowercased()
    if supportedSchemes.contains(where: { lowered.hasPrefix($0) }) {
        // Может быть single URI или multi-line URI list
        let lines = trimmed.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }
        if lines.count == 1 {
            return .singleURI(trimmed)
        } else {
            return .multilineURIList(Array(lines.map(String.init)))
        }
    }
    
    // 4. Detection: base64 (последний шанс)
    let normalized = trimmed.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    let padded = normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4)
    if let decoded = Data(base64Encoded: padded),
       let decodedStr = String(data: decoded, encoding: .utf8),
       supportedSchemes.contains(where: { decodedStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix($0) }) {
        return .base64URIList(decodedStr)
    }
    
    return .unknown(snippet: String(trimmed.prefix(80)))
}

enum InputClass {
    case singleURI(String)
    case multilineURIList([String])
    case subscriptionURL(URL)
    case singBoxJSON(String)
    case base64URIList(String)
    case unknown(snippet: String)
}
```

**Order matters:**
1. **HTTPS URL** — single URL — это subscription (нужен fetch).
2. **JSON `{`** — direct sing-box config (можно сразу parse).
3. **Known URI schemes** — single URI или multi-line.
4. **Base64 fallback** — последний resort.

### 6.4 Error type design — per-source vs per-config

```swift
public enum ImportError: Error, LocalizedError {
    // Source-level (fetch / decode errors)
    case fetchFailed(URL, Error)
    case nonHTTPSSubscription(String)
    case httpStatusError(URL, Int)
    case decodingFailed(reason: String)
    
    // Body-level
    case unknownInputFormat(snippet: String)
    case emptyInput
    case singBoxValidateFailed(SingBoxConfigError)
    
    // Per-config errors (one URI failed but others may succeed)
    case configsFailed([(uri: String, error: Error)])
    
    // Aggregate result
    case allConfigsFailed(errors: [(uri: String, error: Error)])
}
```

**Critical UX consideration:** в multi-line URI list если 5 из 6 URI parse OK, а 1 — malformed, **NOT abort whole import**. Сохранить 5 supported, показать user'у warning «5 импортировано, 1 пропущен (показать detail)».

```swift
// Aggregated import semantics
func importMultipleURIs(_ uris: [String]) -> (succeeded: [ImportedServer], failed: [(uri: String, error: Error)]) {
    var ok: [ImportedServer] = []
    var failed: [(String, Error)] = []
    for uri in uris {
        do {
            let parsed = try parseSingleURI(uri)
            ok.append(parsed)
        } catch {
            failed.append((uri, error))
        }
    }
    return (ok, failed)
}
```

### 6.5 PoolBuilder — generating urltest config from supported servers

```swift
public enum PoolBuilder {
    public static func buildSingBoxJSON(
        from servers: [ImportedServer],
        killSwitchEnabled: Bool  // используется для logging only; реальный apply в KillSwitch.apply
    ) throws -> String {
        let supported = servers.compactMap { server -> AnyParsedConfig? in
            if case let .supported(_, parsed, _) = server { return parsed }
            return nil
        }
        
        guard !supported.isEmpty else {
            throw PoolBuilderError.noSupportedServers
        }
        
        var outbounds: [[String: Any]] = []
        var outboundTags: [String] = []
        
        for (index, parsed) in supported.enumerated() {
            let tag: String
            let outboundJSON: [String: Any]
            
            switch parsed {
            case .vlessReality(let v):
                tag = "vless-\(index)"
                outboundJSON = buildVLESSOutbound(parsed: v, tag: tag)
            case .trojan(let t):
                tag = "trojan-\(index)"
                outboundJSON = buildTrojanOutbound(parsed: t, tag: tag)
            }
            outbounds.append(outboundJSON)
            outboundTags.append(tag)
        }
        
        // urltest outbound
        let urltest: [String: Any] = [
            "type": "urltest",
            "tag": "urltest-out",
            "outbounds": outboundTags,
            "url": "https://cp.cloudflare.com/generate_204",
            "interval": "1m",
            "tolerance": 50,
            "idle_timeout": "30m",
            "interrupt_exist_connections": false
        ]
        outbounds.append(urltest)
        
        // direct outbound (carry-forward Phase 1)
        outbounds.append(["type": "direct", "tag": "direct"])
        
        // Assemble full config
        var root: [String: Any] = [
            "log": ["level": "info", "timestamp": true],
            "dns": buildDNSConfig(detour: "urltest-out"),  // ← Phase 2 change: detour → urltest
            "outbounds": outbounds,
            "route": [
                "rules": [
                    ["action": "sniff", "timeout": "1s"],
                    ["protocol": "dns", "action": "hijack-dns"]
                ],
                "final": "urltest-out",
                "auto_detect_interface": true
            ],
            "experimental": [:]
        ]
        
        let data = try JSONSerialization.data(withJSONObject: root)
        return String(data: data, encoding: .utf8)!
    }
}
```

**Special case: single supported server** — нет смысла создавать urltest для одного outbound. Build degenerated config с `route.final` указывающий напрямую на single outbound:

```swift
if supported.count == 1 {
    // Skip urltest, route.final = single outbound tag
    return buildSingleOutboundConfig(supported.first!)
}
```

Это сохраняет совместимость с Phase 1 (single-server scenario) и упрощает sing-box работу.

---

## 7. `SingBoxConfigLoader.validate` extension для Phase 2

### 7.1 Что нужно поменять — none или минимум

`[VERIFIED: SingBoxConfigLoader.swift текущее состояние]`

Текущий валидатор уже R1-safe. Phase 2 Trojan outbound + urltest outbound + WS transport не нарушают:
- `allowedInboundTypes = {tun, direct}` — outbound types игнорируются валидатором ✅ (Trojan = outbound).
- `experimental.clash_api` / `v2ray_api` / `cache_file` — Phase 2 не добавляет ничего → empty `experimental: {}` ✅.
- `outbounds.contains { type == "vless" }` — **ПРОБЛЕМА**. Сейчас валидатор требует хотя бы один VLESS outbound (Phase 1 PROTO-01 guarantee). В Phase 2 у пользователя может быть pool из только-Trojan'ов!

### 7.2 Конкретное изменение в `SingBoxConfigLoader.validate`

```swift
// SingBoxConfigError — добавить case
public enum SingBoxConfigError: Error, LocalizedError, Equatable {
    case malformedJSON
    case forbiddenInboundType(String)
    case experimentalApiEnabled(String)
    case missingOutbounds
    // case noVLESSOutbound  // ← REMOVE — Phase 1 single-protocol assumption
    case noProxyOutbound    // ← NEW — нужен хотя бы один proxy outbound (vless | trojan | ...)
}

// validate — изменить последнюю проверку
public static func validate(json: String) throws {
    // ... existing inbound + experimental checks ...
    
    guard let outbounds = root["outbounds"] as? [[String: Any]], !outbounds.isEmpty else {
        throw SingBoxConfigError.missingOutbounds
    }
    
    // Phase 2 change: any proxy outbound (not just vless)
    let proxyOutboundTypes: Set<String> = [
        "vless", "trojan",  // Phase 2 supported
        "shadowsocks", "vmess", "hysteria2", "wireguard", "tuic",  // future-supported
    ]
    let hasProxyOutbound = outbounds.contains { 
        guard let type = $0["type"] as? String else { return false }
        return proxyOutboundTypes.contains(type)
    }
    guard hasProxyOutbound else { throw SingBoxConfigError.noProxyOutbound }
}
```

**Why not whitelist outbound types like inbound types?** Outbound types — это «как мы выходим в интернет», они **не listen on loopback** (за исключением `socks5` outbound, но это outbound-side socks5 client, не сервер — это безопасно). Phase 1 не whitelist'ил outbound types, и Phase 2 продолжает этот approach. R1 — это про **inbound** types.

**Should we whitelist `selector` / `urltest` group outbounds?** Они тоже outbound types — не listening on loopback, безопасны. Не whitelist'им — просто включаем в `proxyOutboundTypes` если нужно (для validate logic «есть proxy»):

```swift
let groupOutboundTypes: Set<String> = ["selector", "urltest"]
// эти НЕ proxy сами по себе, но если они есть — внутри них должны быть proxy outbounds
```

Но это уже complex — Phase 2 проще: оставить `noProxyOutbound` check, urltest пройдёт если в нём есть хотя бы один vless/trojan через `outbounds` field. Validator может это проверить рекурсивно (опционально).

### 7.3 Проверка `urltest.outbounds` references — нужна?

Если operator-provided JSON содержит `{"type":"urltest","outbounds":["nonexistent-tag"]}`, sing-box ругнётся при старте. Должен ли наш validator это поймать заранее?

**Yes, recommended:**

```swift
// validate (extension)
let allTags = Set(outbounds.compactMap { $0["tag"] as? String })
for outbound in outbounds {
    guard let type = outbound["type"] as? String else { continue }
    if type == "urltest" || type == "selector" {
        if let refs = outbound["outbounds"] as? [String] {
            for ref in refs {
                if !allTags.contains(ref) {
                    throw SingBoxConfigError.unresolvedOutboundRef(ref, in: type)
                }
            }
        }
    }
}
```

Это catch typos в operator-config и наш generated config (PoolBuilder bug-protection).

### 7.4 `expandConfigForTunnel` — без изменений

Текущая `expandConfigForTunnel` (Phase 1 W3+W3.1) работает идентично для Trojan и multi-outbound urltest конфигов:
- Injection TUN inbound (gvisor stack, /28, MTU 1500) — не trog'ает outbounds.
- DNS-hijack rule injection — не trog'ает outbounds.
- Sniff rule injection — не trog'ает outbounds.
- Удаление legacy `{type:dns}` outbound — фильтр по type, не задевает trojan/urltest.

`[VERIFIED: SingBoxConfigLoader.swift источник]`

**No changes needed.** Confirmed.

---

## 8. AVFoundation QR scanner (iOS + macOS)

### 8.1 Архитектура — pipeline + permissions

`[VERIFIED: developer.apple.com/documentation/avfoundation/avcapturemetadataoutput]` + `[VERIFIED: WebSearch results]`

```
                                   ┌─────────────────────┐
                                   │ User taps QR button │
                                   └──────────┬──────────┘
                                              │
                            ┌─────────────────▼────────────────┐
                            │  AVCaptureDevice.authorizationStatus │
                            └─────────────────┬────────────────┘
                                              │
                       ┌──────────────────────┼────────────────────────┐
                       │                      │                        │
                       ▼                      ▼                        ▼
                  .notDetermined         .authorized             .denied/.restricted
                       │                      │                        │
            ┌──────────▼──────────┐           │                        ▼
            │ requestAccess(for:  │           │              Show alert: «Доступ
            │   .video) → async   │           │              запрещён — открыть
            └──────────┬──────────┘           │              Settings»
                       │                      │
            ┌──────────▼──────────┐           │
            │ granted? Yes/No     │           │
            └──────────┬──────────┘           │
                       │                      │
                       ├─────── Yes ──────────┘
                       │
                       ▼
                ┌──────────────────────────┐
                │ AVCaptureSession         │
                │  .sessionPreset = .high   │
                │ .addInput(videoDevice)   │
                │ .addOutput(meta)          │
                │   meta.metadataObject-   │
                │     Types = [.qr]         │
                │ .startRunning()           │
                └────────────┬──────────────┘
                             │
                             ▼
                ┌──────────────────────────┐
                │ AVCaptureVideoPreviewLayer│
                │ overlay в UIView          │
                └────────────┬──────────────┘
                             │
                             ▼
                ┌──────────────────────────┐
                │ AVCaptureMetadataOutput- │
                │ ObjectsDelegate           │
                │ .metadataOutput(_:        │
                │   didOutput:from:)        │
                └────────────┬──────────────┘
                             │
                             │ on first .qr code:
                             ▼
                ┌──────────────────────────┐
                │ session.stopRunning()    │
                │ haptic feedback           │
                │ dismiss controller        │
                │ → UniversalImport-        │
                │     Parser.import(raw:)   │
                └──────────────────────────┘
```

### 8.2 Camera permission flow

`[VERIFIED: AVCaptureDevice authorizationStatus API + Apple docs]`

```swift
public actor CameraPermission {
    public enum Status {
        case authorized
        case denied
        case restricted
        case notDetermined
    }
    
    public func current() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied  // future-proof
        }
    }
    
    /// Requests permission. Returns true on success.
    /// **Throws** `.denied` if user previously denied (no system prompt will appear).
    public func request() async throws -> Bool {
        let status = current()
        switch status {
        case .authorized: return true
        case .denied, .restricted: throw CameraError.userDenied  // → caller shows "open Settings" alert
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        }
    }
}
```

**Info.plist key** (required для both iOS и macOS):

```xml
<key>NSCameraUsageDescription</key>
<string>BBTB использует камеру для сканирования QR-кодов с конфигурациями VPN-серверов</string>
```

**Локализация:** `NSCameraUsageDescription` поддерживает локализацию через InfoPlist.strings:
- `en.lproj/InfoPlist.strings`: `"NSCameraUsageDescription" = "BBTB uses the camera to scan QR codes containing VPN server configurations";`
- `ru.lproj/InfoPlist.strings`: `"NSCameraUsageDescription" = "BBTB использует камеру для сканирования QR-кодов с конфигурациями VPN-серверов";`

### 8.3 macOS specifics — hardened runtime + entitlement

`[VERIFIED: developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.camera]`

macOS требует **обе вещи** для access камеры:
1. `NSCameraUsageDescription` в Info.plist — для TCC (Transparency, Consent, Control) prompt.
2. `com.apple.security.device.camera = true` entitlement — для hardened runtime.

**Without entitlement**, app crashes when accessing camera (TCC sandbox enforced).

**Phase 1 entitlements** уже включают `com.apple.security.app-sandbox`. Phase 2 добавляет:

```xml
<!-- BBTB/App/macOSApp/BBTB-macOS.entitlements -->
<key>com.apple.security.device.camera</key>
<true/>
```

(iOS: только Info.plist key, no entitlement — iOS sandbox автоматически gates через TCC.)

### 8.4 AVCaptureSession + AVCaptureMetadataOutput setup

`[VERIFIED: hackingwithswift.com/example-code/media/how-to-scan-a-qr-code]`

```swift
final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var onScan: ((String) -> Void)?
    
    convenience init(onScan: @escaping (String) -> Void) {
        self.init()
        self.onScan = onScan
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice)
        else {
            // Fail-fast UI
            return
        }
        
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            metadataOutput.metadataObjectTypes = [.qr]  // ← QR only
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        // Start on a background queue (Apple: don't block main thread)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // Throttle to first detection
        guard !metadataObjects.isEmpty,
              let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = readable.stringValue
        else { return }
        
        session.stopRunning()
        
        // Haptic feedback (iOS only — guard for macOS)
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
        
        // Invoke callback on main, then dismiss
        DispatchQueue.main.async { [weak self] in
            self?.onScan?(value)
            self?.dismiss(animated: true)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }
}
```

**Throttling**: `session.stopRunning()` сразу после first QR — prevents repeated calls в delegate.

### 8.5 SwiftUI integration

#### iOS — UIViewControllerRepresentable

```swift
public struct QRScannerView: UIViewControllerRepresentable {
    public let onScan: (String) -> Void
    public let onError: (Error) -> Void
    
    public init(onScan: @escaping (String) -> Void, onError: @escaping (Error) -> Void) {
        self.onScan = onScan
        self.onError = onError
    }
    
    public func makeUIViewController(context: Context) -> QRScannerViewController {
        QRScannerViewController(onScan: onScan)
    }
    
    public func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}
```

Usage:

```swift
struct ImportFlowView: View {
    @State private var showScanner = false
    @State private var scannedURI: String?
    
    var body: some View {
        // ... main UI ...
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView(
                onScan: { uri in
                    scannedURI = uri
                    showScanner = false
                },
                onError: { error in
                    // show error
                    showScanner = false
                }
            )
        }
    }
}
```

#### macOS — NSViewRepresentable

```swift
#if os(macOS)
public struct QRScannerView: NSViewRepresentable {
    public let onScan: (String) -> Void
    public let onError: (Error) -> Void
    
    public func makeNSView(context: Context) -> QRScannerNSView {
        QRScannerNSView(onScan: onScan, onError: onError)
    }
    
    public func updateNSView(_ nsView: QRScannerNSView, context: Context) {}
}

final class QRScannerNSView: NSView, AVCaptureMetadataOutputObjectsDelegate {
    // Аналогично QRScannerViewController, но NSView вместо UIViewController.
    // NSView не имеет viewDidLoad — setup в init.
    // previewLayer добавляется как backingLayer (или CALayer hosting view).
}
#endif
```

**macOS canvas note:** в SwiftUI на macOS можно использовать `.sheet { QRScannerView(...) }` — modal окно.

### 8.6 Edge cases для QR scanner

| Edge case | Что делать |
|-----------|------------|
| User denied permission earlier | `CameraPermission.request()` throws → show alert «Откройте Настройки → BBTB → Камера» с deep link `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)` |
| Нет камеры (Simulator / Mac без webcam) | `AVCaptureDevice.default(for: .video)` returns nil → show error «Камера недоступна» |
| Multiple QR в кадре | First detected wins (delegate fires for first, мы stopRunning) |
| QR код = текстовый URI vs URI-list (multi-line в одном QR — rare но возможно) | После scan'а передать в `UniversalImportParser` — он сам разберётся multi-line vs single |
| QR содержит non-URI content (например, обычный URL без `vless://`) | `UniversalImportParser.classify` → `.subscriptionURL(url)` — fetch и парсить как subscription |

### 8.7 Module location в SwiftPM

Per `prompts/v2 <swift_package_layout>` Phase 2 добавляет:

```
BBTB/Packages/AppFeatures/Sources/QRScannerFeature/
├── QRScannerView.swift           ← SwiftUI public entry
├── QRScannerViewController.swift  ← iOS UIViewController
├── QRScannerNSView.swift          ← macOS NSView
└── CameraPermission.swift         ← Permission actor
```

**Recommendation:** новый sub-module `QRScannerFeature` под `AppFeatures` package — изолируется от `MainScreenFeature`, тестируется отдельно.

---

## 9. NETunnelProviderManager `providerConfiguration` updates while connected

### 9.1 Save → load pattern (Phase 1 carry-forward — CRITICAL)

`[VERIFIED: Phase 1 RESEARCH §1 — закрыто и применено в ConfigImporter Phase 1 W4]`

Каноничный паттерн при любом save'е:

```swift
manager.protocolConfiguration = updatedProto  // includes KillSwitch.apply(to:enabled:)
manager.isEnabled = true
try await manager.saveToPreferences()
try await manager.loadFromPreferences()  // ← обязательно: workaround для Apple bug
```

Phase 1 этот паттерн уже использует в `ConfigImporter.provisionTunnelProfile`. Phase 2 KILL-03 toggle apply должен следовать ему же.

### 9.2 First save vs subsequent saves — permission prompt behavior

`[VERIFIED: developer.apple.com/forums/thread/692546 + WebSearch confirmation]`

- **First save** (когда `loadAllFromPreferences()` returns empty) → user sees system alert «<App> Would Like to Add VPN Configurations» → user taps «Allow» → profile installed. **Дополнительно на iOS** — TouchID/FaceID prompt для подтверждения admin action.
- **Subsequent saves** (используя `loadAllFromPreferences()`-loaded manager OR keeping manager instance alive) → **silent**, no alert, no biometric prompt. Permission уже granted, profile уже installed.

**Phase 2 KILL-03 implication:**
- User toggle'нет «Kill Switch» в SettingsView → `UserDefaults.standard.set(false, forKey: "app.bbtb.killSwitchEnabled")`.
- При следующем `provisionTunnelProfile()` (например, при следующем connect): `ConfigImporter` читает UserDefaults, передаёт в `KillSwitch.apply(to: proto, enabled: false)`, делает `manager.saveToPreferences()` — **silent**, no prompt.

**Не нужно** persist'ить toggle state в `providerConfiguration` — это просто UserDefaults flag, читается каждый раз при provisioning.

### 9.3 Changes take effect — только на reconnect

`[VERIFIED: Apple DTS Matt Eaton, Apple Developer Forums thread 692546]`

> "Reconnection is required: Configuration changes take effect only after reconnecting the tunnel."

Это означает: если **tunnel активен** в момент toggle change → даже после успешного `saveToPreferences()`, активный tunnel продолжает работать с **старыми** kill switch settings. User должен явно disconnect + connect для apply'а.

**Это и есть основа D-14.** D-14 говорит «применяется на следующем connect, показывается баннер». Это правильный Apple-conformant подход. Альтернатива (auto-reconnect) ломает active streams (4-8 секунд паузы) — недопустимый UX trade-off.

### 9.4 Multiple NETunnelProviderManagers — should we have one or many?

`[CITED: developer.apple.com/forums/thread/72158]`

Apple позволяет несколько managers, но **CONTEXT.md D-01 железно фиксирует один**. Это согласуется с user experience (один VPN profile в системных Settings — VPN → BBTB), и наша auto-fallback логика встроена в sing-box через urltest.

**Phase 2 — продолжаем pattern Phase 1:** один `NETunnelProviderManager`, identified by `protocolConfiguration.providerBundleIdentifier == "app.bbtb.client.{ios,macos}.tunnel"`. Импорт нового pool'а — `update` существующего manager (load → modify providerConfiguration["configJSON"] → save → load).

### 9.5 ProviderConfiguration size limits

`[CITED: Phase 1 RESEARCH §1 — 256 KB iOS limit]`

`providerConfiguration: [String: Any]?` — payload to extension. Limit ~256 KB на iOS. Pool config (2-10 outbounds) — каждый ~1-2 KB JSON → 10 outbounds × 2 KB = 20 KB. **Well below limit.**

**Worst case scenario:** subscription URL возвращает 100 outbounds → 200 KB JSON. Approaches limit. **Mitigation для Phase 2:** ограничить pool size до 50 outbounds (`urltest.outbounds` array length); если subscription content больше — взять первые 50 supported. Это соответствует sensible UX (user-managed list более 50 серверов — край редкости в реальных юзкейсах).

**Phase 3** (server-list UI) добавит UI для manual select/deselect, тогда pool можно сделать subset of total servers.

### 9.6 ConfigImporter архитектурный refactor

Текущий `ConfigImporter.importFromPasteboard()` (Phase 1 path):

```swift
ConfigImporter.importFromPasteboard()
  → пастбоард → VLESSURIParser.parse → ParsedVLESS
  → ConfigBuilder.buildSingBoxJSON(from: parsed)
  → SingBoxConfigLoader.validate(json:)
  → KeychainStore.save(secret: uuid+publicKey+shortId)
  → SwiftData ServerConfig.save
  → NETunnelProviderManager: load/create → set providerConfiguration[configJSON] → KillSwitch.apply → save → load
```

Phase 2 path:

```swift
ConfigImporter.import(rawInput:)  // ← обобщённый entry-point
  → UniversalImportParser.import(rawInput:) → ImportResult
  → (если HTTP fetch) SubscriptionURLFetcher.fetch
  → (если URI list) [TrojanURIParser | VLESSURIParser].parse each
  → (если JSON) SingBoxConfigLoader.validate + extractServers
  → [ImportedServer]
  → For each .supported: KeychainStore.save(secret:) + SwiftData ServerConfig.save (isSupported=true)
  → For each .unsupported: SwiftData ServerConfig.save (isSupported=false)  // не имеет Keychain entry
  → PoolBuilder.buildSingBoxJSON(from: supported, killSwitchEnabled: UserDefaults.bool)
  → SingBoxConfigLoader.validate(json:) ← validation R1 после PoolBuilder
  → NETunnelProviderManager: load/create → providerConfiguration[configJSON] = pool → KillSwitch.apply(enabled: UserDefaults) → save → load
```

**Key refactor:** `ConfigImporter.importFromPasteboard()` → `ConfigImporter.import(rawInput: String, source: ImportSource)`. Source enum определяет UX feedback (pasteboard vs QR vs subscription URL), но import pipeline identical.

---

## 10. SwiftData array migration from singleton

### 10.1 Текущая schema (Phase 1)

`[VERIFIED: BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift]`

```swift
@Model
public final class ServerConfig {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var protocolID: String       // "vless-reality" в Phase 1
    public var keychainTag: String
    public var isActive: Bool           // singleton flag в Phase 1
    public var createdAt: Date
    public var lastLatencyMs: Int?
    
    public init(...) { ... }
}
```

### 10.2 Phase 2 target schema

```swift
@Model
public final class ServerConfig {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var protocolID: String       // "vless-reality" | "trojan" | "ss-stub" | ...
    public var keychainTag: String?     // ← теперь optional (unsupported servers не имеют Keychain)
    public var isActive: Bool           // ← Phase 2: not used (urltest selects); leave field for Phase 3 manual select
    public var createdAt: Date
    public var lastLatencyMs: Int?
    
    // Phase 2 new fields
    public var isSupported: Bool        // true для vless/trojan; false для unknown
    public var subscriptionURL: String? // URL of subscription pool source; nil для single-paste import
    public var sni: String?             // для duplicate detection (host+port+protocolID+sni)
    public var rawURI: String?          // оригинальный URI для re-parse при handler upgrade
    
    public init(...) { ... }
}
```

### 10.3 Lightweight migration — without code

`[VERIFIED: hackingwithswift.com/quick-start/swiftdata + developer.apple.com/forums/thread/738812]`

SwiftData автоматически делает lightweight migration если:
- Добавляются новые properties с **default values**.
- Добавляются новые `@Model` classes.
- Удаляются existing properties (carefully — данные теряются).

**Условие для Phase 2:** добавить properties с default values в Swift code → SwiftData автоматически применит lightweight migration при первом запуске после update.

```swift
@Model
public final class ServerConfig {
    // existing fields...
    public var keychainTag: String? = nil  // ← optional with nil default; existing rows fill in via migration
    
    public var isSupported: Bool = true   // ← default true; existing rows assume supported
    public var subscriptionURL: String? = nil
    public var sni: String? = nil
    public var rawURI: String? = nil
    
    public init(...) {
        // existing args + new defaults
    }
}
```

**Critical:** `isSupported = true` для existing rows — потому что Phase 1 импортировал только vless-reality (= supported). Если бы Phase 1 импортировал unsupported, мы бы не имели его в SwiftData → нет проблемы.

**Verification recommendation:** в Phase 2 W0 (или эквивалент) wave добавить **migration test**:
1. Создать Phase 1 ServerConfig запись через старую schema.
2. Применить Phase 2 schema upgrade.
3. Прочитать запись — проверить что `isSupported == true`, `subscriptionURL == nil`, etc.

### 10.4 VersionedSchema — НЕ нужен в Phase 2

`[VERIFIED]` VersionedSchema нужен **только** для complex migrations (renames, type changes, splits, joins). У нас — только additions с defaults. **Lightweight migration достаточно.**

В Phase 3 если будут breaking changes (например, разделить `keychainTag` на `keychainTag-uuid` + `keychainTag-password` для multi-secret servers) — переходим на VersionedSchema. Но не сейчас.

### 10.5 Fetch descriptors для нового state

```swift
// Fetch all supported configs of current pool (для PoolBuilder)
let descriptor = FetchDescriptor<ServerConfig>(
    predicate: #Predicate { 
        $0.isSupported == true && 
        $0.subscriptionURL == currentPoolURL
    },
    sortBy: [SortDescriptor(\.createdAt)]
)
let supportedServers = try context.fetch(descriptor)

// Fetch all configs of pool (supported + unsupported) для UI display
let allInPool = try context.fetch(FetchDescriptor<ServerConfig>(
    predicate: #Predicate { $0.subscriptionURL == currentPoolURL }
))

// Fetch all configs (для full server list — Phase 3, но и в Phase 2 для empty-state detection)
let all = try context.fetch(FetchDescriptor<ServerConfig>())
```

**Active pool detection в Phase 2:**

Поскольку UI-выбор pool'а — Phase 3, в Phase 2 «активный pool» = последний импортированный. Простая heuristic:

```swift
// Single active pool в v0.2
let mostRecent = try context.fetch(FetchDescriptor<ServerConfig>(
    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
)).first

let activePoolURL = mostRecent?.subscriptionURL
// nil если single-paste import (без subscription URL) — pool = все configs с subscriptionURL == nil
```

**Re-import replace logic (D-07):**

```swift
func replacePool(subscriptionURL: String, with newServers: [ImportedServer], context: ModelContext) async throws {
    // 1. Delete all existing configs from this pool
    let existing = try context.fetch(FetchDescriptor<ServerConfig>(
        predicate: #Predicate { $0.subscriptionURL == subscriptionURL }
    ))
    for config in existing {
        // Cleanup Keychain entry too
        if let tag = config.keychainTag {
            try? KeychainStore.delete(tag: tag)
        }
        context.delete(config)
    }
    
    // 2. Save new ones
    for server in newServers {
        // ... persist
    }
    try context.save()
}
```

---

## 11. HTTP fetch for subscription URLs

### 11.1 URLSession setup

`[VERIFIED: Apple URLSession docs]`

```swift
public actor SubscriptionURLFetcher {
    private let session: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 1  // serial fetches только
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        self.session = URLSession(configuration: config)
    }
    
    public func fetch(url: URL) async throws -> SubscriptionFetchResult {
        guard url.scheme?.lowercased() == "https" else {
            throw FetchError.nonHTTPS(url.scheme ?? "")
        }
        
        var request = URLRequest(url: url)
        request.setValue("BBTB/0.2 (iOS / macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain, application/json, */*", forHTTPHeaderField: "Accept")
        request.setValue("gzip, br", forHTTPHeaderField: "Accept-Encoding")  // URLSession auto-decompresses
        
        let (data, response) = try await session.data(for: request)
        // ... validation
        return SubscriptionFetchResult(...)
    }
}
```

### 11.2 Timeout setting

- `timeoutIntervalForRequest = 30`: 30 секунд hard limit на TCP-handshake + TLS-handshake + first byte. Реалистично для subscription URL на нормальной сети.
- `timeoutIntervalForResource = 60`: общий timeout (включая body download). Subscription body редко больше 100 KB → 60 секунд достаточно.

### 11.3 Redirect handling

`[VERIFIED: URLSession default behavior]`

URLSession по default follows up to 16 redirects. Достаточно для большинства cases (`Moved-Permanently-To` Hiddify header — handled by URLSession если возвращается как HTTP 301/302 Location header).

В Phase 2 — **не override** default. Phase 3 (DPI-08-related) — возможно ограничить до 5 hops для security.

### 11.4 HTTPS enforcement

```swift
guard url.scheme?.lowercased() == "https" else {
    throw FetchError.nonHTTPS(url.scheme ?? "")
}
```

`http://` subscription URL — **reject**. R1-spirit: config содержит secrets (uuid, password); HTTP leak'нет их network observer'у. Если operator на `http://` — он должен переехать на HTTPS (Let's Encrypt бесплатно).

### 11.5 Gzip/Brotli — automatic

`URLSession.data(for:)` автоматически decompress'ит `Content-Encoding: gzip` / `br` / `deflate`. Тело уже decoded в `Data`. **No manual handling needed.**

### 11.6 Cert pinning — NO для v0.2

DPI-08 (certificate pinning) — Phase 7. v0.2 trust'ит system cert store. Это известная DPI-vulnerability (MITM с install'енным root CA — но это unlikely scenario в РФ TSPU context, потому что TSPU не имеет права MitM TLS, только observe/block).

---

## 12. Runtime State Inventory

> Phase 2 — partially rename/refactor: KillSwitch.apply signature change (`apply(to:)` → `apply(to:enabled:)`), SwiftData schema migration, NETunnelProviderManager providerConfiguration changes.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | (1) SwiftData ServerConfig table — Phase 1 rows exist; (2) Keychain entries — Phase 1 secrets (uuid+publicKey+shortId) | (1) Lightweight migration auto-applies — existing rows get `isSupported=true`, `subscriptionURL=nil`, `sni=null`, `rawURI=nil` defaults; verify in W0 test. (2) Keychain entries remain — Phase 2 reads them as-is via existing `keychainTag`. |
| Live service config | One existing NETunnelProviderManager в системе (если user уже импортировал в v0.1) — содержит Phase 1 single-VLESS configJSON | After Phase 2 upgrade, при next import пользователь либо паст'ит новый pool (replace existing providerConfiguration), либо open app + auto-migration (наследовать существующий manager, update providerConfiguration с pool-config из existing single config через legacy → pool transform). **Recommendation:** на app launch в Phase 2 проверить — если есть Phase 1 single-VLESS configJSON, переписать на pool-style config с одним outbound (no urltest при count=1). Это transparent для user. |
| OS-registered state | NETunnelProviderManager в системных VPN settings (название «BBTB») | Display name `BBTB` сохраняется неизменным (D-defaults). User видит ту же VPN-запись. Reconnect required для KILL-03 take-effect. |
| Secrets/env vars | Keychain entries — `keychainTag` ссылка из ServerConfig | После Phase 2 schema migration `keychainTag` опционально. Existing entries — sane defaults, no break. |
| Build artifacts | SwiftPM build cache (.build/), Xcode DerivedData | After Package.swift changes (new sub-modules: `QRScannerFeature`, `SettingsFeature`, новый `Trojan/` package), DerivedData clear не обязателен, но рекомендуется при первом локальном build после merge. |

**Nothing found in category:**
- Database queries against external service (e.g., n8n / ChromaDB / Mem0) — None (clean Apple-native проект).
- OS-level task registrations (cron / launchd / Task Scheduler) — None.
- SOPS secrets — None.

---

## 13. Common Pitfalls

### Pitfall 1: urltest probe URL — HEAD-on-404 passes as success
**What goes wrong:** probe URL возвращает 404; sing-box `client.Do(req)` получает `resp != nil, err == nil`; outbound считается рабочим; реальный user traffic — не работает (TLS-level OK, app-level fail).
**Why it happens:** sing-box urltest source code не проверяет statusCode resp; только проверяет err.
**How to avoid:** использовать probe URL, который **гарантированно** возвращает 204 (canonical: `https://cp.cloudflare.com/generate_204`). Если operator-supplied URL — не trust.
**Warning signs:** outbound в логах sing-box помечен available, но connections к нему обрывают через 5-30 секунд.

### Pitfall 2: urltest switch latency на live dial-error
**What goes wrong:** Selected outbound умер; sing-box возвращает error на `DialContext`; следующий dial — снова selected outbound, снова error; цикл до следующего interval-probe (3 min default).
**Why it happens:** `DialContext` не запускает свежий probe; только `loopCheck()` каждые interval'ы делает.
**How to avoid:** Уменьшить `interval` до `1m` или `30s` в pool template; tolerance `50ms` остаётся.
**Warning signs:** Пользователь видит «нет интернета» на 30-60 секунд после kill primary outbound; через минуту восстанавливается.

### Pitfall 3: WebSocket transport — server-side path mismatch
**What goes wrong:** URI содержит `path=/abc`, sing-box настроен на `path=/abc`, но server-side ожидает `path=/xyz` (e.g., user copied wrong URI fragment); WS upgrade returns 404; sing-box trojan outbound fails handshake.
**Why it happens:** WebSocket path должен совпадать строго.
**How to avoid:** В QA / UAT testing — verify trojan-ws URI с реальной серверной конфигурацией. Документировать в W5 wave (UAT) как required test case.
**Warning signs:** trojan outbound logs «failed to dial: websocket: bad handshake».

### Pitfall 4: SwiftData lightweight migration fails silently
**What goes wrong:** Adding non-optional property without default value → migration fails → SwiftData crashes silently на startup OR drops все existing records.
**Why it happens:** SwiftData lightweight migration requires default values for new non-optional properties.
**How to avoid:** Все new properties либо optional (`String?`) либо имеют explicit default (`= true`). **Тест в W0: создать Phase 1 row → upgrade schema → fetch — verify data preserved.**
**Warning signs:** App launches, but ServerConfig list is empty (вместо migrated rows).

### Pitfall 5: NETunnelProviderManager providerConfiguration not applied on save
**What goes wrong:** `manager.saveToPreferences()` returns success, but new configJSON не применяется в active tunnel.
**Why it happens:** Active tunnel пользуется конфигом, который был при `startVPNTunnel`. Changes apply только при следующем connect.
**How to avoid:** UI должен честно говорить user'у «Переподключитесь для применения». Не делать silent auto-reconnect (D-14 правильное решение).
**Warning signs:** User toggle'ит KILL-03, но active tunnel поведение не меняется → user confused.

### Pitfall 6: Trojan URI password URL-encoded special chars
**What goes wrong:** Password содержит `+`, `=`, `&`, `#` — URL-encoded в URI; декодирование `URLComponents.user` может вернуть encoded form или не handle некоторые символы.
**Why it happens:** RFC 3986 разрешает encoded chars в userinfo, но клиентам нужно явно decode.
**How to avoid:** Использовать `URLComponents(string:).percentEncodedUser?.removingPercentEncoding`, не `.user` (последний может lose info).
**Warning signs:** Trojan handshake fails с «authentication failed» при правильном URI.

### Pitfall 7: Base64 subscription с URL-safe alphabet
**What goes wrong:** Subscription provider использует URL-safe base64 (`-_=`); Swift `Data(base64Encoded:)` принимает только standard (`+/=`).
**Why it happens:** Different conventions в community; some providers use URL-safe для cleaner URI.
**How to avoid:** Preprocess — replace `-` → `+`, `_` → `/`, pad `=`.
**Warning signs:** Subscription fetched, but `Data(base64Encoded:)` returns nil → fall-through to plain-text → URI list empty или garbage.

### Pitfall 8: Hiddify JSON config has `experimental.clash_api` enabled
**What goes wrong:** Operator-supplied sing-box JSON содержит `experimental.clash_api: {external_controller: ":9090"}` — это R1 violation (SEC-02).
**Why it happens:** Hiddify-app использует clash_api для своей UI; operators copy-paste full configs.
**How to avoid:** `SingBoxConfigLoader.validate` rejects → user sees ошибка «config содержит запрещённую секцию clash_api». Operator должен убрать.
**Warning signs:** Subscription URL fetched, validation throws `.experimentalApiEnabled("clash_api")`.

### Pitfall 9: macOS hardened runtime camera entitlement
**What goes wrong:** На macOS app crashes при `AVCaptureDevice.default(for: .video)` если missing `com.apple.security.device.camera` entitlement.
**Why it happens:** Hardened runtime блокирует unauthorized device access.
**How to avoid:** Both `NSCameraUsageDescription` (Info.plist) AND `com.apple.security.device.camera = true` (entitlements) на macOS.
**Warning signs:** App crashes silently при первой попытке открыть QR scanner — no TCC prompt, no error в console.

### Pitfall 10: SwiftUI fullScreenCover camera frame race
**What goes wrong:** `AVCaptureVideoPreviewLayer.frame` set ДО layout completion → preview shows zero-size или wrong aspect → user видит чёрный экран.
**Why it happens:** SwiftUI presentation animation finishes after `viewDidLoad` → bounds зависят от final size.
**How to avoid:** Override `viewDidLayoutSubviews` и установить `previewLayer.frame = view.bounds` там. Не в `viewDidLoad`.
**Warning signs:** QR scanner отображается с чёрной/squashed preview.

---

## 14. Code Examples

Verified patterns from official sources.

### 14.1 Trojan URI parser — minimal

```swift
// Source: trojan-go canonical URL scheme + Apple URLComponents
public enum TrojanURIParser {
    public static func parse(_ uri: String) throws -> ParsedTrojan {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme?.lowercased() == "trojan",
              let host = comps.host, !host.isEmpty,
              let port = comps.port,
              port > 0 && port <= 65535,
              let rawPassword = comps.percentEncodedUser?.removingPercentEncoding,
              !rawPassword.isEmpty
        else {
            throw TrojanURIError.malformedURI
        }
        
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] {
            if let v = item.value { q[item.name] = v }
        }
        
        // R1: security must be tls (D-08)
        let security = q["security"] ?? ""
        guard security.lowercased() == "tls" else {
            throw TrojanURIError.missingTLSSecurity(security.isEmpty ? nil : security)
        }
        
        // Transport: tcp default, ws supported, others reject
        let typeRaw = (q["type"] ?? "tcp").lowercased()
        let transportType: TransportType
        switch typeRaw {
        case "tcp", "original", "": transportType = .tcp
        case "ws": transportType = .ws
        default: throw TrojanURIError.unsupportedTransport(typeRaw)
        }
        
        // WS path required
        var wsPath: String? = nil
        var wsHost: String? = nil
        if transportType == .ws {
            guard let path = q["path"], !path.isEmpty else {
                throw TrojanURIError.missingWSPath
            }
            wsPath = path
            // WS Host header: q["host"] → fallback на sni → fallback на host
            wsHost = q["host"].flatMap { $0.isEmpty ? nil : $0 }
        }
        
        // SNI: q["sni"] → q["peer"] → host
        let sni = q["sni"].flatMap { $0.isEmpty ? nil : $0 } 
                  ?? q["peer"].flatMap { $0.isEmpty ? nil : $0 }
                  ?? host
        
        // ALPN
        let alpn: [String] = (q["alpn"] ?? "h2,http/1.1")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // uTLS fingerprint
        let fp = (q["fp"] ?? q["fingerprint"] ?? "chrome").lowercased()
        let allowedFP: Set<String> = ["chrome", "firefox", "edge", "safari", "360", "qq", "ios", "android", "random", "randomized"]
        let fingerprint = allowedFP.contains(fp) ? fp : "chrome"
        
        let remarks = comps.fragment?.removingPercentEncoding
        
        return ParsedTrojan(
            password: rawPassword,
            host: host, port: port,
            sni: sni, alpn: alpn,
            fingerprint: fingerprint,
            transportType: transportType,
            wsPath: wsPath, wsHost: wsHost,
            remarks: remarks
        )
    }
}
```

### 14.2 urltest config snippet (full pool template)

```json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "dns-remote",
        "address": "https://cloudflare-dns.com/dns-query",
        "address_resolver": "dns-bootstrap",
        "address_strategy": "ipv4_only",
        "detour": "urltest-out"
      },
      {
        "tag": "dns-bootstrap",
        "address": "tcp://77.88.8.8",
        "detour": "direct",
        "strategy": "ipv4_only"
      },
      {
        "tag": "dns-fakeip",
        "address": "fakeip"
      }
    ],
    "rules": [
      { "outbound": "any", "server": "dns-bootstrap" },
      { "query_type": ["HTTPS", "SVCB"], "action": "predefined", "rcode": "NXDOMAIN" },
      { "query_type": ["A", "AAAA"], "server": "dns-fakeip" }
    ],
    "fakeip": {
      "enabled": true,
      "inet4_range": "100.64.0.0/10",
      "inet6_range": "fc00::/18"
    },
    "final": "dns-remote",
    "strategy": "ipv4_only",
    "independent_cache": true
  },
  "outbounds": [
    {
      "type": "vless",
      "tag": "vless-0",
      "server": "...",
      "server_port": 443,
      "uuid": "...",
      "flow": "xtls-rprx-vision",
      "tls": { "enabled": true, "server_name": "...", "utls": {...}, "reality": {...} }
    },
    {
      "type": "trojan",
      "tag": "trojan-1",
      "server": "...",
      "server_port": 2087,
      "password": "...",
      "tls": { "enabled": true, "server_name": "...", "utls": {...} },
      "transport": { "type": "ws", "path": "/...", "headers": {"Host": "..."} }
    },
    {
      "type": "urltest",
      "tag": "urltest-out",
      "outbounds": ["vless-0", "trojan-1"],
      "url": "https://cp.cloudflare.com/generate_204",
      "interval": "1m",
      "tolerance": 50,
      "idle_timeout": "30m",
      "interrupt_exist_connections": false
    },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rules": [
      { "action": "sniff", "timeout": "1s" },
      { "protocol": "dns", "action": "hijack-dns" }
    ],
    "final": "urltest-out",
    "auto_detect_interface": true
  },
  "experimental": {}
}
```

### 14.3 Subscription fetch and detect

```swift
public enum UniversalImportParser {
    public static func `import`(rawInput: String) async throws -> ImportResult {
        let classified = classifyInput(rawInput)
        switch classified {
        case .singleURI(let uri):
            let parsed = try parseURIByScheme(uri)
            return .singleURI(parsed, source: .pasteboard)
        
        case .multilineURIList(let uris):
            let (ok, failed) = importMultipleURIs(uris)
            // log failed; return ok
            return .multipleURIs(ok, source: .multilineText, metadata: nil)
        
        case .subscriptionURL(let url):
            let result = try await SubscriptionURLFetcher().fetch(url: url)
            let bodyStr = String(data: result.body, encoding: .utf8) ?? ""
            let bodyClassified = classifyInput(bodyStr)
            
            switch bodyClassified {
            case .multilineURIList(let uris), .base64URIList(let decodedBody):
                let extractedURIs = bodyClassified.extractURIs() // helper
                let (ok, _) = importMultipleURIs(extractedURIs)
                return .multipleURIs(ok, source: .subscriptionURL(url), metadata: result.metadata)
            
            case .singBoxJSON(let json):
                try SingBoxConfigLoader.validate(json: json)
                let servers = try extractServers(from: json)
                return .singBoxConfig(servers, source: .jsonEndpoint(url), metadata: result.metadata)
            
            default:
                throw ImportError.unknownInputFormat(snippet: String(bodyStr.prefix(80)))
            }
        
        case .singBoxJSON(let json):
            try SingBoxConfigLoader.validate(json: json)
            let servers = try extractServers(from: json)
            return .singBoxConfig(servers, source: .pasteboard, metadata: nil)
        
        case .base64URIList(let decoded):
            let uris = decoded.split(whereSeparator: \.isNewline).map(String.init)
            let (ok, _) = importMultipleURIs(uris)
            return .multipleURIs(ok, source: .pasteboard, metadata: nil)
        
        case .unknown(let snippet):
            throw ImportError.unknownInputFormat(snippet: snippet)
        }
    }
}
```

### 14.4 QR scanner SwiftUI + AVFoundation setup

```swift
// Source: Apple AVFoundation + hackingwithswift.com QR pattern
import SwiftUI
import AVFoundation

#if os(iOS)
public struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void
    
    public func makeUIViewController(context: Context) -> QRScannerVC {
        QRScannerVC(onScan: onScan, onCancel: onCancel, onError: onError)
    }
    public func updateUIViewController(_ uiViewController: QRScannerVC, context: Context) {}
}

final class QRScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer?
    let onScan: (String) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void
    
    init(onScan: @escaping (String) -> Void, onCancel: @escaping () -> Void, onError: @escaping (Error) -> Void) {
        self.onScan = onScan; self.onCancel = onCancel; self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            do {
                try await setup()
            } catch {
                await MainActor.run { onError(error) }
            }
        }
    }
    
    func setup() async throws {
        let granted = try await CameraPermission.request()
        guard granted else { throw QRScannerError.permissionDenied }
        
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw QRScannerError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw QRScannerError.cannotConfigure }
        session.addInput(input)
        
        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else { throw QRScannerError.cannotConfigure }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]
        
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        self.previewLayer = layer
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds  // ← critical: set frame after layout
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue
        else { return }
        
        session.stopRunning()
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        DispatchQueue.main.async { [weak self] in
            self?.onScan(value)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }
}

public enum QRScannerError: Error, LocalizedError {
    case permissionDenied, noCamera, cannotConfigure
    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Камера запрещена. Откройте Настройки → BBTB → Камера."
        case .noCamera: return "Камера недоступна."
        case .cannotConfigure: return "Не удалось настроить камеру."
        }
    }
}
#endif
```

### 14.5 SwiftData lightweight migration test (W0 verification)

```swift
import XCTest
import SwiftData
@testable import VPNCore

@MainActor
final class ServerConfigMigrationTests: XCTestCase {
    func test_phase1_row_migrates_with_defaults() throws {
        let schema = Schema([ServerConfig.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Simulate Phase 1 row creation (without new fields, they default)
        let config1 = ServerConfig(
            name: "Test Latvia",
            host: "93.77.187.150", port: 8443,
            protocolID: "vless-reality",
            keychainTag: "test-tag-123"
        )
        context.insert(config1)
        try context.save()
        
        // Fetch back
        let fetched = try context.fetch(FetchDescriptor<ServerConfig>())
        XCTAssertEqual(fetched.count, 1)
        let row = fetched[0]
        
        XCTAssertEqual(row.name, "Test Latvia")
        XCTAssertEqual(row.host, "93.77.187.150")
        XCTAssertEqual(row.keychainTag, "test-tag-123")
        
        // Phase 2 fields with defaults
        XCTAssertEqual(row.isSupported, true)  // default
        XCTAssertNil(row.subscriptionURL)
        XCTAssertNil(row.sni)
        XCTAssertNil(row.rawURI)
    }
}
```

---

## 15. State of the Art

| Old Approach (Phase 1) | Current Approach (Phase 2) | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Singleton VLESS+Reality config | Pool of supported configs via sing-box `urltest` | Phase 2 D-01 | Multi-server, auto-fallback в одном VPN-профиле |
| Single `ServerConfig` with `isActive` flag | Array of `ServerConfig`s with `isSupported`, `subscriptionURL`, `rawURI` | Phase 2 D-06 | Multi-server SwiftData, foundation для Phase 3 server-list |
| `KillSwitch.apply(to:)` без параметризации | `KillSwitch.apply(to:enabled:)` | Phase 2 D-12, D-15 | UI toggle поверх существующего kill switch механизма |
| Single template `SingBoxConfigTemplate.vless-reality.json` | Multiple per-protocol templates + pool builder | Phase 2 D-discretion | Поддержка Trojan + extensibility для Phase 4+ |
| `ConfigImporter.importFromPasteboard()` only | `ConfigImporter.import(rawInput:source:)` универсальный | Phase 2 D-02 | QR + URL + multi-line + JSON endpoint all supported |
| `validate` требует `vless` outbound | `validate` требует любой proxy outbound | Phase 2 §7.2 | Trojan-only pool валидируется |

**Deprecated/outdated:**
- `noVLESSOutbound` error case — removed (replaced by `noProxyOutbound`).
- `ImportFromClipboardButton.swift` в MainScreenFeature — удаляется, replaced by меню «+» в top bar.
- Hardcoded VLESS template `${VLESS_FLOW}` substitution — продолжается, но теперь часть универсального builder pattern.

---

## 16. Validation Architecture

Phase 2 продолжает Nyquist validation enabled в config.json `workflow.nyquist_validation: true`.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest + Swift Testing (Apple-native, Phase 1 carry-forward) |
| Config file | Package.swift testTargets |
| Quick run command | `swift test --filter ConfigParserTests/TrojanURIParser` |
| Full suite command | `swift test --package-path BBTB/Packages/ConfigParser` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| PROTO-02 | Trojan URI parsed correctly (TCP + WS variants) | Unit | `swift test --filter TrojanURIParserTests` | ❌ W0 — `Packages/ConfigParser/Tests/ConfigParserTests/TrojanURIParserTests.swift` |
| PROTO-02 | Trojan template substitution produces valid sing-box JSON | Unit | `swift test --filter TrojanConfigBuilderTests` | ❌ W0 — `Packages/Protocols/Trojan/Tests/TrojanTests/TrojanConfigBuilderTests.swift` |
| PROTO-10 | PoolBuilder produces valid urltest config from N outbounds | Unit | `swift test --filter PoolBuilderTests` | ❌ W0 |
| IMP-02 | QR scanner returns URI string on detection | Manual (UAT) | Tests on real device: scan QR с user's iPhone | ❌ W5 UAT — не automated |
| IMP-04 | UniversalImportParser handles все 3 формата + URI list | Unit | `swift test --filter UniversalImportParserTests` | ❌ W0 |
| KILL-03 | Toggle persists to UserDefaults; `KillSwitch.apply(enabled: false)` doesn't set includeAllNetworks | Unit | `swift test --filter KillSwitchTests` | partial — `Packages/KillSwitch/Tests/...` exists from Phase 1, extend |
| SRV-01 (foundation) | urltest config validates через SingBoxConfigLoader | Unit | `swift test --filter SingBoxConfigLoaderTests` | partial — Phase 1 tests exist, extend with urltest fixtures |
| SwiftData migration | Phase 1 row → Phase 2 schema preserves data | Unit | `swift test --filter ServerConfigMigrationTests` | ❌ W0 — `Packages/VPNCore/Tests/VPNCoreTests/ServerConfigMigrationTests.swift` |
| Trojan smoke test (real server) | Trojan-WS handshake succeeds against vpn.vergevsky.ru | Manual (UAT) | Device test with real fixture | ❌ W5 UAT |
| Auto-fallback | Kill primary outbound mid-stream → traffic continues через secondary в течение 60s | Manual (UAT) | Device test: physically block primary IP в router | ❌ W5 UAT |
| Universal parser (user fixtures) | Все 3 user fixtures parse без ошибок | Integration | `swift test --filter UniversalImportParserIntegrationTests` | ❌ W0 |

### Sampling Rate
- **Per task commit:** `swift test --package-path BBTB/Packages/<changed-package>`
- **Per wave merge:** `swift test --package-path BBTB/Packages/{ConfigParser,VPNCore,KillSwitch,PacketTunnelKit,Protocols/Trojan,AppFeatures}`
- **Phase gate:** Full suite green + UAT verified before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/TrojanURIParserTests.swift` — TrojanURIParser comprehensive tests (TCP, WS, all edge cases, all 7 user fixtures from CONTEXT.md `<specifics>`)
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/UniversalImportParserTests.swift` — classification logic, all 3 subscription formats, dispatch
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/SubscriptionFetcherTests.swift` — URLSession mocking, HTTPS enforcement, header parsing
- [ ] `BBTB/Packages/Protocols/Trojan/` — new sub-package; tests folder + ConfigBuilder + Handler
- [ ] `BBTB/Packages/AppFeatures/Sources/SettingsFeature/` — new sub-module (no tests Phase 2; UAT manual)
- [ ] `BBTB/Packages/AppFeatures/Sources/QRScannerFeature/` — new sub-module
- [ ] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerConfigMigrationTests.swift` — migration test
- [ ] `BBTB/Packages/PacketTunnelKit/Resources/SingBoxConfigTemplate.trojan.json` — new template (or two: trojan-tcp + trojan-ws)
- [ ] `BBTB/Packages/PacketTunnelKit/Resources/SingBoxConfigTemplate.pool.json` — urltest wrapper template

---

## 17. Security Domain

`security_enforcement` остаётся enabled (carry-forward Phase 1).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Trojan password — secret в Keychain (Phase 1 pattern) |
| V3 Session Management | no | No web sessions; VPN session managed by ОС |
| V4 Access Control | yes | App Group для shared Keychain access between main+extension |
| V5 Input Validation | **yes (critical)** | UniversalImportParser, TrojanURIParser, SubscriptionURLFetcher все принимают untrusted external input |
| V6 Cryptography | yes | TLS via Apple SecureTransport + libbox; nothing hand-rolled |
| V7 Error handling | yes | Error types per-source (FetchError) vs per-config (URIParseError) |
| V8 Data Protection | yes | Keychain `kSecAttrAccessibleWhenUnlocked` (Phase 1 carry-forward); App Group container readable only by signed extensions |
| V9 Communications | **yes (critical)** | HTTPS-only subscription URL, no cert pinning v0.2 (DPI-08 Phase 7) |

### Known Threat Patterns for Phase 2

| Pattern | STRIDE | Standard Mitigation | Phase 2 status |
|---------|--------|---------------------|-----------------|
| Malicious subscription URL injects clash_api | Tampering | SingBoxConfigLoader.validate rejects `experimental.clash_api` | ✅ existing Phase 1 |
| Malicious subscription URL injects SOCKS5 inbound | Tampering | SingBoxConfigLoader.validate rejects forbidden inbound types | ✅ existing Phase 1 |
| Trojan URI password injection (special chars в URI) | Tampering | URLComponents-based parsing + percent-encoding handling | ✅ documented §3.3 |
| QR code with non-URI payload | Tampering | UniversalImportParser classifies; non-URI → error без apply | ✅ §6.3 |
| Subscription URL via HTTP (clear-text) | Information Disclosure | HTTPS-only enforcement (URLSession check) | ✅ §11.4 |
| Subscription URL MITM | Information Disclosure | TLS system cert validation (DPI-08 pinning — Phase 7) | partial — basic TLS only v0.2 |
| Subscription content has malicious URI | Tampering | Per-URI parse isolation; one failure не abort'ит whole import | ✅ §6.4 |
| KILL-03 toggle race condition (toggle during active tunnel) | DoS (user accidentally disables protection) | Banner "Переподключитесь" + persistence в UserDefaults — toggle take-effect только на reconnect | ✅ §9.3 |
| QR camera scope creep (camera для других вещей) | Spoofing (TCC) | Camera used ТОЛЬКО в QRScannerFeature; AVCaptureSession stopped on dismiss | ✅ §8.4 |
| Trojan WebSocket Host header smuggling | Tampering | Sing-box validates server-side; client просто отправляет URI-derived Host | ✅ documented §2.3 |
| Operator's malicious JSON config has self-signed cert in custom outbound `certificate_path` | Tampering | SingBoxConfigLoader на v0.2 не проверяет custom certificate paths в outbounds — TODO Phase 7 add'l validation | ⚠️ open — flagged для Phase 7 |
| URLSession follows malicious redirect (Subscription URL redirected to HTTP) | Information Disclosure | URLSession follows HTTPS redirects; final URL HTTPS-check needed | ⚠️ partial — verify final response URL scheme |

---

## 18. Sources

### Primary (HIGH confidence)
- `[VERIFIED]` `github.com/SagerNet/sing-box/blob/main/docs/configuration/outbound/urltest.md` — urltest schema
- `[VERIFIED]` `github.com/SagerNet/sing-box/blob/main/docs/configuration/outbound/trojan.md` — trojan schema
- `[VERIFIED]` `github.com/SagerNet/sing-box/blob/main/docs/configuration/shared/tls.md` — TLS block schema incl. utls.fingerprint allowed values
- `[VERIFIED]` `github.com/SagerNet/sing-box/blob/main/docs/configuration/shared/v2ray-transport.md` — WebSocket transport schema
- `[VERIFIED]` `github.com/SagerNet/sing-box/blob/main/docs/configuration/shared/multiplex.md` — multiplex (not used Phase 2)
- `[VERIFIED]` `github.com/SagerNet/sing-box/blob/main/common/urltest/urltest.go` — URLTest function: HEAD request, 5s timeout, no statusCode check
- `[VERIFIED]` `github.com/SagerNet/sing-box/blob/main/protocol/group/urltest.go` — switch logic, performUpdateCheck, loopCheck
- `[VERIFIED]` `github.com/SagerNet/sing-box/blob/main/docs/changelog.md` — sing-box 1.13.x changelog (1.13.11 latest stable as of 2026-04-22)
- `[VERIFIED]` `developer.apple.com/forums/thread/692546` — Apple DTS Matt Eaton on NETunnelProviderManager save/reconnect
- `[VERIFIED]` `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift` — existing Phase 1 validator
- `[VERIFIED]` `BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift` — existing Phase 1 parser pattern
- `[VERIFIED]` `BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift` — existing apply(to:) signature

### Secondary (MEDIUM confidence)
- `[CITED]` `azadzadeh.github.io/trojan-go/en/developer/url/` — trojan URI scheme canonical doc
- `[CITED]` `hiddify.com/app/URL-Scheme/` — Hiddify subscription headers spec
- `[CITED]` `github.com/hiddify/hiddify-app/wiki/URL-Scheme` — Hiddify wiki on subscription format
- `[CITED]` `github.com/2dust/v2rayNG/issues/2746` — v2rayN User-Agent convention
- `[CITED]` `hackingwithswift.com/quick-start/swiftdata` — SwiftData lightweight migration patterns
- `[CITED]` `momoproxy.com/blog/gstatic-generate-204-vs-cloudflare-204` — probe URL comparison
- `[CITED]` `developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.camera` — macOS camera entitlement
- `[CITED]` `developer.apple.com/documentation/avfoundation/avcapturemetadataoutput` — AVCaptureMetadataOutput API
- `[CITED]` `kean.blog/post/vpn-configuration-manager` — save → load workaround pattern (Phase 1 RESEARCH already cited)

### Tertiary (LOW confidence — flagged for validation)
- `[ASSUMED]` JSON endpoint user fixture `https://1.2.3.4:port/json/...` returns Hiddify-style sing-box JSON — inferred from path pattern, **needs verification with actual fixture content** during Phase 2 implementation
- `[ASSUMED]` `urltest` interval=1m is good balance for РФ ТСПУ — **needs empirical UAT verification** in Phase 2 W5
- `[ASSUMED]` URLSession redirect following — 16 max default — based on community docs, **not strict-verified Apple-side**

---

## 19. Assumptions Log

> Список assumed claims в этом research'е. Discuss-phase / planner / user используют это для подтверждения перед execution.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | User fixture vol. 3 `https://1.2.3.4:port/json/...` возвращает Hiddify-style sing-box JSON | §5.1 | **Medium** — если возвращает что-то другое (V2Ray-format / custom format), JSONEndpoint pipeline не обработает. Mitigation: UAT в Phase 2 W5 на реальном endpoint'е, обработка ошибки graceful (показать user'у «формат не распознан»). |
| A2 | `interval=1m` is correct balance для ТСПУ failure detection | §1.4 | **Medium** — слишком частые probes = network noise; слишком редкие = долгое silent failure. Validation в Phase 2 UAT через искусственно убитый primary outbound. |
| A3 | `cp.cloudflare.com/generate_204` отвечает на HEAD (не только GET) с 204 | §1.5 | **Low** — Cloudflare standard endpoint, HEAD должен работать. Verification: simple curl test перед Phase 2 W3. |
| A4 | URLSession follows HTTPS redirects to final URL без degradation в HTTP | §11.3 | **Low-medium** — если provider 301-редиректит на HTTP версию, мы leak'нем config. Mitigation: проверить `response.url?.scheme == "https"` после fetch. **Recommendation:** добавить explicit check в SubscriptionURLFetcher. |
| A5 | macOS hardened runtime требует `com.apple.security.device.camera` entitlement | §8.3 | **Low** — verified via Apple docs, но не tested в Phase 1 (camera не использовалась). Test в Phase 2 W4 (UI implementation) — macOS QR scan должен работать. |
| A6 | SwiftData lightweight migration для добавления optional fields работает «just works» без VersionedSchema | §10.3 | **Low** — verified via hackingwithswift docs, но Phase 1 не делал migration. Test в Phase 2 W0 (migration test). |
| A7 | Multi-protocol urltest pool работает stable в libbox 1.13.11 на iOS NE | §1.4 | **Medium** — Phase 1 W5 device debug показал что libbox 1.13.11 имеет квирки (`mixed` stack не работает в нашей сборке). Verification: integration test с 2-3 outbounds (vless + trojan) на устройстве в Phase 2 W5 UAT. |
| A8 | sing-box trojan outbound с WebSocket transport handles binary trojan handshake correctly через WS frames | §2.3 | **Low** — standard sing-box feature, used in production by Hiddify. Verification: smoke test против vpn.vergevsky.ru Trojan-WS fixture. |
| A9 | Hiddify-style headers (`profile-title`, `profile-update-interval`) приходят в HTTP response от subscription URL'а user'а | §4.4 | **Medium** — depends on provider implementation. Could be missing → fallback на default name (host:port). Phase 2 UAT verification на user's real subscription. |
| A10 | URLSession не имеет hard limit на response body size для subscription | §11.1 | **Low** — Apple URLSession theoretical limit is several GB; subscription is < 100 KB realistic. |
| A11 | iOS sandbox protects from cross-app loopback access (Phase 1 R1 assumption carries forward) | §17 | **Low** — Phase 1 SocksProbe verification confirmed; Phase 2 не нарушает. |

**Risk-mitigation strategy:** All MEDIUM-risk assumptions require UAT validation в Phase 2 W5 wave перед `/gsd-verify-work`. Planner должен включить explicit UAT items для каждого MEDIUM-risk assumption.

---

## 20. Open Questions для планировщика

1. **WebSocket transport — отдельный template или conditional substitution?**
   - What we know: §2.6 — варианты A (два template'а), B (conditional substitution), C (Codable model).
   - What's unclear: trade-off complexity vs maintenance vs code reuse в Phase 4+ когда добавим больше protocols.
   - Recommendation: **Вариант A** для Phase 2 (pragmatic), переход на C в Phase 4 (когда добавим ss/vmess/hy2 — они имеют разные transport options, conditional substitution не масштабируется).

2. **urltest interval default value — 1m или 30s?**
   - What we know: §1.4 рекомендует `1m`; sing-box default 3m слишком медленно для нашего case.
   - What's unclear: empirical sweet spot для РФ TSPU характеристик блокировки (нет statistical data).
   - Recommendation: **`1m` в template**, конфигурируемо через `Resources/SingBoxConfigTemplate.pool.json`. Если в Phase 2 W5 UAT обнаружится что 1m недостаточно — поднять до 30s в Phase 3 patch.

3. **PoolBuilder special case для single supported outbound — нужен ли urltest?**
   - What we know: §6.5 рекомендует skip urltest при count=1 → degenerate config с direct `route.final = outbound-tag`.
   - What's unclear: trade-off — skip-urltest упрощает config (no useless probes), но запускает refactor'инг при добавлении второго outbound (= switch на urltest config).
   - Recommendation: **Skip urltest при count=1** — это покрывает Phase 1 → Phase 2 transition path (existing user с одним server-ом получит идентичное поведение). Когда добавляется второй outbound, config rebuild уже происходит — normal flow.

4. **ConfigBuilder refactor — universal builder или per-protocol builders?**
   - What we know: CONTEXT.md (D-discretion) оставляет за planner'ом.
   - What's unclear: extensibility cost для Phase 4+ (5+ протоколов).
   - Recommendation: **Per-protocol ConfigBuilders + PoolBuilder.** Trojan получает `TrojanConfigBuilder.buildOutbound(parsed:)` returning `[String: Any]` outbound dict. PoolBuilder обводит их в pool template. Не общий universal builder — он будет messy. Phase 4 добавит `ShadowsocksConfigBuilder`, `VMessConfigBuilder`, etc. — each minimal and focused.

5. **HTTP-probe URL для urltest — hardcoded в template или configurable через Settings?**
   - What we know: CONTEXT.md (D-discretion) рекомендует `cp.cloudflare.com/generate_204`. Опционально configurable.
   - What's unclear: Phase 2 scope vs Phase 7 anti-DPI suite scope.
   - Recommendation: **Hardcoded в Phase 2** template. Phase 7 (anti-DPI Settings) добавит «Custom probe URL» field в Advanced settings → переезд по проектности.

6. **iOS bundle id для Trojan target нужен ли?**
   - What we know: Phase 1 имеет PacketTunnelExtension targets для iOS и macOS. Trojan не нуждается в отдельном target — он outbound внутри sing-box, который уже в PacketTunnelExtension.
   - What's unclear: ничего.
   - Recommendation: **Не нужно отдельных targets для Trojan.** Existing PacketTunnelExtension targets handle все protocols через unified sing-box config.

7. **Сохранение `rawURI` в ServerConfig — для чего?**
   - What we know: §10.2 — поле для re-parse при handler upgrade.
   - What's unclear: trade-off privacy (URI содержит secrets) vs functionality.
   - Recommendation: **Сохранить** `rawURI: String?` — но **БЕЗ secrets** (mask password / uuid placeholder'ом перед persistence; original secrets уже в Keychain). Это enables Phase 4 transition «когда Trojan handler был unsupported в Phase 2, теперь supported → авторегистрация в urltest без user re-import».
   - Альтернатива: regenerate URI из ServerConfig fields + Keychain secret при handler upgrade. Это cleaner privacy-wise.
   - **Final recommendation:** **regenerate URI from fields + Keychain** — не сохранять rawURI с секретами. Это безопаснее.

8. **macOS Settings entry-point — Cmd+, через `Settings { ... }` Scene или дублирующий menu icon?**
   - What we know: D-discretion рекомендует «оба» (Settings Scene + menu icon).
   - What's unclear: SwiftUI `Settings` Scene на macOS открывает отдельное окно с standardised macOS look. Если меню-иконка в main window открывает тот же view in modal — двойное окно может смутить user'а.
   - Recommendation: **`Settings { SettingsView() }` Scene** для Cmd+, (стандартная macOS UX) + меню-иконка main window открывает **тот же** `Settings { ... }` window programmatically (через `OpenSettingsAction` SwiftUI 16+ или `@Environment(\.openSettings)` в SwiftUI 17+). Не делать NavigationStack push на macOS.

9. **SettingsView UI на iOS — push в NavigationStack или sheet / fullScreenCover?**
   - What we know: D-decisions говорит «NavigationStack push» (D-9).
   - What's unclear: ничего, just confirm.
   - Recommendation: **NavigationStack push** на iOS. Стандартная iOS UX.

10. **Migration test для Phase 2 — runtime migration или SwiftData snapshot test?**
    - What we know: §10.3 — lightweight migration auto-applies; § 14.5 — test code skeleton.
    - What's unclear: testable in unit test vs needs actual SQLite file.
    - Recommendation: **In-memory ModelContainer** test (`isStoredInMemoryOnly: true`) с creating Phase 1-style row, then fetching back и проверкой defaults. Этого достаточно для verification.

---

## 21. Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| sing-box / libbox.xcframework | All Phase 2 work (vendored Phase 1) | ✓ | 1.13.11 (vendored) | — |
| Xcode | All Phase 2 work | ✓ | 16+ (Phase 1 carry-forward) | — |
| Swift toolchain | Same | ✓ | 5.10 / 6.0 mode | — |
| iOS Simulator (iOS 18+) | UI testing | ✓ | Bundled with Xcode 16 | — |
| Real iOS device | Camera testing (Simulator не имеет камеры) | ✓ | User's iPhone | If absent: skip QR UAT, mark IMP-02 as «UAT pending real device» |
| Real macOS device | macOS UAT | ✓ | User's Mac | — |
| User's real subscription URL (`https://vpn.vergevsky.ru/sub/...`) | Subscription URL UAT | ✓ | User-managed | — |
| User's real JSON endpoint (`https://1.2.3.4:port/json/...`) | JSON endpoint UAT | ✓ | User-managed | — |
| Apple Developer Account (`UAN8W9Q82U`) | Code signing | ✓ | Phase 1 verified | — |
| Apple Distribution credentials | TestFlight (not Phase 2 scope) | ✗ | — | Skip — Phase 12 prerequisite (per memory) |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:**
- Distribution creds — not needed для Phase 2 (internal-tier testing OK).

---

## 22. Metadata

**Confidence breakdown:**
- sing-box urltest / trojan / WS schemas: HIGH — source code прочитан, official docs прочитаны
- Trojan URI scheme parsing: HIGH — multiple authoritative sources cross-verified; user fixtures обеспечивают real-world test
- AVFoundation QR scanner: HIGH — Apple-native APIs, multiple references
- NETunnelProviderManager update semantics: HIGH — Apple DTS verified + Phase 1 existing pattern
- SwiftData lightweight migration: HIGH — Apple docs + community confirms
- Hiddify subscription format: MEDIUM — community-документация не RFC; varies across providers
- "Silent ТСПУ" detection via urltest: MEDIUM — source code analyzed but no real-world ТСПУ test (Phase 2 UAT задача)
- Probe URL `cp.cloudflare.com/generate_204` HEAD behavior: MEDIUM — assumed standard but not curl-tested в этом research (rec for W3 verification)

**Research date:** 2026-05-11
**Valid until:** 2026-08-11 (~3 months — sing-box releases каждые ~1-2 месяца; Apple docs стабильнее)

**Total length:** ~1100 lines markdown.

---

*Phase 2 research complete. Ready for `/gsd-plan-phase 2`.*
*Downstream: `gsd-planner` consumes this RESEARCH.md + 02-CONTEXT.md + 02-UI-SPEC.md to produce wave PLAN.md files.*
