# Платформенные адаптеры: VK Games + Yandex Games

## Цель

Одна чистая игра без SDK в ядре. Под каждую площадку — тонкий адаптер и отдельная
сборка. Не форкать геймплей и не держать две копии проекта.

```
Игровое ядро (без VK/Yandex SDK)
  геймплей, UI, бой, магазин, скины, сохранения
        │
Platform (autoload) — стабильный интерфейс
  ├── StandaloneAdapter  — тест/свой сайт, без SDK
  ├── VKAdapter          — VK Bridge, VK Голоса, VK Ads
  └── YandexAdapter      — Yandex Games SDK, платежи, реклама
        │
Сборки: web-standalone / web-vk / web-yandex
```

Ядро не вызывает `VKWebApp...` или `ysdk...` напрямую. Только `Platform.*`.

## Интерфейс Platform

```gdscript
Platform.platform_id            # "standalone" | "vk" | "yandex"
Platform.get_user()             # {id, name, avatar, platform}
Platform.get_launch_token()     # строка/JSON для серверной проверки
Platform.is_ready()
Platform.show_rewarded_ad(placement) -> bool
Platform.show_interstitial(placement) -> bool
Platform.purchase(sku) -> {success, receipt}
Platform.load_cloud() -> Dictionary
Platform.save_cloud(data) -> bool
Platform.track(event, payload)
Platform.on_pause / on_resume
```

Адаптер выбирается по feature tag (`vk`, `yandex`) или по параметрам запуска.
По умолчанию — Standalone.

## Сервер: идентичность

Один Go-сервер, но профиль привязан к площадке:

```
players:
  id            BIGSERIAL PK
  platform      TEXT      -- vk | yandex | standalone
  external_id   TEXT      -- vk_user_id / yandex player id
  nickname      TEXT
  ...
  UNIQUE (platform, external_id)
```

- VK: `/auth/vk` принимает launch params, проверяет `sign` секретом приложения
  (`VK_APP_SECRET`), проверяет свежесть `vk_ts`, создаёт/находит профиль.
- Yandex: `/auth/yandex` — проверка player-токена через Yandex API.
- Старые локальные `player_id` остаются для Standalone; для VK — новый профиль
  или одноразовая привязка (решить отдельно).
- Прогресс (уровни, XP, скины, оружие, осколки) — на сервере, не в `user://`.

## Сборки

Три export preset:

1. **Web Standalone** — без SDK, для теста и своего сайта.
2. **Web VK** — `index.html` грузит `vk-bridge.min.js`; включён `vk` feature;
   в PCK только `VKAdapter`.
3. **Web Yandex** — `index.html` грузит Yandex SDK; включён `yandex` feature;
   в PCK только `YandexAdapter`.

Чужие SDK и адаптеры в сборку не попадают. `tools/web_export.py` и
`tools/patch_chunk_loader.py` должны принимать платформу и не вставлять
VK Bridge в Yandex/Standalone.

## Этапы

### M1. Ядро + Standalone (безопасно, без изменения геймплея)

- Добавить `Platform` autoload и базовый `PlatformAdapter`.
- `StandaloneAdapter`: локальный пользователь, реклама/платежи возвращают
  «недоступно», облако — локальный файл.
- Перевести `AdManager` и `shard_topup_panel` на `Platform.*`.
- Убрать фейковые таймеры рекламы и mock-оплату из публичных сборок.
- Добавить feature tags/export presets.
- Критерий: игра запускается как раньше, Standalone-сборка без SDK, магазин
  не показывает фейковую оплату.

### M2. VK-авторизация

- `VKAdapter`: парсинг launch params, `VKWebAppGetUserInfo` (по желанию),
  `get_launch_token`.
- Сервер: `platform/external_id`, `/auth/vk`, проверка `sign`.
- Клиент: вход через VK, ник — отображаемое имя, без отдельной регистрации.
- Критерий: два разных VK-пользователя получают разные серверные профили;
  поддельный `sign` отклоняется.

### M3. Юридика и первый запуск

- Экран возраста, пользовательское соглашение, политика конфиденциальности,
  чекбокс согласия; блокировка игры до принятия.
- Ссылки в Панели VK.
- Удаление аккаунта/данных на сервере + кнопка в настройках.
- Контакт поддержки/сообщество и данные разработчика.

### M4. VK-монетизация

- Rewarded/interstitial через VK Ads (не mock).
- VK Голоса для виртуальных ценностей (осколки/скины) через VK Bridge.
- Серверная проверка платежей VK.
- Убрать «Купить осколки» и «x2 за рекламу», если адаптер не готов.

### M5. Yandex-адаптер

- Yandex SDK init, player, cloud saves, платежи, реклама, лидерборды,
  локализация, возраст.
- Отдельная сборка и отдельные тексты, без упоминаний VK.

## Открытые вопросы

1. Есть ли VK APP_ID и `VK_APP_SECRET` (или доступ к Панели VK)?
2. Каталог: **игры** (нужна монетизация) или сервисы?
3. Переносить ли старые локальные профили в VK или начать с чистых?
4. Юридические тексты/ИП/контакты поддержки — кто предоставляет?
5. Приоритет монетизации: сначала rewarded ads или VK Голоса?
6. Нужен ли Standalone-билд для itch/своего сайта как отдельный продукт?

## Файлы

- `scripts/platform/platform.gd` — autoload.
- `scripts/platform/platform_adapter.gd` — базовый интерфейс.
- `scripts/platform/standalone_adapter.gd`
- `scripts/platform/vk_adapter.gd`
- `scripts/platform/yandex_adapter.gd`
- `tools/web_export.py`, `tools/patch_chunk_loader.py` — платформенные шаблоны.
- `server/main.go`, `server/ws.go` — auth/platform profile.
- `docs/PLATFORM-ADAPTERS.md` — этот файл.

## Текущее состояние

- Прод: PCK 48 925 168, `main` `9272be6`, вход `?v=20261124_062608`.
- VK Bridge уже подключён в `index.html`, но VK-авторизации/launch params нет.
- `AdManager` и `shard_topup_panel` — mock, в публичную сборку так нельзя.
- Прогресс частично локальный (`player_id`, уровни/XP), сервер — осколки/скины.

## Правило

Перед деплоем проверять `/health.live_matches == 0`; не рвать живые матчи.
