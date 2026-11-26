package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
)

const maxCharacterLevel = 15
const maxTutorialBattles = 10000
const maxMatchXP = 2000

var levelUpShardRewards = map[int]int{
	1: 50, 2: 75, 3: 100, 4: 125, 5: 150,
	6: 175, 7: 200, 8: 225, 9: 250, 10: 300,
	11: 325, 12: 350, 13: 375, 14: 400, 15: 450,
}

var characterKeys = []string{"warrior", "mage", "fairy"}

type progressState struct {
	CharLevels          map[string]int
	CharXPs             map[string]int
	TutorialCompleted   bool
	TutorialSkipped     bool
	TutorialBattlesUsed int
	ProgressInitialized bool
}

type progressRequest struct {
	PlayerID            int64          `json:"player_id"`
	CharLevels          map[string]int `json:"char_levels"`
	CharXPs             map[string]int `json:"char_xps"`
	TutorialCompleted   bool           `json:"tutorial_completed"`
	TutorialSkipped     bool           `json:"tutorial_skipped"`
	TutorialBattlesUsed int            `json:"tutorial_battles_used"`
}

type progressResponse struct {
	Success             bool           `json:"success"`
	CharLevels          map[string]int `json:"char_levels,omitempty"`
	CharXPs             map[string]int `json:"char_xps,omitempty"`
	TutorialCompleted   bool           `json:"tutorial_completed"`
	TutorialSkipped     bool           `json:"tutorial_skipped"`
	TutorialBattlesUsed int            `json:"tutorial_battles_used"`
	ProgressInitialized bool           `json:"progress_initialized"`
	Error               string         `json:"error,omitempty"`
}

func defaultCharacterLevels() map[string]int {
	return map[string]int{"warrior": 1, "mage": 1, "fairy": 1}
}

func defaultCharacterXPs() map[string]int {
	return map[string]int{"warrior": 0, "mage": 0, "fairy": 0}
}

func sanitizeProgress(levels, xps map[string]int, completed, skipped bool, battles int) progressState {
	cleanLevels := defaultCharacterLevels()
	cleanXPs := defaultCharacterXPs()
	for _, key := range characterKeys {
		level := cleanLevels[key]
		if value, ok := levels[key]; ok {
			level = clampInt(value, 1, maxCharacterLevel)
		}
		xp := 0
		if value, ok := xps[key]; ok {
			xp = value
		}
		if level >= maxCharacterLevel {
			xp = 0
		} else {
			xp = clampInt(xp, 0, level*1000-1)
		}
		cleanLevels[key] = level
		cleanXPs[key] = xp
	}
	if completed {
		skipped = false
	} else if skipped {
		completed = false
	}
	return progressState{
		CharLevels:          cleanLevels,
		CharXPs:             cleanXPs,
		TutorialCompleted:   completed,
		TutorialSkipped:     skipped,
		TutorialBattlesUsed: clampInt(battles, 0, maxTutorialBattles),
		ProgressInitialized: true,
	}
}

func clampInt(value, minimum, maximum int) int {
	if value < minimum {
		return minimum
	}
	if value > maximum {
		return maximum
	}
	return value
}

func decodeProgress(levelsJSON, xpsJSON string) progressState {
	levels := defaultCharacterLevels()
	xps := defaultCharacterXPs()
	if strings.TrimSpace(levelsJSON) != "" {
		_ = json.Unmarshal([]byte(levelsJSON), &levels)
	}
	if strings.TrimSpace(xpsJSON) != "" {
		_ = json.Unmarshal([]byte(xpsJSON), &xps)
	}
	return sanitizeProgress(levels, xps, false, false, 0)
}

func decodeStoredProgress(levelsJSON, xpsJSON string, completed, skipped bool, battles int, initialized bool) progressState {
	state := decodeProgress(levelsJSON, xpsJSON)
	state.TutorialCompleted = completed
	state.TutorialSkipped = skipped
	state.TutorialBattlesUsed = clampInt(battles, 0, maxTutorialBattles)
	state.ProgressInitialized = initialized
	return state
}

func validCharacterKey(character string) bool {
	for _, key := range characterKeys {
		if key == character {
			return true
		}
	}
	return false
}

// applyCharacterXP adds XP inside the match-reward transaction. The server
// owns the level curve and the level-up shard bonus, so a replayed reward or a
// forged client XP value cannot create arbitrary levels.
func applyCharacterXP(ctx context.Context, tx *sql.Tx, playerID int64, character string, amount int) (map[string]int, map[string]int, []int, int, error) {
	levels := defaultCharacterLevels()
	xps := defaultCharacterXPs()
	levelUps := []int{}
	shardReward := 0
	if amount < 0 {
		amount = 0
	}
	if amount > maxMatchXP {
		amount = maxMatchXP
	}
	var levelsJSON, xpsJSON string
	if err := tx.QueryRowContext(ctx,
		`SELECT COALESCE(char_levels::text, ''), COALESCE(char_xps::text, '')
		 FROM players WHERE id = $1 FOR UPDATE`, playerID,
	).Scan(&levelsJSON, &xpsJSON); err != nil {
		return nil, nil, nil, 0, err
	}
	if strings.TrimSpace(levelsJSON) != "" {
		_ = json.Unmarshal([]byte(levelsJSON), &levels)
	}
	if strings.TrimSpace(xpsJSON) != "" {
		_ = json.Unmarshal([]byte(xpsJSON), &xps)
	}
	if !validCharacterKey(character) {
		return levels, xps, levelUps, 0, nil
	}
	level := clampInt(levels[character], 1, maxCharacterLevel)
	xp := clampInt(xps[character], 0, maxCharacterLevel*1000)
	if level >= maxCharacterLevel {
		level = maxCharacterLevel
		xp = 0
	} else {
		xp += amount
		for level < maxCharacterLevel && xp >= level*1000 {
			xp -= level * 1000
			level++
			levelUps = append(levelUps, level)
			shardReward += levelUpShardRewards[level]
		}
		if level >= maxCharacterLevel {
			xp = 0
		}
	}
	levels[character] = level
	xps[character] = xp
	encodedLevels, err := json.Marshal(levels)
	if err != nil {
		return nil, nil, nil, 0, err
	}
	encodedXPs, err := json.Marshal(xps)
	if err != nil {
		return nil, nil, nil, 0, err
	}
	if _, err := tx.ExecContext(ctx,
		`UPDATE players SET char_levels = $1::jsonb, char_xps = $2::jsonb WHERE id = $3`,
		string(encodedLevels), string(encodedXPs), playerID,
	); err != nil {
		return nil, nil, nil, 0, err
	}
	return levels, xps, levelUps, shardReward, nil
}

// mergeProgressUpdate decides what /progress is allowed to write.
//
// Before the first import the client may seed levels and XP (old standalone
// profiles). After progress_initialized=TRUE the server owns the level curve:
// client levels/xps are ignored, so a client cannot roll levels back to farm
// level-up shards on the next /match_reward, and cannot raise them either.
// Tutorial flags stay client-driven because they are not a reward source.
func mergeProgressUpdate(stored, incoming progressState) progressState {
	if !stored.ProgressInitialized {
		incoming.ProgressInitialized = true
		return incoming
	}
	return progressState{
		CharLevels:          copyProgressMap(stored.CharLevels, 1),
		CharXPs:             copyProgressMap(stored.CharXPs, 0),
		TutorialCompleted:   incoming.TutorialCompleted,
		TutorialSkipped:     incoming.TutorialSkipped,
		TutorialBattlesUsed: incoming.TutorialBattlesUsed,
		ProgressInitialized: true,
	}
}

func copyProgressMap(source map[string]int, fallback int) map[string]int {
	copied := make(map[string]int, len(characterKeys))
	for _, key := range characterKeys {
		copied[key] = fallback
		if source != nil {
			if value, ok := source[key]; ok {
				copied[key] = value
			}
		}
	}
	return copied
}

func (service *api) handleProgress(w http.ResponseWriter, r *http.Request) {
	if !requirePost(w, r) {
		return
	}
	var request progressRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, progressResponse{Error: "Invalid JSON"})
		return
	}
	if !service.requireSession(w, r, request.PlayerID) {
		return
	}
	incoming := sanitizeProgress(
		request.CharLevels,
		request.CharXPs,
		request.TutorialCompleted,
		request.TutorialSkipped,
		request.TutorialBattlesUsed,
	)

	transaction, err := service.db.BeginTx(r.Context(), nil)
	if err != nil {
		log.Printf("begin player progress: %v", err)
		writeJSON(w, http.StatusInternalServerError, progressResponse{Error: "Internal server error"})
		return
	}
	defer transaction.Rollback()

	var levelsJSON, xpsJSON string
	var tutorialCompleted, tutorialSkipped, initialized bool
	var tutorialBattlesUsed int
	err = transaction.QueryRowContext(r.Context(),
		`SELECT COALESCE(char_levels::text, ''), COALESCE(char_xps::text, ''),
		        COALESCE(tutorial_completed, FALSE), COALESCE(tutorial_skipped, FALSE),
		        COALESCE(tutorial_battles_used, 0), COALESCE(progress_initialized, FALSE)
		 FROM players WHERE id = $1 FOR UPDATE`, request.PlayerID,
	).Scan(&levelsJSON, &xpsJSON, &tutorialCompleted, &tutorialSkipped,
		&tutorialBattlesUsed, &initialized)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, progressResponse{Error: "Player not found"})
		return
	}
	if err != nil {
		log.Printf("load player progress: %v", err)
		writeJSON(w, http.StatusInternalServerError, progressResponse{Error: "Internal server error"})
		return
	}

	stored := decodeStoredProgress(levelsJSON, xpsJSON, tutorialCompleted, tutorialSkipped, tutorialBattlesUsed, initialized)
	state := mergeProgressUpdate(stored, incoming)

	encodedLevels, err := json.Marshal(state.CharLevels)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, progressResponse{Error: "Internal server error"})
		return
	}
	encodedXPs, err := json.Marshal(state.CharXPs)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, progressResponse{Error: "Internal server error"})
		return
	}
	if _, err := transaction.ExecContext(r.Context(), `
		UPDATE players
		SET char_levels = $1::jsonb,
		    char_xps = $2::jsonb,
		    tutorial_completed = $3,
		    tutorial_skipped = $4,
		    tutorial_battles_used = $5,
		    progress_initialized = TRUE
		WHERE id = $6
	`, string(encodedLevels), string(encodedXPs), state.TutorialCompleted, state.TutorialSkipped, state.TutorialBattlesUsed, request.PlayerID); err != nil {
		log.Printf("save player progress: %v", err)
		writeJSON(w, http.StatusInternalServerError, progressResponse{Error: "Internal server error"})
		return
	}
	if err := transaction.Commit(); err != nil {
		log.Printf("commit player progress: %v", err)
		writeJSON(w, http.StatusInternalServerError, progressResponse{Error: "Internal server error"})
		return
	}
	writeJSON(w, http.StatusOK, progressResponse{
		Success:             true,
		CharLevels:          state.CharLevels,
		CharXPs:             state.CharXPs,
		TutorialCompleted:   state.TutorialCompleted,
		TutorialSkipped:     state.TutorialSkipped,
		TutorialBattlesUsed: state.TutorialBattlesUsed,
		ProgressInitialized: true,
	})
}
