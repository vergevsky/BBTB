---
phase: 07-anti-dpi-suite-wireguard-family
sub_phase: 7a
plan: 01
wave: 1
type: execute
title: TUIC v5 protocol package
requirements: [PROTO-08]
autonomous: true
depends_on: []
files_modified:
  - BBTB/Packages/Protocols/TUIC/Package.swift  # NEW
  - BBTB/Packages/Protocols/TUIC/Sources/TUIC/TUICHandler.swift  # NEW
  - BBTB/Packages/Protocols/TUIC/Sources/TUIC/ConfigBuilder.swift  # NEW
  - BBTB/Packages/Protocols/TUIC/Sources/TUIC/Resources/SingBoxConfigTemplate.tuic.json  # NEW
  - BBTB/Packages/Protocols/TUIC/Tests/TUICTests/BuildOutboundTests.swift  # NEW
  - BBTB/Packages/Protocols/TUIC/Tests/TUICTests/ConfigBuilderTests.swift  # NEW
  - BBTB/Packages/VPNCore/Sources/VPNCore/ParsedConfigs.swift  # ADD ParsedTUIC + case
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/TUICURIParser.swift  # NEW
  - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/TUICURIParserTests.swift  # NEW
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift  # ADD tuic:// branch
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift  # ADD .tuic case
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/ClashYAMLParser.swift  # ADD tuic mapping
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/StubParsers.swift  # add "tuic" to knownSchemes
---

# Phase 7a Wave 1 — TUIC v5 protocol package

## Goal

Добавить **TUIC v5** как 6-й protocol handler по образцу Hysteria2 (Phase 4). TUIC v5 — это QUIC-based UDP-протокол с UUID+password authentication, congestion_control выбираемым (cubic/new_reno/bbr), и udp_relay_mode (native/quic).

## Sing-box outbound shape (TUIC v5)

```json
{
  "type": "tuic",
  "tag": "tuic-out",
  "server": "${SERVER_HOST}",
  "server_port": ${SERVER_PORT},
  "uuid": "${TUIC_UUID}",
  "password": "${TUIC_PASSWORD}",
  "congestion_control": "${CONGESTION_CONTROL}",  // "cubic" | "new_reno" | "bbr"
  "udp_relay_mode": "${UDP_RELAY_MODE}",          // "native" | "quic"
  "zero_rtt_handshake": false,
  "heartbeat": "10s",
  "tls": {
    "enabled": true,
    "server_name": "${SNI_DOMAIN}",
    "alpn": ["h3"],
    "utls": { "enabled": true, "fingerprint": "${UTLS_FINGERPRINT}" }
  }
}
```

**Notes:**
- `udp_over_stream` НЕ устанавливаем — он конфликтует с `udp_relay_mode` (Codex Q1).
- R1 invariant: НЕТ `tls.insecure`. TUIC v5 — НЕ исключение R1 (в отличие от Hysteria2).
- TUIC v5 поддерживает только TLS (через QUIC). `alpn: ["h3"]` обязателен.

## TUIC URI format (de facto standard)

```
tuic://<uuid>:<password>@<host>:<port>?
  congestion_control=bbr&
  udp_relay_mode=native&
  sni=<domain>&
  alpn=h3&
  fp=<fingerprint>&
  insecure=0
  #<name>
```

URI parser fields:
- `uuid` (path userinfo before `:`)
- `password` (path userinfo after `:`, URL-decoded)
- `host`, `port` (path)
- query: `congestion_control` (default `bbr`), `udp_relay_mode` (default `native`), `sni` (mandatory R1), `alpn` (default `h3`), `fp` (default `random` per Phase 7a D-05 — но в этом Wave используем "chrome" по образцу Hy2; **смена default-а на random — Wave 2**), `insecure` (игнорируется per R1 strict — TUIC не получает R1 exception в отличие от Hy2).

## Tasks

### Task 1: ParsedTUIC struct + AnyParsedConfig case

**File:** `BBTB/Packages/VPNCore/Sources/VPNCore/ParsedConfigs.swift`

- Добавить `case tuic(ParsedTUIC)` в `AnyParsedConfig` enum.
- Создать `public struct ParsedTUIC: Sendable, Equatable` с полями:
  - `host: String`
  - `port: Int`
  - `uuid: String`
  - `password: String`
  - `congestionControl: String` (validated: "cubic" | "new_reno" | "bbr")
  - `udpRelayMode: String` (validated: "native" | "quic")
  - `sni: String` (R1 mandatory)
  - `alpn: [String]` (default `["h3"]`)
  - `fingerprint: String` (uTLS fingerprint; default "chrome" в этом Wave, перейдёт на "random" в Wave 2)
  - `pinSHA256: String?` (certificate pinning, optional)
  - `remarks: String?`

### Task 2: TUIC SwiftPM package

**Files (new):**
- `BBTB/Packages/Protocols/TUIC/Package.swift` — копия по образцу `Hysteria2/Package.swift`, deps на `VPNCore` + `PacketTunnelKit`, linker settings для libbox transitive deps.
- `BBTB/Packages/Protocols/TUIC/Sources/TUIC/TUICHandler.swift` — `public struct TUICHandler: VPNProtocolHandler` с `identifier = "tuic"`, `displayName = "TUIC v5"`. По образцу Hysteria2Handler.
- `BBTB/Packages/Protocols/TUIC/Sources/TUIC/ConfigBuilder.swift` — `public enum ConfigBuilder` с:
  - `TUICInputs` struct (полный спектр полей)
  - `BuilderError` enum (invalidPort, missingUUID, missingPassword, missingSNI, invalidCongestionControl, invalidUDPRelayMode)
  - `buildSingBoxJSON(from:) throws -> String` — single-server template substitution
  - `buildOutbound(from: ParsedTUIC, transport: TransportConfig, tag: String) -> [String: Any]` — pool case (D-14 pattern)
- `BBTB/Packages/Protocols/TUIC/Sources/TUIC/Resources/SingBoxConfigTemplate.tuic.json` — выше указанный template + полный sing-box config wrapper (inbounds, route, dns — по образцу `SingBoxConfigTemplate.hysteria2.json`).

**Test files (new):**
- `BBTB/Packages/Protocols/TUIC/Tests/TUICTests/BuildOutboundTests.swift` — proves R1 invariant (no `tls.insecure`), correct congestion_control/udp_relay_mode mapping, uTLS fingerprint propagation, pinSHA256 propagation, tag correctness. ~10 test cases.
- `BBTB/Packages/Protocols/TUIC/Tests/TUICTests/ConfigBuilderTests.swift` — template substitution, port mutation, optional fields mutation. ~8 test cases.

### Task 3: TUICURIParser в ConfigParser

**Files (new):**
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/TUICURIParser.swift` — `public enum TUICURIParser` с:
  - `ParseError` enum (invalidScheme, missingUUID, missingPassword, missingHost, missingPort, missingSNI, unsupportedCongestionControl, unsupportedUDPRelayMode)
  - `static func parse(_ uri: String) throws -> AnyParsedConfig` — `tuic://uuid:password@host:port?...`
  - Validation: congestion_control ∈ {cubic, new_reno, bbr}, udp_relay_mode ∈ {native, quic}, SNI mandatory (либо из query, либо fallback to host), port valid range.
  - Default `fp = "chrome"` (Wave 2 поменяет default на "random").

**Test files (new):**
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/TUICURIParserTests.swift` — full URI variations, R1 strict (insecure=1 ignored, throws либо просто ignore), edge cases. ~12 test cases.

### Task 4: UniversalImportParser routing

**File:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift`

- Найти scheme detection блок (где роутятся `vless://`, `trojan://`, `ss://`, `hy2://`).
- Добавить ветку: `if scheme == "tuic" { return try TUICURIParser.parse(line) }`.

### Task 5: PoolBuilder switch case

**File:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift`

- В `buildSingBoxJSON` switch over `AnyParsedConfig` — добавить:
  ```swift
  case .tuic(let parsed):
      outbound = TUIC.ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: tag)
  ```
  Tag pattern по образцу Hysteria2: `"tuic-\(index)"`. Transport всегда `.tcp` (TUIC is QUIC, transport overlay не применяется — D-16 pattern from Phase 5).

### Task 6: ClashYAML mapping

**File:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/ClashYAMLParser.swift`

- В функции маппинга Clash proxy types — добавить case `"tuic"` → ParsedTUIC.
- Clash YAML формат для TUIC:
  ```yaml
  - name: my-tuic
    type: tuic
    server: example.com
    port: 443
    uuid: 00000000-0000-0000-0000-000000000000
    password: secret
    congestion-controller: bbr
    udp-relay-mode: native
    sni: example.com
    alpn: [h3]
    skip-cert-verify: false  # ignored per R1
    client-fingerprint: chrome
  ```
- Mapping: `congestion-controller` → `congestionControl`, `udp-relay-mode` → `udpRelayMode`, `client-fingerprint` → `fingerprint`. `skip-cert-verify` игнорируется.

### Task 7: StubParsers — add "tuic" to knownSchemes

**File:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/StubParsers.swift`

- В `knownSchemes` (Set<String>) — обеспечить чтобы `"tuic"` присутствовал. Если ранее был как stub-only, поведение перейдёт на полный parser (Task 4).

## Must-haves (verifiable)

1. **R1 invariant**: TUIC ConfigBuilder.buildOutbound НЕ устанавливает `tls.insecure` ни в каком сценарии. Test: `test_tuic_outbound_never_has_insecure_true`.
2. **PROTO-08 PROTOCOL_KEY**: `TUICHandler.identifier == "tuic"`, matches `AnyParsedConfig.tuic` case.
3. **sing-box outbound shape**: type:"tuic", uuid, password, congestion_control valid value, udp_relay_mode valid value, tls.alpn:["h3"], tls.server_name:<sni>.
4. **URI parser**: `tuic://uuid:password@host:port?congestion_control=bbr&udp_relay_mode=native&sni=example.com` → valid `ParsedTUIC`.
5. **Pool case**: PoolBuilder switch case `.tuic` covered (test через PoolBuilderSingleOutboundTests).
6. **Clash YAML**: `type: tuic` в YAML → `ParsedTUIC`. `skip-cert-verify: true` игнорируется (R1 strict).
7. **AppFeatures swift test**: 143/143 → 143/143 (новые тесты в TUICTests и ConfigParserTests; AppFeatures count не меняется).
8. **TUICTests swift test**: ~18 tests green.
9. **ConfigParserTests swift test**: existing + 12 новых TUIC parser tests green.
10. **VPNCore swift test**: existing + ParsedTUIC equality test green.

## Verification

```bash
cd BBTB/Packages/AppFeatures && swift test 2>&1 | tail -5
cd BBTB/Packages/Protocols/TUIC && swift test 2>&1 | tail -5
cd BBTB/Packages/ConfigParser && swift test 2>&1 | tail -5
cd BBTB/Packages/VPNCore && swift test 2>&1 | tail -5
```

All green = Wave 1 closed.

## Out of Wave 1 scope

- TUIC handler **registration** в `BBTB_iOSApp.swift` / `BBTB_macOSApp.swift` — Wave 4 (integration).
- Tuist project regen (`tuist generate`) — Wave 4.
- uTLS=random default switch — Wave 2.
- tls.fragment defaults — Wave 2.
- Mux infrastructure — Wave 3.
- Wiki + closure SUMMARY — Wave 5.

## Atomic commit

После полной реализации + verification — один atomic commit:
```
feat(07a-w1): TUIC v5 protocol package (PROTO-08)

- New SwiftPM package Protocols/TUIC with handler + config builder + template.
- TUICURIParser supports tuic://uuid:password@host:port + congestion_control,
  udp_relay_mode, sni, alpn, fp, pinSHA256.
- ParsedTUIC type added to AnyParsedConfig (VPNCore).
- UniversalImportParser routes tuic:// to TUICURIParser.
- PoolBuilder switch handles .tuic case (transport ignored — QUIC).
- ClashYAMLParser maps type: tuic to ParsedTUIC.
- R1 strict: TUIC does NOT get the Hysteria2 allowInsecure exception.
- 30+ new tests across TUIC + ConfigParser + VPNCore packages.
- AppFeatures 143/143 still green.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```
