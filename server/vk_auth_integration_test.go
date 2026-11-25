package main

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"testing"
	"time"

	_ "github.com/lib/pq"
)

// TestVKProfileMigrationIntegration runs the M2 migration and profile upsert
// against a real PostgreSQL copy. It is skipped unless TEST_DATABASE_URL is
// set, so normal unit tests never touch a database.
//
//	$env:TEST_DATABASE_URL = "postgres://user:pass@host:5432/dbname"
//	go test -run TestVKProfileMigrationIntegration -v ./...
func TestVKProfileMigrationIntegration(t *testing.T) {
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
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		t.Fatalf("ping database: %v", err)
	}

	schema := fmt.Sprintf("m2_test_%d", time.Now().UnixNano())
	if _, err := db.ExecContext(ctx, `CREATE SCHEMA `+schema); err != nil {
		t.Fatalf("create schema: %v", err)
	}
	defer db.ExecContext(context.Background(), `DROP SCHEMA `+schema+` CASCADE`)
	if _, err := db.ExecContext(ctx, `SET search_path TO `+schema); err != nil {
		t.Fatalf("set search_path: %v", err)
	}

	// Legacy shape: nickname UNIQUE, no platform/external_id.
	if _, err := db.ExecContext(ctx, `
		CREATE TABLE players (
			id SERIAL PRIMARY KEY,
			nickname TEXT UNIQUE NOT NULL,
			sky_shards INTEGER NOT NULL DEFAULT 0,
			unlocked_wings TEXT NOT NULL DEFAULT '',
			unlocked_weapons TEXT NOT NULL DEFAULT ''
		)
	`); err != nil {
		t.Fatalf("create legacy players: %v", err)
	}
	var legacyID int64
	if err := db.QueryRowContext(ctx,
		`INSERT INTO players (nickname, sky_shards) VALUES ('Старый', 17) RETURNING id`,
	).Scan(&legacyID); err != nil {
		t.Fatalf("insert legacy player: %v", err)
	}

	if err := createPlayersTable(ctx, db); err != nil {
		t.Fatalf("migration: %v", err)
	}
	// Idempotency: a second pass must not fail or drop the identity index.
	if err := createPlayersTable(ctx, db); err != nil {
		t.Fatalf("second migration: %v", err)
	}

	var platform, externalID string
	var shards int
	if err := db.QueryRowContext(ctx,
		`SELECT platform, external_id, sky_shards FROM players WHERE id = $1`, legacyID,
	).Scan(&platform, &externalID, &shards); err != nil {
		t.Fatalf("read legacy row: %v", err)
	}
	if platform != "standalone" || externalID != fmt.Sprint(legacyID) || shards != 17 {
		t.Fatalf("legacy row platform=%q external_id=%q shards=%d", platform, externalID, shards)
	}
	var indexCount int
	if err := db.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM pg_indexes
		WHERE schemaname = $1 AND indexname = 'players_platform_external_id_idx'
	`, schema).Scan(&indexCount); err != nil {
		t.Fatalf("read identity index: %v", err)
	}
	if indexCount != 1 {
		t.Fatalf("identity index count=%d, want 1", indexCount)
	}

	service := &api{db: db}
	first, err := service.upsertVKProfile(ctx, "111", "")
	if err != nil {
		t.Fatalf("first vk profile: %v", err)
	}
	again, err := service.upsertVKProfile(ctx, "111", "ВК Имя")
	if err != nil {
		t.Fatalf("second vk profile: %v", err)
	}
	if first.id != again.id {
		t.Fatalf("same vk_user_id created ids %d and %d", first.id, again.id)
	}
	if first.sessionToken == "" || first.sessionToken != again.sessionToken {
		t.Fatalf("session token was not reused: %q / %q", first.sessionToken, again.sessionToken)
	}
	if again.nickname != "ВК Имя" {
		t.Fatalf("display name=%q, want %q", again.nickname, "ВК Имя")
	}
	if !first.progressInitialized {
		t.Fatal("new VK profile must be progress-initialized (no local standalone upload)")
	}
	if first.levelsJSON == "" || first.xpsJSON == "" {
		t.Fatalf("progress maps are empty: %q / %q", first.levelsJSON, first.xpsJSON)
	}
	if _, err := db.ExecContext(ctx, `
		UPDATE players
		SET char_levels = '{"warrior":3,"mage":2,"fairy":1}'::jsonb,
		    char_xps = '{"warrior":250,"mage":900,"fairy":0}'::jsonb,
		    tutorial_completed = TRUE,
		    tutorial_skipped = FALSE,
		    tutorial_battles_used = 4
		WHERE id = $1`, first.id,
	); err != nil {
		t.Fatalf("seed progress: %v", err)
	}
	progressed, err := service.upsertVKProfile(ctx, "111", "")
	if err != nil {
		t.Fatalf("load progress: %v", err)
	}
	loaded := decodeStoredProgress(progressed.levelsJSON, progressed.xpsJSON, progressed.tutorialCompleted, progressed.tutorialSkipped, progressed.tutorialBattlesUsed, progressed.progressInitialized)
	if loaded.CharLevels["warrior"] != 3 || loaded.CharLevels["mage"] != 2 {
		t.Fatalf("loaded levels=%v", loaded.CharLevels)
	}
	if loaded.CharXPs["warrior"] != 250 || loaded.CharXPs["mage"] != 900 {
		t.Fatalf("loaded xps=%v", loaded.CharXPs)
	}
	if !loaded.TutorialCompleted || loaded.TutorialSkipped || loaded.TutorialBattlesUsed != 4 {
		t.Fatalf("loaded tutorial=%+v", loaded)
	}

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatalf("begin xp tx: %v", err)
	}
	levels, xps, levelUps, shardReward, err := applyCharacterXP(ctx, tx, first.id, "fairy", 1200)
	if err != nil {
		tx.Rollback()
		t.Fatalf("apply xp: %v", err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatalf("commit xp: %v", err)
	}
	if levels["fairy"] != 2 || xps["fairy"] != 200 {
		t.Fatalf("level curve level=%d xp=%d", levels["fairy"], xps["fairy"])
	}
	if len(levelUps) != 1 || levelUps[0] != 2 || shardReward != 75 {
		t.Fatalf("level ups=%v shards=%d", levelUps, shardReward)
	}

	if _, err := db.ExecContext(ctx,
		`UPDATE players SET last_interstitial_at = NOW() WHERE id = $1`, first.id,
	); err != nil {
		t.Fatalf("set interstitial: %v", err)
	}
	var lastShown float64
	if err := db.QueryRowContext(ctx,
		`SELECT EXTRACT(EPOCH FROM last_interstitial_at) FROM players WHERE id = $1`, first.id,
	).Scan(&lastShown); err != nil {
		t.Fatalf("read interstitial: %v", err)
	}
	if lastShown <= 0 {
		t.Fatalf("interstitial timestamp=%v", lastShown)
	}

	second, err := service.upsertVKProfile(ctx, "222", "Другой")
	if err != nil {
		t.Fatalf("second vk account: %v", err)
	}
	if second.id == first.id {
		t.Fatalf("different vk_user_id reused player id %d", first.id)
	}

	if _, err := db.ExecContext(ctx,
		`UPDATE players SET nickname = 'Свой', nickname_custom = TRUE WHERE id = $1`, first.id,
	); err != nil {
		t.Fatalf("set custom nickname: %v", err)
	}
	custom, err := service.upsertVKProfile(ctx, "111", "Новое Имя")
	if err != nil {
		t.Fatalf("custom nickname upsert: %v", err)
	}
	if custom.nickname != "Свой" {
		t.Fatalf("custom nickname overwritten: %q", custom.nickname)
	}
}
