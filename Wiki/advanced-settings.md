# Advanced Settings

**Summary**: Описание 5-секционного экрана «Расширенные настройки» (AdvancedSettingsView, D-15 layout) — все toggle, их defaults, persistence и платформенные ограничения.

**Sources**: `.planning/phases/10-advanced-settings-security-polish/10-CONTEXT.md` (D-15..D-17), Phase 10 waves 1-4.

**Last updated**: 2026-05-15 (Phase 10 closure — v0.10)

---

## Layout (D-15)

AdvancedSettingsView разделён на 5 секций в следующем порядке:

1. **DNS** — customDNS поле + AdBlock toggle
2. **Anti-DPI** — Mux toggle + CDN-фронтинг toggle + uTLS fingerprint picker + STUN-block toggle
3. **Безопасность** — cert pinning toggle
4. **Rules** — force update button + MinAppVersionBanner (Phase 8)
5. **macOS only** — enforceRoutes toggle (скрыт на iOS через `#if os(macOS)`)

## Toggle inventory

### DNS секция

| Toggle | UserDefaults key | Default | Suite |
|--------|-----------------|---------|-------|
| Custom DNS field | `app.bbtb.customDNS` | `""` | `.standard` |
| AdBlock | `app.bbtb.adBlockEnabled` | `false` | `.standard` |

### Anti-DPI секция

| Toggle | UserDefaults key | Default | Suite | Phase |
|--------|-----------------|---------|-------|-------|
| Mux (DPI-05) | `app.bbtb.muxEnabled` | `false` | App Group `group.app.bbtb.shared` | 10 |
| CDN-фронтинг (DPI-06) | `app.bbtb.cdnFrontingEnabled` | `false` | `.standard` | 10 |
| uTLS fingerprint picker (DPI-09) | `app.bbtb.utlsFingerprint` | `"random"` | App Group `group.app.bbtb.shared` | 10 |
| STUN-block (BIO-04) | `app.bbtb.stunBlockEnabled` | `false` | App Group `group.app.bbtb.shared` | 10 |

### Безопасность секция

| Toggle | UserDefaults key | Default | Suite | Phase |
|--------|-----------------|---------|-------|-------|
| Cert pinning (DPI-08) | `app.bbtb.certPinningEnabled` | `true` | `.standard` | 10 |

### Phase 6 и Phase 8 toggles (уже существовавшие)

| Toggle | UserDefaults key | Default | Phase |
|--------|-----------------|---------|-------|
| Kill switch | `NEVPNProtocol.includeAllNetworks` | `false` | 1 |
| Auto-reconnect | `app.bbtb.autoReconnect` | `true` | 6c |

## macOS-only гейты (#if os(macOS))

**D-17 решение**: `enforceRoutes` toggle присутствует только на macOS. На iOS toggle скрыт — он не нужен (iOS сетевой стек не позволяет bypass VPN маршрута так же, как macOS). Реализация:

```swift
#if os(macOS)
EnforceRoutesSection()
#endif
```

UserDefaults key: `app.bbtb.enforceRoutes` в App Group `group.app.bbtb.shared`. Default: `true` (enforceRoutes включён по умолчанию — safe default, D-17).

## Destructive flows

### STUN-block OFF→ON confirm (D-16)

При переключении «Блокировать STUN-трафик» из OFF → ON показывается `.alert`:

```
«Блокировка STUN-трафика нарушит звонки в браузерных мессенджерах
(Google Meet, Zoom web). Продолжить?»
```

Действия: «Включить» (destructive) / «Отменить». Переключение применяется только при подтверждении.

## Persistence и App Group

Ряд toggles хранится в **App Group UserDefaults** (`group.app.bbtb.shared`), потому что их значения нужны туннельному extension (Mux, STUN-block, uTLS picker, enforceRoutes). Остальные — в `.standard` UserDefaults (только main app читает: CDN-фронтинг, cert pinning).

При использовании `@AppStorage` с App Group suite: `@AppStorage("key", store: UserDefaults(suiteName: "group.app.bbtb.shared"))`.

## L10n ключи (19 новых в Phase 10)

Ключи добавлены в `Localization/Sources/Localization/L10n.swift` и `ru.lproj/Localizable.strings` + `en.lproj/Localizable.strings`:

| Ключ | Описание |
|------|----------|
| `settings.advanced.mux.title` | «Mux мультиплексирование» |
| `settings.advanced.mux.footer` | Объяснение для чего нужен |
| `settings.advanced.cdn.title` | «CDN-фронтинг» |
| `settings.advanced.cdn.footer` | Cloudflare/Fastly объяснение |
| `settings.advanced.utls.title` | «uTLS fingerprint» |
| `settings.advanced.stun.title` | «Блокировать STUN-трафик» |
| `settings.advanced.stun.footer` | WebRTC leak protection объяснение |
| `settings.advanced.stun.confirm.title` | Заголовок .alert |
| `settings.advanced.stun.confirm.message` | Текст .alert |
| `settings.advanced.stun.confirm.enable` | «Включить» (destructive) |
| `settings.advanced.certPinning.title` | «Cert pinning» |
| `settings.advanced.certPinning.footer` | MITM protection объяснение |
| `settings.advanced.enforceRoutes.title` | «Принудительная маршрутизация» |
| `settings.advanced.enforceRoutes.footer` | macOS-only объяснение |
| ... (остальные 5) | DNS + AdBlock обновления |

## Related pages

- [[anti-dpi-techniques]]
- [[cdn-fronting-architecture-2026]]
- [[cert-pinning-spki]]
- [[rules-engine]]
- [[security-gaps]]
