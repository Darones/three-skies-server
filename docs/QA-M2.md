# QA M2: VK-авторизация

Дата: 24.11.2026. Ветка `mobile-ui`, изменения M2 пока не закоммичены и не
задеплоены. Прод остаётся на `main` `03a6178`.

## Что сделано

- `server/vk_auth.go`: `POST /auth/vk`, проверка `vk_app_id=54906713`,
  MD5-подписи по всем `vk_*` + `VK_APP_SECRET`, свежести `vk_ts` (≤3600 с),
  rate-limit 20 запросов/мин на IP, профиль по `(platform='vk', external_id)`.
  Секрет читается только из env. Ошибка → `401` до создания профиля.
- `server/main.go`: `players.platform/external_id/level`, partial unique index,
  идемпотентная миграция старых строк (`platform='standalone'`,
  `external_id=id::text`), `/game-vk/` и `WEB_VK_DIR`, fallback на общие
  JS/WASM из standalone-сборки.
- `server/schema.sql`: та же миграция для ручного `psql`.
- `server/Dockerfile`: `web-vk`, `WEB_VK_ORIGIN`, `WEB_VK_DIR`.
- `scripts/platform/vk_adapter.gd`: `VKWebAppGetLaunchParams` + fallback на
  URL, `VKWebAppGetUserInfo` после серверной проверки, понятные коды ошибок.
- `scripts/lobby.gd`: экран «Вход через VK» с повтором; для VK нет локальной
  регистрации и кнопки «Сменить ник»; ник — display name из VK.
- `scripts/network_client.gd`, `scripts/MetaProgression.gd`: `auth_vk`,
  применение серверного профиля, `account_level`.
- `tools/server_web_vk.py`: `server/web-vk/index.html` + `index.pck` для
  RelaxDev; остальные файлы берутся из `server/web`.

## Тесты

Выполнено локально 24.11.2026:

```text
cd server
go vet ./...                          # ok
go test -count=1 ./...                # ok (5.2s, включая TestVerifyVK*)
go test -count=1 -v -run 'TestVK|TestHandleVK' ./...  # ok
```

Покрыто unit-тестами (`server/vk_auth_test.go`):

- известный MD5-вектор подписи;
- валидные launch params;
- поддельный `sign` → 401;
- просроченный `vk_ts` → 401;
- чужой `vk_app_id` → 401;
- отсутствие `sign`;
- нормализация display name;
- rate-limit;
- HTTP-обработчик возвращает 401 для подделки/просрочки/чужого app id;
- `sanitizeProgress`: клампы уровней/XP, известные персонажи, взаимоисключающие
  `tutorial_completed`/`tutorial_skipped`;
- `POST /progress` на копии БД: валидный токен сохраняет XP/обучение, неверный
  токен → 401.

Интеграционный тест с реальной PostgreSQL (пропускается без env):

```powershell
$env:TEST_DATABASE_URL = "postgres://user:pass@host:5432/dbname"
cd server
go test -run TestVKProfileMigrationIntegration -v ./...
```

Он проверяет миграцию старой таблицы, идемпотентность, backfill
`platform/external_id`, наличие unique index, переиспользование сессии,
разные профили для разных `vk_user_id` и сохранение кастомного ника.

## Сборки

`python tools/web_export.py --platform vk`:

- PCK `48 973 924` байт (`index_20261124_202152.pck`);
- `[Platform] id=vk adapter=VK`;
- вне VK показывает «VK не передал данные для входа. Перезапусти игру из VK.»
  и кнопку «Повторить» (скриншот `docs/qa-m2-vk-no-params.jpeg`);
- с синтетическим `vkBridge` и mock `/auth/vk` проверен успешный вход:
  экран входа скрылся, в профиле появилось имя из VK, ошибок в консоли нет.

`python tools/web_export.py --platform standalone`:

- PCK `48 973 940` байт (`index_20261124_202208.pck`);
- `[Platform] id=standalone adapter=Standalone`;
- экрана VK нет, лобби работает как раньше
  (`docs/qa-m2-standalone-lobby.jpeg`).

`server/web-vk/index.pck` = `48 973 924`; локальный Go-сервер отдаёт
`/game-vk/index.html`, `/game-vk/index.js`, `/game-vk/index.wasm` и
range-запросы к PCK (`Content-Range: bytes 0-99/48973924`).

## Бэкап и проверка restore (24.11.2026)

- Свежий `pg_dump` из панели RelaxDev: `db_three_skies_server.sql`,
  `pg_dump 17.9`, размер `190 387` байт.
- Дамп восстановлен локально в PostgreSQL 17.11, БД `three_skies_m2_copy`.
- Сверка строк дампа и восстановленной БД:

| Таблица | В дампе | После restore |
|---|---:|---:|
| players | 103 | 103 |
| matches | 49 | 49 |
| reports | 2 | 2 |
| stats_events | 872 | 872 |

- Сумма `sky_shards` до/после restore: `679 229` / `679 229`.
- Ошибок restore нет (`ON_ERROR_STOP=1`).

## Миграция на копии БД (перед деплоем)

Проверено на `three_skies_m2_copy` 24.11.2026:

- до миграции: `players=103`, `sum(sky_shards)=679229`, `novice=7`;
- после миграции: `players=103`, `sum(sky_shards)=679229`, `novice=7`;
- `platform IS NULL/''` = 0;
- `external_id IS NULL` = 0;
- дублей `(platform, external_id)` = 0;
- `external_id <> id::text` у standalone = 0;
- `level IS NULL` = 0;
- `char_levels/char_xps IS NULL` = 0;
- `players_platform_external_id_idx` = 1;
- повторный запуск миграции не меняет строки и не падает.

## XP, обучение, matches_played/novice

- `matches_played` и `novice` уже были серверными: их пишет WS-сервер
  (`server/ws.go`) и отдаёт `/profile`; клиент лишь кэширует значения.
- XP/уровни персонажей и прохождение обучения раньше были только в
  `user://meta_save.cfg` и `user://tutorial.cfg`. Теперь они хранятся в
  `players.char_levels`, `char_xps`, `tutorial_completed`, `tutorial_skipped`,
  `tutorial_battles_used`; клиент читает их из профиля и сохраняет через
  `POST /progress`.
- Для старых standalone-профилей `progress_initialized=false`: первый вход
  после обновления один раз выгружает локальные XP/обучение на сервер.
  VK-профили создаются с `progress_initialized=true` и никогда не получают
  чужой локальный standalone-прогресс.
- Проверено на копии: VK-профиль с сервера показал уровень 5 и XP 420 в
  клиенте; `POST /progress` с валидным токеном сохранил значения, с неверным
  токеном вернул 401. Новый standalone-профиль после первого входа получил
  `progress_initialized=true`.
- Старый standalone-профиль (id 110, `progress_initialized=false`) загрузил
  локальные `warrior 6 / 321 XP`, `mage 3 / 654 XP`, `fairy 2 / 7 XP`,
  обучение `completed=true`, `battles_used=2`; в БД значения совпали,
  флаг стал `true`.

## Порядок перед деплоем

1. Сделать бэкап: `pg_dump "$DATABASE_URL" > three-skies-pre-m2.sql`.
2. Восстановить копию в отдельную БД и прогнать:
   `TEST_DATABASE_URL=<копия> go test -run TestVKProfileMigrationIntegration -v ./...`
3. Проверить на копии:
   - у старых строк `platform='standalone'`, `external_id=id::text`;
   - `SELECT COUNT(*) FROM players WHERE external_id IS NULL` = 0;
   - осколки/скины/оружие не изменились;
   - индекс `players_platform_external_id_idx` существует.
4. Только после этого деплоить при `/health.live_matches == 0`.

## Что осталось проверить вручную

- Сменить URL VK-приложения на `https://three-skies-server.relaxdev.ru/game-vk/`.
- Два разных VK-аккаунта → два разных `player_id`, разные профили.
- Один VK-аккаунт на двух устройствах → один `player_id`, одинаковые осколки,
  скины, оружие и уровень.
- Реальный VK webview: вход без ручной регистрации, имя из VK, повтор после
  ошибки сети.
- iPhone/Safari: отсутствие зависания на экране входа, клавиатура не нужна.
- Standalone `/game/` после деплоя: старый вход и прогресс не сломаны.

## Секрет

`VK_APP_SECRET` нигде не закоммичен. В коде только `os.Getenv`; в тестах —
`test_secret`. Значение из RelaxDev не читалось, не логировалось и не
передавалось в файлы.
