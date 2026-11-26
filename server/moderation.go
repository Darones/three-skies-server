package main

import (
	"context"
	"crypto/subtle"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// Manual nickname moderation. The page is private: it is protected by the same
// ADMIN_TOKEN as /admin/grant_shards and is not linked from the game. Reports
// come from the in-game "Пожаловаться" button (/report); nicknames are the
// player's VK first/last name, so a moderator decides what to do by hand.

const (
	moderationPagePath    = "/admin/moderation"
	moderationReportsPath = "/admin/moderation/reports"
	moderationPlayersPath = "/admin/moderation/players"

	moderationStatusOpen     = "open"
	moderationStatusResolved = "resolved"

	// moderationPlayersDefaultLimit is the page size used when the players
	// endpoint is called without limit (the pre-pagination behaviour).
	moderationPlayersDefaultLimit = 100
	// moderationPlayersMaxLimit caps one players page so a typo like
	// limit=1000000 cannot load the whole table into memory.
	moderationPlayersMaxLimit = 500

	// accountBannedError is the machine-readable ban code shared by /profile,
	// /session and the WebSocket join. Clients must show a ban screen instead
	// of retrying the normal flow.
	accountBannedError = "account_banned"
	// hiddenNickname replaces a moderated nickname everywhere other players can
	// see it: the profile payload and the match/lobby roster.
	hiddenNickname = "Игрок"
)

// moderationActions are the decisions a moderator can take on one report.
var moderationActions = map[string]bool{
	"dismiss":         true,
	"hide_nickname":   true,
	"unhide_nickname": true,
	"warn":            true,
	"ban":             true,
	"unban":           true,
}

// playerModerationActions can be applied to a player directly from the players
// table, without an open report.
var playerModerationActions = map[string]bool{
	"hide_nickname":   true,
	"unhide_nickname": true,
	"warn":            true,
	"ban":             true,
	"unban":           true,
	"grant_xp":        true,
	"remove_weapon":   true,
	"clear_weapons":   true,
}

var (
	errModerationPlayerNotFound   = errors.New("player not found")
	errModerationAmbiguous        = errors.New("nickname belongs to several players")
	errModerationUnknownCharacter = errors.New("unknown character")
	errModerationInvalidItemID    = errors.New("invalid item id")
)

// maxCharacterTotalXP is the XP needed to reach maxCharacterLevel (15):
// sum(1..14) * 1000. The last level has no further requirement and stores xp=0.
const maxCharacterTotalXP = 105000

// adminCharacterXPUpdateQuery deliberately touches only the XP maps and the
// progress lock: an admin XP edit is a test operation, must not pay level-up
// shards, and must not be overwritten by the next client /progress import.
const adminCharacterXPUpdateQuery = `
UPDATE players SET char_levels = $1::jsonb, char_xps = $2::jsonb, progress_initialized = TRUE WHERE id = $3`

type moderationReport struct {
	ID               int64      `json:"id"`
	ReporterID       int64      `json:"reporter_id"`
	ReporterNickname string     `json:"reporter_nickname"`
	ReportedNickname string     `json:"reported_nickname"`
	ReportedPlayerID int64      `json:"reported_player_id"`
	PlayerID         int64      `json:"player_id"`
	PlayerNickname   string     `json:"player_nickname"`
	Platform         string     `json:"platform"`
	MatchesPlayed    int        `json:"matches_played"`
	LastSeenAt       *time.Time `json:"last_seen_at"`
	RoomID           int64      `json:"room_id"`
	Reason           string     `json:"reason"`
	CreatedAt        time.Time  `json:"created_at"`
	HoursOpen        float64    `json:"hours_open"`
	Status           string     `json:"status"`
	Action           string     `json:"action"`
	ResolvedAt       *time.Time `json:"resolved_at"`
	NicknameHidden   bool       `json:"nickname_hidden"`
	Banned           bool       `json:"banned"`
	BanReason        string     `json:"ban_reason"`
	NicknameMatches  int        `json:"nickname_matches"`
}

type moderationPlayer struct {
	ID                int64          `json:"id"`
	Nickname          string         `json:"nickname"`
	Platform          string         `json:"platform"`
	MatchesPlayed     int            `json:"matches_played"`
	SkyShards         int            `json:"sky_shards"`
	Level             int            `json:"level"`
	UnlockedWeapons   string         `json:"unlocked_weapons"`
	CharLevels        map[string]int `json:"char_levels"`
	CharXPs           map[string]int `json:"char_xps"`
	LastSeenAt        *time.Time     `json:"last_seen_at"`
	ReportsCount      int            `json:"reports_count"`
	NicknameHidden    bool           `json:"nickname_hidden"`
	Banned            bool           `json:"banned"`
	BanReason         string         `json:"ban_reason"`
	Warnings          int            `json:"warnings"`
	LastWarningReason string         `json:"last_warning_reason"`
	LastWarningAt     *time.Time     `json:"last_warning_at"`
}

type moderationReportsResponse struct {
	Success bool               `json:"success"`
	Reports []moderationReport `json:"reports"`
	Error   string             `json:"error,omitempty"`
}

type moderationPlayersResponse struct {
	Success bool               `json:"success"`
	Players []moderationPlayer `json:"players"`
	Total   int                `json:"total"`
	Limit   int                `json:"limit"`
	Offset  int                `json:"offset"`
	Error   string             `json:"error,omitempty"`
}

type moderationActionRequest struct {
	Action    string `json:"action"`
	PlayerID  int64  `json:"player_id"`
	BanReason string `json:"ban_reason"`
	Reason    string `json:"reason"`
	Character string `json:"character"`
	Amount    int    `json:"amount"`
	ItemID    int    `json:"item_id"`
}

type moderationActionResponse struct {
	Success         bool           `json:"success"`
	ReportID        int64          `json:"report_id,omitempty"`
	PlayerID        int64          `json:"player_id,omitempty"`
	Action          string         `json:"action,omitempty"`
	Character       string         `json:"character,omitempty"`
	Level           *int           `json:"level,omitempty"`
	XP              *int           `json:"xp,omitempty"`
	TotalXP         *int           `json:"total_xp,omitempty"`
	CharLevels      map[string]int `json:"char_levels,omitempty"`
	CharXPs         map[string]int `json:"char_xps,omitempty"`
	UnlockedWeapons string         `json:"unlocked_weapons"`
	Error           string         `json:"error,omitempty"`
}

func adminTokenValid(value string) bool {
	expected := adminTokenValue()
	if expected == "" || value == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(value), []byte(expected)) == 1
}

// adminAuthorized accepts the token from the X-Admin-Token header or from the
// token query parameter (the moderation page puts it in the URL). The token is
// never logged.
func (service *api) adminAuthorized(r *http.Request) bool {
	token := strings.TrimSpace(r.Header.Get("X-Admin-Token"))
	if token == "" {
		token = strings.TrimSpace(r.URL.Query().Get("token"))
	}
	return adminTokenValid(token)
}

func (service *api) requireModerationJSON(w http.ResponseWriter, r *http.Request) bool {
	if service.adminAuthorized(r) {
		return true
	}
	writeJSON(w, http.StatusForbidden, moderationActionResponse{Error: "Forbidden"})
	return false
}

// publicNickname is the only place a moderated nickname is replaced. It is
// used by the profile payload and by the match/lobby roster, so the original
// string never reaches another player.
func publicNickname(nickname string, hidden bool) string {
	if hidden {
		return hiddenNickname
	}
	return nickname
}

// writeBannedProfile answers /profile without any game data or session token.
// The ban is distinguishable by error="account_banned" and the banned flag, so
// the client can stop retrying instead of treating it as a network failure.
func (service *api) writeBannedProfile(w http.ResponseWriter, reason string) {
	writeJSON(w, http.StatusForbidden, playerProfileResponse{
		Success:   false,
		Banned:    true,
		BanReason: reason,
		Error:     accountBannedError,
	})
}

// writeBannedSession answers /session the same way: no token, a distinct code.
func (service *api) writeBannedSession(w http.ResponseWriter, reason string) {
	writeJSON(w, http.StatusForbidden, sessionResponse{
		Success:   false,
		Banned:    true,
		BanReason: reason,
		Error:     accountBannedError,
	})
}

func (service *api) requireModerationPage(w http.ResponseWriter, r *http.Request) bool {
	if service.adminAuthorized(r) {
		return true
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	http.Error(w, "forbidden", http.StatusForbidden)
	return false
}

func (service *api) handleModerationPage(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !service.requireModerationPage(w, r) {
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("X-Frame-Options", "DENY")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	// The page is one self-contained file: inline CSS/JS and same-origin fetch.
	w.Header().Set("Content-Security-Policy",
		"default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'self'")
	fmt.Fprint(w, moderationPageHTML)
}

func (service *api) handleModerationReports(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeJSON(w, http.StatusMethodNotAllowed, moderationReportsResponse{Error: "Method not allowed"})
		return
	}
	if !service.requireModerationJSON(w, r) {
		return
	}
	status := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("status")))
	if status == "" {
		status = moderationStatusOpen
	}
	if status != moderationStatusOpen && status != moderationStatusResolved && status != "all" {
		writeJSON(w, http.StatusBadRequest, moderationReportsResponse{Error: "Unknown status filter"})
		return
	}
	if service.db == nil {
		writeJSON(w, http.StatusServiceUnavailable, moderationReportsResponse{Error: "Database unavailable"})
		return
	}

	rows, err := service.db.QueryContext(r.Context(), moderationReportsQuery, status)
	if err != nil {
		log.Printf("moderation reports: %v", err)
		writeJSON(w, http.StatusInternalServerError, moderationReportsResponse{Error: "Internal server error"})
		return
	}
	defer rows.Close()

	reports := make([]moderationReport, 0, 32)
	for rows.Next() {
		var report moderationReport
		var lastSeen sql.NullTime
		var resolvedAt sql.NullTime
		if err := rows.Scan(
			&report.ID, &report.ReporterID, &report.ReporterNickname,
			&report.ReportedNickname, &report.ReportedPlayerID,
			&report.PlayerID, &report.PlayerNickname, &report.Platform,
			&report.MatchesPlayed, &lastSeen, &report.RoomID,
			&report.Reason, &report.CreatedAt, &report.HoursOpen,
			&report.Status, &report.Action, &resolvedAt,
			&report.NicknameHidden, &report.Banned, &report.BanReason,
			&report.NicknameMatches,
		); err != nil {
			log.Printf("scan moderation report: %v", err)
			writeJSON(w, http.StatusInternalServerError, moderationReportsResponse{Error: "Internal server error"})
			return
		}
		report.LastSeenAt = nullableTime(lastSeen)
		report.ResolvedAt = nullableTime(resolvedAt)
		reports = append(reports, report)
	}
	if err := rows.Err(); err != nil {
		log.Printf("iterate moderation reports: %v", err)
		writeJSON(w, http.StatusInternalServerError, moderationReportsResponse{Error: "Internal server error"})
		return
	}
	writeJSON(w, http.StatusOK, moderationReportsResponse{Success: true, Reports: reports})
}

func (service *api) handleModerationPlayers(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeJSON(w, http.StatusMethodNotAllowed, moderationPlayersResponse{Error: "Method not allowed"})
		return
	}
	if !service.requireModerationJSON(w, r) {
		return
	}
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	query = truncateText(query, 64)
	all := parseModerationAll(r.URL.Query().Get("all"))
	limit, offset := parseModerationPagination(r.URL.Query().Get("limit"), r.URL.Query().Get("offset"))
	if service.db == nil {
		writeJSON(w, http.StatusServiceUnavailable, moderationPlayersResponse{Error: "Database unavailable"})
		return
	}

	rows, err := service.db.QueryContext(r.Context(), moderationPlayersQuery, query, all, limit, offset)
	if err != nil {
		log.Printf("moderation players: %v", err)
		writeJSON(w, http.StatusInternalServerError, moderationPlayersResponse{Error: "Internal server error"})
		return
	}
	defer rows.Close()

	players := make([]moderationPlayer, 0, 32)
	total := 0
	for rows.Next() {
		var player moderationPlayer
		var lastSeen sql.NullTime
		var lastWarningAt sql.NullTime
		var levelsJSON, xpsJSON string
		if err := rows.Scan(
			&player.ID, &player.Nickname, &player.Platform, &player.MatchesPlayed,
			&lastSeen, &player.ReportsCount, &player.NicknameHidden,
			&player.Banned, &player.BanReason, &player.Warnings,
			&player.LastWarningReason, &lastWarningAt,
			&player.SkyShards, &player.Level, &player.UnlockedWeapons,
			&levelsJSON, &xpsJSON, &total,
		); err != nil {
			log.Printf("scan moderation player: %v", err)
			writeJSON(w, http.StatusInternalServerError, moderationPlayersResponse{Error: "Internal server error"})
			return
		}
		progress := decodeProgress(levelsJSON, xpsJSON)
		player.CharLevels = progress.CharLevels
		player.CharXPs = progress.CharXPs
		player.LastSeenAt = nullableTime(lastSeen)
		player.LastWarningAt = nullableTime(lastWarningAt)
		players = append(players, player)
	}
	if err := rows.Err(); err != nil {
		log.Printf("iterate moderation players: %v", err)
		writeJSON(w, http.StatusInternalServerError, moderationPlayersResponse{Error: "Internal server error"})
		return
	}
	writeJSON(w, http.StatusOK, moderationPlayersResponse{
		Success: true,
		Players: players,
		Total:   total,
		Limit:   limit,
		Offset:  offset,
	})
}

// parseModerationPagination sanitizes the limit/offset query parameters of the
// players table. A missing, malformed or non-positive limit falls back to 100
// and never exceeds 500; offset is never negative. Atoi also rejects values
// that overflow int, so they behave like malformed input.
func parseModerationPagination(rawLimit, rawOffset string) (limit, offset int) {
	limit = moderationPlayersDefaultLimit
	if value, err := strconv.Atoi(strings.TrimSpace(rawLimit)); err == nil {
		switch {
		case value > moderationPlayersMaxLimit:
			limit = moderationPlayersMaxLimit
		case value > 0:
			limit = value
		}
	}
	if value, err := strconv.Atoi(strings.TrimSpace(rawOffset)); err == nil && value > 0 {
		offset = value
	}
	return limit, offset
}

// parseModerationAll accepts the common truthy spellings of ?all=, so a
// hand-typed admin URL works as well as the page's all=1.
func parseModerationAll(raw string) bool {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}

// handleModerationResolve applies a decision to one report and (when relevant)
// to the player the report points at.
func (service *api) handleModerationResolve(w http.ResponseWriter, r *http.Request) {
	if !service.requireModerationJSON(w, r) {
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeJSON(w, http.StatusMethodNotAllowed, moderationActionResponse{Error: "Method not allowed"})
		return
	}
	reportID, ok := parseModerationPath(r.URL.Path, moderationReportsPath+"/", "/resolve")
	if !ok {
		writeJSON(w, http.StatusBadRequest, moderationActionResponse{Error: "Invalid report id"})
		return
	}
	request, err := readModerationAction(w, r)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, moderationActionResponse{Error: "Invalid request"})
		return
	}
	action := strings.ToLower(strings.TrimSpace(request.Action))
	if !moderationActions[action] {
		writeJSON(w, http.StatusBadRequest, moderationActionResponse{Error: "Unknown action"})
		return
	}
	if service.db == nil {
		writeJSON(w, http.StatusServiceUnavailable, moderationActionResponse{Error: "Database unavailable"})
		return
	}

	transaction, err := service.db.BeginTx(r.Context(), nil)
	if err != nil {
		log.Printf("begin moderation resolve: %v", err)
		writeJSON(w, http.StatusInternalServerError, moderationActionResponse{Error: "Internal server error"})
		return
	}
	defer transaction.Rollback()

	var reportedNickname, reportReason, status string
	var reportedPlayerID sql.NullInt64
	err = transaction.QueryRowContext(r.Context(),
		`SELECT reported_nickname, reported_player_id, reason, status FROM reports WHERE id = $1 FOR UPDATE`,
		reportID,
	).Scan(&reportedNickname, &reportedPlayerID, &reportReason, &status)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, moderationActionResponse{Error: "Report not found"})
		return
	}
	if err != nil {
		log.Printf("load moderation report: %v", err)
		writeJSON(w, http.StatusInternalServerError, moderationActionResponse{Error: "Internal server error"})
		return
	}

	playerID := int64(0)
	if action != "dismiss" {
		playerID = request.PlayerID
		if playerID <= 0 && reportedPlayerID.Valid {
			playerID = reportedPlayerID.Int64
		}
		if playerID <= 0 {
			playerID, err = findModerationTarget(r.Context(), transaction, reportedNickname)
			if err != nil {
				switch {
				case errors.Is(err, errModerationPlayerNotFound):
					writeJSON(w, http.StatusNotFound, moderationActionResponse{Error: "Reported player not found; pass player_id"})
				case errors.Is(err, errModerationAmbiguous):
					writeJSON(w, http.StatusConflict, moderationActionResponse{Error: "Nickname belongs to several players; pass player_id"})
				default:
					log.Printf("resolve moderation target: %v", err)
					writeJSON(w, http.StatusInternalServerError, moderationActionResponse{Error: "Internal server error"})
				}
				return
			}
		} else if err := ensurePlayerExists(r.Context(), transaction, playerID); err != nil {
			if errors.Is(err, errModerationPlayerNotFound) {
				writeJSON(w, http.StatusNotFound, moderationActionResponse{Error: "Player not found"})
			} else {
				log.Printf("check moderation player: %v", err)
				writeJSON(w, http.StatusInternalServerError, moderationActionResponse{Error: "Internal server error"})
			}
			return
		}
		if err := applyPlayerModerationAction(r.Context(), transaction, playerID, action, moderationActionReason(request), reportReason); err != nil {
			log.Printf("apply moderation action: %v", err)
			writeJSON(w, http.StatusInternalServerError, moderationActionResponse{Error: "Internal server error"})
			return
		}
	}

	if _, err := transaction.ExecContext(r.Context(),
		`UPDATE reports SET status = $2, action = $3, resolved_at = NOW() WHERE id = $1`,
		reportID, moderationStatusResolved, action,
	); err != nil {
		log.Printf("resolve moderation report: %v", err)
		writeJSON(w, http.StatusInternalServerError, moderationActionResponse{Error: "Internal server error"})
		return
	}
	if err := transaction.Commit(); err != nil {
		log.Printf("commit moderation resolve: %v", err)
		writeJSON(w, http.StatusInternalServerError, moderationActionResponse{Error: "Internal server error"})
		return
	}

	log.Printf("[MODERATION] report=%d action=%s player=%d", reportID, action, playerID)
	writeJSON(w, http.StatusOK, moderationActionResponse{
		Success:  true,
		ReportID: reportID,
		PlayerID: playerID,
		Action:   action,
	})
}

// handleModerationPlayerAction applies ban/hide changes from the players table,
// where there is no single report to resolve. unban lives here too.
func (service *api) handleModerationPlayerAction(w http.ResponseWriter, r *http.Request) {
	if !service.requireModerationJSON(w, r) {
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeJSON(w, http.StatusMethodNotAllowed, moderationActionResponse{Error: "Method not allowed"})
		return
	}
	playerID, ok := parseModerationPath(r.URL.Path, moderationPlayersPath+"/", "/action")
	if !ok {
		writeJSON(w, http.StatusBadRequest, moderationActionResponse{Error: "Invalid player id"})
		return
	}
	request, err := readModerationAction(w, r)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, moderationActionResponse{Error: "Invalid request"})
		return
	}
	action := strings.ToLower(strings.TrimSpace(request.Action))
	if !playerModerationActions[action] {
		writeJSON(w, http.StatusBadRequest, moderationActionResponse{Error: "Unknown action"})
		return
	}
	request.Character = strings.ToLower(strings.TrimSpace(request.Character))
	if action == "grant_xp" && !validCharacterKey(request.Character) {
		writeJSON(w, http.StatusBadRequest, moderationActionResponse{Error: "Unknown character"})
		return
	}
	if action == "remove_weapon" && request.ItemID <= 0 {
		writeJSON(w, http.StatusBadRequest, moderationActionResponse{Error: "Invalid item id"})
		return
	}
	if service.db == nil {
		writeJSON(w, http.StatusServiceUnavailable, moderationActionResponse{Error: "Database unavailable"})
		return
	}

	transaction, err := service.db.BeginTx(r.Context(), nil)
	if err != nil {
		log.Printf("begin moderation player action: %v", err)
		writeJSON(w, http.StatusInternalServerError, moderationActionResponse{Error: "Internal server error"})
		return
	}
	defer transaction.Rollback()

	if isPlayerProgressAction(action) {
		response, err := applyPlayerProgressAction(r.Context(), transaction, playerID, action, request)
		if err != nil {
			switch {
			case errors.Is(err, errModerationPlayerNotFound):
				writeJSON(w, http.StatusNotFound, moderationActionResponse{Error: "Player not found"})
			case errors.Is(err, errModerationUnknownCharacter):
				writeJSON(w, http.StatusBadRequest, moderationActionResponse{Error: "Unknown character"})
			case errors.Is(err, errModerationInvalidItemID):
				writeJSON(w, http.StatusBadRequest, moderationActionResponse{Error: "Invalid item id"})
			default:
				log.Printf("apply player progress action: %v", err)
				writeJSON(w, http.StatusInternalServerError, moderationActionResponse{Error: "Internal server error"})
			}
			return
		}
		if err := transaction.Commit(); err != nil {
			log.Printf("commit player progress action: %v", err)
			writeJSON(w, http.StatusInternalServerError, moderationActionResponse{Error: "Internal server error"})
			return
		}
		response.Success = true
		response.PlayerID = playerID
		response.Action = action
		log.Printf("[MODERATION] player=%d action=%s", playerID, action)
		writeJSON(w, http.StatusOK, response)
		return
	}

	if err := applyPlayerModerationAction(r.Context(), transaction, playerID, action, moderationActionReason(request), ""); err != nil {
		if errors.Is(err, errModerationPlayerNotFound) {
			writeJSON(w, http.StatusNotFound, moderationActionResponse{Error: "Player not found"})
			return
		}
		log.Printf("apply moderation player action: %v", err)
		writeJSON(w, http.StatusInternalServerError, moderationActionResponse{Error: "Internal server error"})
		return
	}
	if err := transaction.Commit(); err != nil {
		log.Printf("commit moderation player action: %v", err)
		writeJSON(w, http.StatusInternalServerError, moderationActionResponse{Error: "Internal server error"})
		return
	}

	log.Printf("[MODERATION] player=%d action=%s", playerID, action)
	writeJSON(w, http.StatusOK, moderationActionResponse{
		Success:  true,
		PlayerID: playerID,
		Action:   action,
	})
}

// isPlayerProgressAction reports whether an action edits XP or the owned item
// list, which live in different columns than the ban/nickname flags.
func isPlayerProgressAction(action string) bool {
	switch action {
	case "grant_xp", "remove_weapon", "clear_weapons":
		return true
	default:
		return false
	}
}

// applyPlayerProgressAction edits XP and the owned weapon/skin list inside the
// caller's transaction. It never pays level-up shards: this is an admin test
// operation, not a match reward. Owned items are a comma-separated ID list
// (`players.unlocked_weapons`), shared by weapons 1..9 and skins 101..102.
func applyPlayerProgressAction(ctx context.Context, transaction *sql.Tx, playerID int64, action string, request moderationActionRequest) (moderationActionResponse, error) {
	var response moderationActionResponse
	switch action {
	case "grant_xp":
		character := strings.ToLower(strings.TrimSpace(request.Character))
		if !validCharacterKey(character) {
			return response, errModerationUnknownCharacter
		}
		var levelsJSON, xpsJSON string
		err := transaction.QueryRowContext(ctx,
			`SELECT COALESCE(char_levels::text, ''), COALESCE(char_xps::text, '')
			 FROM players WHERE id = $1 FOR UPDATE`, playerID,
		).Scan(&levelsJSON, &xpsJSON)
		if errors.Is(err, sql.ErrNoRows) {
			return response, errModerationPlayerNotFound
		}
		if err != nil {
			return response, err
		}
		state := decodeProgress(levelsJSON, xpsJSON)
		level, xp, total := applyCharacterXPDelta(
			state.CharLevels[character], state.CharXPs[character], request.Amount,
		)
		state.CharLevels[character] = level
		state.CharXPs[character] = xp
		encodedLevels, err := json.Marshal(state.CharLevels)
		if err != nil {
			return response, err
		}
		encodedXPs, err := json.Marshal(state.CharXPs)
		if err != nil {
			return response, err
		}
		if _, err := transaction.ExecContext(ctx,
			adminCharacterXPUpdateQuery,
			string(encodedLevels), string(encodedXPs), playerID,
		); err != nil {
			return response, err
		}
		response.Character = character
		response.Level = &level
		response.XP = &xp
		response.TotalXP = &total
		response.CharLevels = state.CharLevels
		response.CharXPs = state.CharXPs
	case "remove_weapon":
		if request.ItemID <= 0 {
			return response, errModerationInvalidItemID
		}
		var weapons string
		err := transaction.QueryRowContext(ctx,
			`SELECT COALESCE(unlocked_weapons, '') FROM players WHERE id = $1 FOR UPDATE`, playerID,
		).Scan(&weapons)
		if errors.Is(err, sql.ErrNoRows) {
			return response, errModerationPlayerNotFound
		}
		if err != nil {
			return response, err
		}
		updated := removeItemIDFromList(weapons, request.ItemID)
		if _, err := transaction.ExecContext(ctx,
			`UPDATE players SET unlocked_weapons = $1 WHERE id = $2`, updated, playerID,
		); err != nil {
			return response, err
		}
		response.UnlockedWeapons = updated
	case "clear_weapons":
		result, err := transaction.ExecContext(ctx,
			`UPDATE players SET unlocked_weapons = '' WHERE id = $1`, playerID,
		)
		if err != nil {
			return response, err
		}
		affected, err := result.RowsAffected()
		if err != nil {
			return response, err
		}
		if affected == 0 {
			return response, errModerationPlayerNotFound
		}
		response.UnlockedWeapons = ""
	}
	return response, nil
}

// characterTotalXP converts a level and the XP inside that level into lifetime
// XP. Reaching level L costs L*1000, so the curve is sum(1..L-1)*1000 + xp.
func characterTotalXP(level, xp int) int {
	level = clampInt(level, 1, maxCharacterLevel)
	if level >= maxCharacterLevel {
		return maxCharacterTotalXP
	}
	xp = clampInt(xp, 0, level*1000-1)
	return (level-1)*level/2*1000 + xp
}

// applyCharacterXPDelta applies an admin XP delta to one character and
// recalculates the level from the resulting lifetime XP. The total is clamped
// to [0, maxCharacterTotalXP], so a negative delta can empty a character and a
// positive one stops at level 15 with xp=0. It returns the new level, the XP
// inside that level and the new lifetime total; it never changes sky_shards.
func applyCharacterXPDelta(level, xp, delta int) (newLevel, newXP, total int) {
	total = characterTotalXP(level, xp)
	if delta > maxCharacterTotalXP {
		delta = maxCharacterTotalXP
	}
	if delta < -maxCharacterTotalXP {
		delta = -maxCharacterTotalXP
	}
	total = clampInt(total+delta, 0, maxCharacterTotalXP)
	newLevel = 1
	remaining := total
	for newLevel < maxCharacterLevel && remaining >= newLevel*1000 {
		remaining -= newLevel * 1000
		newLevel++
	}
	if newLevel >= maxCharacterLevel {
		return maxCharacterLevel, 0, total
	}
	return newLevel, remaining, total
}

// removeItemIDFromList removes one ID from the comma-separated owned-item list.
// It is idempotent, keeps the original order, drops invalid/duplicate IDs and
// returns "" for an empty result.
func removeItemIDFromList(value string, itemID int) string {
	ids := parseItemIDs(value)
	kept := make([]int, 0, len(ids))
	seen := make(map[int]bool, len(ids))
	for _, id := range ids {
		if id == itemID || seen[id] {
			continue
		}
		seen[id] = true
		kept = append(kept, id)
	}
	return formatItemIDList(kept)
}

func formatItemIDList(ids []int) string {
	parts := make([]string, 0, len(ids))
	for _, id := range ids {
		parts = append(parts, strconv.Itoa(id))
	}
	return strings.Join(parts, ",")
}

// moderationActionReason accepts both the legacy ban_reason field and the
// generic reason used by warnings, preferring the explicit reason.
func moderationActionReason(request moderationActionRequest) string {
	if reason := strings.TrimSpace(request.Reason); reason != "" {
		return reason
	}
	return strings.TrimSpace(request.BanReason)
}

func applyPlayerModerationAction(ctx context.Context, transaction *sql.Tx, playerID int64, action, actionReason, fallbackReason string) error {
	var statement string
	var arguments []any
	switch action {
	case "hide_nickname":
		statement = `UPDATE players SET nickname_hidden = TRUE WHERE id = $1`
		arguments = []any{playerID}
	case "unhide_nickname":
		statement = `UPDATE players SET nickname_hidden = FALSE WHERE id = $1`
		arguments = []any{playerID}
	case "warn":
		reason := strings.TrimSpace(actionReason)
		if reason == "" {
			reason = strings.TrimSpace(fallbackReason)
		}
		if reason == "" {
			reason = "Нарушение правил"
		}
		reason = truncateText(reason, 300)
		// Warnings are additive and keep the latest reason and timestamp.
		statement = `UPDATE players SET warnings = COALESCE(warnings, 0) + 1,
			last_warning_reason = $2, last_warning_at = NOW() WHERE id = $1`
		arguments = []any{playerID, reason}
	case "ban":
		reason := strings.TrimSpace(actionReason)
		if reason == "" {
			reason = strings.TrimSpace(fallbackReason)
		}
		reason = truncateText(reason, 300)
		statement = `UPDATE players SET banned = TRUE, ban_reason = $2 WHERE id = $1`
		arguments = []any{playerID, reason}
	case "unban":
		statement = `UPDATE players SET banned = FALSE, ban_reason = '' WHERE id = $1`
		arguments = []any{playerID}
	default:
		// dismiss does not touch player flags.
		return nil
	}
	result, err := transaction.ExecContext(ctx, statement, arguments...)
	if err != nil {
		return err
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if affected == 0 {
		return errModerationPlayerNotFound
	}
	return nil
}

func findModerationTarget(ctx context.Context, transaction *sql.Tx, nickname string) (int64, error) {
	rows, err := transaction.QueryContext(ctx,
		`SELECT id FROM players WHERE LOWER(BTRIM(nickname)) = LOWER(BTRIM($1)) ORDER BY id LIMIT 20`,
		nickname,
	)
	if err != nil {
		return 0, err
	}
	defer rows.Close()
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return 0, err
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return 0, err
	}
	switch len(ids) {
	case 0:
		return 0, errModerationPlayerNotFound
	case 1:
		return ids[0], nil
	default:
		return 0, errModerationAmbiguous
	}
}

func ensurePlayerExists(ctx context.Context, transaction *sql.Tx, playerID int64) error {
	var exists bool
	if err := transaction.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM players WHERE id = $1)`, playerID,
	).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		return errModerationPlayerNotFound
	}
	return nil
}

func readModerationAction(w http.ResponseWriter, r *http.Request) (moderationActionRequest, error) {
	var request moderationActionRequest
	contentType := strings.ToLower(r.Header.Get("Content-Type"))
	if strings.HasPrefix(contentType, "application/json") {
		if err := decodeJSON(w, r, &request); err != nil {
			return request, err
		}
		return request, nil
	}
	if err := r.ParseForm(); err != nil {
		return request, err
	}
	request.Action = r.PostForm.Get("action")
	request.BanReason = r.PostForm.Get("ban_reason")
	request.Reason = r.PostForm.Get("reason")
	request.Character = r.PostForm.Get("character")
	if raw := strings.TrimSpace(r.PostForm.Get("amount")); raw != "" {
		amount, err := strconv.Atoi(raw)
		if err != nil {
			return request, err
		}
		request.Amount = amount
	}
	if raw := strings.TrimSpace(r.PostForm.Get("item_id")); raw != "" {
		itemID, err := strconv.Atoi(raw)
		if err != nil {
			return request, err
		}
		request.ItemID = itemID
	}
	if raw := strings.TrimSpace(r.PostForm.Get("player_id")); raw != "" {
		playerID, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			return request, err
		}
		request.PlayerID = playerID
	}
	return request, nil
}

// parseModerationPath extracts {id} from "<prefix>{id}/<suffix>".
func parseModerationPath(path, prefix, suffix string) (int64, bool) {
	rest := strings.Trim(strings.TrimPrefix(path, prefix), "/")
	if !strings.HasSuffix(rest, suffix) {
		return 0, false
	}
	number := strings.Trim(strings.TrimSuffix(rest, suffix), "/")
	if number == "" || strings.Contains(number, "/") {
		return 0, false
	}
	id, err := strconv.ParseInt(number, 10, 64)
	if err != nil || id <= 0 {
		return 0, false
	}
	return id, true
}

func nullableTime(value sql.NullTime) *time.Time {
	if !value.Valid {
		return nil
	}
	result := value.Time
	return &result
}

// moderationReportsQuery joins the reporter and the reported player. Reports
// written before reported_player_id existed fall back to an exact nickname
// match; nickname_matches lets the page warn when that match is ambiguous.
const moderationReportsQuery = `
SELECT r.id, r.reporter_id, COALESCE(rep.nickname, ''),
       r.reported_nickname, COALESCE(r.reported_player_id, 0),
       COALESCE(p.id, 0), COALESCE(p.nickname, ''), COALESCE(p.platform, ''),
       COALESCE(p.matches_played, 0), p.last_seen_at, COALESCE(r.room_id, 0),
       r.reason, r.created_at,
       EXTRACT(EPOCH FROM (NOW() - r.created_at))::float8 / 3600.0,
       r.status, r.action, r.resolved_at,
       COALESCE(p.nickname_hidden, FALSE), COALESCE(p.banned, FALSE), COALESCE(p.ban_reason, ''),
       COALESCE(match_counts.cnt, 0)
FROM reports r
LEFT JOIN players rep ON rep.id = r.reporter_id
LEFT JOIN LATERAL (
    SELECT p2.id, p2.nickname, p2.platform, p2.matches_played, p2.last_seen_at,
           p2.nickname_hidden, p2.banned, p2.ban_reason
    FROM players p2
    WHERE (r.reported_player_id IS NOT NULL AND p2.id = r.reported_player_id)
       OR (r.reported_player_id IS NULL
           AND LOWER(BTRIM(p2.nickname)) = LOWER(BTRIM(r.reported_nickname))
           AND (SELECT COUNT(*) FROM players p4
                 WHERE LOWER(BTRIM(p4.nickname)) = LOWER(BTRIM(r.reported_nickname))) = 1)
    LIMIT 1
) p ON TRUE
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt FROM players p3
    WHERE LOWER(BTRIM(p3.nickname)) = LOWER(BTRIM(r.reported_nickname))
) match_counts ON TRUE
WHERE ($1 = 'all')
   OR ($1 = 'open' AND r.status = 'open')
   OR ($1 = 'resolved' AND r.status <> 'open')
ORDER BY CASE WHEN r.status = 'open' THEN 0 ELSE 1 END, r.created_at DESC
LIMIT 500`

// moderationPlayersQuery returns players with at least one report, a ban/hidden
// nick, or a recent login when no search is given. ?q= always searches every
// nickname, ?all=1 drops the 14-day/problem filter, and LIMIT/OFFSET paginate
// the same filtered set; COUNT(*) OVER() is the total before LIMIT.
const moderationPlayersQuery = `
SELECT p.id, p.nickname, COALESCE(p.platform, ''), COALESCE(p.matches_played, 0),
       p.last_seen_at,
       (SELECT COUNT(*) FROM reports r
         WHERE r.reported_player_id = p.id
            OR (r.reported_player_id IS NULL
                AND LOWER(BTRIM(r.reported_nickname)) = LOWER(BTRIM(p.nickname)))) AS reports_count,
       COALESCE(p.nickname_hidden, FALSE), COALESCE(p.banned, FALSE), COALESCE(p.ban_reason, ''),
       COALESCE(p.warnings, 0), COALESCE(p.last_warning_reason, ''), p.last_warning_at,
       COALESCE(p.sky_shards, 0), COALESCE(p.level, 1),
       COALESCE(p.unlocked_weapons, ''),
       COALESCE(p.char_levels::text, ''), COALESCE(p.char_xps::text, ''),
       COUNT(*) OVER() AS total
FROM players p
WHERE ($1 <> '' AND p.nickname ILIKE '%' || $1 || '%')
   OR ($1 = '' AND (
        $2::boolean
        OR COALESCE(p.banned, FALSE) OR COALESCE(p.nickname_hidden, FALSE)
        OR p.last_seen_at > NOW() - INTERVAL '14 days'
        OR EXISTS (SELECT 1 FROM reports r0
                    WHERE r0.reported_player_id = p.id
                       OR (r0.reported_player_id IS NULL
                           AND LOWER(BTRIM(r0.reported_nickname)) = LOWER(BTRIM(p.nickname))))))
ORDER BY COALESCE(p.banned, FALSE) DESC, reports_count DESC, p.last_seen_at DESC NULLS LAST, p.id DESC
LIMIT $3 OFFSET $4`
