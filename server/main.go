package main

import (
	"compress/gzip"
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"mime"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
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
// arbitrary amount of shards in one request. The client's reward is 1/3/5.
const maxMatchReward = 10

// A match interrupted by a server restart is compensated with a small fixed
// payout. The cooldown keeps a client from farming it by dropping the socket.
const compensationShards = 20
const compensationCooldown = 10 * time.Minute

// Admin grants are guarded by the same token as the stats dashboard.
const adminToken = "239837"

func adminTokenValue() string {
	if value := strings.TrimSpace(os.Getenv("ADMIN_TOKEN")); value != "" {
		return value
	}
	return adminToken
}

const sessionHeader = "X-Session-Token"

// nicknameChangeCost is charged for every rename after the first one.
const nicknameChangeCost = 100

var wingPrices = map[int]int{
	1: 500,
	2: 1500,
	3: 3000,
	4: 5000,
}

var weaponPrices = map[int]int{
	1:   1500,
	2:   1500,
	3:   1500,
	4:   100,
	5:   100,
	6:   100,
	7:   400,
	8:   800,
	9:   400,
	101: 5000,
	102: 5000,
}

var startedAt = time.Now()
var webBuildVersion = "dev"

type api struct {
	db            *sql.DB
	dbHost        string
	dbReady       atomic.Bool
	dbError       atomic.Value
	hub           *wsHub
	vkAuthLimiter *vkRateLimiter
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
	Token    string `json:"token,omitempty"`
	Error    string `json:"error,omitempty"`
}

type sessionRequest struct {
	PlayerID int64 `json:"player_id"`
}

type sessionResponse struct {
	Success bool   `json:"success"`
	Token   string `json:"token,omitempty"`
	Error   string `json:"error,omitempty"`
}

type playerProfileResponse struct {
	Success             bool           `json:"success"`
	PlayerID            int64          `json:"player_id,omitempty"`
	Nickname            string         `json:"nickname,omitempty"`
	NicknameCustom      bool           `json:"nickname_custom"`
	SkyShards           int            `json:"sky_shards,omitempty"`
	Level               int            `json:"level"`
	UnlockedWings       []int          `json:"unlocked_wings,omitempty"`
	UnlockedWeapons     []int          `json:"unlocked_weapons,omitempty"`
	MatchesPlayed       int            `json:"matches_played"`
	Novice              bool           `json:"novice"`
	CharLevels          map[string]int `json:"char_levels"`
	CharXPs             map[string]int `json:"char_xps"`
	TutorialCompleted   bool           `json:"tutorial_completed"`
	TutorialSkipped     bool           `json:"tutorial_skipped"`
	TutorialBattlesUsed int            `json:"tutorial_battles_used"`
	ProgressInitialized bool           `json:"progress_initialized"`
	LastInterstitialAt  int64          `json:"last_interstitial_at"`
	SessionToken        string         `json:"session_token,omitempty"`
	Error               string         `json:"error,omitempty"`
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

type accountDeleteRequest struct {
	PlayerID int64 `json:"player_id"`
}

type accountDeleteResponse struct {
	Success bool   `json:"success"`
	Error   string `json:"error,omitempty"`
}

type matchRewardRequest struct {
	PlayerID  int64  `json:"player_id"`
	RoomID    int64  `json:"room_id"`
	Amount    int    `json:"amount"`
	Shards    int    `json:"shards"`
	XP        int    `json:"xp"`
	Character string `json:"character"`
	Bonus     bool   `json:"bonus"`
}

type matchRewardResponse struct {
	Success       bool           `json:"success"`
	NewShards     int            `json:"new_shards,omitempty"`
	CharLevels    map[string]int `json:"char_levels,omitempty"`
	CharXPs       map[string]int `json:"char_xps,omitempty"`
	LeveledUp     bool           `json:"leveled_up"`
	LevelUpShards int            `json:"level_up_shards,omitempty"`
	Bonus         bool           `json:"bonus"`
	Error         string         `json:"error,omitempty"`
}

type compensationRequest struct {
	PlayerID int64  `json:"player_id"`
	Reason   string `json:"reason"`
}

type adminGrantRequest struct {
	PlayerID int64  `json:"player_id"`
	Nickname string `json:"nickname"`
	Amount   int    `json:"amount"`
}

type adminGrantResponse struct {
	Success    bool             `json:"success"`
	PlayerID   int64            `json:"player_id,omitempty"`
	Nickname   string           `json:"nickname,omitempty"`
	NewShards  int              `json:"new_shards,omitempty"`
	Candidates []adminPlayerRef `json:"candidates,omitempty"`
	Error      string           `json:"error,omitempty"`
}

type adminPlayerRef struct {
	ID       int64  `json:"id"`
	Nickname string `json:"nickname"`
	Shards   int    `json:"shards"`
}

func main() {
	webBuildVersion = time.Now().Format("20060102_150405")
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
		if err := initStatsTable(db); err != nil {
			log.Printf("WARNING: stats table setup failed: %v", err)
		}
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
	shutdownSignals := make(chan os.Signal, 1)
	signal.Notify(shutdownSignals, syscall.SIGTERM, os.Interrupt)
	go func() {
		<-shutdownSignals
		log.Printf("shutdown requested; finishing live matches")
		hub.finishLiveMatches("server_restart")
		// Let the clients receive match_finished and save the result before
		// the process disappears.
		time.Sleep(2 * time.Second)
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := server.Shutdown(ctx); err != nil {
			log.Printf("server shutdown: %v", err)
		}
	}()
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
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
	service.hub = hub
	if service.vkAuthLimiter == nil {
		service.vkAuthLimiter = newVKRateLimiter(vkAuthRateLimit, vkAuthRateWindow)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/health", service.handleHealth)
	mux.HandleFunc("/rules", service.handleRules)
	mux.HandleFunc("/ws", hub.handleWebSocket)
	mux.HandleFunc("/auth/vk", service.handleVKAuth)
	mux.HandleFunc("/auth/ok", service.handleOKAuth)
	mux.HandleFunc("/vk/pay", service.handleVKPay)
	mux.HandleFunc("/ok/pay", service.handleOKPay)
	mux.HandleFunc("/register", service.handleRegister)
	mux.HandleFunc("/session", service.handleSession)
	mux.HandleFunc("/profile", service.handleProfile)
	mux.HandleFunc("/progress", service.handleProgress)
	mux.HandleFunc("/rename", service.handleRename)
	mux.HandleFunc("/report", service.handleReport)
	mux.HandleFunc("/buy_wing", service.handleBuyWing)
	mux.HandleFunc("/buy_weapon", service.handleBuyWeapon)
	mux.HandleFunc("/match_reward", service.handleMatchReward)
	mux.HandleFunc("/ad_interstitial", service.handleInterstitialShown)
	mux.HandleFunc("/account/delete", service.handleAccountDelete)
	mux.HandleFunc("/compensation", service.handleCompensation)
	mux.HandleFunc("/admin/grant_shards", service.handleAdminGrantShards)
	mux.HandleFunc(moderationPagePath, service.handleModerationPage)
	mux.HandleFunc(moderationReportsPath, service.handleModerationReports)
	mux.HandleFunc(moderationPlayersPath, service.handleModerationPlayers)
	mux.HandleFunc(moderationReportsPath+"/", service.handleModerationResolve)
	mux.HandleFunc(moderationPlayersPath+"/", service.handleModerationPlayerAction)
	mux.HandleFunc("/stats/event", service.handleStatsEvent)
	mux.HandleFunc("/stats/data", service.handleStatsData)
	mux.HandleFunc("/stats/dashboard", service.handleStatsDashboard)
	mux.HandleFunc("/stats/player", service.handleStatsPlayer)
	mux.HandleFunc("/stats/reset", service.handleStatsReset)
	gameDir := gameWebDir()
	if gameDir != "" {
		// Serve the HTML5 build from the same origin as REST/WS. GitHub Pages
		// is not reachable at usable speed from Russia, while this host is.
		mux.Handle("/game/", service.trackGamePage(http.StripPrefix("/game/", staticGameHandler(gameDir))))
		// Large files are sometimes missing from the build context; warm the
		// cache in the background so the first player does not wait.
		go prefetchGameAssets(gameDir)
	}
	if vkDir := gameVKWebDir(); vkDir != "" {
		// The VK build is a separate PCK with the `vk` export feature tag. It
		// reuses the common JS/WASM assets from the standalone build.
		mux.Handle("/game-vk/", service.trackGamePage(http.StripPrefix("/game-vk/", staticGameHandlerWithFallback(vkDir, gameDir, gameVKOrigins()))))
		go prefetchGamePack(vkDir, gameVKOrigins())
	}
	if okDir := gameOKWebDir(); okDir != "" {
		// OK uses the same VK Bridge shell with the `ok` feature tag. It has
		// its own PCK because only the OKAdapter is compiled in.
		mux.Handle("/game-ok/", service.trackGamePage(http.StripPrefix("/game-ok/", staticGameHandlerWithFallback(okDir, gameDir, gameOKOrigins()))))
		go prefetchGamePack(okDir, gameOKOrigins())
	}
	return cors(databaseGate(mux, service))
}

// gameWebDir returns the directory with the exported HTML5 build, or "" when
// this deployment does not ship one (local tests, server-only builds).
func gameWebDir() string {
	dir := strings.TrimSpace(os.Getenv("WEB_DIR"))
	if dir == "" {
		dir = "web"
	}
	if info, err := os.Stat(dir); err == nil && info.IsDir() {
		return dir
	}
	return ""
}

func gameVKWebDir() string {
	dir := strings.TrimSpace(os.Getenv("WEB_VK_DIR"))
	if dir == "" {
		dir = "web-vk"
	}
	if info, err := os.Stat(dir); err == nil && info.IsDir() {
		return dir
	}
	return ""
}

func gameOKWebDir() string {
	dir := strings.TrimSpace(os.Getenv("WEB_OK_DIR"))
	if dir == "" {
		dir = "web-ok"
	}
	if info, err := os.Stat(dir); err == nil && info.IsDir() {
		return dir
	}
	return ""
}

// staticGameHandler serves the web export with the MIME types, caching rules
// and optional pre-compressed files Godot needs. The export is copied into the
// image so players download it from the game server instead of GitHub.
func staticGameHandler(dir string) http.Handler {
	return staticGameHandlerWithFallback(dir, "", gameOrigins())
}

// staticGameHandlerWithFallback serves platform-specific files from dir and
// common JS/WASM/font assets from fallback. The VK build only ships its HTML
// and PCK; the rest is identical to the standalone export.
func staticGameHandlerWithFallback(dir, fallback string, origins []string) http.Handler {
	mime.AddExtensionType(".wasm", "application/wasm")
	mime.AddExtensionType(".pck", "application/octet-stream")
	mime.AddExtensionType(".js", "text/javascript")
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		name := path.Clean("/" + r.URL.Path)
		if name == "/" {
			name = "/index.html"
		}
		if strings.HasSuffix(name, "/") || strings.Contains(name, "..") {
			http.NotFound(w, r)
			return
		}
		full := filepath.Join(dir, filepath.FromSlash(name))
		if strings.HasSuffix(name, ".pck") {
			packName, expectedPackSize := mainPackInfo(dir)
			if name == "/"+packName && expectedPackSize > 0 {
				if packInfo, statErr := os.Stat(full); statErr == nil && !packInfo.IsDir() && packInfo.Size() != expectedPackSize {
					log.Printf("game asset %s size mismatch (%d != %d); refetching", name, packInfo.Size(), expectedPackSize)
					if removeErr := os.Remove(full); removeErr != nil {
						log.Printf("game asset remove %s: %v", name, removeErr)
					}
				}
			}
		}
		info, err := os.Stat(full)
		if (err != nil || info.IsDir()) && fallback != "" && !strings.HasSuffix(name, ".pck") {
			fallbackFull := filepath.Join(fallback, filepath.FromSlash(name))
			if fallbackInfo, fallbackErr := os.Stat(fallbackFull); fallbackErr == nil && !fallbackInfo.IsDir() {
				full = fallbackFull
				info = fallbackInfo
				err = nil
			}
		}
		if (err != nil || info.IsDir()) && fetchableGameAsset(name) {
			// RelaxDev's build context drops files above ~20 MB. Fetch them
			// once from the published build and cache them on disk.
			fetchErr := fetchGameAssetWithOrigins(dir, name, origins)
			if fetchErr != nil && fallback != "" && !strings.HasSuffix(name, ".pck") {
				// The VK image may not contain the shared 39 MB WASM; the
				// standalone build has the same engine asset.
				fetchErr = fetchGameAssetWithOrigins(dir, name, gameOrigins())
			}
			if fetchErr != nil {
				log.Printf("game asset %s: %v", name, fetchErr)
			} else {
				info, err = os.Stat(full)
			}
		}
		if err != nil || info == nil || info.IsDir() {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("X-Content-Type-Options", "nosniff")
		switch filepath.Ext(name) {
		case ".html", ".pck":
			// A new PCK keeps the same name on this host; never cache the
			// entry point or the game data, or players stay on an old build.
			w.Header().Set("Cache-Control", "no-store")
		default:
			w.Header().Set("Cache-Control", "public, max-age=86400")
		}
		// Serve the pre-compressed copy when one exists. The PCK stays raw:
		// its 43 MB gzip stream breaks behind the platform proxy over HTTP/2,
		// while the raw file has Content-Length and downloads at full speed.
		servePath := full
		if r.Header.Get("Range") == "" && strings.Contains(r.Header.Get("Accept-Encoding"), "gzip") && filepath.Ext(name) != ".pck" {
			if gzInfo, gzErr := os.Stat(full + ".gz"); gzErr == nil && !gzInfo.IsDir() {
				servePath = full + ".gz"
				w.Header().Set("Content-Encoding", "gzip")
				w.Header().Set("Vary", "Accept-Encoding")
			}
		}
		file, err := os.Open(servePath)
		if err != nil {
			http.NotFound(w, r)
			return
		}
		defer file.Close()
		http.ServeContent(w, r, filepath.Base(name), info.ModTime(), file)
	})
}

var gameAssetLocks sync.Map

func fetchableGameAsset(name string) bool {
	if name == "/index.wasm" || name == "/index.pck" {
		return true
	}
	return strings.HasPrefix(name, "/index_") && strings.HasSuffix(name, ".pck")
}

// gameOrigins reads a comma-separated list of mirrors of the published build.
// The first that answers is cached locally, so players download from this host.
func gameOrigins() []string {
	return originsFromEnv("WEB_ORIGIN")
}

func gameVKOrigins() []string {
	return originsFromEnv("WEB_VK_ORIGIN")
}

func gameOKOrigins() []string {
	return originsFromEnv("WEB_OK_ORIGIN")
}

func originsFromEnv(name string) []string {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return nil
	}
	out := make([]string, 0, 2)
	for _, part := range strings.Split(raw, ",") {
		if part = strings.TrimSpace(part); part != "" {
			out = append(out, strings.TrimRight(part, "/"))
		}
	}
	return out
}

func fetchGameAsset(dir, name string) error {
	return fetchGameAssetWithOrigins(dir, name, gameOrigins())
}

func fetchGameAssetWithOrigins(dir, name string, origins []string) error {
	full := filepath.Join(dir, filepath.FromSlash(name))
	if info, err := os.Stat(full); err == nil && !info.IsDir() {
		return nil
	}
	lockAny, _ := gameAssetLocks.LoadOrStore(full, &sync.Mutex{})
	lock := lockAny.(*sync.Mutex)
	lock.Lock()
	defer lock.Unlock()
	if info, err := os.Stat(full); err == nil && !info.IsDir() {
		return nil
	}
	if len(origins) == 0 {
		return os.ErrNotExist
	}
	client := &http.Client{Timeout: 15 * time.Minute}
	var lastErr error
	for _, origin := range origins {
		url := origin + "/" + strings.TrimLeft(name, "/")
		response, err := client.Get(url)
		if err != nil {
			lastErr = err
			continue
		}
		if response.StatusCode != http.StatusOK {
			response.Body.Close()
			lastErr = fmt.Errorf("%s: %s", url, response.Status)
			continue
		}
		part := full + ".part"
		out, err := os.Create(part)
		if err != nil {
			response.Body.Close()
			return err
		}
		_, copyErr := io.Copy(out, response.Body)
		closeErr := out.Close()
		response.Body.Close()
		if copyErr != nil || closeErr != nil {
			os.Remove(part)
			lastErr = copyErr
			if lastErr == nil {
				lastErr = closeErr
			}
			continue
		}
		if err := os.Rename(part, full); err != nil {
			return err
		}
		log.Printf("game asset cached: %s", name)
		return nil
	}
	if lastErr == nil {
		lastErr = os.ErrNotExist
	}
	return lastErr
}

func prefetchGameAssets(dir string) {
	prefetchGameAssetsWithOrigins(dir, gameOrigins())
}

func prefetchGamePack(dir string, origins []string) {
	if len(origins) == 0 {
		return
	}
	packName, expected := mainPackInfo(dir)
	if packName == "" {
		return
	}
	full := filepath.Join(dir, filepath.FromSlash(packName))
	if info, err := os.Stat(full); err == nil && !info.IsDir() && expected > 0 && info.Size() != expected {
		// The persistent /app/web cache can keep an old PCK while the new
		// index.html already advertises the new size. Refetch instead of
		// serving a mismatched pack to the browser.
		log.Printf("game asset %s size mismatch (%d != %d); refetching", packName, info.Size(), expected)
		if err := os.Remove(full); err != nil {
			log.Printf("game asset remove %s: %v", packName, err)
		}
	}
	if err := fetchGameAssetWithOrigins(dir, "/"+packName, origins); err != nil {
		log.Printf("game asset %s: %v", packName, err)
	}
}

func prefetchGameAssetsWithOrigins(dir string, origins []string) {
	if len(origins) == 0 {
		return
	}
	prefetchGamePack(dir, origins)
	name := "/index.wasm"
	if err := fetchGameAssetWithOrigins(dir, name, origins); err != nil {
		log.Printf("game asset %s: %v", name, err)
		return
	}
	full := filepath.Join(dir, filepath.FromSlash(name))
	gz := full + ".gz"
	if info, err := os.Stat(gz); err == nil && !info.IsDir() {
		return
	}
	if err := gzipFile(full, gz); err != nil {
		log.Printf("game asset gzip %s: %v", name, err)
	}
}

// mainPackInfo reads the PCK name and expected size from the exported HTML.
// The HTML is small and always ships in the build context, so it is the
// authoritative description of which pack the browser will request.
func mainPackInfo(dir string) (string, int64) {
	name := "index.pck"
	data, err := os.ReadFile(filepath.Join(dir, "index.html"))
	if err != nil {
		return name, 0
	}
	html := string(data)
	if match := regexp.MustCompile(`"mainPack":"([^"]+)"`).FindStringSubmatch(html); len(match) > 1 {
		name = match[1]
	}
	sizePattern := regexp.MustCompile(`"` + regexp.QuoteMeta(name) + `":(\d+)`)
	if match := sizePattern.FindStringSubmatch(html); len(match) > 1 {
		if size, err := strconv.ParseInt(match[1], 10, 64); err == nil {
			return name, size
		}
	}
	return name, 0
}

func gzipFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	part := dst + ".part"
	out, err := os.Create(part)
	if err != nil {
		return err
	}
	writer, err := gzip.NewWriterLevel(out, gzip.BestCompression)
	if err != nil {
		out.Close()
		os.Remove(part)
		return err
	}
	if _, err := io.Copy(writer, in); err != nil {
		writer.Close()
		out.Close()
		os.Remove(part)
		return err
	}
	if err := writer.Close(); err != nil {
		out.Close()
		os.Remove(part)
		return err
	}
	if err := out.Close(); err != nil {
		os.Remove(part)
		return err
	}
	return os.Rename(part, dst)
}

// cors lets the browser client run from another origin (local test server,
// static hosting, a store page) while the API stays on its own domain.
func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if origin := r.Header.Get("Origin"); origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Add("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Session-Token, X-Claim-Session")
			w.Header().Set("Access-Control-Max-Age", "86400")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// databaseGate keeps the container alive when the database is down: health and
// the realtime match endpoint keep working, while economy endpoints fail with a
// readable 503 instead of the platform reporting a dead backend.
func databaseGate(next http.Handler, service *api) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" || r.URL.Path == "/ws" || strings.HasPrefix(r.URL.Path, "/game/") || strings.HasPrefix(r.URL.Path, "/game-vk/") || strings.HasPrefix(r.URL.Path, "/stats/") || strings.HasPrefix(r.URL.Path, "/admin/moderation") || service.dbReady.Load() {
			next.ServeHTTP(w, r)
			return
		}
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{
			"success": false,
			"error":   "Database unavailable",
		})
	})
}

func (service *api) handleRules(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"success": false,
			"error":   "Method not allowed",
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"success":              true,
		"crystals_to_win":      crystalsToWin,
		"bot_fill_seconds":     int(roomBotFillDelay / time.Second),
		"match_length_seconds": int(matchLength / time.Second),
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
	if service.hub != nil {
		response["live_matches"] = service.hub.liveMatchCount()
		response["online_players"] = service.hub.connectedClientCount()
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
			if err == nil {
				err = initStatsTable(db)
			}
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
	if err := createMatchesTable(ctx, db); err != nil {
		return err
	}
	if err := createPaymentsTable(ctx, db); err != nil {
		return err
	}
	return backfillPlayerMatches(ctx, db)
}

// backfillPlayerMatches fills matches_played for rows created before the
// column existed. novice stays false for those rows on purpose.
func backfillPlayerMatches(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(ctx, `
		UPDATE players p
		SET matches_played = COALESCE(m.cnt, 0)
		FROM (
			SELECT player_id, COUNT(DISTINCT room_id) AS cnt
			FROM matches
			GROUP BY player_id
		) m
		WHERE m.player_id = p.id AND p.matches_played = 0
	`)
	return err
}

func createPlayersTable(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS players (
			id SERIAL PRIMARY KEY,
			nickname TEXT NOT NULL,
			nickname_custom BOOLEAN DEFAULT FALSE,
			sky_shards INTEGER DEFAULT 0,
			unlocked_wings TEXT DEFAULT '',
			unlocked_weapons TEXT DEFAULT '',
			matches_played INTEGER DEFAULT 0,
			novice BOOLEAN DEFAULT FALSE,
			platform TEXT NOT NULL DEFAULT 'standalone',
			external_id TEXT,
			level INTEGER DEFAULT 1,
			char_levels JSONB NOT NULL DEFAULT '{"warrior":1,"mage":1,"fairy":1}'::jsonb,
			char_xps JSONB NOT NULL DEFAULT '{"warrior":0,"mage":0,"fairy":0}'::jsonb,
			tutorial_completed BOOLEAN NOT NULL DEFAULT FALSE,
			tutorial_skipped BOOLEAN NOT NULL DEFAULT FALSE,
			tutorial_battles_used INTEGER NOT NULL DEFAULT 0,
			progress_initialized BOOLEAN NOT NULL DEFAULT FALSE,
			last_interstitial_at TIMESTAMPTZ
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
	_, err = db.ExecContext(ctx, `ALTER TABLE players ADD COLUMN IF NOT EXISTS session_token TEXT`)
	if err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `ALTER TABLE players ADD COLUMN IF NOT EXISTS last_compensation_at TIMESTAMPTZ`)
	if err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `ALTER TABLE players ADD COLUMN IF NOT EXISTS matches_played INTEGER DEFAULT 0`)
	if err != nil {
		return err
	}
	// Existing players keep novice=false: the migration must not push veterans
	// into the novice pool or force the tutorial on them.
	_, err = db.ExecContext(ctx, `ALTER TABLE players ADD COLUMN IF NOT EXISTS novice BOOLEAN DEFAULT FALSE`)
	if err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `ALTER TABLE players ADD COLUMN IF NOT EXISTS platform TEXT NOT NULL DEFAULT 'standalone'`)
	if err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `ALTER TABLE players ADD COLUMN IF NOT EXISTS external_id TEXT`)
	if err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `ALTER TABLE players ADD COLUMN IF NOT EXISTS level INTEGER DEFAULT 1`)
	if err != nil {
		return err
	}
	for _, statement := range []string{
		`ALTER TABLE players ADD COLUMN IF NOT EXISTS char_levels JSONB NOT NULL DEFAULT '{"warrior":1,"mage":1,"fairy":1}'::jsonb`,
		`ALTER TABLE players ADD COLUMN IF NOT EXISTS char_xps JSONB NOT NULL DEFAULT '{"warrior":0,"mage":0,"fairy":0}'::jsonb`,
		`ALTER TABLE players ADD COLUMN IF NOT EXISTS tutorial_completed BOOLEAN NOT NULL DEFAULT FALSE`,
		`ALTER TABLE players ADD COLUMN IF NOT EXISTS tutorial_skipped BOOLEAN NOT NULL DEFAULT FALSE`,
		`ALTER TABLE players ADD COLUMN IF NOT EXISTS tutorial_battles_used INTEGER NOT NULL DEFAULT 0`,
		`ALTER TABLE players ADD COLUMN IF NOT EXISTS progress_initialized BOOLEAN NOT NULL DEFAULT FALSE`,
		`ALTER TABLE players ADD COLUMN IF NOT EXISTS last_interstitial_at TIMESTAMPTZ`,
		`ALTER TABLE players ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ`,
		`ALTER TABLE players ADD COLUMN IF NOT EXISTS nickname_hidden BOOLEAN NOT NULL DEFAULT FALSE`,
		`ALTER TABLE players ADD COLUMN IF NOT EXISTS banned BOOLEAN NOT NULL DEFAULT FALSE`,
		`ALTER TABLE players ADD COLUMN IF NOT EXISTS ban_reason TEXT NOT NULL DEFAULT ''`,
	} {
		if _, err := db.ExecContext(ctx, statement); err != nil {
			return err
		}
	}
	// Ник — отображаемое имя, а не логин: уникальность не нужна и мешает
	// игрокам брать понравившиеся имена. Личность определяется по id.
	if err := dropNicknameUniqueness(ctx, db); err != nil {
		return err
	}
	// Backfill old rows before creating the unique identity index. The index
	// is created after dropNicknameUniqueness so that routine does not remove
	// it as if it were the old nickname uniqueness index.
	if _, err := db.ExecContext(ctx, `
		UPDATE players
		SET platform = 'standalone'
		WHERE platform IS NULL OR platform = ''
	`); err != nil {
		return err
	}
	if _, err := db.ExecContext(ctx, `
		UPDATE players
		SET external_id = id::text
		WHERE platform = 'standalone' AND external_id IS NULL
	`); err != nil {
		return err
	}
	// A platform profile never imports the device-local standalone XP or
	// tutorial state. Old VK/OK rows are marked initialized so a VK client
	// cannot upload an unrelated local profile into them.
	if _, err := db.ExecContext(ctx, `
		UPDATE players
		SET progress_initialized = TRUE
		WHERE platform <> 'standalone' AND progress_initialized = FALSE
	`); err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `
		CREATE UNIQUE INDEX IF NOT EXISTS players_platform_external_id_idx
		ON players (platform, external_id)
		WHERE external_id IS NOT NULL
	`)
	return err
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
		// This is the platform identity index added in M2, not the legacy
		// nickname-uniqueness index this routine exists to remove.
		if name == "players_platform_external_id_idx" {
			continue
		}
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
	for _, statement := range []string{
		`ALTER TABLE reports ADD COLUMN IF NOT EXISTS reported_player_id BIGINT`,
		`ALTER TABLE reports ADD COLUMN IF NOT EXISTS room_id BIGINT`,
		`ALTER TABLE reports ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'open'`,
		`ALTER TABLE reports ADD COLUMN IF NOT EXISTS action TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE reports ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ`,
	} {
		if _, err := db.ExecContext(ctx, statement); err != nil {
			return err
		}
	}
	_, err = db.ExecContext(ctx, `CREATE INDEX IF NOT EXISTS reports_created_idx ON reports (created_at)`)
	if err != nil {
		return err
	}
	if _, err := db.ExecContext(ctx, `CREATE INDEX IF NOT EXISTS reports_status_idx ON reports (status, created_at)`); err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `CREATE INDEX IF NOT EXISTS reports_reported_player_idx ON reports (reported_player_id)`)
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
	if err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `CREATE INDEX IF NOT EXISTS matches_room_player_idx ON matches (room_id, player_id)`)
	if err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `ALTER TABLE matches ADD COLUMN IF NOT EXISTS rewarded BOOLEAN DEFAULT FALSE`)
	if err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `ALTER TABLE matches ADD COLUMN IF NOT EXISTS rewarded_bonus BOOLEAN DEFAULT FALSE`)
	if err != nil {
		return err
	}
	for _, statement := range []string{
		`ALTER TABLE matches ADD COLUMN IF NOT EXISTS reward_shards INTEGER DEFAULT 0`,
		`ALTER TABLE matches ADD COLUMN IF NOT EXISTS reward_xp INTEGER DEFAULT 0`,
		`ALTER TABLE matches ADD COLUMN IF NOT EXISTS reward_character TEXT DEFAULT ''`,
	} {
		if _, err := db.ExecContext(ctx, statement); err != nil {
			return err
		}
	}
	// No unique index here: old deployments already contain duplicate
	// (room_id, player_id) rows, and CREATE UNIQUE INDEX aborted the whole
	// schema setup. Reward idempotency is guarded by SELECT ... FOR UPDATE.
	return nil
}

func newSessionToken() (string, error) {
	buffer := make([]byte, 32)
	if _, err := rand.Read(buffer); err != nil {
		return "", err
	}
	return hex.EncodeToString(buffer), nil
}

func (service *api) sessionTokenFromRequest(r *http.Request) string {
	return strings.TrimSpace(r.Header.Get(sessionHeader))
}

func (service *api) sessionTokenFor(ctx context.Context, playerID int64) (string, error) {
	var token string
	err := service.db.QueryRowContext(ctx, `SELECT COALESCE(session_token, '') FROM players WHERE id = $1`, playerID).Scan(&token)
	return token, err
}

func (service *api) sessionValid(ctx context.Context, playerID int64, token string) bool {
	if playerID <= 0 || token == "" {
		return false
	}
	var exists bool
	err := service.db.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM players WHERE id = $1 AND session_token = $2 AND session_token <> '')`,
		playerID, token,
	).Scan(&exists)
	return err == nil && exists
}

func (service *api) requireSession(w http.ResponseWriter, r *http.Request, playerID int64) bool {
	if service.sessionValid(r.Context(), playerID, service.sessionTokenFromRequest(r)) {
		return true
	}
	// Legacy migration: an account that never claimed a token may keep using
	// the old API. Once the new client claims it, the token is mandatory.
	if token, err := service.sessionTokenFor(r.Context(), playerID); err == nil && token == "" {
		return true
	}
	writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "Invalid session"})
	return false
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
	token, tokenErr := newSessionToken()
	if tokenErr != nil {
		log.Printf("generate session token: %v", tokenErr)
		writeJSON(w, http.StatusInternalServerError, registerResponse{Error: "Internal server error"})
		return
	}
	err := service.db.QueryRowContext(r.Context(),
		`INSERT INTO players (nickname, nickname_custom, session_token, novice, platform, last_seen_at) VALUES ($1, $2, $3, TRUE, 'standalone', NOW()) RETURNING id`, nickname, customNickname, token,
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
	if _, err := service.db.ExecContext(r.Context(),
		`UPDATE players SET external_id = id::text WHERE id = $1 AND external_id IS NULL`,
		playerID,
	); err != nil {
		log.Printf("register player external id: %v", err)
	}

	writeJSON(w, http.StatusCreated, registerResponse{Success: true, PlayerID: playerID, Token: token})
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
	var level int
	var unlockedWings string
	var unlockedWeapons string
	var matchesPlayed int
	var novice bool
	var levelsJSON string
	var xpsJSON string
	var tutorialCompleted bool
	var tutorialSkipped bool
	var tutorialBattlesUsed int
	var progressInitialized bool
	var lastInterstitialAt int64
	var storedToken string
	err = service.db.QueryRowContext(r.Context(),
		`SELECT nickname, COALESCE(nickname_custom, FALSE), sky_shards, COALESCE(level, 1),
		        COALESCE(unlocked_wings, ''), COALESCE(unlocked_weapons, ''),
		        COALESCE(matches_played, 0), COALESCE(novice, FALSE),
		        COALESCE(char_levels::text, ''), COALESCE(char_xps::text, ''),
		        COALESCE(tutorial_completed, FALSE), COALESCE(tutorial_skipped, FALSE),
		        COALESCE(tutorial_battles_used, 0), COALESCE(progress_initialized, FALSE),
		        COALESCE(EXTRACT(EPOCH FROM last_interstitial_at)::bigint, 0),
		        COALESCE(session_token, '')
		 FROM players WHERE id = $1`, playerID,
	).Scan(&nickname, &nicknameCustom, &shards, &level, &unlockedWings, &unlockedWeapons, &matchesPlayed, &novice,
		&levelsJSON, &xpsJSON, &tutorialCompleted, &tutorialSkipped, &tutorialBattlesUsed, &progressInitialized, &lastInterstitialAt, &storedToken)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, playerProfileResponse{Error: "Player not found"})
		return
	}
	if err != nil {
		log.Printf("load player profile: %v", err)
		writeJSON(w, http.StatusInternalServerError, playerProfileResponse{Error: "Internal server error"})
		return
	}
	progress := decodeStoredProgress(levelsJSON, xpsJSON, tutorialCompleted, tutorialSkipped, tutorialBattlesUsed, progressInitialized)
	sessionToken := storedToken
	if sessionToken == "" {
		// Only the new client asks to claim a session. An old client keeps a
		// tokenless read-only profile so it is not locked out mid-update.
		if strings.TrimSpace(r.Header.Get("X-Claim-Session")) != "1" {
			writeJSON(w, http.StatusOK, playerProfileResponse{
				Success:             true,
				PlayerID:            playerID,
				Nickname:            nickname,
				NicknameCustom:      nicknameCustom,
				SkyShards:           shards,
				Level:               level,
				UnlockedWings:       parseItemIDs(unlockedWings),
				UnlockedWeapons:     parseItemIDs(unlockedWeapons),
				MatchesPlayed:       matchesPlayed,
				Novice:              novice,
				CharLevels:          progress.CharLevels,
				CharXPs:             progress.CharXPs,
				TutorialCompleted:   progress.TutorialCompleted,
				TutorialSkipped:     progress.TutorialSkipped,
				TutorialBattlesUsed: progress.TutorialBattlesUsed,
				ProgressInitialized: progress.ProgressInitialized,
				LastInterstitialAt:  lastInterstitialAt,
			})
			return
		}
		newToken, tokenErr := newSessionToken()
		if tokenErr != nil {
			log.Printf("generate session token: %v", tokenErr)
			writeJSON(w, http.StatusInternalServerError, playerProfileResponse{Error: "Internal server error"})
			return
		}
		if _, err := service.db.ExecContext(r.Context(),
			`UPDATE players SET session_token = $1 WHERE id = $2 AND COALESCE(session_token, '') = ''`,
			newToken, playerID,
		); err != nil {
			log.Printf("claim session token: %v", err)
			writeJSON(w, http.StatusInternalServerError, playerProfileResponse{Error: "Internal server error"})
			return
		}
		// Re-read: a concurrent request may have claimed it first.
		if token, tokenErr := service.sessionTokenFor(r.Context(), playerID); tokenErr == nil {
			sessionToken = token
		} else {
			sessionToken = newToken
		}
	} else if !service.sessionValid(r.Context(), playerID, service.sessionTokenFromRequest(r)) {
		writeJSON(w, http.StatusUnauthorized, playerProfileResponse{Error: "Invalid session"})
		return
	}

	writeJSON(w, http.StatusOK, playerProfileResponse{
		Success:             true,
		PlayerID:            playerID,
		Nickname:            nickname,
		NicknameCustom:      nicknameCustom,
		SkyShards:           shards,
		Level:               level,
		UnlockedWings:       parseItemIDs(unlockedWings),
		UnlockedWeapons:     parseItemIDs(unlockedWeapons),
		MatchesPlayed:       matchesPlayed,
		Novice:              novice,
		CharLevels:          progress.CharLevels,
		CharXPs:             progress.CharXPs,
		TutorialCompleted:   progress.TutorialCompleted,
		TutorialSkipped:     progress.TutorialSkipped,
		TutorialBattlesUsed: progress.TutorialBattlesUsed,
		ProgressInitialized: progress.ProgressInitialized,
		LastInterstitialAt:  lastInterstitialAt,
		SessionToken:        sessionToken,
	})
}

func (service *api) handleSession(w http.ResponseWriter, r *http.Request) {
	if !requirePost(w, r) {
		return
	}
	var request sessionRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, sessionResponse{Error: "Invalid JSON"})
		return
	}
	if request.PlayerID <= 0 {
		writeJSON(w, http.StatusBadRequest, sessionResponse{Error: "Invalid player ID"})
		return
	}
	token, err := service.sessionTokenFor(r.Context(), request.PlayerID)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, sessionResponse{Error: "Player not found"})
		return
	}
	if err != nil {
		log.Printf("load session token: %v", err)
		writeJSON(w, http.StatusInternalServerError, sessionResponse{Error: "Internal server error"})
		return
	}
	supplied := service.sessionTokenFromRequest(r)
	if token != "" {
		if supplied != token {
			writeJSON(w, http.StatusUnauthorized, sessionResponse{Error: "Invalid session"})
			return
		}
		service.touchPlayerLastSeen(r.Context(), request.PlayerID)
		writeJSON(w, http.StatusOK, sessionResponse{Success: true, Token: token})
		return
	}
	newToken, tokenErr := newSessionToken()
	if tokenErr != nil {
		log.Printf("generate session token: %v", tokenErr)
		writeJSON(w, http.StatusInternalServerError, sessionResponse{Error: "Internal server error"})
		return
	}
	result, err := service.db.ExecContext(r.Context(),
		`UPDATE players SET session_token = $1 WHERE id = $2 AND COALESCE(session_token, '') = ''`,
		newToken, request.PlayerID,
	)
	if err != nil {
		log.Printf("claim session token: %v", err)
		writeJSON(w, http.StatusInternalServerError, sessionResponse{Error: "Internal server error"})
		return
	}
	if affected, _ := result.RowsAffected(); affected == 0 {
		if raced, raceErr := service.sessionTokenFor(r.Context(), request.PlayerID); raceErr == nil && raced != "" {
			writeJSON(w, http.StatusOK, sessionResponse{Success: true, Token: raced})
			return
		}
		writeJSON(w, http.StatusConflict, sessionResponse{Error: "Session already claimed"})
		return
	}
	service.touchPlayerLastSeen(r.Context(), request.PlayerID)
	writeJSON(w, http.StatusOK, sessionResponse{Success: true, Token: newToken})
}

// touchPlayerLastSeen records a launch for the moderation page ("последний
// вход"). It is best-effort: a failure must not block the session response.
func (service *api) touchPlayerLastSeen(ctx context.Context, playerID int64) {
	if _, err := service.db.ExecContext(ctx,
		`UPDATE players SET last_seen_at = NOW() WHERE id = $1`, playerID,
	); err != nil {
		log.Printf("touch last seen: %v", err)
	}
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
	if !service.requireSession(w, r, request.PlayerID) {
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
	if !service.requireSession(w, r, request.PlayerID) {
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
	// Remember which player the nickname belonged to at report time, so the
	// moderation page can target exactly that account. Nicknames are not
	// unique: if several players match, leave it NULL and let the moderator
	// choose by player_id.
	var reportedPlayerID sql.NullInt64
	if err := service.db.QueryRowContext(r.Context(),
		`SELECT CASE WHEN COUNT(*) = 1 THEN MIN(id) END
		   FROM players
		  WHERE LOWER(BTRIM(nickname)) = LOWER(BTRIM($1))`,
		nickname,
	).Scan(&reportedPlayerID); err != nil {
		log.Printf("resolve reported player: %v", err)
	}
	_, err = service.db.ExecContext(r.Context(),
		`INSERT INTO reports (reporter_id, reported_nickname, reason, reported_player_id) VALUES ($1, $2, $3, $4)`,
		request.PlayerID, nickname, reason, reportedPlayerID,
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
	if !service.requireSession(w, r, request.PlayerID) {
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
		// Idempotent retry: a lost response after a committed purchase must not
		// look like a failure and must not charge the player twice.
		writeJSON(w, http.StatusOK, buyWingResponse{Success: true, NewShards: shards})
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
	if !service.requireSession(w, r, request.PlayerID) {
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
		// Idempotent retry: a lost response after a committed purchase must not
		// look like a failure and must not charge the player twice.
		writeJSON(w, http.StatusOK, buyWeaponResponse{Success: true, NewShards: shards})
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
	if !service.requireSession(w, r, request.PlayerID) {
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
	character := strings.TrimSpace(request.Character)
	xp := clampInt(request.XP, 0, maxMatchXP)
	if character != "" && !validCharacterKey(character) {
		writeJSON(w, http.StatusBadRequest, matchRewardResponse{Error: "Invalid character"})
		return
	}
	if xp > 0 && character == "" {
		writeJSON(w, http.StatusBadRequest, matchRewardResponse{Error: "Character is required for XP"})
		return
	}
	if request.PlayerID <= 0 || request.RoomID <= 0 || amount <= 0 || amount > maxMatchReward {
		writeJSON(w, http.StatusBadRequest, matchRewardResponse{Error: "Invalid reward"})
		return
	}

	transaction, err := service.db.BeginTx(r.Context(), nil)
	if err != nil {
		log.Printf("begin match reward: %v", err)
		writeJSON(w, http.StatusInternalServerError, matchRewardResponse{Error: "Internal server error"})
		return
	}
	defer transaction.Rollback()

	// One reward per finished match: the row is marked atomically, so a retry
	// or a replayed request cannot grant shards or XP twice.
	var won bool
	var matchID int64
	rewardShards := amount
	rewardXP := xp
	rewardCharacter := character
	if request.Bonus {
		// The rewarded-ad bonus is a second, separately idempotent payout for
		// a match whose base reward was already claimed. The stored base
		// values are authoritative, so the bonus always pays exactly x2.
		var storedShards, storedXP int
		var storedCharacter string
		err = transaction.QueryRowContext(r.Context(),
			`SELECT id, won, COALESCE(reward_shards, 0), COALESCE(reward_xp, 0), COALESCE(reward_character, '')
			 FROM matches WHERE room_id = $1 AND player_id = $2 AND COALESCE(rewarded, FALSE) = TRUE AND COALESCE(rewarded_bonus, FALSE) = FALSE ORDER BY id LIMIT 1 FOR UPDATE`,
			request.RoomID, request.PlayerID,
		).Scan(&matchID, &won, &storedShards, &storedXP, &storedCharacter)
		if errors.Is(err, sql.ErrNoRows) {
			writeJSON(w, http.StatusConflict, matchRewardResponse{Error: "Reward already claimed"})
			return
		}
		if err != nil {
			log.Printf("claim match bonus: %v", err)
			writeJSON(w, http.StatusInternalServerError, matchRewardResponse{Error: "Internal server error"})
			return
		}
		if storedShards > 0 {
			rewardShards = storedShards
		}
		if storedXP > 0 && storedCharacter != "" {
			rewardXP = storedXP
			rewardCharacter = storedCharacter
		}
		if _, err := transaction.ExecContext(r.Context(),
			`UPDATE matches SET rewarded_bonus = TRUE WHERE room_id = $1 AND player_id = $2 AND COALESCE(rewarded, FALSE) = TRUE AND COALESCE(rewarded_bonus, FALSE) = FALSE`,
			request.RoomID, request.PlayerID,
		); err != nil {
			log.Printf("mark match bonus: %v", err)
			writeJSON(w, http.StatusInternalServerError, matchRewardResponse{Error: "Internal server error"})
			return
		}
	} else {
		err = transaction.QueryRowContext(r.Context(),
			`SELECT id, won FROM matches WHERE room_id = $1 AND player_id = $2 AND COALESCE(rewarded, FALSE) = FALSE ORDER BY id LIMIT 1 FOR UPDATE`,
			request.RoomID, request.PlayerID,
		).Scan(&matchID, &won)
		if errors.Is(err, sql.ErrNoRows) {
			writeJSON(w, http.StatusConflict, matchRewardResponse{Error: "Reward already claimed"})
			return
		}
		if err != nil {
			log.Printf("claim match reward: %v", err)
			writeJSON(w, http.StatusInternalServerError, matchRewardResponse{Error: "Internal server error"})
			return
		}
		// The server owns the payout ceiling even though the client picks the
		// 1/3/5 tier: a win can pay at most 5, a loss at most 3.
		maxAward := 3
		if won {
			maxAward = 5
		}
		if rewardShards > maxAward {
			rewardShards = maxAward
		}
		// Mark every duplicate row for this room/player as rewarded so a retry
		// cannot farm the same match more than once. Store the base payout for
		// the later, separately idempotent x2 bonus.
		if _, err := transaction.ExecContext(r.Context(),
			`UPDATE matches SET rewarded = TRUE, reward_shards = $3, reward_xp = $4, reward_character = $5
			 WHERE room_id = $1 AND player_id = $2 AND COALESCE(rewarded, FALSE) = FALSE`,
			request.RoomID, request.PlayerID, rewardShards, rewardXP, rewardCharacter,
		); err != nil {
			log.Printf("mark match reward: %v", err)
			writeJSON(w, http.StatusInternalServerError, matchRewardResponse{Error: "Internal server error"})
			return
		}
	}

	levels, xps, levelUps, levelUpShards, err := applyCharacterXP(
		r.Context(), transaction, request.PlayerID, rewardCharacter, rewardXP,
	)
	if err != nil {
		log.Printf("apply match xp: %v", err)
		writeJSON(w, http.StatusInternalServerError, matchRewardResponse{Error: "Internal server error"})
		return
	}
	var newShards int
	payout := rewardShards + levelUpShards
	err = transaction.QueryRowContext(r.Context(),
		`UPDATE players SET sky_shards = COALESCE(sky_shards, 0) + $1 WHERE id = $2 RETURNING sky_shards`,
		payout, request.PlayerID,
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
	if err := transaction.Commit(); err != nil {
		log.Printf("commit match reward: %v", err)
		writeJSON(w, http.StatusInternalServerError, matchRewardResponse{Error: "Internal server error"})
		return
	}

	writeJSON(w, http.StatusOK, matchRewardResponse{
		Success:       true,
		NewShards:     newShards,
		CharLevels:    levels,
		CharXPs:       xps,
		LeveledUp:     len(levelUps) > 0,
		LevelUpShards: levelUpShards,
		Bonus:         request.Bonus,
	})
}

// handleAccountDelete removes the player's profile and personal fields.
// Match history and analytics are kept but anonymized: their player_id is
// zeroed and session/user-agent fields are cleared, so aggregate counters stay
// correct without leaving a link to the person.
func (service *api) handleAccountDelete(w http.ResponseWriter, r *http.Request) {
	if !requirePost(w, r) {
		return
	}
	var request accountDeleteRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, accountDeleteResponse{Error: "Invalid JSON"})
		return
	}
	if request.PlayerID <= 0 {
		writeJSON(w, http.StatusBadRequest, accountDeleteResponse{Error: "Invalid player"})
		return
	}
	if !service.requireSession(w, r, request.PlayerID) {
		return
	}
	transaction, err := service.db.BeginTx(r.Context(), nil)
	if err != nil {
		log.Printf("begin account delete: %v", err)
		writeJSON(w, http.StatusInternalServerError, accountDeleteResponse{Error: "Internal server error"})
		return
	}
	defer transaction.Rollback()
	var nickname string
	err = transaction.QueryRowContext(r.Context(),
		`DELETE FROM players WHERE id = $1 RETURNING nickname`, request.PlayerID,
	).Scan(&nickname)
	if errors.Is(err, sql.ErrNoRows) {
		// Already deleted: deletion is idempotent.
		writeJSON(w, http.StatusOK, accountDeleteResponse{Success: true})
		return
	}
	if err != nil {
		log.Printf("delete player: %v", err)
		writeJSON(w, http.StatusInternalServerError, accountDeleteResponse{Error: "Internal server error"})
		return
	}
	if _, err := transaction.ExecContext(r.Context(),
		`UPDATE stats_events SET player_id = 0, session_id = '', user_agent = '' WHERE player_id = $1`,
		request.PlayerID,
	); err != nil {
		log.Printf("anonymize stats: %v", err)
		writeJSON(w, http.StatusInternalServerError, accountDeleteResponse{Error: "Internal server error"})
		return
	}
	if _, err := transaction.ExecContext(r.Context(),
		`UPDATE matches SET player_id = 0 WHERE player_id = $1`, request.PlayerID,
	); err != nil {
		log.Printf("anonymize matches: %v", err)
		writeJSON(w, http.StatusInternalServerError, accountDeleteResponse{Error: "Internal server error"})
		return
	}
	if _, err := transaction.ExecContext(r.Context(),
		`DELETE FROM reports WHERE reporter_id = $1 OR reported_nickname = $2`, request.PlayerID, nickname,
	); err != nil {
		log.Printf("delete reports: %v", err)
		writeJSON(w, http.StatusInternalServerError, accountDeleteResponse{Error: "Internal server error"})
		return
	}
	if err := transaction.Commit(); err != nil {
		log.Printf("commit account delete: %v", err)
		writeJSON(w, http.StatusInternalServerError, accountDeleteResponse{Error: "Internal server error"})
		return
	}
	log.Printf("[ACCOUNT] deleted player=%d", request.PlayerID)
	writeJSON(w, http.StatusOK, accountDeleteResponse{Success: true})
}


func (service *api) handleCompensation(w http.ResponseWriter, r *http.Request) {
	if !requirePost(w, r) {
		return
	}
	var request compensationRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, matchRewardResponse{Error: "Invalid JSON"})
		return
	}
	if !service.requireSession(w, r, request.PlayerID) {
		return
	}
	if request.PlayerID <= 0 || request.Reason != "match_aborted" {
		writeJSON(w, http.StatusBadRequest, matchRewardResponse{Error: "Invalid compensation"})
		return
	}
	transaction, err := service.db.BeginTx(r.Context(), nil)
	if err != nil {
		log.Printf("begin compensation: %v", err)
		writeJSON(w, http.StatusInternalServerError, matchRewardResponse{Error: "Internal server error"})
		return
	}
	defer transaction.Rollback()
	var last sql.NullTime
	err = transaction.QueryRowContext(r.Context(),
		`SELECT last_compensation_at FROM players WHERE id = $1 FOR UPDATE`,
		request.PlayerID,
	).Scan(&last)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, matchRewardResponse{Error: "Player not found"})
		return
	}
	if err != nil {
		log.Printf("claim compensation: %v", err)
		writeJSON(w, http.StatusInternalServerError, matchRewardResponse{Error: "Internal server error"})
		return
	}
	if last.Valid && time.Since(last.Time) < compensationCooldown {
		writeJSON(w, http.StatusTooManyRequests, matchRewardResponse{Error: "cooldown"})
		return
	}
	var newShards int
	err = transaction.QueryRowContext(r.Context(),
		`UPDATE players SET sky_shards = COALESCE(sky_shards, 0) + $1, last_compensation_at = NOW() WHERE id = $2 RETURNING sky_shards`,
		compensationShards, request.PlayerID,
	).Scan(&newShards)
	if err != nil {
		log.Printf("grant compensation: %v", err)
		writeJSON(w, http.StatusInternalServerError, matchRewardResponse{Error: "Internal server error"})
		return
	}
	if err := transaction.Commit(); err != nil {
		log.Printf("commit compensation: %v", err)
		writeJSON(w, http.StatusInternalServerError, matchRewardResponse{Error: "Internal server error"})
		return
	}
	writeJSON(w, http.StatusOK, matchRewardResponse{Success: true, NewShards: newShards})
}

func (service *api) handleAdminGrantShards(w http.ResponseWriter, r *http.Request) {
	if !requirePost(w, r) {
		return
	}
	if r.Header.Get("X-Admin-Token") != adminTokenValue() {
		writeJSON(w, http.StatusForbidden, adminGrantResponse{Error: "Forbidden"})
		return
	}
	var request adminGrantRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, adminGrantResponse{Error: "Invalid JSON"})
		return
	}
	if request.Amount < 1 || request.Amount > 1000000 {
		writeJSON(w, http.StatusBadRequest, adminGrantResponse{Error: "Invalid amount"})
		return
	}
	transaction, err := service.db.BeginTx(r.Context(), nil)
	if err != nil {
		log.Printf("begin admin grant: %v", err)
		writeJSON(w, http.StatusInternalServerError, adminGrantResponse{Error: "Internal server error"})
		return
	}
	defer transaction.Rollback()
	playerID := request.PlayerID
	var nickname string
	if playerID > 0 {
		err = transaction.QueryRowContext(r.Context(),
			`SELECT nickname FROM players WHERE id = $1 FOR UPDATE`, playerID,
		).Scan(&nickname)
		if errors.Is(err, sql.ErrNoRows) {
			writeJSON(w, http.StatusNotFound, adminGrantResponse{Error: "Player not found"})
			return
		}
		if err != nil {
			log.Printf("lock admin grant player: %v", err)
			writeJSON(w, http.StatusInternalServerError, adminGrantResponse{Error: "Internal server error"})
			return
		}
	} else {
		nickname = strings.TrimSpace(request.Nickname)
		if nickname == "" {
			writeJSON(w, http.StatusBadRequest, adminGrantResponse{Error: "Nickname is required"})
			return
		}
		findCandidates := func() []adminPlayerRef {
			candidateRows, err := transaction.QueryContext(r.Context(),
				`SELECT id, nickname, COALESCE(sky_shards, 0) FROM players WHERE nickname ILIKE '%' || $1 || '%' ORDER BY id LIMIT 10`,
				nickname,
			)
			if err != nil {
				return nil
			}
			defer candidateRows.Close()
			candidates := make([]adminPlayerRef, 0, 4)
			for candidateRows.Next() {
				var candidate adminPlayerRef
				if err := candidateRows.Scan(&candidate.ID, &candidate.Nickname, &candidate.Shards); err != nil {
					return candidates
				}
				candidates = append(candidates, candidate)
			}
			return candidates
		}
		rows, err := transaction.QueryContext(r.Context(),
			`SELECT id, nickname FROM players WHERE LOWER(TRIM(nickname)) = LOWER($1) FOR UPDATE`, nickname,
		)
		if err != nil {
			log.Printf("find admin grant player: %v", err)
			writeJSON(w, http.StatusInternalServerError, adminGrantResponse{Error: "Internal server error"})
			return
		}
		type foundPlayer struct {
			id       int64
			nickname string
		}
		var found []foundPlayer
		for rows.Next() {
			var player foundPlayer
			if err := rows.Scan(&player.id, &player.nickname); err != nil {
				rows.Close()
				writeJSON(w, http.StatusInternalServerError, adminGrantResponse{Error: "Internal server error"})
				return
			}
			found = append(found, player)
		}
		rows.Close()
		if len(found) == 0 {
			writeJSON(w, http.StatusNotFound, adminGrantResponse{Error: "Player not found", Candidates: findCandidates()})
			return
		}
		if len(found) > 1 {
			writeJSON(w, http.StatusConflict, adminGrantResponse{Error: "Multiple players with this nickname; use player_id", Candidates: findCandidates()})
			return
		}
		playerID = found[0].id
		nickname = found[0].nickname
	}
	var newShards int
	err = transaction.QueryRowContext(r.Context(),
		`UPDATE players SET sky_shards = COALESCE(sky_shards, 0) + $1 WHERE id = $2 RETURNING sky_shards`,
		request.Amount, playerID,
	).Scan(&newShards)
	if err != nil {
		log.Printf("admin grant update: %v", err)
		writeJSON(w, http.StatusInternalServerError, adminGrantResponse{Error: "Internal server error"})
		return
	}
	if err := transaction.Commit(); err != nil {
		log.Printf("commit admin grant: %v", err)
		writeJSON(w, http.StatusInternalServerError, adminGrantResponse{Error: "Internal server error"})
		return
	}
	log.Printf("admin grant: player=%d nickname=%q amount=%d new_shards=%d", playerID, nickname, request.Amount, newShards)
	writeJSON(w, http.StatusOK, adminGrantResponse{
		Success: true, PlayerID: playerID, Nickname: nickname, NewShards: newShards,
	})
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
