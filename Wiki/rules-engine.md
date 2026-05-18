---
name: Rules Engine
description: Phase 8 final state — Ed25519-signed rules pipeline, split-tunnel через sing-box rule_set, архитектурные решения D-01..D-13 (v0.8 2026-05-15)
type: project
---

# Rules Engine

**Summary**: Централизованный `rules.json` с Ed25519-подписью. Иерархия `block_completely > never_through_vpn > always_through_vpn > default`. Скачивается с primary VPS + failover-зеркала, обновляется раз в 6 часов. Применяется через sing-box `route.rule_set` (binary SRS format). **Phase 8 (v0.8) — полностью реализован 2026-05-15.** **Phase 13 (v0.13) — добавлен user toggle (D-14) для отключения routing rules целиком (full tunnel mode).**

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md, Phase 8 CONTEXT.md, Phase 13 CONTEXT.md, Codex threads 019e2841 + 019e284c + 019e3210.

**Last updated**: 2026-05-16 (Phase 13 D-14 routing rules toggle)

---

## Зачем

Администратор (разработчик) должен иметь возможность **централизованно** управлять поведением приложения у всех пользователей без выпуска нового билда. Сценарии:

- срочно заблокировать вредный домен (например, MAX — см. [[max-messenger]])
- маршрутизировать конкретный сервис через VPN независимо от настроек пользователя
- разрешить домены, которые ломаются через VPN (банки, госуслуги) — пускать напрямую

## Архитектура (Phase 8, v0.8)

```
VPS admin workflow:
  rules.json → sing-box rule-set compile → 3 x .srs (binary SRS)
             → Ed25519 sign each file    → .srs.sig (detached)
             → sign manifest             → baseline-rules-manifest.json + .sig
             → publish на primary + зеркала

Client pipeline (RulesEngineCoordinator):
  cold start → BaselineRulesLoader (bundle baseline → App Group cache)
             → RulesFetcher (primary URL → 3 mirrors failover, sequential)
             → RulesSigner.verify(manifest) + verify each .srs.sig
             → SRSCacheStore.write (atomic via Data.write options: .atomic)
             → notify PacketTunnelExtension (App Group auto-reload)

PacketTunnel pipeline (SingBoxConfigLoader):
  expandConfigForTunnel(_:)
    → inject 3 route.rule_set entries (type: local, format: binary, path: App Group)
    → inject 3 priority rules: block→reject | never→direct | always→urltest-auto
    → post-expand validate (R1 + R10 invariants)
    → libbox startOrReloadService
```

### Компоненты (SwiftPM пакет `RulesEngine`)

| Файл | Роль |
|------|------|
| `PublicKey.swift` | 32-byte Ed25519 pubkey — compile-time constant |
| `RulesSigner.swift` | `Curve25519.Signing.PublicKey.isValidSignature(_:for:)` + `SignatureVerifierProtocol` |
| `RulesFetcher.swift` | HTTPS + `isBlockedHost` SSRF guard + sequential mirror failover |
| `RulesManifest.swift` | Codable: version / minAppVersion / srsFormatVersion / files[] / categoryBodies |
| `SRSCacheStore.swift` | actor — atomic writes to App Group `Library/Caches/rules/` |
| `BaselineRulesLoader.swift` | Bundle.module first-run hydration |
| `RulesEngineCoordinator.swift` | top-level actor — orchestrates fetch + verify + cache + notify |
| `RulesSnapshot.swift` | Sendable/Equatable value for UI display |
| `Clock.swift` | ClockProtocol + SystemClock (injectable for tests) |

### Правила маршрутизации (D-01)

| Категория | sing-box action | Приоритет |
|-----------|----------------|-----------|
| `block_completely` | `reject` | 1 (highest) |
| `never_through_vpn` | `direct` (bypass tunnel) | 2 |
| `always_through_vpn` | `urltest-auto` (via tunnel, inherits Protocol failover) | 3 |
| default | пользовательский тоггл | 4 (lowest) |

## Структура rules.json (server-side)

```json
{
  "version": 1,
  "min_app_version": "0.8.0",
  "srs_format_version": 1,
  "updated_at": "2026-05-15T00:00:00Z",
  "total_size_bytes": 134,
  "block_completely": {
    "domains": ["max.ru", "mssgr.tatar.ru"],
    "ip_cidrs": [],
    "countries": []
  },
  "never_through_vpn": {
    "domains": ["sberbank.ru", "gosuslugi.ru"],
    "ip_cidrs": [],
    "countries": ["RU"]
  },
  "always_through_vpn": {
    "domains": ["telegram.org"],
    "ip_cidrs": [],
    "countries": []
  },
  "files": [
    {
      "name": "bbtb-baseline-block.srs",
      "sig_path": "bbtb-baseline-block.srs.sig",
      "sha256": "...",
      "size_bytes": 44
    }
  ]
}
```

## Архитектурные решения Phase 8 (D-01..D-13)

### D-01: Server-side SRS pipeline через sing-box `route.rule_set`

_(Codex thread `019e2841`)_

VPS компилирует `rules.json` → 3 binary `.srs` файла (`sing-box rule-set compile`) + подписывает Ed25519. Клиент скачивает уже скомпилированные SRS-ы и инжектирует их в конфиг через `SingBoxConfigLoader.expandConfigForTunnel(_:)`. Sing-box перечитывает SRS из App Group файловой системы через `type: local` автоматически (libbox 1.13.11 поддерживает auto-reload с 1.10.0).

**Почему:** sing-box rule_set binary формат — единственный performant способ; клиентская MMDB база неприемлема (100+ MB). Client-compile SRS потребовал бы embed Go-компилятора.

### D-02: Domain/IP/Country mapping в SRS rules

- `domains` → sing-box `domain_suffix` matcher в SRS
- `ip_cidrs` → `ip_cidr` matcher
- `countries` → server-side expanded в CIDR-набор (D-04), затем `ip_cidr` в SRS

### D-03: DNS sniffing обязателен для domain matching

`sniff: true` в TUN inbound → sing-box определяет domain из DNS запроса / TLS SNI. Без sniff `domain_suffix` rules не работают. TUN inbound уже выставлен в `expandConfigForTunnel` Phase 1 R10; Phase 8 не меняет эту настройку.

### D-04: Full server-side country resolve в v0.8

`"countries": ["RU"]` в admin field → VPS разворачивает в CIDR-набор (из MaxMind GeoIP или ip-api.com bulk) на момент signing → включается в SRS как `ip_cidr` entries. Никаких client-side MMDB лукапов. Точность GeoIP зависит от admin data source.

### D-05: Embedded baseline `baseline-rules.json` (signed) в .app bundle

Baseline SRS (signed) shipped в Bundle.module под `RulesEngine/Resources/`. `BaselineRulesLoader` гидрирует App Group cache при первом запуске (до первого server fetch). Один trust-path с серверным rules (та же Ed25519 pubkey).

### D-07: Two-file Ed25519 signature (`rules.json` + `rules.json.sig`)

Detached signature scheme: `rules.json` + `rules.json.sig` (64-byte raw Ed25519 sig). Manifest file (`baseline-rules-manifest.json`) содержит SHA-256 + sig_path для каждого SRS. Coordinator verifies manifest sig first, then each SRS sig independently.

### D-08: RULES-11 + Phase 8 SC #3 → Out of Scope, v0.10+ conditional

_(Codex thread `019e284c`)_

macOS per-app routing через `NEAppProxyProvider` (L4) ↔ sing-box L3 TUN — архитектурный mismatch. `NETunnelProviderManager` ↔ `NEAppProxyProviderManager` — mutual exclusivity (один manager в системе). Реализация через SOCKS5 bridge ломает R1 (no localhost listen-on-SOCKS5). **Решение: defer to v0.10+** conditional on real user demand (0 confirmed TestFlight requests). Workaround — `never_through_vpn` rule_set покрывает 95% TestFlight scenarios.

Подробнее: [[appproxy-deferral-2026]].

### D-09: AppProxyExtension-macOS target → DELETE из Tuist

`BBTB/App/AppProxyExtension-macOS/` и target `AppProxyExtension-macOS` в `Project.swift` удалены в Phase 8 W0. `app-proxy-provider` capability удалена из `BBTB-macOS.entitlements`. Apple Developer Portal: capability при необходимости re-add для v0.10.

Invariant: `validate-r1-r6.sh` D-08 checks `! grep -rE "NEAppProxyProvider"` in main app sources.

### D-10: Force-update button cooldown = 60 секунд

UI disabled с countdown «Подождите Ns». `ForceUpdateButtonStateTests` проверяет state machine. Защита VPS от случайного flood на ручном refresh.

### D-11: `min_app_version` UX = modal sheet + persistent banner

Если `manifest.minAppVersion > currentAppVersion`:
1. `MinAppVersionSheet` — modal поверх main screen (dismissible, `@AppStorage` per-version flag для повторного показа)
2. `MinAppVersionBanner` — persistent banner в Settings → Advanced

НЕ full-screen takeover: TestFlight обновит автоматически, пользователю нужна возможность закрыть и пользоваться приложением в режиме ожидания.

### D-12: rules.json не блокирует cold start (DEC-06d-01)

Bootstrap baseline применяется немедленно из bundle (D-05); server fetch — background task (`BGAppRefreshTask` iOS / `NSBackgroundActivityScheduler` macOS). Main thread не блокируется.

### D-13: Failover mirrors max concurrency = 1 (sequential)

При boot fetch и при force-update — sequential (concurrency=1): primary → mirror 1 → mirror 2 → mirror 3. Per DEC-06d-04 bounded probe concurrency principle.

### D-14 (Phase 13): User toggle для отключения routing rules целиком

_(Phase 13 Plan 01, Codex thread `019e3210`, commits `bbe2493` → `f1eab97`)_

**Контекст:** Перед TestFlight v0.13 пользователь попросил добавить toggle «Правила маршрутизации» в Advanced Settings — чтобы при желании можно было выключить block/never/always и весь трафик отправить через VPN (full tunnel mode).

**Решение (Вариант 1 из 2 после code review):**

- `SettingsViewModel.routingRulesEnabled` — `@AppStorage("app.bbtb.routingRulesEnabled", store: UserDefaults(suiteName: "group.app.bbtb.shared"))`, default `true`. App Group suite **обязателен** — extension читает напрямую (паттерн идентичен `stunBlockEnabled` D-16, `muxEnabled` DPI-05).
- `SingBoxConfigLoader.expandConfigForTunnel` блок 5 (Phase 8 W5 injection of 3 rule_set + 3 priority rules) обёрнут чтением toggle. Default fallback при отсутствующем ключе → `true` (backward compat: existing 57/57 SingBoxConfigLoaderTests green).
- Toggle OFF → extension полностью skip-ит rule_set decls + priority rules → весь трафик через `route.final` → full tunnel.
- Toggle ON → Phase 8 W5 path как раньше (signed binary SRS остаются authoritative).

**Что отвергли (Вариант 2):** inline-rules path из main app (`PoolBuilder.extraRules` параметр + `RulesEngineCoordinator.currentSnapshot()` через MainScreenViewModel) — реализован в `bbe2493`, откачен в `f1eab97`. Причины:

1. **Параллельный injection conflict** — Phase 8 W5 в extension инжектил rule_set безусловно, перед main-app rules в той же позиции (после `hijack-dns`). First-match wins → свежий snapshot main app проигрывал baseline `.srs`.
2. **`outbound: "block"` некорректен** — нет outbound с tag `block` в outbounds array. Проектный паттерн `action: "reject"` (`SingBoxConfigLoader.swift:360`).
3. **Security regression** — main-app authority вместо signed manifest. Если приложение скомпрометировано — любые routing rules можно подсунуть extension. Phase 8 R1/R10 invariants терялись.

**Преимущества Варианта 1:**

- Signed binary manifest остаётся single source of truth (defence-in-depth).
- −150 строк кода vs Вариант 2.
- Существующие тесты (57/57 SingBoxConfigLoaderTests + 11/11 Phase 12 snapshot baselines) — green без изменений.

**Пользовательский UX:**

- Toggle живёт в Advanced Settings → Section 5b (между Rules Viewer и Force-update button).
- L10n: EN «Routing rules» / RU «Правила маршрутизации»; footer объясняет «full tunnel mode».
- Applies on next reconnect (paint: NEVPNConnection rebuild при provisionTunnelProfile next call). User-facing документация footer'ом «применится при следующем подключении» **не указана** — TODO Phase 13+ UX polish если поступят жалобы (паттерн `needsReconnectForKillSwitch` существует для подобных сценариев).

**Известные ограничения (carry-forward, не blocking):**

- Changing toggle while `.connected` — apply только при manual reconnect. Не auto-reconnect (как `needsReconnectForKillSwitch` для KILL toggle). UX-04 candidate для Phase 13+ polish если user feedback потребует.
- Toggle key `app.bbtb.routingRulesEnabled` в App Group → если admin sign'нёт rules.json с другой философией — toggle всё равно respect-ится. Это feature, не bug: user override admin для full-tunnel предпочтения.

---

## Применение правил

- Скачивание при старте + раз в 6 часов в фоне (iOS BGAppRefreshTask / macOS NSBackgroundActivityScheduler)
- Если новая `version` > текущей — применяется атомарно через `SRSCacheStore`
- Baseline из bundle — fallback на случай если server fetch ещё не произошёл
- Подпись не прошла проверку → игнорировать обновление, оставить cache

## Что видит пользователь

- **Read-only просмотр** в Settings → Advanced (`RulesViewerSection`) — категории + количество записей
- **Кнопка «Обновить правила»** с 60с cooldown (`ForceUpdateRulesButton`)
- **Banner** «Обновитесь через TestFlight» при `min_app_version` превышении (`MinAppVersionBanner`)
- **Modal sheet** при первом/каждом появлении нового `min_app_version` (`MinAppVersionSheet`)

## Стратегия ротации ключей (v1.x, вне Phase 8)

1. App build N+1 поддерживает два ключа одновременно (old + new).
2. Manifest подписывается обоими ключами.
3. После 99% migration users → app build N+2 drop'ает old key.

## Закрытые / принятые решения

### 2026-05-18 — Owner confirmation: PublicKey.swift bytes = non-trivial placeholder

**Контекст:** AUDIT-3 finding `L-A5-3-09 / C5'-3-005` (LOW cross-validated)
вопрошал: doc-comment в `PublicKey.swift` claimed sequential placeholder
bytes `0x00..0x1F`, но actual bytes random-looking (`0xB5, 0x3F, 0xCF,
0xC3, ...`). Требовалось owner clarification: реальный ключ committed
случайно или non-trivial заглушка.

**Решение (owner clarify 2026-05-18):** **Нетривиальная заглушка** —
специально сделана похожей на ключ, чтобы случайно не приняли за обычный
нуль и чтобы прошла Ed25519 point validation в `Curve25519.Signing.PublicKey(rawRepresentation:)`.

**Обоснование:**
- Plan 07 T-C-D2 уже addressed это (Q1=B owner clarification) — doc-comment
  в `PublicKey.swift:22-31` обновлён "non-trivial random byte sequence,
  NOT a real production keypair, NO matching private key exists".
- AUDIT-3 finding L-A5-3-09 был **stale** — относился к pre-T-C-D2 state.
- Rule-set signed verify pipeline currently dead code в shipping v1.0
  (production использует `DefaultSubscriptionURLFetcher` + hardcoded
  baseline, не signed pipeline).

**TODO:** перед External Rollout (BACKLOG §10 Tier 1 #1) — generate real
Ed25519 keypair, replace placeholder bytes, deploy signed manifest
publishing infra. Private key хранится на VPS / 1Password / SecureKeep,
никогда не commit в repo.

**Где зафиксировано:**
- Memory: `project_publickey_placeholder_owner_confirm.md`
- Code: `BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift:22-31, 51-56`
- Backlog: `.planning/BACKLOG.md` §10 Tier 1 #3 (CLOSED)

## Возвратные условия для RULES-11 (D-08 revisit)

Пересмотреть перенос RULES-11 (macOS per-app routing) в активную разработку при:

1. ≥5 TestFlight user requests для per-app routing на macOS (Github Issues / TestFlight feedback)
2. Apple публикует пример кода с `NEAppProxyProvider` + `NETunnelProviderManager` coexistence
3. sing-box добавляет native macOS per-app proxy mode (bypassing NEAppProxy constraint)

До выполнения хотя бы одного — RULES-11 остаётся в `v0.10+ conditional`.

## Файлы реализации

| Путь | Назначение |
|------|------------|
| `BBTB/Packages/RulesEngine/` | SwiftPM пакет — весь pipeline |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift` | 32-byte Ed25519 pubkey |
| `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` | expandConfigForTunnel + rule_set injection + D-14 toggle gating |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` (`routingRulesEnabled`) | D-14 toggle storage (App Group suite) |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift` (Section 5b) | D-14 toggle UI |
| `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift` | rulesCacheDirectory path |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/RulesViewerSection.swift` | RULES-09 read-only viewer |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/ForceUpdateRulesButton.swift` | RULES-10 force-update + cooldown |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/MinAppVersionBanner.swift` | D-11 persistent banner |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MinAppVersionSheet.swift` | D-11 modal sheet |
| `BBTB/scripts/build-baseline-rules.sh` | Developer workflow: compile + sign + commit baseline |
| `BBTB/App/iOSApp/Info.plist` | BGTaskSchedulerPermittedIdentifiers + UIBackgroundModes:fetch |

## Related pages

- [[architecture]]
- [[tech-stack]]
- [[security-gaps]]
- [[max-messenger]]
- [[performance-baseline]]
- [[appproxy-deferral-2026]]
- [[engine-abstraction-decision-2026]]
- [[geoip-detection]]
- [[release-roadmap]]
