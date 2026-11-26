package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestAdminTokenValid(t *testing.T) {
	t.Setenv("ADMIN_TOKEN", "s3cret")
	if !adminTokenValid("s3cret") {
		t.Fatal("expected the configured token to be accepted")
	}
	if adminTokenValid("wrong") {
		t.Fatal("expected a wrong token to be rejected")
	}
	if adminTokenValid("") {
		t.Fatal("expected an empty token to be rejected")
	}
}

func TestModerationPageRequiresToken(t *testing.T) {
	t.Setenv("ADMIN_TOKEN", "s3cret")

	service := &api{}
	recorder := httptest.NewRecorder()
	service.handleModerationPage(recorder, httptest.NewRequest(http.MethodGet, "/admin/moderation?token=nope", nil))
	if recorder.Code != http.StatusForbidden {
		t.Fatalf("expected 403 without a valid token, got %d", recorder.Code)
	}

	recorder = httptest.NewRecorder()
	service.handleModerationPage(recorder, httptest.NewRequest(http.MethodGet, "/admin/moderation?token=s3cret", nil))
	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200 with a valid token, got %d", recorder.Code)
	}
	if contentType := recorder.Header().Get("Content-Type"); !strings.HasPrefix(contentType, "text/html") {
		t.Fatalf("expected an HTML page, got %q", contentType)
	}
	if !strings.Contains(recorder.Body.String(), "Модерация ников") {
		t.Fatal("page does not look like the moderation page")
	}
	if strings.Contains(recorder.Body.String(), "s3cret") {
		t.Fatal("the admin token must not be embedded into the page")
	}

	recorder = httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/admin/moderation", nil)
	request.Header.Set("X-Admin-Token", "s3cret")
	service.handleModerationPage(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("expected the header token to be accepted, got %d", recorder.Code)
	}
}

func TestModerationPageRejectsPost(t *testing.T) {
	t.Setenv("ADMIN_TOKEN", "s3cret")
	service := &api{}
	recorder := httptest.NewRecorder()
	service.handleModerationPage(recorder, httptest.NewRequest(http.MethodPost, "/admin/moderation?token=s3cret", nil))
	if recorder.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", recorder.Code)
	}
}

func TestModerationReportsAndPlayersRejectBadToken(t *testing.T) {
	t.Setenv("ADMIN_TOKEN", "s3cret")
	service := &api{}

	for _, handler := range []http.HandlerFunc{service.handleModerationReports, service.handleModerationPlayers} {
		recorder := httptest.NewRecorder()
		handler(recorder, httptest.NewRequest(http.MethodGet, "/admin/moderation/x?token=nope", nil))
		if recorder.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d", recorder.Code)
		}
		var body map[string]any
		if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
			t.Fatalf("decode forbidden body: %v", err)
		}
		if body["error"] != "Forbidden" {
			t.Fatalf("unexpected forbidden body: %v", body)
		}
	}
}

func TestModerationReadEndpointsWithoutDatabase(t *testing.T) {
	t.Setenv("ADMIN_TOKEN", "s3cret")
	service := &api{}

	recorder := httptest.NewRecorder()
	service.handleModerationReports(recorder, httptest.NewRequest(http.MethodGet, "/admin/moderation/reports?token=s3cret", nil))
	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 without a database, got %d", recorder.Code)
	}

	recorder = httptest.NewRecorder()
	service.handleModerationReports(recorder, httptest.NewRequest(http.MethodGet, "/admin/moderation/reports?token=s3cret&status=nonsense", nil))
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for an unknown status filter, got %d", recorder.Code)
	}

	recorder = httptest.NewRecorder()
	service.handleModerationPlayers(recorder, httptest.NewRequest(http.MethodGet, "/admin/moderation/players?token=s3cret&q=abc", nil))
	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 without a database, got %d", recorder.Code)
	}
}

func TestModerationResolveValidationWithoutDatabase(t *testing.T) {
	t.Setenv("ADMIN_TOKEN", "s3cret")
	service := &api{}

	post := func(path, body string) *httptest.ResponseRecorder {
		request := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
		request.Header.Set("Content-Type", "application/json")
		recorder := httptest.NewRecorder()
		service.handleModerationResolve(recorder, request)
		return recorder
	}

	if recorder := post("/admin/moderation/reports/abc/resolve?token=s3cret", `{"action":"dismiss"}`); recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for a bad report id, got %d", recorder.Code)
	}
	if recorder := post("/admin/moderation/reports/5/resolve?token=s3cret", `{"action":"explode"}`); recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for an unknown action, got %d", recorder.Code)
	}
	if recorder := post("/admin/moderation/reports/5/resolve?token=s3cret", `{"action":"dismiss"}`); recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 without a database, got %d", recorder.Code)
	}
	if recorder := post("/admin/moderation/reports/5/resolve?token=nope", `{"action":"dismiss"}`); recorder.Code != http.StatusForbidden {
		t.Fatalf("expected 403 without a token, got %d", recorder.Code)
	}
}

func TestModerationPlayerActionValidation(t *testing.T) {
	t.Setenv("ADMIN_TOKEN", "s3cret")
	service := &api{}

	request := httptest.NewRequest(http.MethodPost, "/admin/moderation/players/7/action?token=s3cret", strings.NewReader(`{"action":"dismiss"}`))
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	service.handleModerationPlayerAction(recorder, request)
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for a report-only action, got %d", recorder.Code)
	}

	// warn is now a first-class player action (it increments the counter).
	request = httptest.NewRequest(http.MethodPost, "/admin/moderation/players/7/action?token=s3cret", strings.NewReader(`{"action":"warn","reason":"Спам"}`))
	request.Header.Set("Content-Type", "application/json")
	recorder = httptest.NewRecorder()
	service.handleModerationPlayerAction(recorder, request)
	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 without a database for warn, got %d", recorder.Code)
	}

	request = httptest.NewRequest(http.MethodPost, "/admin/moderation/players/7/action?token=s3cret", strings.NewReader(`{"action":"unban"}`))
	request.Header.Set("Content-Type", "application/json")
	recorder = httptest.NewRecorder()
	service.handleModerationPlayerAction(recorder, request)
	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 without a database, got %d", recorder.Code)
	}
}

func TestParseModerationPath(t *testing.T) {
	cases := []struct {
		path   string
		prefix string
		suffix string
		want   int64
		ok     bool
	}{
		{"/admin/moderation/reports/42/resolve", "/admin/moderation/reports/", "/resolve", 42, true},
		{"/admin/moderation/reports/42/resolve/", "/admin/moderation/reports/", "/resolve", 42, true},
		{"/admin/moderation/reports/0/resolve", "/admin/moderation/reports/", "/resolve", 0, false},
		{"/admin/moderation/reports/-3/resolve", "/admin/moderation/reports/", "/resolve", 0, false},
		{"/admin/moderation/reports/abc/resolve", "/admin/moderation/reports/", "/resolve", 0, false},
		{"/admin/moderation/reports/1/2/resolve", "/admin/moderation/reports/", "/resolve", 0, false},
		{"/admin/moderation/players/9/action", "/admin/moderation/players/", "/action", 9, true},
	}
	for _, testCase := range cases {
		got, ok := parseModerationPath(testCase.path, testCase.prefix, testCase.suffix)
		if got != testCase.want || ok != testCase.ok {
			t.Fatalf("%s: got (%d,%v), want (%d,%v)", testCase.path, got, ok, testCase.want, testCase.ok)
		}
	}
}

func TestParseModerationPagination(t *testing.T) {
	cases := []struct {
		rawLimit  string
		rawOffset string
		wantLimit int
		wantOff   int
	}{
		{"", "", 100, 0},
		{"25", "10", 25, 10},
		{" 42 ", " 3 ", 42, 3},
		{"0", "0", 100, 0},
		{"-5", "-7", 100, 0},
		{"501", "5", 500, 5},
		{"abc", "xyz", 100, 0},
		{"1.5", "2.5", 100, 0},
		{"100000000000000000000", "100000000000000000000", 100, 0},
		{"100", "", 100, 0},
	}
	for _, testCase := range cases {
		limit, offset := parseModerationPagination(testCase.rawLimit, testCase.rawOffset)
		if limit != testCase.wantLimit || offset != testCase.wantOff {
			t.Fatalf("limit=%q offset=%q: got (%d,%d), want (%d,%d)",
				testCase.rawLimit, testCase.rawOffset, limit, offset, testCase.wantLimit, testCase.wantOff)
		}
	}
}

func TestParseModerationAll(t *testing.T) {
	for _, raw := range []string{"1", "true", "TRUE", " yes ", "on"} {
		if !parseModerationAll(raw) {
			t.Fatalf("%q should enable all players", raw)
		}
	}
	for _, raw := range []string{"", "0", "false", "no", "abc", "2"} {
		if parseModerationAll(raw) {
			t.Fatalf("%q should not enable all players", raw)
		}
	}
}

func TestCharacterTotalXP(t *testing.T) {
	expectedMax := 0
	for level := 1; level < maxCharacterLevel; level++ {
		expectedMax += level * 1000
	}
	if expectedMax != maxCharacterTotalXP {
		t.Fatalf("maxCharacterTotalXP=%d, curve sum=%d", maxCharacterTotalXP, expectedMax)
	}
	cases := []struct {
		level int
		xp    int
		want  int
	}{
		{1, 0, 0},
		{1, 500, 500},
		{2, 0, 1000},
		{2, 500, 1500},
		{10, 0, 45000},
		{14, 13999, 104999},
		{15, 0, maxCharacterTotalXP},
		{15, 500, maxCharacterTotalXP},
		{0, 0, 0},
		{2, -50, 1000},
	}
	for _, testCase := range cases {
		if got := characterTotalXP(testCase.level, testCase.xp); got != testCase.want {
			t.Fatalf("level=%d xp=%d: got %d, want %d", testCase.level, testCase.xp, got, testCase.want)
		}
	}
}

func TestApplyCharacterXPDelta(t *testing.T) {
	cases := []struct {
		level     int
		xp        int
		delta     int
		wantLevel int
		wantXP    int
		wantTotal int
	}{
		{1, 0, 500, 1, 500, 500},
		{1, 0, 999, 1, 999, 999},
		{1, 999, 1, 2, 0, 1000},
		{1, 0, 1000, 2, 0, 1000},
		{2, 500, -600, 1, 900, 900},
		{2, 500, -100, 2, 400, 1400},
		{3, 500, -999999, 1, 0, 0},
		{14, 13999, 1, 15, 0, 105000}, // the last point of the curve fills level 15 exactly
		{15, 0, -1, 14, 13999, 104999},
		{15, 0, 1000, 15, 0, 105000},
		{10, 0, -5000, 9, 4000, 40000},
		{1, 0, 0, 1, 0, 0},
		{1, 0, -1, 1, 0, 0},
		{1, 0, 1000000000, 15, 0, 105000},
		{15, 0, -1000000000, 1, 0, 0},
	}
	for _, testCase := range cases {
		level, xp, total := applyCharacterXPDelta(testCase.level, testCase.xp, testCase.delta)
		if level != testCase.wantLevel || xp != testCase.wantXP || total != testCase.wantTotal {
			t.Fatalf("level=%d xp=%d delta=%d: got (%d,%d,%d), want (%d,%d,%d)",
				testCase.level, testCase.xp, testCase.delta,
				level, xp, total,
				testCase.wantLevel, testCase.wantXP, testCase.wantTotal)
		}
	}
}

func TestRemoveItemIDFromList(t *testing.T) {
	cases := []struct {
		value  string
		itemID int
		want   string
	}{
		{"1,2,3", 2, "1,3"},
		{"1,2", 9, "1,2"},
		{"", 1, ""},
		{"101,102", 101, "102"},
		{"1,1,2", 1, "2"},
		{" 1, 2 ,3", 3, "1,2"},
		{"abc,0,-1,2", 3, "2"},
		{"101,102", 102, "101"},
	}
	for _, testCase := range cases {
		if got := removeItemIDFromList(testCase.value, testCase.itemID); got != testCase.want {
			t.Fatalf("value=%q item=%d: got %q, want %q", testCase.value, testCase.itemID, got, testCase.want)
		}
	}
}

func TestAdminXPUpdateDoesNotTouchShards(t *testing.T) {
	lowered := strings.ToLower(adminCharacterXPUpdateQuery)
	if strings.Contains(lowered, "sky_shards") {
		t.Fatal("admin XP update must not change sky_shards")
	}
	for _, want := range []string{"char_levels", "char_xps"} {
		if !strings.Contains(lowered, want) {
			t.Fatalf("admin XP update does not contain %q", want)
		}
	}
}

func TestModerationProgressResponseKeepsZeroValues(t *testing.T) {
	zero := 0
	payload, err := json.Marshal(moderationActionResponse{
		Success:         true,
		Level:           &zero,
		XP:              &zero,
		TotalXP:         &zero,
		UnlockedWeapons: "",
	})
	if err != nil {
		t.Fatalf("marshal response: %v", err)
	}
	body := string(payload)
	for _, want := range []string{`"level":0`, `"xp":0`, `"total_xp":0`, `"unlocked_weapons":""`} {
		if !strings.Contains(body, want) {
			t.Fatalf("response %s does not contain %s", body, want)
		}
	}
}

func TestModerationProgressActionValidation(t *testing.T) {
	t.Setenv("ADMIN_TOKEN", "s3cret")
	service := &api{}
	post := func(body string) *httptest.ResponseRecorder {
		request := httptest.NewRequest(http.MethodPost, "/admin/moderation/players/7/action?token=s3cret", strings.NewReader(body))
		request.Header.Set("Content-Type", "application/json")
		recorder := httptest.NewRecorder()
		service.handleModerationPlayerAction(recorder, request)
		return recorder
	}

	if recorder := post(`{"action":"grant_xp","character":"rogue","amount":100}`); recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for an unknown character, got %d", recorder.Code)
	}
	if recorder := post(`{"action":"remove_weapon","item_id":0}`); recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for an invalid item id, got %d", recorder.Code)
	}
	// Valid payloads reach the database, which is nil in this unit test.
	if recorder := post(`{"action":"grant_xp","character":"warrior","amount":-100}`); recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 without a database for grant_xp, got %d", recorder.Code)
	}
	if recorder := post(`{"action":"remove_weapon","item_id":101}`); recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 without a database for remove_weapon, got %d", recorder.Code)
	}
	if recorder := post(`{"action":"clear_weapons"}`); recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 without a database for clear_weapons, got %d", recorder.Code)
	}
}

func TestModerationPageHasPlayerAdminControls(t *testing.T) {
	t.Setenv("ADMIN_TOKEN", "s3cret")
	service := &api{}
	recorder := httptest.NewRecorder()
	service.handleModerationPage(recorder, httptest.NewRequest(http.MethodGet, "/admin/moderation?token=s3cret", nil))
	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", recorder.Code)
	}
	body := recorder.Body.String()
	for _, want := range []string{
		"Все игроки",
		"Показано",
		"Осколки",
		"Опыт",
		"Прогресс/инвентарь",
		"grant_shards",
		"data-grant-shards",
		"data-grant-xp",
		"grant_xp",
		"remove_weapon",
		"clear_weapons",
		"Забрать всё оружие и скины",
		"X-Admin-Token",
		"offset",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("moderation page does not contain %q", want)
		}
	}
	lower := strings.ToLower(body)
	for _, unwanted := range []string{"unlocked_wings", "remove_wing", "clear_wings", "крыл"} {
		if strings.Contains(lower, unwanted) {
			t.Fatalf("moderation page still mentions wings: %q", unwanted)
		}
	}
	for _, external := range []string{"http://", "https://"} {
		if strings.Contains(body, external) {
			t.Fatalf("moderation page loads an external resource: %q", external)
		}
	}
}

func TestPlayerModerationActionSet(t *testing.T) {
	for _, action := range []string{"ban", "unban", "warn", "hide_nickname", "unhide_nickname", "grant_xp", "remove_weapon", "clear_weapons"} {
		if !playerModerationActions[action] {
			t.Fatalf("action %q is missing from playerModerationActions", action)
		}
	}
	// Wings were removed from the game; the admin API must not expose them.
	for _, action := range []string{"remove_wing", "clear_wings"} {
		if playerModerationActions[action] {
			t.Fatalf("action %q must not be accepted", action)
		}
	}
}

func TestModerationPlayersQueryHasAdminFields(t *testing.T) {
	for _, want := range []string{
		"COALESCE(p.sky_shards, 0)",
		"COALESCE(p.level, 1)",
		"COALESCE(p.unlocked_weapons, '')",
		"COALESCE(p.char_levels::text, '')",
		"COALESCE(p.char_xps::text, '')",
		"COUNT(*) OVER()",
		"$2::boolean",
		"LIMIT $3 OFFSET $4",
	} {
		if !strings.Contains(moderationPlayersQuery, want) {
			t.Fatalf("players query does not contain %q", want)
		}
	}
}

func TestModerationRoutesAreWired(t *testing.T) {
	t.Setenv("ADMIN_TOKEN", "s3cret")
	service := &api{}
	router := newRouter(service, newWebSocketHub(nil))

	check := func(method, path, body string, want int) {
		var reader *strings.Reader
		if body == "" {
			reader = strings.NewReader("")
		} else {
			reader = strings.NewReader(body)
		}
		request := httptest.NewRequest(method, path, reader)
		if body != "" {
			request.Header.Set("Content-Type", "application/json")
		}
		recorder := httptest.NewRecorder()
		router.ServeHTTP(recorder, request)
		if recorder.Code != want {
			t.Fatalf("%s %s: got %d, want %d (%s)", method, path, recorder.Code, want, recorder.Body.String())
		}
	}

	check(http.MethodGet, "/admin/moderation?token=s3cret", "", http.StatusOK)
	check(http.MethodGet, "/admin/moderation/reports?token=s3cret", "", http.StatusServiceUnavailable)
	check(http.MethodGet, "/admin/moderation/players?token=s3cret&q=a", "", http.StatusServiceUnavailable)
	check(http.MethodPost, "/admin/moderation/reports/3/resolve?token=s3cret", `{"action":"dismiss"}`, http.StatusServiceUnavailable)
	check(http.MethodPost, "/admin/moderation/players/3/action?token=s3cret", `{"action":"unban"}`, http.StatusServiceUnavailable)
}
