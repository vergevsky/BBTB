---
name: AppProxyProvider (macOS) — deferral decision May 2026
description: Решение Phase 8 D-08/D-09 — RULES-11 + Phase 8 SC #3 (реальный macOS AppProxy data plane) в Out of Scope v0.8, conditional return в v0.10+. Архитектурное обоснование: L3 sing-box vs L4 NEAppProxyFlow + mutually-exclusive managers; bridging либо ломает R1, либо bypass-ит Reality. Workaround — `never_through_vpn` через sing-box `route.rule_set`.
type: project
---

# AppProxyProvider (macOS) — отложен на v0.10+ backlog (Phase 8 D-08/D-09)

**Summary**: По итогам Phase 8 discuss-phase 2026-05-15 (Codex GPT-5 architectural review thread `019e284c-4bf6-7f91-ada7-7e679692b5fb`) — **удалить per-bundle-ID AppProxyProvider data plane на macOS из v0.8 scope**, перенести в Out of Scope с conditional return в v0.10+. Причины: (а) sing-box интегрирован через L3 TUN inbound, AppProxy даёт L4 NEAppProxyFlow — нет verified API для injection L4 flows в L3 router; (б) `NETunnelProviderManager` и `NEAppProxyProviderManager` взаимоисключающие на уровне системы; (в) любая попытка моста (SOCKS5 inbound на localhost, multi-instance sing-box, plain TCP bypass) ломает либо R1 invariant, либо anti-DPI guarantees Reality; (г) workaround `never_through_vpn` через sing-box `route.rule_set` (domain/IP matching) покрывает 95% friends-and-family TestFlight scenarios без architectural risk.

**Sources**: Phase 8 discuss-phase 2026-05-15 (`/.planning/phases/08-rules-engine-split-tunneling/08-CONTEXT.md` D-08/D-09 + `/.planning/phases/08-rules-engine-split-tunneling/08-RESEARCH.md` § «Why RULES-11 carve-out»), Codex thread `019e284c-4bf6-7f91-ada7-7e679692b5fb` (Area D architectural review), Apple Developer docs `NEAppProxyProvider` / `NEAppProxyProviderManager`.

**Last updated**: 2026-05-15

---

## Контекст

ROADMAP Phase 8 изначально содержал Success Criterion #3 («На macOS AppProxyProvider позволяет роутить отдельные приложения через VPN») и требование RULES-11 («AppProxyProvider таргет на macOS для per-app routing»). Phase 1 W3 зарегистрировал Tuist target `BBTB-AppProxy-macOS` как **placeholder** — пустой `AppProxyProvider.swift` с `completionHandler(NSError(... "Phase 8"))`, чтобы реализация ждала Phase 8. Phase 1 commit `eafb88c` явно отметил это в memory `project_phase1_complete.md` как «8 validated requirements» — но AppProxy сам стоял в карантине.

На этапе `/gsd-discuss-phase 8` 2026-05-15 запрошен Codex architectural review для проверки feasibility интеграции AppProxy данных в sing-box-based архитектуру v0.7. Результат — `019e284c-4bf6-7f91-ada7-7e679692b5fb`: «архитектурный mismatch, recommendation = carve-out v0.10+».

## Что показало архитектурное исследование

### Слой работы — L3 vs L4

| Layer | sing-box (наш стек) | NEAppProxyProvider |
|-------|---------------------|--------------------|
| Network layer | **L3** (IP packets через TUN inbound) | **L4** (TCP/UDP flows через `NEAppProxyFlow`) |
| Точка входа | NEPacketTunnelProvider → TUN device → libbox parses IP | NEAppProxyProvider → flow callbacks (handle TCP/UDP отдельно) |
| Routing primitive | `route.rule_set` (домены/IP/страны) поверх IP-уровня | per-bundle-ID + per-protocol через ProxyConfiguration |
| iOS support | ✓ (PacketTunnel доступен на iOS+macOS) | ✗ (AppProxy **только macOS**) |
| Per-app filter | ✗ (нет native bundle-id matching в sing-box) | ✓ (это primary feature) |

### Manager exclusivity

`NETunnelProviderManager` (PacketTunnel) и `NEAppProxyProviderManager` (AppProxy) — два разных типа manager'ов. По Apple-документации **только один может быть active одновременно на системе** — оба претендуют на роль «системного провайдера сети». Если bbtb запустит оба, второй вытеснит первый, и пользователь получит непредсказуемое поведение.

Это означает: в Phase 8 архитектуре с одним active NETunnelProviderManager (наш PacketTunnel + sing-box) **физически нет места** для параллельного NEAppProxyProviderManager.

### Почему «мостить» AppProxy → sing-box нельзя

Codex review рассмотрел три моста и забраковал все:

**Мост 1 — SOCKS5 inbound в sing-box на localhost**

- Идея: AppProxy перехватывает flow → форвардит на `127.0.0.1:<port>` → sing-box принимает SOCKS5 → routes через нужный outbound.
- Проблема: **R1 invariant** (Phase 1 security audit, locked by Codex 2026-05-11) — sing-box config **не должен** содержать `"type": "socks"` или `"type": "mixed"` inbound. R1 защищает от рейс-двойного-туннелирования и системной утечки SOCKS5 endpoint. Phase 6c добавил `validate-r1-r6.sh` shell gate, который грепит на `"type": "socks"` после `expandConfigForTunnel` — мы **физически не пропустим** SOCKS5 inbound в шиппинг.
- Вывод: ломает R1 → отбраковано.

**Мост 2 — Multi-instance sing-box**

- Идея: один libbox instance — для PacketTunnel (full-tunnel), второй libbox instance — для AppProxy (per-app), IPC между ними.
- Проблема: libbox 1.13.11 не имеет documented multi-instance coordination API. Engineering cost — 5-10 engineer-weeks реверс-инжиниринга libbox internals + написания IPC слоя + риск upstream breakage при каждом libbox upgrade. Это не carry-out, это новый под-проект.
- Вывод: not feasible без архитектурного ресета → отбраковано.

**Мост 3 — Plain TCP bypass через AppProxy**

- Идея: AppProxy перенаправляет flow напрямую на VPS-сервер без sing-box.
- Проблема: теряем Reality fingerprint defense (anti-DPI ядро bbtb). Flow идёт как plain TCP → ТСПУ его видит → блокирует или ловит сам факт VPN-использования. Защита от Russian TSPU — главный value proposition bbtb, потеря Reality для отдельных приложений не приемлема.
- Вывод: ломает anti-DPI guarantees → отбраковано.

### Что говорит Apple HIG

Дополнительный архитектурный недочёт оригинального RULES-11 — поле `bundle_ids` в `rules.json` schema. По Apple Human Interface Guidelines для AppProxy (NEAppProxyProvider docs), правильный filter primitive — **`signing_identifier + designated_requirement`**, а не bare bundle IDs. Bundle IDs spoofable (любой может зарегистрировать `com.apple.calculator` для своего бинаря). Если AppProxy когда-то вернётся в v0.10+, schema должна быть отдельным `macos_app_proxy.json` manifest'ом с Apple-canonical полями.

## Что мы делаем сейчас (v0.8 carve-out)

**Plan 08-01 (W0) — физическое удаление placeholder'а:**

1. `git rm -r BBTB/App/AppProxyExtension-macOS/` (3 файла: `AppProxyProvider.swift`, `Info.plist`, `.entitlements`).
2. `BBTB/Project.swift` — удалить блок `.target(name: "BBTB-AppProxy-macOS", ...)` + dependency reference `.target(name: "BBTB-AppProxy-macOS")` в `BBTB-macOS` deps.
3. `BBTB/App/macOSApp/BBTB-macOS.entitlements` — убрать `<string>app-proxy-provider</string>` из массива `com.apple.developer.networking.networkextension` (оставить только `packet-tunnel-provider`).
4. Apple Developer Portal (manual): Identifiers → `app.bbtb.client.macos` → Network Extensions → снять галочку «App Proxy Provider». Если был отдельный App ID `app.bbtb.client.macos.appproxy` — disable / удалить.
5. `tuist generate` чтобы regenerate workspace без `BBTB-AppProxy-macOS` schema.
6. `validate-r1-r6.sh` Phase 8 W7 extension — добавится новый check «D-08: No NEAppProxyProvider import in main app sources».
7. ROADMAP/REQUIREMENTS — strikethrough RULES-11 + Phase 8 SC #3 (см. `wiki/release-roadmap.md` + `.planning/REQUIREMENTS.md`).

## Workaround в v0.8

Реальный split-tunneling в v0.8 реализуется через `never_through_vpn` категорию `rules.json`:

```json
{
  "never_through_vpn": {
    "domains": ["bank.ru", "gosuslugi.ru"],
    "ip_cidrs": ["203.0.113.0/24"],
    "countries": ["RU"]
  }
}
```

Sing-box `route.rule_set` matcher разворачивает это в `domain_suffix` / `ip_cidr` rules → выбранный domain / IP / country идёт через `outbound: "direct"` (мимо VPN). Это **domain/IP/country granularity**, не **per-bundle granularity**.

**Что покрывает workaround (95% friends-and-family scenarios):**
- Сайт российского банка через direct (`bank.ru` domain → direct outbound).
- Госуслуги через direct (`gosuslugi.ru` → direct).
- Yandex / Mail.ru ecosystem domains через direct.
- Country-wide RU CIDR-набор через direct (для пользователей которые хотят «всё российское — direct, всё остальное — через VPN»).

**Что workaround НЕ покрывает (per-bundle-ID granularity loss):**
- Сценарий «route Telegram через VPN, но WhatsApp — direct» когда оба приложения используют те же серверные домены / IP-диапазоны.
- Сценарий «приложение X со spoof-ом domain (e.g. CDN-fronting) → нет надёжного domain match».
- Per-process traffic split (не data plane концепт sing-box).

## Условие возврата (v0.10+ conditional)

Реальный AppProxy data plane может быть пересмотрен в v0.10+ при одном из triggers:

1. **TestFlight signal:** 3+ независимых пользователя из friends-and-family пула запросили per-app routing функцию (например, «хочу WhatsApp через VPN, банковское приложение — direct, при одинаковых backend-доменах»).
2. **TSPU behavioral break:** Russian TSPU начала ломать domain-based split-tunnel (маловероятно — это не их фокус 2025-2026; domain SNI matching у них и так работает).
3. **Архитектурный pivot:** если libbox получит multi-instance coordination API (upstream SagerNet) или будет создан Apple-canonical AppProxy → sing-box bridge тулинг.

**Cost возврата (если triggers сработают):**

| Шаг | Effort |
|---|---|
| Tuist target re-add `BBTB-AppProxy-macOS` | ~15 минут (re-add block, deps, paths) |
| Apple Developer Portal capability re-enable | ~30 минут (Identifiers → app.bbtb.client.macos → Network Extensions → check «App Proxy Provider» + provisioning profile regenerate) |
| Schema design `macos_app_proxy.json` с `signing_identifier + designated_requirement` (NOT bundle IDs per Apple HIG) | TBD |
| AppProxy data plane implementation | TBD — зависит от chosen approach (fresh design vs sing-box bridge — см. рассмотрение трёх мостов выше) |

Итого — **Tuist + Portal = Quick** (~45 минут); **data plane = Medium-Large** (зависит от подхода).

## Что мы теряем (v0.8)

- ✗ Phase 8 ROADMAP Success Criterion #3 формально не достигается → strikethrough + Out of Scope notation.
- ✗ Per-bundle-ID granularity в split-tunnel — пользователи получают domain/IP/country split, но не per-app split.
- ✗ macOS-only feature — iOS пользователи и так не получают AppProxy (Apple не предоставляет AppProxy на iOS), так что для iOS workaround «equally good».

## Что мы получаем (v0.8)

- ✓ Чистый Tuist Project.swift без «зомби»-target'а — `tuist generate` не включает в workspace stub, который никогда не reach production.
- ✓ macOS entitlements честно отражают actual capability — только `packet-tunnel-provider`. Apple Developer Portal capability disable убирает potential confusion при code-signing review.
- ✓ Архитектурный фокус Phase 8 — server-side signed rules pipeline + sing-box route.rule_set engine — без распыления на AppProxy data plane исследование.
- ✓ Сохраняется R1 invariant (нет SOCKS5 inbound) + Reality anti-DPI guarantees для всего трафика без исключений.
- ✓ Single trust path — все трафик routing через один sing-box engine, одно место для security audit.

## Связанные wiki pages

- [[security-gaps]] — R1 invariant (sing-box без SOCKS5 inbound) который сохраняется carve-out'ом
- [[engine-abstraction-decision-2026]] — Phase 7c HYBRID решение о mono-engine sing-box (Phase 8 D-08 reaffirms this — нет engine abstraction для AppProxy)
- [[architecture]] — current architecture diagram (после Phase 8 closure будет обновлена с rule_set integration + AppProxy carve-out note)
- [[rules-engine]] — design doc Phase 8 rules engine; будет обновлена после Phase 8 closure с финальной реализацией
- [[wireguard-deferral-2026]] — parallel deferral pattern (Phase 7 D-02) — этот же long-term-decision-log жанр
- [[openvpn-deferral-2026]] — parallel deferral pattern (Phase 7 D-01)
- [[amneziawg-deferral-2026]] — parallel deferral pattern (Phase 7b cancellation)
- [[release-roadmap]] — версии v0.1 → v1.0 (Phase 8 SC #3 marked deferred → v0.10+)
- [[tspu]] — описание угрозы ТСПУ (anti-DPI рассуждения которые делают workaround достаточным для primary use-case)

## Source URLs (full list)

- Apple Developer docs: `https://developer.apple.com/documentation/networkextension/neappproxyprovider`
- Apple Developer docs: `https://developer.apple.com/documentation/networkextension/neappproxyprovidermanager`
- Apple Developer docs: `https://developer.apple.com/documentation/networkextension/nepackettunnelprovider`
- sing-box docs: `https://sing-box.sagernet.org/configuration/route/` (rule_set + L3 routing model)
- sing-box docs: `https://sing-box.sagernet.org/configuration/inbound/` (no AppProxy inbound type)
- Phase 8 RESEARCH.md § «Why RULES-11 carve-out» (`.planning/phases/08-rules-engine-split-tunneling/08-RESEARCH.md`)
- Phase 8 CONTEXT.md D-08/D-09 (`.planning/phases/08-rules-engine-split-tunneling/08-CONTEXT.md`)
- Codex GPT-5 architectural review thread `019e284c-4bf6-7f91-ada7-7e679692b5fb` (Area D AppProxy review)
- Codex GPT-5 reference thread `019e2841-e382-7cb1-98b4-793307090ae4` (Area A sing-box rule_set architecture — context для понимания почему bridge не работает)

*Decision logged 2026-05-15 in `/gsd-discuss-phase 8` D-08 + D-09. CONTEXT: `.planning/phases/08-rules-engine-split-tunneling/08-CONTEXT.md`. Execution: Plan 08-01 (W0). PROJECT.md: будет обновлён после Phase 8 closure (carry-out RULES-11 → Out of Scope в final list).*
