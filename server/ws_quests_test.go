package main

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"os"
	"testing"
	"time"

	_ "github.com/lib/pq"
)

// TestMatchCountersFeedQuestStats drives the real event handlers of a live
// match (confirmed hits, a shell kill, a shard delivery, a shop purchase) and
// checks that the counters they fill become exactly the match result and the
// quest progress input. No database is needed: applyQuestProgress is only
// reached through saveMatch, which returns early without a db.
func TestMatchCountersFeedQuestStats(t *testing.T) {
	hub := newWebSocketHub(nil)
	attacker := newTestClient(1, 0, 0, 0)
	victim := newTestClient(2, 1, 0, 2)
	room := newTestRoom(attacker, victim)
	room.startedAt = time.Now().Add(-2 * time.Minute)
	hub.rooms[room.id] = room

	// Confirmed damage: the server caps each hit at base x2x2.6, so several
	// hits are needed. The cooldown map is reset instead of sleeping, because
	// this test covers the counters, not the rate limit (which has its own
	// integration test).
	sentDamage := 0
	for hit := 0; victim.alive; hit++ {
		if hit > 20 {
			t.Fatalf("victim survived %d capped hits, hp=%.0f", hit, victim.hp)
		}
		sentDamage++
		attacker.lastAttacks = make(map[string]time.Time)
		hub.handleAttackIntent(attacker, wsIncoming{TargetID: victim.id, Skill: "auto", Amount: 9999})
	}
	if attacker.killsDealt != 1 {
		t.Fatalf("killsDealt = %d, want 1", attacker.killsDealt)
	}
	if victim.deaths != 1 {
		t.Fatalf("deaths = %d, want 1", victim.deaths)
	}
	// Overkill must not inflate the damage metric: the applied damage is the
	// victim's whole HP, never the sum of the capped packets.
	if math.Abs(attacker.damageDealt-victim.maxHP) > 0.01 {
		t.Fatalf("damageDealt = %.2f, want %.2f (%d hits)", attacker.damageDealt, victim.maxHP, sentDamage)
	}

	// Shell death is counted only for a real client source. One accepted hit
	// is capped at 800, so the shell survives the first and dies on the second.
	room.shell = &wsShellState{Alive: true, HP: 1000, MaxHP: 1000, X: 0, Y: 0.45, Z: 0}
	attacker.lastAttacks = make(map[string]time.Time)
	hub.handleShellAttack(attacker, wsIncoming{Amount: 800})
	if attacker.shellsDestroyed != 0 {
		t.Fatalf("shellsDestroyed = %d after a non-lethal hit, want 0", attacker.shellsDestroyed)
	}
	attacker.lastAttacks = make(map[string]time.Time)
	hub.handleShellAttack(attacker, wsIncoming{Amount: 800})
	if attacker.shellsDestroyed != 1 {
		t.Fatalf("shellsDestroyed = %d, want 1", attacker.shellsDestroyed)
	}

	// Shard delivery goes through the real altar validation.
	deliverTestShard(hub, room, attacker)
	if attacker.crystalsDelivered != 1 {
		t.Fatalf("crystalsDelivered = %d, want 1", attacker.crystalsDelivered)
	}
	if room.score[0] != 1 {
		t.Fatalf("score after delivery = %d, want 1", room.score[0])
	}

	// Shop: the metric is the number of distinct server-confirmed purchases.
	attacker.x, attacker.z = -40, 0
	attacker.gold = matchItemPrices["life_amulet"]
	hub.handleBuyItem(attacker, wsIncoming{ItemID: "life_amulet"})
	if len(attacker.bought) != 1 {
		t.Fatalf("bought = %v, want one item", attacker.bought)
	}

	hub.mu.Lock()
	results := hub.finishMatchLocked(room)
	hub.mu.Unlock()
	if len(results) != 2 {
		t.Fatalf("finish returned %d players, want 2", len(results))
	}

	var attackerResult, victimResult matchResultPlayer
	for _, result := range results {
		switch result.playerID {
		case attacker.id:
			attackerResult = result
		case victim.id:
			victimResult = result
		}
	}
	if attackerResult.playerID == 0 || victimResult.playerID == 0 {
		t.Fatalf("match result lost a player: %+v", results)
	}
	if attackerResult.kills != 1 || attackerResult.deaths != 0 {
		t.Fatalf("attacker kills/deaths = %d/%d, want 1/0", attackerResult.kills, attackerResult.deaths)
	}
	if victimResult.deaths != 1 || victimResult.kills != 0 {
		t.Fatalf("victim kills/deaths = %d/%d, want 0/1", victimResult.kills, victimResult.deaths)
	}
	if attackerResult.damage != int(victim.maxHP) {
		t.Fatalf("stored damage = %d, want %d", attackerResult.damage, int(victim.maxHP))
	}
	if attackerResult.crystals != 1 || attackerResult.shells != 1 || attackerResult.shopItems != 1 {
		t.Fatalf("counters = crystals %d, shells %d, shop %d, want 1/1/1",
			attackerResult.crystals, attackerResult.shells, attackerResult.shopItems)
	}
	if attackerResult.durationSec < 120 || attackerResult.durationSec > 130 {
		t.Fatalf("durationSec = %d, want about 120", attackerResult.durationSec)
	}
	if attackerResult.classKey != "warrior" {
		t.Fatalf("classKey = %q, want warrior", attackerResult.classKey)
	}

	// matchResultPlayer -> matchStats is the only path from a saved match to a
	// quest, so every counter must survive the conversion.
	stats := attackerResult.stats(true)
	if stats.kills != 1 || stats.deaths != 0 || stats.damage != int(victim.maxHP) ||
		stats.crystals != 1 || stats.shells != 1 || stats.shopItems != 1 ||
		stats.durationSec != attackerResult.durationSec ||
		stats.classKey != "warrior" || !stats.won {
		t.Fatalf("matchStats lost a counter: %+v (result %+v)", stats, attackerResult)
	}

	// A repeated finish must not pay again: the room is already saved and a
	// late delivery packet is rejected before any counter or score moves.
	scoreBefore := room.score
	countersBefore := attacker.crystalsDelivered
	hub.finishMatchByTimeout(room.id)
	hub.mu.Lock()
	room.crystal = &wsCrystalState{State: "carried", CarrierID: attacker.id}
	hub.mu.Unlock()
	attacker.x = 0
	attacker.z = 27.5
	hub.handleCrystalDeliver(attacker, wsIncoming{})
	if room.score != scoreBefore {
		t.Fatalf("repeated finish moved the score: %v -> %v", scoreBefore, room.score)
	}
	if attacker.crystalsDelivered != countersBefore {
		t.Fatalf("repeated finish moved the delivery counter: %d -> %d", countersBefore, attacker.crystalsDelivered)
	}
	if !room.resultSaved {
		t.Fatal("room.resultSaved is false after the match finished")
	}
}

// TestMatchResultWritesQuestCountersIntegration is the match -> counters ->
// progress -> reward path against a real PostgreSQL copy. It is skipped unless
// TEST_DATABASE_URL is set, like the other database tests.
//
//	$env:TEST_DATABASE_URL = "postgres://user:pass@host:5432/dbname"
//	go test -run TestMatchResultWritesQuestCountersIntegration -v ./...
func TestMatchResultWritesQuestCountersIntegration(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	db, err := sql.Open("postgres", normalizeDatabaseURL(dsn))
	if err != nil {
		t.Fatalf("open database: %v", err)
	}
	defer db.Close()
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		t.Fatalf("ping database: %v", err)
	}

	schema := fmt.Sprintf("dq_ws_test_%d", time.Now().UnixNano())
	if _, err := db.ExecContext(ctx, `CREATE SCHEMA `+schema); err != nil {
		t.Fatalf("create schema: %v", err)
	}
	defer db.ExecContext(context.Background(), `DROP SCHEMA `+schema+` CASCADE`)
	if _, err := db.ExecContext(ctx, `SET search_path TO `+schema); err != nil {
		t.Fatalf("set search_path: %v", err)
	}

	for _, statement := range []string{
		`CREATE TABLE players (
			id SERIAL PRIMARY KEY,
			nickname TEXT NOT NULL,
			sky_shards INTEGER NOT NULL DEFAULT 0,
			unlocked_wings TEXT NOT NULL DEFAULT '',
			unlocked_weapons TEXT NOT NULL DEFAULT '',
			level INTEGER NOT NULL DEFAULT 1,
			matches_played INTEGER NOT NULL DEFAULT 0,
			novice BOOLEAN NOT NULL DEFAULT FALSE,
			char_levels JSONB NOT NULL DEFAULT '{"warrior":1,"mage":1,"fairy":1}'::jsonb,
			char_xps JSONB NOT NULL DEFAULT '{"warrior":0,"mage":0,"fairy":0}'::jsonb
		)`,
		`CREATE TABLE matches (
			id BIGSERIAL PRIMARY KEY,
			room_id BIGINT NOT NULL,
			player_id BIGINT NOT NULL,
			team INTEGER NOT NULL,
			won BOOLEAN NOT NULL,
			played_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			rewarded BOOLEAN DEFAULT FALSE,
			rewarded_bonus BOOLEAN DEFAULT FALSE,
			reward_shards INTEGER DEFAULT 0,
			reward_xp INTEGER DEFAULT 0,
			reward_character TEXT DEFAULT '',
			duration_sec INTEGER NOT NULL DEFAULT 0,
			kills INTEGER NOT NULL DEFAULT 0,
			deaths INTEGER NOT NULL DEFAULT 0,
			damage INTEGER NOT NULL DEFAULT 0,
			crystals INTEGER NOT NULL DEFAULT 0,
			shells INTEGER NOT NULL DEFAULT 0,
			shop_items INTEGER NOT NULL DEFAULT 0,
			class_key TEXT NOT NULL DEFAULT ''
		)`,
		`CREATE TABLE daily_quest_days (
			player_id BIGINT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
			quest_day DATE NOT NULL,
			seed BIGINT NOT NULL,
			reroll_seq SMALLINT NOT NULL DEFAULT 0,
			free_reroll_used BOOLEAN NOT NULL DEFAULT FALSE,
			paid_rerolls SMALLINT NOT NULL DEFAULT 0,
			completed_count SMALLINT NOT NULL DEFAULT 0,
			all_done_bonus BOOLEAN NOT NULL DEFAULT FALSE,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			PRIMARY KEY (player_id, quest_day)
		)`,
		`CREATE TABLE daily_quests (
			player_id BIGINT NOT NULL,
			quest_day DATE NOT NULL,
			slot SMALLINT NOT NULL,
			template_id TEXT NOT NULL,
			metric TEXT NOT NULL,
			target INTEGER NOT NULL,
			progress INTEGER NOT NULL DEFAULT 0,
			reward_shards SMALLINT NOT NULL,
			reward_xp SMALLINT NOT NULL,
			rerolled BOOLEAN NOT NULL DEFAULT FALSE,
			completed_at TIMESTAMPTZ,
			PRIMARY KEY (player_id, quest_day, slot),
			FOREIGN KEY (player_id, quest_day)
				REFERENCES daily_quest_days (player_id, quest_day) ON DELETE CASCADE
		)`,
		`CREATE TABLE weekly_grants (
			player_id BIGINT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
			week_start DATE NOT NULL,
			tier SMALLINT NOT NULL,
			reward_kind TEXT NOT NULL,
			item_id INTEGER NOT NULL DEFAULT 0,
			shards INTEGER NOT NULL DEFAULT 0,
			granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			PRIMARY KEY (player_id, week_start)
		)`,
	} {
		if _, err := db.ExecContext(ctx, statement); err != nil {
			t.Fatalf("create test table: %v\n%s", err, statement)
		}
	}

	var playerID int64
	if err := db.QueryRowContext(ctx,
		`INSERT INTO players (nickname) VALUES ('Квест') RETURNING id`,
	).Scan(&playerID); err != nil {
		t.Fatalf("insert player: %v", err)
	}
	// One easy quest that a single match completes: metric matches, target 1.
	day := questDayKey(time.Now())
	if _, err := db.ExecContext(ctx,
		`INSERT INTO daily_quest_days (player_id, quest_day, seed) VALUES ($1, $2, 1)`,
		playerID, day); err != nil {
		t.Fatalf("insert quest day: %v", err)
	}
	if _, err := db.ExecContext(ctx, `
		INSERT INTO daily_quests (player_id, quest_day, slot, template_id, metric, target, reward_shards, reward_xp)
		VALUES ($1, $2, 1, 'play_1', 'matches', 1, 3, 150)
	`, playerID, day); err != nil {
		t.Fatalf("insert daily quest: %v", err)
	}

	hub := newWebSocketHub(db)
	result := matchResultPlayer{
		playerID:    playerID,
		team:        0,
		kills:       8,
		deaths:      2,
		damage:      4000,
		crystals:    2,
		shells:      1,
		shopItems:   2,
		durationSec: 240,
		classKey:    "warrior",
	}
	const roomID = int64(987654321)
	hub.saveMatch(roomID, []matchResultPlayer{result}, 0)

	var durationSec, kills, deaths, damage, crystals, shells, shopItems int
	var classKey string
	var won bool
	if err := db.QueryRowContext(ctx, `
		SELECT duration_sec, kills, deaths, damage, crystals, shells, shop_items, class_key, won
		FROM matches WHERE room_id = $1 AND player_id = $2
	`, roomID, playerID).Scan(&durationSec, &kills, &deaths, &damage, &crystals, &shells, &shopItems, &classKey, &won); err != nil {
		t.Fatalf("read saved match: %v", err)
	}
	if durationSec != 240 || kills != 8 || deaths != 2 || damage != 4000 ||
		crystals != 2 || shells != 1 || shopItems != 2 || classKey != "warrior" || !won {
		t.Fatalf("saved counters differ: duration=%d kills=%d deaths=%d damage=%d crystals=%d shells=%d shop=%d class=%q won=%v",
			durationSec, kills, deaths, damage, crystals, shells, shopItems, classKey, won)
	}

	var progress int
	var completedAt sql.NullTime
	if err := db.QueryRowContext(ctx,
		`SELECT progress, completed_at FROM daily_quests WHERE player_id = $1 AND slot = 1`,
		playerID).Scan(&progress, &completedAt); err != nil {
		t.Fatalf("read quest progress: %v", err)
	}
	if progress < 1 || !completedAt.Valid {
		t.Fatalf("quest did not complete from the saved match: progress=%d completed=%v", progress, completedAt)
	}
	var shardsAfterMatch int
	if err := db.QueryRowContext(ctx, `SELECT sky_shards FROM players WHERE id = $1`, playerID).Scan(&shardsAfterMatch); err != nil {
		t.Fatalf("read shards: %v", err)
	}
	if shardsAfterMatch < 3 {
		t.Fatalf("quest reward was not paid: shards=%d", shardsAfterMatch)
	}

	// A repeated finish of the same room must not insert a second row, roll the
	// progress again or pay the reward twice.
	hub.saveMatch(roomID, []matchResultPlayer{result}, 0)
	var rows int
	if err := db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM matches WHERE room_id = $1 AND player_id = $2`,
		roomID, playerID).Scan(&rows); err != nil {
		t.Fatalf("count match rows: %v", err)
	}
	if rows != 1 {
		t.Fatalf("repeated finish saved %d match rows, want 1", rows)
	}
	var progressAfter, shardsAfterRepeat int
	if err := db.QueryRowContext(ctx,
		`SELECT progress FROM daily_quests WHERE player_id = $1 AND slot = 1`,
		playerID).Scan(&progressAfter); err != nil {
		t.Fatalf("read quest progress after repeat: %v", err)
	}
	if err := db.QueryRowContext(ctx, `SELECT sky_shards FROM players WHERE id = $1`, playerID).Scan(&shardsAfterRepeat); err != nil {
		t.Fatalf("read shards after repeat: %v", err)
	}
	if progressAfter != progress || shardsAfterRepeat != shardsAfterMatch {
		t.Fatalf("repeated finish advanced the quest: progress %d -> %d, shards %d -> %d",
			progress, progressAfter, shardsAfterMatch, shardsAfterRepeat)
	}
}
