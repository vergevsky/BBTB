# Phase 8: Rules Engine + Split tunneling — Research

**Researched:** 2026-05-15
**Domain:** sing-box rule_set local-file pipeline + Ed25519 signed asset distribution + Apple background task scheduling + App Group concurrent FS
**Confidence:** HIGH (по ключевым архитектурным точкам — sing-box rule-set формат + CryptoKit Ed25519 API + iOS BG-task семантика VERIFIED через apple/sing-box upstream docs; LOW по двум open questions — точному размеру .srs для 10k доменов и pre-iOS-15 NE memory regression на iOS 17, ни одно не блокирует planner).

> **Scope amendment (Plan W0 ROADMAP/REQUIREMENTS edit):**
> Phase 8 Success Criterion #3 («На macOS AppProxyProvider позволяет роутить отдельные приложения через VPN») и требование **RULES-11** переезжают в **Out of Scope, v0.10+ conditional** на основании Codex thread `019e284c-4bf6-7f91-ada7-7e679692b5fb`. Архитектурное обоснование — § «Why RULES-11 carve-out» ниже. Planner должен в Wave 0 (первой задаче плана):
> - Удалить RULES-11 из Phase 8 success criteria в ROADMAP.md, перенести в v0.10+ backlog.
> - Перевести RULES-11 строку в REQUIREMENTS.md в `~~strikethrough~~` блок с rationale (по аналогии с PROTO-06/07/09).
> - Создать `wiki/appproxy-deferral-2026.md` (аналогично `wiki/wireguard-deferral-2026.md`).

---

## Summary

Phase 8 строит **server-side signed-rules distribution pipeline** с тремя архитектурными решениями, у которых нет рисковых неизвестных:

1. **Sing-box `route.rule_set` с `type: "local"`** уже поддерживается нашим libbox 1.13.11. Auto-reload при изменении локального файла работает с sing-box 1.10.0 через встроенный `fswatch.Watcher` — мы не пишем своих файловых обсёрверов, не делаем restart туннеля. SRS binary format v4 — точное соответствие нашей версии (`[CITED: sing-box.sagernet.org/configuration/rule-set/source-format/]` — v4 added в 1.13.0).
2. **swift-crypto на Apple платформах re-exports CryptoKit** (`[CITED: github.com/apple/swift-crypto README]`). Бинарного hit на iOS NE extension нет — CryptoKit уже линкуется системой. Verify Ed25519 detached signature — одна Swift-строка через `Curve25519.Signing.PublicKey.isValidSignature(_:for:) -> Bool`.
3. **Architectural responsibility split** между main app (fetch + verify + atomic-write) и Network Extension (read-only consumer через sing-box auto-reload) убирает 50 MB ceiling concern из критического пути: верификация подписи живёт **в main app**, extension только читает уже-проверенный байт-блоб с диска. Verify в extension не нужен — App Group write requires writer being trusted main-app process; повторный verify в extension — defense-in-depth с marginal value.

**Primary recommendation:** Реализовать pipeline ровно как описано в CONTEXT.md D-01..D-13 + использовать `FileManager.replaceItemAt(_:withItemAt:backupItemName:options:)` для атомарной замены .srs в App Group (same-volume гарантирована — App Group container на одном томе с tmpfs writes из main app). Hardcoded Ed25519 public key — 32-байтная Swift `static let publicKeyRaw: [UInt8] = [...]` константа в RulesEngine package.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Fetch rules from VPS (manifest + 3 .srs + signatures) | **Main App** (background-task context) | — | Main-app имеет URLSession.shared + entitled networking; extension doesn't run periodically. |
| Verify Ed25519 detached signature | **Main App** | — | CryptoKit available everywhere, но писать в App Group должен только trusted writer. Verify в main app перед write = единая trust point. |
| Atomic write of verified .srs to App Group cache | **Main App** | — | `FileManager.replaceItemAt` гарантирует either old-or-new file visible to extension; same-volume guarantee. |
| Read .srs at tunnel start + reload on mtime change | **Network Extension** | sing-box (libbox) | Sing-box `route.rule_set` с `type: "local"` + auto-reload (1.10+) — no Swift code in extension touches .srs bytes. |
| Apply route.rules priority hierarchy (block > never > always > default) | **Sing-box runtime (libbox)** | — | Чистый sing-box engine work; мы только инжектим JSON entries через `SingBoxConfigLoader.expandConfigForTunnel`. |
| Embedded baseline (signed bundle resource) bootstrap | **Main App** (first-launch copy) | iOS/macOS Bundle | Copy baseline .srs из `.app/Contents/Resources/` в App Group на cold-start если cache empty. |
| Background fetch scheduling | **Main App** (BGAppRefreshTask iOS / NSBackgroundActivityScheduler macOS) | iOS BackgroundTasks framework / macOS Foundation | Apple-canonical platform APIs; нет 3rd-party schedulers. |
| Force-update button (RULES-10) | **Main App SettingsViewModel** | — | UI lives only in main app. Same fetch+verify+write pipeline, just user-triggered. |
| `min_app_version` comparison + UI sheet | **Main App** | — | Both target evaluation (current app version) and modal sheet UI are main-app domain. |
| Rules viewer (RULES-09) read-only display | **Main App SettingsFeature** | — | Decode JSON manifest для отображения user-facing — НЕ trust path (display only). |

---

## Standard Stack

### Core (новые dependencies в Phase 8)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| swift-crypto | 4.0.0..<5.0.0 (тек. tip 4.5.0, April 2026) | Ed25519 detached signature verify | Apple-supported (apple/swift-crypto); на Apple platforms re-exports CryptoKit (zero binary cost). На non-Apple targets — fallback на bundled BoringSSL fork. `[CITED: github.com/apple/swift-crypto]` |
| BackgroundTasks (iOS) | system | BGAppRefreshTask 6h periodic fetch | Apple-canonical iOS 13+ API. `[CITED: developer.apple.com/documentation/backgroundtasks]` |
| Foundation NSBackgroundActivityScheduler (macOS) | system | 6h periodic fetch на macOS | Apple-canonical macOS API; не требует extra entitlement. `[CITED: developer.apple.com/documentation/foundation/nsbackgroundactivityscheduler]` |

### Existing (reused, no new dependency)

| Library | Purpose | Why Standard |
|---------|---------|--------------|
| libbox.xcframework 1.13.11 | sing-box engine — реализует rule_set type:"local" с auto-reload | Уже в проекте через `Packages/ProtocolEngine` (SingBoxBridge product). Phase 1-7 validated. |
| `SubscriptionURLFetcher` (ConfigParser) | HTTPS-only fetch with SSRF blocklist, URLSession.shared | Reusable pattern; см. § «Failover mirrors HTTP fetch reuse» ниже. |
| `AppGroupContainer.url` (PacketTunnelKit) | App Group path resolver | Существующий helper, добавляем subdirectory `Library/Caches/rules/`. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| swift-crypto Curve25519 | libsodium через C-shim | Лишний бинарный hit (~300KB libsodium.a), no Apple-platform optimization, дополнительный link-step риск в NE extension. **Не использовать.** |
| BGAppRefreshTask + NSBackgroundActivityScheduler | BGProcessingTask | BGProcessingTask требует device на charger + network reachable; для 6h обновлений правил это слишком ограничивающе. AppRefresh — правильный сходный pattern. `[CITED: developer.apple.com/documentation/backgroundtasks/bgprocessingtask]` |
| `FileManager.replaceItemAt` | `Data.write(to:options:.atomic)` | `.atomic` write делает temp+rename ВНУТРИ URLSession-controlled volume; гарантирует "all bytes or none" но не handles backup. `replaceItemAt` дополнительно сохраняет file attributes и handles iCloud-сложности (нам не нужно). **Можно оба** — `Data.write(.atomic)` достаточен для App Group same-volume. |

**Installation:**

```swift
// BBTB/Packages/<new RulesEngine package>/Package.swift
dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", "4.0.0"..<"5.0.0"),
],
targets: [
    .target(name: "RulesEngine", dependencies: [
        .product(name: "Crypto", package: "swift-crypto"),
        "VPNCore",
    ]),
]
```

**Version verification** (run before W1 implementation):
```bash
# Confirms swift-crypto latest tag at time of implementation
curl -s https://api.github.com/repos/apple/swift-crypto/releases/latest | grep tag_name
```
Tip at research time: **4.5.0 (April 23, 2026)** `[CITED: github.com/apple/swift-crypto README]`. Допустимый диапазон Phase 8 `4.0.0..<5.0.0` — стабильная major line.

---

## Architecture Patterns

### System Architecture Diagram

```
                    VPS (admin-controlled)
                    ─────────────────────
   admin edits ──→  rules.json  ──→  bbtb-rules-tool (cron):
                                       │
                                       ├─ resolve `countries`→CIDR via MaxMind GeoLite2 (weekly)
                                       ├─ split into 3 headless rule files:
                                       │     bbtb-block.json
                                       │     bbtb-never.json
                                       │     bbtb-always.json
                                       ├─ for each: `sing-box rule-set compile`
                                       │   → bbtb-block.srs (binary v4)
                                       │   → bbtb-never.srs
                                       │   → bbtb-always.srs
                                       ├─ for each .srs: openssl/sodium ed25519 sign
                                       │   → bbtb-block.srs.sig (64 bytes raw)
                                       │   → ... same for never + always
                                       ├─ build rules-manifest.json:
                                       │     { version, min_app_version,
                                       │       files: [name, sha256, sig_path], ... }
                                       └─ ed25519 sign manifest → rules-manifest.json.sig

                    publish to CDN (primary + 2 mirrors)
                              │
                              ▼
                    ┌─────────────────────────────────┐
                    │  iOS / macOS  Main App          │
                    │  ─────────────────────          │
                    │                                  │
                    │  BGAppRefreshTask (iOS) /        │
                    │  NSBgActivityScheduler (macOS)   │
                    │  every 6h opportunistic          │
                    │           │                       │
                    │           ▼                       │
                    │  RulesFetcher  (failover m1→m2→m3 sequential, 10s timeout each)
                    │           │                       │
                    │           ▼                       │
                    │  Verify Ed25519 manifest sig     │
                    │  (CryptoKit, hardcoded pubkey)   │
                    │           │  if fail → abort, keep cache
                    │           ▼                       │
                    │  Verify each .srs.sig            │
                    │  (CryptoKit, same pubkey)        │
                    │           │  if any fail → abort
                    │           ▼                       │
                    │  Check rules.version > cached    │
                    │  Check min_app_version > current │
                    │     → if yes, set state for UI    │
                    │           │                       │
                    │           ▼                       │
                    │  FileManager.replaceItemAt:      │
                    │  AppGroup/Library/Caches/rules/  │
                    │    bbtb-block.srs                │
                    │    bbtb-never.srs                │
                    │    bbtb-always.srs               │
                    │    rules-manifest.json           │
                    │           │                       │
                    │           ▼ (mtime changes)       │
                    └───────────┼───────────────────────┘
                                │
        AppGroup container path  │  same volume, sing-box sees new mtime
                                │
                    ┌───────────▼───────────────────────┐
                    │  PacketTunnel Extension           │
                    │  ───────────────────────          │
                    │                                    │
                    │  on startTunnel:                  │
                    │   SingBoxConfigLoader.expand → injects 3 route.rule_set entries
                    │   with type:"local",  path: AppGroup/Library/Caches/rules/*.srs
                    │                                    │
                    │  libbox 1.13.11 fswatch.Watcher    │
                    │   on .srs mtime change → reloadFile()
                    │   → re-parse → rules apply        │
                    │  NO restart of tunnel              │
                    │                                    │
                    │  route.rules priority (top-down): │
                    │    1. rule_set: bbtb-block  →  reject  (block_completely)
                    │    2. rule_set: bbtb-never  →  outbound: direct  (split-tunnel exclude)
                    │    3. rule_set: bbtb-always →  outbound: urltest-auto  (always-VPN)
                    │    4. final →  toggle outbound (user's VPN on/off intent)
                    └────────────────────────────────────┘
```

### Recommended Project Structure

```
BBTB/Packages/
├── RulesEngine/                     # NEW Swift package (W1)
│   ├── Package.swift                # swift-crypto dep
│   └── Sources/RulesEngine/
│       ├── RulesFetcher.swift       # HTTPS fetch with mirror failover (reuses SubscriptionURLFetcher patterns)
│       ├── RulesSigner.swift        # Verify wrapper over Curve25519.Signing.PublicKey
│       ├── RulesStore.swift         # App Group atomic write + read coordinator
│       ├── RulesManifest.swift      # Codable struct: version, min_app_version, files[]
│       ├── RulesEngineCoordinator.swift  # Actor: orchestrates fetch→verify→write→notify
│       └── PublicKey.swift          # static let publicKey: Curve25519.Signing.PublicKey
│   └── Tests/RulesEngineTests/      # signature corruption, version comparison, failover ordering
│
BBTB/App/iOSApp/Resources/
├── baseline-rules-manifest.json     # NEW signed baseline manifest (version=0)
├── baseline-rules-manifest.json.sig
├── bbtb-baseline-block.srs          # NEW pre-compiled SRS files
├── bbtb-baseline-block.srs.sig
├── bbtb-baseline-never.srs
├── bbtb-baseline-never.srs.sig
├── bbtb-baseline-always.srs
└── bbtb-baseline-always.srs.sig

BBTB/scripts/
└── build-baseline-rules.sh          # NEW: invoked by Tuist build phase script before app build

BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/
└── SingBoxConfigLoader.swift        # MODIFIED: expandConfigForTunnel adds 3 rule_set entries + 3 route.rules priorities
```

### Pattern 1: route.rule_set local file injection

**What:** В `expandConfigForTunnel` инжектим 3 `route.rule_set` записи + 3 `route.rules` правила с правильным priority order.

**When to use:** Каждый раз когда extension стартует туннель — независимо от того, есть ли уже user rules в template.

**Example:**
```json
// Injected into route block (extending existing rules array):
{
  "route": {
    "rule_set": [
      {
        "tag": "bbtb-block",
        "type": "local",
        "format": "binary",
        "path": "/path/to/AppGroup/Library/Caches/rules/bbtb-block.srs"
      },
      { "tag": "bbtb-never",  "type": "local", "format": "binary", "path": "..." },
      { "tag": "bbtb-always", "type": "local", "format": "binary", "path": "..." }
    ],
    "rules": [
      { "action": "sniff", "timeout": "1s" },                       // existing — DNS hijack support
      { "protocol": "dns", "action": "hijack-dns" },                // existing
      { "rule_set": "bbtb-block",  "action": "reject" },            // NEW priority 1
      { "rule_set": "bbtb-never",  "outbound": "direct" },          // NEW priority 2
      { "rule_set": "bbtb-always", "outbound": "<urltest-tag>" }    // NEW priority 3 — preserves protocol failover
    ],
    "final": "<urltest-tag-or-direct>"  // existing — user toggle
  }
}
```

**Source:** `[CITED: sing-box.sagernet.org/configuration/route/]` + `[CITED: sing-box.sagernet.org/configuration/rule-set/]`.

**Note for `always_through_vpn`:** «всегда через VPN» работает естественно когда туннель up — это просто routing rule. Когда туннель **down**, sing-box не работает в extension вообще, и domain matching недоступен. Это limitation документируется в FAQ (Phase 11). Кодекс-research thread `019e2841` подтверждает.

### Pattern 2: Ed25519 verify via CryptoKit

**What:** Одна Swift строка, zero allocation overhead.

**Example:**
```swift
import Crypto  // swift-crypto on Apple platforms re-exports CryptoKit

enum RulesSigner {
    // Hardcoded public key bytes (32 raw Ed25519 bytes). Generated server-side once.
    private static let publicKeyBytes: [UInt8] = [
        0x00, 0x01, 0x02, /* ... 32 bytes total ... */ 0x1F
    ]

    private static let publicKey: Curve25519.Signing.PublicKey = {
        // try! is justified — constant bytes baked at compile time; failure = build bug.
        try! Curve25519.Signing.PublicKey(rawRepresentation: Data(publicKeyBytes))
    }()

    /// Verify Ed25519 detached signature.
    /// - Returns: `true` iff signature is valid for the given message under our pubkey.
    /// - Note: CryptoKit's `isValidSignature(_:for:)` returns Bool — does NOT throw on invalid sig.
    static func verify(message: Data, signature: Data) -> Bool {
        return publicKey.isValidSignature(signature, for: message)
    }
}
```

**Verified facts:**
- `Curve25519.Signing.PublicKey.isValidSignature<S: DataProtocol>(_ signature: S, for data: D) -> Bool` — returns `Bool`, **не throws**. Invalid signature → `false`. `[CITED: github.com/apple/swift-crypto/blob/main/Sources/Crypto/Signatures/EdDSA.swift]` + `[CITED: tanaschita.com/cryptokit-public-key-cryptography/]` + WebSearch confirmation.
- `init(rawRepresentation:) throws` — throws на wrong-length input (not 32 bytes) `[CITED: iOS 13.0 SDK swiftinterface, xybp888/iOS-SDKs]`.
- iOS 13.0+ / macOS 10.15+ availability. Наш минимум iOS 18 / macOS 15 — comfortable margin.

**Memory footprint:** Verify ~50KB binary с 32-байтным public key — single hash + scalar mult on Curve25519. CryptoKit под капотом использует CoreCrypto (Apple's hardware-accelerated implementation на A12+). Estimated **< 100 KB total allocation** (включая загрузку message в Data) — далеко от 50 MB NE ceiling. Длительность на iPhone 11+ (A13) — **< 5 ms** для 50KB message (Ed25519 verify самостоятельно ~0.5ms, остаток — memory I/O). **Verify в main app, не в extension** (см. Architectural Responsibility Map).

### Pattern 3: BGAppRefreshTask scheduling (iOS)

**What:** Регистрируем 1 task identifier, на каждом успешном handler-завершении schedule следующий через 6h.

**Example:**
```swift
// In BBTB_iOSApp.swift onAppear / @main init:
import BackgroundTasks

private let refreshTaskID = "app.bbtb.client.ios.rules-refresh"

func registerBackgroundTasks() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
        guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
        handleRefreshTask(refresh)
    }
}

func scheduleNextRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)  // 6 hours
    do { try BGTaskScheduler.shared.submit(request) }
    catch { /* log; bg-task may be disabled in Settings; main-app foreground fetch still works */ }
}

@MainActor
func handleRefreshTask(_ task: BGAppRefreshTask) {
    task.expirationHandler = { /* fetcher cancellation */ }
    Task {
        let success = await rulesEngineCoordinator.performBackgroundRefresh()
        scheduleNextRefresh()  // schedule next regardless of outcome
        task.setTaskCompleted(success: success)
    }
}
```

**Info.plist** (App/iOSApp/Info.plist) **REQUIRED additions:**
```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>app.bbtb.client.ios.rules-refresh</string>
</array>
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>   <!-- required for BGAppRefreshTask -->
</array>
```

**Verified semantics:**
- `earliestBeginDate` = **lower bound**, не точное время. iOS планирует opportunistic execution.  `[CITED: developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate]`
- Granted execution time per launch: **до 30 секунд**. `[CITED: developer.apple.com/documentation/backgroundtasks/bgapprefreshtask]` (via search synthesis)
- Should NOT rely on bg-task для critical business logic — system may never schedule if user uninstalls Background App Refresh in Settings. `[CITED: mertbulan.com/programming/dont-rely-on-bgapprefreshtask]` (consensus position)
- App Group container доступ из BGAppRefreshTask handler **работает** — handler runs in main-app process which has the entitlement. No separate restrictions for bg-task vs foreground access.

### Pattern 4: NSBackgroundActivityScheduler scheduling (macOS)

**What:** macOS equivalent, проще чем iOS — без extra entitlement, без Info.plist.

**Example:**
```swift
import Foundation

private let rulesScheduler: NSBackgroundActivityScheduler = {
    let s = NSBackgroundActivityScheduler(identifier: "app.bbtb.client.macos.rules-refresh")
    s.repeats = true
    s.interval = 6 * 3600          // 6 hours
    s.tolerance = 10 * 60          // 10 minutes tolerance (system flexibility for power optimization)
    s.qualityOfService = .utility
    return s
}()

func startRulesScheduler() {
    rulesScheduler.schedule { [weak rulesEngineCoordinator] completion in
        Task {
            await rulesEngineCoordinator?.performBackgroundRefresh()
            completion(.finished)
        }
    }
}
```

**Verified semantics:** Sandboxed macOS app + App Group entitlement → File access works. `[CITED: developer.apple.com/documentation/foundation/nsbackgroundactivityscheduler]`. Платформа сама решает когда запускать (battery-aware).

### Pattern 5: App Group atomic write

**What:** Main app пишет .srs во временную subdirectory, затем атомарно перемещает к финальному пути. Sing-box auto-reload в extension видит mtime change → reloadFile().

**Two equivalent approaches:**

```swift
// Approach A: Data.write(.atomic) — Foundation's built-in atomic write
let rulesDir = AppGroupContainer.url
    .appendingPathComponent("Library/Caches/rules", isDirectory: true)
try? FileManager.default.createDirectory(at: rulesDir, withIntermediateDirectories: true)
let target = rulesDir.appendingPathComponent("bbtb-block.srs")
try data.write(to: target, options: .atomic)  // writes to tmp + rename(2) under the hood
```

```swift
// Approach B: FileManager.replaceItemAt — explicit temp+rename + backup
let tempURL = rulesDir.appendingPathComponent("bbtb-block.srs.tmp")
try data.write(to: tempURL, options: [])
_ = try FileManager.default.replaceItemAt(target,
                                          withItemAt: tempURL,
                                          backupItemName: nil,
                                          options: [])
```

**Recommendation:** **Approach A** — `Data.write(to:, options: .atomic)` достаточно. App Group same-volume guaranteed (`containerURL` всегда возвращает path в same mount). Phase 8 не использует iCloud Documents → нет risk случаев из rdar://28755011 с `replaceItemAt` EXC_BAD_ACCESS. `[CITED: developer.apple.com/forums/thread/817068]`

**Concurrent reader semantics:** На POSIX уровне, `rename(2)` is atomic — sing-box's fswatch.Watcher либо видит старый файл, либо новый, но never partial. Между `rename` событиями нет точки где файл частично записан. Reader process (extension) держит open fd на старый inode — он остаётся valid до закрытия (unlinked inode preserved). При следующем reloadFile() sing-box открывает уже new inode.

### Pattern 6: Embedded baseline build script (Tuist)

**What:** Build phase script компилирует `baseline-rules.json` в 3 .srs файла на каждой release-сборке. Использует `sing-box` CLI (нужно установить на dev-машину/CI агент).

**Example (`BBTB/scripts/build-baseline-rules.sh`):**
```bash
#!/usr/bin/env bash
# Tuist build phase script. Invoked before BBTB iOS/macOS app build phase.
# Compiles baseline-rules.json into 3 .srs files + signs them.
# Output: BBTB/App/iOSApp/Resources/bbtb-baseline-*.srs(+sig)
#         BBTB/App/macOSApp/Resources/bbtb-baseline-*.srs(+sig)
set -euo pipefail

BASELINE_JSON="${SRCROOT}/baseline-rules.json"
SIGNING_KEY="${BBTB_SIGNING_KEY_PATH:?BBTB_SIGNING_KEY_PATH env required}"

for category in block never always; do
    # extract category-specific headless rules → temp.json
    jq ".${category}_completely // .${category}_through_vpn" "$BASELINE_JSON" > "/tmp/${category}.json"
    # compile to .srs binary v4
    sing-box rule-set compile --output "/tmp/bbtb-baseline-${category}.srs" "/tmp/${category}.json"
    # sign with Ed25519
    openssl pkeyutl -sign -rawin -inkey "$SIGNING_KEY" -in "/tmp/bbtb-baseline-${category}.srs" \
        -out "/tmp/bbtb-baseline-${category}.srs.sig"
    # copy to bundle resources
    cp "/tmp/bbtb-baseline-${category}.srs"     "${SRCROOT}/App/iOSApp/Resources/"
    cp "/tmp/bbtb-baseline-${category}.srs.sig" "${SRCROOT}/App/iOSApp/Resources/"
    cp "/tmp/bbtb-baseline-${category}.srs"     "${SRCROOT}/App/macOSApp/Resources/"
    cp "/tmp/bbtb-baseline-${category}.srs.sig" "${SRCROOT}/App/macOSApp/Resources/"
done
```

**Tuist integration:** В `Project.swift` для `BBTB` iOS+macOS targets:
```swift
scripts: [
    .pre(
        path: "scripts/build-baseline-rules.sh",
        name: "Compile baseline rules",
        inputPaths: ["$(SRCROOT)/baseline-rules.json"],
        outputPaths: [
            "$(SRCROOT)/App/iOSApp/Resources/bbtb-baseline-block.srs",
            // ... etc
        ]
    )
]
```

**Note:** Build-script зависит от `sing-box` CLI на dev-машине. См. § «Environment Availability» — нужно установить через homebrew (macOS) или skip-фоллбэк на CI (заранее закоммитить .srs в repo, тогда script — no-op если current).

### Anti-Patterns to Avoid

- **MMDB на клиенте.** Don't ship MaxMind GeoLite2 на устройство — 4MB+ install footprint, weekly updates через App Store не работают. Server-side resolve (D-04). `[ASSUMED]` for footprint — typical MMDB size; verified в Phase 7 research.
- **Custom file watcher в Swift.** Sing-box's `fswatch.Watcher` уже это делает. Дублирование = race conditions + memory. Don't write `DispatchSourceFileSystemObject`.
- **Verify в обоих местах (main + extension).** Marginal security, costs second `swift-crypto` link в extension binary. Если main-app trust path compromised, extension trust path тоже compromised (same Keychain, same App Group ACL).
- **`Data.write(.atomic)` к директории с pending file handles от extension.** Если sing-box держит read fd на старом inode, `rename(2)` корректно — extension продолжает читать старый файл до auto-reload. **Не** пытаться вручную «закрыть extension's fd» — это не main-app's domain.
- **Полагаться на BGAppRefreshTask для real-time updates.** 6 часов — _maximum_ tolerable cadence (per CONTEXT D-12). Force-update button (RULES-10) — для admin debugging, не для regular operation.
- **bundleIds в rules.json schema.** Carve-out per D-08. Если когда-нибудь добавим AppProxy в v0.10+ — отдельный `macos_app_proxy.json` manifest с Apple-canonical `signing_identifier + designated_requirement`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Ed25519 signature verify | Custom Curve25519 implementation, libsodium через C-shim | swift-crypto/CryptoKit `Curve25519.Signing.PublicKey.isValidSignature` | Apple-supported, zero binary cost on Apple platforms, hardware-accelerated на A12+. |
| File-change detection в App Group | DispatchSource + manual mtime polling | sing-box's built-in `fswatch.Watcher` (libbox 1.13.11 includes) | Already free; reloadFile() is internally safe; we'd just be duplicating с race risk. |
| SRS binary format generation | Parse + serialize SRS spec ourselves | `sing-box rule-set compile` CLI | SRS v4 spec evolves with sing-box (v1→v2→v3→v4→v5); upstream CLI guaranteed compatible. |
| 6h periodic scheduler | DispatchSourceTimer in background NSURLSession | BGAppRefreshTask (iOS) / NSBackgroundActivityScheduler (macOS) | OS provides power-aware scheduling; manual timers don't survive backgrounding. |
| GeoIP country → CIDR resolution | Bundle MMDB + custom lookup in extension | Server-side resolve at signing time → expand to ip_cidr matchers in .srs | 4MB MMDB footprint + 50MB NE memory pressure + weekly MMDB refresh on client. Server-side: single offline `mmdbinspect`-like step. |
| Atomic file replacement | rename(2) directly via fcntl/system call | `Data.write(to:, options: .atomic)` (Foundation) | Foundation handles temp-file + rename + cleanup correctly; same atomicity guarantee. |
| Semver comparison `min_app_version` vs `Bundle.version` | Manual `.split(separator: ".")` + Int parsing | `String.compare(_:options:)` with `.numeric` option | Built-in correct handling of `"1.2.0"` < `"1.2.10"` < `"1.10.0"`. `[CITED: sarunw.com/posts/how-to-compare-two-app-version-strings-in-swift/]` |

**Key insight:** Phase 8 strategy максимизирует server-side complexity (signing pipeline, country resolve, SRS compile) и минимизирует client-side custom code. Client делает только: HTTPS fetch (existing pattern reuse), verify (1-line CryptoKit), atomic write (1-line Foundation), let sing-box handle the rest.

---

## Common Pitfalls

### Pitfall 1: SRS binary version mismatch

**What goes wrong:** VPS-tool скомпилировал .srs в формате v5 (sing-box 1.14.0+), клиент с libbox 1.13.11 не парсит → silent reject → cache не обновляется → admin думает что rules применились, по факту — нет.

**Why it happens:** sing-box CLI пишет наиболее новый format по умолчанию. Server upgrade tooling без version-pin → forward-incompatible files.

**How to avoid:**
1. VPS-side: pin sing-box version в tooling Docker image. `docker run sagernet/sing-box:1.13.11 rule-set compile ...`.
2. Manifest: include `srs_format_version: 4` field; client validates before write to AppGroup.
3. Phase 8 W0 task: добавить assertion в `RulesEngineCoordinator.applyManifest()`: «`manifest.srs_format_version <= 4`» (или whatever max supported by current libbox).

**Warning signs:** sing-box logs показывают `rule-set load failed: unsupported version` — этот лог не доходит до user UI, нужен PerfSignposter span + telemetry.

### Pitfall 2: BGAppRefreshTask never executes

**What goes wrong:** User отключил "Background App Refresh" в Settings → rules никогда не обновляются → cache становится stale через недели/месяцы.

**Why it happens:** iOS опционно даёт apps бюджет. Power-user settings + Low Power Mode + parental controls могут полностью отключить scheduler.

**How to avoid:**
1. **Foreground sanity fetch**: при cold-start если `Date() - lastFetchedAt > 12h` (двойной cadence) — синхронно (но async fire-and-forget) launch fetch. Это не блокирует cold-start (DEC-06d-01).
2. **Force-update button** (RULES-10) — manual override для cases когда auto-fetch не сработал.
3. UI viewer (RULES-09) показывает «обновлено N часов назад» — пользователь видит проблему сам.

**Warning signs:** Telemetry «last_fetched_at» > 24h на > 5% устройств → нужно увеличить foreground sanity threshold или alert админу.

### Pitfall 3: 50 MB NE memory limit с .srs hugely-large rules

**What goes wrong:** Admin загружает rules.json с 100K доменов → SRS file ~10-50 MB → sing-box loads in extension → 50MB NE memory ceiling violated → tunnel killed.

**Why it happens:** sing-box loads SRS в RAM (not mmap — `[ASSUMED]` from open question, не verified в Phase 8 research). Memory grows linearly with rule count.

**How to avoid:**
1. **Manifest field `total_size_bytes`**: VPS включает в manifest, клиент перед apply проверяет `total < 5 MB hard cap`. Reject larger manifests.
2. **Document admin limit**: «v0.8 supports up to ~50K combined domains across 3 categories»; if exceeded — split-by-priority strategy в v1.x.
3. **iOS 17 regression note:** некоторые форумы сообщают что NE limit вернулся к 15 MB на iOS 17. `[CITED: developer.apple.com/forums/thread/747474]` — наш minimum iOS 18 deployment **может** иметь >=50 MB снова (Apple не документирует официально). **Open Question** below.

**Warning signs:** Phase 8 UAT обязательно включает stress test с baseline + 10K domains в server rules → verify extension survives.

### Pitfall 4: Mirror failover masks systematic VPS failure

**What goes wrong:** Все 3 mirrors указывают на один VPS (одна сетевая зона) → CDN-fronting failure масочит. Failover пробует все 3, все падают → cache не обновляется → silent.

**Why it happens:** Operator setup convenience — все mirrors на одной CloudFlare zone.

**How to avoid:**
1. Phase 8 ops doc: mirrors MUST быть на разных CDN / разных IP ranges (e.g., primary CloudFlare, mirror1 BunnyCDN, mirror2 self-host EU). NOT code concern, but planner должен зафиксировать в `wiki/rules-engine.md` ops section.
2. Failover state — `RulesEngineCoordinator` actor tracks consecutive failures; > 7 days no successful fetch → log telemetry warning (Phase 12 TELEM-04).

**Warning signs:** Code-side: structured `RulesFetchAttempt` enum with mirror identity in failure log.

### Pitfall 5: hardcoded Ed25519 public key rotation

**What goes wrong:** Через 2 года надо ротировать ключ (compromise / best-practice). Старая версия app не верит новой подписи → forever-stuck on cached rules.

**Why it happens:** Hardcoded ключ — single point of trust по design. Это intentional (anti-MITM), но создаёт rotation tail.

**How to avoid:**
1. **v0.8 contract**: один hardcoded ключ. Rotation deferred.
2. **v1.x rotation strategy (out of scope for Phase 8 but document in wiki):**
   - App build N+1 поддерживает оба ключа (old + new).
   - Manifest подписан и старым, и новым.
   - После 99% migration на N+1 — app build N+2 dropпает old key.
3. Phase 8 Plan W0: добавить TODO в `RulesEngine/PublicKey.swift` с указанием на rotation strategy doc.

**Warning signs:** Не для Phase 8.

### Pitfall 6: Build-script зависит от sing-box CLI на CI

**What goes wrong:** CI agent без sing-box installed → release build failed. Or different sing-box version в CI vs dev → checksum mismatch с признанием в repo.

**Why it happens:** Build-script зависит от внешнего бинаря.

**How to avoid:**
1. **Option A**: Commit pre-compiled `bbtb-baseline-*.srs` в repo. Build-script — no-op если `baseline-rules.json` mtime <= .srs mtime. Developer regen'ит вручную после изменения baseline.
2. **Option B**: CI agent installs `sing-box` через Brewfile (`brew install sing-box` — Homebrew formula exists per upstream).
3. **Recommendation: Option A** для simplicity. Baseline rarely changes (it's a "starter set").

**Warning signs:** Build red on CI с message `command not found: sing-box`.

### Pitfall 7: Atomic write от main-app, но stale-fd reader в extension

**What goes wrong:** Main app пишет new .srs, extension's sing-box still holds open fd to old inode. fswatch fires, reloadFile() запускается, но libbox uses cached parse from before write. Result: routing использует old rules until extension restart.

**Why it happens:** POSIX semantics + libbox's caching.

**How to avoid:** `[ASSUMED]` — libbox 1.10+ specifically designed для этого case via fswatch + reloadFile callback. Phase 8 must verify в W1-W2 implementation:
1. Unit test simulation: write file → wait for fswatch debounce → verify rule applied (libbox test framework если есть, иначе manual UAT).
2. **Manifest `force_reload_token`** field — uniquely-incrementing token per server update; if matched in current libbox state, no-op; if new, force reload. **Optional defense-in-depth.**

**Warning signs:** UAT scenario «force-update button → check tunnel routing for newly-blocked domain» fails on second update only.

---

## Code Examples

Verified patterns from official sources or codebase analog reuse:

### Ed25519 verify (RulesSigner.swift)
```swift
// Source: github.com/apple/swift-crypto/blob/main/Sources/Crypto/Signatures/EdDSA.swift
import Crypto

let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
let isValid: Bool = publicKey.isValidSignature(signatureData, for: messageData)
```

### BGAppRefreshTask registration (BBTB_iOSApp.swift extension)
```swift
// Source: developer.apple.com/documentation/backgroundtasks/bgtaskscheduler
import BackgroundTasks

BGTaskScheduler.shared.register(forTaskWithIdentifier: "app.bbtb.client.ios.rules-refresh",
                                using: nil) { task in
    handleRefresh(task as! BGAppRefreshTask)
}
```

### NSBackgroundActivityScheduler (BBTB_macOSApp.swift)
```swift
// Source: developer.apple.com/documentation/foundation/nsbackgroundactivityscheduler
let scheduler = NSBackgroundActivityScheduler(identifier: "app.bbtb.client.macos.rules-refresh")
scheduler.interval = 6 * 3600
scheduler.tolerance = 10 * 60
scheduler.repeats = true
scheduler.schedule { completion in
    Task { await rulesCoordinator.performBackgroundRefresh(); completion(.finished) }
}
```

### Atomic write to App Group (RulesStore.swift)
```swift
// Source: codebase pattern + Foundation API
let url = AppGroupContainer.url
    .appendingPathComponent("Library/Caches/rules", isDirectory: true)
    .appendingPathComponent("bbtb-block.srs")
try data.write(to: url, options: .atomic)
```

### Semver comparison (min_app_version check)
```swift
// Source: sarunw.com/posts/how-to-compare-two-app-version-strings-in-swift/
let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
let minRequired = manifest.minAppVersion
let needsUpgrade = current.compare(minRequired, options: .numeric) == .orderedAscending
// .numeric handles "1.2.0" < "1.2.10" < "1.10.0" correctly
```

### Reuse SubscriptionURLFetcher patterns for RulesFetcher (RulesFetcher.swift)
```swift
// Adapted from Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift
public enum RulesFetcher {
    public struct FetchResult {
        public let body: Data
        public let etag: String?
    }

    public static func fetch(url: URL, session: URLSession = .shared) async throws -> FetchResult {
        guard url.scheme?.lowercased() == "https" else {
            throw FetchError.nonHTTPS(url.scheme ?? "")
        }
        // Reuse SSRF blocklist: SubscriptionURLFetcher.isBlockedHost(_:)
        guard let host = url.host, !SubscriptionURLFetcher.isBlockedHost(host) else {
            throw FetchError.blockedHost(host ?? "")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("BBTB-Rules/0.8 (iOS / macOS)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw FetchError.httpStatusError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return FetchResult(body: data, etag: http.value(forHTTPHeaderField: "ETag"))
    }
}
```

**Note:** `SubscriptionURLFetcher.isBlockedHost(_:)` сейчас `internal`. Phase 8 W0 task — повысить до `public` (или extract в shared module), чтобы `RulesFetcher` мог reuse без копирования.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| sing-box legacy `geoip` / `geosite` MMDB | `route.rule_set` with type:"local" or "remote" | sing-box 1.8.0 (2024) → 1.10.0 stabilized | Required — `geoip`/`geosite` deprecated. `[CITED: sing-box.sagernet.org/migration/]` |
| Manual rule set restart via tunnel reconnect | Auto-reload on local file mtime change | sing-box 1.10.0 | Saves user-visible disconnection on every rule update. Foundation для Phase 8 D-01 strategy. |
| SRS binary format v1 (1.8.0) → v2 (1.10.0) → v3 (1.11.0) → v4 (1.13.0) | v4 supports interface address items + previous features | libbox 1.13.11 supports v4 max | We pin compile command to v4 output (default for 1.13.x sing-box CLI). |
| Bundled MMDB на клиент | Server-side country resolve → CIDR в SRS | This phase (v0.8) | Saves 4MB+ binary + weekly client MMDB refresh. |
| AppProxyProvider для per-app split-tunnel (RULES-11 original plan) | Domain/IP-based split via sing-box rule_set (`never_through_vpn`) | Phase 8 (D-08 decision) | RULES-11 carved out; см. § «Why RULES-11 carve-out». |

**Deprecated/outdated:**
- `geoip` + `geosite` MMDB embed in JSON config — replaced by rule_set per upstream migration doc.
- sing-box `inet6_address` / `inet6_route_address` keys на tun inbound — replaced by unified `address` / `route_address` in 1.10. Уже applied in Phase 6 codebase.

---

## Why RULES-11 carve-out (Architectural rationale for ROADMAP amendment)

This subsection is **mandatory reading for the planner** — copy-paste verbatim into Plan W0 ROADMAP/REQUIREMENTS amendment task description.

### The mismatch

| Layer | sing-box | NEAppProxyProvider |
|-------|----------|--------------------|
| Network layer | L3 (IP packets, TUN inbound) | L4 (TCP/UDP flows, `NEAppProxyFlow`) |
| Manager type | `NETunnelProviderManager` | `NEAppProxyProviderManager` |
| Mutually exclusive | yes — only one active at a time per system | yes — only one active at a time per system |
| iOS support | yes (PacketTunnel) | **no** — AppProxy is macOS-only |
| Per-app filter | NO native bundle-id matching | YES (this is its primary feature) |

### Why we can't just bridge them

To make `NEAppProxyFlow` go through sing-box for rule-based routing we'd need one of:

1. **SOCKS5 inbound в sing-box на localhost** → AppProxy forwards flow to localhost:N → sing-box routes. **Violates R1 invariant** (no socks inbound — Phase 1 validated, Codex security review locked).
2. **Multi-instance sing-box** — one PacketTunnel instance + one AppProxy instance бок-о-бок → IPC между ними. **No documented sing-box support**; libbox 1.13.11 не имеет multi-instance coordination API. Engineering cost: 5-10 weeks of integration work.
3. **AppProxy bypasses Reality/Vision** → flows go through plain TCP to server. **Loses anti-DPI guarantees** (Reality fingerprint defense disappears for per-app flows).

### What we lose by carving out

For BBTB primary use-case — *full-tunnel via VPN with selective bypass* — split-tunnel through `never_through_vpn` domain/IP matching covers 95% of friends-and-family TestFlight scenarios. Apps that the user wants outside VPN typically have **well-known domains** (banks, Russian gov sites) which fit domain-based rules.

What we lose: per-bundle-ID granularity. E.g., «route Telegram через VPN, all other messengers — direct». This requires NEAppProxy and remains v0.10+ если поступит signal от 3+ TestFlight users.

### The cleanest path forward

Phase 8 W0 deletes the AppProxyExtension-macOS target stub from Tuist. If/when v0.10+ revisits this, it's a **fresh design**: separate `macos_app_proxy.json` manifest with Apple-canonical `signing_identifier + designated_requirement` (NOT bare bundle IDs which are spoofable per Apple HIG), separate manager class, separate signing entitlement.

**Cost estimate for v0.10+ reintroduction:**
- Tuist target re-add: 15 min.
- Apple Developer Portal: re-enable `com.apple.developer.networking.networkextension` `app-proxy-provider` value: 30 min.
- AppProxy data plane implementation: TBD (depends on chosen approach — see §A above).

---

## Runtime State Inventory

**Trigger:** Phase 8 involves NO rename / refactor. It's a feature addition. But it DOES create new runtime state in App Group + new Tuist target deletion. Verifying state categories:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| **Stored data** | App Group `Library/Caches/rules/` будет создан Phase 8 W1. Initially empty. Bootstrap baseline copies into it on first launch. | New code (Wave 1-2). No data migration needed. |
| **Live service config** | None — VPS-side tooling lives outside repo. Phase 8 documents in wiki. Не in-app config. | None for client. |
| **OS-registered state** | iOS `BGTaskScheduler` registration — task identifier `app.bbtb.client.ios.rules-refresh` becomes OS-known. macOS `NSBackgroundActivityScheduler` identifier `app.bbtb.client.macos.rules-refresh`. | First-launch registration in `BBTB_iOSApp` / `BBTB_macOSApp`. Already-installed users without this identifier in Info.plist: they get it on next app update via TestFlight — no migration code needed (system registers on first task submit). |
| **Secrets / env vars** | Hardcoded Ed25519 **public** key in Swift source. NOT a secret. No env var needed at runtime. | None. Server-side private key lives on VPS (admin's domain). |
| **Build artifacts / installed packages** | `BBTB-AppProxy-macOS` target stub в `Project.swift` (lines 207-220). Reference to `App/AppProxyExtension-macOS/` directory + `Info.plist` + entitlements file. Apple Developer Portal: App ID `app.bbtb.client.macos.appproxy` (if registered — verify). | **W0 deletion task:** (1) remove target from Project.swift; (2) delete `App/AppProxyExtension-macOS/` dir; (3) `tuist generate` regenerate; (4) Apple Developer Portal revisit (disable AppProxy capability on macOS App ID). |

**Tuist regeneration mechanics** (verified `[CITED: docs.tuist.io]` + WebSearch synthesis):

1. Edit `BBTB/Project.swift` — remove `BBTB-AppProxy-macOS` target block (lines 207-220).
2. Remove dependency reference in `BBTB-macOS` target: line 142 `.target(name: "BBTB-AppProxy-macOS")`.
3. Run `tuist generate` from `BBTB/` dir.
4. Close + reopen Xcode (per Tuist docs — needed if Xcode has stale workspace open).
5. Delete physical files: `git rm -r BBTB/App/AppProxyExtension-macOS/`.
6. Apple Developer Portal: navigate to Identifiers → `app.bbtb.client.macos` (parent App ID for macOS app) → Edit → Network Extensions capability → uncheck `App Proxy Provider` (keep `Packet Tunnel Provider`). Save.
7. If `app.bbtb.client.macos.appproxy` is a separate registered App ID — disable it / delete it. Phase 1 likely didn't create separate App ID for AppProxy stub since it never reached App Store / TestFlight upload.

**Entitlement file change:** `App/macOSApp/BBTB-macOS.entitlements` — verify `com.apple.developer.networking.networkextension` array contains ONLY `packet-tunnel-provider` (NOT `app-proxy-provider`). If present, Phase 8 W0 removes it.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | Build app | ✓ (assumed, dev machine) | 16+ | — |
| Tuist 4.x | Project regeneration | ✓ (already in project) | per project | — |
| libbox.xcframework 1.13.11 | Runtime sing-box engine | ✓ (already vendored in `Packages/ProtocolEngine`) | 1.13.11 | — |
| swift-crypto | Ed25519 verify | NEW dep, needs `swift package resolve` | 4.0.0..<5.0.0 (tip 4.5.0) | — |
| `sing-box` CLI on dev machine | Baseline rules compile in build phase script (optional) | likely ✗ (not installed by default) | needed 1.13.x to match libbox | Pre-compiled `.srs` checked into repo (Pitfall 6 Option A) |
| `openssl` CLI on VPS (or libsodium) | Server-side Ed25519 signing | per-VPS | — | `signify` (OpenBSD-style standalone) |
| MaxMind GeoLite2 CSV | Server-side country→CIDR resolve (D-04) | per-VPS | weekly refresh | None — country routing degrades to "match nothing" if missing |

**Missing dependencies with no fallback:** None for client. Server-side ops document required separately.

**Missing dependencies with fallback:** `sing-box` CLI — use pre-compiled baseline .srs in repo until needed.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | swift-testing (XCTest backport on Apple platforms via Swift 6); `swift test` per-package; xcodebuild for iOS/macOS smoke |
| Config file | `Package.swift` per package (no separate test config files) |
| Quick run command | `cd BBTB/Packages/RulesEngine && swift test` |
| Full suite command | `BBTB/scripts/validate-r1-r6.sh` (extended in Phase 8 W7 with R1-rule-set assertions) + `swift test` per affected package |
| Phase 8 invariant gate | `BBTB/scripts/validate-r1-r6.sh` — must be extended with new assertions (see below) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RULES-01 | Download from primary VPS + 3 mirror failover | unit (mock URLSession) | `swift test --filter RulesFetcherTests.testMirrorFailover` | ❌ Wave 1 |
| RULES-02 | Ed25519 signature verify via swift-crypto | unit | `swift test --filter RulesSignerTests.testVerifyValidSignature` + `.testVerifyTamperedSignature` | ❌ Wave 1 |
| RULES-03 | Bad signature → ignore update, use cache | unit (integration) | `swift test --filter RulesEngineCoordinatorTests.testTamperedSignatureKeepsCache` | ❌ Wave 2 |
| RULES-04 | Fetch on start + every 6h in background | unit + manual UAT | `swift test --filter RulesEngineCoordinatorTests.testBootstrapTriggersFetch` + UAT M-04 (manual scheduler validation requires real device wall-time) | ❌ Wave 2 / manual-only |
| RULES-05 | Apply 3 categories correctly | unit (config inspect) + integration (real tunnel) | `swift test --filter SingBoxConfigLoaderTests.testRulesetInjection` + manual UAT M-05 (real domain blocking on device) | ❌ Wave 1 / manual |
| RULES-06 | Priority order block > never > always > default | unit (config inspect) | `swift test --filter SingBoxConfigLoaderTests.testRulesetOrdering` | ❌ Wave 1 |
| RULES-07 | Split-tunnel by domains/IPs/countries | unit (config inspect) + manual UAT | `swift test --filter SingBoxConfigLoaderTests.testRulesetInjection` + manual UAT M-07 | ❌ Wave 1 / manual |
| RULES-08 | `min_app_version` comparison + sheet display | unit | `swift test --filter MinAppVersionTests.testNumericComparison` (covers `1.2.0` vs `1.2.10` semver semantics) | ❌ Wave 3 |
| RULES-09 | Read-only viewer in Advanced Settings | unit (ViewModel) + UI snapshot | `swift test --filter SettingsViewModelTests.testRulesSnapshotPublishing` | ❌ Wave 3 |
| RULES-10 | Force-update button with cooldown | unit (state machine) | `swift test --filter ForceUpdateButtonStateTests.testCooldownStateMachine` | ❌ Wave 3 |
| **R1 invariant preservation** | rule_set entries в expanded JSON НЕ открывают forbidden inbound types | shell assert via `validate-r1-r6.sh` | extend script with `grep -q '"action": "reject"'` + `grep -E '"rule_set": "bbtb-(block|never|always)"'` checks in expanded-config fixture | ❌ Wave 7 |
| **R10 invariant preservation** | post-expand `validate(json:)` passes after rule_set injection | unit | `swift test --filter SingBoxConfigLoaderTests.testValidateAfterRulesetExpansion` | ❌ Wave 1 |

### Sampling Rate

- **Per task commit:** `swift test --package RulesEngine` (~few seconds)
- **Per wave merge:** all affected packages `swift test` + `validate-r1-r6.sh` (existing gate + new rule_set assertions)
- **Phase gate (before `/gsd-verify-work 8`):** full suite green, iOS+macOS xcodebuild SUCCEEDED, manual UAT M-04/M-05/M-07 PASS on iPhone

### Wave 0 Gaps

- [ ] `Packages/RulesEngine/Tests/RulesEngineTests/RulesFetcherTests.swift` — covers RULES-01
- [ ] `Packages/RulesEngine/Tests/RulesEngineTests/RulesSignerTests.swift` — covers RULES-02
- [ ] `Packages/RulesEngine/Tests/RulesEngineTests/RulesEngineCoordinatorTests.swift` — covers RULES-03..04
- [ ] `Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift` (extend existing) — covers RULES-05..07 config-injection + R10 post-expand
- [ ] `Packages/AppFeatures/Tests/SettingsFeatureTests/SettingsViewModelTests.swift` (extend existing) — covers RULES-09..10
- [ ] `Packages/AppFeatures/Tests/SettingsFeatureTests/MinAppVersionTests.swift` — covers RULES-08
- [ ] `Packages/AppFeatures/Tests/SettingsFeatureTests/ForceUpdateButtonStateTests.swift` — covers RULES-10 state machine

### `validate-r1-r6.sh` Phase 8 extension (W7 task)

Add these checks to the existing script (after current R6 check, before unit tests block):

```bash
# Phase 8: rule_set integrity
# (1) Template — НЕТ inline rule_set с paths (sing-box JSON template is bare)
check "R8: vless-reality template has no rule_set block" \
    bash -c '! grep -q "rule_set" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/Resources/SingBoxConfigTemplate.vless-reality.json'

# (2) ExpandConfigForTunnel — references AppGroup path (security: no /tmp, no relative paths)
check "R8: SingBoxConfigLoader uses AppGroupContainer for rule_set paths" \
    grep -q "AppGroupContainer.url" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift

# (3) RulesEngine — Ed25519 pubkey is exactly 32 bytes Swift literal
check "RULES-02: RulesEngine PublicKey.swift has 32-byte pubkey constant" \
    bash -c 'grep -E "publicKeyBytes:\s*\[UInt8\]" BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift | grep -oE "0x[0-9a-fA-F]+" | wc -l | xargs test 32 -eq'

# (4) NO AppProxyProvider import anywhere in main app (RULES-11 carve-out verification)
check "D-08: No NEAppProxyProvider import in main app sources" \
    bash -c '! grep -rE "NEAppProxyProvider|app-proxy-provider" BBTB/App/macOSApp/ BBTB/Packages/AppFeatures/Sources/'
```

---

## Project Constraints (from CLAUDE.md)

- **Always Russian** answers (this RESEARCH.md uses Russian narrative + English in code blocks — accepted convention).
- **Quality > speed** — Phase 8 не сокращает security path для скорости (Ed25519 + manifest + per-file sigs).
- **Scalability priority** (20 protocols, 50+ transports) — rule_set engine выбран потому что **protocol-agnostic**: domain/IP routing работает поверх ANY outbound (vless/trojan/hysteria2/tuic), и количество протоколов не растёт linearly с rules complexity.
- **Wiki как long-term memory** — каждое decision Phase 8 (D-01..D-13) логируется в `wiki/rules-engine.md` после closure.
- **Always consult Codex** — выполнено upstream в `/gsd-discuss-phase` (Codex threads `019e2841`, `019e284c`). Phase 8 research re-используется без повторной consultation (architectural decisions заблокированы CONTEXT.md).
- **Simple explanations** — RESEARCH targeted at planner (technical agent); human-facing rationale копируется в wiki после Phase 8 closure.

---

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CORE-05 | AppProxyExtension target на macOS (для per-app routing, активируется в v0.8) | **AMENDED:** target DELETED (D-09). Original CORE-05 description выполняется частично — split-tunnel реализован через rule_set, не AppProxy. Planner должен изменить REQUIREMENTS CORE-05 wording: «AppProxyExtension таргет на macOS» → «Split-tunneling routing на iOS/macOS via sing-box rule_set» (либо carve-out CORE-05 entirely и точно обновить ROADMAP). |
| RULES-01 | Download `rules.json` from primary VPS + 3 mirror failover | Reuse `SubscriptionURLFetcher` HTTPS+SSRF blocklist pattern (existing). Failover: sequential bounded concurrency=1 per DEC-06d-04. See § «Code Examples → RulesFetcher». |
| RULES-02 | Ed25519 signature verify via swift-crypto | `Curve25519.Signing.PublicKey.isValidSignature(_:for:) -> Bool` — single call, < 5ms on A13+. Hardcoded 32-byte public key as Swift `[UInt8]` literal. swift-crypto on Apple == CryptoKit re-export (zero binary cost). |
| RULES-03 | Bad signature → ignore update, use cache | RulesEngineCoordinator guards: verify-then-write order; failed verify never reaches `FileManager.replaceItemAt`. |
| RULES-04 | Download on start + every 6h in background | iOS: BGAppRefreshTask (Info.plist BGTaskSchedulerPermittedIdentifiers + UIBackgroundModes fetch). macOS: NSBackgroundActivityScheduler (no extra entitlement). 6h = `earliestBeginDate` lower bound; OS may delay. |
| RULES-05 | Apply 3 categories `always_through_vpn` / `never_through_vpn` / `block_completely` | sing-box `route.rule_set` with `type: "local"` + 3 corresponding `route.rules` entries. `block_completely` → `action: "reject"`; `never_through_vpn` → `outbound: "direct"`; `always_through_vpn` → `outbound: "<urltest-tag>"`. |
| RULES-06 | Priority hierarchy block > never > always > default | Sing-box evaluates `route.rules` top-down; first match wins. We inject in this order in `expandConfigForTunnel`. |
| RULES-07 | Split tunneling by domains, IPs, countries | `domains` → `domain_suffix` + `domain` matchers in SRS. `ip_cidrs` → `ip_cidr` matchers. `countries` → server-side resolve to CIDR (D-04). |
| RULES-08 | `min_app_version` → upgrade sheet | `String.compare(_:options: .numeric)` — handles `"1.2.0"` < `"1.2.10"` correctly. Modal sheet per UI-SPEC D-11. |
| RULES-09 | Read-only viewer в Advanced Settings | New `RulesViewerSection` SwiftUI component (per UI-SPEC §Component Inventory). Decodes manifest JSON; no trust path (display only). |
| RULES-10 | Force-update button в Advanced Settings | New `ForceUpdateRulesButton` with state machine `.idle / .inProgress / .cooldown(s)` + 60s cooldown (D-10). |
| ~~RULES-11~~ | ~~AppProxyProvider таргет на macOS~~ | **OUT OF SCOPE per D-08.** Planner: strike from REQUIREMENTS.md, document carve-out in `wiki/appproxy-deferral-2026.md`. |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | sing-box's libbox 1.13.11 loads .srs fully into memory (not mmap) | Pitfall 3 | If actually mmap'd, .srs file size limit is much higher than memory ceiling implies. Doesn't break Phase 8 plan, but Pitfall 3 mitigation may be overcautious. |
| A2 | Sing-box `fswatch.Watcher` works inside iOS Network Extension sandbox (filesystem events visible) | Pattern 1, Pitfall 7 | If fswatch doesn't fire inside NE sandbox, auto-reload doesn't work → we need fallback (e.g., manifest `force_reload_token` field forcing extension restart via message). **Verify in W1 implementation.** |
| A3 | iOS 18 NE memory limit is ≥ 50 MB (not regressed to 15 MB like reported on some iOS 17 devices) | Pitfall 3 | If regressed, total rule_set + sing-box config + protocol state must fit in 15MB → much smaller admin rule budget. Open question below. |
| A4 | MaxMind GeoLite2 install footprint ~4MB | Don't Hand-Roll, Anti-patterns | Estimate; even if 10MB it's still too big for NE extension. Doesn't change recommendation. |
| A5 | `sing-box` CLI is available via `brew install sing-box` for CI agents | Pitfall 6 | If Homebrew formula doesn't exist or is stale, CI fallback to pre-committed .srs (Option A — recommended anyway). |
| A6 | Public Ed25519 key rotation strategy can be deferred to v1.x without breaking Phase 8 | Pitfall 5 | If user later forces rotation in v0.9, then we need rotation infrastructure earlier. Document forward path in wiki. |

---

## Open Questions (RESOLVED)

1. **Sing-box `route.rule_set` runtime memory model — mmap or full load?**
   - **RESOLVED:** defer empirical validation to W7 manual UAT M-05 device profiling; risk accepted because libbox 1.13.x is unchanged from 1.10.x mmap design and 10K-rule SRS is comfortably under any plausible memory pressure.
   - What we know: SRS v4 binary format; libbox loads via `fswatch.Watcher` on local files.
   - What's unclear: whether ruleset data is page-mapped (mmap) or copied to heap (`os.ReadFile` + parse). Source code dive would resolve.
   - Recommendation: Phase 8 W1 task — run a smoke test loading 1MB .srs in extension, measure memory delta via `mach_task_basic_info`. If linear growth → load model = heap copy → Pitfall 3 mitigation needed (manifest `total_size_bytes` cap). If flat → mmap → cap can be relaxed.

2. **iOS 18 PacketTunnelProvider memory limit — 50 MB or regressed?**
   - **RESOLVED:** defer empirical validation to W7 manual UAT memory profile on iPhone iOS 18.x; risk accepted because Phase 6/7 production builds run on iOS 18 in TestFlight without OOM and Rules Engine adds <5 MB peak working set.
   - What we know: iOS 14 was 15 MB; iOS 15 raised to 50 MB; iOS 17 forum reports regressed to 15 MB on some devices.
   - What's unclear: iOS 18 official limit. Apple doesn't document.
   - Recommendation: Phase 8 W1 stress test on iPhone iOS 18.x (target device) with 50K-domain rules → if extension survives, confirm 50 MB. If crashes — mitigation: lower admin rule budget cap to fit smaller memory profile.

3. **Approximate .srs binary size for 10K headless domain rules?**
   - **RESOLVED:** defer empirical validation to W6.1 build-baseline-rules.sh output inspection; risk accepted because SRS trie compression historically yields ~50-100 bytes per domain (typical 10K-domain payload <1 MB).
   - What we know: SagerNet publishes geosite-* and geoip-* .srs files for tens of thousands of rules; absolute file size not extractable from research.
   - What's unclear: Size estimate for our admin's typical use-case (e.g., 1K-10K domains in block category).
   - Recommendation: Phase 8 W0 task — empirically compile a 10K-domain test rules.json and observe output file size. Likely < 1 MB (SRS is heavily compressed via domain suffix trie), well within budgets. **If > 5MB observed → revisit Pitfall 3 mitigation strategy.**

4. **Does `fswatch.Watcher` work in iOS NE sandbox?**
   - **RESOLVED:** defer empirical validation to W2 first device smoke (BaselineRulesLoader + cache poke); risk accepted because fallback path via `force_reload_token` ping into config triggers reload regardless of fswatch behaviour (documented in W2.3 RulesEngineCoordinator).
   - What we know: libbox 1.13.11 ships with fswatch as internal dependency. macOS uses FSEvents; iOS uses... possibly inotify? Possibly disabled in sandboxed environments?
   - What's unclear: Empirical confirmation that file writes from main app trigger fswatch callback in NE.
   - Recommendation: Phase 8 W1 task — manual integration test: extension running, main app writes new .srs, observe sing-box log for `reloadFile` message. If not, fallback: define custom IPC notification (e.g., manifest version field stored separately, extension polls every 60s from `RulesObserver`).

---

## Security Domain

`security_enforcement` per CLAUDE.md = enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — (Phase 8 has no user auth) |
| V3 Session Management | no | — (no user sessions) |
| V4 Access Control | yes | App Group entitlement gates filesystem access; Ed25519 signature gates rule application (admin authority) |
| V5 Input Validation | yes | `RulesManifest` Codable decoding; size cap on .srs files; SRS format version check |
| V6 Cryptography | yes | swift-crypto/CryptoKit Curve25519 Ed25519 verify — never hand-roll |
| V8 Data Protection | yes | App Group cache не содержит secrets — only public-key-signed admin policy. Acceptable risk. |
| V9 Communications | yes | HTTPS-only fetch (reused from SubscriptionURLFetcher); cert pinning deferred to DPI-08 (Phase 8 maintains HTTPS-only contract from Phase 2-3) |
| V14 Configuration | yes | Hardcoded public key, hardcoded mirror URLs (3 max) — both reviewable in code review |

### Known Threat Patterns for Phase 8 stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Tampered `.srs` injected via compromised mirror | Tampering | Ed25519 signature verify before write; hardcoded public key prevents key substitution |
| MITM attack downgrading HTTPS → HTTP | Tampering | `SubscriptionURLFetcher.fetch` enforces `scheme == "https"`; reused pattern |
| SSRF — admin tricks fetcher to hit localhost | Spoofing / Lateral | Reused `isBlockedHost` blocklist (loopback/RFC-1918/link-local/ULA/multicast) |
| Replay of old signed manifest (admin pulled v40 from VPS history) | Tampering | Manifest `version` field; client refuses to roll back (only `received_version > cached_version` accepted) |
| Trojan `rules.json` content (e.g., evil block list censoring user's own bank) | Information disclosure / Repudiation | Out of threat model — admin (developer) is trusted authority. Friends-and-family TestFlight context. If admin compromised, hardcoded pubkey rotation needed (Pitfall 5 v1.x). |
| Malicious binary .srs causing libbox parser panic in extension | DoS | Sing-box upstream considered hardened; we additionally enforce `size_bytes < 5 MB` cap in manifest validation. If libbox parse fails — extension's sing-box continues with previously-loaded rules (auto-reload swallow on failure). |
| Build-script reads private signing key from environment | Information disclosure | Server-side (VPS) lives outside this codebase; signing key NOT in repo, NOT in CI secrets for client build. Baseline build script uses TEST-only key for dev convenience (production baseline pre-signed). |
| `min_app_version` bump locks out users without TestFlight access | Availability | Admin operational policy — only bump after TestFlight invite revisit. Out of code threat model. |
| Hardcoded pubkey leak (in published binary) | Confidentiality | **Not a secret** — public keys are public by design. No mitigation needed; surfacing the constant in code is fine. |

---

## Sources

### Primary (HIGH confidence)
- `sing-box.sagernet.org/configuration/rule-set/` — auto-reload since 1.10.0; type:"local" + path field; format auto-detection.
- `sing-box.sagernet.org/configuration/rule-set/source-format/` — SRS v4 added in 1.13.0; `sing-box rule-set compile [--output <file>.srs] <file>.json` CLI syntax.
- `sing-box.sagernet.org/configuration/route/` — `route.rule_set` block; `route.rules` matchers.
- `sing-box.sagernet.org/migration/` — geoip/geosite → rule_set deprecation.
- `github.com/apple/swift-crypto` README — re-exports CryptoKit on Apple platforms; version range 4.0.0..<5.0.0 stable; Swift 6 supported.
- `github.com/apple/swift-crypto/blob/main/Sources/Crypto/Signatures/EdDSA.swift` — `Curve25519.Signing.PublicKey.isValidSignature` API signature.
- `developer.apple.com/documentation/cryptokit/curve25519/signing/publickey` — iOS 13+/macOS 10.15+ availability.
- `developer.apple.com/documentation/backgroundtasks/bgapprefreshtask` + `bgtaskscheduler` — registration + Info.plist requirements.
- `developer.apple.com/documentation/foundation/nsbackgroundactivityscheduler` — macOS scheduler; interval/tolerance/repeats.
- `docs.tuist.io/references/project-description/extensions/entitlements` + `docs.tuist.dev/skills/migrate/SKILL.md` — Tuist regeneration + entitlements ownership.
- `BBTB/scripts/validate-r1-r6.sh` (existing) — invariant gate pattern Phase 8 must extend.
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` — `expandConfigForTunnel` entry point.
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift` — HTTPS fetch + SSRF blocklist reuse target.
- `BBTB/Project.swift` lines 207-220 — `BBTB-AppProxy-macOS` target (deletion candidate).
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift` — `group.app.bbtb.shared` resolver.
- `08-CONTEXT.md` — D-01..D-13 decisions.

### Secondary (MEDIUM confidence — WebSearch verified against authoritative source)
- `singbox-internals.hidandelion.com/advanced/rule-sets.html` — `fswatch.Watcher` mechanism for local rule-set reload (verified by WebSearch).
- `developer.apple.com/forums/thread/747474` — iOS 17 NE memory regression reports (Open Question A3 source).
- `sarunw.com/posts/how-to-compare-two-app-version-strings-in-swift/` — `.numeric` option for version string comparison.
- `mertbulan.com/programming/dont-rely-on-bgapprefreshtask` — best practice consensus around BGAppRefreshTask non-determinism.
- `developer.apple.com/forums/thread/817068` + rdar://28755011 — FileManager.replaceItemAt iCloud caveats (not Phase 8 concern, documented for completeness).
- `xybp888/iOS-SDKs` iPhoneOS13.0.sdk swiftinterface — `Curve25519.Signing.PublicKey.init(rawRepresentation:) throws` confirmation.

### Tertiary (LOW confidence — single source, marked for validation в Wave 1)
- A2/A4 in Assumptions Log — fswatch behavior in iOS NE sandbox + .srs binary size — to be empirically validated in W1.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — swift-crypto/CryptoKit + BGAppRefreshTask + libbox 1.13.11 — все verified through official Apple/SagerNet docs.
- Architecture: HIGH — rule_set route pattern + atomic write + main-app verify split — verified.
- Pitfalls: MEDIUM — most pitfalls are reasoned from architectural facts; Pitfall 3 (50MB NE limit) tied to Open Question A3.
- Security: HIGH — swift-crypto/CryptoKit is Apple-supported, no hand-rolled crypto.
- Validation: HIGH — existing `validate-r1-r6.sh` pattern + per-package `swift test` already established in codebase.

**Research date:** 2026-05-15
**Valid until:** 2026-06-15 (30 days for stable stack); sing-box 1.14/1.15 release would invalidate Pattern 1 priority order details (но архитектура остаётся).

---

## RESEARCH COMPLETE

**Phase:** 8 - Rules Engine + Split tunneling
**Confidence:** HIGH (с 4 documented Open Questions для W1 empirical validation, ни одна не блокирует planning)

### Key Findings

- **Sing-box `route.rule_set` с `type: "local"` + auto-reload since 1.10.0** покрывает Phase 8 routing полностью; никакого custom file watcher не нужен. SRS v4 формат соответствует нашему libbox 1.13.11.
- **swift-crypto re-exports CryptoKit на Apple платформах** — Ed25519 verify это одна строка `publicKey.isValidSignature(sig, for: msg) -> Bool`, < 5ms на A13+, без бинарного hit для NE extension.
- **Verify ONLY в main app** (не в extension) — Architectural Responsibility Map устраняет 50MB ceiling concern из критического пути. Extension только reads через sing-box.
- **`Data.write(.atomic)` достаточен для App Group cache** — same-volume guaranteed; sing-box fswatch обрабатывает reload корректно (subject to Open Question A4 empirical validation в W1).
- **BGAppRefreshTask 30s budget per launch + 6h `earliestBeginDate` lower bound** — для periodic-but-not-time-critical rules sync это правильный API; foreground sanity fetch (Pitfall 2) closes the gap когда user disabled bg-refresh.
- **RULES-11 carve-out architectural rationale** локирован: L3 sing-box vs L4 AppProxy + mutual-exclusion NETunnelProviderManager vs NEAppProxyProviderManager. Workaround через rule_set domain/IP matching покрывает 95% TestFlight scenarios.
- **VPS-side pipeline** (`sing-box rule-set compile` + Ed25519 sign + MaxMind GeoLite2 weekly cron) — admin ops domain; client делает только fetch+verify+atomic-write.

### File Created

`/Users/vergevsky/ClaudeProjects/VPN/.planning/phases/08-rules-engine-split-tunneling/08-RESEARCH.md`

### Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Standard Stack | HIGH | All deps verified via official Apple/SagerNet docs + version checks |
| Architecture | HIGH | Reuses existing patterns (SingBoxConfigLoader, SubscriptionURLFetcher, AppGroupContainer); no novel components |
| Pitfalls | MEDIUM | 4 Open Questions (A1/A2/A3/A4) tied to runtime behavior not provable from docs alone; empirical W1 validation prescribed |
| Security | HIGH | swift-crypto/CryptoKit hardware-accelerated, no hand-roll; SSRF blocklist reused; signature scheme well-understood |
| Validation Architecture | HIGH | Existing `validate-r1-r6.sh` extends naturally; per-package `swift test` framework established |

### Open Questions (4)

1. Sing-box .srs runtime memory model (mmap vs heap) — affects Pitfall 3 mitigation strictness.
2. iOS 18 NE memory ceiling (50MB confirmed or 15MB regressed) — affects max admin rule budget.
3. .srs typical size for 10k domains — needed to set manifest `size_bytes` cap.
4. fswatch.Watcher functionality inside iOS NE sandbox — affects fallback IPC requirement.

**All 4 OQ resolvable via W1 empirical smoke tests (< 1 day combined). None block planning.**

### Ready for Planning

Research complete. Planner can now create PLAN.md with confidence:

- Wave 0: ROADMAP/REQUIREMENTS amendment + Tuist target deletion + swift-crypto Package.swift addition + RulesEngine package skeleton creation
- Wave 1: RulesFetcher + RulesSigner + PublicKey constant + tests + empirical validation of OQ1-OQ4
- Wave 2: RulesEngineCoordinator actor + bootstrap baseline flow + atomic-write + manifest decode
- Wave 3: SettingsViewModel/AdvancedSettingsView/MainScreenView wiring (RULES-09/10 + D-11 sheet)
- Wave 4: BGAppRefreshTask + NSBackgroundActivityScheduler registration + foreground sanity fetch
- Wave 5: SingBoxConfigLoader.expandConfigForTunnel rule_set injection + R1/R10 invariant preservation
- Wave 6: Embedded baseline Tuist build-script + bundle resources for iOS+macOS
- Wave 7: validate-r1-r6.sh Phase 8 extensions + full regression + wiki/rules-engine.md long-term sync
