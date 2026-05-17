# BBTB — Bring Back the Bug

iOS VPN client built around [sing-box](https://github.com/SagerNet/sing-box)

**Display name:** «BBTB».

---

## Status

🚧 **Pre-TestFlight Internal Distribution** (Phase 13, May 2026).

Phase progress: 13/N. See [`.planning/STATE.md`](.planning/STATE.md) for current
phase status; [`prompts/`](prompts/) for production spec; [`Wiki/`](Wiki/) для
domain knowledge base.

---

## Architecture

- **Engine:** sing-box (libbox.xcframework) — multi-protocol routing/transport.
- **Protocols supported:** VLESS+Reality, VLESS+TLS, Trojan, Shadowsocks (SS-2022),
  Hysteria2, TUIC v5 (6 protocols × 6 transports = 50+ combinations).
- **iOS:** NetworkExtension `NEPacketTunnelProvider` + Swift 6 strict concurrency.
- **Min support:** iPhone XS / iOS 18.
- **Architecture:** 15 SwiftPM packages.

See [`Wiki/architecture.md`](Wiki/architecture.md) и [`Wiki/tech-stack.md`](Wiki/tech-stack.md)
для detail.

---

## License

**Core (this repository):** AGPL-3.0 (Affero General Public License v3.0) —
required для linking с GPL-3 sing-box engine. See [`LICENSE`](LICENSE).

**Future GUI / Pro features:** likely closed-source proprietary (split repo
when launched).

См. [`Wiki/licensing.md`](Wiki/licensing.md) для full rationale.

---

## Build

Requires Xcode 16+ / Swift 6.

```bash
git clone https://github.com/vergevsky/BBTB.git
cd BBTB/BBTB
xcodebuild -scheme BBTB \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Tests (per-package):

```bash
swift test --package-path BBTB/Packages/ConfigParser
swift test --package-path BBTB/Packages/PacketTunnelKit
# etc.
```

---

## Independent Audit Tooling

This repository has set up [independent code audit tooling](docs/tooling-recommendations.md):

- **Dependabot** — weekly SwiftPM dep CVE alerts
- **CodeQL** — semantic SAST (every push + weekly)
- **Thread Sanitizer (TSAN)** — runtime concurrency race detection on PR / nightly
- **CodeRabbit** — AI-powered PR review (planned activation)
- **Periphery** — Swift dead code detection
- **SwiftLint** — style + 3 custom security rules

Audit history visible in [`.planning/phases/13-testflight-internal-distribution/`](
.planning/phases/13-testflight-internal-distribution/) — 4 comprehensive
audit cycles (AUDIT.md, AUDIT-2.md, AUDIT-3.md, AUDIT-4.md) с 16 parallel
reviewers (7 Opus 4.7 + 9 Codex 5.5) каждый.

---

## Project Structure

```
BBTB/                 — Xcode project root (Swift code)
  App/                — iOS + macOS app shells
  Packages/           — 15 SwiftPM packages (VPNCore, PacketTunnelKit,
                        ConfigParser, RulesEngine, AppFeatures, и др.)
  Protocols/          — 6 protocol packages (VLESSReality, VLESSTLS,
                        Trojan, Shadowsocks, Hysteria2, TUIC)
Wiki/                 — long-form domain knowledge base
.planning/            — GSD operational planning (phases, audits, decisions)
prompts/              — production prompts (v2 spec)
docs/                 — engineering docs (tooling, etc.)
raw/                  — source documents (immutable)
```

---

## Contributing

Currently solo development. Public repo для transparency, не для accepting
external contributions yet. PRs могут быть reviewed но не merged без
explicit design discussion.

Bug reports + security findings welcome via GitHub Issues.

**Security:** see [`SECURITY.md`](SECURITY.md) (TODO — добавим перед v1.0).

---

## Acknowledgements

Built on top of [sing-box](https://github.com/SagerNet/sing-box) (GPL-3.0)
by SagerNet. iOS bindings via libbox.xcframework.

Reference projects: Mullvad VPN (Swift architecture inspiration),
ProtonVPN (kill switch implementation), Wireguard-iOS (NEPacketTunnelProvider
lifecycle patterns).
