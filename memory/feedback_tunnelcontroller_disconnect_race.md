---
name: TunnelController disconnect/connect race — ждать .disconnected перед connect
description: stopVPNTunnel fire-and-forget; немедленный startVPNTunnel видит .disconnecting и бросает ошибку
type: feedback
---

После `stopVPNTunnel()` нельзя сразу вызывать `startVPNTunnel()` — туннель ещё в `.disconnecting`.

**Why:** `stopVPNTunnel()` огонь-и-забудь. `connect()` поллит статус и видит `.disconnecting` → бросает "Connection failed". Проявляется при reconnect-on-selection-change (T6 UAT Phase 3).

**How to apply:** `disconnect()` должен поллить до `.disconnected`/`.invalid` (max 5s, шаг 0.5s) перед return. `connect()` должен трактовать `.disconnecting` как transient state (continue polling), не как terminal failure. Реализовано в `TunnelController.swift` коммит `b5d3120`.
