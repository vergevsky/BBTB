---
name: Релизный roadmap
description: Версии v0.1–v2.1 с фичами и Definition of Done на каждом шаге
type: project
---

# Релизный roadmap

**Summary**: 12 поэтапных релизов от v0.1 (Foundation) до v1.0 (публичный TestFlight) + дальнейшие v1.1–v2.1. Semver, без жёсткого календаря, релизы по готовности фич.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-11

---

## Принципы релизов

- **v0.x** — internal alpha, узкий круг бета-тестеров среди близких знакомых
- **v1.0** — публичный TestFlight, прошедший Beta App Review
- **v1.x** — расширение фичами, всё ещё в публичном TestFlight
- **v2.x** — мажорные изменения архитектуры или бизнес-модели (managed-серверы и т.п.)

Каждая версия — самодостаточная сборка для TestFlight, готовая к раздаче friends-tier тестировщикам.

## v0.1 — Foundation

Минимально жизнеспособная сборка. Только [[vless-reality|VLESS+Vision+Reality]], импорт через буфер обмена, главный экран (таймер + кнопка + статус), [[kill-switch]] (включён по дефолту), iOS+macOS минимальные сборки, базовая модульная архитектура SwiftPM, локальный crash reporter (без UI отправки пока).

**Security review до релиза** (см. [[security-gaps]] R1, R6):
- Проверить, что `libbox.xcframework` не запускает локальный SOCKS5 (см. [[xray-localhost-vulnerability]])
- Отключить gRPC API sing-box в production-сборке
- При настройке `NEPacketTunnelNetworkSettings` не выставлять `P2P=true` на интерфейсе

**DoD**: на iPhone и MacBook импортируется vless+vision+reality конфиг → подключение → IP меняется по `api.ipify.org` → kill switch блокирует трафик при разрыве туннеля → security review passed.

## v0.2 — Trojan + Import flow

Trojan, импорт через QR-код и файл, auto-fallback между протоколами одного сервера при DPI-блокировке, toggle для kill switch в Расширенных.

**DoD**: импорт любым из трёх способов; при блокировке VLESS+Reality автоматически пробуется Trojan без действий пользователя.

## v0.3 — Server management

Auto-select сервера по пингу + потерям, экран списка серверов (референс — Hiddify) с pull-to-refresh, bottom bar главного экрана с кнопкой выбора, connection timer, поддержка нескольких subscription URL.

**DoD**: pull-to-refresh обновляет список; auto-select переключает на сервер с наименьшим latency; timer считает с момента установки туннеля.

## v0.4 — Protocol expansion

VLESS+XTLS-Vision (без Reality), Shadowsocks-2022, Hysteria2. ConfigParser: полная поддержка URI (vless://, ss://, trojan://, hy2://) + subscription URL формата v2ray. Outline access keys.

**DoD**: импортируется любой формат; все 5 протоколов подключаются на тестовых серверах.

## v0.5 — Transports

XHTTP (приоритетный для anti-DPI), gRPC, WebSocket, HTTPUpgrade. Регистрация транспортов через `TransportRegistry` (см. [[architecture]]).

**DoD**: VLESS работает поверх каждого из четырёх транспортов; в Расширенных можно вручную выбрать транспорт.

## v0.6 — Network resilience

DoH (DNS over HTTPS) внутри туннеля, encrypted bootstrap DNS, whitelist провайдеров (Cloudflare/NextDNS/AdGuard/Quad9), IPv6 туннелирование с fallback на блок, auto-reconnect при смене Wi-Fi ↔ LTE / выхода из sleep / смены IP, failover на другой сервер при падении.

**DoD**: DNS leak-test пройден; IPv6 leak-test пройден; смена сети не приводит к утечкам трафика.

## v0.7 — Anti-DPI suite + WireGuard family

uTLS fingerprint mimicking (Chrome/Firefox/Safari/random), TLS ClientHello фрагментация, packet padding, random TCP/UDP delay, mux. WireGuard через WireGuardKit, AmneziaWG, TUIC v5, OpenVPN over TLS.

**DoD**: все 9 протоколов подключаются; обход тестового DPI-сценария проходит. Подробности — [[anti-dpi-techniques]].

## v0.8 — Rules Engine + Split tunneling

Скачивание rules.json с primary VPS + failover-зеркала, проверка Ed25519-подписи, применение правил `always_through_vpn`/`never_through_vpn`/`block_completely`, split tunneling по доменам/IP/CIDR/странам, AppProxyProvider на macOS, просмотр текущих правил (read-only), ручное обновление через кнопку.

**DoD**: подмена rules.json на сервере → клиент применяет в течение 6 часов; битая подпись → откат на закешированную версию; на macOS можно роутить отдельные приложения через VPN. Подробности — [[rules-engine]].

## v0.9 — Deep links

Custom URL Scheme `bbtb://` (import/connect/disconnect), Universal Links + apple-app-site-association, endpoint `https://import.bbtb.app/c/{token}` на VPS, landing page для тех, у кого приложение не установлено.

**DoD**: тап на `bbtb://import?config=...` в Telegram открывает приложение и импортирует конфиг; тап на `https://import.bbtb.app/c/...` делает то же самое. Подробности — [[deep-links]].

## v0.10 — Advanced settings + Security polish

Расширенные настройки полностью, биометрия (Face ID / Touch ID), тоггл «Блокировать STUN», On-Demand rules («всегда вкл» + автоконнект в публичных Wi-Fi), CDN-фронтинг как fallback transport, cert pinning, ручной выбор протокола, выбор uTLS fingerprint.

**macOS only**: тоггл «Отключить принудительную маршрутизацию» (выкл `enforceRoutes`) для tech-savvy пользователей — снижает детектируемость на macOS ценой риска DNS-leak. См. [[security-gaps]] R5.

**DoD**: все опции в Расширенных функциональны и сохраняются; биометрия защищает приложение при backgrounding.

## v0.11 — Onboarding + UX polish

Финальный onboarding по Figma, финальный дизайн всех экранов, полная локализация ru+en (никаких hardcoded строк), [[max-messenger|MAX-detection]] (без UI, только в локальный лог), кнопка «Отправить лог разработчику», FAQ в разделе Help, анимации переходов главной кнопки.

**DoD**: visual review соответствует Figma; локализация-аудит не находит хардкода; MAX-detection отрабатывает без раздражения пользователя.

## v0.12 — Telemetry + Pre-release

Privacy-respecting аналитика на собственном VPS, crash reporter с UI отправки, performance audit (Instruments: CPU/memory/energy), memory leak audit, тоггл отключения аналитики, App Privacy declaration заполнена.

**DoD**: телеметрия батч долетает до сервера; крашлоги пишутся и отправляются; нет утечек памяти при многочасовом подключении.

## v1.0 — Public TestFlight Release 🚀

Beta App Review submission и approval, public invite link через TestFlight, сайт лендинга, About-screen с версией и ссылкой на open-source ядро, documentation для конечных пользователей.

**DoD**: приложение прошло Beta App Review; публичная invite-ссылка работает; пользователь, получивший ссылку в Telegram, может импортировать конфиг и подключиться без помощи разработчика.

## v1.1+ — После публичного MVP

- **v1.1** — smart auto-select (latency + jitter + DPI-успех с локальной памятью)
- **v1.2** — speed test, полные логи соединений с тогглом приватности, графики latency/jitter
- **v1.3** — multi-hop / chain proxy
- **v1.4** — iOS Widgets + Live Activity
- **v1.5** — Apple Watch (independent app)
- **v1.6** — push notifications
- **v1.7** — Shortcuts & Siri
- **v1.8** — Stealth & Panic mode (alternateIcons, decoy-режим, quick wipe)
- **v1.9** — iCloud sync
- **v2.0** — Major: managed-серверы, биллинг через App Store, аккаунты, server-side admin panel
- **v2.1** — Modular UI Pro (feature flags, режимы Basic/Pro)

## Related pages

- [[product-overview]]
- [[protocols-overview]]
- [[anti-dpi-techniques]]
- [[rules-engine]]
- [[deep-links]]
