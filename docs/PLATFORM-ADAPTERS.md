# Платформенные адаптеры: VK Games + Одноклассники + Yandex Games

## Цель

Одна чистая игра без SDK в ядре. Под каждую площадку — тонкий адаптер и отдельная
сборка. Не форкать геймплей и не держать две копии проекта.

```
Игровое ядро (без VK/OK/Yandex SDK)
  геймплей, UI, бой, магазин, скины, сохранения
        │
Platform (autoload) — стабильный интерфейс
  ├── StandaloneAdapter  — тест/свой сайт, без SDK
  ├── VKBridgeBase       — общая обвязка VK Bridge
  │     ├── VKAdapter    — VK Голоса, VK-ссылки, VK-методы
  │     └── OKAdapter    — ОКи, OK-ссылки, local_access_token
  └── YandexAdapter      — Yandex Games SDK, платежи, реклама
        │
Сборки: web-standalone / web-vk / web-ok / web-yandex
```

Ядро не вызывает `VKWebApp...` или `ysdk...` напрямую. Только `Platform.*`.

## Интерфейс Platform

```gdscript
Platform.platform_id            # "standalone" | "vk" | "ok" | "yandex"
Platform.authenticate()         # await; вход через площадку (VK: launch params -> /auth/vk)
Platform.is_authenticated()
Platform.get_auth_error()       # машинный код ошибки для экрана повтора
Platform.get_user()             # {id, name, avatar, platform}
Platform.get_launch_token()     # строка/JSON для серверной проверки
Platform.get_app_link()         # ссылка на приложение ЭТОЙ площадки
Platform.get_currency()         # "votes" | "oki" | "yandex"
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
  platform      TEXT      -- vk | ok | yandex | standalone
  external_id   TEXT      -- vk_user_id / ok uid / yandex player id
  nickname      TEXT
  ...
  UNIQUE (platform, external_id)
```

- VK: `/auth/vk` принимает launch params, проверяет `sign` секретом приложения
  (`VK_APP_SECRET`), проверяет свежесть `vk_ts`, создаёт/находит профиль.
- OK: `/auth/ok` принимает `local_access_token`, проверяет его через OK API,
  создаёт/находит профиль по OK uid.
- Yandex: `/auth/yandex` — проверка player-токена через Yandex API.
- Старые локальные `player_id` остаются для Standalone; для VK/OK — новый профиль
  или одноразовая привязка (решить отдельно).
- Прогресс (уровни, XP, скины, оружие, осколки) — на сервере, не в `user://`.
- **Прогресс VK и OK хранится отдельно** и не переносится между соцсетями.

## Сборки

Четыре export preset:

1. **Web Standalone** — без SDK, для теста и своего сайта.
2. **Web VK** — `index.html` грузит `vk-bridge.min.js`; feature `vk`;
   в PCK только `VKAdapter`.
3. **Web OK** — тоже `vk-bridge.min.js`, но feature `ok`, только `OKAdapter`;
   все ссылки/шеринг — на приложение в Одноклассниках.
4. **Web Yandex** — `index.html` грузит Yandex SDK; feature `yandex`;
   в PCK только `YandexAdapter`.

Чужие SDK и адаптеры в сборку не попадают. `tools/web_export.py` и
`tools/patch_chunk_loader.py` должны принимать платформу, вставлять VK Bridge
только в VK/OK и не вставлять его в Yandex/Standalone.

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

### M2. VK-авторизация — сделано

- `VKAdapter`: `VKWebAppGetLaunchParams` с fallback на URL-параметры,
  `VKWebAppGetUserInfo` для имени, `get_launch_token`.
- Сервер: `players.platform/external_id` + partial unique index, `/auth/vk`,
  проверка `vk_app_id`, MD5 `sign` (`VK_APP_SECRET` только из env) и свежести
  `vk_ts` (≤3600 с), rate-limit. Профиль — по `(platform='vk', external_id)`.
- Клиент: экран входа/повтора, ник — из VK, без ручной регистрации.
- Критерий: два разных VK-пользователя получают разные серверные профили;
  поддельный `sign` отклоняется. Unit-тесты `server/vk_auth_test.go`; живой
  тест двумя VK-аккаунтами — вручную после смены URL приложения на
  `/game-vk/`.

### M2b. OK-авторизация

- `OKAdapter` наследует `VKBridgeBase`.
- `VKWebAppGetAuthToken` с `append_local: true` → `local_access_token`.
- OK API-методы — через `VKWebAppCallAPIMethod` с `use_local: true`.
- Сервер: `/auth/ok`, проверка OK-токена, профиль по OK uid.
- Все ссылки и шеринг — только на приложение в Одноклассниках; никаких VK-ссылок.
- Критерий: VK- и OK-профили независимы; прогресс в OK не пересекается с VK.

### M3. Юридика и первый запуск

- Экран возраста, пользовательское соглашение, политика конфиденциальности,
  чекбокс согласия; блокировка игры до принятия.
- Ссылки в Панели VK.
- Удаление аккаунта/данных на сервере + кнопка в настройках.
- Контакт поддержки/сообщество и данные разработчика.

### M4. Монетизация VK + OK

- Rewarded/interstitial через VK Ads (не mock).
- VK: VK Голоса для виртуальных ценностей (осколки/скины) через VK Bridge.
- OK: ОКи вместо Голосов; разовые платежи/подписки и обработка платёжных
  уведомлений OK. Экономика и SKU общие, цены/валюта — через адаптер.
- Если реклама VK Ads уже подключена, в OK она показывается автоматически;
  проверить на OK-сборке.
- Серверная проверка платежей отдельно для VK и OK.
- Убрать «Купить осколки» и «x2 за рекламу», если адаптер не готов.

### Особенности OK

- В OK используем VK Bridge, но авторизация — `VKWebAppGetAuthToken` с
  `append_local: true`, токен в `local_access_token`; API-методы —
  `VKWebAppCallAPIMethod` с `use_local: true`.
- VK-специфичные методы (`VKWebAppAddToHomeScreen`, `VKWebAppAddToFavorites`
  и т.п.) в OK не работают; проверять ответ `Unsupported platform`.
- `VKWebAppShare`/`VKWebAppShowStoryBox` — только ссылка на приложение в OK,
  не на VK.
- Никаких внешних ссылок и перехода в VK из OK-сборки.
- Прогресс OK хранится отдельно на сервере (`platform='ok'`) и синхронизируется
  между устройствами пользователя OK.

### M5. Yandex-адаптер

- Yandex SDK init, player, cloud saves, платежи, реклама, лидерборды,
  локализация, возраст.
- Отдельная сборка и отдельные тексты, без упоминаний VK.

## Открытые вопросы

1. Есть ли VK APP_ID и `VK_APP_SECRET` (или доступ к Панели VK)?
2. Есть ли OK APP_ID/ключи и доступ к Панели OK?
3. Каталог VK: **игры** (нужна монетизация) или сервисы?
4. Переносить ли старые локальные профили в VK/OK или начать с чистых?
5. Юридические тексты/ИП/контакты поддержки — кто предоставляет?
6. Приоритет монетизации: сначала rewarded ads или VK Голоса/ОКи?
7. Нужен ли Standalone-билд для itch/своего сайта как отдельный продукт?

## Файлы

- `scripts/platform/platform.gd` — autoload.
- `scripts/platform/platform_adapter.gd` — базовый интерфейс.
- `scripts/platform/standalone_adapter.gd`
- `scripts/platform/vk_adapter.gd`
- `scripts/platform/ok_adapter.gd`
- `scripts/platform/yandex_adapter.gd`
- `tools/web_export.py`, `tools/patch_chunk_loader.py` — платформенные шаблоны.
- `server/main.go`, `server/ws.go` — auth/platform profile.
- `docs/PLATFORM-ADAPTERS.md` — этот файл.

## Текущее состояние

- Прод: PCK 48 959 796, `main` `03a6178`, вход `?v=20261124_102718`.
  M1, D1 и темп обучения задеплоены 24.11; `/health` ok, `live_matches=0`.
  В прод-HTML есть VK Bridge/init для VK-webview, но PCK остаётся standalone;
  отдельная VK-сборка с адаптером — M2.
- **M1 сделан (24.11.2026).** Autoload `Platform` + `PlatformAdapter`,
  `StandaloneAdapter`, заглушки VK/OK/Yandex. `AdManager` и
  `shard_topup_panel` больше не mock: реклама/оплата только через адаптер,
  без реального адаптера кнопки скрыты. В standalone нет VK Bridge.
- **M2 сделан в коде (24.11.2026), не задеплоен.** `/auth/vk` со строгой
  проверкой `sign`/`vk_ts`/`vk_app_id`, профиль `(platform='vk',
  external_id=vk_user_id)`, миграция `players`, VK-экран входа без регистрации
  по нику. XP/уровни персонажей и обучение перенесены в серверный профиль
  (`POST /progress`). Подробно — `docs/QA-M2.md`.
- Сборки: `Web Standalone` (`web-standalone`, `build/web`) и `Web VK`
  (`web-vk,vk`, `build/web-vk`). `python tools/web_export.py --platform
  standalone|vk`; без флага — standalone. VK Bridge вставляется только в VK.
  `python tools/server_web_vk.py` готовит `server/web-vk`.
- Проверки M1: `tools/PlatformProbe.tscn` 22/22 PASS, `go test` ok, оба
  web-билда запускаются (`[Platform] id=standalone` / `id=vk`), кадры
  `docs/qa-m1-shop-standalone.png`, `docs/qa-m1-topup-standalone.png`.
  Подробно — `docs/QA-M1.md`.
- Реальных VK Ads/Голосов пока нет (M4). OK-сборки нет (M2b/M5).
- Прогресс: осколки/скины/оружие, `matches_played`/`novice`, XP и уровни
  персонажей, прохождение/пропуск обучения — серверные (`players.char_levels`,
  `char_xps`, `tutorial_*`). Клиент синхронизирует их через `POST /progress`;
  старые standalone-сейвы один раз выгружаются при первом входе.
- Перед запуском VK: сменить URL приложения на `/game-vk/`, сделать бэкап БД,
  прогнать миграцию на копии и проверить два VK-аккаунта вручную.

## Правило

Перед деплоем проверять `/health.live_matches == 0`; не рвать живые матчи.
