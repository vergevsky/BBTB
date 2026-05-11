# Phase 1 Security Evidence

Эта директория хранит **артефакты ручной проверки** Phase 1: скриншоты, логи, и manual smoke-test reports.

## Что должно сюда попасть до закрытия Phase 1

| Файл | Содержание | Кто кладёт |
|------|-----------|------------|
| `r1-socksprobe-iphone.png` | Скриншот SocksProbe на iPhone при активном BBTB-туннеле, все порты «closed» | W5-T4 (manual) |
| `r1-socksprobe-mac.png` | Скриншот SocksProbe на Mac при активном BBTB-туннеле, все порты «closed» | W5-T4 (manual) |
| `r6-no-p2p-iphone.png` | Скриншот SocksProbe utun-секции с «POINTOPOINT: NO» | W5-T4 (manual) |
| `r6-no-p2p-mac.png` | То же на macOS | W5-T4 (manual) |
| `r6-no-p2p.log` | Текстовый дамп `getifaddrs` для всех utun*: имя, addresses, flags, POINTOPOINT YES/NO | W5-T4 (manual) |
| `dod1-api-ipify-iphone.png` | Скриншот Safari на iPhone с `https://api.ipify.org` показывающим IP сервера VPN (не реальный пользовательский) | W5-T4 (manual) |
| `dod1-api-ipify-mac.png` | То же на Mac | W5-T4 (manual) |
| `dod2-killswitch-iphone.png` | Скриншот Safari с ошибкой загрузки https://example.com после убийства sing-box на сервере (трафик заблокирован kill switch'ем) | W5-T4 (manual) |
| `dod2-killswitch-mac.png` | То же на Mac | W5-T4 (manual) |
| `dod-iphone.md` | Прозаический отчёт о ручной проверке всех DoD на iPhone (см. template ниже) | W5-T4 (manual) |
| `dod-mac.md` | То же на Mac | W5-T4 (manual) |
| `archive-ios-output.log` | Лог `bash BBTB/scripts/archive-ios.sh` — стэйджит DIST-01 | W5-T4 |
| `archive-macos-output.log` | Лог `bash BBTB/scripts/archive-macos.sh` — стэйджит DIST-02 | W5-T4 |
| `validate-r1-r6-output.log` | Лог `bash BBTB/scripts/validate-r1-r6.sh` — все green | W5-T2 (auto) |

## Template — `dod-iphone.md` (W5-T4 заполняет)

```markdown
# Phase 1 DoD Manual Verification — iPhone

**Date:** YYYY-MM-DD
**Device:** iPhone XX (iOS X.Y)
**Tester:** {developer}
**Test config:** Tests/Fixtures/test-config.vless.local.txt (host masked)

## DoD #1 — api.ipify.org IP swap

1. ✓ Установлен BBTB через TestFlight Internal / Xcode signing.
2. ✓ Импорт через буфер обмена — vless:// → видно «Импорт успешен», name = (remarks).
3. ✓ Тап ConnectButton → status «Подключение…» → «Подключено», timer считает.
4. ✓ Safari → https://api.ipify.org → IP отображается = IP сервера (не оригинальный).
5. ✓ Скриншот: `dod1-api-ipify-iphone.png`.

**Result: PASS / FAIL**

## DoD #2 — Kill switch blocks traffic on tunnel drop

1. ✓ Туннель активен.
2. ✓ На сервере (SSH): `sudo systemctl stop sing-box` (или kill процесс).
3. ✓ В Safari → https://example.com → ошибка timeout / no internet.
4. ✓ Скриншот ошибки: `dod2-killswitch-iphone.png`.
5. ✓ После `sudo systemctl start sing-box` на сервере — трафик восстанавливается (timer продолжает).

**Result: PASS / FAIL**

## R1 — No SOCKS5 on loopback

1. ✓ Установлен SocksProbe (отдельное приложение от BBTB) на iPhone.
2. ✓ Tunnel активен.
3. ✓ Открыт SocksProbe → Start Scan.
4. ✓ Все порты из `RKNPorts.phase1` (1080, 9000, 5555, 16000-16100, 3128, 3127, 8000, 8080, 8081, 8888, 9050, 9051, 9150) → status `closed`.
5. ✓ Summary: «R1 verdict: PASS — no ports respond».
6. ✓ Скриншот: `r1-socksprobe-iphone.png`.

**Result: PASS / FAIL**

## R6 — No IFF_POINTOPOINT on utun

1. ✓ В том же SocksProbe scan видна секция «utun interfaces».
2. ✓ Все utun-интерфейсы: POINTOPOINT: NO ✓.
3. ✓ Скриншот: `r6-no-p2p-iphone.png`.
4. ✓ Текстовый лог в `r6-no-p2p.log`.

**Result: PASS / FAIL**

## Release-режим без debug-логов

1. ✓ Открыть Console.app на Mac, подключить iPhone, фильтр subsystem = `app.bbtb.tunnel`.
2. ✓ Release-сборка (TestFlight) — нет debug-уровней; в Console только info/notice/error.
3. ✓ Скриншот фильтра Console: `release-no-debug-iphone.png`.

**Result: PASS / FAIL**
```

## Template — `dod-mac.md`

Аналогично iPhone, заменить `Safari → api.ipify.org` на macOS Safari/любой браузер; Console.app — встроенный на той же машине.

## Что НЕ требуется

- Не нужны NPVN profile screenshots (Settings → VPN) — это для Phase 12 Beta App Review.
- Не нужен полный suite UI screenshots (Phase 11 финализирует дизайн).
- Не нужны crash report samples — на свежем устройстве MetricKit может не доставить никаких payload'ов; достаточно убедиться что `CrashReporter.shared.install()` логирует «installed» в Console (info-уровень).
