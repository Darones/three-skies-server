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
