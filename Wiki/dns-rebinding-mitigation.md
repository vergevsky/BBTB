---
name: DNS-rebinding mitigation
description: Анализ DNS-rebinding атаки против SubscriptionURLFetcher, текущие защитные слои и accepted residual risk
type: project
---

# DNS-rebinding mitigation

**Summary**: DNS-rebinding атака позволяет хосту с контролем DNS обойти hostname-based SSRF блоклист, манипулируя TTL: первый resolve возвращает публичный IP (проходит guard), последующие — loopback/private. Этот документ описывает атаку, текущие защитные слои в BBTB и принятый residual risk.

**Sources**: [[security-gaps]] R15 (Phase 3 SSRF guard), R25 (Phase 13 hardening), AUDIT-2.md (Plan 04 audit A4'-001)

**Last updated**: 2026-05-17 (Phase 13 Plan 05)

---

## Что такое DNS-rebinding

Атака на TOCTOU (time-of-check-to-time-of-use) семантику hostname-based блоклистов:

1. **Setup.** Атакующий контролирует DNS для `evil.example.com` (через свой authoritative DNS server или DDNS сервис).
2. **Initial resolve.** Жертва (client) запрашивает `https://evil.example.com/subscription` — DNS возвращает `203.0.113.5` (публичный IP сервера атакующего). Hostname-based check `isBlockedHost("evil.example.com")` → `false` (публичный hostname, не в blocklist).
3. **TLS + handshake.** Client устанавливает TCP+TLS к `203.0.113.5`. Если есть HTTPS-only enforcement (BBTB enforces), handshake проходит с валидным cert для `evil.example.com`.
4. **TTL=0 + re-resolve.** Server отвечает `Cache-Control: no-cache` и `DNS TTL=0`. На следующий redirect или повторный DNS lookup (i.e., second request в session), DNS теперь возвращает `127.0.0.1`.
5. **SSRF.** Client делает request к `127.0.0.1` через **тот же hostname** `evil.example.com` — hostname-check продолжает пропускать. Loopback service (e.g., local Redis, metadata server, dev API) теперь доступен атакующему.

## Как BBTB защищается сегодня

`SubscriptionURLFetcher.isBlockedHost()` (после Plan 05 / T-A3'):

- **IP literal detection.** Использует `Network.framework` `IPv4Address` / `IPv6Address` для **numeric** разбора. Если host в URL — это IP literal (`https://127.0.0.1/sub` или `https://[::ffff:7f00:1]/sub`), мы детектим loopback/RFC1918/multicast/ULA/link-local **из 16-байтового представления**, а не из строки. Это закрывает обход через non-canonical формы (`::ffff:7f00:1` ≡ `127.0.0.1`).
- **Hostname check.** Если host не parsed как numeric IP — это hostname. Hostname сам по себе не в blocklist (мы блокируем только литералы; hostnames общего вида проходят). DNS rebinding bypass возможен здесь.
- **HTTPS-only.** Schema enforce — отвергаем `http://` (открытый канал) и custom schemes.

`HTTPSRedirectGuard.willPerformHTTPRedirection` (после Plan 05 / T-B1'):

- Validates redirect destination host **строкой** через тот же `isBlockedHost()`. Не помогает против повторного DNS resolve по тому же hostname (атака на DNS TTL).

`PinnedSessionDelegate` (после Plan 05 / T-B1'):

- TLS pinning (когда production keys будут опубликованы — placeholder на v1.0). Connection к loopback не пройдёт TLS handshake, потому что cert не match'ит для `127.0.0.1` (cert выдан для `evil.example.com`).

## Защитные слои (defence-in-depth)

| Слой | Защищает от | Не защищает от |
|---|---|---|
| 1. HTTPS-only + URL scheme check | HTTP plaintext, custom schemes | DNS rebinding (HTTPS не мешает) |
| 2. `isBlockedHost()` numeric IP parsing | IP literal в URL (`https://127.0.0.1/`, non-canonical IPv6-mapped) | Hostnames общего вида |
| 3. `HTTPSRedirectGuard` redirect host validation | Redirect к IP literal в private range | Same-hostname re-resolve (DNS TTL=0) |
| 4. TLS certificate pinning (Phase 10 / R21, real keys v1.1+) | Atttacker-controlled cert для loopback (не match'ит pin) | Compromised CA (rare); local cert override (jailbreak only) |
| 5. **(NOT IMPLEMENTED)** Post-connection `URLSessionTaskMetrics.remoteAddress` numeric check | DNS rebinding после connection establishment | Streaming case (data leaked до metric collection) |

## Почему accepted residual risk для v1.0

1. **Production subscription URLs always HTTPS** с валидным cert от public CA. Атакующий не может выдать cert для `127.0.0.1` без compromising CA infrastructure (расширенный attack surface, beyond обычной DNS rebinding).
2. **TLS pinning** (когда подключим production keys в v1.1+) делает TLS handshake к non-pinned loopback service невозможным даже при rebinding.
3. **Subscription flow rare и user-initiated** — нет periodic polling без явной user setup. Attack window — момент Save Subscription, narrow.
4. **`URLSessionTaskMetrics.remoteAddress` enhancement** требует metrics collection wiring, который мы пока не используем для diagnostics. Когда добавим (если будем) для perf/error telemetry — заодно сделаем blocklist post-check.

## Что станет TODO (v1.1+)

- [ ] **Post-connection IP check.** В `URLSessionTaskDelegate.urlSession(_:task:didFinishCollecting:)` извлечь `task.metrics.transactionMetrics.first?.remoteAddress`, parse как `IPv4Address`/`IPv6Address`, прогнать через `isBlockedHost` numeric path. Reject response если remote был loopback/RFC1918/multicast/ULA. Trade-off: late detection (после headers получены), не покрывает streaming responses.
- [ ] **Документировать в README.** «Subscription URL должен быть HTTPS. HTTP отвергается by design. Production URLs должны иметь валидный cert от public CA.»
- [ ] **Дополнительный telemetry** для subscription fetch failures — agregating «cert pin failed» events может выявить targeted rebinding attempts.

## Связанные страницы

- [[security-gaps]] — R15 (original SSRF guard), R21 (DPI-08 cert pinning), R25 (Phase 13 hardening detailed table)
- [[cert-pinning-spki]] — SPKI cert pinning design (Phase 10 / DPI-08)
- [[config-importer]] — где SubscriptionURLFetcher fits в pipeline
- [[anti-dpi-techniques]] — broader DPI evasion context

## Cross-references (внешние)

- OWASP — [DNS Rebinding entry](https://owasp.org/www-community/attacks/DNS_Rebinding)
- Phase 13 audit findings — `.planning/phases/13-testflight-internal-distribution/AUDIT-2.md` § A4'-001
