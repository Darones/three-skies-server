package main

import (
	"database/sql"
	"errors"
	"log"
	"net/http"
	"time"
)

const noviceInterstitialCooldown = 30 * time.Minute
const minMatchesForAds = 3

type interstitialRequest struct {
	PlayerID int64 `json:"player_id"`
}

type interstitialResponse struct {
	Success            bool   `json:"success"`
	LastInterstitialAt int64  `json:"last_interstitial_at"`
	Error              string `json:"error,omitempty"`
}

// handleInterstitialShown records a completed interstitial. The client only
// calls it after the VK ad promise resolved successfully; the server still
// enforces the battle gate and the novice 30-minute cooldown across devices.
func (service *api) handleInterstitialShown(w http.ResponseWriter, r *http.Request) {
	if !requirePost(w, r) {
		return
	}
	var request interstitialRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, interstitialResponse{Error: "Invalid JSON"})
		return
	}
	if !service.requireSession(w, r, request.PlayerID) {
		return
	}
	transaction, err := service.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, interstitialResponse{Error: "Internal server error"})
		return
	}
	defer transaction.Rollback()
	var matchesPlayed int
	var novice bool
	var lastShown float64
	err = transaction.QueryRowContext(r.Context(),
		`SELECT COALESCE(matches_played, 0), COALESCE(novice, FALSE),
		        COALESCE(EXTRACT(EPOCH FROM last_interstitial_at), 0)
		 FROM players WHERE id = $1 FOR UPDATE`, request.PlayerID,
	).Scan(&matchesPlayed, &novice, &lastShown)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, interstitialResponse{Error: "Player not found"})
		return
	}
	if err != nil {
		log.Printf("load interstitial state: %v", err)
		writeJSON(w, http.StatusInternalServerError, interstitialResponse{Error: "Internal server error"})
		return
	}
	if matchesPlayed < minMatchesForAds {
		writeJSON(w, http.StatusConflict, interstitialResponse{Error: "Not enough matches"})
		return
	}
	now := time.Now()
	if novice && lastShown > 0 && now.Sub(time.Unix(int64(lastShown), 0)) < noviceInterstitialCooldown {
		writeJSON(w, http.StatusTooManyRequests, interstitialResponse{Error: "cooldown"})
		return
	}
	var shownAt float64
	if err := transaction.QueryRowContext(r.Context(),
		`UPDATE players SET last_interstitial_at = NOW() WHERE id = $1
		 RETURNING EXTRACT(EPOCH FROM last_interstitial_at)`, request.PlayerID,
	).Scan(&shownAt); err != nil {
		log.Printf("record interstitial: %v", err)
		writeJSON(w, http.StatusInternalServerError, interstitialResponse{Error: "Internal server error"})
		return
	}
	if err := transaction.Commit(); err != nil {
		writeJSON(w, http.StatusInternalServerError, interstitialResponse{Error: "Internal server error"})
		return
	}
	writeJSON(w, http.StatusOK, interstitialResponse{Success: true, LastInterstitialAt: int64(shownAt)})
}
