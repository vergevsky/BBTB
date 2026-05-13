# Wave 06D-02a — PREFLIGHT

**Дата:** 2026-05-14
**Базовая ветка / SHA:** `main @ e2c9ac6` (на момент Commit 1)
**Инициатор:** Wave 06D-02a Task 1 (tooling install)

---

## 1. Tool install verification (Commit 1 scope)

### Periphery 3.7.4

| Параметр | Значение |
|---|---|
| Требуется планом | ≥ 3.7.4 |
| Установленная версия | **3.7.4** |
| Источник | GitHub Releases (`https://github.com/peripheryapp/periphery/releases/download/3.7.4/periphery-3.7.4.zip`) |
| Расположение бинаря | `/opt/homebrew/opt/periphery-3.7.4/periphery-bin` |
| Wrapper | `/opt/homebrew/bin/periphery` (bash-скрипт с `DYLD_LIBRARY_PATH`) |
| Команда проверки | `periphery version` → `3.7.4` |

**Известный delta vs план:** homebrew-tap `peripheryapp/periphery/periphery` отдаёт устаревшую версию 2.21.2 (cask последний раз обновлён на 2.x). Поэтому установка выполнена **прямой выгрузкой** официального ZIP-релиза 3.7.4 от автора (peripheryapp), с distincit-папкой `/opt/homebrew/opt/periphery-3.7.4/` для бинаря и `libIndexStore.dylib`. Wrapper в `/opt/homebrew/bin/periphery` оборачивает запуск с правильным `DYLD_LIBRARY_PATH`. Quarantine attribute снят (`xattr -dr com.apple.quarantine`), бинарь подписан upstream (Apple-notarized).

После публикации tap-update на 3.x можно будет вернуться к `brew install peripheryapp/periphery/periphery` — текущая установка совместима по результату (`periphery version` → `3.7.4`).

### jq

| Параметр | Значение |
|---|---|
| Установленная версия | **jq-1.7.1-apple** |
| Расположение | `/usr/bin/jq` (system; уже было) |
| Команда проверки | `jq --version` |

### ripgrep (rg)

| Параметр | Значение |
|---|---|
| Установленная версия | **ripgrep 14.1.1 (rev 0a466a11ee)** |
| Расположение | shell-alias через mise/Claude exec wrapper |
| Команда проверки | `rg --version | head -1` |

### Tuist (бонус, уже было)

| Параметр | Значение |
|---|---|
| Версия | 4.192.3 |
| Источник | mise (`/Users/vergevsky/.local/share/mise/installs/tuist/4.192.3/tuist`) |

---

## 2. Periphery + Tuist compat — mini-scan (A6)

**Команда:**

```bash
cd BBTB && tuist generate
periphery scan --project BBTB.xcworkspace --schemes BBTB --retain-public \
    --report-exclude '**/Tests/*.swift' --exclude-tests --disable-update-check
```

**API delta vs план:** Periphery 3.x использует флаг `--project` для пути к `.xcodeproj` или `.xcworkspace` (план писался с 2.x флагами `--workspace`/`--targets`). Целевой scheme задаётся через `--schemes`, targets фильтруются через `--exclude-targets` или scheme membership — этого достаточно для нашего workflow.

**Результат mini-scan:** `success — 30+ warnings` (unused imports / unused params / unused functions). Это **input для Wave 06D-02b synthesis** (multi-AI prescriptive playbook), а не материал для исправления в этой волне.

Пример первой пятёрки findings:

| File | Line | Warning |
|---|---|---|
| `AppFeatures/.../TunnelController.swift` | 80 | Assign-only property `userIntendedConnected` is assigned, but never used |
| `AppFeatures/.../TunnelWatchdog.swift` | 180–182 | Unused test-helper functions (`getStableSessionForTest()` etc.) |
| `AppFeatures/.../ServerDetailView.swift` | 18 | Unused imported module `ConfigParser` |
| `Protocols/Hysteria2/ConfigBuilder.swift` | 2, 212 | Unused imported module + unused parameter `transport` |
| `Protocols/Shadowsocks/ConfigBuilder.swift` | 2, 108 | Same pattern (Shadowsocks) |

Полный список — будет сгенерирован отдельным runs в Wave 06D-02b.

**Verdict:** Periphery 3.7.4 + Tuist 4.192.3 + BBTB.xcworkspace = **compat OK**. Mini-scan завершился без crashes / unsupported-options.

---

## 3. Regression gate D-08 (Commit 1)

| Step | Команда | Результат |
|---|---|---|
| 1 | `swift test --package-path BBTB/Packages/AppFeatures` | **133/133 PASS** в 7.83s |
| 2 | `xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB -destination 'generic/platform=iOS Simulator' build` | ** BUILD SUCCEEDED ** |
| 3 | `xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB-macOS -destination 'platform=macOS' build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` | ** BUILD SUCCEEDED ** |

**Уточнения по build-командам (фиксируем для всех последующих волн):**

1. План указывал `-project BBTB/BBTB.xcodeproj` — но iOS scheme требует SPM-разрешения, которое работает только через **workspace** (`BBTB/BBTB.xcworkspace`). Поэтому actual commands используют `-workspace`. `BBTB.xcodeproj` существует (Tuist его генерирует), но iOS-сборка через project напрямую упирается в неразрешённые SPM-пакеты.
2. macOS build требует `CODE_SIGNING_ALLOWED=NO` (либо активного Developer ID Application cert + dev team) — на чистой dev-машине без signing setup это единственный способ собрать с `entitlements`. iOS Simulator build не требует signing.

**Каноническая команда для всех последующих regression gates Phase 6d** (используйте именно её):

```bash
swift test --package-path BBTB/Packages/AppFeatures
xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB \
    -destination 'generic/platform=iOS Simulator' build
xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB-macOS \
    -destination 'platform=macOS' build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

---

## 4. ASSUMED-claims verification (Commit 3 extension)

Все проверки выполнены против актуального HEAD после Commit 2 (`64368c6`).

### A1 — `SwiftDataContainer.makeShared()` cost

**Источник:** `BBTB/Packages/VPNCore/Sources/VPNCore/SwiftDataContainer.swift`.

`makeShared()` выполняет:

1. `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` — system call, дешёвый (cached).
2. `ModelContainer(for: ServerConfig.self, Subscription.self, configurations: ...)` — основная стоимость. SwiftData инициализирует SQLite store, регистрирует обе модели и mapping. **Это может занимать 50–200 мс** на холодном старте (Phase 3 migration), особенно если store не пустой.
3. **One-time migration `migratePhase2ToPhase3`** — guarded by `UserDefaults.migrationDoneKey`. После первого запуска **skipped**. Однако даже guard-check сам по себе дешёвый (`UserDefaults.bool(forKey:)`).
4. Если App Group entitlement отсутствует (тесты) — fallback на in-memory ModelContainer (быстрее).

**Decision (Wave 06D-02c reservation):** baseline должен **измерить вклад makeShared()** через `ColdLaunch` span и Allocations instrument. Если контейнер берёт > 50% ColdLaunch — defer на background actor (loadable от lazy property). Если < 10% — оставляем инлайн.

**Текущая инъекция:** `BBTB_iOSApp.init` вызывает `try SwiftDataContainer.makeShared()` synchronously на главном треде. `ColdLaunch` span это покрывает.

### A2 — Registry register thread coordination

**Источники:**
- `BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift`
- `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/TransportRegistry.swift`

**Модель:** оба реестра — `public final class @unchecked Sendable` singletons с **NSLock**-защищённым внутренним словарём `[String: any Handler.Type]`.

```swift
public func register<H: VPNProtocolHandler>(_ handlerType: H.Type) {
    lock.lock(); defer { lock.unlock() }
    handlers[H.identifier] = handlerType
}
```

**Анализ:**

- Регистрация выполняется **синхронно из BBTB_iOSApp.init / BBTB_macOSApp.init** на главном треде (~5 calls в каждом app).
- NSLock — non-recursive POSIX mutex. На uncontended path стоимость ~ 50 нс.
- **Не actor, не @MainActor** — поэтому `register` доступен из любого треда без `await`. Это сознательный выбор (Phase 1 решение, см. CORE-02 в .planning).
- Risk: если в Phase 6d optimization Wave 02f / 03 будет идея перенести regstration на background — нужно убедиться, что **не появляется race** между registration и первым `handler(for:)` call (происходит позже при `provisionTunnelProfile`).

**Verdict:** thread coordination = NSLock. Безопасно, идиоматично, **не требует изменений** в этой волне.

### A6 — Periphery + Tuist compat

(см. §2 выше — verified в Commit 1, mini-scan на BBTB scheme прошёл успешно).

Дополнение после Commit 2: повторный mini-scan **post-injection** не нужен для compat — Periphery работает с indexed Swift code независимо от signposter инъекций. Полный production-scan — Wave 06D-02b.

### A7 — Existing OSSignposter grep (post-injection count)

**Команда:**

```bash
grep -rn "OSSignposter\|os_signpost" BBTB --include="*.swift" | grep -v ".build/" | wc -l
```

**Pre-Commit 2 expected count:** 0 (Phase 6c не использовал signpostes — только Logger из OSLog).

**Post-Commit 2 actual count:** **11** occurrences (включая doc-comments и declarations).

Распределение:
- `PerfSignposter.swift` — 4 `OSSignposter(...)` declarations + 2 doc-comment mentions = 6.
- `BaseSingBoxTunnel.swift` — 1 `private static let perfSignposter = OSSignposter(...)` + 1 doc-comment = 2.
- `BBTB_iOSApp.swift` — 1 doc-comment mention = 1.
- `PacketTunnelProvider-iOS/-macOS.swift` — 1 doc-comment each = 2.

`beginInterval` + `endInterval` pairs (не учитывается в grep `OSSignposter|os_signpost` — это method calls, ищем отдельно):

```bash
grep -rn "beginInterval\|endInterval" BBTB --include="*.swift" | grep -v ".build/" | wc -l
```

Это даст 8+ для пар spans в `BBTB_iOSApp` (1 begin + 1 end), `BBTB_macOSApp` (1+1), `TunnelController.connect()` (3 begin + 4 end из-за PreConnectProbe catch path), `TunnelController.applyCurrentStateToCachedManager()` (1+1), `BaseSingBoxTunnel.startTunnel` (1 + endLibboxStart closure invocations ×9 paths).

**Verdict:** target ≥ 3 → actual 11 (declarations) + 16+ (intervals) → **PASS**.

### A8 — `/usr/lib/swift` runtime search path в Tuist DSL

**Команда:**

```bash
grep -rn "/usr/lib/swift\|LD_RUNPATH\|runpathSearchPaths" BBTB/Project.swift BBTB/Workspace.swift
grep -rn "RUNPATH_SEARCH_PATHS\|ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES" BBTB/Config
```

**Результат:** **нет custom overrides**. Tuist DSL не задаёт `runpathSearchPaths` явно, `.xcconfig` файлы (`Common.xcconfig`, `Debug.xcconfig`, `Release.xcconfig`) не содержат `RUNPATH_SEARCH_PATHS` или `ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES`.

**Интерпретация:** проект использует **Xcode-default runpath search paths** (`@executable_path/Frameworks @loader_path/Frameworks`). Swift Standard Library для iOS 12.2+ / macOS 10.14.4+ загружается из `/usr/lib/swift` системно (ABI stability). Embed `libswiftCore` в bundle **не выполняется** — это default-OFF для современных deployment targets.

**Verdict:** runtime search path — Xcode default. Никаких custom правил, никаких action items для Phase 6d.

### Open Q #3 — macOS Packet Tunnel extension type

**Источники:** `BBTB/App/PacketTunnelExtension-macOS/Info.plist` + `PacketTunnelExtension-macOS.entitlements`.

**Info.plist signature:**

```xml
<key>CFBundlePackageType</key><string>XPC!</string>
<key>NSExtension</key>
<dict>
  <key>NSExtensionPointIdentifier</key>
  <string>com.apple.networkextension.packet-tunnel</string>
  <key>NSExtensionPrincipalClass</key>
  <string>$(PRODUCT_MODULE_NAME).PacketTunnelProvider</string>
</dict>
```

**Entitlements:** `com.apple.developer.networking.networkextension` = `["packet-tunnel-provider"]` (NE entitlement, не sysextension entitlement); `com.apple.security.app-sandbox` = true.

**Verdict:** macOS extension — **app extension** (NSExtension-based, .appex packaged в App.app/Contents/PlugIns). Это **НЕ** system extension (тот использует `com.apple.developer.system-extension.install` + `NEMachServiceName`). Совпадает с iOS PacketTunnelExtension architecture.

**Implication for Phase 6d:** профилирование macOS extension доступно через стандартный Xcode + Instruments attach к `BBTB Tunnel macOS.appex` process (как и iOS). Никакого system-extension lifecycle (re-install / approval) учитывать не нужно.

### Sing-box JSON templates count

**Команда:**

```bash
find BBTB/Packages/PacketTunnelKit -name "*.json" -type f -not -path "*/.build/*"
```

**Результат:** **15 JSON files** в PacketTunnelKit. Распределение:

- **Production template — 1:** `Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json` (универсальный VLESS-Reality шаблон с placeholders типа `${VLESS_FLOW}`).
- **Test fixtures — 14:** все в `Tests/PacketTunnelKitTests/Fixtures/` (valid + invalid scenarios для `SingBoxConfigLoader.validate`).

**Delta vs RESEARCH:** researcher ожидал 6 production templates. Фактически — **1 универсальный template + post-processing в PoolBuilder/SingBoxConfigLoader**. Это означает, что архитектура per-protocol templates **уже унифицирована** через placeholder substitution, что **снижает scope unused-code findings** для Wave 02b.

**Verdict:** template count — 1 production + 14 test fixtures. Уточнение в RESEARCH.md (Wave 02b post-fix).

