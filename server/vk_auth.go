package main

import (
	"context"
	"crypto/hmac"
	"crypto/md5"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

const (
	defaultVKAppID   = "54906713"
	vkAuthMaxAge     = 3600
	vkAuthRateLimit  = 20
	vkAuthRateWindow = time.Minute
)

var (
	errVKMissingSign = errors.New("missing_sign")
	errVKAppID       = errors.New("app_id_mismatch")
	errVKTimestamp   = errors.New("stale_timestamp")
	errVKSignature   = errors.New("invalid_signature")
	errVKUserID      = errors.New("invalid_user_id")
	errVKSecret      = errors.New("secret_not_configured")
)

type vkAuthResponse struct {
	Success             bool           `json:"success"`
	PlayerID            int64          `json:"player_id,omitempty"`
	SessionToken        string         `json:"session_token,omitempty"`
	Nickname            string         `json:"nickname,omitempty"`
	NicknameCustom      bool           `json:"nickname_custom"`
	SkyShards           int            `json:"sky_shards,omitempty"`
	Level               int            `json:"level,omitempty"`
	UnlockedWings       []int          `json:"unlocked_wings,omitempty"`
	UnlockedWeapons     []int          `json:"unlocked_weapons,omitempty"`
	Skins               []int          `json:"skins,omitempty"`
	Weapons             []int          `json:"weapons,omitempty"`
	MatchesPlayed       int            `json:"matches_played"`
	Novice              bool           `json:"novice"`
	CharLevels          map[string]int `json:"char_levels"`
	CharXPs             map[string]int `json:"char_xps"`
	TutorialCompleted   bool           `json:"tutorial_completed"`
	TutorialSkipped     bool           `json:"tutorial_skipped"`
	TutorialBattlesUsed int            `json:"tutorial_battles_used"`
	ProgressInitialized bool           `json:"progress_initialized"`
	LastInterstitialAt  int64          `json:"last_interstitial_at"`
	Error               string         `json:"error,omitempty"`
}

type vkProfileRow struct {
	id                  int64
	nickname            string
	nicknameCustom      bool
	shards              int
	wings               string
	weapons             string
	matchesPlayed       int
	novice              bool
	level               int
	levelsJSON          string
	xpsJSON             string
	tutorialCompleted   bool
	tutorialSkipped     bool
	tutorialBattlesUsed int
	progressInitialized bool
	lastInterstitialAt  int64
	sessionToken        string
}

type vkRateLimiter struct {
	mu     sync.Mutex
	hits   map[string][]time.Time
	limit  int
	window time.Duration
}

func newVKRateLimiter(limit int, window time.Duration) *vkRateLimiter {
	return &vkRateLimiter{
		hits:   make(map[string][]time.Time),
		limit:  limit,
		window: window,
	}
}

func (limiter *vkRateLimiter) allow(key string) bool {
	if limiter == nil {
		return true
	}
	now := time.Now()
	cutoff := now.Add(-limiter.window)
	limiter.mu.Lock()
	defer limiter.mu.Unlock()
	entries := limiter.hits[key]
	kept := entries[:0]
	for _, entry := range entries {
		if entry.After(cutoff) {
			kept = append(kept, entry)
		}
	}
	if len(kept) >= limiter.limit {
		limiter.hits[key] = kept
		return false
	}
	limiter.hits[key] = append(kept, now)
	// Keep the map bounded on a long-running process.
	if len(limiter.hits) > 2000 {
		for ip, values := range limiter.hits {
			if len(values) == 0 || !values[len(values)-1].After(cutoff) {
				delete(limiter.hits, ip)
			}
		}
	}
	return true
}

func vkAppID() string {
	if value := strings.TrimSpace(os.Getenv("VK_APP_ID")); value != "" {
		return value
	}
	return defaultVKAppID
}

func vkAppSecret() string {
	return strings.TrimSpace(os.Getenv("VK_APP_SECRET"))
}

func vkSignatureMessage(params map[string]string) string {
	keys := make([]string, 0, len(params))
	for key := range params {
		if strings.HasPrefix(key, "vk_") {
			keys = append(keys, key)
		}
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, key := range keys {
		// VK signs URL-encoded values. QueryEscape is close but uses "+" for
		// spaces; VK's examples require %20.
		value := strings.ReplaceAll(url.QueryEscape(params[key]), "+", "%20")
		parts = append(parts, key+"="+value)
	}
	return strings.Join(parts, "&")
}

// vkSign is the current VK launch-params signature: HMAC-SHA256 over sorted
// vk_* key=value pairs joined by "&", base64url without padding.
func vkSign(params map[string]string, secret string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(vkSignatureMessage(params)))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

// vkLegacySign is the old MD5 signature still accepted for launch params
// generated before VK switched to HMAC-SHA256.
func vkLegacySign(params map[string]string, secret string) string {
	keys := make([]string, 0, len(params))
	for key := range params {
		if strings.HasPrefix(key, "vk_") {
			keys = append(keys, key)
		}
	}
	sort.Strings(keys)
	var builder strings.Builder
	for _, key := range keys {
		builder.WriteString(key)
		builder.WriteByte('=')
		builder.WriteString(params[key])
	}
	builder.WriteString(secret)
	sum := md5.Sum([]byte(builder.String()))
	return hex.EncodeToString(sum[:])
}

func verifyVKLaunchParams(params map[string]string, appID, secret string, now time.Time) error {
	if secret == "" {
		return errVKSecret
	}
	if strings.TrimSpace(params["vk_app_id"]) != appID {
		return errVKAppID
	}
	rawTS := strings.TrimSpace(params["vk_ts"])
	if rawTS == "" {
		return errVKTimestamp
	}
	ts, err := strconv.ParseInt(rawTS, 10, 64)
	if err != nil || ts <= 0 {
		return errVKTimestamp
	}
	if now.Unix()-ts > vkAuthMaxAge || ts > now.Unix()+300 {
		return errVKTimestamp
	}
	userID := strings.TrimSpace(params["vk_user_id"])
	if userID == "" {
		return errVKUserID
	}
	if _, err := strconv.ParseInt(userID, 10, 64); err != nil {
		return errVKUserID
	}
	// Base64url is case-sensitive; only the legacy hex form is lowercased.
	sign := strings.TrimSpace(params["sign"])
	if sign == "" {
		return errVKMissingSign
	}
	expected := vkSign(params, secret)
	legacy := vkLegacySign(params, secret)
	hmacOK := subtle.ConstantTimeCompare([]byte(sign), []byte(expected)) == 1
	legacyOK := subtle.ConstantTimeCompare([]byte(strings.ToLower(sign)), []byte(legacy)) == 1
	if !hmacOK && !legacyOK {
		return errVKSignature
	}
	return nil
}

func normalizeVKDisplayName(name string) string {
	name = strings.TrimSpace(name)
	if name == "" || !utf8.ValidString(name) || containsProfanity(name) {
		return ""
	}
	runes := []rune(name)
	if len(runes) > 32 {
		name = string(runes[:32])
	}
	return strings.TrimSpace(name)
}

func splitUnlockedItems(ids []int) ([]int, []int) {
	skins := make([]int, 0, 2)
	weapons := make([]int, 0, len(ids))
	for _, id := range ids {
		if id >= 101 && id <= 102 {
			skins = append(skins, id)
		} else {
			weapons = append(weapons, id)
		}
	}
	return skins, weapons
}

func readVKParams(w http.ResponseWriter, r *http.Request) (map[string]string, error) {
	params := make(map[string]string)
	r.Body = http.MaxBytesReader(w, r.Body, maxRequestBody)
	contentType := strings.ToLower(r.Header.Get("Content-Type"))
	if strings.Contains(contentType, "application/json") || contentType == "" {
		decoder := json.NewDecoder(r.Body)
		decoder.UseNumber()
		var raw map[string]any
		if err := decoder.Decode(&raw); err != nil {
			return nil, err
		}
		for key, value := range raw {
			switch typed := value.(type) {
			case string:
				params[key] = typed
			case json.Number:
				params[key] = typed.String()
			case bool:
				params[key] = strconv.FormatBool(typed)
			default:
				return nil, fmt.Errorf("unsupported parameter %s", key)
			}
		}
		return params, nil
	}
	if err := r.ParseForm(); err != nil {
		return nil, err
	}
	for key := range r.Form {
		params[key] = r.Form.Get(key)
	}
	return params, nil
}

func vkClientIP(r *http.Request) string {
	if forwarded := strings.TrimSpace(r.Header.Get("X-Forwarded-For")); forwarded != "" {
		parts := strings.Split(forwarded, ",")
		// The last entry is appended by the closest proxy; the first can be
		// supplied by the caller and must not choose the rate-limit bucket.
		return strings.TrimSpace(parts[len(parts)-1])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}

func (service *api) handleVKAuth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeJSON(w, http.StatusMethodNotAllowed, vkAuthResponse{Error: "Method not allowed"})
		return
	}
	if !service.vkAuthLimiter.allow(vkClientIP(r)) {
		w.Header().Set("Retry-After", "60")
		writeJSON(w, http.StatusTooManyRequests, vkAuthResponse{Error: "rate_limited"})
		return
	}
	params, err := readVKParams(w, r)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, vkAuthResponse{Error: "invalid_launch_params"})
		return
	}
	secret := vkAppSecret()
	if secret == "" {
		log.Printf("vk auth: VK_APP_SECRET is not configured")
		writeJSON(w, http.StatusServiceUnavailable, vkAuthResponse{Error: "vk_auth_not_configured"})
		return
	}
	if err := verifyVKLaunchParams(params, vkAppID(), secret, time.Now()); err != nil {
		// Never log the signature or the full launch-parameter set.
		log.Printf("vk auth rejected: %s", err.Error())
		writeJSON(w, http.StatusUnauthorized, vkAuthResponse{Error: "invalid_vk_auth"})
		return
	}
	externalID := strings.TrimSpace(params["vk_user_id"])
	displayName := normalizeVKDisplayName(firstNonEmpty(params["name"], params["vk_name"]))
	profile, err := service.upsertVKProfile(r.Context(), externalID, displayName)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, http.StatusInternalServerError, vkAuthResponse{Error: "Internal server error"})
		return
	}
	if err != nil {
		log.Printf("vk auth profile: %v", err)
		writeJSON(w, http.StatusInternalServerError, vkAuthResponse{Error: "Internal server error"})
		return
	}
	unlockedWeapons := parseItemIDs(profile.weapons)
	skins, weapons := splitUnlockedItems(unlockedWeapons)
	progress := decodeStoredProgress(
		profile.levelsJSON, profile.xpsJSON,
		profile.tutorialCompleted, profile.tutorialSkipped, profile.tutorialBattlesUsed,
		profile.progressInitialized,
	)
	writeJSON(w, http.StatusOK, vkAuthResponse{
		Success:             true,
		PlayerID:            profile.id,
		SessionToken:        profile.sessionToken,
		Nickname:            profile.nickname,
		NicknameCustom:      profile.nicknameCustom,
		SkyShards:           profile.shards,
		Level:               profile.level,
		UnlockedWings:       parseItemIDs(profile.wings),
		UnlockedWeapons:     unlockedWeapons,
		Skins:               skins,
		Weapons:             weapons,
		MatchesPlayed:       profile.matchesPlayed,
		Novice:              profile.novice,
		CharLevels:          progress.CharLevels,
		CharXPs:             progress.CharXPs,
		TutorialCompleted:   progress.TutorialCompleted,
		TutorialSkipped:     progress.TutorialSkipped,
		TutorialBattlesUsed: progress.TutorialBattlesUsed,
		ProgressInitialized: progress.ProgressInitialized,
		LastInterstitialAt:  profile.lastInterstitialAt,
	})
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func (service *api) upsertVKProfile(ctx context.Context, externalID, displayName string) (vkProfileRow, error) {
	tx, err := service.db.BeginTx(ctx, nil)
	if err != nil {
		return vkProfileRow{}, err
	}
	defer tx.Rollback()

	token, err := newSessionToken()
	if err != nil {
		return vkProfileRow{}, err
	}
	defaultName := "VK " + externalID
	if displayName != "" {
		defaultName = displayName
	}
	_, err = tx.ExecContext(ctx, `
		INSERT INTO players (
			nickname, nickname_custom, sky_shards, unlocked_wings, unlocked_weapons,
			matches_played, novice, session_token, platform, external_id, level,
			progress_initialized
		) VALUES ($1, FALSE, 0, '', '', 0, TRUE, $2, 'vk', $3, 1, TRUE)
		ON CONFLICT (platform, external_id) WHERE external_id IS NOT NULL DO NOTHING
	`, defaultName, token, externalID)
	if err != nil {
		return vkProfileRow{}, err
	}

	var profile vkProfileRow
	err = tx.QueryRowContext(ctx, `
		SELECT id, nickname, COALESCE(nickname_custom, FALSE), COALESCE(sky_shards, 0),
		       COALESCE(unlocked_wings, ''), COALESCE(unlocked_weapons, ''),
		       COALESCE(matches_played, 0), COALESCE(novice, FALSE),
		       COALESCE(level, 1),
		       COALESCE(char_levels::text, ''), COALESCE(char_xps::text, ''),
		       COALESCE(tutorial_completed, FALSE), COALESCE(tutorial_skipped, FALSE),
		       COALESCE(tutorial_battles_used, 0), COALESCE(progress_initialized, FALSE),
		       COALESCE(EXTRACT(EPOCH FROM last_interstitial_at)::bigint, 0),
		       COALESCE(session_token, '')
		FROM players WHERE platform = 'vk' AND external_id = $1 FOR UPDATE
	`, externalID).Scan(
		&profile.id, &profile.nickname, &profile.nicknameCustom, &profile.shards,
		&profile.wings, &profile.weapons, &profile.matchesPlayed, &profile.novice,
		&profile.level, &profile.levelsJSON, &profile.xpsJSON,
		&profile.tutorialCompleted, &profile.tutorialSkipped, &profile.tutorialBattlesUsed,
		&profile.progressInitialized, &profile.lastInterstitialAt, &profile.sessionToken,
	)
	if err != nil {
		return vkProfileRow{}, err
	}
	if profile.sessionToken == "" {
		if _, err := tx.ExecContext(ctx, `UPDATE players SET session_token = $1 WHERE id = $2`, token, profile.id); err != nil {
			return vkProfileRow{}, err
		}
		profile.sessionToken = token
	}
	if displayName != "" && !profile.nicknameCustom {
		if _, err := tx.ExecContext(ctx, `UPDATE players SET nickname = $1 WHERE id = $2`, displayName, profile.id); err != nil {
			return vkProfileRow{}, err
		}
		profile.nickname = displayName
	}
	if err := tx.Commit(); err != nil {
		return vkProfileRow{}, err
	}
	return profile, nil
}
