---
name: MAX-домены для block_completely (admin handoff)
description: Список доменов мессенджера MAX для добавления в rules.json — admin handoff документ для DETECT-03 (Phase 11 client-side ready; серверная задача)
type: project
---

# MAX-домены для добавления в `block_completely` правила

**Summary**: Phase 11 закрывает DETECT-01 / DETECT-02 (silent client-side detection факта установки MAX-мессенджера) через `MAXDetector.detectAndLog()`. DETECT-03 — серверная задача: администратор добавляет MAX-домены в `block_completely` секцию `rules.json` через [[rules-engine]] pipeline. Phase 8 RulesEngine клиента подхватит изменения автоматически в течение ≤6 часов (BGAppRefreshTask на iOS / NSBackgroundActivityScheduler на macOS). **Никакого client code change для DETECT-03 не требуется.**

**Sources**: [[vpn-detection-by-apps]], [[max-messenger]], `.planning/phases/11-onboarding-ux-polish/11-CONTEXT.md` § D-Detect, `.planning/phases/08-rules-engine-split-tunnel/08-CONTEXT.md` § D-01 sing-box rule_set pipeline

**Last updated**: 2026-05-15 (Phase 11 Plan 04 closure — handoff документ создан)

---

## Контекст и связь с другими страницами

- **Что делает клиент (Phase 11 ✓):** `MAXDetector.detectAndLog()` — silent best-effort detection при cold start (iOS: `UIApplication.canOpenURL("max://"...)`, macOS: `NSWorkspace.shared.urlForApplication(...)`). Результат пишется в `os.Logger(category: "detection")` — никакого UI side-effect. См. [[max-messenger]] и `.planning/phases/11-onboarding-ux-polish/11-04-PLAN.md`.
- **Что делает админ (этот документ, DETECT-03):** добавляет домены MAX в `rules.json` через тот же [[rules-engine|server-side pipeline]], который уже работает с Phase 8 (v0.8). Подписывает Ed25519, публикует. Клиент скачивает обновление в ближайший 6-часовой interval.
- **Где не пересекаются:** клиент НЕ держит hardcoded список MAX-доменов в коде. Это сервер-side и должно туда оставаться — иначе при изменении инфраструктуры MAX (новые домены, CDN-мирроры) пришлось бы выпускать новый билд клиента.

См. также [[rules-engine]] § «Иерархия и приоритеты» — `block_completely` имеет высший приоритет, соединения дропаются вне зависимости от состояния VPN и пользовательских настроек.

## Список доменов для добавления

> **Маркировка**: домены без пометки — наблюдаемые / документированные. Домены с пометкой `[ASSUMED]` — предположения, требуют независимой верификации админом перед добавлением в production rules.json (см. § «Verification protocol» ниже).

| # | Домен | Назначение | Статус |
|---|-------|------------|--------|
| 1 | `max.ru` | Основной домен MAX | подтверждён (источник: `wiki/max-messenger.md` § Контекст) |
| 2 | `mssgr.tatar.ru` | VK-инфраструктура MAX (исторически наблюдалось до ребрендинга) | подтверждён (источник: `wiki/max-messenger.md` § Блокировка через rules.json) |
| 3 | `api.max.ru` | API endpoint (assumed по стандартному паттерну под-доменов) | `[ASSUMED]` — верифицировать через `dig api.max.ru +short` и сравнить с `max.ru` |
| 4 | `cdn.max.ru` | CDN для media-content (assumed CDN-pattern; может быть на стороннем CDN типа Cloudflare/Akamai с разными hostname'ами) | `[ASSUMED]` — верифицировать через tcpdump capture при отправке media в MAX |
| 5 | `static.max.ru` | Static assets (logos, emoji-packs, web-ассеты) | `[ASSUMED]` — верифицировать через `Charles Proxy` / `mitmproxy` snapshot |
| 6 | `apk.max.ru` | APK distribution для Android sideload (если применимо к iOS — нет, но добавляем для парного coverage) | `[ASSUMED]` — verify через 302 redirect target из `https://max.ru/download` |
| 7 | `auth.max.ru` | Authentication endpoint (assumed по обычному `auth.<domain>` паттерну) | `[ASSUMED]` — может быть unified с `id.vk.com` если MAX shares VK auth (см. § Open questions) |

**Минимум 5 доменов** (PRD acceptance criterion 11-04-PLAN.md): пункты 1-5 закрывают требование. Остальные — рекомендуемые для расширения coverage.

### JSON-фрагмент для rules.json

```json
{
  "block_completely": {
    "domains": [
      "max.ru",
      "mssgr.tatar.ru",
      "api.max.ru",
      "cdn.max.ru",
      "static.max.ru",
      "apk.max.ru",
      "auth.max.ru"
    ]
  }
}
```

> ⚠️ **Перед production:** удалите либо verify'те все `[ASSUMED]` записи. False positive (блокируем домен, который не принадлежит MAX) приведёт к broken third-party сервису у пользователей. False negative (пропускаем реальный MAX-домен) — MAX продолжит работать, но это менее критично, чем breakage other apps.

## Verification protocol для админа

Перед коммитом обновлённого `rules.json` в [[rules-engine|server-side pipeline]]:

### Шаг 1 — DNS baseline

Для каждого `[ASSUMED]` домена:

```bash
dig <домен> +short
# или
host <домен>
```

Проверка:
- Возвращает ли IP?
- IP принадлежит ли VK / Mail.ru Group / Ростелекому (`whois <ip>` — поле OrgName)?
- TTL разумный (≥60s)? Очень короткий TTL — признак anti-block load-balancer, домен живой.

### Шаг 2 — Traffic capture с реального устройства

Установить MAX на тестовое iOS / Android устройство. Подключить через test-VPN или WiFi с прозрачным mitmproxy:

```bash
# macOS / Linux на router-машине:
sudo tcpdump -i any -n 'host max.ru or host mssgr.tatar.ru' -w max-trace.pcap
# Затем открыть MAX, поскроллить чат, открыть call, открыть Settings.
# Анализ:
tshark -r max-trace.pcap -T fields -e ip.dst -e dns.qry.name | sort -u
```

Все hostname'ы, которые появятся в SNI / DNS queries — кандидаты для добавления. Cross-check с § Список доменов выше; новые → добавить в rules.json.

### Шаг 3 — Sign + publish через build-baseline-rules.sh

После верификации:

```bash
# В директории scripts/ репозитория VPS:
./build-baseline-rules.sh --input rules.json --output dist/
# Выводит:
#   dist/rules.json
#   dist/rules.json.sig
#   dist/block.srs
#   dist/block.srs.sig
#   ...
# Upload dist/* в primary VPS + 3 mirror'а.
```

Клиент через [[rules-engine|RulesEngineCoordinator]] заметит обновление в течение ≤6 часов (BGAppRefreshTask iOS / NSBackgroundActivityScheduler macOS — см. Phase 8 Plan W4).

### Шаг 4 — Monitoring после публикации

В течение 24 часов после publish:

- Мониторить `os.Logger(category: "detection")` на тестовых устройствах — должны видеть запись `MAX-app detected via scheme: max` при наличии MAX.
- Мониторить sing-box.log: запросы к заблокированным MAX-доменам должны returning `reject` (см. Phase 8 D-01 priority rules `block→reject`).
- Если пользователь сообщает breakage другого сервиса — проверить, не пересекается ли его домен с одним из `[ASSUMED]` в block_completely. При false positive — удалить и republish.

## Closure dependency для DETECT-03

**REQ DETECT-03 status:**

- **Client-side (Phase 11):** ✅ Validated — MAXDetector silent detection реализован, AppFeatures 178/178 тестов PASS, никаких client-side rules.json changes (правильно — должно быть server-side).
- **Server-side (admin handoff):** ⏸ Pending — admin применяет этот документ:
  1. Verify домены по § «Verification protocol»
  2. Update `rules.json` на VPS
  3. Run `build-baseline-rules.sh` + sign + upload
  4. Monitor 24h
  5. Mark DETECT-03 as `⚙️ Infrastructure-validated` в REQUIREMENTS.md (паттерн как Phase 10 DPI-06 CDN fronting closure)

## Open questions

- **MAX shares VK auth?** — `auth.max.ru` vs `id.vk.com` — какой реальный auth endpoint? Может быть unified с VK SSO (тогда `id.vk.com` нельзя блокировать без breakage ВКонтакте). Требует traffic capture при первом логине в MAX.
- **MAX через CloudFront / Akamai?** — если MAX использует сторонний CDN, hostname'ы там — `dxxxxxxxxx.cloudfront.net`, и блок per-CDN-hostname будет over-broad (заденет другие сервисы). Альтернатива: блокировать только по DNS-уровню (resolve `cdn.max.ru` → знать IP-диапазон → блок per-IP), но это требует обновления при ротации CDN. Phase 8 sing-box rule_set поддерживает оба варианта (`domain_keyword`, `ip_cidr`).
- **Detection vs blocking — какой UAT-сценарий?** — если пользователь установит MAX уже после блокировки доменов, MAX-app будет показывать infinite loading. Нужно ли FAQ entry «MAX не работает — установлен ли он на устройстве?». См. [[max-messenger]] § App Store risk и Phase 11 LOC-03 FAQ scope.

## Related pages

- [[max-messenger]]
- [[rules-engine]]
- [[vpn-detection-by-apps]]
- [[security-gaps]]

---

*(source: wiki/vpn-detection-by-apps.md, wiki/max-messenger.md, .planning/phases/11-onboarding-ux-polish/11-04-PLAN.md, .planning/phases/08-rules-engine-split-tunnel/08-CONTEXT.md — Phase 8 RulesEngine pipeline, Phase 11 DETECT-01..03 vertical slice)*
