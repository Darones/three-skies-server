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

	request := httptest.NewRequest(http.MethodPost, "/admin/moderation/players/7/action?token=s3cret", strings.NewReader(`{"action":"warn"}`))
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	service.handleModerationPlayerAction(recorder, request)
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for a report-only action, got %d", recorder.Code)
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
