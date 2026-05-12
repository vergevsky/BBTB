# Plan 06-03 — Wave 3 SUMMARY

**Phase:** 06-network-resilience
**Plan:** 03 — Settings UI for DNS configuration
**Wave:** 3
**Date completed:** 2026-05-13
**Status:** ✅ COMPLETE

---

## Goal recap

Vertical UI slice exposing the two new global DNS-strategy settings (`customDNS`, `adBlockEnabled`) and a computed `dnsConfig: DNSConfig` resolving D-01..D-04 priority. The bridge for Wave 5 (TunnelController) and Wave 6 (failover).

Requirements covered: **NET-02** (Custom DNS UI) + **NET-03** (AdBlock toggle UI); foundation for **NET-01** priority resolution.

---

## Files created / modified

| Path | Δ lines | Role |
|------|---------|------|
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` | 9 → 132 | Added `customDNS` + `adBlockEnabled` `@AppStorage`, `dnsConfig` computed property + IPv4/RFC 1123 hostname validators. |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift` | new (38) | Form-based Advanced screen with DNS section. |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdBlockToggleSection.swift` | new (19) | Reusable toggle row mirroring `KillSwitchToggleSection`. |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/CustomDNSField.swift` | new (111) | Text field row with inline IPv4/hostname validation (red invalid hint). |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift` | 30 → 37 | Added `NavigationLink` → `AdvancedSettingsView`. |
| `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelDNSTests.swift` | new (158) | 16 unit tests — defaults, priority, persistence, validation. |
| `BBTB/Packages/AppFeatures/Package.swift` | +5 | Registered new `SettingsFeatureTests` test target. |
| `BBTB/Packages/Localization/Sources/Localization/L10n.swift` | +9 | Added 9 new public static keys. |
| `BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings` | +54 | Added ru/en localizations for 9 keys. |

---

## Tests

**Target:** `SettingsFeatureTests` (new, registered in Package.swift).
**Total:** 16 / 16 passing.

| Test | Covers |
|------|--------|
| `test_SettingsViewModel_defaults_customDNS_empty` | Default state |
| `test_SettingsViewModel_defaults_adBlockEnabled_false` | Default state |
| `test_SettingsViewModel_dnsConfig_returns_cloudflare_when_defaults` | D-02 Cloudflare default |
| `test_SettingsViewModel_dnsConfig_returns_adGuard_when_adBlockEnabled` | D-04 AdGuard branch |
| `test_SettingsViewModel_dnsConfig_returns_custom_when_customDNS_set` | D-03 IPv4 → `tcp://` |
| `test_SettingsViewModel_dnsConfig_customDNS_wins_over_adBlock` | Priority D-03 > D-04 |
| `test_SettingsViewModel_dnsConfig_customDNS_hostname_becomes_doh` | hostname → `https://.../dns-query` |
| `test_SettingsViewModel_dnsConfig_customDNS_whitespace_trimmed` | Whitespace handling |
| `test_SettingsViewModel_dnsConfig_invalid_customDNS_falls_back_to_cloudflare` | Pitfall 9 defense |
| `test_SettingsViewModel_dnsConfig_invalid_customDNS_falls_back_to_adGuard_if_adBlock` | Pitfall 9 + D-04 fallback |
| `test_SettingsViewModel_dnsConfig_rejects_out_of_range_octet` | IPv4 octet > 255 |
| `test_SettingsViewModel_dnsConfig_rejects_single_label_hostname` | `localhost` rejected |
| `test_SettingsViewModel_customDNS_persisted_via_AppStorage` | UserDefaults round-trip |
| `test_SettingsViewModel_adBlockEnabled_persisted_via_AppStorage` | UserDefaults round-trip |
| `test_SettingsViewModel_killSwitchEnabled_still_works` | Regression guard |
| `test_SettingsViewModel_dnsConfig_usable_in_Task_closure` | Sendable across actor boundary |

**Regression:** full AppFeatures suite — **70 / 70 pass**.
**VPNCore suite:** **57 / 57 pass** (1 pre-existing skip).

---

## L10n keys added (9)

| Key | RU | EN |
|-----|----|----|
| `settings.advanced.title` | Расширенные | Advanced |
| `settings.advanced.entry.label` | Расширенные | Advanced |
| `settings.dns.section` | DNS | DNS |
| `settings.dns.adblock.label` | Блокировать рекламу | Block ads |
| `settings.dns.adblock.footer` | Использовать AdGuard DNS вместо Cloudflare | Use AdGuard DNS instead of Cloudflare |
| `settings.dns.custom.label` | Свой DNS-сервер | Custom DNS server |
| `settings.dns.custom.placeholder` | IP-адрес или DoH-хост | IP address or DoH host |
| `settings.dns.custom.footer` | Приоритет: свой DNS > AdBlock > по умолчанию | Priority: custom DNS > AdBlock > default |
| `settings.dns.custom.invalid` | Неверный формат: введите IPv4 или имя хоста | Invalid format: enter IPv4 or hostname |

---

## Navigation flow

`MainScreenView` → … (existing) → `SettingsView`
                                  ├── Section «Безопасность» — Kill Switch toggle (existing)
                                  └── Section (new) — `NavigationLink` «Расширенные» → **`AdvancedSettingsView`**
                                                                                       └── Section «DNS»
                                                                                           ├── `AdBlockToggleSection` (bound to `viewModel.adBlockEnabled`)
                                                                                           └── `CustomDNSField` (bound to `viewModel.customDNS`)

Both bindings use the **same** `SettingsViewModel` instance — no separate VM for Advanced.

---

## Validation strategy (Pitfall 9 — defense in depth)

Two independent layers reject garbage `customDNS` input:

1. **`SettingsViewModel.dnsConfig`** — invalid input → tunnelDNS resolves as if `customDNS` were empty (falls through to AdBlock / Cloudflare). Garbage NEVER reaches sing-box JSON via `.custom(address:)`.
2. **`CustomDNSField`** — inline red error message (`settings.dns.custom.invalid`) when text is non-empty and fails validation; reactive via `onChange`.

Validation rules (both layers, intentionally duplicated to keep `CustomDNSField` standalone):
- If string *looks like* IPv4 (all dot-separated labels are pure digits, ≥ 2 parts) → must be valid IPv4 (4 octets, each 0...255). Don't fall through to hostname (so `1.2.3.999` is rejected, not treated as hostname).
- Else: RFC 1123 hostname subset — non-empty, ≤ 253 chars, ≥ 2 labels (single-label `localhost` rejected), labels 1...63 chars of ASCII letters/digits/hyphens, no leading/trailing hyphen.

---

## Verification artifacts

- ✅ `swift build --package-path BBTB/Packages/AppFeatures` — clean.
- ✅ `swift build --package-path BBTB/Packages/Localization` — clean.
- ✅ `grep -c "app.bbtb.customDNS" SettingsViewModel.swift` = 1.
- ✅ `grep -c "app.bbtb.adBlockEnabled" SettingsViewModel.swift` = 1.
- ✅ `grep -c "var dnsConfig" SettingsViewModel.swift` = 1.
- ✅ `grep -c "AdvancedSettingsView" SettingsView.swift` = 2 (NavigationLink destination + import-via-target).
- ✅ `grep -c "NavigationLink" SettingsView.swift` = 1.
- ✅ `grep -c -E "settings\.dns\.adblock\.label|…(9 keys)" L10n.swift` = 9.
- ✅ Inline `Text("...")` literals in AdvancedSettingsView = 0 (every label via `L10n.*`).

---

## References

- **Decisions:** D-02 (Cloudflare default), D-03 (Custom DNS), D-04 (AdBlock toggle), D-05 (global scope via `@AppStorage`) in `.planning/phases/06-network-resilience/06-CONTEXT.md`.
- **Validation logic:** `06-RESEARCH.md` §8 (buildDNSConfig format rules).
- **UI pattern:** `06-PATTERNS.md` «AdvancedSettingsView.swift» (mirror SettingsView + KillSwitchToggleSection).
- **Wiki:** value-type DNSConfig from Wave 1, see `06-01-SUMMARY.md`.

---

## Deferred to later waves

- **Wave 4** — Settings → Advanced reconnect banner (UserDefaults observer detects DNS-setting change while `.connected`, surfaces `ReconnectBanner` with `banner.reconnecting` text). Not in scope for Wave 3.
- **Wave 5** — `ConfigImporter.buildDNSConfig` wires `viewModel.dnsConfig` into sing-box JSON via `PoolBuilder.dnsBlock(dnsConfig:)`. Repeats the same IPv4/hostname validation as a third defense layer.
- **Visual UAT** — Wave 6 / device test (does the field render correctly on iPhone, Mac, with Dynamic Type, etc.).
