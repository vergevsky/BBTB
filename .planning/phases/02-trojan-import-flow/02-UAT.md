# Phase 2 — UAT (User Acceptance Test) Plan

**Target device:** iPhone (iOS 18+) с активной TestFlight / Debug сборкой v0.2.
**Prerequisite:** Phase 1 build установлен и работает (Phase 1 UAT closed 2026-05-11).
**Estimated duration:** ~60 минут включая ожидание urltest switching window.

---

## T1 — Variant 1: Subscription URL import

**Цель:** Подтвердить D-02 / IMP-04 — клиент принимает subscription URL и парсит весь pool.

**Шаги:**
1. Открыть BBTB на iPhone.
2. Скопировать `https://vpn.vergevsky.ru/sub/VGVzdCwxNzc4NTIzNzExdXbmcsiR_Y` в буфер обмена.
3. Tap `+` → «Добавить из буфера».
4. Дождаться завершения progress overlay (~5-15s).

**Ожидаемое:**
- Alert «Импорт завершён. Добавлено: X. Будут включены в следующих версиях: Y.»
- iOS Settings → VPN — появилась запись «BBTB» (если ещё не было).
- В SwiftData rows должно быть ~6-7 (зависит от состава подписки).
- Top bar остаётся видимым; layout перешёл от empty-state карточки к idle layout
  (Timer + StatusPill + ConnectionButton + ServerLine).

---

## T2 — Variant 2: Multi-line URI block import

**Цель:** Подтвердить D-02 multi-line поддержку.

**Шаги:**
1. Скопировать в буфер обмена 6-строчный блок URI из `.planning/phases/02-trojan-import-flow/02-CONTEXT.md` `<specifics>` Вариант 2 (4 VLESS + 2 Trojan).
2. Tap `+` → «Добавить из буфера».

**Ожидаемое:** Alert «Импорт завершён. Добавлено: 6.»

---

## T3 — Variant 3: JSON endpoint import

**Цель:** Подтвердить D-02 JSON endpoint path.

**Шаги:**
1. Скопировать `https://185.237.218.81:24527/json/v3ry-53cur3-p4th-98231/g8ogx6367znwvy95` в буфер обмена.
2. Tap `+` → «Добавить из буфера».

**Ожидаемое:** Alert «Импорт завершён. Добавлено: N.» (N зависит от содержимого operator JSON).

---

## T4 — QR-code import

**Цель:** Подтвердить IMP-02 + camera permission flow.

**Шаги:**
1. Сгенерировать QR-код с одним vless:// URI (например через `qrencode` на ноутбуке).
2. На iPhone: tap `+` → «Сканировать QR».
3. (Первый запуск) — iOS показывает permission prompt — нажать «Разрешить».
4. Навести камеру на QR.

**Ожидаемое:**
- Виден preview камеры с hint «Наведите камеру на QR-код».
- При сканировании — haptic feedback (notification.success), sheet закрывается.
- Alert «Импорт завершён. Добавлено: 1.»

**Permission denied subtest:**
1. iOS Settings → BBTB → Camera → Deny.
2. Tap `+` → «Сканировать QR».

**Ожидаемое:** Видна "Open Settings" deep link на стандартный iOS Settings screen.

---

## T5 — Connect & IP change verification

**Цель:** Подтвердить что после import → connect туннель работает.

**Шаги:**
1. После T1/T2/T3 на главном экране.
2. Tap power button — state переходит .connecting → .connected.
3. Открыть Safari → `https://api.ipify.org`.

**Ожидаемое:**
- Status pill «Подключено» (green capsule, 18% bg).
- Timer считает с 00:00:00 вверх.
- IP на api.ipify.org — IP одного из серверов из импортированного пула (НЕ домашний IP).
- ServerLine показывает «Авто» (т.к. в пуле > 1 сервера) или конкретное имя для single-server.

---

## T6 — urltest failover (manual или natural)

**Цель:** Подтвердить PROTO-10 / D-01 — при failure активного outbound, urltest переключается.

**Шаги:**
1. После T5 (connected).
2. **Manual scenario:** на сервере остановить процесс sing-box на VLESS-сервере (через SSH).
3. **OR Natural scenario:** дождаться ТСПУ-блокировки VLESS (может занять часы — выполнить тест на нескольких сетях).
4. Подождать ~1-2 минуты (urltest interval=1m).
5. Проверить IP на api.ipify.org.

**Ожидаемое:**
- IP меняется на Trojan-сервер (или другой выживший outbound из пула).
- Connection продолжает работать без полного reconnect.
- VPN profile в iOS Settings остаётся active.

**Caveat:** real-device test. Если urltest не переключается за 2 минуты — проверить `interval` и `interrupt_exist_connections` в config через `sing-box check`.

---

## T7 — Kill Switch OFF round-trip

**Цель:** Подтвердить D-14, D-15.

**Шаги:**
1. Перейти в Settings (≡ → Настройки).
2. Toggle «Kill Switch» — выключить.
3. Возврат на MainScreen — ReconnectBanner НЕ показывается (т.к. tunnel был disconnected или ещё не connected).
4. Connect.
5. Открыть iOS Settings → VPN → BBTB → проверить «Include All Networks» = OFF.

**Ожидаемое:**
- VPN profile: includeAllNetworks=false, enforceRoutes=false.
- Tunnel работает в обычном split-VPN режиме.
- Local network (192.168.x.x) доступен.

---

## T8 — Kill Switch ON round-trip (return to default)

**Цель:** Подтвердить D-15 reverse.

**Шаги:**
1. Settings → Kill Switch — включить.
2. Connect → IP change verified.

**Ожидаемое:**
- VPN profile: includeAllNetworks=true.
- При искусственном disconnect (закрыть VPN profile через iOS Settings) — внешний трафик блокируется до restart.

---

## T9 — Toggle Kill Switch during active tunnel — banner appears

**Цель:** D-14 баннер «Переподключитесь».

**Шаги:**
1. Connect (state == .connected).
2. Settings → Kill Switch — toggle (любое направление).
3. Возврат на MainScreen.

**Ожидаемое:**
- ReconnectBanner показывается сверху со словами «Переподключитесь для применения изменений».
- Tap `✕` — banner закрывается.
- Disconnect → connect — изменения applied; banner не возвращается.

---

## Sign-off

После завершения всех 9 тестов:
- [x] T1 — **PASS** (subscription URL import, pool loaded, server-line «Сервер: Авто»)
- [x] T2 — **PASS** (multi-line URI block: 6 URI imported)
- [x] T3 — **PASS-B** (JSON endpoint: TLS cert mismatch via IP — R1 принцип работает корректно)
- [x] T4 — **PASS** (QR-код: Trojan-Латвия URI, permission flow OK)
- [x] T5 — **PASS** (connect + IP change; 3 UAT-баги закрыты: serverAddress, fp= fallback, ALPN h2 strip)
- [x] T6 — **PASS** (urltest failover: один Trojan outbound unavailable → трафик через рабочий)
- [x] T7 — **PASS** (Kill Switch OFF: includeAllNetworks=false подтверждён в iOS Settings)
- [x] T8 — **PASS** (Kill Switch ON: includeAllNetworks=true подтверждён в iOS Settings)
- [x] T9 — **PASS** (ReconnectBanner при toggle Kill Switch в активном тоннеле)

**Carry-forward Phase 1 invariants** (re-verified на v0.2 build):
- [x] R1 — SocksProbe не находит SOCKS listeners на 127.0.0.1 нашего PacketTunnelProvider.
- [x] R6 — N/A on iOS 26 (Apple unconditionally sets P2P flag — accepted, commit 74605f8).
- [x] No debug logs в Release config (Phase 1 SEC carry-forward).

**UAT date:** 2026-05-12
**Tester:** Nv (project owner)
**Sign-off:** PASS 9/9 (T3 = PASS-B: expected behaviour)

---

## Known caveats

- **macOS Debug build fails** with signing-cert error — Phase 1 DIST-02 gap, requires
  Apple Distribution cert + provisioning profile setup (see project memory
  "Phase 12 prerequisite"). iOS Simulator Debug + on-device Debug сработают.
- **AVCaptureSession on macOS Simulator** не имеет real camera — функциональный QR
  test возможен только на macOS device или с реальным iPhone для iOS.
- **sing-box urltest behavior** — libbox 1.13.11 specifics не были device-validated
  в Phase 2 executor; expected reasonable per docs, но T6 — критичный test
  на реальном устройстве.

---

*Phase 2 UAT v1.0 — 2026-05-12.*
*Generated by Phase 2 executor (autonomous).*
*Source: 02-PLAN.md W5.T2 + ROADMAP Phase 2 success criteria SC1-SC8.*
