# Тест ЄДКІ — Інфекційна дерматологія (6 курс)

Сторінки лежать у `site/` і публікуються через GitHub Pages. Результати зберігаються в Supabase.

- `site/index.html` — тест для студентів: група → прізвище → 30 випадкових питань, таймер, одна спроба.
- `site/teacher.html` — сторінка викладача (пароль): відкрити/закрити тест, результати, аналіз питань, експорт в Excel, скидання спроби.
- `supabase/schema.sql` — таблиці й функції. Оцінювання на сервері; ключів відповідей на сторінках немає.

Банк питань і списки груп (`private/`) у репозиторій не потрапляють — вони завантажуються в Supabase через `private/seed.sql`.

## Запуск
1. supabase.com → New project. SQL Editor → вставити `supabase/schema.sql` (замінити пароль `zmini-mene` в кінці) → Run.
2. SQL Editor → вставити `private/seed.sql` → Run.
3. Project Settings → API → скопіювати Project URL і anon public key у `site/config.js`.
4. GitHub → Settings → Pages → Source: GitHub Actions (workflow вже є).
5. На `…/teacher.html` відкрити тест.

Шкала: ≥90 % — відмінно (A), 82 — B, 74 — добре (C), 64 — D, 60 — задовільно (E), 35 — FX, нижче — F.
