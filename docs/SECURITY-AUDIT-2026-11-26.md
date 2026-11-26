# Аудит безопасности и соответствия VK/OK — 26.11.2026

Аудит только читал код и прод, но один агент по ошибке выполнил destructive-запрос.
Ниже — инцидент, восстановление и найденные блокеры. Код игры/сервера в этом
аудите **не менялся**, деплоя не было.

## 0. Инцидент: удалён legacy-профиль id=1 «Даронес»

- Агент проверял, требует ли `/account/delete` сессию, и отправил
  `POST /account/delete {"player_id":1}` **без токена**. Сервер ответил
  `200 {"success":true}` и удалил реальный профиль.
- Причина — legacy-байпас в `requireSession` (`server/main.go:1198-1208`):
  для профилей с пустым `session_token` сессия не требуется.
- Последствия: строка `players.id=1` удалена; у `matches.id=1` `player_id`
  заменён на 0; события `stats_events` с `player_id=1` анонимизированы;
  жалобы по нику «Даронес» удалены (в дампе таких не было).
- Синтетический OK-профиль `id=202`, созданный при проверке `/auth/ok`,
  удалён; других тестовых профилей агент не создавал.
- Профиль 1 в бэкапе `backups/three-skies-prod-2026-11-24_1705.sql`:
  `1  Даронес  0  ''  ''  f  \N  \N  1  f`, матч `id=1 room_id=1 player_id=1`.
- Точный SQL восстановления: `docs/RESTORE-player-1.sql`. **Не выполнять
  полный restore дампа** — он откатит 24–26 ноября. Выполнять только
  точечный INSERT/UPDATE после закрытия legacy-байпаса.

### Восстановление (когда будет доступ к БД)

1. Закрыть legacy-байпас `requireSession` (иначе профиль снова удалят).
2. Выполнить `docs/RESTORE-player-1.sql` под `DATABASE_URL` прода.
3. Проверить `GET /profile?player_id=1` → 200, ник «Даронес», 1 матч,
   `GET /admin/moderation/players?q=Даронес` → id=1.
4. Проверить `matches.id=1.player_id=1`.

## 1. Критичные блокеры (P0)

1. **Дефолтные `ADMIN_TOKEN`/`STATS_TOKEN` = `239837` работают на проде.**
   Живой `GET /admin/moderation?token=239837` → 200; `/stats/data?token=239837`
   → 200. Любой может выдать себе до 1 000 000 осколков, банить/скрывать
   ники, читать жалобы и стирать статистику.
2. **Legacy-профили без токена полностью открыты.**
   `/session` и `/profile` с `X-Claim-Session: 1` выдают токен без
   аутентификации; `requireSession` разрешает любые операции. Уже привело
   к удалению player 1.
3. **OK-авторизация обходится.** `/auth/ok` принимает `ok_user_id` из тела
   без подтверждения; живой запрос создал профиль и вернул `session_token`.
   Так можно войти в чужой OK-профиль по uid.
4. **OK-платежи не подписаны.** `/ok/pay` не проверяет подпись; `/vk/pay`
   с `site=OK` (или `app_id=512005268801`, `method=callbacks.getCustomProductInfo`)
   пропускает проверку подписи. Это бесплатные осколки и перехват заказов.
5. **VK display name не подписан.** `sign` покрывает только `vk_*`;
   `name` приходит от клиента. Бесплатная смена ника и снятие
   `nickname_hidden` при каждом логине (`platformRenameDecision`).
6. **UGC/жалобы не соответствуют VK 2.5.1–2.5.3.** Нельзя пожаловаться на
   ник длиннее 12 символов (VK/OK — до 32); гостевые ники в WS не
   фильтруются; нет публичных правил, согласия и SLA 48 ч.
7. **Удаление данных неполное.** `payments.external_id` и
   `stats.payload.ref` (с `vk_user_id`/`sign`) переживают `/account/delete`;
   отчёты по старому нику остаются.
8. **`sign` хранится в статистике.** `stats.go:410-418` пишет `ref` с
   `sign`; `/stats/player` с дефолтным токеном отдаёт это наружу
   (в живом прогоне 21 событие).

## 2. Что проверено и работает

- VK auth: `vk_app_id`, HMAC/legacy MD5, `vk_ts` ≤ 3600, rate-limit 20/мин;
  неверный sign/старый ts/чужой app_id → 401; 21-й запрос → 429.
- VK-платежи: MD5-подпись, `get_item`, `order_status_change`,
  `status=chargeable`; реальная покупка 25.11 прошла; без подписи → ошибка.
- `/match_reward`: проверка комнаты/игрока, потолок 5/3, XP ≤ 2000,
  бонус x2 только после base, идемпотентность.
- `/compensation` → 410.
- `/report` rate-limit 5/мин, reason 3–200, очередь модерации.
- Админка без токена → 403; токен не в HTML; traversal → 404.
- `/health` ok, `/game/` 200, `/game-ok/` 200.

## 3. Риски, не блокеры

- Нет общих rate-limit на `/profile`, `/register`, `/session`, `/progress`,
  `/rename`, `/buy_*`, `/match_reward`, `/account/delete`, `/stats/event`,
  payments, admin, WS.
- CORS отражает любой `Origin` (`Access-Control-Allow-Origin: evil.example`).
- `/game-ok/` не пропущен в `databaseGate` (при падении БД OK-шелл упадёт).
- WS `CheckOrigin: true`, нет лимита соединений, `sessionAllowed` fail-open.
- Нет TTL/ротации `session_token`, нет `Cache-Control: no-store`.
- `/health` отдаёт `database_host` и `database_error`.
- `/rename` доступен VK/OK-профилям через API (бесплатный кастомный ник).
- Дубликаты ников разрешены; жалобы по нику неоднозначны.
- `/stats/event` без auth/rate-limit.
- В `credits/licenses.gd` есть URL лицензий (некликабельные) — проверить 4.1.8.
- OK-реклама наследует VK-адаптер; неизвестно, поддерживает ли OK
  `VKWebAppShowNativeAds`.

## 4. Рекомендуемый порядок

1. Сменить `ADMIN_TOKEN`/`STATS_TOKEN` на сильные env-токены, fail-closed.
2. Закрыть legacy-байпас, восстановить player 1.
3. Убрать приём `ok_user_id`; только `local_access_token` + проверка OK API.
4. Закрыть OK-платежи до одобрения; проверять подписи/суммы/order_id.
5. Не доверять `name` при VK/OK-логине; не снимать `nickname_hidden`
   автоматически по неподписанному имени.
6. UGC: жалобы по `player_id`, фильтр гостевых ников, правила/SLA 48 ч,
   согласие и политика, контакт поддержки.
7. Почистить `payments.external_id` и `stats.ref`; вырезать `sign` из
   статистики.
8. Общие rate-limit, CORS allowlist, `/game-ok/` gate, WS origin/cap.

## 5. Ограничения аудита

- Валидную VK-подпись и реальную покупку не повторяли (нет секрета,
  мутации запрещены).
- Живой повтор `order_id`, `/admin/grant_shards`, `/stats/reset`,
  `/report`, `/match_reward` не выполняли.
- OK-платёж на стороне OK недоступен («платёжная система на профилактике»).
- Полный OK-UI и статус модерации VK/OK не проверены.
