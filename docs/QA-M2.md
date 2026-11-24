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
- HTTP-обработчик возвращает 401 для подделки/просрочки/чужого app id.

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

- PCK `48 971 364` байт (`index_20261124_150929.pck`);
- `[Platform] id=vk adapter=VK`;
- вне VK показывает «VK не передал данные для входа. Перезапусти игру из VK.»
  и кнопку «Повторить» (скриншот `docs/qa-m2-vk-no-params.jpeg`);
- с синтетическим `vkBridge` и mock `/auth/vk` проверен успешный вход:
  экран входа скрылся, в профиле появилось имя из VK, ошибок в консоли нет.

`python tools/web_export.py --platform standalone`:

- PCK `48 971 380` байт (`index_20261124_150944.pck`);
- `[Platform] id=standalone adapter=Standalone`;
- экрана VK нет, лобби работает как раньше
  (`docs/qa-m2-standalone-lobby.jpeg`).

`server/web-vk/index.pck` = `48 971 364`; локальный Go-сервер отдаёт
`/game-vk/index.html`, `/game-vk/index.js`, `/game-vk/index.wasm` и
range-запросы к PCK (`Content-Range: bytes 0-99/48971364`).

## Миграция на копии БД (перед деплоем)

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
