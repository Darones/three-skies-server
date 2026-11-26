package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"
)

func vkTestParams() map[string]string {
	return map[string]string{
		"vk_app_id":   defaultVKAppID,
		"vk_user_id":  "123",
		"vk_ts":       "1700000000",
		"vk_language": "ru",
		"vk_platform": "desktop_web",
	}
}

func TestVKSignKnownVector(t *testing.T) {
	params := map[string]string{
		"vk_user_id":                   "494075",
		"vk_app_id":                    "6736218",
		"vk_is_app_user":               "1",
		"vk_are_notifications_enabled": "1",
		"vk_language":                  "ru",
		"vk_access_token_settings":     "",
		"vk_platform":                  "android",
	}
	const want = "htQFduJpLxz7ribXRZpDFUH-XEUhC9rBPTJkjUFEkRA"
	if got := vkSign(params, "wvl68m4dR1UpLrVRli"); got != want {
		t.Fatalf("vkSign=%q, want %q", got, want)
	}
}

func TestVKLegacySignKnownVector(t *testing.T) {
	params := map[string]string{
		"vk_app_id":  "54906713",
		"vk_ts":      "1700000000",
		"vk_user_id": "123",
	}
	const want = "7d6b4f8581a8f85b4259b56059f352fd"
	if got := vkLegacySign(params, "test_secret"); got != want {
		t.Fatalf("vkLegacySign=%q, want %q", got, want)
	}
}

func TestVerifyVKLaunchParamsValid(t *testing.T) {
	t.Setenv("VK_APP_SECRET", "test_secret")
	params := vkTestParams()
	params["sign"] = vkSign(params, "test_secret")
	now := time.Unix(1700000100, 0)
	if err := verifyVKLaunchParams(params, defaultVKAppID, vkAppSecret(), now); err != nil {
		t.Fatalf("valid launch params rejected: %v", err)
	}
}

func TestVerifyVKLaunchParamsAcceptsLegacyMD5(t *testing.T) {
	t.Setenv("VK_APP_SECRET", "test_secret")
	params := vkTestParams()
	params["sign"] = vkLegacySign(params, "test_secret")
	if err := verifyVKLaunchParams(params, defaultVKAppID, vkAppSecret(), time.Unix(1700000100, 0)); err != nil {
		t.Fatalf("legacy MD5 launch params rejected: %v", err)
	}
}

func TestVerifyVKLaunchParamsForgedSignature(t *testing.T) {
	params := vkTestParams()
	params["sign"] = "00000000000000000000000000000000"
	err := verifyVKLaunchParams(params, defaultVKAppID, "test_secret", time.Unix(1700000100, 0))
	if err != errVKSignature {
		t.Fatalf("forged signature error=%v, want %v", err, errVKSignature)
	}
}

func TestVerifyVKLaunchParamsExpiredTimestamp(t *testing.T) {
	params := vkTestParams()
	params["sign"] = vkSign(params, "test_secret")
	err := verifyVKLaunchParams(params, defaultVKAppID, "test_secret", time.Unix(1700000000+vkAuthMaxAge+1, 0))
	if err != errVKTimestamp {
		t.Fatalf("expired timestamp error=%v, want %v", err, errVKTimestamp)
	}
}

func TestVerifyVKLaunchParamsWrongAppID(t *testing.T) {
	params := vkTestParams()
	params["vk_app_id"] = "11111111"
	params["sign"] = vkSign(params, "test_secret")
	err := verifyVKLaunchParams(params, defaultVKAppID, "test_secret", time.Unix(1700000100, 0))
	if err != errVKAppID {
		t.Fatalf("wrong app id error=%v, want %v", err, errVKAppID)
	}
}

func TestVerifyVKLaunchParamsMissingSign(t *testing.T) {
	params := vkTestParams()
	err := verifyVKLaunchParams(params, defaultVKAppID, "test_secret", time.Unix(1700000100, 0))
	if err != errVKMissingSign {
		t.Fatalf("missing sign error=%v, want %v", err, errVKMissingSign)
	}
}

func TestNormalizeVKDisplayName(t *testing.T) {
	if got := normalizeVKDisplayName("  Иван Петров  "); got != "Иван Петров" {
		t.Fatalf("normalize name=%q", got)
	}
	long := "abcdefghijklmnopqrstuvwxyzabcdefghij"
	if got := normalizeVKDisplayName(long); len([]rune(got)) != 32 {
		t.Fatalf("long name should be truncated to 32 runes, got %d", len([]rune(got)))
	}
}

func TestPlatformRenameDecision(t *testing.T) {
	tests := []struct {
		name         string
		oldNickname  string
		newDisplay   string
		hidden       bool
		custom       bool
		wantNickname string
		wantUnhide   bool
	}{
		{
			name:         "changed name unhides a hidden nickname",
			oldNickname:  "Старый",
			newDisplay:   "Новый",
			hidden:       true,
			wantNickname: "Новый",
			wantUnhide:   true,
		},
		{
			name:         "changed name keeps a visible profile visible",
			oldNickname:  "Старый",
			newDisplay:   "Новый",
			hidden:       false,
			wantNickname: "Новый",
			wantUnhide:   false,
		},
		{
			name:         "same name keeps the hidden flag",
			oldNickname:  "Иван",
			newDisplay:   "Иван",
			hidden:       true,
			wantNickname: "Иван",
			wantUnhide:   false,
		},
		{
			name:         "surrounding spaces do not count as a rename",
			oldNickname:  "Иван",
			newDisplay:   "  Иван  ",
			hidden:       true,
			wantNickname: "Иван",
			wantUnhide:   false,
		},
		{
			name:         "custom nickname ignores the platform name",
			oldNickname:  "Свой",
			newDisplay:   "Новое",
			hidden:       true,
			custom:       true,
			wantNickname: "Свой",
			wantUnhide:   false,
		},
		{
			name:         "empty platform name changes nothing",
			oldNickname:  "Иван",
			newDisplay:   "",
			hidden:       true,
			wantNickname: "Иван",
			wantUnhide:   false,
		},
		{
			name:         "whitespace platform name changes nothing",
			oldNickname:  "Иван",
			newDisplay:   "   ",
			hidden:       true,
			wantNickname: "Иван",
			wantUnhide:   false,
		},
		{
			name:         "profane rename keeps the old hidden nickname",
			oldNickname:  "Иван",
			newDisplay:   "ебаный",
			hidden:       true,
			wantNickname: "Иван",
			wantUnhide:   false,
		},
		{
			name:         "profane rename does not change a visible profile",
			oldNickname:  "Иван",
			newDisplay:   "shit",
			hidden:       false,
			wantNickname: "Иван",
			wantUnhide:   false,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			nickname, unhide := platformRenameDecision(test.oldNickname, test.newDisplay, test.hidden, test.custom)
			if nickname != test.wantNickname {
				t.Fatalf("nickname=%q, want %q", nickname, test.wantNickname)
			}
			if unhide != test.wantUnhide {
				t.Fatalf("unhide=%v, want %v", unhide, test.wantUnhide)
			}
		})
	}
}

func TestAuthProfileResponseHidesNickname(t *testing.T) {
	hidden := authProfileResponse(vkProfileRow{
		nickname:       "НастоящийНик",
		nicknameCustom: true,
		nicknameHidden: true,
	})
	if hidden.Nickname != hiddenNickname {
		t.Fatalf("hidden nickname=%q, want %q", hidden.Nickname, hiddenNickname)
	}
	if hidden.Nickname != "Игрок" {
		t.Fatalf("hidden nickname=%q, want %q", hidden.Nickname, "Игрок")
	}
	if hidden.NicknameCustom {
		t.Fatal("a hidden nickname must not be reported as custom")
	}

	visible := authProfileResponse(vkProfileRow{
		nickname:       "НастоящийНик",
		nicknameCustom: true,
	})
	if visible.Nickname != "НастоящийНик" {
		t.Fatalf("visible nickname=%q, want %q", visible.Nickname, "НастоящийНик")
	}
	if !visible.NicknameCustom {
		t.Fatal("a visible custom nickname must stay custom")
	}
}

func TestSplitUnlockedItems(t *testing.T) {
	skins, weapons := splitUnlockedItems([]int{1, 5, 101, 102})
	if len(skins) != 2 || skins[0] != 101 || skins[1] != 102 {
		t.Fatalf("skins=%v", skins)
	}
	if len(weapons) != 2 || weapons[0] != 1 || weapons[1] != 5 {
		t.Fatalf("weapons=%v", weapons)
	}
}

func vkAuthRequest(t *testing.T, params map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	body, err := json.Marshal(params)
	if err != nil {
		t.Fatalf("marshal params: %v", err)
	}
	request := httptest.NewRequest(http.MethodPost, "/auth/vk", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	(&api{}).handleVKAuth(recorder, request)
	return recorder
}

func TestHandleVKAuthRejectsForgedSignature(t *testing.T) {
	t.Setenv("VK_APP_SECRET", "test_secret")
	params := vkTestParams()
	params["vk_ts"] = strconv.FormatInt(time.Now().Unix(), 10)
	params["sign"] = "00000000000000000000000000000000"
	recorder := vkAuthRequest(t, params)
	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d, want 401; body=%s", recorder.Code, recorder.Body.String())
	}
}

func TestHandleVKAuthRejectsExpiredTimestamp(t *testing.T) {
	t.Setenv("VK_APP_SECRET", "test_secret")
	params := vkTestParams()
	params["vk_ts"] = strconv.FormatInt(time.Now().Unix()-vkAuthMaxAge-10, 10)
	params["sign"] = vkSign(params, "test_secret")
	recorder := vkAuthRequest(t, params)
	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d, want 401; body=%s", recorder.Code, recorder.Body.String())
	}
}

func TestHandleVKAuthRejectsWrongAppID(t *testing.T) {
	t.Setenv("VK_APP_SECRET", "test_secret")
	params := vkTestParams()
	params["vk_app_id"] = "11111111"
	params["vk_ts"] = strconv.FormatInt(time.Now().Unix(), 10)
	params["sign"] = vkSign(params, "test_secret")
	recorder := vkAuthRequest(t, params)
	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d, want 401; body=%s", recorder.Code, recorder.Body.String())
	}
}

func TestVKRateLimiter(t *testing.T) {
	limiter := newVKRateLimiter(2, time.Minute)
	if !limiter.allow("1.2.3.4") || !limiter.allow("1.2.3.4") {
		t.Fatal("first two attempts should pass")
	}
	if limiter.allow("1.2.3.4") {
		t.Fatal("third attempt should be limited")
	}
	if !limiter.allow("5.6.7.8") {
		t.Fatal("another IP should not be limited")
	}
}
