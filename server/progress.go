package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
)

const maxCharacterLevel = 15
const maxTutorialBattles = 10000

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
	state := sanitizeProgress(
		request.CharLevels,
		request.CharXPs,
		request.TutorialCompleted,
		request.TutorialSkipped,
		request.TutorialBattlesUsed,
	)
	levelsJSON, err := json.Marshal(state.CharLevels)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, progressResponse{Error: "Internal server error"})
		return
	}
	xpsJSON, err := json.Marshal(state.CharXPs)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, progressResponse{Error: "Internal server error"})
		return
	}
	result, err := service.db.ExecContext(r.Context(), `
		UPDATE players
		SET char_levels = $1::jsonb,
		    char_xps = $2::jsonb,
		    tutorial_completed = $3,
		    tutorial_skipped = $4,
		    tutorial_battles_used = $5,
		    progress_initialized = TRUE
		WHERE id = $6
	`, string(levelsJSON), string(xpsJSON), state.TutorialCompleted, state.TutorialSkipped, state.TutorialBattlesUsed, request.PlayerID)
	if err != nil {
		log.Printf("save player progress: %v", err)
		writeJSON(w, http.StatusInternalServerError, progressResponse{Error: "Internal server error"})
		return
	}
	if affected, _ := result.RowsAffected(); affected == 0 {
		writeJSON(w, http.StatusNotFound, progressResponse{Error: "Player not found"})
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
