package main

import (
	"context"
	"crypto/subtle"
	"database/sql"
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
}

var (
	errModerationPlayerNotFound = errors.New("player not found")
	errModerationAmbiguous      = errors.New("nickname belongs to several players")
)

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
	ID                int64      `json:"id"`
	Nickname          string     `json:"nickname"`
	Platform          string     `json:"platform"`
	MatchesPlayed     int        `json:"matches_played"`
	LastSeenAt        *time.Time `json:"last_seen_at"`
	ReportsCount      int        `json:"reports_count"`
	NicknameHidden    bool       `json:"nickname_hidden"`
	Banned            bool       `json:"banned"`
	BanReason         string     `json:"ban_reason"`
	Warnings          int        `json:"warnings"`
	LastWarningReason string     `json:"last_warning_reason"`
	LastWarningAt     *time.Time `json:"last_warning_at"`
}

type moderationReportsResponse struct {
	Success bool               `json:"success"`
	Reports []moderationReport `json:"reports"`
	Error   string             `json:"error,omitempty"`
}

type moderationPlayersResponse struct {
	Success bool               `json:"success"`
	Players []moderationPlayer `json:"players"`
	Error   string             `json:"error,omitempty"`
}

type moderationActionRequest struct {
	Action    string `json:"action"`
	PlayerID  int64  `json:"player_id"`
	BanReason string `json:"ban_reason"`
	Reason    string `json:"reason"`
}

type moderationActionResponse struct {
	Success  bool   `json:"success"`
	ReportID int64  `json:"report_id,omitempty"`
	PlayerID int64  `json:"player_id,omitempty"`
	Action   string `json:"action,omitempty"`
	Error    string `json:"error,omitempty"`
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
	if service.db == nil {
		writeJSON(w, http.StatusServiceUnavailable, moderationPlayersResponse{Error: "Database unavailable"})
		return
	}

	rows, err := service.db.QueryContext(r.Context(), moderationPlayersQuery, query)
	if err != nil {
		log.Printf("moderation players: %v", err)
		writeJSON(w, http.StatusInternalServerError, moderationPlayersResponse{Error: "Internal server error"})
		return
	}
	defer rows.Close()

	players := make([]moderationPlayer, 0, 32)
	for rows.Next() {
		var player moderationPlayer
		var lastSeen sql.NullTime
		var lastWarningAt sql.NullTime
		if err := rows.Scan(
			&player.ID, &player.Nickname, &player.Platform, &player.MatchesPlayed,
			&lastSeen, &player.ReportsCount, &player.NicknameHidden,
			&player.Banned, &player.BanReason, &player.Warnings,
			&player.LastWarningReason, &lastWarningAt,
		); err != nil {
			log.Printf("scan moderation player: %v", err)
			writeJSON(w, http.StatusInternalServerError, moderationPlayersResponse{Error: "Internal server error"})
			return
		}
		player.LastSeenAt = nullableTime(lastSeen)
		player.LastWarningAt = nullableTime(lastWarningAt)
		players = append(players, player)
	}
	if err := rows.Err(); err != nil {
		log.Printf("iterate moderation players: %v", err)
		writeJSON(w, http.StatusInternalServerError, moderationPlayersResponse{Error: "Internal server error"})
		return
	}
	writeJSON(w, http.StatusOK, moderationPlayersResponse{Success: true, Players: players})
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
// nick, or a recent login when no search is given.
const moderationPlayersQuery = `
SELECT p.id, p.nickname, COALESCE(p.platform, ''), COALESCE(p.matches_played, 0),
       p.last_seen_at,
       (SELECT COUNT(*) FROM reports r
         WHERE r.reported_player_id = p.id
            OR (r.reported_player_id IS NULL
                AND LOWER(BTRIM(r.reported_nickname)) = LOWER(BTRIM(p.nickname)))) AS reports_count,
       COALESCE(p.nickname_hidden, FALSE), COALESCE(p.banned, FALSE), COALESCE(p.ban_reason, ''),
       COALESCE(p.warnings, 0), COALESCE(p.last_warning_reason, ''), p.last_warning_at
FROM players p
WHERE ($1 <> '' AND p.nickname ILIKE '%' || $1 || '%')
   OR ($1 = '' AND (
        COALESCE(p.banned, FALSE) OR COALESCE(p.nickname_hidden, FALSE)
        OR p.last_seen_at > NOW() - INTERVAL '14 days'
        OR EXISTS (SELECT 1 FROM reports r0
                    WHERE r0.reported_player_id = p.id
                       OR (r0.reported_player_id IS NULL
                           AND LOWER(BTRIM(r0.reported_nickname)) = LOWER(BTRIM(p.nickname))))))
ORDER BY COALESCE(p.banned, FALSE) DESC, reports_count DESC, p.last_seen_at DESC NULLS LAST, p.id DESC
LIMIT 100`
