# Phase 11: Onboarding + UX polish — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-15
**Phase:** 11-onboarding-ux-polish
**Areas discussed:** Onboarding (UX-01), Анимации кнопки (UX-08), Figma макеты (UX-09), FAQ + Log export (LOC-03/TELEM-02)

---

## Onboarding (UX-01)

### Когда показывать

| Option | Description | Selected |
|--------|-------------|----------|
| Только первый запуск | UserDefaults флаг «shown_once» навсегда | ✓ |
| Всегда доступен | Кнопка в Settings открывает onboarding-шит | |

**User's choice:** Только первый запуск — даже если все серверы удалены, онбординг больше не показывается.
**Notes:** Пользователь явно уточнил это — не первый запуск «пока серверов нет», а буквально один раз за всё время.

---

### Структура экрана

| Option | Description | Selected |
|--------|-------------|----------|
| Только импорт | Заголовок + подзаголовок + 2 CTA | ✓ |
| Импорт + описание | Краткая строка про обход ТСПУ над кнопками | |

**User's choice:** Заголовок + подзаголовок + две кнопки «Вставить из буфера» и «Сканировать QR». Никаких слайдов, никаких объяснений что такое VPN.

---

### Переход после импорта

| Option | Description | Selected |
|--------|-------------|----------|
| Главный экран сразу | Onboarding исчезает, виден главный экран с сервером | ✓ |
| Короткая анимация успеха | Checkmark/celebration момент, потом главный экран | |

**User's choice:** Главный экран сразу, без промежуточных шагов.

---

### IMP-03 (file picker) в Onboarding

| Option | Description | Selected |
|--------|-------------|----------|
| Маленькая ссылка под кнопками | «У меня есть файл конфигурации» — серый текст | |
| Отдельная третья кнопка | 3 CTA на экране | |
| Не нужен в Onboarding | File picker только через меню «+» на главном экране | ✓ |

**User's choice:** Не нужен в Onboarding.
**Notes:** Решение Phase 2 (угловая ссылка) пересмотрено — пользователь упростил.

---

## Анимации кнопки (UX-08)

| Option | Description | Selected |
|--------|-------------|----------|
| Пульсация при connecting | Scale + opacity repeating animation | |
| Пульсация + glow при connected | Shadow blur + meditate-пульсация | |
| Только цвет + withAnimation | Плавная смена цвета, без repeating | |
| Спиннер по Figma | Пользователь опишет в макете | ✓ |

**User's choice:** Спиннер при connecting. Точный вид — в Figma.
**Notes:** «Я думал о спинере. Покажу в Figma» — решение отложено до передачи макетов.

---

## Figma макеты (UX-09)

**Ситуация:** Пользователь рисует дизайн в Figma параллельно с обсуждением. Запросил spec-файл.

**Действие:** Создан `11-FIGMA-SPEC.md` — перечень экранов и элементов для отрисовки с текущими константами высот из кода.

**Порядок приоритетов в Figma-SPEC:**
1. Connection Button состояния (блокирует UX-08)
2. Onboarding Screen (нет кода)
3. FAQ / Help (нет кода)
4. Server List Sheet высоты (блокирует корректное открытие)
5. Main Screen polish
6. Log export кнопка

---

## FAQ + Log export

### Расположение FAQ

| Option | Description | Selected |
|--------|-------------|----------|
| Кнопка в Settings → отдельный экран | NavigationLink → HelpView | ✓ |
| Секция внутри Settings | DisclosureGroup прямо в Settings Form | |
| Кнопка «?» в Top Bar | Sheet с FAQ | |

**User's choice:** Кнопка «Помощь» в Settings → NavigationLink → отдельный HelpView.

---

### Расположение Log export

| Option | Description | Selected |
|--------|-------------|----------|
| Секция «Диагностика» в Settings | Отдельный Section под остальными | ✓ |
| Внутри FAQ/Help экрана | В конце Help экрана | |
| В Advanced Settings | Рядом с техническими настройками | |

**User's choice:** Секция «Диагностика» в Settings.

---

### Способ отправки лога

| Option | Description | Selected |
|--------|-------------|----------|
| Нет backend, добавим позже | Placeholder URL в коде | |
| Есть URL, введу сейчас | — | |
| Share Sheet (UIActivityViewController) | Пользователь сам выбирает куда отправить | ✓ |

**User's choice:** Share Sheet.
**Notes:** Пользователь попросил объяснить третий вариант подробнее. После объяснения (стандартный системный попап «Поделиться», без backend, подходит для TestFlight friends-and-family) — выбрал Share Sheet.

---

## Claude's Discretion

- Точный текст заголовка/подзаголовка Onboarding на ru/en
- Структура HelpView (DisclosureGroup vs статический ScrollView)
- Анонимный device-id реализация (identifierForVendor vs UserDefaults UUID)
- Момент вызова MAX-detection (при запуске vs при подключении)
- ShareLink vs UIActivityViewController (рекомендую ShareLink — кроссплатформенно)

## Deferred Ideas

- Backend для log export — при росте аудитории TestFlight (100+), Phase 12+
- Onboarding доступность из Settings — не нужна по D-01
- NET-12, Config editor, Network diagnostics — carry-over deferred Phase 12+
