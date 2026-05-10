---
name: Методичка РКН по детекту VPN
description: Структура методики РКН по обнаружению VPN на пользовательских устройствах — карта угроз для нашего проекта
type: project
---

# Методичка РКН по детекту VPN

**Summary**: Репозиторий `xtclovver/RKNHardering` (Android, Kotlin, 1231 ★) — практическая реализация методики РКН по детектированию VPN на пользовательском устройстве. Это **Android-имплементация**; официальный первоисточник методики см. [[rkn-methodology-document]]. iOS/macOS-релевантные методы — [[apple-detection-surface]].

**Sources**: https://github.com/xtclovver/RKNHardering (README, обновлён 2026-05-10), Дыры в безопасности, которые нужно обсудить.md

**Last updated**: 2026-05-11

---

## Контекст

Это **Android-приложение** для детектирования VPN/прокси на устройстве, реализующее методику РКН. Минимальная версия Android 8.0 (API 26). Целевая платформа отличается от нашей (iOS/macOS).

Для нашего проекта эта страница — **дополнение** к [[rkn-methodology-document|первоисточнику методики]] и [[apple-detection-surface|переносу на наши платформы]]. Здесь сохранены детали Android-имплементации для понимания «как именно работает детектор на практике», но **архитектурные выводы для iOS/macOS** — на тех страницах.

Автор репозитория параллельно ищет помощь сообщества по **обратной задаче** — как ПРЕДОТВРАТИТЬ детектирование VPN (см. ниже).

## Архитектура детектора

Параллельный запуск независимых модулей проверки, итоговый вердикт в `VerdictEngine`.

```
VpnCheckRunner
├── GeoIpChecker           — GeoIP + hosting/proxy-сигналы
├── IpComparisonChecker    — RU/не-RU IP-чекеры (диагностика)
├── DirectSignsChecker     — NetworkCapabilities, системный proxy, установленные VPN apps
├── IndirectSignsChecker   — интерфейсы, маршруты, DNS, dumpsys, proxy-tech signals
├── CallTransportChecker   — STUN/MTProto (утечки и доступность)
├── CdnPullingChecker      — HTTPS-запросы к CDN/redirector
├── LocationSignalsChecker — MCC/SIM/cell/Wi-Fi/BeaconDB
├── BypassChecker          — localhost proxy, Xray gRPC API, underlying-network leak
├── RttTriangulationChecker — SNITCH (β): RTT-триангуляция по RU/иностранным хостам
└── NativeSignsChecker     — JNI-проверки (маршруты, интерфейсы, хуки, root)
        └── VerdictEngine  — логика итогового вердикта
```

## Категории сигналов

### 1. GeoIP

Источники: `api.ipapi.is` (основной), `iplocate.io` (fallback). Сигналы:

| Сигнал | Логика |
|--------|--------|
| `countryCode != RU` | needsReview, если нет одновременно `hosting` и `proxy` |
| `hosting` | majority vote по совместимым ответам — `detected` |
| `proxy` | хотя бы один источник говорит о proxy/VPN/Tor — `detected` |

### 2. Прямые признаки

- **`NetworkCapabilities`**: `TRANSPORT_VPN`, строки `IS_VPN`, `VpnTransportInfo`
- **Системный proxy**: `System.getProperty("http.proxyHost")`, `ConnectivityManager.getDefaultProxy()`, `ProxyInfo.getPacFileUrl()`
- **Известные proxy-порты**: 80, 443, 1080, 3127, 3128, 4080, 5555, 7000, 7044, 8000, 8080, 8081, 8082, 8888, 9000, 9050, 9051, 9150, 12345, диапазон 16000..16100
- **Установленные VPN-приложения** через `PackageManager`

### 3. Косвенные признаки

- **Отсутствие `NOT_VPN`** capability — `detected`
- **VPN-подобные интерфейсы**: `tun\d+`, `tap\d+`, `wg\d+`, `ppp\d+`, `ipsec.*` — `detected`
- **MTU аномалии**: VPN-подобный интерфейс с MTU 1..1499 — `detected`
- **Маршрутизация**: default route через нестандартный интерфейс или split tunneling — `detected`
- **DNS**: loopback DNS (`127.x.x.x`, `::1`) — `detected`; private DNS при активном VPN с отличием от underlying сети — `detected`
- **`dumpsys vpn_management`** (Android 12+) и **`dumpsys activity services android.net.VpnService`** — активные VPN-записи — `detected`

### 4. Bypass-проверки

- **Сканер localhost-прокси** (порты 1024..65535, параллельность 200, таймаут connect 80мс): обнаруживает SOCKS5 (`0x05 0x01 0x00`) и HTTP CONNECT — это критично для xray/sing-box, см. [[xray-localhost-vulnerability]]
- **Сканер Xray gRPC API** через `HandlerServiceGrpc.listOutbounds(...)` — может вытащить полный список outbounds (`tag`, `protocol`, `address`, `port`, `sni`)
- **Underlying network leak**: при активном VPN перебирает все internet-capable сети без `TRANSPORT_VPN`, привязывает HTTPS-запросы к ним и запрашивает публичный IP — `detected`, если получает прямой IP

### 5. Сигналы местоположения

`TelephonyManager.networkOperator` (`MCC = 250` для RU), Wi-Fi BSSID + BeaconDB (`api.beacondb.net/v1/geolocate`), reverse geocoding.

### 6. SNITCH — RTT-триангуляция (β)

ICMP ping к российским (`yandex.ru`, `mail.ru`, `vk.com`, `sberbank.ru`, `gosuslugi.ru`) и иностранным хостам (`facebook.com`, `github.com`, `twitter.com`, `reddit.com`, `instagram.com`). Если медианный RTT до RU-хостов > 80 мс — устройство, вероятно, не в РФ.

### 7. Native JNI-проверки

- `getifaddrs()`, прямой парсинг `/proc/net/route`
- сканирование `/proc/self/maps` на признаки hook'ов
- целостность `dlsym`
- обнаружение root

## Что переносимо на iOS/macOS

Полную карту см. в [[apple-detection-surface]]. Короткая сводка:

| Метод детекта (Android) | iOS / macOS |
|-------------------------|-------------|
| GeoIP | ✅ переносимо полностью |
| `NetworkInterface` (`utun*`) | ✅ переносимо — Foundation API даёт интерфейсы |
| Сканирование localhost-портов | ⚠ частично — sandbox ограничивает |
| `tun*` интерфейсы | ✅ на Apple — `utun*` |
| MTU аномалии | ✅ переносимо |
| DNS leak / loopback DNS | ✅ переносимо |
| `dumpsys` | ❌ Android-specific |
| `/proc/*` | ❌ на iOS не применимо, частично на macOS |
| SNITCH RTT-триангуляция | ✅ полностью переносимо, см. [[snitch-rtt-detection]] |
| Underlying network leak | ⚠ на iOS через `NWPathMonitor` |
| Запрос Xray gRPC API на localhost | ✅ переносимо если xray слушает localhost — см. [[xray-localhost-vulnerability]] |

## Открытая задача автора репо

Автор открыто ищет помощь по «обратной задаче» — как СКРЫТЬ VPN от детекта на Android:

- маскировка `tun0`/`wg0` интерфейсов
- подмена `NetworkCapabilities` (убрать `TRANSPORT_VPN`)
- скрытие от `dumpsys`
- MTU-нормализация (выставление 1500 для туннельных интерфейсов)
- предотвращение DNS-leak'ов
- скрытие localhost-прокси
- обход нативных JNI-проверок
- маскировка установленных VPN-приложений от `PackageManager`

Это roadmap антидетекта — для нас часть пунктов переносится напрямую (MTU-нормализация, скрытие localhost), часть требует iOS-специфичных подходов.

## Что это значит для проекта

См. [[security-gaps]] — обсуждение приоритетов по антидетекту.

## Related pages

- [[rkn-methodology-document]]
- [[apple-detection-surface]]
- [[geoip-detection]]
- [[snitch-rtt-detection]]
- [[false-positives]]
- [[xray-localhost-vulnerability]]
- [[vpn-detection-by-apps]]
- [[tspu]]
- [[security-gaps]]
- [[anti-dpi-techniques]]
