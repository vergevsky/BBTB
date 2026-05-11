## Purpose

This wiki is a structured, interlinked knowledge base for planning and creating a user-friendly VPN application that is protected from Russian TSPU.
Claude maintains the wiki. The human curates sources, asks questions, and guides the analysis.


## Folder structure


```
raw/          -- source documents (immutable -- never modify these)
wiki/         -- markdown pages maintained by Claude
wiki/index.md -- table of contents for the entire wiki
wiki/log.md   -- append-only record of all operations
prompts/      -- production prompts for Claude Code (e.g. v2 spec)
.planning/    -- GSD operational planning (PROJECT.md, ROADMAP.md, phases)
BBTB/         -- Xcode project root (создаётся на Phase 1; имя проекта BBTB, display name "Верни жука" / "Bring Back the Bug")
```


## Ingest workflow


When the user adds a new source to `raw/` and asks you to ingest it:

1. Read the full source document
2. Discuss key takeaways with the user before writing anything
3. Create a summary page in `wiki/` named after the source
4. Create or update concept pages for each major idea or entity
5. Add wiki-links ([[page-name]]) to connect related pages
6. Update `wiki/index.md` with new pages and one-line descriptions
7. Append an entry to `wiki/log.md` with the date, source name, and what changed

A single source may touch 10-15 wiki pages. That is normal.

## Page format

Every wiki page should follow this structure:

```markdown
# Page Title


**Summary**: One to two sentences describing this page.


**Sources**: List of raw source files this page draws from.


**Last updated**: Date of most recent update.


---


Main content goes here. Use clear headings and short paragraphs.


Link to related concepts using [[wiki-links]] throughout the text.


## Related pages


- [[related-concept-1]]
- [[related-concept-2]]
```


## Citation rules


- Every factual claim should reference its source file
- Use the format (source: filename.pdf) after the claim
- If two sources disagree, note the contradiction explicitly
- If a claim has no source, mark it as needing verification


## Question answering

When the user asks a question:


1. Read `wiki/index.md` first to find relevant pages
2. Read those pages and synthesize an answer
3. Cite specific wiki pages in your response
4. If the answer is not in the wiki, say so clearly
5. If the answer is valuable, offer to save it as a new wiki page

Good answers should be filed back into the wiki so they compound over time.


## Lint

When the user asks you to lint or audit the wiki:
- Check for contradictions between pages
- Find orphan pages (no inbound links from other pages)
- Identify concepts mentioned in pages that lack their own page
- Flag claims that may be outdated based on newer sources
- Check that all pages follow the page format above
- Report findings as a numbered list with suggested fixes


## Rules

- Never modify anything in the `raw/` folder
- Always update `wiki/index.md` and `wiki/log.md` after changes
- Keep page names lowercase with hyphens (e.g. `machine-learning.md`)
- Write in clear, plain language
- When uncertain about how to categorize something, ask the user
- Always giving an answer in Russian
- If there are abbreviations, provide their Russian translations in parentheses

---

## GSD Workflow (operational planning)

Параллельно с wiki поддерживается GSD planning в `.planning/`:

- `.planning/PROJECT.md` — описание проекта, core value, requirements, key decisions
- `.planning/REQUIREMENTS.md` — детальный список требований v1 с REQ-IDs
- `.planning/ROADMAP.md` — план по фазам с маппингом требований и success criteria
- `.planning/STATE.md` — текущее состояние, активная фаза, прогресс
- `.planning/config.json` — конфигурация GSD-агентов (mode=yolo, granularity=fine, model_profile=quality)
- `.planning/phase-N-<name>/` — артефакты конкретной фазы (SPEC.md, PLAN.md, VERIFICATION.md)

**Источник истины по составу релизов и архитектуре** — `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md`. ROADMAP.md и REQUIREMENTS.md производны от него.

**Wiki vs GSD** — разные типы артефактов:
- Wiki — долговременная **knowledge base** (концепты, методики, поверхность угроз, принятые решения). Растёт по мере проекта.
- `.planning/` — оперативное **планирование и исполнение** (что делать, в каком порядке, что готово). Меняется по мере прогресса фаз.

**Синхронизация при работе с GSD:**
1. После каждого важного шага в `.planning/` (новое решение, итог фазы, новый learning) — обновлять соответствующие страницы wiki, чтобы знание сохранялось долговременно.
2. Архитектурные решения (как R1–R6) фиксировать в `wiki/security-gaps.md` секция «Закрытые / принятые решения» (или в новой странице, если тема не про безопасность).
3. Не дублировать содержимое между `.planning/` и wiki — линковать. В `.planning/` указывать «см. `wiki/<page>.md`», в wiki можно указывать «оперативный план — `.planning/ROADMAP.md`».

**GSD commands** (запускает пользователь через `/<command>`):
- `/gsd-discuss-phase N` — обсудить контекст фазы перед планированием
- `/gsd-plan-phase N` — создать PLAN.md фазы
- `/gsd-execute-phase N` — выполнить план фазы
- `/gsd-verify-work N` — проверить достижение целей фазы
- `/gsd-progress` — посмотреть статус и продвинуть workflow
- `/gsd-autonomous` — выполнить все фазы автономно

**Правило, перенесённое из auto memory:** каждое архитектурное решение или технологический выбор, принятый в ходе GSD-работы, **обязательно** фиксируется в wiki — чтобы не возвращаться к нему повторно. Не оставлять решения только в `.planning/` (там оперативный план), переносить в wiki в формате «контекст, решение, обоснование, что становится TODO».