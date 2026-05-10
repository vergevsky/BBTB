---
name: Парсер подписок singbox-launcher
description: Документация парсера URI-схем и подписок из репо Leadaxe/singbox-launcher — источник для нашего ConfigParser модуля
type: reference
---

# Парсер подписок singbox-launcher

**Summary**: Документация парсера из `Leadaxe/singbox-launcher` — рабочий референс для нашего модуля `ConfigParser`. Описывает поддержку URI-схем (vless, vmess, trojan, ss, hy2, wireguard и др.), форматы подписок и edge cases.

**Sources**: Документация парсера подписок singbox-launcher.md (raw), https://github.com/Leadaxe/singbox-launcher/blob/main/docs/ParserConfig.md

**Last updated**: 2026-05-11

---

## Что это

`singbox-launcher` — конфигуратор для sing-box на других платформах. Его документация парсера — полезный референс для нашего модуля `ConfigParser` (см. [[architecture]]), потому что описывает:

- Какие URI-схемы парсятся и как
- Как обрабатываются подписки (base64, plain-text, JSON-массивы)
- Какие edge cases и ограничения известны

## Поддерживаемые URI-схемы

| Схема | Назначение |
|-------|------------|
| `vless://` | VLESS с поддержкой TLS/Reality (наш приоритетный — см. [[vless-reality]]) |
| `vmess://` | VMess (base64 JSON или legacy формат) |
| `trojan://` | Trojan-протокол |
| `ss://` | Shadowsocks (формат SIP002) |
| `hysteria2://` или `hy2://` | Hysteria2 с обфускацией |
| `ssh://` | SSH-туннелирование |
| `socks5://` или `socks://` | SOCKS5 |
| `naive+https://`, `naive+quic://` | NaïveProxy (требует sing-box ≥ 1.13.0) |
| `wireguard://` | WireGuard (sing-box 1.11+) |

## Форматы подписок

- Base64-кодированные списки строк URI
- Plain-text списки URI
- JSON-массивы полных конфигов Xray/V2Ray

## Особенности парсера

- **Версионирование конфига** (на момент документации — версия 4)
- **Управление источниками**: фильтры (`skip` arrays), tag prefixing/postfixing, локальные outbounds
- **Селекторы**: `selector` и `urltest` типы
- **Парсинг нод**: extract server, port, encryption, protocol параметров
- Результаты пишутся между маркерами `/** @ParserSTART */` и `/** @ParserSTART_E */` (для WireGuard endpoints)

## Поддерживаемые транспорты

TCP, WebSocket (`ws`), gRPC, HTTP, `xhttp`/`httpupgrade`, QUIC, raw — все совпадают с нашим списком (см. [[transports]]).

## Поддерживаемые TLS-фичи

- SNI configuration
- uTLS fingerprint support (то, что мы используем в [[anti-dpi-techniques]])
- Certificate validation options
- ALPN handling

## Известные edge cases и ограничения

Полезно учесть в нашем `ConfigParser`:

| Edge case | Что делать |
|-----------|------------|
| **WireGuard с несколькими peers** | Не кодируется в single share URI. Только через JSON. |
| **Xray JSON arrays** | `singbox-launcher` парсит **только** sing-box формат, не полные Xray-массивы. Мы должны решить: парсить ли Xray-формат? |
| **NaïveProxy** | Требует explicit build tag; custom SNI пока не поддержан. На MVP не делаем. |
| **SSH** | Не инлайнит приватные ключи в URI — нужны пути. На MVP можно опустить SSH вообще. |
| **VMess legacy cleartext** | Поддержан, но non-standard. Учесть для совместимости. |
| **Outbounds с `detour`** (subscription chains) | Не делятся как URI. Только через JSON. Multi-hop в нашем roadmap — v1.3. |

## Что использовать у себя

При реализации модуля `ConfigParser` (см. [[architecture]]) можно:

1. Взять список URI-схем из этой документации как baseline
2. Учесть edge cases с самого начала (WireGuard multi-peer, VMess legacy)
3. Не реализовывать SSH и NaïveProxy на MVP — отложить
4. Опционально: рассмотреть совместимость с Xray JSON-массивами (post-MVP)

## Что НЕ копировать

`singbox-launcher` — это конфигуратор для sing-box на desktop/CLI, у него своя архитектура с парсингом в `bin/config.json` и маркерами. Наш `ConfigParser` — Swift-модуль с in-memory моделью, маркеры и shell-логика нерелевантны.

## Лицензия

Репозиторий — `Leadaxe/singbox-launcher` на GitHub. Перед заимствованием кода или подходов **проверить лицензию** репо (предположительно GPL-совместимая, как у самого sing-box, см. [[licensing]]).

## Related pages

- [[architecture]]
- [[protocols-overview]]
- [[transports]]
- [[vless-reality]]
- [[release-roadmap]]
