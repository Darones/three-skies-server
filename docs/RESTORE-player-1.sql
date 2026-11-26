-- Точечное восстановление legacy-профиля id=1 «Даронес»,
-- удалённого 26.11.2026 запросом /account/delete без сессии.
--
-- НЕ запускать полный restore дампа: он откатит данные за 24–26 ноября.
-- Перед запуском:
--   1. закрыть legacy-байпас requireSession;
--   2. сделать свежий бэкап БД;
--   3. выполнить: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f docs/RESTORE-player-1.sql
--
-- Источник строки: backups/three-skies-prod-2026-11-24_1705.sql
--   players: 1  Даронес  0  ''  ''  f  \N  \N  1  f
--   matches: 1  1  1  0  f  2026-11-12 07:15:51.168672+00  f  f

BEGIN;

-- Если id=1 уже существует (например, восстановление повторяют) — не дублируем.
INSERT INTO players (
    id,
    nickname,
    nickname_custom,
    sky_shards,
    unlocked_wings,
    unlocked_weapons,
    matches_played,
    novice,
    platform,
    external_id,
    level,
    progress_initialized
) VALUES (
    1,
    'Даронес',
    FALSE,
    0,
    '',
    '',
    1,
    FALSE,
    'standalone',
    '1',
    1,
    FALSE
)
ON CONFLICT DO NOTHING;

-- Вернуть матч id=1 удалённому игроку (сейчас player_id=0 после анонимизации).
UPDATE matches
   SET player_id = 1
 WHERE id = 1
   AND room_id = 1
   AND player_id = 0
   AND played_at = '2026-11-12 07:15:51.168672+00'::timestamptz;

COMMIT;

-- Проверки после выполнения:
-- SELECT id, nickname, sky_shards, matches_played, platform, external_id, progress_initialized
--   FROM players WHERE id = 1;
-- SELECT id, room_id, player_id, played_at FROM matches WHERE id = 1;
