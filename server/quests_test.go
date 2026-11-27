package main

import (
	"os"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestQuestDayBoundaries(t *testing.T) {
	cases := []struct {
		name string
		at   time.Time
		want string
	}{
		{"just before reset", time.Date(2026, 11, 27, 3, 59, 0, 0, questZone), "2026-11-26"},
		{"exactly at reset", time.Date(2026, 11, 27, 4, 0, 0, 0, questZone), "2026-11-27"},
		{"late evening", time.Date(2026, 11, 27, 23, 59, 0, 0, questZone), "2026-11-27"},
		{"midnight is still the same quest day", time.Date(2026, 11, 28, 0, 0, 0, 0, questZone), "2026-11-27"},
		{"utc 01:00 is msk 04:00", time.Date(2026, 11, 27, 1, 0, 0, 0, time.UTC), "2026-11-27"},
		{"new year night", time.Date(2027, 1, 1, 3, 0, 0, 0, questZone), "2026-12-31"},
	}
	for _, testCase := range cases {
		if got := questDayKey(testCase.at); got != testCase.want {
			t.Fatalf("%s: questDayKey = %q, want %q", testCase.name, got, testCase.want)
		}
	}
}

func TestQuestResetsAt(t *testing.T) {
	cases := []struct {
		name string
		at   time.Time
		want time.Time
	}{
		{
			"before reset",
			time.Date(2026, 11, 27, 3, 59, 0, 0, questZone),
			time.Date(2026, 11, 27, 4, 0, 0, 0, questZone),
		},
		{
			"exactly at reset moves to tomorrow",
			time.Date(2026, 11, 27, 4, 0, 0, 0, questZone),
			time.Date(2026, 11, 28, 4, 0, 0, 0, questZone),
		},
		{
			"daytime",
			time.Date(2026, 11, 27, 10, 30, 0, 0, questZone),
			time.Date(2026, 11, 28, 4, 0, 0, 0, questZone),
		},
		{
			"utc timestamp",
			time.Date(2026, 11, 27, 22, 0, 0, 0, time.UTC),
			time.Date(2026, 11, 28, 4, 0, 0, 0, questZone),
		},
	}
	for _, testCase := range cases {
		if got := questResetsAt(testCase.at); got != testCase.want.Unix() {
			t.Fatalf("%s: questResetsAt = %d, want %d (%s)",
				testCase.name, got, testCase.want.Unix(), testCase.want)
		}
	}
}

func TestQuestResetsAtForDay(t *testing.T) {
	want := time.Date(2026, 11, 28, 4, 0, 0, 0, questZone).Unix()
	if got := questResetsAtForDay("2026-11-27"); got != want {
		t.Fatalf("questResetsAtForDay = %d, want %d", got, want)
	}
	if got := questResetsAtForDay("not-a-day"); got != 0 {
		t.Fatalf("invalid day resets_at = %d, want 0", got)
	}
}

func TestQuestWeekStart(t *testing.T) {
	cases := map[string]string{
		"2026-11-23": "2026-11-23", // Monday
		"2026-11-27": "2026-11-23", // Friday
		"2026-11-29": "2026-11-23", // Sunday
		"2026-11-30": "2026-11-30", // season anchor is a Monday
		"2026-12-06": "2026-11-30", // Sunday of week 1
	}
	for day, want := range cases {
		if got := questWeekStart(day); got != want {
			t.Fatalf("questWeekStart(%q) = %q, want %q", day, got, want)
		}
	}
	if got := questWeekStart(""); got != "" {
		t.Fatalf("questWeekStart(\"\") = %q, want empty", got)
	}
}

func TestQuestSeasonTierLadder(t *testing.T) {
	cases := []struct {
		weekStart string
		tier      int
		kind      string
		shards    int
		items     []int
	}{
		{"2026-11-30", 1, "weapon", 100, []int{13}},
		{"2026-12-07", 2, "shards", 1000, nil},
		{"2026-12-14", 3, "shards", 3000, nil},
		{"2026-12-21", 4, "skin", 0, []int{10, 11, 12}},
		{"2026-12-28", 5, "shards", 1000, nil},
		{"2027-01-04", 6, "shards", 3000, nil},
		{"2027-01-11", 7, "skin", 0, []int{10, 11, 12}},
		{"2026-11-23", 1, "weapon", 100, []int{13}}, // before the anchor: week 1
	}
	for _, testCase := range cases {
		tier, kind, shards, items := questSeasonTier(testCase.weekStart)
		if tier != testCase.tier || kind != testCase.kind || shards != testCase.shards || !reflect.DeepEqual(items, testCase.items) {
			t.Fatalf("questSeasonTier(%q) = (%d, %q, %d, %v), want (%d, %q, %d, %v)",
				testCase.weekStart, tier, kind, shards, items,
				testCase.tier, testCase.kind, testCase.shards, testCase.items)
		}
	}
}

func TestQuestTemplateTable(t *testing.T) {
	expected := map[string]struct {
		metric     string
		target     int
		difficulty string
		shards     int
		xp         int
		minMatches int
	}{
		"kills_8":     {"kills", 8, questEasy, 3, 150, 0},
		"kills_12":    {"kills", 12, questMedium, 4, 200, 5},
		"triple_kill": {"max_kills_one", 3, questMedium, 4, 200, 3},
		"damage_4000": {"damage", 4000, questMedium, 4, 200, 0},
		"damage_7000": {"damage", 7000, questHard, 5, 250, 10},
		"shells_2":    {"shells", 2, questEasy, 3, 150, 0},
		"crystal_2":   {"crystals", 2, questMedium, 4, 200, 0},
		"crystal_3":   {"crystals", 3, questHard, 5, 250, 5},
		"play_2":      {"matches", 2, questEasy, 3, 150, 0},
		"play_3":      {"matches", 3, questEasy, 3, 150, 0},
		"win_1":       {"wins", 1, questEasy, 3, 150, 0},
		"win_2":       {"wins", 2, questMedium, 4, 200, 3},
		"fast_win":    {"fast_wins", 1, questMedium, 4, 200, 3},
		"fast_win_2":  {"fast_wins", 2, questHard, 5, 250, 10},
		"buy_2":       {"shop_items_one", 2, questMedium, 4, 200, 0},
		"buy_3":       {"shop_items_one", 3, questHard, 5, 250, 20},
	}
	seen := map[string]bool{}
	enabledCount := 0
	disabledCount := 0
	for _, template := range questTemplateRegistry {
		seen[template.ID] = true
		if !template.Enabled {
			disabledCount++
			continue
		}
		enabledCount++
		want, ok := expected[template.ID]
		if !ok {
			t.Fatalf("unexpected enabled template %q", template.ID)
		}
		if template.Metric != want.metric || template.Target != want.target ||
			template.Difficulty != want.difficulty || template.RewardShards != want.shards ||
			template.RewardXP != want.xp || template.MinMatches != want.minMatches {
			t.Fatalf("template %q = %+v, want metric=%s target=%d difficulty=%s reward=%d/%d min=%d",
				template.ID, template, want.metric, want.target, want.difficulty, want.shards, want.xp, want.minMatches)
		}
		if template.Title == "" || template.Category == "" || template.Minutes <= 0 {
			t.Fatalf("template %q is missing metadata: %+v", template.ID, template)
		}
	}
	for id := range expected {
		if !seen[id] {
			t.Fatalf("template %q is missing from the registry", id)
		}
	}
	if enabledCount != 16 {
		t.Fatalf("enabled templates = %d, want 16", enabledCount)
	}
	if disabledCount != 1 {
		t.Fatalf("disabled templates = %d, want 1 (survive_win)", disabledCount)
	}
	if questTemplateByID("survive_win") == nil || questTemplateByID("survive_win").Enabled {
		t.Fatal("survive_win must exist and be disabled")
	}
	if template := questTemplateByID("buy_3"); template == nil || !template.Enabled {
		t.Fatal("buy_3 must exist and be enabled")
	}
}

func TestGenerateQuestsDeterministic(t *testing.T) {
	first := generateQuests(42, "2026-11-27", 12, 0)
	again := generateQuests(42, "2026-11-27", 12, 0)
	if !reflect.DeepEqual(first, again) {
		t.Fatalf("same seed produced different quests:\n%+v\n%+v", first, again)
	}
	otherDay := generateQuests(42, "2026-11-28", 12, 0)
	if reflect.DeepEqual(first, otherDay) {
		t.Fatal("a different day produced the same quest set")
	}
	otherPlayer := generateQuests(43, "2026-11-27", 12, 0)
	if reflect.DeepEqual(first, otherPlayer) {
		t.Fatal("a different player produced the same quest set")
	}
}

func TestGenerateQuestsRerollStreamShifts(t *testing.T) {
	changed := 0
	for playerID := int64(1); playerID <= 20; playerID++ {
		base := generateQuests(playerID, "2026-11-27", 20, 0)
		shifted := generateQuests(playerID, "2026-11-27", 20, 1)
		if !reflect.DeepEqual(base, shifted) {
			changed++
		}
	}
	if changed == 0 {
		t.Fatal("reroll_seq did not shift the generation stream for any player")
	}
}

func TestGenerateQuestsConstraints(t *testing.T) {
	days := []string{"2026-11-27", "2026-11-28", "2026-11-30", "2026-12-01", "2026-12-07"}
	matchesOptions := []int{0, 1, 3, 5, 9, 10, 30, 200}
	for playerID := int64(1); playerID <= 25; playerID++ {
		for _, day := range days {
			for _, matchesPlayed := range matchesOptions {
				quests := generateQuests(playerID, day, matchesPlayed, 0)
				context := "player=" + itoa64(playerID) + " day=" + day + " matches=" + itoa(matchesPlayed)
				if len(quests) != questsPerDay {
					t.Fatalf("%s: generated %d quests, want %d", context, len(quests), questsPerDay)
				}
				ids := map[string]bool{}
				categories := map[string]bool{}
				easyCount := 0
				winCount := 0
				totalMinutes := 0
				newbie := matchesPlayed < questNoviceMatches
				sawPlayTwo := false
				for slot, quest := range quests {
					if quest.Slot != slot {
						t.Fatalf("%s: slot %d has Slot=%d", context, slot, quest.Slot)
					}
					if quest.TemplateID == "" || quest.Metric == "" || quest.Target <= 0 {
						t.Fatalf("%s: empty quest at slot %d: %+v", context, slot, quest)
					}
					if ids[quest.TemplateID] {
						t.Fatalf("%s: duplicate template %q", context, quest.TemplateID)
					}
					ids[quest.TemplateID] = true
					template := questTemplateByID(quest.TemplateID)
					if template == nil || !template.Enabled {
						t.Fatalf("%s: generated disabled/unknown template %q", context, quest.TemplateID)
					}
					if matchesPlayed < template.MinMatches {
						t.Fatalf("%s: template %q needs %d matches", context, quest.TemplateID, template.MinMatches)
					}
					if newbie && questNoviceExcludedIDs[quest.TemplateID] {
						t.Fatalf("%s: novice got restricted template %q", context, quest.TemplateID)
					}
					if categories[template.Category] {
						t.Fatalf("%s: category %q appears twice", context, template.Category)
					}
					categories[template.Category] = true
					if quest.Difficulty == questEasy {
						easyCount++
					}
					if questIsWinMetric(*template) {
						winCount++
					}
					totalMinutes += template.Minutes
					if quest.TemplateID == "play_2" {
						sawPlayTwo = true
					}
				}
				if !sawPlayTwo {
					t.Fatalf("%s: play_2 is not in the easy slot (got %v)", context, questIDs(quests))
				}
				if easyCount != 1 {
					t.Fatalf("%s: easy quests = %d, want exactly 1 (%v)", context, easyCount, questIDs(quests))
				}
				if winCount > 1 {
					t.Fatalf("%s: win quests = %d, want at most 1 (%v)", context, winCount, questIDs(quests))
				}
				if totalMinutes < 15 || totalMinutes > questTargetMinutes {
					t.Fatalf("%s: estimated minutes = %d, want 15..%d (%v)",
						context, totalMinutes, questTargetMinutes, questIDs(quests))
				}
			}
		}
	}
}

func TestGenerateQuestsNovicePool(t *testing.T) {
	// A novice never sees the restricted ids, no matter the day/player.
	for playerID := int64(1); playerID <= 30; playerID++ {
		for dayIndex := 0; dayIndex < 30; dayIndex++ {
			day := questAddDays("2026-11-27", dayIndex)
			quests := generateQuests(playerID, day, 7, 0)
			for _, quest := range quests {
				if questNoviceExcludedIDs[quest.TemplateID] {
					t.Fatalf("player=%d day=%s: novice got %q", playerID, day, quest.TemplateID)
				}
				template := questTemplateByID(quest.TemplateID)
				if template == nil || 7 < template.MinMatches {
					t.Fatalf("player=%d day=%s: novice got a locked template %q", playerID, day, quest.TemplateID)
				}
			}
		}
	}
	// After ten matches the wider pool is reachable.
	sawAdvanced := false
	for playerID := int64(1); playerID <= 60; playerID++ {
		for dayIndex := 0; dayIndex < 20; dayIndex++ {
			day := questAddDays("2026-11-27", dayIndex)
			for _, quest := range generateQuests(playerID, day, 20, 0) {
				switch quest.TemplateID {
				case "triple_kill", "fast_win_2", "damage_7000", "crystal_3", "kills_12", "buy_3":
					sawAdvanced = true
				}
			}
		}
	}
	if !sawAdvanced {
		t.Fatal("advanced templates never appeared for a non-novice")
	}
}

func TestQuestProgressPerMatchCap(t *testing.T) {
	cases := []struct {
		metric string
		target int
		value  int
		want   int
	}{
		{"kills", 8, 100, 4},
		{"kills", 12, 100, 7},
		{"damage", 4000, 999999, 2400},
		{"damage", 7000, 999999, 4200},
		{"crystals", 2, 9, 1},
		{"crystals", 3, 9, 1},
		{"shells", 2, 9, 1},
	}
	for _, testCase := range cases {
		stats := matchStats{durationSec: 300}
		switch testCase.metric {
		case "kills":
			stats.kills = testCase.value
		case "damage":
			stats.damage = testCase.value
		case "crystals":
			stats.crystals = testCase.value
		case "shells":
			stats.shells = testCase.value
		}
		got := questProgressAfterMatch(testCase.metric, testCase.target, 0, stats)
		if got != testCase.want {
			t.Fatalf("%s/%d after one match = %d, want %d", testCase.metric, testCase.target, got, testCase.want)
		}
	}
	if cap := questPerMatchCap(2); cap != 1 {
		t.Fatalf("questPerMatchCap(2) = %d, want 1", cap)
	}
	if cap := questPerMatchCap(3); cap != 1 {
		t.Fatalf("questPerMatchCap(3) = %d, want 1 (floor of 60%%)", cap)
	}
}

func TestQuestProgressAccumulatesToTarget(t *testing.T) {
	stats := matchStats{durationSec: 200, kills: 50}
	progress := 0
	for match := 0; match < 2; match++ {
		progress = questProgressAfterMatch("kills", 8, progress, stats)
	}
	if progress != 8 {
		t.Fatalf("two capped matches gave %d, want the target 8", progress)
	}
	// More matches cannot overshoot the target.
	progress = questProgressAfterMatch("kills", 8, progress, stats)
	if progress != 8 {
		t.Fatalf("progress after a completed quest = %d, want 8", progress)
	}
}

func TestQuestProgressMetrics(t *testing.T) {
	longWin := matchStats{durationSec: 300, won: true}
	if got := questProgressAfterMatch("matches", 3, 1, longWin); got != 2 {
		t.Fatalf("matches = %d, want 2", got)
	}
	if got := questProgressAfterMatch("wins", 2, 0, longWin); got != 1 {
		t.Fatalf("wins = %d, want 1", got)
	}
	if got := questProgressAfterMatch("wins", 2, 0, matchStats{durationSec: 300}); got != 0 {
		t.Fatalf("lost match moved wins to %d, want 0", got)
	}
	if got := questProgressAfterMatch("fast_wins", 1, 0, matchStats{durationSec: 420, won: true}); got != 1 {
		t.Fatalf("fast_win at 7:00 = %d, want 1", got)
	}
	if got := questProgressAfterMatch("fast_wins", 1, 0, matchStats{durationSec: 421, won: true}); got != 0 {
		t.Fatalf("fast_win at 7:01 = %d, want 0", got)
	}
	if got := questProgressAfterMatch("fast_wins", 1, 0, matchStats{durationSec: 100, won: false}); got != 0 {
		t.Fatalf("fast_win on a loss = %d, want 0", got)
	}
	if got := questProgressAfterMatch("max_kills_one", 3, 0, matchStats{kills: 2}); got != 2 {
		t.Fatalf("max_kills_one = %d, want 2", got)
	}
	if got := questProgressAfterMatch("max_kills_one", 3, 2, matchStats{kills: 1}); got != 2 {
		t.Fatalf("max_kills_one used a sum instead of the maximum: %d", got)
	}
	if got := questProgressAfterMatch("max_kills_one", 3, 2, matchStats{kills: 9}); got != 3 {
		t.Fatalf("max_kills_one = %d, want the capped target 3", got)
	}
	if got := questProgressAfterMatch("shop_items_one", 2, 0, matchStats{shopItems: 1}); got != 1 {
		t.Fatalf("shop_items_one = %d, want 1", got)
	}
	if got := questProgressAfterMatch("shop_items_one", 2, 1, matchStats{shopItems: 0}); got != 1 {
		t.Fatalf("shop_items_one went backwards: %d", got)
	}
	if got := questProgressAfterMatch("shop_items_one", 2, 1, matchStats{shopItems: 5}); got != 2 {
		t.Fatalf("shop_items_one = %d, want 2", got)
	}
	if got := questProgressAfterMatch("survive_wins", 1, 0, matchStats{won: true, deaths: 0}); got != 1 {
		t.Fatalf("survive_win with no deaths = %d, want 1", got)
	}
	if got := questProgressAfterMatch("survive_wins", 1, 0, matchStats{won: true, deaths: 1}); got != 0 {
		t.Fatalf("survive_win with a death = %d, want 0", got)
	}
}

func TestQuestMinimumMatchDuration(t *testing.T) {
	if questMatchQualifies(matchStats{durationSec: 89}) {
		t.Fatal("an 89-second match must not count")
	}
	if !questMatchQualifies(matchStats{durationSec: 90}) {
		t.Fatal("a 90-second match must count")
	}
	// applyQuestProgress returns before any metric math for a short match; the
	// pure metric helper stays unaware of the duration on purpose, so this is
	// the single gate.
	stats := matchStats{durationSec: 89, kills: 8}
	if questMatchQualifies(stats) {
		t.Fatal("the short-match gate must reject this input")
	}
}

func TestAllThreeBonus(t *testing.T) {
	cases := []struct {
		completed int
		already   bool
		want      int
		closed    bool
	}{
		{0, false, 0, false},
		{2, false, 0, false},
		{3, false, questAllDoneBonusShards, true},
		{3, true, 0, true},
		{4, false, questAllDoneBonusShards, true},
	}
	for _, testCase := range cases {
		if got := questAllDoneBonus(testCase.completed, testCase.already); got != testCase.want {
			t.Fatalf("questAllDoneBonus(%d, %v) = %d, want %d",
				testCase.completed, testCase.already, got, testCase.want)
		}
		if got := questDayClosed(testCase.completed); got != testCase.closed {
			t.Fatalf("questDayClosed(%d) = %v, want %v", testCase.completed, got, testCase.closed)
		}
	}
}

func TestWeekSevenOfSeven(t *testing.T) {
	// Only fully completed days move the strict 7/7 counter.
	fullWeek := []int{3, 3, 3, 3, 3, 3, 3}
	if got := questWeekActiveDaysFromCounts(fullWeek); got != 7 {
		t.Fatalf("active_days for 7 full days = %d, want 7", got)
	}
	if !(questWeekActiveDaysFromCounts(fullWeek) >= questWeekDays) {
		t.Fatal("7/7 week must be claimable")
	}
	onePartialDay := []int{3, 3, 3, 2, 3, 3, 3}
	if got := questWeekActiveDaysFromCounts(onePartialDay); got != 6 {
		t.Fatalf("active_days with one 2/3 day = %d, want 6", got)
	}
	if questWeekActiveDaysFromCounts(onePartialDay) >= questWeekDays {
		t.Fatal("a week with a 2/3 day must not be claimable")
	}
	// One quest is not a closed day any more (the old >= 1 rule).
	if got := questWeekActiveDaysFromCounts([]int{1, 1, 1, 1, 1, 1, 1}); got != 0 {
		t.Fatalf("active_days with one quest per day = %d, want 0", got)
	}
}

func TestWeekMissedDay(t *testing.T) {
	counts := []int{3, 0, 3, 3, 2, 3, 3}
	activeDays := questWeekActiveDaysFromCounts(counts)
	if activeDays != 5 {
		t.Fatalf("active_days = %d, want 5", activeDays)
	}
	missed := 0
	for _, completed := range counts {
		if !questDayClosed(completed) {
			missed++
		}
	}
	if missed != 2 {
		t.Fatalf("missed days = %d, want 2 (0/3 and 2/3)", missed)
	}
	if activeDays+missed != questWeekDays {
		t.Fatalf("active %d + missed %d != %d", activeDays, missed, questWeekDays)
	}
}

func TestQuestRerollMode(t *testing.T) {
	if mode, cost := questRerollMode(false, 0); mode != "free" || cost != 0 {
		t.Fatalf("first reroll = (%q, %d), want free/0", mode, cost)
	}
	if mode, cost := questRerollMode(true, 0); mode != "paid" || cost != 1 {
		t.Fatalf("second reroll = (%q, %d), want paid/1", mode, cost)
	}
	if mode, cost := questRerollMode(true, 1); mode != "paid" || cost != 1 {
		t.Fatalf("third reroll = (%q, %d), want paid/1", mode, cost)
	}
	if mode, _ := questRerollMode(true, 2); mode != "" {
		t.Fatalf("fourth reroll = %q, want denied", mode)
	}
	state := questRerollStateFrom(dailyQuestDayState{FreeRerollUsed: false, PaidRerolls: 0})
	if state.Remaining != 3 || !state.FreeAvailable || state.PaidRemaining != 2 {
		t.Fatalf("fresh reroll state = %+v", state)
	}
	state = questRerollStateFrom(dailyQuestDayState{FreeRerollUsed: true, PaidRerolls: 2})
	if state.Remaining != 0 || state.FreeAvailable || state.PaidRemaining != 0 {
		t.Fatalf("exhausted reroll state = %+v", state)
	}
}

func TestQuestRerollReplacement(t *testing.T) {
	for playerID := int64(1); playerID <= 12; playerID++ {
		for _, matchesPlayed := range []int{0, 3, 20} {
			quests := generateQuests(playerID, "2026-11-27", matchesPlayed, 0)
			novice := matchesPlayed < questNoviceMatches
			for slot := 0; slot < questsPerDay; slot++ {
				replacement := questPickReroll(
					questRNGFromSeed(int64(questFNV1a64("seed")), 0, slot),
					quests[slot], quests, matchesPlayed, novice,
				)
				if replacement == nil {
					t.Fatalf("player=%d matches=%d slot=%d: no replacement", playerID, matchesPlayed, slot)
				}
				if replacement.ID == quests[slot].TemplateID {
					t.Fatalf("player=%d slot=%d: reroll kept %q", playerID, slot, replacement.ID)
				}
				for otherSlot, quest := range quests {
					if otherSlot != slot && quest.TemplateID == replacement.ID {
						t.Fatalf("player=%d slot=%d: reroll duplicated %q from slot %d",
							playerID, slot, replacement.ID, otherSlot)
					}
				}
				if matchesPlayed < replacement.MinMatches {
					t.Fatalf("player=%d: reroll picked %q with min %d", playerID, replacement.ID, replacement.MinMatches)
				}
				if novice && questNoviceExcludedIDs[replacement.ID] {
					t.Fatalf("player=%d: novice reroll picked %q", playerID, replacement.ID)
				}
				if quests[slot].Difficulty != questEasy && replacement.Difficulty == questEasy {
					t.Fatalf("player=%d slot=%d: reroll added a second easy quest (%q -> %q)",
						playerID, slot, quests[slot].TemplateID, replacement.ID)
				}
			}
		}
	}
	// The easy slot keeps its difficulty (and category) so the 7/7 safety and
	// the exactly-one-easy rule survive a reroll.
	quests := generateQuests(7, "2026-11-27", 20, 0)
	replacement := questPickReroll(questRNGFromSeed(1, 0, 1), quests[1], quests, 20, false)
	if replacement == nil || replacement.Difficulty != questEasy || replacement.Category != "matches" {
		t.Fatalf("easy-slot reroll = %+v, want an easy matches quest", replacement)
	}
}

func TestQuestWeeklyCompensationAndItems(t *testing.T) {
	if got := questWeeklyCompensation("skin"); got != 1000 {
		t.Fatalf("skin compensation = %d, want 1000", got)
	}
	if got := questWeeklyCompensation("weapon"); got != 100 {
		t.Fatalf("weapon compensation = %d, want 100", got)
	}
	if got := questWeeklyCompensation("shards"); got != 100 {
		t.Fatalf("product compensation = %d, want 100", got)
	}
	if got := questAppendItemID("1,2", 3); got != "1,2,3" {
		t.Fatalf("questAppendItemID = %q", got)
	}
	if got := questAppendItemID("1,2", 2); got != "1,2" {
		t.Fatalf("questAppendItemID duplicated an item: %q", got)
	}
	if !questPlayerOwns("1,10", "", 10) {
		t.Fatal("a wing item must count as owned")
	}
	if !questPlayerOwns("", "10", 10) {
		t.Fatal("a weapon item must count as owned")
	}
	if questPlayerOwns("1,2", "3", 10) {
		t.Fatal("an unowned item counted as owned")
	}
	if !questContainsInt([]int{10, 11, 12}, 11) || questContainsInt([]int{10, 11, 12}, 13) {
		t.Fatal("questContainsInt is wrong")
	}
}

func questIDs(quests []dailyQuest) []string {
	ids := make([]string, 0, len(quests))
	for _, quest := range quests {
		ids = append(ids, quest.TemplateID)
	}
	return ids
}

func itoa(value int) string {
	if value == 0 {
		return "0"
	}
	negative := value < 0
	if negative {
		value = -value
	}
	digits := make([]byte, 0, 12)
	for value > 0 {
		digits = append([]byte{byte('0' + value%10)}, digits...)
		value /= 10
	}
	if negative {
		return "-" + string(digits)
	}
	return string(digits)
}

func itoa64(value int64) string {
	return itoa(int(value))
}

// TestQuestSchemaMatchesSQLFile keeps the runtime migration (quests.go) in
// sync with schema.sql. The production server never reads schema.sql, so a
// statement that exists only in the file is dead code on a deployed database.
func TestQuestSchemaMatchesSQLFile(t *testing.T) {
	data, err := os.ReadFile("schema.sql")
	if err != nil {
		t.Fatalf("read schema.sql: %v", err)
	}
	schemaText := normalizeQuestSQL(string(data))
	for _, statement := range questSchemaStatements {
		normalized := normalizeQuestSQL(statement)
		if !strings.Contains(schemaText, normalized) {
			t.Fatalf("schema.sql is missing an ensureQuestSchema statement:\n%s", statement)
		}
	}
}

func normalizeQuestSQL(text string) string {
	lines := strings.Split(text, "\n")
	kept := make([]string, 0, len(lines))
	for _, line := range lines {
		if index := strings.Index(line, "--"); index >= 0 {
			line = line[:index]
		}
		kept = append(kept, line)
	}
	text = strings.ReplaceAll(strings.Join(kept, "\n"), ";", " ")
	return strings.Join(strings.Fields(text), " ")
}
