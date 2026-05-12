# Phase 2 — Device UAT progress

**Started:** 2026-05-12 ~10:00
**Paused at:** 2026-05-12 ~10:45 (context window saturation)
**Device:** реальный iPhone (iOS 26.x), Xcode debug session
**Tester:** Nv

---

## Результаты по тестам

| Тест | Статус | Заметка |
|---|---|---|
| T0 — Build & Launch | **PASS** | Empty-state карточка отрендерилась корректно. |
| T1 — Subscription URL import | **PASS** | `https://vpn.vergevsky.ru/sub/VGV...` → pool успешно загружен, layout перешёл из empty в idle, server-line «Сервер: Авто». **Silent success без alert** — by design (executor намеренно не сделал success-alert; error-alert работает). |
| T2 — Multi-line URI block | **PASS** | 6 URI (4 VLESS+Reality + 2 Trojan-WS) → импорт прошёл, server-line «Сервер: Авто». |
| T3 — JSON endpoint import | **PASS-B** | TLS error отклонил endpoint `https://185.237.218.81:24527/json/...` — cert на `virt.vergevsky.ru`, accessed via IP → hostname mismatch. R1 принцип работает корректно. |
| T4 — QR-code import | **PASS** | Trojan-Латвия URI через qrencode → камера → import → server-line «Сервер: Латвия — Trojan». Permission flow OK. |
| T5 — Connect + IP change | **PASS** | Два фикса: `39356a4` (serverAddress regression) + `6d0f798` (fp= fallback) + `4255a77` (ALPN h2 stripped for WS). Trojan-WS подключается, `connection download closed` за 350-500ms, данные идут. |
| T6 — urltest failover | **PASS** | trojan-0 (2087): available 182ms; trojan-1 (2088): unavailable i/o timeout. urltest перепроверяет каждые 1m, трафик идёт через рабочий outbound. |
| T7 — Kill Switch OFF | **PASS** | Include All Networks = OFF подтверждён в iOS Settings → VPN → BBTB. |
| T8 — Kill Switch ON | **PASS** | Include All Networks = ON подтверждён в iOS Settings → VPN → BBTB. |
| T9 — Reconnect banner | **PASS** | Баннер появился при переключении Kill Switch в активном тоннеле. |

---

## ROOT CAUSE T5 (Phase 1 regression)

**Симптом:** `connect` → state `.error` сразу. Pill в UI не показывала текст ошибки (UI bug отдельно). VLESS+Reality (работавший в Phase 1) тоже падал — широкая регрессия.

**Поиск:** sing-box.log был пуст (только network init). Console.app OSLog от extension показал:

```
[Extension app.bbtb.client.ios.tunnel]: Started with error
  startOrReloadService: start inbound/tun[tun-in]:
  configure tun interface: Invalid NETunnelNetworkSettings tunnelRemoteAddress
```

**Cause:** В `ConfigImporter.provisionTunnelProfile` Phase 2 W3 rewrite (commit `5fa9a29`) изменил `proto.serverAddress` с `server.host` (Phase 1 working) на `"BBTB"` (literal label). iOS прокидывает это значение в `NEPacketTunnelNetworkSettings.tunnelRemoteAddress` через цепочку:

```
ConfigImporter.proto.serverAddress = "BBTB"
   → BaseSingBoxTunnel.startTunnel → guard let serverAddress = proto.serverAddress
   → ExtensionPlatformInterface(serverAddressHint: serverAddress)
   → TunnelSettings.makeR6Safe(serverAddress: hint)
   → NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "BBTB")  ← iOS rejects
```

iOS отвергает буквы как невалидный hostname/IP. Extension падает в openTun, sing-box engine даже не загружается (объясняет пустой sing-box.log).

**Fix (commit `39356a4`):** Извлекать host первого supported outbound из pool (VLESS или Trojan), передавать в `provisionTunnelProfile(serverHost:)`, ставить `proto.serverAddress = serverHost`. Это совпадает с Phase 1 поведением.

**Также найдены небольшие UX findings** (не блокеры, отложены до Phase 11 polish):

1. **Tunnel error message не отображается** — `.error(message:)` state в `MainScreenView` не показывает `message` пользователю (только pill «Ошибка» без подробностей). Phase 1 показывал error через alert; Phase 2 показывает только для import errors, не для tunnel errors.
2. **Wrapped error text** — alert при T3 показал `Parse: Fetch failed: ...` — технические префиксы из enum-обёрток (`ImporterError → ParserError → FetcherError`). Должна показываться только финальная пользовательская строка.
3. **Empty-state UI** — описание было неверно понято в одной итерации (карточка vs. только текст). Спецификация в CONTEXT.md / UI-SPEC уточнена.

---

## Что делать после возобновления

### Шаг 1 — Retry T5 (5 минут)

1. В Xcode (workspace `BBTB.xcworkspace` уже открыт) → **Stop** (⌘.) → **Run** (⌘R). Пересоберёт с фиксом `39356a4` и переустановит на iPhone.
2. На iPhone — pool из T4 ещё в SwiftData. Можно сразу tap **power-кнопку** (без re-import).
3. **Жди ~3-10 секунд** — TCP + TLS + WebSocket handshake к `185.237.218.81:2087`.
4. Ожидаемый PASS: state `.connected`, timer пошёл, pill «Подключено», Safari → `https://api.ipify.org` показывает `185.237.218.81`.

### Шаг 2 — Если T5 PASS — продолжить с T6-T9

- **T6 (urltest failover)** — broken URI scenario: импортировать pool где один URI заведомо ломаный (например изменить port `2087` → `2088` в одной из Trojan-URI). urltest должен исключить broken outbound в течение ~1-2 минут. Server SSH у пользователя есть, но shared с другими — broken-URI подход безопаснее.
- **T7 (Kill Switch OFF)** — Settings → toggle off → connect → проверить `Include All Networks = OFF` в iOS Settings → VPN → BBTB.
- **T8 (Kill Switch ON)** — toggle on → reconnect → проверить default behavior.
- **T9 (banner)** — connect → toggle Kill Switch когда `.connected` → проверить ReconnectBanner.

### Шаг 3 — Если T5 всё ещё FAIL

Запросить новые OSLog (Console.app, filter `bbtb`, 30s после tap). Возможные оставшиеся причины:
- sing-box engine падает на чём-то другом (нужно проверить sing-box.log в Documents — должен быть полнее после успешного openTun).
- Trojan-WS специфика в libbox 1.13.11.
- TLS handshake с `vpn.vergevsky.ru:2087` со стороны клиента.

### Шаг 4 — После полного UAT

- Обновить `02-UAT.md` с финальной таблицей PASS/FAIL по T1-T9.
- Зафиксировать findings (3 UX-issues выше) в Phase 11 backlog или в `02-EXECUTION-LOG.md`.
- Commit финальный transition `docs(phase-2): UAT closed — N/9 PASS, ready for Phase 3`.
- Запустить `/gsd-discuss-phase 3` (Server management).

---

## Состояние git (на момент паузы)

```
HEAD: 39356a4 fix(02/uat-t5): serverAddress = host первого outbound (Phase 1 regression)
```

Phase 2 commits после `eafb88c` (Phase 1 close):
- `ceefc73` discuss artefacts
- `89ef6d7` ROADMAP/REQ sync
- `b59bcac` UI-SPEC + RESEARCH + PATTERNS
- `7f063ff` PLAN + PLAN-CHECK
- 18 atomic W0-W6 commits
- `2c52e27` security fixes (T-02-04 + W-02-08)
- `7b39384` VERIFICATION
- `5c38f6f` STATE.md transition
- `6d0f798` fp= empty → "chrome" default fix (UAT discovery)
- `39356a4` serverAddress regression fix (UAT discovery) ← **HEAD**

Всего ~25 commits в Phase 2.

---

*Generated: 2026-05-12 ~10:45.*
*Paused: context exhaustion.*
*Resume from: Step 1 above (Xcode ⌘R retry T5).*
