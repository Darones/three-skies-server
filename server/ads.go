package main

import (
	"context"
	"database/sql"
	"errors"
	"log"
	"net/http"
	"time"
)

const noviceInterstitialCooldown = 30 * time.Minute
const minMatchesForAds = 3

// Match reward (x2 rewarded ad) answers. They are distinct on purpose:
// the client drops "Reward already claimed" for a base reward, so a match row
// that has not reached the database yet must not look like an already paid
// one, or a slow saveMatch would silently cost the player the whole payout.
const (
	rewardAlreadyClaimedError = "Reward already claimed"
	rewardBasePendingError    = "Base reward not claimed yet"
	matchNotRecordedError     = "Match not recorded"
)

// baseRewardCap is the server-side ceiling for one match payout: a win pays at
// most 5 shards, a loss at most 3. The client picks the 1/3/5 tier.
func baseRewardCap(won bool) int {
	if won {
		return 5
	}
	return 3
}

// bonusPayoutShards returns the shards for the separately idempotent x2 bonus.
// The base payout stored by handleMatchReward is authoritative, so the bonus
// always pays exactly the same amount again and the match pays 2x in total.
// Rows rewarded before reward_shards existed have no stored base; the client
// sends the already doubled total there, so paying it as the bonus would pay
// 3x. legacy caps that fallback to the base ceiling.
func bonusPayoutShards(storedShards, requestAmount int, won bool) (payout int, legacy bool) {
	if storedShards > 0 {
		return storedShards, false
	}
	payout = requestAmount
	if limit := baseRewardCap(won); payout > limit {
		payout = limit
	}
	return payout, true
}

// matchRewardClaimFailure explains why the FOR UPDATE claim found no row. The
// cases need different client behaviour: a match row that is not saved yet is
// retried, an already paid base reward is final, and a bonus that arrives
// before its base reward waits for the retry instead of being dropped.
func matchRewardClaimFailure(ctx context.Context, tx *sql.Tx, roomID, playerID int64, bonus bool) (int, string) {
	var recorded, basePaid bool
	err := tx.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM matches WHERE room_id = $1 AND player_id = $2),
		        EXISTS(SELECT 1 FROM matches WHERE room_id = $1 AND player_id = $2 AND COALESCE(rewarded, FALSE) = TRUE)`,
		roomID, playerID,
	).Scan(&recorded, &basePaid)
	if err != nil {
		log.Printf("inspect match reward room=%d player=%d: %v", roomID, playerID, err)
		return http.StatusInternalServerError, "Internal server error"
	}
	if !recorded {
		// saveMatch runs asynchronously from the match end; the results screen
		// can ask for the reward before the row is committed.
		log.Printf("match reward room=%d player=%d: match row not saved yet", roomID, playerID)
		return http.StatusConflict, matchNotRecordedError
	}
	if bonus && !basePaid {
		log.Printf("match x2 room=%d player=%d: bonus before the base reward", roomID, playerID)
		return http.StatusConflict, rewardBasePendingError
	}
	return http.StatusConflict, rewardAlreadyClaimedError
}

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
	// The server is the authority for a completed interstitial: the client only
	// calls this endpoint after the VK promise resolved, so this row is the
	// watched ad even if the client-side stats batch never flushes. The client
	// deliberately does not send its own ok=true ad_result for interstitial, so
	// the ad is never counted twice.
	service.recordStats(statsEvent{
		Event:    "ad_result",
		PlayerID: request.PlayerID,
		Payload: map[string]any{
			"format":    "interstitial",
			"placement": "results",
			"ok":        true,
			"source":    "server",
		},
	})
	writeJSON(w, http.StatusOK, interstitialResponse{Success: true, LastInterstitialAt: int64(shownAt)})
}
