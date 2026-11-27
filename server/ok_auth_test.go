package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestOKStrictAuthFlag(t *testing.T) {
	tests := []struct {
		value string
		want  bool
	}{
		{"", false},
		{"1", true},
		{"true", true},
		{"TRUE", true},
		{"yes", true},
		{"Yes", true},
		{"on", true},
		{" on ", true},
		{"0", false},
		{"false", false},
		{"no", false},
		{"off", false},
	}
	for _, test := range tests {
		test := test
		t.Run(test.value, func(t *testing.T) {
			t.Setenv("OK_STRICT_AUTH", test.value)
			if got := okStrictAuth(); got != test.want {
				t.Fatalf("okStrictAuth()=%v for %q, want %v", got, test.value, test.want)
			}
		})
	}
}

func TestOKAuthRejectsUIDWhenStrict(t *testing.T) {
	t.Setenv("OK_STRICT_AUTH", "1")
	body, err := json.Marshal(map[string]string{
		"ok_user_id": "123",
		"name":       "X",
	})
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	request := httptest.NewRequest(http.MethodPost, "/auth/ok", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	// No database is configured: reaching upsertOKProfile would fail/panic, so
	// a clean 401 also proves the strict gate fires before any profile write.
	(&api{}).handleOKAuth(recorder, request)
	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d, want 401; body=%s", recorder.Code, recorder.Body.String())
	}
	var response map[string]any
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if got, _ := response["error"].(string); got != "invalid_ok_auth" {
		t.Fatalf("error=%q, want %q", got, "invalid_ok_auth")
	}
}

// TestOKAuthStrictGateBeforeUpsert keeps the ordering honest without a
// database: the legacy branch must check the flag before the identity upsert.
func TestOKAuthStrictGateBeforeUpsert(t *testing.T) {
	raw, err := os.ReadFile("ok_auth.go")
	if err != nil {
		t.Fatalf("read ok_auth.go: %v", err)
	}
	source := string(raw)
	branch := strings.Index(source, `if accessToken == "" {`)
	if branch < 0 {
		t.Fatal("legacy accessToken branch not found")
	}
	rest := source[branch:]
	end := strings.Index(rest, "user, err := fetchOKUser")
	if end < 0 {
		t.Fatal("token branch not found after the legacy branch")
	}
	legacy := rest[:end]
	gate := strings.Index(legacy, "if okStrictAuth() {")
	if gate < 0 {
		t.Fatal("okStrictAuth() gate is missing from the legacy branch")
	}
	upsert := strings.Index(legacy, "service.upsertOKProfile(r.Context(), externalID")
	if upsert < 0 {
		t.Fatal("legacy identity upsert not found")
	}
	if gate > upsert {
		t.Fatal("okStrictAuth() gate must run before the identity upsert")
	}
}
