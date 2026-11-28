package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// statsTestNow returns a fixed moment in the middle of a Moscow day so day
// buckets and the "today" checks are stable.
func statsTestNow() time.Time {
	local := time.Now().In(statsLocation)
	return time.Date(local.Year(), local.Month(), local.Day(), 12, 0, 0, 0, statsLocation)
}

func statsEventAt(at time.Time, event string, playerID int64, session string, payload map[string]any) statsEvent {
	if payload == nil {
		payload = map[string]any{}
	}
	return statsEvent{
		TS:       at,
		Event:    event,
		PlayerID: playerID,
		Session:  session,
		Platform: "VK/Android",
		Payload:  payload,
	}
}

func TestStatsDaysParamDefaultsAndClamps(t *testing.T) {
	cases := map[string]int{
		"":    defaultStatsDays,
		"1":   1,
		"7":   7,
		"30":  30,
		"2":   defaultStatsDays,
		"90":  defaultStatsDays,
		"abc": defaultStatsDays,
	}
	for raw, want := range cases {
		request := httptest.NewRequest(http.MethodGet, "/stats/data?days="+raw, nil)
		if got := statsDaysParam(request); got != want {
			t.Fatalf("days=%q -> %d, want %d", raw, got, want)
		}
	}
}

func TestStatsWindowCoversCalendarDaysInMoscow(t *testing.T) {
	now := statsTestNow()
	if got := statsDayKey(statsWindowStart(now, 1)); got != statsDayKey(now) {
		t.Fatalf("1 day window starts at %s, want today %s", got, statsDayKey(now))
	}
	start7 := statsWindowStart(now, 7)
	if got := statsDayKey(start7); got != statsDayKey(now.AddDate(0, 0, -6)) {
		t.Fatalf("7 day window starts at %s, want 6 days back", got)
	}
	start30 := statsWindowStart(now, 30)
	if got := statsDayKey(start30); got != statsDayKey(now.AddDate(0, 0, -29)) {
		t.Fatalf("30 day window starts at %s, want 29 days back", got)
	}
}

func TestStatsAdsFunnelAndFormatSplit(t *testing.T) {
	now := statsTestNow()
	events := []statsEvent{
		statsEventAt(now.Add(-time.Hour), "ad_offer", 1, "s1", map[string]any{"format": "rewarded", "placement": "results_double"}),
		statsEventAt(now.Add(-time.Hour), "ad_offer", 2, "s2", map[string]any{"format": "rewarded", "placement": "results_double"}),
		statsEventAt(now.Add(-time.Hour), "ad_result", 1, "s1", map[string]any{"format": "rewarded", "ok": true}),
		statsEventAt(now.Add(-time.Hour), "ad_result", 2, "s2", map[string]any{"format": "rewarded", "ok": false, "reason": "closed"}),
		statsEventAt(now.Add(-time.Hour), "ad_offer", 3, "s3", map[string]any{"format": "interstitial", "placement": "results"}),
		statsEventAt(now.Add(-time.Hour), "ad_offer", 4, "s4", map[string]any{"format": "interstitial", "placement": "results"}),
		statsEventAt(now.Add(-time.Hour), "ad_result", 3, "s3", map[string]any{"format": "interstitial", "ok": true}),
		// A bot offer must never reach the funnel.
		{TS: now.Add(-time.Hour), Event: "ad_offer", IsBot: true, Payload: map[string]any{"format": "rewarded"}},
	}
	summary := summarizeWindow(events, 7, nil)

	if summary.Ads.Formats["rewarded"].Offered != 2 {
		t.Fatalf("rewarded offered = %d, want 2", summary.Ads.Formats["rewarded"].Offered)
	}
	if summary.Ads.Formats["rewarded"].Watched != 1 {
		t.Fatalf("rewarded watched = %d, want 1", summary.Ads.Formats["rewarded"].Watched)
	}
	if summary.Ads.Formats["rewarded"].Skipped != 1 {
		t.Fatalf("rewarded skipped = %d, want 1", summary.Ads.Formats["rewarded"].Skipped)
	}
	if summary.Ads.Formats["rewarded"].WatchRate != 50 {
		t.Fatalf("rewarded watch rate = %d, want 50", summary.Ads.Formats["rewarded"].WatchRate)
	}
	if summary.Ads.Formats["interstitial"].Watched != 1 || summary.Ads.Formats["interstitial"].Offered != 2 {
		t.Fatalf("interstitial = %+v, want 1 watched of 2 offered", summary.Ads.Formats["interstitial"])
	}
	if summary.Ads.Offered != 4 || summary.Ads.Watched != 2 || summary.Ads.NotWatched != 2 {
		t.Fatalf("ads totals = %+v, want offered 4 watched 2 not watched 2", summary.Ads)
	}
	if summary.Ads.WatchRate != 50 {
		t.Fatalf("total watch rate = %d, want 50", summary.Ads.WatchRate)
	}
	if summary.JunkViews != 1 {
		t.Fatalf("junk views = %d, want 1", summary.JunkViews)
	}
}

func TestStatsReturningNewAndReturnedToday(t *testing.T) {
	now := statsTestNow()
	daysAgo := func(n int) time.Time { return now.AddDate(0, 0, -n).Add(-2 * time.Hour) }
	events := []statsEvent{
		// player 1: old player, active today and 3 days ago -> returning + returned today
		statsEventAt(daysAgo(3), "session_start", 1, "s1a", nil),
		statsEventAt(now.Add(-time.Hour), "session_start", 1, "s1b", nil),
		// player 2: new today
		statsEventAt(now.Add(-time.Hour), "session_start", 2, "s2", nil),
		// player 3: active on two old days, not today -> returning, not returned today
		statsEventAt(daysAgo(5), "session_start", 3, "s3a", nil),
		statsEventAt(daysAgo(2), "session_start", 3, "s3b", nil),
	}
	firstSeen := map[int64]time.Time{
		1: daysAgo(20),
		2: now.Add(-time.Hour),
		3: daysAgo(10),
	}
	summary := summarizeWindow(events, 7, firstSeen)

	if summary.UniquePlayers != 3 {
		t.Fatalf("unique players = %d, want 3", summary.UniquePlayers)
	}
	if summary.ReturningPlayers != 2 {
		t.Fatalf("returning players = %d, want 2 (1 and 3)", summary.ReturningPlayers)
	}
	if summary.ReturnedToday != 1 {
		t.Fatalf("returned today = %d, want 1 (player 1)", summary.ReturnedToday)
	}
	if summary.NewPlayers != 1 {
		t.Fatalf("new players = %d, want 1 (player 2)", summary.NewPlayers)
	}
	if len(summary.Days) != 7 {
		t.Fatalf("days rows = %d, want 7", len(summary.Days))
	}
	today := summary.Days[len(summary.Days)-1]
	if today.Date != statsDayKey(now) {
		t.Fatalf("last day row = %s, want %s", today.Date, statsDayKey(now))
	}
	if today.DAU != 2 || today.NewPlayers != 1 {
		t.Fatalf("today row = %+v, want DAU 2 and 1 new", today)
	}
}

func TestStatsWindowDropsOlderEventsButKeepsThemOutOfDays(t *testing.T) {
	now := statsTestNow()
	old := now.AddDate(0, 0, -8)
	events := []statsEvent{
		statsEventAt(old, "page_view", 0, "old", nil),
		statsEventAt(now.Add(-time.Hour), "page_view", 0, "new", nil),
		statsEventAt(now.Add(-time.Hour), "match_start", 5, "new", nil),
	}
	summary := summarizeWindow(events, 7, nil)
	if summary.PageViews != 1 {
		t.Fatalf("page views = %d, want 1 (the 8-day-old view is outside the window)", summary.PageViews)
	}
	if summary.Matches != 1 {
		t.Fatalf("matches = %d, want 1", summary.Matches)
	}
	// The window start itself: a 30-day summary must include the same event.
	long := summarizeWindow(events, 30, nil)
	if long.PageViews != 2 {
		t.Fatalf("30-day page views = %d, want 2", long.PageViews)
	}
}

func TestStatsEmptyWindowRendersZeroes(t *testing.T) {
	summary := summarizeWindow(nil, 7, nil)
	if summary.UniquePlayers != 0 || summary.Ads.Offered != 0 || summary.Ads.WatchRate != 0 {
		t.Fatalf("empty window = %+v, want zeroes", summary)
	}
	if len(summary.Days) != 7 {
		t.Fatalf("empty window must still return 7 day rows, got %d", len(summary.Days))
	}
	if _, ok := summary.Ads.Formats["rewarded"]; !ok {
		t.Fatal("rewarded format must always be present")
	}
	if _, ok := summary.Ads.Formats["interstitial"]; !ok {
		t.Fatal("interstitial format must always be present")
	}
}

func TestStatsDashboardExplainsMissingTokenWith503(t *testing.T) {
	t.Setenv("STATS_TOKEN", "")
	t.Setenv("ADMIN_TOKEN", "")
	service := &api{}

	recorder := httptest.NewRecorder()
	service.handleStatsDashboard(recorder, httptest.NewRequest(http.MethodGet, "/stats/dashboard", nil))
	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("dashboard without STATS_TOKEN = %d, want 503", recorder.Code)
	}
	body := recorder.Body.String()
	if !strings.Contains(body, "STATS_TOKEN") || !strings.Contains(body, "RelaxDev") {
		t.Fatal("503 page must name STATS_TOKEN and the RelaxDev panel")
	}
}

func TestStatsDashboardRendersWithToken(t *testing.T) {
	t.Setenv("STATS_TOKEN", "test-token")
	service := &api{}

	recorder := httptest.NewRecorder()
	service.handleStatsDashboard(recorder, httptest.NewRequest(http.MethodGet, "/stats/dashboard?token=test-token", nil))
	if recorder.Code != http.StatusOK {
		t.Fatalf("dashboard with token = %d, want 200", recorder.Code)
	}
	body := recorder.Body.String()
	for _, marker := range []string{"data-days=\"1\"", "data-days=\"7\"", "data-days=\"30\"", "Реклама за период", "Вернулись"} {
		if !strings.Contains(body, marker) {
			t.Fatalf("dashboard HTML is missing %q", marker)
		}
	}
}

func TestStatsDataStaysFailClosedAndExplainsMissingToken(t *testing.T) {
	t.Setenv("STATS_TOKEN", "")
	t.Setenv("ADMIN_TOKEN", "")
	service := &api{}

	recorder := httptest.NewRecorder()
	service.handleStatsData(recorder, httptest.NewRequest(http.MethodGet, "/stats/data?token=239837", nil))
	if recorder.Code != http.StatusForbidden {
		t.Fatalf("data without STATS_TOKEN = %d, want 403", recorder.Code)
	}
	body := recorder.Body.String()
	if !strings.Contains(body, "stats_token_not_configured") {
		t.Fatalf("403 body must explain the missing token, got %s", body)
	}
	if !strings.Contains(body, `"error":"forbidden"`) {
		t.Fatalf("403 body must keep the old error string, got %s", body)
	}
}

func TestStatsDataAcceptsTokenAndDays(t *testing.T) {
	t.Setenv("STATS_TOKEN", "test-token")
	service := &api{}

	recorder := httptest.NewRecorder()
	service.handleStatsData(recorder, httptest.NewRequest(http.MethodGet, "/stats/data?token=test-token&days=30", nil))
	if recorder.Code != http.StatusOK {
		t.Fatalf("data with token = %d, want 200", recorder.Code)
	}
	body := recorder.Body.String()
	if !strings.Contains(body, `"window_days":30`) {
		t.Fatalf("data must report the requested window, got %s", body)
	}
	if !strings.Contains(body, `"ads"`) || !strings.Contains(body, `"returning_players"`) {
		t.Fatalf("data must expose the new fields, got %s", body)
	}
}
