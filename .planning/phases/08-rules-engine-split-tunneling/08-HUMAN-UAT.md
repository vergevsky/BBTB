---
phase: 08-rules-engine-split-tunneling
doc_type: human-uat
created: 2026-05-15
scenarios: [M-04, M-05, M-07, M-08]
prerequisites:
  - Real iPhone with TestFlight build installed (iOS 18+)
  - Xcode with device connected (for Console.app / Simulate Background Fetch)
  - For M-07/M-08: admin VPS access to publish signed rules.json
---

# Phase 8 — Human UAT Instructions

Four scenarios require device-based validation. Automated checks have verified all code paths; these scenarios confirm end-to-end behavior in the real iOS environment.

---

## Required Setup

**For all scenarios:**
- Install latest BBTB TestFlight build on real iPhone (iOS 18+)
- Have one working VPN server subscription already imported
- Xcode Console.app available with device filter on `app.bbtb.client`

**For M-07 and M-08 only:**
- Admin VPS access: SSH + ability to publish signed `rules-manifest.json` to your CDN/VPS
- `build-baseline-rules.sh` production signing mode (`BBTB_BASELINE_SIGNING_KEY` set)
- Replace `productionMirrors` in `RulesEngineCoordinator.swift` with real VPS URL before build

---

## Scenario M-04: BGAppRefreshTask Cadence

**Tests:** RULES-04, CORE-05 — Background fetch fires on schedule

### Steps

1. Build with `productionMirrors` pointing at a real server (or a mock that returns HTTP 200 with any valid JSON).
2. Install on iPhone. Launch app. Verify it connects (normal VPN test).
3. Background the app completely (swipe up from home, not just home button).
4. Option A (Simulator): Xcode → Debug → Simulate Background Fetch. Check Console immediately.
   Option B (real device, ~6h wait): Leave phone on charger, screen off, connected to Wi-Fi. After ~6h, foreground the app and check Console.
5. In Console.app, filter by subsystem `app.bbtb.client`, category `rules-engine`:
   - Look for: `RulesEngineCoordinator.performBackgroundRefresh:`
   - If server returned valid rules: `success, version=X`
   - If server returned placeholder/error: `fetch failed:` (expected if no real server)
   - Either way, verify the task FIRED (log entry present)

### Expected

- Console shows a `performBackgroundRefresh` log entry originating from background context (not foreground)
- If real server: `bbtbRulesEngineDidUpdate` notification posted, SRS file mtime in App Group advances
- If placeholder server: network failure log, NO crash, rules unchanged (kept from baseline)
- **No crash, no freeze, no EXC_RESOURCE** during or after background task

### PASS criteria

- [ ] Task fires (Console log entry exists for performBackgroundRefresh)
- [ ] App does not crash
- [ ] If real server: file mtime advances in App Group Library/Caches/rules/

### FAIL criteria

- Task never fires after 6h on real device (iOS energy saver over-throttled — check Background App Refresh enabled in Settings)
- App crashes during background task
- EXC_RESOURCE / PORT_SPACE in crash log

---

## Scenario M-05: Real Domain Blocking On Device

**Tests:** RULES-05 — block_completely category enforces traffic drop

### Pre-flight check

Verify baseline SRS files are in App Group by running this in a Debug build or via Instruments:

```
App Group path: Settings → Privacy → VPN → tap BBTB → check that tunnel has been started at least once
```

The baseline includes `max.ru` in `block_completely`. This test works with the baseline (no server needed).

**Note on naming gap:** There is a known code gap where bootstrap copies `bbtb-baseline-block.srs` but sing-box config references `bbtb-block.srs`. If this scenario FAILS with "domain not blocked", that confirms the gap is active and requires the filename fix before rules enforce on first boot.

### Steps

1. Connect BBTB VPN tunnel on iPhone.
2. In Safari, navigate to `https://max.ru`. 
   - Expected: page does not load (connection reset / timeout)
3. Also test via Shortcuts "Get Contents of URL" action with URL = `https://max.ru` to see the actual error (not cached by Safari).
4. Navigate to a non-blocked domain (e.g. `https://apple.com`) — should load normally.
5. Test never_through_vpn scenario (requires custom signed rules with a test domain in never_through_vpn):
   - Navigate to a domain in never_through_vpn while connected
   - Check IP in response — should show your real ISP IP (not VPN IP)

### Expected

- `max.ru` request: connection refused / reset (sing-box action: reject)
- Normal domains: load correctly
- never_through_vpn domain: responds via direct ISP connection (non-VPN IP)

### PASS criteria

- [ ] max.ru blocked (connection fails) while connected to BBTB tunnel
- [ ] Normal domains unaffected
- [ ] Tunnel stays connected (no crash/disconnect) after blocked request

### FAIL criteria

- max.ru loads normally (rules not applied — likely filename gap or SRS not loaded)
- Tunnel disconnects on blocked domain
- Other domains are also blocked (priority ordering broken)

---

## Scenario M-07: Split-Tunnel Country Resolution

**Tests:** RULES-07 — country-based routing (server-side CIDR expansion per D-04)

**Requires:** Real admin VPS + signed rules with `countries: ["RU"]` in never_through_vpn

### Admin Setup (VPS side)

1. Edit `rules.json` on VPS to add `countries: ["RU"]` to `never_through_vpn`:
   ```json
   "never_through_vpn": {
     "domains": [],
     "ip_cidrs": [],
     "countries": ["RU"]
   }
   ```
2. Run VPS tooling to expand "RU" → CIDR set (requires MaxMind GeoLite2 + sing-box CLI + openssl):
   ```bash
   BBTB_BASELINE_SIGNING_KEY=/path/to/private.pem ./build-baseline-rules.sh
   # Upload output to CDN/VPS
   ```
3. Verify new manifest published at your rules URL.

### Client Steps

1. Build with real `productionMirrors` pointing to your VPS.
2. Install on iPhone. Trigger force-update in Settings → Advanced → "Принудительно обновить правила".
3. Verify in Advanced Settings viewer that `never_through_vpn` → Countries shows `["RU"]`.
4. Connect BBTB VPN tunnel.
5. Open Safari → navigate to `https://yandex.ru`.
6. Check what IP the response comes from: use `https://api.ipify.org` — if direct (not VPN), you'll see your ISP IP; if through VPN, you'll see VPN server IP.

### Expected

- Request to `yandex.ru` (Russian IP) → response via direct connection (non-VPN ISP IP)
- Request to `https://api.ipify.org` (non-RU) → VPN server IP
- Rules viewer shows Countries = ["RU"] under never_through_vpn

### PASS criteria

- [ ] RU-hosted IP goes direct while tunnel is connected
- [ ] Non-RU IP goes through VPN
- [ ] Rules viewer correctly displays country list after force-update

### FAIL criteria

- RU IPs go through VPN (country routing not applied)
- Non-RU traffic goes direct (routing broken for all traffic)
- Force-update fails (signature verification failure = key mismatch)

---

## Scenario M-08: min_app_version Sheet UX Flow

**Tests:** RULES-08, D-11 — Upgrade prompt sheet + persistent banner + @AppStorage durability

**Requires:** Real admin VPS OR a debug build workaround

### Option A: Real server (preferred)

Publish manifest with `min_app_version: "99.0.0"` (above any current build version).

### Option B: Debug build workaround (no server needed)

In `SettingsViewModel.swift`, temporarily change line 374:
```swift
// Temporarily force-show the sheet for testing:
let needsUpgrade = true  // was: snapshot.minAppVersion.compare(...)
```
Build and install debug build.

### Steps

1. Trigger rules fetch (force-update button OR wait for BG fetch with Option A).
2. App should display `MinAppVersionSheet` (modal sheet over main screen).
3. **Test dismissal:** Tap "Позже" (Later) button.
   - Sheet dismisses
   - Navigate to Settings → Advanced
   - Verify `MinAppVersionBanner` is still visible (persistent)
4. **Test durability:** Force-kill the app (swipe up from app switcher). Reopen app.
   - Sheet re-appears (because dismissed version was "99.0.0" and fetchedVersion is still "99.0.0")
5. **Test TestFlight link:** Tap "Открыть TestFlight" button.
   - TestFlight app opens (or App Store TestFlight page if TestFlight not installed)
6. **Test banner persistence:** With sheet dismissed, confirm banner in Advanced Settings shows orange arrow icon and "Доступна новая версия" text.
7. **Test banner tap:** Tap the banner.
   - TestFlight opens (same as primary button)

### Expected

- Modal sheet appears when min_app_version > current
- Sheet dismisses on either button tap
- Banner in Advanced Settings persists after sheet dismissal
- Force-kill → reopen → sheet re-appears (not permanently dismissed by single dismiss)
- TestFlight button opens TestFlight URL
- Banner tap opens TestFlight URL

### PASS criteria

- [ ] Sheet appears on version mismatch
- [ ] Sheet dismisses without crashing
- [ ] Banner persists in Advanced Settings after dismiss
- [ ] Force-kill → reopen → sheet re-appears
- [ ] TestFlight button opens correct URL
- [ ] Banner tap opens correct URL

### FAIL criteria

- Sheet does not appear
- Sheet dismissal permanently suppresses future appearances (wrong @AppStorage key)
- Banner absent after sheet dismissal
- TestFlight URL doesn't open (wrong URL scheme)

---

## Signaling PASS/FAIL

After running each scenario, record results in `.planning/phases/08-rules-engine-split-tunneling/` as:

```
08-UAT-M04: PASS / FAIL — [brief note]
08-UAT-M05: PASS / FAIL — [brief note]
08-UAT-M07: PASS / FAIL — [brief note]  
08-UAT-M08: PASS / FAIL — [brief note]
```

Or update this file's scenario status and re-run `/gsd-verify-work 8` to produce the final VERIFICATION.md with `status: passed`.

---

*Created: 2026-05-15*
*Phase: 8-rules-engine-split-tunneling*
