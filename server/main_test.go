package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthReportsDatabaseDown(t *testing.T) {
	service := &api{}
	service.setDatabaseError(errors.New("connection refused"))

	recorder := httptest.NewRecorder()
	service.handleHealth(recorder, httptest.NewRequest(http.MethodGet, "/health", nil))

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200 from health, got %d", recorder.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode health body: %v", err)
	}
	if body["status"] != "degraded" || body["database"] != "down" {
		t.Fatalf("unexpected health body: %v", body)
	}
	if body["database_error"] != "connection refused" {
		t.Fatalf("expected database error in health body, got %v", body["database_error"])
	}
}

func TestHealthReportsDatabaseUp(t *testing.T) {
	service := &api{}
	service.setDatabaseReady()

	recorder := httptest.NewRecorder()
	service.handleHealth(recorder, httptest.NewRequest(http.MethodGet, "/health", nil))

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200 from health, got %d", recorder.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode health body: %v", err)
	}
	if body["status"] != "ok" || body["database"] != "ok" {
		t.Fatalf("unexpected health body: %v", body)
	}
}

func TestDataEndpointsReturn503WithoutDatabase(t *testing.T) {
	service := &api{}
	service.setDatabaseError(errors.New("connection refused"))
	router := newRouter(service, newWebSocketHub(nil))

	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/profile?player_id=1", nil))

	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 while the database is down, got %d", recorder.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode 503 body: %v", err)
	}
	if body["success"] != false {
		t.Fatalf("expected success=false, got %v", body["success"])
	}
}

func TestHealthStaysAvailableWithoutDatabase(t *testing.T) {
	service := &api{}
	service.setDatabaseError(errors.New("connection refused"))
	router := newRouter(service, newWebSocketHub(nil))

	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/health", nil))

	if recorder.Code != http.StatusOK {
		t.Fatalf("health must stay reachable, got %d", recorder.Code)
	}
}

func TestNormalizeDatabaseURL(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"empty", "", ""},
		{"plain url", "postgres://u:p@db:5432/name", "postgres://u:p@db:5432/name?sslmode=disable"},
		{"existing query", "postgres://u:p@db:5432/name?connect_timeout=5", "postgres://u:p@db:5432/name?connect_timeout=5&sslmode=disable"},
		{"explicit sslmode", "postgres://u:p@db:5432/name?sslmode=require", "postgres://u:p@db:5432/name?sslmode=require"},
		{"keyword dsn", "host=db port=5432 user=u dbname=n", "host=db port=5432 user=u dbname=n sslmode=disable"},
	}
	for _, testCase := range cases {
		if got := normalizeDatabaseURL(testCase.in); got != testCase.want {
			t.Fatalf("%s: got %q, want %q", testCase.name, got, testCase.want)
		}
	}
}

func TestDatabaseHost(t *testing.T) {
	if got := databaseHost("postgres://u:p@db-team-example:5432/base?sslmode=disable"); got != "db-team-example" {
		t.Fatalf("unexpected host: %q", got)
	}
	if got := databaseHost("host=localhost port=5432 user=u dbname=n"); got != "localhost" {
		t.Fatalf("unexpected keyword host: %q", got)
	}
	if got := databaseHost(""); got != "" {
		t.Fatalf("empty url must give empty host, got %q", got)
	}
}

func TestHealthShowsDatabaseHost(t *testing.T) {
	service := &api{dbHost: "localhost"}
	service.setDatabaseError(errors.New("connection refused"))

	recorder := httptest.NewRecorder()
	service.handleHealth(recorder, httptest.NewRequest(http.MethodGet, "/health", nil))

	var body map[string]any
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode health body: %v", err)
	}
	if body["database_host"] != "localhost" {
		t.Fatalf("expected database_host in health, got %v", body["database_host"])
	}
}
