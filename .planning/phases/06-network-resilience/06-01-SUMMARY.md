---
phase: 06-network-resilience
plan: 01
subsystem: dns-foundation-vertical-slice
wave: 1
tags: [dns, dnsconfig, poolbuilder, vpncore, configparser, packettunnelkit, tdd, wave1, D-01, D-02, D-03, D-04]
status: complete
date: 2026-05-13
requirements: [NET-01, NET-02, NET-03, NET-04]
dependency_graph:
  requires:
    - Phase 5 Wave 7 (05-08-SUMMARY.md) — PoolBuilder coordinator pattern;
      `import VPNCore` already declared in ConfigParser Package.swift.
    - Phase 5 Wave 0 (05-01-SUMMARY.md) — TransportConfig analog для DNSConfig
      (same Sendable+Equatable+Codable+Hashable shape; synthesized Codable for
      enum with associated values).
  provides:
    - "VPNCore.DNSConfig — value-type для DNS-стратегии (bootstrap address +
       TunnelDNSProvider enum). Default = Cloudflare bootstrap + Cloudflare DoH.
       Используется PoolBuilder и (в Wave 5) ConfigImporter."
    - "VPNCore.DNSConfig.TunnelDNSProvider — enum с case-ами `.cloudflare`,
       `.adguard`, `.custom(address:)`. dohAddress() возвращает каноничный DoH URL."
    - "PoolBuilder.buildSingBoxJSON(from:dns:) + buildSingleOutboundJSON(from:dns:)
       — overload с default `DNSConfig.default` сохраняет backward-compat для
       всех Phase 1-5 callers."
    - "PoolBuilder.dnsBlock(detour:dns:) — приватный helper, читает
       `dns.bootstrapAddress` для `dns-bootstrap.address` и `dns.dohAddress()`
       для `dns-remote.address`. Yandex hardcode `tcp://77.88.8.8` удалён
       (D-01 violation closed)."
    - "BaseSingBoxTunnel.swift — doc-comment, фиксирующий контракт: DNSConfig
       проходит через configJSON (single source of truth), а не через отдельный
       providerConfiguration ключ."
  affects:
    - Wave 2 (TUN inbound IPv6 blackhole) — не зависит от DNS, но Wave 3 будет
      потреблять DNSConfig в SettingsViewModel.
    - Wave 3 (Settings UI + DNSConfig persistence) — будет читать
      `app.bbtb.customDNS`, `app.bbtb.adBlockEnabled` из AppStorage и собирать
      DNSConfig через computed property.
    - Wave 5 (ConfigImporter buildDNSConfig + provision integration) — будет
      собирать DNSConfig из SettingsViewModel + serverConfig.host (D-01: server IP
      first для bootstrap), и передавать в `PoolBuilder.buildSingBoxJSON(dns:)`.

tech_stack:
  added:
    - "VPNCore.DNSConfig — value-type, единственный зависимость: Foundation."
  patterns:
    - "DNSConfig ← TransportConfig analog. Single source of truth для DoH URL'ов
       (cloudflare-dns.com, dns.adguard-dns.com) + формата bootstrap address
       (sing-box принимает `tcp://`, `udp://`, `https://`, `tls://` префиксы)."
    - "Default parameter в PoolBuilder API сохраняет backward-compat: 13
       существующих PoolBuilder*Tests не редактировались, продолжают работать
       с `DNSConfig.default`."
    - "DNSConfig — dumb value carrier без валидации. Валидация IPv4/RFC1123
       hostname для `.custom` — в SettingsViewModel.validateCustomDNS и
       ConfigImporter.buildDNSConfig (Wave 3 / Wave 5). Это позволяет DNSConfig
       пересекать actor-границы (Sendable) без блокирующих side-effects."
    - "TDD RED-GREEN: тесты `DNSConfigTests.swift` написаны ДО `DNSConfig.swift`,
       аналогично тесты `PoolBuilderDNSConfigTests.swift` ДО правки PoolBuilder.swift."

key_files:
  created:
    - BBTB/Packages/VPNCore/Sources/VPNCore/DNSConfig.swift (73 lines)
    - BBTB/Packages/VPNCore/Tests/VPNCoreTests/DNSConfigTests.swift (123 lines)
    - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderDNSConfigTests.swift (171 lines)
  modified:
    - BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift (+28 lines: dns: parameter, dnsBlock takes DNSConfig, Yandex hardcode removed)
    - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift (+11 lines: Phase 6 hygiene comment block)

decisions:
  - "D-01 (Bootstrap DNS) realized: `dns.bootstrapAddress` принимает sing-box
     адрес (`tcp://<ip>` или `https://<host>/dns-query`). DNSConfig.default
     использует Cloudflare `tcp://1.1.1.1` — это safe fallback; ConfigImporter
     (Wave 5) переопределит на server IP per D-01 trinity."
  - "D-02..D-04 (Tunnel DNS) realized через TunnelDNSProvider enum: `.cloudflare`
     (default), `.adguard` (AdBlock), `.custom(address:)` (user override).
     Priority resolution не в DNSConfig — DNSConfig получает уже решённый
     case-выбор. Это позволяет SettingsViewModel изменить логику приоритета
     в будущем без правки value-type."
  - "Backward-compat через default параметр `dns: DNSConfig = .default` —
     явное решение НЕ ломать 13+ существующих тестов PoolBuilder. Это canon-
     ный pattern из Phase 5 (TransportConfig тоже добавлен без breaking change'ей)."
  - "BaseSingBoxTunnel НЕ читает DNSConfig напрямую — DNSConfig пеките в JSON
     через PoolBuilder (Wave 5). Single source of truth = configJSON.
     Альтернатива (отдельный providerConfiguration['dnsConfig'] ключ)
     отвергнута: дублирование state + риск рассинхрона между JSON и Swift-side
     представлением."

invariants_preserved:
  - "R1: experimental={} остаётся пустым; никаких clash_api / v2ray_api / cache_file
     в generated JSON. Verified by test_R10_invariants_preserved."
  - "R10: dns.strategy=ipv4_only, dns.final=dns-remote, dns.independent_cache=true,
     fakeip block с inet4_range=100.64.0.0/10 и inet6_range=fc00::/18 — без
     изменений. Verified test_R10_invariants_preserved."
  - "R1 self-test: post-build JSON всё ещё проходит SingBoxConfigLoader.validate
     для всех 4-х DNSConfig вариантов. Verified test_customDNSConfig_passesSingBoxValidate."

tests_added:
  vpncore:
    - test_default_usesCloudflareTunnelAndCloudflareBootstrap
    - test_init_cloudflareProvider_returnsCloudflareDoH
    - test_adGuardProvider_returnsAdGuardDoH
    - test_customProvider_passesThroughAddress
    - test_codable_roundtrip_allProviderVariants
    - test_equatable_identicalFieldsAreEqual
    - test_equatable_differentBootstrap_notEqual
    - test_equatable_differentProvider_notEqual
    - test_equatable_customAssociatedValueMatters
    - test_sendable_crossesActorBoundary
    - test_hashable_setMembership_distinguishesProviders
    - test_default_doesNotReferenceYandexBootstrap
  configparser:
    - test_defaultDNSConfig_emitsCloudflareBootstrapAndDoH
    - test_explicitBootstrapAddress_threadedIntoJSON
    - test_adguardProvider_emitsAdGuardDoH
    - test_customProvider_emitsUserAddress
    - test_invariant_no_yandex_in_generated_json
    - test_R10_invariants_preserved
    - test_backwardCompat_noDNSArg_passesSingBoxValidate
    - test_backwardCompat_singleOutbound_noDNSArg
    - test_singleOutbound_threadsDNSConfig
    - test_customDNSConfig_passesSingBoxValidate

test_counts:
  new_tests: 22
  new_dnsconfig_tests: 12
  new_poolbuilder_dns_tests: 10
  total_vpncore: 57
  total_configparser: 210
  total_packettunnelkit: 44
  grand_total: 311
  failures: 0

yandex_eradication:
  command: 'grep -RIn "77.88.8.8" BBTB/Packages/ConfigParser/Sources/ BBTB/Packages/VPNCore/Sources/'
  result: 0
  status: PASS

verification:
  vpncore:
    command: "swift test --package-path BBTB/Packages/VPNCore"
    result: "57 tests, 0 failures (1 skipped, pre-existing)"
  configparser:
    command: "swift test --package-path BBTB/Packages/ConfigParser"
    result: "210 tests, 0 failures"
  packettunnelkit:
    command: "swift test --package-path BBTB/Packages/PacketTunnelKit"
    result: "44 tests, 0 failures"

references:
  context: .planning/phases/06-network-resilience/06-CONTEXT.md (D-01..D-04)
  research: .planning/phases/06-network-resilience/06-RESEARCH.md (§7 sing-box DNS schema, §8 PoolBuilder rewrite)
  patterns: .planning/phases/06-network-resilience/06-PATTERNS.md (DNSConfig ← TransportConfig analog)
  plan: .planning/phases/06-network-resilience/06-01-PLAN.md

deviations: []
---

## Wave 1 Summary

Wave 1 ставит фундамент DNS-стратегии Phase 6 — введён `DNSConfig` value-type
в `VPNCore`, `PoolBuilder.dnsBlock` переписан под него, и хардкод
`tcp://77.88.8.8` (Yandex) удалён согласно D-01.

### What changed

1. **VPNCore/DNSConfig.swift** (new, 73 lines) — Sendable+Equatable+Codable+Hashable
   value-type:
   ```swift
   public struct DNSConfig: Sendable, Equatable, Codable, Hashable {
       public let bootstrapAddress: String
       public let tunnelDNS: TunnelDNSProvider
       public enum TunnelDNSProvider: Sendable, Equatable, Codable, Hashable {
           case cloudflare
           case adguard
           case custom(address: String)
       }
       public static let `default` = DNSConfig(bootstrapAddress: "tcp://1.1.1.1",
                                                tunnelDNS: .cloudflare)
       public func dohAddress() -> String { ... }
   }
   ```

2. **ConfigParser/PoolBuilder.swift** (modified) —
   - `buildSingBoxJSON(from:dns:)` принимает `DNSConfig = .default` (backward compat).
   - `buildSingleOutboundJSON(from:dns:)` аналогично.
   - `dnsBlock(detour:dns:)` читает `dns.bootstrapAddress` для `dns-bootstrap.address`
     и `dns.dohAddress()` для `dns-remote.address`.
   - Удалён hardcoded `"address": "tcp://77.88.8.8"`.

3. **PacketTunnelKit/BaseSingBoxTunnel.swift** (modified, +11 lines) — hygiene
   doc-comment, фиксирующий single-source-of-truth контракт: DNSConfig peched в
   configJSON через PoolBuilder, а не передаётся отдельным
   `providerConfiguration["dnsConfig"]` ключом. Это lock-down для Wave 5.

### Test counts

| Package | Tests | New | Failures |
|---------|-------|-----|----------|
| VPNCore | 57 | +12 (DNSConfigTests) | 0 |
| ConfigParser | 210 | +10 (PoolBuilderDNSConfigTests) | 0 |
| PacketTunnelKit | 44 | 0 | 0 |
| **Total** | **311** | **+22** | **0** |

### Yandex eradication

```bash
$ grep -RIn "77.88.8.8" BBTB/Packages/ConfigParser/Sources/ BBTB/Packages/VPNCore/Sources/
$ echo $?
0   # exit code 0 + zero matches = clean
```

### What did NOT change (locks)

- `SingBoxConfigLoader.expandConfigForTunnel` — Wave 2 будет править его
  для IPv6 blackhole `inet6_address`.
- `SettingsViewModel` — Wave 3 добавит `@AppStorage` ключи.
- `ConfigImporter` — Wave 5 добавит `buildDNSConfig(for:)`.
- `App/PacketTunnelExtension-{iOS,macOS}/PacketTunnelProvider.swift` shells —
  остаются 14-16-строчными пустыми shell'ами (R10 architecture invariant).

### Next wave

Wave 2 — IPv6 blackhole in TunnelSettings + SingBoxConfigLoader.expandConfigForTunnel
(`inet6_address` injection per D-06). DNS Foundation готов для интеграции в Wave 5.

### Deviations from plan

Нет. Все 3 task'а Wave 1 выполнены ровно по PLAN.md. Тесты RED-GREEN порядок
соблюдён (тесты добавлены до production кода). Acceptance criteria всех 3
task'ов выполнены (12 DNSConfigTests, 10 PoolBuilderDNSConfigTests, +2 "Phase 6"
comment-references in BaseSingBoxTunnel.swift).
