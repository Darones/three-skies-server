# OK-вход по access token — чек-лист проверки на реальном OK

Обновлено: 27.11.2026. Относится к волне 4 (OK-вход и изоляция).

## Что уже в сборке

- Клиент `scripts/platform/ok_adapter.gd` сначала берёт `local_access_token` из
  launch URL (query или hash) и вызывает `NetworkClient.auth_ok(token)`.
- Если токена нет — остаётся старый путь `VKWebAppGetUserInfo(use_local:true)`
  → `NetworkClient.auth_ok_identity(ok_user_id, ...)`.
- Сервер `/auth/ok` уже умеет `local_access_token` → `fetchOKUser`.
- Строгий режим **выключен**: сервер принимает `ok_user_id`, пока не задан
  `OK_STRICT_AUTH=1`.

## Проверка на реальном OK (приложение 512005268801)

1. Открыть игру в OK на телефоне (не в VK).
2. Убедиться, что в адресе есть `local_access_token` (значение не копировать,
   не пересылать, не вставлять в отчёт).
3. В логе клиента ожидается:
   - `[Platform] id=ok`;
   - `[OK] auth via local_access_token`;
   - запрос `POST /auth/ok` с телом `{"local_access_token": "..."}`
     (не `ok_user_id`).
4. Проверить:
   - профиль загрузился, ник/уровень/осколки совпадают с прошлым входом;
   - вход в обучение, обычный матч, выход в лобби;
   - магазин и покупка (окно оплаты OK);
   - реклама x2 (если доступна) и начисление после ответа сервера.
5. Если вход не прошёл — зафиксировать:
   - `Platform.get_auth_error()` / `_last_error`
     (`ok_auth_not_configured`, `invalid_ok_auth`, `ok_auth_failed`,
     `ok_rate_limited`, `ok_bridge_unavailable`);
   - полный URL без значения `local_access_token` (заменить на `***`);
   - время и устройство.
   Токен и uid в отчёт не включать.

## Проверка 27.11.2026 — результат

Проверено на реальном OK (Яндекс.Браузер, аккаунт `Андрей Давлеев`, приложение
512005268801):

1. В launch URL **нет** `local_access_token`; клиент уходит в
   `[OK] auth via bridge identity (no token)`.
2. `VKWebAppGetAuthToken` запрошен через Bridge (`app_id` = 54906713, `scope`):
   - без `app_id` — `Missing required param "app_id"`;
   - с `app_id` — OK launcher отдаёт токен, но `/auth/ok` отвечает
     `invalid_ok_auth`.
3. В логах RelaxDev:
   - сначала `ok api: PARAM_API_KEY : Application not exist` — в переменных
     проекта не было `OK_APP_KEY`, код брал `OK_APP_ID` как application key;
     добавлен `OK_APP_KEY=CDJKIQJGDIHBABABA` (значение из launch URL OK);
   - после этого `ok api: PARAM : Parameter access_token specified but
     application is not EXTERNAL`.
4. Вывод: приложение 512005268801 в кабинете OK **не помечено как EXTERNAL**
   (внешнее), поэтому OK API не принимает access_token. Пока это не исправлено
   в кабинете OK, token-first путь работать не будет.
5. Дополнительно: вызов `VKWebAppGetAuthToken` перед `VKWebAppGetUserInfo`
   ломал старый UID-fallback (`/auth/ok` 400). Поэтому вызов токена убран из
   `authenticate()`; метод `_request_bridge_access_token()` оставлен на будущее.
   Сейчас вход снова идёт через `[OK] auth via bridge identity (no token)` и
   профиль загружается.

**Что нужно от кабинета OK:** перевести приложение 512005268801 в тип
«внешнее»/разрешить access token (или уточнить у поддержки OK точную настройку).
После этого включить `OK_STRICT_AUTH=1` и проверить снова.

**Строгий режим:** `OK_STRICT_AUTH` не задан; не включать до успешного
token-входа.

## Если токен есть, но сервер отвечает `ok_auth_not_configured`

Это значит, что на RelaxDev не заданы `OK_APP_KEY` / `OK_APP_SECRET`
(по памяти проекта они уже заданы — проверить в переменных окружения).
До исправления env строгий режим включать нельзя.

## Включение строгого режима (только после успешного теста)

1. В переменных окружения RelaxDev добавить `OK_STRICT_AUTH=1`.
2. Перезапустить сервис.
3. Повторить шаги 1–4: вход должен идти только по `local_access_token`;
   `ok_user_id` из тела должен получать 401 `invalid_ok_auth`.
4. Проверить, что старый fallback не нужен. Если OK не отдаёт токен —
   вернуть `OK_STRICT_AUTH=0` и оставить fallback.

## После строгого режима — изоляция шеллов (отдельный шаг)

- `/game-ok/` без VK-строк (`vk_client`, `vk_user_id`, `sign`) и без VK Bridge.
- `/game-vk/` без `ok.ru` / `vk_client=ok`.
- `/game/` грузит VK Bridge только для VK.
- OK-юр-ссылки — на разрешённом домене, не на RelaxDev.
- Проверить: OK-вход, OK-реклама, OK-платежи; VK-вход, VK-реклама, VK-платежи.
- Откат: вернуть предыдущий deploy-коммит `main` и `OK_STRICT_AUTH=0`.

## Текущие ограничения

- `OK_STRICT_AUTH` по умолчанию выключен; поведение входа не меняется.
- Шеллы и VK Bridge в этом шаге не тронуты: на них держится текущий OK-вход.
- OK-платежи (`/ok/pay`) и начисления не менялись.
