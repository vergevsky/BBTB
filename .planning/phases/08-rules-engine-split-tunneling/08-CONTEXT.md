# Phase 8: Rules Engine + Split tunneling — Context

**Gathered:** 2026-05-15
**Status:** Ready for planning

> **ROADMAP scope amendment (decided 2026-05-15 in this discuss-phase):** Phase 8 Success Criterion #3 («На macOS AppProxyProvider позволяет роутить отдельные приложения через VPN») и требование RULES-11 переезжают **out of v0.8** на основании Codex architectural review (`019e284c-4bf6-7f91-ada7-7e679692b5fb`). См. D-08/D-09 ниже. ROADMAP.md и REQUIREMENTS.md обновляются planner'ом в первой задаче плана.

<domain>
## Phase Boundary

**Что фаза делает (v0.8):** Приложение начинает скачивать с твоего VPS подписанный файл `rules.json` (или его прекомпилированные SRS-эквиваленты), проверять подпись Ed25519, и применять три категории правил (`always_through_vpn`, `never_through_vpn`, `block_completely`) к трафику **через sing-box `route.rule_set`** — единый protocol-agnostic слой routing, который масштабируется на 10K+ доменов без restart туннеля.

**Зачем (бизнес-смысл):** Админ (разработчик) может **без выпуска новой версии приложения** срочно добавить домен в block, отправить домен мимо VPN, или закрепить домен через VPN. Применение у пользователей — максимум 6 часов (background fetch interval).

**Версия:** v0.8

### В скоупе v0.8

1. **Server-side SRS pipeline (D-01):** VPS компилирует rules.json → 3 binary `.srs` файла + подписывает Ed25519. Клиент скачивает уже скомпилированные SRS-ы.
2. **Ed25519 signature verification** через swift-crypto (с локированной publicKey в коде).
3. **Local rule_set auto-reload через sing-box 1.10+ feature** — обновление без restart туннеля (release gate verification обязателен).
4. **3 sing-box `route.rules` priority entries**: block → reject; never → direct; always → urltest-auto; default → toggle outbound.
5. **App Group sync** (`group.app.bbtb.shared`) для .srs cache между main app и PacketTunnel extension.
6. **Server-side country resolve** (D-04): `"countries": ["RU"]` admin field → VPS разворачивает в CIDR-набор на момент signing → SRS. Никакой MMDB на клиенте.
7. **Embedded baseline `baseline-rules.json` (D-06):** signed (version 0) в .app bundle для bootstrap до первого server fetch. Один trust-path с серверным rules.
8. **Background fetch:** при старте + каждые 6 часов (`BGAppRefreshTask` / `NSBackgroundActivityScheduler`).
9. **Failover mirrors:** до 3 hardcoded URL, sequential try с bounded concurrency (DEC-06d-04).
10. **UI RULES-09:** Read-only viewer текущих правил в Расширенных Настройках (Settings → Advanced → Rules).
11. **UI RULES-10:** Кнопка «Принудительно обновить правила» в Расширенных (with cooldown — см. D-10).
12. **`min_app_version` field (RULES-08):** при превышении показывается экран «Обновитесь через TestFlight».
13. **AppProxyExtension-macOS target deletion (D-09):** удаляем из Tuist Project.swift, Apple Developer Portal entitlement revisit.

### НЕ в скоупе v0.8 (scope amendment + carve-outs)

- **RULES-11 + Phase 8 SC #3** — реальный per-app routing data plane на macOS. Перенос в **Out of Scope, v0.10+ conditional on demand**. Rationale: D-08 ниже + Codex architectural review.
- **`bundle_ids` поле в rules.json schema** — не вводим в v0.8. Если когда-то AppProxy data plane появится — будет отдельный `macos_app_proxy.json` manifest с Apple-canonical `signing_identifier + designated_requirement` (NOT bare bundle IDs).
- **NET-12** (active liveness probe) — повторный carry-out из Phase 7-8 backlog, остаётся deferred (Phase 9+).
- **User override rules** — locked per spec (RULES-09 read-only viewer only).
- **Push «правила обновлены»** уведомления — backlog v1.4+ (per v2 prompt `<roadmap_v1>`).
- **`feature_flags` секция в rules.json** — schema допускает, но в v0.8 клиент не интерпретирует. Hooks в будущее.

</domain>

<decisions>
## Implementation Decisions

### Area A — In-tunnel routing implementation

- **D-01: Server-side SRS pipeline через sing-box `route.rule_set`** _(Codex thread `019e2841-e382-7cb1-98b4-793307090ae4` recommendation)._
  - Админ обновляет `rules.json` на VPS → VPS-tooling запускает `sing-box rule-set compile` → получает 3 binary `.srs` файла → подписывает Ed25519 → публикует на CDN.
  - Клиент скачивает `bbtb-block.srs` + `bbtb-never-vpn.srs` + `bbtb-always-vpn.srs` + manifest с signature.
  - Sing-box config содержит 3 `route.rule_set` entries с `type: "local"`, `format: "binary"`, `path: <App-Group-path>`.
  - **Priority hierarchy через `route.rules` order:** block (reject/drop) > never (outbound: direct) > always (outbound: urltest-auto, composes с protocol failover) > default (toggle).
  - **Sing-box version dependency:** route.rule_set since 1.8.0, local file auto-reload since 1.10.0, binary SRS format v4 since 1.13.0 (см. https://sing-box.sagernet.org/configuration/rule-set/). Наш libbox 1.13.11 supports all three.

- **D-02: Domain/IP/Country mapping в SRS rules.**
  - `domains` → `domain_suffix` + `domain` exact matchers (headless rules) в SRS.
  - `ip_cidrs` → `ip_cidr` matchers в SRS.
  - `countries` → server-side expanded в CIDR-набор на момент signing (см. D-04), затем как `ip_cidr` в SRS. Никаких client-side MMDB лукапов.

- **D-03: DNS sniffing обязателен для domain matching.**
  - Sing-box `route.rules` с domain matchers работают только если sing-box видит domain. С учётом `hijack-dns` в config и encrypted DoH inside tunnel — нужен явный `sniff` step перед domain rule evaluation.
  - Risk mitigation: ECH (Encrypted Client Hello) и raw-IP connections не дадут domain match — accept'им как limitation, документируем в FAQ для Phase 11. Для критичных доменов админ должен добавить IP-диапазоны в `ip_cidrs`.

### Area B — Country routing (resolved by A)

- **D-04: Full server-side country resolve в v0.8.**
  - Поле `countries` в `rules.json` поддерживается с момента релиза v0.8.
  - VPS-tooling: cron-обновление MaxMind GeoLite2 country CSV (бесплатный, weekly) → при signing разворачивает country codes в CIDR-набор → пакует в `.srs`.
  - Клиент не несёт MMDB — никакого install footprint penalty, никакой памяти в 50MB iOS extension.
  - Когда GeoLite2 обновится (раз в неделю), админ перепакует rules.json — клиенты получат свежие CIDR-ы за 6 часов.

### Area C — Bootstrap rules

- **D-05: Embedded baseline `baseline-rules.json` (signed) в .app bundle.**
  - Файл лежит в Resources main app target, version=0.
  - Подписан тем же Ed25519 ключом что и server-side rules.
  - Также прекомпилирован в 3 baseline `.srs` файла (`bbtb-baseline-block.srs` etc.) и положен в bundle.
  - Bootstrap логика: если App Group cache пустой (первый запуск) — копируем baseline SRS из bundle в App Group → sing-box подхватывает. Когда придёт server version > 0 — атомарно подменяем.
  - **Содержимое baseline (v0.8 starter set):** `block_completely.domains = ["max.ru", "mssgr.tatar.ru", ...]` (синхронизировано с `wiki/max-messenger.md`). Banks/government в `never_through_vpn` не bundle'им (баланс между безопасностью и open-source-доверием к app bundle — пусть админ-rules заведуют этим).
  - Tooling: build-script step «sign + compile baseline» в Tuist либо CI, чтобы при сборке release любое изменение baseline.json автоматически подписывалось и компилировалось.

### Area D — macOS AppProxyProvider

- **D-08: RULES-11 + Phase 8 SC #3 → Out of Scope, v0.10+ conditional** _(Codex thread `019e284c-4bf6-7f91-ada7-7e679692b5fb` recommendation)._
  - **Architectural blocker:** AppProxy даёт L4 `NEAppProxyFlow`; sing-box интегрирован через L3 TUN inbound. Нет verified API для injection flow → sing-box router (libbox 1.13.11 не подтверждает). Альтернативы либо ломают R1 invariant (SOCKS5 на localhost), либо bypass-ят Reality (теряем anti-DPI), либо требуют IPC/multi-instance sing-box без подтверждённой support.
  - **Semantic mismatch:** `NETunnelProviderManager` и `NEAppProxyProviderManager` mutually exclusive. AppProxy создан для use-case «почти всё прямо, несколько apps через прокси». BBTB нужен обратный кейс. AppProxy — wrong tool для BBTB primary goal.
  - **Workaround:** `never_through_vpn` для apps уже работает на уровне domains/IPs через sing-box rule_set. Bundle-ID гранулярность даёт marginal benefit для friends-and-family TestFlight.

- **D-09: AppProxyExtension-macOS target → DELETE из Tuist.** _(D2 user decision, ROADMAP/REQUIREMENTS amendment.)_
  - Удалить target из `BBTB/Project.swift`.
  - Удалить файл `BBTB/App/AppProxyExtension-macOS/AppProxyProvider.swift` и `AppProxyExtension-macOS.entitlements`.
  - Apple Developer Portal: revisit App ID `app.bbtb.client.macos.appproxy` (если existed) — disable AppProxy capability.
  - Macros app entitlement: убрать `com.apple.developer.networking.networkextension` value `app-proxy-provider` (keep только `packet-tunnel-provider`).
  - **Cost возврата (если v0.10+ передумаем):** ~15 минут Tuist + ~30 минут Portal = Quick.

### Area E — Signature placement (auto-decided, default applied)

- **D-07: Two-file Ed25519 signature (`rules.json` + `rules.json.sig`).**
  - НЕ embedded signature внутри JSON (избегаем canonical JSON serialization fragility).
  - `.sig` файл = raw Ed25519 signature над byte content `rules.json` (или каждого `.srs` файла отдельно).
  - Каждый `.srs` файл также подписан → `.srs.sig`. Manifest `rules-manifest.json` содержит version + list of files + signatures hash. Manifest сам подписан.
  - Rationale: проще validate (`crypto.verify(message=fileBytes, signature=sigBytes, publicKey=hardcoded)`), без JSON tricks.

### Auxiliary defaults (auto-decided, можно revisit в planning)

- **D-10: Force-update button cooldown = 60 секунд.** UI disabled с countdown «Подождите 45с». Защита VPS от случайного DDoS.
- **D-11: `min_app_version` UX = modal sheet поверх main, dismissible, persistent banner в Settings → Advanced.** НЕ full-screen takeover (UX harsh для случая «обновись через TestFlight» который пользователь сам контролирует — TestFlight автоматически обновит, нужно только время).
- **D-12: rules.json не блокирует cold start** (per DEC-06d-01). Bootstrap baseline применяется immediately из bundle (D-05); server fetch — background task через `BGAppRefreshTask`.
- **D-13: Failover mirrors max concurrency = 1 (sequential)** при boot fetch; force-update button = 1 (current mirror first, fail → next). Per DEC-06d-04 bounded concurrency principle.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 8 spec source
- `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` §`<rules_engine>` (lines 289-347) — authoritative rules.json structure + Ed25519 signature + priority hierarchy + cadence + min_app_version semantics.
- `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` §`<release_roadmap>` lines 887-901 — Phase 8 (v0.8) deliverables.
- `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` §`<network_extension_targets>` lines 144-154 — AppProxyProvider semantics + App Group sync invariants.

### Requirements & ROADMAP
- `.planning/REQUIREMENTS.md` § Rules Engine — RULES-01..11 detailed list with REQ-IDs.
- `.planning/ROADMAP.md` Phase 8 entry (lines 323-336) — original Success Criteria + Requirements mapping. **NB: SC #3 + RULES-11 → Out of Scope per D-08/D-09 этого CONTEXT.**

### Wiki long-term decision log
- `wiki/rules-engine.md` — current state design doc. Update после Phase 8 closure с финальной реализацией.
- `wiki/geoip-detection.md` — РКН methodology GeoIP background, relevant для D-04 (server-side country resolve) rationale.
- `wiki/max-messenger.md` — domain list для baseline `block_completely` (D-05).
- `wiki/architecture.md` — current architecture diagram. **Update после Phase 8** с rule_set integration.
- `wiki/security-gaps.md` § R1 (sing-box no SOCKS5 invariant), § R10 (TUN inbound default-deny) — invariants which D-01 must preserve.
- `wiki/performance-baseline.md` § DEC-06d-01..06 — performance patterns которые D-12 enforces.
- `wiki/engine-abstraction-decision-2026.md` — mono-engine sing-box decision (Phase 7c HYBRID) which D-08 reaffirms.
- `wiki/auto-reconnect.md` § R18 — Apple's NEOnDemandRule invariants, rules engine updates НЕ должны нарушать sliding session window logic.

### Codex consultation threads (architectural backbone)
- Codex thread `019e2841-e382-7cb1-98b4-793307090ae4` (Area A architectural review) — full sing-box feature audit + version verification + update strategy.
- Codex thread `019e284c-4bf6-7f91-ada7-7e679692b5fb` (Area D AppProxy review) — основа D-08 deferral decision.

### Sing-box upstream documentation (verified by Codex)
- https://sing-box.sagernet.org/configuration/route/ — route.rules + route.rule_set fields.
- https://sing-box.sagernet.org/configuration/route/rule/ — rule matchers.
- https://sing-box.sagernet.org/configuration/rule-set/ — Local + Remote rule-set; auto-reload on local file change (since 1.10.0).
- https://sing-box.sagernet.org/configuration/rule-set/source-format/ — SRS v4 (since 1.13.0).
- https://sing-box.sagernet.org/configuration/route/rule_action/ — `route` / `reject` / `hijack-dns` / `sniff` actions.
- https://sing-box.sagernet.org/migration/ — legacy geoip/geosite → rule_set migration.

### Apple platform documentation
- https://developer.apple.com/documentation/networkextension/nepackettunnelprovider — current ship-mode provider.
- https://developer.apple.com/documentation/networkextension/neappproxyprovider — AppProxy reference (для D-08 context, NOT для v0.8 implementation).
- https://developer.apple.com/documentation/networkextension/neipv4settings/excludedroutes — IP-level routing constraints (D-01 justification).

### Codebase entry points для planner
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` — runtime config expansion; D-01 будет расширять `expandConfigForTunnel(_:)` для injection `route.rule_set` entries.
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/Resources/SingBoxConfigTemplate.vless-reality.json` — existing template, route.rules block (lines 68+); D-01 расширит другие per-protocol templates аналогично.
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift` — App Group path resolver; D-05/D-13 будут использовать для SRS cache location.
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift` — D-10/D-11 + RULES-09/RULES-10 UI добавляется здесь.
- `BBTB/App/AppProxyExtension-macOS/` — **DELETE** в Plan W0 (D-09).
- `BBTB/Project.swift` — Tuist target list, **DELETE** AppProxyExtension target (D-09).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`SingBoxConfigLoader.expandConfigForTunnel(_:)`** (PacketTunnelKit/SingBox/) — public + idempotent + post-expand R1 validation. D-01 расширяет: после tun-inbound expansion + DNS-hijack migration также инжектит `route.rule_set` entries + 3 priority rules. Post-expand validation должен пройти после расширения.
- **App Group `group.app.bbtb.shared`** — уже работает для config sync (Phase 1 R8 + R10). D-05/D-13 будут использовать subdirectory `Library/Caches/rules/` для SRS файлов.
- **swift-crypto** — нет в Package.swift dependencies сейчас. Добавить в W0 как Apple-supported dep (https://github.com/apple/swift-crypto), используется в `RulesEngine` package для Ed25519 verify.
- **`SettingsViewModel` + `AdvancedSettingsView`** (AppFeatures/SettingsFeature/) — existing pattern для toggle/list UI; D-10/D-11 + RULES-09/RULES-10 добавляются tail в существующий ViewModel + новый section в View.
- **`AdvancedSettingsStore`** (Phase 6) — паттерн для persistent settings; rules-engine state (last fetch timestamp, current version, force-update cooldown) идёт в новый `RulesEngineState` actor.
- **`SubscriptionFetcher`** (Phase 2-3) — паттерн для HTTPS fetch с failover mirrors; адаптируем для `RulesFetcher` (но без user-visible error UI, всё в background log).
- **`PerfSignposter`** (Phase 6d, DEC-06d-06) — обязательны spans для rule-set reload latency.
- **`OnDemandRulesBuilder`** (Phase 6c) — не путать с Rules Engine. Это `NEOnDemandRule` builder для auto-reconnect; rules engine отдельный модуль.

### Established Patterns

- **R1 invariant test** (`tests/validate-r1-r6.sh` § R1) — post-expand grep на `"type": "socks"`/`"type": "mixed"` etc. D-01 routing extension должна пройти этот gate.
- **R10 invariant** — default-deny TUN inbound whitelist `{tun, direct}` для outbound chain. D-01 правила routing **расширяют** outbound usage до `urltest-auto` (already existing) + `reject` (new action, not new outbound — pass).
- **Two-phase init pattern** для actor-actor циклов (memory `feedback_failover_two_phase_init.md`) — `RulesEngineCoordinator` ↔ `TunnelController` будут связаны late-binding setter.
- **`NEVPNStatusDidChange` observer queue=nil** invariant (memory `feedback_nevpn_observer_queue_main.md`) — rules engine background flow не должен делать XPC в `.main`.
- **Bounded concurrency** (DEC-06d-04) — failover между 3 mirrors — sequential (concurrency=1) по умолчанию; pre-flight check на каждый force-update tap (cooldown D-10).
- **Cold-start init defer** (DEC-06d-01) — RulesEngineCoordinator init **не блокирует** TunnelController/AppContext startup. Bootstrap baseline применяется synchronously (быстро, файлы в bundle); server fetch — defer'нутый Task через BGAppRefreshTask.

### Integration Points

- **`SingBoxConfigLoader.expandConfigForTunnel(_:)`** — единственная точка инъекции `route.rule_set` entries. D-01 implementation.
- **PacketTunnel extension `startTunnel(options:completionHandler:)`** — точка, где app group cache читается перед service start. Если cache empty → читаем baseline SRS из bundle (D-05).
- **`AdvancedSettingsView`** — точка интеграции UI rules viewer (RULES-09) + force-update button (RULES-10) + min_app_version banner (D-11).
- **`BBTB_iOSApp.swift` / `BBTB_macOSApp.swift`** — точка регистрации `BGAppRefreshTask` для 6h background fetch.
- **Tuist `Project.swift`** — D-09 target deletion happens here.

</code_context>

<specifics>
## Specific Ideas

- **User preferences carried into this phase:** масштабируемость priority (20+ протоколов, 50+ транспортов), качество > скорость, простое объяснение каждого решения, обязательная Codex consultation на ключевых архитектурных решениях. Все 4 area decisions приняты с Codex backing для архитектурных областей (A, D) + plain-language rationale для UX (C) и spec-level (B).
- **`baseline-rules.json` content** — стартовый список доменов синхронизирован с `wiki/max-messenger.md`. Banks/government в baseline НЕ кладём (admin-only, server-controlled).
- **Sing-box `urltest` outbound** — уже работает с Phase 2 IMP-04 (`PROTO-10` auto-fallback). D-01 routing rule «always → outbound: urltest-auto» означает: правила always-through-vpn автоматически наследуют protocol failover. **Composes**, не bypass.

</specifics>

<deferred>
## Deferred Ideas

### Перенесено в Phase 9+ или v0.10+

- **RULES-11 (AppProxyProvider data plane на macOS)** → Out of Scope v0.8, conditional on demand в v0.10+. Документировать в `wiki/appproxy-deferral-2026.md` (new file aналогично `wiki/wireguard-deferral-2026.md`) с rationale + Codex thread reference + return condition.
- **Phase 8 ROADMAP Success Criterion #3** — формально deferим из v0.8.
- **`bundle_ids` field в rules.json schema** → не вводим. Если AppProxy появится в v0.10+, отдельный `macos_app_proxy.json` manifest с `signing_identifier + designated_requirement`.

### Carry-out из Phase 6c (по-прежнему deferred)

- **NET-12** (active liveness probe — Pitfall 5 soft-kill server detection) — повторный carve-out для Phase 9+.

### Backlog для Phase 11/12 (pre-TestFlight)

- **Numerical Instruments baseline** Time Profiler / Energy Log / Allocations capture — PerfSignposter spans готовы (DEC-06d-06).
- **macOS UAT replay** 5 scenarios (Phase 6e D-03).
- **L16/L18** (Phase 6e Wave 2 deferred items).
- **MainScreenView.swift:15** unused `@Environment(\.scenePhase)` cleanup.
- **W2-05 iOS 16.1+ Apple-leak документация** wiki promotion.

### Backlog для v1.x+ (post-MVP)

- **Push «правила обновлены» уведомления** (v2 prompt mention) — v1.4+.
- **`feature_flags` секция в rules.json** consumption на клиенте — schema допускает в v0.8, но client не интерпретирует. Hooks для v1.x admin-driven feature toggles.
- **Per-app routing UI на macOS** (если AppProxy data plane появится) — list-view + toggles в Settings.
- **Multi-port format** `host:port1,port2` (carry from Phase 4 D-09).

</deferred>

---

*Phase: 8-Rules Engine + Split tunneling*
*Context gathered: 2026-05-15*
