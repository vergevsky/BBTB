# Project State

## Project Reference

See: `.planning/PROJECT.md` (initialized 2026-05-11)

**Project codename:** `BBTB` (display name «Верни жука» / «Bring Back the Bug»)
**Core value:** В один тап получить VPN-соединение, обходящее ТСПУ, без необходимости разбираться в протоколах.

**Current focus:** Phase 1 — Foundation (v0.1)

## Active Phase

- **Phase:** 1
- **Name:** Foundation
- **Status:** W0..W5 + W3.1 gap-closure complete; validate-r1-r6.sh green (11 invariants + SPM test packages PASS); **W5-T4 device DoD: PARTIAL — туннель + DNS + Apple/Telegram backbone работают, Safari user HTTPS обрывается** (commit `0299af6`, 2026-05-11). Подозрение на sing-box vs Xray Vision incompatibility. См. `.planning/phases/01-foundation/01-W5-device-debug-2026-05-11.md`. Следующий шаг — Опция Б (trace-level sing-box log).
- **Goal:** Минимально жизнеспособная сборка с VLESS+Vision+Reality, kill switch и базовой архитектурой SwiftPM.
- **Context file:** `.planning/phases/01-foundation/01-CONTEXT.md`
- **Build system:** Tuist 4.x (`BBTB/Project.swift` + `BBTB/Workspace.swift`)
- **libbox.xcframework:** built from sing-box v1.13.11 via `make lib_apple`; postprocessed via `BBTB/scripts/fix-libbox-xcframework.sh`
- **Dev workflow:** `bash BBTB/scripts/dev-bootstrap.sh` resolves SPM, generates xcodeproj, builds both schemes

## W3.1 Gap-Closure (TUN inbound cleanup)

- **Status:** ✓ Complete 2026-05-11 — все 5 tasks + 2 побочных fix'а закоммичены атомарно.
- **Plan:** `.planning/phases/01-foundation/01-W3.1-tun-inbound-cleanup-PLAN.md`
- **Summary:** `.planning/phases/01-foundation/01-W3.1-tun-inbound-cleanup-SUMMARY.md`
- **What changed:** R1 валидатор ослаблен (forbidden = {socks, http, mixed, redirect, tproxy}); публичный `SingBoxConfigLoader.expandConfigForTunnel`; hack убран из `BaseSingBoxTunnel`; wiki R10 закрывает архитектурное решение.

## Progress

| Phase | Name | Version | Status |
|-------|------|---------|--------|
| 1 | Foundation | v0.1 | Not started |
| 2 | Trojan + Import flow | v0.2 | Not started |
| 3 | Server management | v0.3 | Not started |
| 4 | Protocol expansion | v0.4 | Not started |
| 5 | Transports | v0.5 | Not started |
| 6 | Network resilience | v0.6 | Not started |
| 7 | Anti-DPI suite + WireGuard family | v0.7 | Not started |
| 8 | Rules Engine + Split tunneling | v0.8 | Not started |
| 9 | Deep links | v0.9 | Not started |
| 10 | Advanced settings + Security polish | v0.10 | Not started |
| 11 | Onboarding + UX polish | v0.11 | Not started |
| 12 | Pre-release + Public TestFlight | v0.12 + v1.0 | Not started |

## Next Action

W5-T4 device DoD #1 ipify swap — **в работе, partial pass.** См. `.planning/phases/01-foundation/01-W5-device-debug-2026-05-11.md`.

**Текущий блокер:** Safari user HTTPS обрывается до TLS completion. Подозрение sing-box vs Xray-core Vision implementation incompatibility (Happ работает с тем же URI). Зафиксировано в `wiki/vless-reality.md` секция «Известный issue».

**Следующий шаг (после очистки контекста, выбран пользователем):**
- **Опция Б** — trace-level sing-box.log, искать новые ошибки в `level: trace` которые скрыты в `info`
- **Опция В** (fallback) — clone Hiddify-Next и diff sing-box JSON генерации с нашим

Опции зафиксированы в memo `~/.claude/projects/.../memory/project_phase1_next_options_2026-05-11.md`.

**После завершения W5-T4** — оставшиеся DoD'ы:
- DoD #2 kill switch blocks traffic on tunnel drop
- R1 SocksProbe screenshots (all ports closed)
- R6 POINTOPOINT: NO screenshots
- DIST-01/DIST-02 archive smoke

Затем `/gsd-verify-work 1`.

---
*Last updated: 2026-05-11 after Phase 1 W5 device debug session (commit `0299af6`): DNS pipeline rebuild + log injection + Vision-related outbound tuning. Partial pass — backbone traffic works, user HTTPS blocked, sing-box Vision incompatibility candidate.*

## Open UX issue (post-W3.1 device test, 2026-05-11)

**Симптом**: после удаления VPN profile из iOS Settings, BBTB main screen остаётся в `error` state с текстом «No VPN profile — import config first», но без кнопки «Импортировать из буфера» (SwiftData запись осталась активной, UI читает её как «сервер есть», но manager отсутствует).

**Workaround**: delete + reinstall приложения через Xcode сбрасывает SwiftData и возвращает empty state.

**Постоянный fix** (Phase 11 UX polish или раньше): в `MainScreenViewModel` при `error` state из-за `manager == nil` показывать действия «Re-create VPN profile from saved server» (просто snapshot config + saveToPreferences) и «Delete server», вместо тупикового error. Альтернатива — auto-recreate manager при старте приложения если активный ServerConfig есть, а manager отсутствует.

**Связано с**: REQ UX-02 (empty state UX), REQ CORE-07 (server lifecycle).

---

## Phase 1 device test progress 2026-05-11 (continued)

**Туннель доходит до `NEVPNStatus.connected` на iPhone (iOS 26).** Через него проходит ~100KB трафика, но `https://api.ipify.org` бесконечно грузит — пользовательский трафик не достигает destinations. Гипотеза: эти 100KB — внутренний трафик sing-box (Reality handshake retries + DoH attempts), а user TCP застревает между TUN inbound и vless outbound.

**4 закрытых блокера (закоммичены 2026-05-11):**

1. **Provider-queue deadlock в `openTun`** — completion-handler `setTunnelNetworkSettings` ждал освобождения той же провайдер-очереди, которую блокировал `semaphore.wait()`. Fix: `startOrReloadService` вынесен в `DispatchQueue.global().async` (`BaseSingBoxTunnel.swift:165-191`). Гипотеза подтверждена Codex'ом + экспериментом с 5s timeout.
2. **`stack: "system"` запрещён в iOS NE sandbox** — `SingBoxConfigLoader.expandConfigForTunnel` теперь ставит `stack: "gvisor"`. Это **канонический выбор** для NE, не временный workaround. См. sing-tun #25.
3. **R6 client-side mitigation сломан на iOS 26** — все `utun*` имеют `IFF_POINTOPOINT` независимо от отсутствия `destinationAddresses`. Наш DEBUG-only assert валил extension с corpse. Заменён на warning (`InterfaceFlagsInspector.swift`). R6 как фича требует переосмысления — этот вектор detection больше не контролируется на стороне клиента.
4. **KVC `socket.fileDescriptor` на iOS 26 не отдаётся как `Int32`** (возвращает что-то приватное). Fallback на `LibboxGetTunnelFileDescriptor()` отдал FD=5, и туннель завёлся. Это **возможно** часть загадки про "трафик не доходит" — стоит подтвердить, что FD корректный. Добавлены подробные trace-логи + 5s timeout safety-net (`ExtensionPlatformInterface.swift`).

**Полезные референсы из сессии:**
- Codex (GPT-5) CLI работает (`codex` глобально), отличный инструмент для диагностики архитектурных проблем.
- Gemini API заблокирован из RU (`User location is not supported`).
- Happ работает с тем же VLESS URI на том же iPhone из той же сети → ТСПУ и сервер не виноваты.
- `nc -zv 185.237.218.81 25871` с Mac → succeeded.

**Следующий шаг — диагностика пользовательского forwarding:**
- Добавить `log.output` в sing-box config (путь в App Group container `/private/var/mobile/Containers/Shared/AppGroup/.../sing-box.log`).
- Пересобрать → запустить → попытаться открыть api.ipify.org.
- Выкачать container через Xcode → прочитать sing-box internal logs.
- Это покажет Reality handshake outcome, DNS query path, TCP forwarding errors.

**Альтернативный быстрый тест:** Safari → `https://1.1.1.1` (без DNS). Если откроется — проблема в DNS layer (cf-doh через vless-out). Если нет — broken forwarding на уровне TUN/vless.

**Что осталось НЕ закоммичено:**
- `KillSwitch.swift` откачен к продакшну (`includeAllNetworks=true, enforceRoutes=true`) — все 4 фикса выше работают и с включённым kill switch (теоретически; практически надо подтвердить пересборкой с прода).
