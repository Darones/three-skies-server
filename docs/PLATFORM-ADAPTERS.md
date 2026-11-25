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

Один универсальный web-билд (25.11.2026):

1. **Web Standalone** — единственный export preset. В PCK входят все
   адаптеры (`StandaloneAdapter`, `VKAdapter`, `OKAdapter`,
   `YandexAdapter`); feature tag больше не выбирает платформу.
2. `python tools/web_export.py` собирает `build/web`, кладёт один
   `server/web/index.pck` и пишет тонкие shell'ы
   `server/web-vk/index.html` и `server/web-ok/index.html`.
3. `/game-vk/` и `/game-ok/` не содержат PCK: они перекидывают на `/game/`,
   сохраняя `search` и `hash` (VK launch params). OK-shell добавляет
   `vk_client=ok`; VK-shell делает то же, если referrer — `ok.ru`.
4. `Platform` выбирает адаптер в runtime: OK (`vk_client=ok`, referrer
   `ok.ru`, `local_access_token`), VK (`vk_user_id`/`vk_app_id`/`vk_ts`/
   `vk_platform` в query или hash), иначе Standalone.
5. `tools/patch_chunk_loader.py` один для всех: range-загрузка PCK.

Старые отдельные `Web VK`/`Web OK` presets, `build/web-vk`/`build/web-ok`
PCK и `tools/server_web_vk.py`/`server_web_ok.py` удалены.

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
  проверка `vk_app_id`, HMAC-SHA256/base64url `sign` (`VK_APP_SECRET` только из
  env; старый MD5-hex тоже принимается) и свежести `vk_ts` (≤3600 с),
  rate-limit. Профиль — по `(platform='vk', external_id)`.
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

- Прод (25.11.2026, вечер): **один PCK** `/game/index.pck` **48 975 700**,
  `main` `46b510d`, `/health` ok, `live_matches=0`. `/game-vk/` и
  `/game-ok/` — тонкие shell'ы (1017/1016 байт) без PCK; VK/OK выбираются
  в runtime. В PCK входят обучение этапы 1–4; 12+/юр-строка скрываются
  после старта.
- **M1 сделан (24.11.2026).** Autoload `Platform` + `PlatformAdapter`,
  `StandaloneAdapter`, заглушки VK/OK/Yandex. `AdManager` и
  `shard_topup_panel` больше не mock: реклама/оплата только через адаптер,
  без реального адаптера кнопки скрыты. В standalone нет VK Bridge.
- **M2 задеплоен (24.11.2026).** `/auth/vk` со строгой
  проверкой `sign`/`vk_ts`/`vk_app_id`, профиль `(platform='vk',
  external_id=vk_user_id)`, миграция `players`, VK-экран входа без регистрации
  по нику. XP/уровни персонажей и обучение перенесены в серверный профиль
  (`POST /progress`). Подробно — `docs/QA-M2.md`.
- Сборки: один `Web Standalone` preset, один `build/web` и один
  `server/web/index.pck`; `/game-vk/` и `/game-ok/` — тонкие redirect-shell'ы
  без PCK. `python tools/web_export.py` делает всё за один запуск
  (сборка, `server/web`, shell'ы); `python tools/server_web.py` оставлен
  совместимым враппером. VK/OK выбираются в runtime по launch params.
- Проверки 25.11: `PlatformProbe` 22/22, `OKUiProbe` 10/10, `go test`/`go vet`
  ok; один PCK, в браузере `[Platform] id=standalone/vk/ok`; кадры
  `docs/qa-single-pck-vk.png`, `docs/qa-single-pck-ok.png`.
  Подробно — `docs/QA-SINGLE-PCK.md`.
- Реальная VK-реклама подключена; VK Голоса и ОКи (платежи) — ещё нет
  (M4/M5). В OK валюта и ссылки уже runtime-OK, но покупки честно недоступны.
- Перед изменением панели VK/OK: URL можно оставить `/game-vk/` — shell
  ведёт на `/game/` и сохраняет launch params; отдельный PCK не нужен.
- Прогресс: осколки/скины/оружие, `matches_played`/`novice`, XP и уровни
  персонажей, прохождение/пропуск обучения — серверные (`players.char_levels`,
  `char_xps`, `tutorial_*`). Клиент синхронизирует их через `POST /progress`;
  старые standalone-сейвы один раз выгружаются при первом входе.

## Правило

Перед деплоем проверять `/health.live_matches == 0`; не рвать живые матчи.
