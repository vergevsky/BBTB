# C8' — Protocols/* re-audit (Codex 5.5)

**Baseline:** commit 55523dd
**Files audited:** 6 ConfigBuilder.swift files

## Closure Verification

| Protocol | Template path removed | Dict path intact | Only public ConfigBuilder method |
|---|---:|---:|---:|
| VLESSReality | ✅ YES | ✅ YES | ✅ YES |
| VLESSTLS | ✅ YES | ✅ YES | ✅ YES |
| Trojan | ✅ YES | ✅ YES | ✅ YES |
| Shadowsocks | ✅ YES | ✅ YES | ✅ YES |
| Hysteria2 | ✅ YES | ✅ YES | ✅ YES |
| TUIC | ✅ YES | ✅ YES | ✅ YES |

Search confirmed no executable `buildSingBoxJSON`, `loadTemplate`, `mutatePort`, `mutateOptionalFields`, `BuilderError`, `*Inputs`, `replacingOccurrences`, or JSON template substitution path remains under the six protocol `Sources/`. Remaining hits are comments only.

## New Findings

### TUIC

#### [LOW] C8'-001: Comment says `tls.insecure` is "always false", implementation correctly never emits it
- **Location:** `TUIC/Sources/TUIC/ConfigBuilder.swift:14`
- **Description:** Comment явно says "always false", but implementation never emits `tls.insecure` key at all. Future maintainers may "fix" code к add `"insecure": false`, violating R1 strict invariant.
- **Suggested fix:** Update TUIC comments к say `tls.insecure` is omitted / never emitted.

Behavioral invariant check: `TUIC/Sources/TUIC/ConfigBuilder.swift:32` builds `tls` without any `insecure` key.

### Other protocols
No new correctness/security findings. All invariants verified.

## Cross-protocol consistency

All six builders construct `[String: Any]` outbounds directly; no JSON string concatenation or template substitution remains.

`tls.insecure` behavior is consistent с policy:
- VLESSTLS: hardcoded `false`
- Trojan: hardcoded `false`
- Hysteria2: `parsed.allowInsecure`, exception only
- TUIC: not emitted
- Shadowsocks: no TLS block
- VLESSReality: no `insecure` key

Resource template JSON files still exist on disk для 5 protocols, но no live source path references them для config building.

## Verdict

**PASS for Plan 03 T-A2 closure.** Unsafe template code paths removed across all 6 protocol builders. Safe dictionary-based `buildOutbound` path the only public ConfigBuilder API. One LOW documentation inconsistency in TUIC; no CRITICAL/HIGH regressions found.
