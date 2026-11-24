# Бриф для нового чата

Скопируй текст ниже в новый чат.

---

Проект: `C:\myGames3D\three-skies` (Godot 4.7, GDScript, Go-сервер, веб-сборка на RelaxDev).

Сначала прочитай:
- `AGENTS.md` — состояние проекта, деплой, правила;
- `docs/PLATFORM-ADAPTERS.md` — чистое ядро + адаптеры VK/OK/Yandex;
- `docs/DIFFICULTY-PLAN.md` — обучение 1→2→3 бота и новичковый пул;
- `docs/VK-COMPLIANCE.md` — аудит требований VK и блокеры.

Текущий прод: PCK `48 925 168`, `main` `9272be6`, вход `?v=20261124_062608`,
`/health` ok (`live_matches=0`). Исходники — ветка `mobile-ui`.

Цель: одна чистая игра без SDK в ядре + тонкие адаптеры и отдельные сборки
`web-standalone`, `web-vk`, `web-ok`, позже `web-yandex`.

## M1 — выполнен 24.11.2026

- Autoload `Platform` + `PlatformAdapter`, `StandaloneAdapter`, заглушки
  VK/OK/Yandex; выбор по feature tags `web-vk`/`vk`, `web-ok`/`ok`,
  `web-yandex`/`yandex`, иначе standalone.
- `AdManager` и `shard_topup_panel` больше не mock: только `Platform.*`.
  В standalone «Купить осколки», оплата и «x2 за рекламу» скрыты.
- Сборки `Web Standalone` (`build/web`) и `Web VK` (`build/web-vk`);
  `python tools/web_export.py --platform standalone|vk`.
- Проверки и размеры — `docs/QA-M1.md`. Прод не тронут.

## Следующая задача — D1

Обучение 1→2→3 бота, обязательный первый запуск, скип, экран правил;
новичковый пул ~10 матчей, уровни ботов easy/normal/hard, серверный
`matches_played`/`novice`, телеметрия.

## Следующие этапы (после D1)

- **M2**: VK-авторизация: launch params, `sign`, `vk_user_id`, серверный профиль.
- **M3**: юридика/возраст/согласие/удаление данных/поддержка.
- **M4**: реальные VK Ads/Голоса, серверная проверка платежей.
- **M5**: OK-адаптер (VK Bridge, `local_access_token`, ОКи, OK-ссылки).
- **M6**: Yandex-адаптер.

## Что нужно уточнить у пользователя

1. VK APP_ID и APP_SECRET (или доступ к Панели VK).
2. OK APP_ID/ключи.
3. Каталог VK: игры или сервисы.
4. Переносить ли старые локальные профили в VK/OK.
5. Юридические тексты/ИП/поддержка.
6. Приоритет монетизации: rewarded ads или VK Голоса.

## Правила работы

- Одна кодовая база, не форкать игру под площадки.
- В ядре нет `VKWebApp...`/`ysdk...`.
- В магазинных сборках нет mock-оплаты и фейковой рекламы.
- Перед деплоем: `/health.live_matches == 0`, затем PCK/HTML и `/health`.
- После изменений: diff, проверки сцен, `go test`, кадры/скриншоты для UI.
- Ничего не менять в геймплее/балансе без прямой просьбы.
