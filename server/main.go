package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/lib/pq"
)

const maxRequestBody = 1 << 20

// dbMonitorInterval is how often the server checks a database that was
// unavailable at startup, and how often it re-checks a live connection.
const dbMonitorInterval = 15 * time.Second

// maxMatchReward is a sanity limit so a malformed client cannot add an
// arbitrary amount of shards in one request.
const maxMatchReward = 100000

// nicknameChangeCost is charged for every rename after the first one.
const nicknameChangeCost = 100

var wingPrices = map[int]int{
	1: 50,
	2: 500,
	3: 1500,
	4: 3000,
}

var weaponPrices = map[int]int{
	1: 500,
}

var startedAt = time.Now()

type api struct {
	db      *sql.DB
	dbHost  string
	dbReady atomic.Bool
	dbError atomic.Value
}

func (service *api) setDatabaseReady() {
	service.dbError.Store("")
	service.dbReady.Store(true)
}

func (service *api) setDatabaseError(err error) {
	service.dbReady.Store(false)
	if err != nil {
		service.dbError.Store(err.Error())
	}
}

func (service *api) lastDatabaseError() string {
	value := service.dbError.Load()
	if value == nil {
		return ""
	}
	message, _ := value.(string)
	return message
}

type registerRequest struct {
	Nickname string `json:"nickname"`
}

type registerResponse struct {
	Success  bool   `json:"success"`
	PlayerID int64  `json:"player_id,omitempty"`
	Error    string `json:"error,omitempty"`
}

type playerProfileResponse struct {
	Success         bool   `json:"success"`
	PlayerID        int64  `json:"player_id,omitempty"`
	Nickname        string `json:"nickname,omitempty"`
	NicknameCustom  bool   `json:"nickname_custom"`
	SkyShards       int    `json:"sky_shards,omitempty"`
	UnlockedWings   []int  `json:"unlocked_wings,omitempty"`
	UnlockedWeapons []int  `json:"unlocked_weapons,omitempty"`
	Error           string `json:"error,omitempty"`
}

type buyWingRequest struct {
	PlayerID int64 `json:"player_id"`
	WingID   int   `json:"wing_id"`
	Cost     int   `json:"cost"`
}

type buyWingResponse struct {
	Success   bool   `json:"success"`
	NewShards int    `json:"new_shards,omitempty"`
	Error     string `json:"error,omitempty"`
}

type buyWeaponResponse struct {
	Success   bool   `json:"success"`
	NewShards int    `json:"new_shards,omitempty"`
	Error     string `json:"error,omitempty"`
}

type renameRequest struct {
	PlayerID int64  `json:"player_id"`
	Nickname string `json:"nickname"`
}

type renameResponse struct {
	Success   bool   `json:"success"`
	Nickname  string `json:"nickname,omitempty"`
	Charged   bool   `json:"charged"`
	Cost      int    `json:"cost,omitempty"`
	NewShards int    `json:"new_shards,omitempty"`
	Error     string `json:"error,omitempty"`
}

type reportRequest struct {
	PlayerID int64  `json:"player_id"`
	Nickname string `json:"nickname"`
	Reason   string `json:"reason"`
}

type reportResponse struct {
	Success bool   `json:"success"`
	Error   string `json:"error,omitempty"`
}

type matchRewardRequest struct {
	PlayerID int64 `json:"player_id"`
	Amount   int   `json:"amount"`
	Shards   int   `json:"shards"`
}

type matchRewardResponse struct {
	Success   bool   `json:"success"`
	NewShards int    `json:"new_shards,omitempty"`
	Error     string `json:"error,omitempty"`
}

func main() {
	databaseURL := normalizeDatabaseURL(strings.TrimSpace(os.Getenv("DATABASE_URL")))

	db, err := sql.Open("postgres", databaseURL)
	if err != nil {
		log.Fatalf("open database: %v", err)
	}
	defer db.Close()
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(30 * time.Minute)

	service := &api{db: db, dbHost: databaseHost(databaseURL)}
	hub := newWebSocketHub(db)
	router := newRouter(service, hub)

	startupContext, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	if databaseURL == "" {
		log.Print("WARNING: DATABASE_URL is not set; serving /health only")
		service.setDatabaseError(errors.New("DATABASE_URL is required"))
	} else if err := db.PingContext(startupContext); err != nil {
		log.Printf("WARNING: database unavailable at startup: %v", err)
		service.setDatabaseError(err)
	} else if err := createSchema(startupContext, db); err != nil {
		log.Printf("WARNING: database schema setup failed: %v", err)
		service.setDatabaseError(err)
	} else {
		log.Print("database ready")
		service.setDatabaseReady()
	}
	cancel()

	go service.monitorDatabase(db)

	port := strings.TrimSpace(os.Getenv("PORT"))
	if port == "" {
		port = "8080"
	}
	portNumber, portErr := strconv.Atoi(port)
	if portErr != nil || portNumber < 1 || portNumber > 65535 {
		log.Fatal("PORT must be a port number")
	}

	server := &http.Server{
		Addr:              ":" + port,
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	log.Printf("server listening on :%s (health: /health)", port)
	log.Fatal(server.ListenAndServe())
}

// normalizeDatabaseURL makes the managed PostgreSQL connection work with
// lib/pq, which requires TLS by default. The internal database does not serve
// TLS, so use plaintext unless the DSN already asks for a specific sslmode.
func normalizeDatabaseURL(raw string) string {
	if raw == "" || strings.Contains(raw, "sslmode=") {
		return raw
	}
	if isDatabaseURL(raw) {
		separator := "?"
		if strings.Contains(raw, "?") {
			separator = "&"
		}
		return raw + separator + "sslmode=disable"
	}
	return raw + " sslmode=disable"
}

func isDatabaseURL(raw string) bool {
	return strings.HasPrefix(raw, "postgres://") || strings.HasPrefix(raw, "postgresql://")
}

// databaseHost returns only the host from the connection string so the health
// endpoint can show which database the container actually sees. It supports
// both URL and keyword/value DSNs.
func databaseHost(raw string) string {
	if raw == "" {
		return ""
	}
	if isDatabaseURL(raw) {
		parsed, err := url.Parse(raw)
		if err != nil {
			return ""
		}
		return parsed.Hostname()
	}
	for _, field := range strings.Fields(raw) {
		if value, found := strings.CutPrefix(field, "host="); found {
			return value
		}
	}
	return ""
}

func newRouter(service *api, hub *wsHub) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", service.handleHealth)
	mux.HandleFunc("/ws", hub.handleWebSocket)
	mux.HandleFunc("/register", service.handleRegister)
	mux.HandleFunc("/profile", service.handleProfile)
	mux.HandleFunc("/rename", service.handleRename)
	mux.HandleFunc("/report", service.handleReport)
	mux.HandleFunc("/buy_wing", service.handleBuyWing)
	mux.HandleFunc("/buy_weapon", service.handleBuyWeapon)
	mux.HandleFunc("/match_reward", service.handleMatchReward)
	return databaseGate(mux, service)
}

// databaseGate keeps the container alive when the database is down: health and
// the realtime match endpoint keep working, while economy endpoints fail with a
// readable 503 instead of the platform reporting a dead backend.
func databaseGate(next http.Handler, service *api) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" || r.URL.Path == "/ws" || service.dbReady.Load() {
			next.ServeHTTP(w, r)
			return
		}
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{
			"success": false,
			"error":   "Database unavailable",
		})
	})
}

func (service *api) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"success": false,
			"error":   "Method not allowed",
		})
		return
	}

	response := map[string]any{
		"success":        true,
		"status":         "ok",
		"database":       "ok",
		"uptime_seconds": int(time.Since(startedAt).Seconds()),
	}
	if service.dbHost != "" {
		response["database_host"] = service.dbHost
	}
	if !service.dbReady.Load() {
		response["status"] = "degraded"
		response["database"] = "down"
		if message := service.lastDatabaseError(); message != "" {
			response["database_error"] = message
		}
	}
	writeJSON(w, http.StatusOK, response)
}

func (service *api) monitorDatabase(db *sql.DB) {
	ticker := time.NewTicker(dbMonitorInterval)
	defer ticker.Stop()
	for range ticker.C {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		err := db.PingContext(ctx)
		if err == nil && !service.dbReady.Load() {
			err = createSchema(ctx, db)
		}
		cancel()

		if err != nil {
			if service.dbReady.Load() {
				log.Printf("database connection lost: %v", err)
			}
			service.setDatabaseError(err)
			continue
		}
		if !service.dbReady.Load() {
			log.Print("database connection ready")
		}
		service.setDatabaseReady()
	}
}

func createSchema(ctx context.Context, db *sql.DB) error {
	if err := createPlayersTable(ctx, db); err != nil {
		return err
	}
	if err := createReportsTable(ctx, db); err != nil {
		return err
	}
	return createMatchesTable(ctx, db)
}

func createPlayersTable(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS players (
			id SERIAL PRIMARY KEY,
			nickname TEXT NOT NULL,
			nickname_custom BOOLEAN DEFAULT FALSE,
			sky_shards INTEGER DEFAULT 0,
			unlocked_wings TEXT DEFAULT '',
			unlocked_weapons TEXT DEFAULT ''
		)
	`)
	if err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `ALTER TABLE players ADD COLUMN IF NOT EXISTS unlocked_weapons TEXT DEFAULT ''`)
	if err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `ALTER TABLE players ADD COLUMN IF NOT EXISTS nickname_custom BOOLEAN DEFAULT FALSE`)
	if err != nil {
		return err
	}
	// Ник — отображаемое имя, а не логин: уникальность не нужна и мешает
	// игрокам брать понравившиеся имена. Личность определяется по id.
	return dropNicknameUniqueness(ctx, db)
}

// dropNicknameUniqueness removes any unique constraints or indexes on the
// players table except the primary key. Older deployments created the nickname
// column as UNIQUE, and manual schema edits may have left indexes with
// non-default names.
func dropNicknameUniqueness(ctx context.Context, db *sql.DB) error {
	rows, err := db.QueryContext(ctx, `
		SELECT conname
		FROM pg_constraint
		WHERE conrelid = 'players'::regclass AND contype = 'u'
	`)
	if err != nil {
		return err
	}
	var constraints []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			rows.Close()
			return err
		}
		constraints = append(constraints, name)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	for _, name := range constraints {
		if _, err := db.ExecContext(ctx, `ALTER TABLE players DROP CONSTRAINT `+pq.QuoteIdentifier(name)); err != nil {
			return err
		}
	}

	rows, err = db.QueryContext(ctx, `
		SELECT indexrelid::regclass::text
		FROM pg_index
		WHERE indrelid = 'players'::regclass
		  AND indisunique
		  AND NOT indisprimary
		  AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conindid = indexrelid)
	`)
	if err != nil {
		return err
	}
	var indexes []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			rows.Close()
			return err
		}
		indexes = append(indexes, name)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	for _, name := range indexes {
		if _, err := db.ExecContext(ctx, `DROP INDEX IF EXISTS `+name); err != nil {
			return err
		}
	}
	return nil
}

func createReportsTable(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS reports (
			id BIGSERIAL PRIMARY KEY,
			reporter_id BIGINT NOT NULL,
			reported_nickname TEXT NOT NULL,
			reason TEXT NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)
	`)
	if err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `CREATE INDEX IF NOT EXISTS reports_created_idx ON reports (created_at)`)
	return err
}

func createMatchesTable(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS matches (
			id BIGSERIAL PRIMARY KEY,
			room_id BIGINT NOT NULL,
			player_id BIGINT NOT NULL,
			team INTEGER NOT NULL,
			won BOOLEAN NOT NULL,
			played_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)
	`)
	if err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `CREATE INDEX IF NOT EXISTS matches_player_id_idx ON matches (player_id)`)
	return err
}

func (service *api) handleRegister(w http.ResponseWriter, r *http.Request) {
	if !requirePost(w, r) {
		return
	}
	var request registerRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, registerResponse{Error: "Invalid JSON"})
		return
	}

	nickname := strings.TrimSpace(request.Nickname)
	if !validNickname(nickname) {
		writeJSON(w, http.StatusBadRequest, registerResponse{Error: "Nickname must be 3 to 12 characters"})
		return
	}
	if containsProfanity(nickname) {
		writeJSON(w, http.StatusBadRequest, registerResponse{Error: "Nickname contains forbidden words"})
		return
	}

	var playerID int64
	customNickname := !strings.HasPrefix(nickname, "Игрок ")
	err := service.db.QueryRowContext(r.Context(),
		`INSERT INTO players (nickname, nickname_custom) VALUES ($1, $2) RETURNING id`, nickname, customNickname,
	).Scan(&playerID)
	if err != nil {
		var postgresError *pq.Error
		if errors.As(err, &postgresError) && postgresError.Code == "23505" {
			writeJSON(w, http.StatusConflict, registerResponse{Error: "Nickname already taken"})
			return
		}
		log.Printf("register player: %v", err)
		writeJSON(w, http.StatusInternalServerError, registerResponse{Error: "Internal server error"})
		return
	}

	writeJSON(w, http.StatusCreated, registerResponse{Success: true, PlayerID: playerID})
}

func (service *api) handleProfile(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeJSON(w, http.StatusMethodNotAllowed, playerProfileResponse{Error: "Method not allowed"})
		return
	}
	playerID, err := strconv.ParseInt(r.URL.Query().Get("player_id"), 10, 64)
	if err != nil || playerID <= 0 {
		writeJSON(w, http.StatusBadRequest, playerProfileResponse{Error: "Invalid player ID"})
		return
	}

	var nickname string
	var nicknameCustom bool
	var shards int
	var unlockedWings string
	var unlockedWeapons string
	err = service.db.QueryRowContext(r.Context(),
		`SELECT nickname, COALESCE(nickname_custom, FALSE), sky_shards, COALESCE(unlocked_wings, ''), COALESCE(unlocked_weapons, '') FROM players WHERE id = $1`, playerID,
	).Scan(&nickname, &nicknameCustom, &shards, &unlockedWings, &unlockedWeapons)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, playerProfileResponse{Error: "Player not found"})
		return
	}
	if err != nil {
		log.Printf("load player profile: %v", err)
		writeJSON(w, http.StatusInternalServerError, playerProfileResponse{Error: "Internal server error"})
		return
	}

	writeJSON(w, http.StatusOK, playerProfileResponse{
		Success:         true,
		PlayerID:        playerID,
		Nickname:        nickname,
		NicknameCustom:  nicknameCustom,
		SkyShards:       shards,
		UnlockedWings:   parseItemIDs(unlockedWings),
		UnlockedWeapons: parseItemIDs(unlockedWeapons),
	})
}

func (service *api) handleRename(w http.ResponseWriter, r *http.Request) {
	if !requirePost(w, r) {
		return
	}
	var request renameRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, renameResponse{Error: "Invalid JSON"})
		return
	}
	nickname := strings.TrimSpace(request.Nickname)
	if request.PlayerID <= 0 || !validNickname(nickname) {
		writeJSON(w, http.StatusBadRequest, renameResponse{Error: "Nickname must be 3 to 12 characters"})
		return
	}
	if containsProfanity(nickname) {
		writeJSON(w, http.StatusBadRequest, renameResponse{Error: "Nickname contains forbidden words"})
		return
	}

	tx, err := service.db.BeginTx(r.Context(), nil)
	if err != nil {
		log.Printf("rename begin: %v", err)
		writeJSON(w, http.StatusInternalServerError, renameResponse{Error: "Internal server error"})
		return
	}
	defer tx.Rollback()

	var currentNickname string
	var nicknameCustom bool
	var shards int
	err = tx.QueryRowContext(r.Context(),
		`SELECT nickname, COALESCE(nickname_custom, FALSE), COALESCE(sky_shards, 0) FROM players WHERE id = $1 FOR UPDATE`,
		request.PlayerID,
	).Scan(&currentNickname, &nicknameCustom, &shards)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, renameResponse{Error: "Player not found"})
		return
	}
	if err != nil {
		log.Printf("rename load player: %v", err)
		writeJSON(w, http.StatusInternalServerError, renameResponse{Error: "Internal server error"})
		return
	}

	changed := nickname != currentNickname
	cost := 0
	if changed && nicknameCustom {
		cost = nicknameChangeCost
	}
	if shards < cost {
		writeJSON(w, http.StatusPaymentRequired, renameResponse{
			Error:     "Not enough shards",
			Cost:      cost,
			NewShards: shards,
		})
		return
	}

	newCustom := nicknameCustom || changed
	_, err = tx.ExecContext(r.Context(),
		`UPDATE players SET nickname = $1, nickname_custom = $2, sky_shards = sky_shards - $3 WHERE id = $4`,
		nickname, newCustom, cost, request.PlayerID,
	)
	if err != nil {
		var postgresError *pq.Error
		if errors.As(err, &postgresError) && postgresError.Code == "23505" {
			writeJSON(w, http.StatusConflict, renameResponse{Error: "Nickname already taken"})
			return
		}
		log.Printf("rename player: %v", err)
		writeJSON(w, http.StatusInternalServerError, renameResponse{Error: "Internal server error"})
		return
	}
	if err := tx.Commit(); err != nil {
		log.Printf("rename commit: %v", err)
		writeJSON(w, http.StatusInternalServerError, renameResponse{Error: "Internal server error"})
		return
	}

	writeJSON(w, http.StatusOK, renameResponse{
		Success:   true,
		Nickname:  nickname,
		Charged:   cost > 0,
		Cost:      cost,
		NewShards: shards - cost,
	})
}

func (service *api) handleReport(w http.ResponseWriter, r *http.Request) {
	if !requirePost(w, r) {
		return
	}
	var request reportRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, reportResponse{Error: "Invalid JSON"})
		return
	}
	nickname := strings.TrimSpace(request.Nickname)
	reason := strings.TrimSpace(request.Reason)
	if request.PlayerID <= 0 || !validNickname(nickname) {
		writeJSON(w, http.StatusBadRequest, reportResponse{Error: "Invalid report"})
		return
	}
	reasonLength := utf8.RuneCountInString(reason)
	if reasonLength < 3 || reasonLength > 200 {
		writeJSON(w, http.StatusBadRequest, reportResponse{Error: "Invalid report"})
		return
	}
	var recent int
	err := service.db.QueryRowContext(r.Context(),
		`SELECT COUNT(*) FROM reports WHERE reporter_id = $1 AND created_at > NOW() - INTERVAL '1 minute'`,
		request.PlayerID,
	).Scan(&recent)
	if err != nil {
		log.Printf("report rate limit: %v", err)
		writeJSON(w, http.StatusInternalServerError, reportResponse{Error: "Internal server error"})
		return
	}
	if recent >= 5 {
		writeJSON(w, http.StatusTooManyRequests, reportResponse{Error: "Too many reports"})
		return
	}
	_, err = service.db.ExecContext(r.Context(),
		`INSERT INTO reports (reporter_id, reported_nickname, reason) VALUES ($1, $2, $3)`,
		request.PlayerID, nickname, reason,
	)
	if err != nil {
		log.Printf("save report: %v", err)
		writeJSON(w, http.StatusInternalServerError, reportResponse{Error: "Internal server error"})
		return
	}
	log.Printf("[REPORT] reporter=%d nickname=%q reason=%q", request.PlayerID, nickname, reason)
	writeJSON(w, http.StatusOK, reportResponse{Success: true})
}

func validNickname(nickname string) bool {
	length := utf8.RuneCountInString(nickname)
	return length >= 3 && length <= 12
}

var profanityRoots = []string{
	"хуй", "хуё", "хуе", "хую", "хуя",
	"пизд",
	"ебат", "ебал", "ебан", "ебуч", "ебёт", "ебет", "ебу", "ебись", "ебля",
	"ёб", "ёба", "ёбу",
	"бля", "блят",
	"сука", "суки", "суке", "суку", "суч",
	"мудак", "мудил", "мудоз",
	"гандон",
	"залуп",
	"дроч",
	"пидор", "пидар", "педик",
	"шлюх",
	"мраз",
	"ублюд",
	"долбо",
	"дебил", "кретин",
	"нацист", "нацизм", "фашист",
	"fuck", "shit", "bitch", "cunt", "dick", "cock", "pussy",
	"asshole", "nigger", "faggot", "whore", "slut", "rapist",
	"nazi", "retard",
}

func containsProfanity(nickname string) bool {
	normalized := normalizeNickname(nickname)
	for _, root := range profanityRoots {
		if strings.Contains(normalized, root) {
			return true
		}
	}
	return false
}

func normalizeNickname(value string) string {
	var builder strings.Builder
	for _, r := range strings.ToLower(value) {
		switch r {
		case '0':
			r = 'о'
		case '1':
			r = 'и'
		case '3':
			r = 'е'
		case '4':
			r = 'а'
		case '5':
			r = 'с'
		case '7':
			r = 'т'
		case '@':
			r = 'а'
		case '$':
			r = 'с'
		}
		if unicode.Is(unicode.Cyrillic, r) || unicode.Is(unicode.Latin, r) {
			builder.WriteRune(r)
		}
	}
	return builder.String()
}

func (service *api) handleBuyWing(w http.ResponseWriter, r *http.Request) {
	if !requirePost(w, r) {
		return
	}
	var request buyWingRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, buyWingResponse{Error: "Invalid JSON"})
		return
	}

	price, knownWing := wingPrices[request.WingID]
	if request.PlayerID <= 0 || !knownWing || request.Cost != price {
		writeJSON(w, http.StatusBadRequest, buyWingResponse{Error: "Invalid purchase"})
		return
	}

	transaction, err := service.db.BeginTx(r.Context(), nil)
	if err != nil {
		log.Printf("begin wing purchase: %v", err)
		writeJSON(w, http.StatusInternalServerError, buyWingResponse{Error: "Internal server error"})
		return
	}
	defer transaction.Rollback()

	var shards int
	var unlockedWings string
	err = transaction.QueryRowContext(r.Context(),
		`SELECT sky_shards, unlocked_wings FROM players WHERE id = $1 FOR UPDATE`, request.PlayerID,
	).Scan(&shards, &unlockedWings)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, buyWingResponse{Error: "Player not found"})
		return
	}
	if err != nil {
		log.Printf("load player for wing purchase: %v", err)
		writeJSON(w, http.StatusInternalServerError, buyWingResponse{Error: "Internal server error"})
		return
	}
	if containsWing(unlockedWings, request.WingID) {
		writeJSON(w, http.StatusConflict, buyWingResponse{Error: "Wing already unlocked"})
		return
	}
	if shards < price {
		writeJSON(w, http.StatusBadRequest, buyWingResponse{Error: "Not enough shards"})
		return
	}

	newShards := shards - price
	newUnlockedWings := appendWing(unlockedWings, request.WingID)
	_, err = transaction.ExecContext(r.Context(),
		`UPDATE players SET sky_shards = $1, unlocked_wings = $2 WHERE id = $3`,
		newShards, newUnlockedWings, request.PlayerID,
	)
	if err != nil {
		log.Printf("update wing purchase: %v", err)
		writeJSON(w, http.StatusInternalServerError, buyWingResponse{Error: "Internal server error"})
		return
	}
	if err := transaction.Commit(); err != nil {
		log.Printf("commit wing purchase: %v", err)
		writeJSON(w, http.StatusInternalServerError, buyWingResponse{Error: "Internal server error"})
		return
	}

	writeJSON(w, http.StatusOK, buyWingResponse{Success: true, NewShards: newShards})
}

func (service *api) handleBuyWeapon(w http.ResponseWriter, r *http.Request) {
	if !requirePost(w, r) {
		return
	}
	var request struct {
		PlayerID int64 `json:"player_id"`
		WeaponID int   `json:"weapon_id"`
		Cost     int   `json:"cost"`
	}
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, buyWeaponResponse{Error: "Invalid JSON"})
		return
	}

	price, knownWeapon := weaponPrices[request.WeaponID]
	if request.PlayerID <= 0 || !knownWeapon || request.Cost != price {
		writeJSON(w, http.StatusBadRequest, buyWeaponResponse{Error: "Invalid purchase"})
		return
	}

	transaction, err := service.db.BeginTx(r.Context(), nil)
	if err != nil {
		log.Printf("begin weapon purchase: %v", err)
		writeJSON(w, http.StatusInternalServerError, buyWeaponResponse{Error: "Internal server error"})
		return
	}
	defer transaction.Rollback()

	var shards int
	var unlockedWeapons string
	err = transaction.QueryRowContext(r.Context(),
		`SELECT sky_shards, unlocked_weapons FROM players WHERE id = $1 FOR UPDATE`, request.PlayerID,
	).Scan(&shards, &unlockedWeapons)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, buyWeaponResponse{Error: "Player not found"})
		return
	}
	if err != nil {
		log.Printf("load player for weapon purchase: %v", err)
		writeJSON(w, http.StatusInternalServerError, buyWeaponResponse{Error: "Internal server error"})
		return
	}
	if containsWing(unlockedWeapons, request.WeaponID) {
		writeJSON(w, http.StatusConflict, buyWeaponResponse{Error: "Weapon already unlocked"})
		return
	}
	if shards < price {
		writeJSON(w, http.StatusBadRequest, buyWeaponResponse{Error: "Not enough shards"})
		return
	}

	newShards := shards - price
	newUnlockedWeapons := appendWing(unlockedWeapons, request.WeaponID)
	_, err = transaction.ExecContext(r.Context(),
		`UPDATE players SET sky_shards = $1, unlocked_weapons = $2 WHERE id = $3`,
		newShards, newUnlockedWeapons, request.PlayerID,
	)
	if err != nil {
		log.Printf("update weapon purchase: %v", err)
		writeJSON(w, http.StatusInternalServerError, buyWeaponResponse{Error: "Internal server error"})
		return
	}
	if err := transaction.Commit(); err != nil {
		log.Printf("commit weapon purchase: %v", err)
		writeJSON(w, http.StatusInternalServerError, buyWeaponResponse{Error: "Internal server error"})
		return
	}

	writeJSON(w, http.StatusOK, buyWeaponResponse{Success: true, NewShards: newShards})
}

func (service *api) handleMatchReward(w http.ResponseWriter, r *http.Request) {
	if !requirePost(w, r) {
		return
	}
	var request matchRewardRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, matchRewardResponse{Error: "Invalid JSON"})
		return
	}

	// amount is the canonical field; shards is accepted as an alias for
	// clients that name the currency explicitly.
	if request.Amount != 0 && request.Shards != 0 && request.Amount != request.Shards {
		writeJSON(w, http.StatusBadRequest, matchRewardResponse{Error: "Conflicting reward amount"})
		return
	}
	amount := request.Amount
	if amount == 0 {
		amount = request.Shards
	}
	if request.PlayerID <= 0 || amount <= 0 || amount > maxMatchReward {
		writeJSON(w, http.StatusBadRequest, matchRewardResponse{Error: "Invalid reward"})
		return
	}

	var newShards int
	err := service.db.QueryRowContext(r.Context(),
		`UPDATE players SET sky_shards = COALESCE(sky_shards, 0) + $1 WHERE id = $2 RETURNING sky_shards`,
		amount, request.PlayerID,
	).Scan(&newShards)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, matchRewardResponse{Error: "Player not found"})
		return
	}
	if err != nil {
		log.Printf("grant match reward: %v", err)
		writeJSON(w, http.StatusInternalServerError, matchRewardResponse{Error: "Internal server error"})
		return
	}

	writeJSON(w, http.StatusOK, matchRewardResponse{Success: true, NewShards: newShards})
}

func containsWing(unlocked string, wingID int) bool {
	for _, value := range strings.Split(unlocked, ",") {
		if strings.TrimSpace(value) == strconv.Itoa(wingID) {
			return true
		}
	}
	return false
}

func appendWing(unlocked string, wingID int) string {
	wing := strconv.Itoa(wingID)
	if strings.TrimSpace(unlocked) == "" {
		return wing
	}
	return unlocked + "," + wing
}

func parseItemIDs(value string) []int {
	itemIDs := make([]int, 0)
	for _, rawID := range strings.Split(value, ",") {
		itemID, err := strconv.Atoi(strings.TrimSpace(rawID))
		if err == nil && itemID > 0 {
			itemIDs = append(itemIDs, itemID)
		}
	}
	return itemIDs
}

func requirePost(w http.ResponseWriter, r *http.Request) bool {
	if r.Method == http.MethodPost {
		return true
	}
	w.Header().Set("Allow", http.MethodPost)
	writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "Method not allowed"})
	return false
}

func decodeJSON(w http.ResponseWriter, r *http.Request, destination any) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxRequestBody)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return errors.New("request must contain one JSON object")
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		log.Printf("write JSON response: %v", err)
	}
}
