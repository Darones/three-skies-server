-- Three Skies server schema.
-- Apply with: psql "$DATABASE_URL" -f schema.sql

CREATE TABLE IF NOT EXISTS players (
    id SERIAL PRIMARY KEY,
    nickname TEXT NOT NULL,
    sky_shards INTEGER NOT NULL DEFAULT 0,
    unlocked_wings TEXT NOT NULL DEFAULT '',
    unlocked_weapons TEXT NOT NULL DEFAULT ''
);

ALTER TABLE players ADD COLUMN IF NOT EXISTS unlocked_weapons TEXT NOT NULL DEFAULT '';
ALTER TABLE players ADD COLUMN IF NOT EXISTS last_compensation_at TIMESTAMPTZ;
ALTER TABLE players ADD COLUMN IF NOT EXISTS nickname_custom BOOLEAN DEFAULT FALSE;
ALTER TABLE players ADD COLUMN IF NOT EXISTS session_token TEXT;
ALTER TABLE players ADD COLUMN IF NOT EXISTS matches_played INTEGER DEFAULT 0;
ALTER TABLE players ADD COLUMN IF NOT EXISTS novice BOOLEAN DEFAULT FALSE;
ALTER TABLE players ADD COLUMN IF NOT EXISTS platform TEXT NOT NULL DEFAULT 'standalone';
ALTER TABLE players ADD COLUMN IF NOT EXISTS external_id TEXT;
ALTER TABLE players ADD COLUMN IF NOT EXISTS level INTEGER DEFAULT 1;
ALTER TABLE players ADD COLUMN IF NOT EXISTS char_levels JSONB NOT NULL DEFAULT '{"warrior":1,"mage":1,"fairy":1}'::jsonb;
ALTER TABLE players ADD COLUMN IF NOT EXISTS char_xps JSONB NOT NULL DEFAULT '{"warrior":0,"mage":0,"fairy":0}'::jsonb;
ALTER TABLE players ADD COLUMN IF NOT EXISTS tutorial_completed BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE players ADD COLUMN IF NOT EXISTS tutorial_skipped BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE players ADD COLUMN IF NOT EXISTS tutorial_battles_used INTEGER NOT NULL DEFAULT 0;
ALTER TABLE players ADD COLUMN IF NOT EXISTS progress_initialized BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE players ADD COLUMN IF NOT EXISTS last_interstitial_at TIMESTAMPTZ;
ALTER TABLE players ALTER COLUMN sky_shards SET DEFAULT 0;
ALTER TABLE players ALTER COLUMN unlocked_wings SET DEFAULT '';
ALTER TABLE players ALTER COLUMN unlocked_weapons SET DEFAULT '';

-- M2: platform identity. Old rows remain standalone profiles; VK rows are
-- identified by (platform='vk', external_id=vk_user_id).
UPDATE players SET platform = 'standalone' WHERE platform IS NULL OR platform = '';
UPDATE players SET external_id = id::text
WHERE platform = 'standalone' AND external_id IS NULL;
UPDATE players SET progress_initialized = TRUE
WHERE platform <> 'standalone' AND progress_initialized = FALSE;
CREATE UNIQUE INDEX IF NOT EXISTS players_platform_external_id_idx
ON players (platform, external_id)
WHERE external_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS matches (
    id BIGSERIAL PRIMARY KEY,
    room_id BIGINT NOT NULL,
    player_id BIGINT NOT NULL,
    team INTEGER NOT NULL,
    won BOOLEAN NOT NULL,
    played_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS matches_player_id_idx ON matches (player_id);
CREATE INDEX IF NOT EXISTS matches_room_id_idx ON matches (room_id);
ALTER TABLE matches ADD COLUMN IF NOT EXISTS rewarded BOOLEAN DEFAULT FALSE;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS rewarded_bonus BOOLEAN DEFAULT FALSE;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS reward_shards INTEGER DEFAULT 0;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS reward_xp INTEGER DEFAULT 0;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS reward_character TEXT DEFAULT '';
