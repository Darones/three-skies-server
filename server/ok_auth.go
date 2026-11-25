package main

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

const okAPIURL = "https://api.ok.ru/fb.do"

var errOKNotConfigured = errors.New("ok_not_configured")

type okAuthRequest struct {
	LocalAccessToken string `json:"local_access_token"`
	AccessToken      string `json:"access_token"`
	OKUserID         string `json:"ok_user_id"`
	Name             string `json:"name"`
	Avatar           string `json:"avatar"`
}

type okUser struct {
	UID       string
	FirstName string
	LastName  string
	Name      string
	Pic1      string
	Pic2      string
	Pic3      string
}

var okHTTPClient = &http.Client{Timeout: 8 * time.Second}

func okApplicationKey() string {
	return strings.TrimSpace(firstNonEmpty(
		os.Getenv("OK_APP_KEY"),
		os.Getenv("OK_APPLICATION_KEY"),
		os.Getenv("OK_APP_ID"),
	))
}

func okApplicationSecret() string {
	return strings.TrimSpace(firstNonEmpty(
		os.Getenv("OK_APP_SECRET"),
		os.Getenv("OK_APPLICATION_SECRET_KEY"),
		os.Getenv("OK_SECRET"),
	))
}

func okMD5(value string) string {
	sum := md5.Sum([]byte(value))
	return strings.ToLower(hex.EncodeToString(sum[:]))
}

// OK signs a session call without the access_token parameter. The session
// secret is MD5(access_token + application_secret_key); all other parameters
// are sorted and concatenated as key=value, then the session secret is
// appended and the whole string is hashed again.
func okSignature(params map[string]string, accessToken, appSecret string) string {
	sessionSecret := okMD5(accessToken + appSecret)
	keys := make([]string, 0, len(params))
	for key := range params {
		if key == "access_token" || key == "session_key" || key == "sig" {
			continue
		}
		keys = append(keys, key)
	}
	sort.Strings(keys)
	var builder strings.Builder
	for _, key := range keys {
		builder.WriteString(key)
		builder.WriteString("=")
		builder.WriteString(params[key])
	}
	builder.WriteString(sessionSecret)
	return okMD5(builder.String())
}

func okScalarString(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	case json.Number:
		return typed.String()
	case float64:
		return strconv.FormatInt(int64(typed), 10)
	case bool:
		return strconv.FormatBool(typed)
	default:
		return ""
	}
}

func okScalarInt(value any) int {
	switch typed := value.(type) {
	case json.Number:
		number, _ := typed.Int64()
		return int(number)
	case float64:
		return int(typed)
	case string:
		number, _ := strconv.Atoi(typed)
		return number
	default:
		return 0
	}
}

func fetchOKUser(ctx context.Context, accessToken string) (okUser, error) {
	appKey := okApplicationKey()
	appSecret := okApplicationSecret()
	if appKey == "" || appSecret == "" {
		return okUser{}, errOKNotConfigured
	}
	params := map[string]string{
		"application_key": appKey,
		"format":          "json",
		"method":          "users.getCurrentUser",
	}
	query := url.Values{}
	for key, value := range params {
		query.Set(key, value)
	}
	query.Set("access_token", accessToken)
	query.Set("sig", okSignature(params, accessToken, appSecret))
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, okAPIURL+"?"+query.Encode(), nil)
	if err != nil {
		return okUser{}, err
	}
	response, err := okHTTPClient.Do(request)
	if err != nil {
		return okUser{}, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return okUser{}, fmt.Errorf("ok api status %d", response.StatusCode)
	}
	var raw map[string]any
	if err := json.NewDecoder(response.Body).Decode(&raw); err != nil {
		return okUser{}, err
	}
	if message := strings.TrimSpace(okScalarString(raw["error_msg"])); message != "" {
		return okUser{}, fmt.Errorf("ok api: %s", message)
	}
	if code := okScalarInt(raw["error_code"]); code != 0 {
		return okUser{}, fmt.Errorf("ok api error %d", code)
	}
	user := okUser{
		UID:       strings.TrimSpace(okScalarString(raw["uid"])),
		FirstName: strings.TrimSpace(okScalarString(raw["first_name"])),
		LastName:  strings.TrimSpace(okScalarString(raw["last_name"])),
		Name:      strings.TrimSpace(okScalarString(raw["name"])),
		Pic1:      strings.TrimSpace(okScalarString(raw["pic_1"])),
		Pic2:      strings.TrimSpace(okScalarString(raw["pic_2"])),
		Pic3:      strings.TrimSpace(okScalarString(raw["pic_3"])),
	}
	if user.UID == "" {
		return okUser{}, errors.New("ok api: empty uid")
	}
	return user, nil
}

func (service *api) handleOKAuth(w http.ResponseWriter, r *http.Request) {
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
	var request okAuthRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, vkAuthResponse{Error: "invalid_ok_token"})
		return
	}
	accessToken := strings.TrimSpace(firstNonEmpty(request.LocalAccessToken, request.AccessToken))
	if accessToken == "" {
		// VKWebAppGetUserInfo is available in OK without permissions. It gives
		// the OK UID and display name, which is enough for a separate OK
		// profile; no OK API key is required for this path.
		externalID := strings.TrimSpace(request.OKUserID)
		if externalID == "" {
			writeJSON(w, http.StatusBadRequest, vkAuthResponse{Error: "invalid_ok_token"})
			return
		}
		if _, err := strconv.ParseInt(externalID, 10, 64); err != nil {
			writeJSON(w, http.StatusBadRequest, vkAuthResponse{Error: "invalid_ok_user"})
			return
		}
		profile, err := service.upsertOKProfile(r.Context(), externalID, normalizeVKDisplayName(request.Name))
		if err != nil {
			log.Printf("ok auth identity profile: %v", err)
			writeJSON(w, http.StatusInternalServerError, vkAuthResponse{Error: "Internal server error"})
			return
		}
		log.Printf("[OK] bridge identity uid=%s", externalID)
		writeJSON(w, http.StatusOK, authProfileResponse(profile))
		return
	}
	user, err := fetchOKUser(r.Context(), accessToken)
	if errors.Is(err, errOKNotConfigured) {
		log.Printf("ok auth: OK_APP_KEY/OK_APP_SECRET are not configured")
		writeJSON(w, http.StatusServiceUnavailable, vkAuthResponse{Error: "ok_auth_not_configured"})
		return
	}
	if err != nil {
		log.Printf("ok auth rejected: %v", err)
		writeJSON(w, http.StatusUnauthorized, vkAuthResponse{Error: "invalid_ok_auth"})
		return
	}
	displayName := normalizeVKDisplayName(firstNonEmpty(
		strings.TrimSpace(user.FirstName+" "+user.LastName),
		user.Name,
	))
	profile, err := service.upsertOKProfile(r.Context(), user.UID, displayName)
	if err != nil {
		log.Printf("ok auth profile: %v", err)
		writeJSON(w, http.StatusInternalServerError, vkAuthResponse{Error: "Internal server error"})
		return
	}
	writeJSON(w, http.StatusOK, authProfileResponse(profile))
}
