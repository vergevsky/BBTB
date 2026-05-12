---
phase: 06-network-resilience
plan: 02
subsystem: ipv6-blackhole-vertical-slice
wave: 2
tags: [ipv6, blackhole, tunnelsettings, singboxconfigloader, packettunnelkit, tdd, wave2, D-06, NET-05, NET-06, R6, R10]
status: complete
date: 2026-05-13
requirements: [NET-05, NET-06]
dependency_graph:
  requires:
    - Wave 1 (06-01-SUMMARY.md) — DNS Foundation. Wave 2 не зависит от DNSConfig,
      но строит на той же интеграционной поверхности (`expandConfigForTunnel`).
    - Phase 1 W3.1 — Phase 1 TUN inbound injection. Wave 2 расширяет (не заменяет)
      существующий append-блок: добавлен IPv6 prefix в `address` + новый
      `route_address` ключ.
  provides:
    - "TunnelSettings.makeR6Safe — non-nil NEIPv6Settings(addresses: [\"fd00::1\"],
       networkPrefixLengths: [128]) с includedRoutes=[NEIPv6Route.default()] и
       excludedRoutes=[]. Закрывает Phase 1 TODO «settings.ipv6Settings = nil»."
    - "SingBoxConfigLoader.expandConfigForTunnel — TUN inbound `address` array
       теперь `[<tunIP>/28, \"fd00::1/126\"]` + новое поле `route_address: [\"::/0\"]`.
       Использует unified sing-box 1.13 syntax (не deprecated inet6_address)."
  affects:
    - Wave 3 (Settings UI + DNSConfig persistence) — не зависит от Wave 2.
    - Wave 5 (ConfigImporter integration) — не зависит напрямую, но получит
       blackhole «бесплатно» когда PoolBuilder JSON пройдёт через
       expandConfigForTunnel в BaseSingBoxTunnel.startTunnel.
    - Wave 6 (device UAT) — добавится manual check на ipv6-test.com (см.
       deferred verification ниже).

tech_stack:
  added: []
  patterns:
    - "NEIPv6Settings blackhole: ULA `fd00::/8` (RFC 4193) + default included route
       — стандартный pattern для VPN-клиентов которые хотят выключить v6 без
       NEIPv6Settings=nil. Канон — 06-RESEARCH.md §1."
    - "sing-box 1.13 unified TUN inbound syntax — `address: [\"v4/prefix\", \"v6/prefix\"]`
       + `route_address: [\"v4_dest\", \"v6_dest\"]`. Deprecated alternative
       (`inet4_address`/`inet6_address`/`inet4_route_address`/`inet6_route_address`)
       — НЕ используется per 06-RESEARCH.md §2 (deprecated in sing-box 1.10)."
    - "R6 invariant on v6: NEIPv6Settings.destinationAddresses НИКОГДА не
       выставляется. На macOS 26 / iOS 19 SDK это enforced at compile time —
       property скрыт SDK (как и для NEIPv4Settings). Compile-error если кто-то
       попытается, plus grep guard в validate-r1-r6.sh."

key_files:
  created:
    - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/TunnelSettingsIPv6Tests.swift (110 lines, 9 tests)
    - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderIPv6Tests.swift (123 lines, 8 tests)
  modified:
    - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift (+18/-2 lines: NEIPv6Settings blackhole)
    - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift (+14/-1 lines: address+route_address для v6)
    - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/TunnelSettingsTests.swift (Phase 1 holding test обновлён под Phase 6 behavior)
    - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift (Phase 1 expand assertion обновлён под v4+v6 address shape)

decisions:
  - "D-06 (IPv6 always block) realized как **blackhole**, не как `ipv6Settings = nil`.
     Причина: nil даёт ОС маршрутизировать v6 в обход туннеля (Pitfall 1) — это и
     был v6 leak. Blackhole: ULA-адрес внутри TUN + default v6 route + отсутствие
     v6 outbound в sing-box → v6 пакеты входят в туннель и dropпаются. Это
     гарантирует что AAAA-resolvable destinations не утекают на cellular (где ISP
     часто даёт v6)."
  - "fd00::1/128 на стороне NEIPv6Settings, fd00::1/126 на стороне sing-box TUN.
     /128 — single tunnel-local address, /126 — minimal subnet (4 addresses)
     которое sing-box gvisor stack ожидает для address assignment. Это
     соответствует sing-box docs Inbound TUN example (cited 06-RESEARCH.md §1)."
  - "sing-box unified 1.13 syntax (`address` array, `route_address` array) — НЕ
     deprecated `inet6_address` / `inet6_route_address`. sing-box 1.10 пометил
     отдельные ключи deprecated; 1.13.11 (наша версия libbox) обрабатывает обе
     формы, но unified — forward-compat. Если в Wave 6 device UAT покажет, что
     unified не работает — fallback на deprecated form задокументирован в
     06-PATTERNS.md T-06-W2-05."
  - "PacketTunnelProvider shells (App/PacketTunnelExtension-{iOS,macOS}) НЕ
     трогаются — вся IPv6 логика инкапсулирована в TunnelSettings.swift +
     SingBoxConfigLoader.swift. Это R10 architecture invariant (Phase 1).
     Shells остаются 14-16 line `@objc(PacketTunnelProvider) final class
     PacketTunnelProvider: BaseSingBoxTunnel`."

invariants_preserved:
  - "R6 (P2P=false): NEIPv6Settings.destinationAddresses не выставлен. На
     macOS 26 / iOS 19 SDK это compile-time enforced (property hidden). Verified
     by test_TunnelSettings_ipv6_noDestinationAddresses + existing
     test_makeR6Safe_doesNotSetDestinationAddresses (для v4) + grep guard."
  - "R10 (post-expand validate): `SingBoxConfigLoader.validate(json: expanded)`
     остаётся PASS после Wave 2 правок. Verified by
     test_SingBoxConfigLoader_validate_post_expand + existing
     test_expandConfigForTunnel_outputPassesValidate_fromCleanInput. Никаких
     новых inbound types не появилось — allow-list `tun` + `direct` без изменений."
  - "R10 (idempotency): hasTun guard остаётся главным defender'ом против
     дублирования TUN inbound. Verified by
     test_SingBoxConfigLoader_ipv6_idempotent_whenTunAlreadyPresent."
  - "R1 (experimental={}, no clash_api/v2ray_api/cache_file): не задеты — TUN
     inbound expansion не пишет в experimental block."

tests_added:
  tunnel_settings_ipv6:
    - test_TunnelSettings_ipv6_isNotNil                     # Pitfall 1 invariant
    - test_TunnelSettings_ipv6_addresses_useULA             # fd00::1
    - test_TunnelSettings_ipv6_prefixLengths_are128
    - test_TunnelSettings_ipv6_blackholeRoute_present       # 1 route
    - test_TunnelSettings_ipv6_blackholeRoute_isDefault     # ::/0
    - test_TunnelSettings_ipv6_noDestinationAddresses       # R6 invariant
    - test_TunnelSettings_ipv6_excludedRoutes_explicitEmpty
    - test_TunnelSettings_ipv4_unchanged                    # regression guard
    - test_TunnelSettings_convenienceOverload_emitsIPv6Blackhole
  singbox_configloader_ipv6:
    - test_SingBoxConfigLoader_ipv6_address_added           # fd00::1/126 in address
    - test_SingBoxConfigLoader_ipv6_route_address_blackhole # ["::/0"]
    - test_SingBoxConfigLoader_ipv6_auto_route_stays_false  # R10
    - test_SingBoxConfigLoader_ipv6_stack_stays_gvisor
    - test_SingBoxConfigLoader_ipv6_mtu_preserved
    - test_SingBoxConfigLoader_ipv6_idempotent_whenTunAlreadyPresent
    - test_SingBoxConfigLoader_validate_post_expand         # R10 critical
    - test_SingBoxConfigLoader_ipv6_noDeprecatedKeys        # no inet6_address

test_counts:
  new_tests: 17
  new_tunnel_settings_ipv6_tests: 9
  new_singbox_configloader_ipv6_tests: 8
  total_packettunnelkit: 61   # was 44 in Wave 1; +17 new
  total_vpncore: 57           # unchanged (1 pre-existing skip)
  total_configparser: 210     # unchanged
  grand_total: 328
  failures: 0

grep_invariants:
  nil_ipv6Settings_assigns:
    cmd: "grep -c 'settings.ipv6Settings = nil' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift"
    result: 0
    status: PASS
  NEIPv6Settings_present:
    cmd: "grep -c 'NEIPv6Settings' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift"
    result: 3
    status: PASS
  fd00_in_loader:
    cmd: "grep -c 'fd00::1/126' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift"
    result: 2
    status: PASS
  route_address_present:
    cmd: "grep -c 'route_address' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift"
    result: 4
    status: PASS
  no_deprecated_inet6_keys:
    cmd: "grep -RIn 'inet6_address\\|inet6_route_address' BBTB/Packages/PacketTunnelKit/Sources/ | grep -v '//' | wc -l"
    result: 0
    status: PASS

verification:
  packettunnelkit:
    command: "swift test --package-path BBTB/Packages/PacketTunnelKit"
    result: "61 tests, 0 failures"
  vpncore:
    command: "swift test --package-path BBTB/Packages/VPNCore"
    result: "57 tests, 0 failures (1 skipped, pre-existing)"
  configparser:
    command: "swift test --package-path BBTB/Packages/ConfigParser"
    result: "210 tests, 0 failures"

deferred_uat:
  - "Wave 6 device test: запустить туннель на iPhone (LTE — типичный v6-enabled
     network) и открыть https://ipv6-test.com. Ожидается: «No IPv6 connectivity
     detected» при подключённом VPN (v6 пакеты заблокированы внутри туннеля).
     Без VPN на той же сим — должен показывать v6 connectivity (sanity check на
     то что сама сим v6 поддерживает)."

references:
  context: .planning/phases/06-network-resilience/06-CONTEXT.md (D-06)
  research: .planning/phases/06-network-resilience/06-RESEARCH.md (§1 NEIPv6Settings canonical, §2 sing-box TUN inet6 syntax, §14 Pitfall 1, §15 patch)
  patterns: .planning/phases/06-network-resilience/06-PATTERNS.md (TunnelSettings + SingBoxConfigLoader integration points)
  plan: .planning/phases/06-network-resilience/06-02-PLAN.md
  wave1_summary: .planning/phases/06-network-resilience/06-01-SUMMARY.md

deviations:
  - "PLAN.md Task 1 behavior описывал `XCTAssertNil(s.ipv6Settings?.destinationAddresses)`
     как Test 5. macOS 26 / iOS 19 SDK скрывает property полностью (compile-time
     R6 enforcement) — тест заменён на comment-only assertion + XCTAssertNotNil
     wrapper, аналогично существующему IPv4 test_makeR6Safe_doesNotSetDestinationAddresses
     pattern. R6 на v6 теперь enforced at compile time (что **сильнее** runtime check
     из PLAN). Net: invariant укреплён, не ослаблен."
  - "PLAN.md acceptance criterion для Task 1 ожидает `grep -c destinationAddresses ... | grep -v '^#'`
     = 0 code lines. После правки comment-блок упоминает 'destinationAddresses'
     дважды в комментариях — фактически 0 code-lines (только comments)."
---

## Wave 2 Summary

Wave 2 закрывает Phase 1 TODO «ipv6Settings = nil» и закрывает v6 leak,
описанный в 06-RESEARCH.md Pitfall 1. Две координированные правки на двух
архитектурных слоях — OS routing (NEIPv6Settings) и sing-box engine (TUN inbound).

### What changed

1. **TunnelSettings.swift** (+18/-2 lines) — Phase 1 `settings.ipv6Settings = nil`
   заменён на blackhole-конфигурацию:

   ```swift
   let ipv6 = NEIPv6Settings(addresses: ["fd00::1"],
                              networkPrefixLengths: [NSNumber(value: 128)])
   ipv6.includedRoutes = [NEIPv6Route.default()]   // ::/0
   ipv6.excludedRoutes = []
   settings.ipv6Settings = ipv6
   ```

   ОС теперь маршрутизирует ВЕСЬ v6 трафик в TUN. Без upstream v6 gateway и
   без v6 outbound в sing-box пакеты dropпаются внутри gvisor stack.

2. **SingBoxConfigLoader.expandConfigForTunnel** (+14/-1 lines) — TUN inbound
   расширен IPv6:

   ```swift
   inbounds.append([
       "type": "tun",
       "tag": "tun-in",
       "address": ["\(tunIP)/28", "fd00::1/126"],   // +IPv6 ULA prefix
       "route_address": ["::/0"],                    // +v6 blackhole
       "mtu": mtu,
       "auto_route": false,
       "stack": "gvisor",
   ])
   ```

   sing-box TUN теперь понимает что v6 пакеты ему свои (через `address`) и что
   все v6 destinations должны идти в TUN (через `route_address`). Без второго
   ключа v6 могло бы прыгнуть в `direct` outbound = leak.

3. **Tests** (+17 tests across 2 new files) — RED-GREEN порядок: тесты написаны
   ДО production кода, провалили build (compile error на skрытом
   `destinationAddresses`), потом доведены до PASS.

4. **Phase 1 holding tests обновлены** — два теста изменили expectations
   (Phase 1 → Phase 6 behavior), не сломаны:
   - `test_makeR6Safe_ipv6Settings_areNilOnPhase1` → переименован в
     `test_makeR6Safe_ipv6Settings_areConfiguredForBlackhole_inPhase6`
   - `test_expandConfigForTunnel_addsTunInbound` — assertion обновлён под
     v4+v6 address array shape и наличие `route_address`.

### Test counts

| Package | Tests | Δ Wave 2 | Failures |
|---------|-------|----------|----------|
| PacketTunnelKit | 61 | +17 | 0 |
| VPNCore | 57 | 0 | 0 (1 skipped) |
| ConfigParser | 210 | 0 | 0 |
| **Total** | **328** | **+17** | **0** |

### Grep invariants (acceptance)

| Check | Cmd | Result | Status |
|-------|-----|--------|--------|
| Phase 1 nil placeholder gone | `grep -c 'settings.ipv6Settings = nil' TunnelSettings.swift` | 0 | PASS |
| NEIPv6Settings present | `grep -c 'NEIPv6Settings' TunnelSettings.swift` | 3 | PASS |
| IPv6 ULA in expand | `grep -c 'fd00::1/126' SingBoxConfigLoader.swift` | 2 | PASS |
| route_address present | `grep -c 'route_address' SingBoxConfigLoader.swift` | 4 | PASS |
| No deprecated keys | `grep inet6_address SingBoxConfigLoader.swift` | 0 | PASS |

### Invariants re-verified

- **R6** (P2P=false): NEIPv6Settings.destinationAddresses не выставлен.
  Compile-time enforced (macOS 26 / iOS 19 SDK скрыл property — попытка
  присвоения = compile error).
- **R10** (post-expand validate): `SingBoxConfigLoader.validate(json:)` всё
  ещё PASS после expand. Verified test_SingBoxConfigLoader_validate_post_expand.
- **R10 idempotency**: hasTun guard не нарушен. Verified
  test_SingBoxConfigLoader_ipv6_idempotent_whenTunAlreadyPresent.
- **R1** (experimental={}): не задет — TUN inbound expansion не пишет в
  experimental block.

### What did NOT change (locks)

- `App/PacketTunnelExtension-{iOS,macOS}/PacketTunnelProvider.swift` shells —
  всё ещё 14-16 line `@objc(PacketTunnelProvider) final class ... :
  BaseSingBoxTunnel`. R10 architecture invariant.
- `BaseSingBoxTunnel.swift` — Wave 2 не правил (Wave 1 уже добавил Phase 6
  hygiene comment).
- `PoolBuilder.swift` — Wave 1 артефакт, Wave 2 не трогает.
- `validate(json:)` allow-list — `tun` + `direct` без изменений.

### Deferred UAT

Wave 6 device test: запустить туннель на iPhone (LTE/cellular — типичный
v6-enabled network) и открыть https://ipv6-test.com. Ожидается «No IPv6
connectivity detected» при включённом VPN.

### Next wave

Wave 3 — Settings UI + DNSConfig persistence (`@AppStorage('app.bbtb.customDNS')`,
`@AppStorage('app.bbtb.adBlockEnabled')`, `SettingsViewModel.dnsConfig`
computed property + `AdvancedSettingsView`).
