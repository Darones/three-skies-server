-- Three Skies server schema.
-- Apply with: psql "$DATABASE_URL" -f schema.sql

CREATE TABLE IF NOT EXISTS players (
    id SERIAL PRIMARY KEY,
    nickname TEXT UNIQUE NOT NULL,
    sky_shards INTEGER NOT NULL DEFAULT 0,
    unlocked_wings TEXT NOT NULL DEFAULT '',
    unlocked_weapons TEXT NOT NULL DEFAULT ''
);

ALTER TABLE players ADD COLUMN IF NOT EXISTS unlocked_weapons TEXT NOT NULL DEFAULT '';
ALTER TABLE players ALTER COLUMN sky_shards SET DEFAULT 0;
ALTER TABLE players ALTER COLUMN unlocked_wings SET DEFAULT '';
ALTER TABLE players ALTER COLUMN unlocked_weapons SET DEFAULT '';

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
