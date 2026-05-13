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

## 4. Дальнейшее расширение (Commit 3)

Этот раздел будет **заполнен в Commit 3** — после инъекций signposts (Commit 2):

- **A1** — SwiftDataContainer.makeShared() cost (нужен ли deferral)
- **A2** — Registry register thread coordination (`ProtocolRegistry` + `TransportRegistry`)
- **A6** — Periphery + Tuist compat (уже здесь, повтор для полноты)
- **A7** — Post-injection OSSignposter grep count (ожидаемо ≥3)
- **A8** — `/usr/lib/swift` runtime search path в Tuist DSL
- **Open Q #3** — macOS Packet Tunnel extension type (app vs system extension)
- **Sing-box JSON templates count** — `find BBTB/Packages/PacketTunnelKit -name "*.json" | wc -l`

Подробности — после Commit 2.
