package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

func TestHiddenNicknameReplacement(t *testing.T) {
	if got := publicNickname("НастоящийНик", true); got != hiddenNickname {
		t.Fatalf("hidden nickname leaked: %q", got)
	}
	if got := publicNickname("НастоящийНик", false); got != "НастоящийНик" {
		t.Fatalf("visible nickname changed: %q", got)
	}
}

func TestVisibleJoinNameHidesTheOriginal(t *testing.T) {
	// The client may still send the original nickname in the join payload;
	// the hidden flag must win.
	hidden := playerMatchAccess{Nickname: "НастоящийНик", Hidden: true}
	if got := visibleJoinName("НастоящийНик", hidden, 7); got != hiddenNickname {
		t.Fatalf("join name leaked a hidden nickname: %q", got)
	}
	// A readable server profile overrides whatever the client sent.
	normal := playerMatchAccess{Nickname: "СерверныйНик"}
	if got := visibleJoinName("ЧужойНик", normal, 7); got != "СерверныйНик" {
		t.Fatalf("server nickname did not win: %q", got)
	}
	// A profile we could not read falls back to the requested name.
	if got := visibleJoinName("КлиентскийНик", playerMatchAccess{}, 7); got != "КлиентскийНик" {
		t.Fatalf("requested fallback lost: %q", got)
	}
	if got := visibleJoinName("", playerMatchAccess{}, 42); got != "Игрок 42" {
		t.Fatalf("empty name fallback = %q", got)
	}
	long := strings.Repeat("я", 40)
	if got := visibleJoinName(long, playerMatchAccess{}, 1); len([]rune(got)) != 32 {
		t.Fatalf("name was not truncated to 32 runes: %d", len([]rune(got)))
	}
}

func TestPlayerMatchAccessWithoutDatabase(t *testing.T) {
	hub := newWebSocketHub(nil)
	access := hub.playerMatchAccess(123)
	if access.Banned || access.Hidden || access.Nickname != "" || access.BanReason != "" {
		t.Fatalf("nil database must not invent moderation flags: %+v", access)
	}
}

func TestBannedAccountResponsesAreDistinguishable(t *testing.T) {
	service := &api{}

	profileRecorder := httptest.NewRecorder()
	service.writeBannedProfile(profileRecorder, "оскорбления")
	if profileRecorder.Code != http.StatusForbidden {
		t.Fatalf("profile ban status = %d, want 403", profileRecorder.Code)
	}
	var profile map[string]any
	if err := json.Unmarshal(profileRecorder.Body.Bytes(), &profile); err != nil {
		t.Fatalf("decode banned profile: %v", err)
	}
	if profile["success"] != false || profile["error"] != accountBannedError {
		t.Fatalf("banned profile must carry the ban code: %v", profile)
	}
	if profile["banned"] != true || profile["ban_reason"] != "оскорбления" {
		t.Fatalf("banned profile lost the flags: %v", profile)
	}
	if _, found := profile["session_token"]; found {
		t.Fatalf("banned profile must not return a token: %v", profile)
	}
	if _, found := profile["sky_shards"]; found {
		t.Fatalf("banned profile must not return game data: %v", profile)
	}

	sessionRecorder := httptest.NewRecorder()
	service.writeBannedSession(sessionRecorder, "оскорбления")
	if sessionRecorder.Code != http.StatusForbidden {
		t.Fatalf("session ban status = %d, want 403", sessionRecorder.Code)
	}
	var session map[string]any
	if err := json.Unmarshal(sessionRecorder.Body.Bytes(), &session); err != nil {
		t.Fatalf("decode banned session: %v", err)
	}
	if session["success"] != false || session["error"] != accountBannedError || session["banned"] != true {
		t.Fatalf("banned session response = %v", session)
	}
	if _, found := session["token"]; found {
		t.Fatalf("banned session must not return a token: %v", session)
	}
}

func TestWarningMigrationIsIdempotentAndPresent(t *testing.T) {
	needed := map[string]bool{
		"warnings INTEGER":            false,
		"last_warning_reason TEXT":    false,
		"last_warning_at TIMESTAMPTZ": false,
	}
	for _, statement := range playerColumnMigrations {
		if !strings.Contains(statement, "ADD COLUMN IF NOT EXISTS") {
			t.Fatalf("migration is not idempotent: %s", statement)
		}
		for fragment := range needed {
			if strings.Contains(statement, fragment) {
				needed[fragment] = true
			}
		}
	}
	for fragment, found := range needed {
		if !found {
			t.Fatalf("playerColumnMigrations is missing %q", fragment)
		}
	}

	raw, err := os.ReadFile("schema.sql")
	if err != nil {
		t.Fatalf("read schema.sql: %v", err)
	}
	schema := string(raw)
	for fragment := range needed {
		if !strings.Contains(schema, fragment) {
			t.Fatalf("schema.sql is missing %q", fragment)
		}
	}
	if !strings.Contains(schema, "ADD COLUMN IF NOT EXISTS warnings") {
		t.Fatal("schema.sql warning migration must use IF NOT EXISTS")
	}
}

func TestPlayerModerationActionsIncludeWarn(t *testing.T) {
	if !playerModerationActions["warn"] {
		t.Fatal("warn must be allowed as a direct player action")
	}
	if !moderationActions["warn"] {
		t.Fatal("warn must stay allowed on a report")
	}
}

func TestModerationActionReasonPrefersExplicitReason(t *testing.T) {
	if got := moderationActionReason(moderationActionRequest{Reason: "Спам", BanReason: "Читы"}); got != "Спам" {
		t.Fatalf("explicit reason lost: %q", got)
	}
	if got := moderationActionReason(moderationActionRequest{BanReason: "Читы"}); got != "Читы" {
		t.Fatalf("ban_reason fallback lost: %q", got)
	}
}

func TestModerationPageExposesWarnAction(t *testing.T) {
	for _, fragment := range []string{
		`data-player-act="warn"`,
		"Предупредить",
		"Причина предупреждения",
		"player.warnings",
	} {
		if !strings.Contains(moderationPageHTML, fragment) {
			t.Fatalf("moderation page is missing %q", fragment)
		}
	}
}

func TestMatchRewardClaimQueriesAreGuarded(t *testing.T) {
	queries := map[string]string{
		"base":  matchRewardBaseClaimQuery,
		"bonus": matchRewardBonusClaimQuery,
	}
	for name, query := range queries {
		if !strings.Contains(query, "FOR UPDATE") {
			t.Fatalf("%s reward claim is not locked: %s", name, query)
		}
		if !strings.Contains(query, "COALESCE(rewarded, FALSE)") {
			t.Fatalf("%s reward claim ignores the rewarded flag: %s", name, query)
		}
	}
	if !strings.Contains(matchRewardBonusClaimQuery, "COALESCE(rewarded_bonus, FALSE) = FALSE") {
		t.Fatalf("bonus claim is not separately idempotent: %s", matchRewardBonusClaimQuery)
	}
	if !strings.Contains(matchRewardBaseClaimQuery, "COALESCE(rewarded, FALSE) = FALSE") {
		t.Fatalf("base claim can pay a rewarded match twice: %s", matchRewardBaseClaimQuery)
	}
}

func TestProfileResponseCarriesModerationFields(t *testing.T) {
	raw, err := json.Marshal(playerProfileResponse{WarningCount: 2, LastWarningReason: "Спам"})
	if err != nil {
		t.Fatalf("marshal profile: %v", err)
	}
	body := string(raw)
	for _, field := range []string{`"warning_count":2`, `"last_warning_reason":"Спам"`, `"warning_count"`} {
		if !strings.Contains(body, field) {
			t.Fatalf("profile response is missing %s: %s", field, body)
		}
	}
	// banned=true is omitted only when false; a real ban must serialize it.
	raw, err = json.Marshal(playerProfileResponse{Banned: true, BanReason: "чит"})
	if err != nil {
		t.Fatalf("marshal banned profile: %v", err)
	}
	if !strings.Contains(string(raw), `"banned":true`) || !strings.Contains(string(raw), `"ban_reason":"чит"`) {
		t.Fatalf("banned profile lost its flags: %s", raw)
	}
}

func TestCompensationEndpointIsClosed(t *testing.T) {
	service := &api{}
	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/compensation", strings.NewReader(`{"player_id":1,"reason":"match_aborted"}`))
	request.Header.Set("Content-Type", "application/json")
	service.handleCompensation(recorder, request)

	if recorder.Code != http.StatusGone {
		t.Fatalf("compensation status = %d, want 410", recorder.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode compensation body: %v", err)
	}
	if body["error"] != "compensation_disabled" || body["success"] != false {
		t.Fatalf("unexpected compensation body: %v", body)
	}
	if _, found := body["new_shards"]; found {
		t.Fatalf("disabled compensation must not pay: %v", body)
	}
}

func TestCompensationRejectsGet(t *testing.T) {
	service := &api{}
	recorder := httptest.NewRecorder()
	service.handleCompensation(recorder, httptest.NewRequest(http.MethodGet, "/compensation", nil))
	if recorder.Code != http.StatusMethodNotAllowed {
		t.Fatalf("GET compensation status = %d, want 405", recorder.Code)
	}
}

func TestRoomIDSeedIsUniqueAcrossRestartsAndJSSafe(t *testing.T) {
	first := roomIDSeed(time.UnixMilli(1_800_000_000_000))
	second := roomIDSeed(time.UnixMilli(1_800_000_000_001))
	if first <= 0 || second <= 0 {
		t.Fatalf("room id seed must be positive: %d %d", first, second)
	}
	if first == second {
		t.Fatalf("restart seeds collide: %d", first)
	}
	const jsSafeMax = int64(1)<<53 - 1
	if first > jsSafeMax || second > jsSafeMax {
		t.Fatalf("room id exceeds the JS-safe integer range: %d %d", first, second)
	}
	// An old counter started at 1; a timestamp seed must be far above every
	// historical row so /match_reward cannot match it.
	if first < 1_000_000_000_000 {
		t.Fatalf("room id seed is too small: %d", first)
	}
	if got := roomIDSeed(time.Unix(0, 0)); got != 1 {
		t.Fatalf("zero seed fallback = %d, want 1", got)
	}
}

func TestMatchFinishedWaitsForACongestedSendBuffer(t *testing.T) {
	hub := newWebSocketHub(nil)
	client := &wsClient{
		id:       1,
		roomID:   1,
		team:     0,
		send:     make(chan []byte, 1),
		done:     make(chan struct{}),
		alive:    true,
		hasState: true,
	}
	room := &wsRoom{id: 1, state: "live", humanCount: 1, hostID: client.id}
	room.players[0] = client
	room.score = [2]int{1, 0}
	hub.rooms[1] = room

	// Fill the buffer: the non-critical match_score is dropped, while
	// match_finished must wait for the writer instead of disappearing.
	client.send <- []byte("filler")
	drained := make(chan struct{})
	go func() {
		time.Sleep(20 * time.Millisecond)
		<-client.send
		close(drained)
	}()

	hub.finishMatchByTimeout(1)
	<-drained

	var finished *wsOutgoing
	select {
	case data := <-client.send:
		var message wsOutgoing
		if err := json.Unmarshal(data, &message); err != nil {
			t.Fatalf("decode critical message: %v", err)
		}
		finished = &message
	case <-time.After(2 * time.Second):
		t.Fatal("match_finished was never queued")
	}
	if finished == nil || finished.Type != "match_finished" {
		t.Fatalf("expected match_finished, got %+v", finished)
	}
	if finished.RoomID != 1 || finished.WinningTeam != 0 {
		t.Fatalf("match_finished lost its result: %+v", finished)
	}
}
