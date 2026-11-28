package main

// Daily quests: deterministic daily sets, progress from validated matches, the
// weekly ladder and the HTTP API. The single source of truth for constants,
// schema and templates is docs/DAILY-QUESTS-SPEC.md.
//
// The quest day is 04:00 MSK -> 03:59 MSK (UTC+3, no DST). Progress is only
// moved by applyQuestProgress, which the match saver calls inside its own
// transaction with counters the server validated itself.

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const (
	questDateLayout         = "2006-01-02"
	questDayResetHour       = 4
	questsPerDay            = 3
	questFreeRerolls        = 1
	questPaidRerolls        = 2
	questPaidRerollCost     = 1
	questAllDoneBonusShards = 10
	questWeekDays           = 7
	questNoviceMatches      = 10
	questMinMatchSeconds    = 90
	questFastWinSeconds     = 7 * 60
	// questProgressPercent is the share of a cumulative target one match may
	// contribute. Without it a single very long match could finish a 3-day
	// quest on day one.
	questProgressPercent = 60
	// questWeeklyShardReward is the flat weekly prize for a 7/7 week. There is
	// no tier ladder any more: every completed week pays the same 300 shards.
	questWeeklyShardReward = 300
	// questTargetMinutes is the soft upper bound for the three quests' sum.
	questTargetMinutes = 25

	questEasy   = "E"
	questMedium = "M"
	questHard   = "H"
)

// questZone is fixed UTC+3: the quest day never shifts with DST.
var questZone = time.FixedZone("MSK", 3*60*60)

// questNoviceExcludedIDs is the spec's novice pool restriction (fewer than ten
// matches). min_matches already hides most of them; triple_kill and the
// disabled ids need this explicit list.
var questNoviceExcludedIDs = map[string]bool{
	"triple_kill": true,
	"fast_win_2":  true,
	"survive_win": true,
	"buy_3":       true,
}

// questTemplate is one row of the MVP template table. Category is the
// diversity axis: a daily set never contains two templates of one category.
type questTemplate struct {
	ID           string
	Title        string
	Metric       string
	Category     string
	Target       int
	Difficulty   string
	RewardShards int
	RewardXP     int
	MinMatches   int
	Minutes      int
	Enabled      bool
}

// questTemplateRegistry holds the 15 MVP templates plus the two disabled ones
// that are kept for a later wave. Rewards come from the E/M/H table:
// 3/150, 4/200, 5/250.
var questTemplateRegistry = []questTemplate{
	{ID: "kills_8", Title: "Убить 8 врагов", Metric: "kills", Category: "kills", Target: 8, Difficulty: questEasy, RewardShards: 3, RewardXP: 150, Minutes: 7, Enabled: true},
	{ID: "kills_12", Title: "Убить 12 врагов", Metric: "kills", Category: "kills", Target: 12, Difficulty: questMedium, RewardShards: 4, RewardXP: 200, MinMatches: 5, Minutes: 9, Enabled: true},
	{ID: "triple_kill", Title: "3 убийства за бой", Metric: "max_kills_one", Category: "kills", Target: 3, Difficulty: questMedium, RewardShards: 4, RewardXP: 200, MinMatches: 3, Minutes: 8, Enabled: true},
	{ID: "damage_4000", Title: "Нанести урон 4000", Metric: "damage", Category: "damage", Target: 4000, Difficulty: questMedium, RewardShards: 4, RewardXP: 200, Minutes: 8, Enabled: true},
	{ID: "damage_7000", Title: "Нанести урон 7000", Metric: "damage", Category: "damage", Target: 7000, Difficulty: questHard, RewardShards: 5, RewardXP: 250, MinMatches: 10, Minutes: 13, Enabled: true},
	{ID: "shells_2", Title: "Разрушить 2 снаряда", Metric: "shells", Category: "shells", Target: 2, Difficulty: questEasy, RewardShards: 3, RewardXP: 150, Minutes: 6, Enabled: true},
	{ID: "crystal_2", Title: "Доставить 2 кристалла", Metric: "crystals", Category: "crystals", Target: 2, Difficulty: questMedium, RewardShards: 4, RewardXP: 200, Minutes: 8, Enabled: true},
	{ID: "crystal_3", Title: "Доставить 3 кристалла", Metric: "crystals", Category: "crystals", Target: 3, Difficulty: questHard, RewardShards: 5, RewardXP: 250, MinMatches: 5, Minutes: 11, Enabled: true},
	{ID: "play_2", Title: "Сыграть 2 боя", Metric: "matches", Category: "matches", Target: 2, Difficulty: questEasy, RewardShards: 3, RewardXP: 150, Minutes: 6, Enabled: true},
	{ID: "play_3", Title: "Сыграть 3 боя", Metric: "matches", Category: "matches", Target: 3, Difficulty: questEasy, RewardShards: 3, RewardXP: 150, Minutes: 9, Enabled: true},
	{ID: "win_1", Title: "Победить", Metric: "wins", Category: "wins", Target: 1, Difficulty: questEasy, RewardShards: 3, RewardXP: 150, Minutes: 8, Enabled: true},
	{ID: "win_2", Title: "Победить 2 раза", Metric: "wins", Category: "wins", Target: 2, Difficulty: questMedium, RewardShards: 4, RewardXP: 200, MinMatches: 3, Minutes: 9, Enabled: true},
	{ID: "fast_win", Title: "Победа за 7 мин", Metric: "fast_wins", Category: "fast_wins", Target: 1, Difficulty: questMedium, RewardShards: 4, RewardXP: 200, MinMatches: 3, Minutes: 8, Enabled: true},
	{ID: "fast_win_2", Title: "2 быстрые победы", Metric: "fast_wins", Category: "fast_wins", Target: 2, Difficulty: questHard, RewardShards: 5, RewardXP: 250, MinMatches: 10, Minutes: 11, Enabled: true},
	{ID: "buy_2", Title: "Купить 2 усиления", Metric: "shop_items_one", Category: "shop", Target: 2, Difficulty: questMedium, RewardShards: 4, RewardXP: 200, Minutes: 5, Enabled: true},
	{ID: "buy_3", Title: "Купить 3 усиления", Metric: "shop_items_one", Category: "shop", Target: 3, Difficulty: questHard, RewardShards: 5, RewardXP: 250, MinMatches: 20, Minutes: 7, Enabled: true},
	// Later wave: defined so the id and reward exist, never generated yet.
	{ID: "survive_win", Title: "Победить, не умерев", Metric: "survive_wins", Category: "survival", Target: 1, Difficulty: questHard, RewardShards: 5, RewardXP: 250, MinMatches: 10, Minutes: 12, Enabled: false},
}

func questTemplateByID(id string) *questTemplate {
	for index := range questTemplateRegistry {
		if questTemplateRegistry[index].ID == id {
			return &questTemplateRegistry[index]
		}
	}
	return nil
}

func questIsWinMetric(t questTemplate) bool {
	return t.Metric == "wins" || t.Metric == "fast_wins"
}

func questFilterTemplates(match func(questTemplate) bool) []questTemplate {
	filtered := make([]questTemplate, 0, len(questTemplateRegistry))
	for _, template := range questTemplateRegistry {
		if match(template) {
			filtered = append(filtered, template)
		}
	}
	return filtered
}

func questTemplateAvailable(t questTemplate, matchesPlayed int, novice bool, usedIDs, usedCategories map[string]bool) bool {
	if !t.Enabled {
		return false
	}
	if matchesPlayed < t.MinMatches {
		return false
	}
	if novice && questNoviceExcludedIDs[t.ID] {
		return false
	}
	if usedIDs != nil && usedIDs[t.ID] {
		return false
	}
	if usedCategories != nil && usedCategories[t.Category] {
		return false
	}
	return true
}

func questEstimateMinutes(templates []questTemplate) int {
	total := 0
	for _, template := range templates {
		total += template.Minutes
	}
	return total
}

// ------------------------------ time helpers ------------------------------

// questDayKey is the civil quest day a timestamp belongs to: 04:00 MSK starts
// a new day.
func questDayKey(t time.Time) string {
	return t.In(questZone).Add(-time.Duration(questDayResetHour) * time.Hour).Format(questDateLayout)
}

// questResetsAt is the Unix time of the next 04:00 MSK strictly after t.
func questResetsAt(t time.Time) int64 {
	local := t.In(questZone)
	reset := time.Date(local.Year(), local.Month(), local.Day(), questDayResetHour, 0, 0, 0, questZone)
	if !reset.After(local) {
		reset = reset.Add(24 * time.Hour)
	}
	return reset.Unix()
}

// questParseDay validates a YYYY-MM-DD quest day.
func questParseDay(day string) (time.Time, bool) {
	parsed, err := time.ParseInLocation(questDateLayout, day, questZone)
	if err != nil {
		return time.Time{}, false
	}
	return parsed, true
}

// questAddDays returns day+n, or "" for an invalid day.
func questAddDays(day string, n int) string {
	parsed, ok := questParseDay(day)
	if !ok {
		return ""
	}
	return parsed.AddDate(0, 0, n).Format(questDateLayout)
}

// questResetsAtForDay is 04:00 MSK of the following day.
func questResetsAtForDay(day string) int64 {
	parsed, ok := questParseDay(day)
	if !ok {
		return 0
	}
	return parsed.Add(time.Duration(questDayResetHour+24) * time.Hour).Unix()
}

// questWeekStart is the Monday of the week that contains day. Weeks run
// Monday 04:00 MSK -> Sunday 03:59 MSK, so the civil date of the Monday is the
// key.
func questWeekStart(day string) string {
	parsed, ok := questParseDay(day)
	if !ok {
		return ""
	}
	offset := (int(parsed.Weekday()) + 6) % 7 // Monday = 0
	return parsed.AddDate(0, 0, -offset).Format(questDateLayout)
}

// questWeeklyReward is the flat weekly prize: 300 shards for a 7/7 week, with
// no tier ladder, items, skins or ownership compensation.
func questWeeklyReward() int {
	return questWeeklyShardReward
}

// ------------------------------ deterministic rng ------------------------------

type questRNG struct {
	state uint64
}

// newQuestRNG seeds from fnv1a64("dq|pid|day"); rerollSeq shifts the stream so
// a reroll cannot return the same template by construction.
func newQuestRNG(playerID int64, day string, rerollSeq int) *questRNG {
	seed := questFNV1a64(fmt.Sprintf("dq|%d|%s", playerID, day))
	seed += uint64(rerollSeq) * 0x9E3779B97F4A7C15
	return &questRNG{state: seed}
}

func questRNGFromSeed(seed int64, rerollSeq, slot int) *questRNG {
	state := uint64(seed) + uint64(rerollSeq)*0x9E3779B97F4A7C15 + uint64(slot+1)*0xBF58476D1CE4E5B9
	return &questRNG{state: state}
}

func (rng *questRNG) next() uint64 {
	rng.state += 0x9E3779B97F4A7C15
	value := rng.state
	value = (value ^ (value >> 30)) * 0xBF58476D1CE4E5B9
	value = (value ^ (value >> 27)) * 0x94D049BB133111EB
	return value ^ (value >> 31)
}

func (rng *questRNG) intn(n int) int {
	if n <= 0 {
		return 0
	}
	return int(rng.next() % uint64(n))
}

func questFNV1a64(value string) uint64 {
	const (
		offset = 14695981039346656037
		prime  = 1099511628211
	)
	hash := uint64(offset)
	for index := 0; index < len(value); index++ {
		hash ^= uint64(value[index])
		hash *= prime
	}
	return hash
}

// questPickTemplate prefers medium templates three times out of four, so the
// daily sum stays near the 15-25 minute target without ever being impossible.
func questPickTemplate(rng *questRNG, pool []questTemplate) *questTemplate {
	if len(pool) == 0 {
		return nil
	}
	medium := make([]int, 0, len(pool))
	hard := make([]int, 0, len(pool))
	easy := make([]int, 0, len(pool))
	for index, template := range pool {
		switch template.Difficulty {
		case questHard:
			hard = append(hard, index)
		case questEasy:
			easy = append(easy, index)
		default:
			medium = append(medium, index)
		}
	}
	var chosen int
	switch {
	case len(medium) > 0 && len(hard) > 0:
		if rng.intn(4) == 0 {
			chosen = hard[rng.intn(len(hard))]
		} else {
			chosen = medium[rng.intn(len(medium))]
		}
	case len(medium) > 0:
		chosen = medium[rng.intn(len(medium))]
	case len(easy) > 0:
		chosen = easy[rng.intn(len(easy))]
	default:
		chosen = hard[rng.intn(len(hard))]
	}
	return &pool[chosen]
}

// ------------------------------ generation ------------------------------

// generateQuests builds exactly three deterministic quests for a player/day.
//
// Roles: slot 0 active (kills/damage), slot 1 steady (play_2, the guaranteed
// achievable easy quest), slot 2 flex (crystals/wins/shop/shells). The set
// always has three different templates, one template per category and exactly
// one easy quest; wins/fast wins appear at most once.
func generateQuests(playerID int64, day string, matchesPlayed int, rerollSeq int) []dailyQuest {
	if matchesPlayed < 0 {
		matchesPlayed = 0
	}
	if rerollSeq < 0 {
		rerollSeq = 0
	}
	rng := newQuestRNG(playerID, day, rerollSeq)
	novice := matchesPlayed < questNoviceMatches
	usedIDs := make(map[string]bool, questsPerDay)
	usedCategories := make(map[string]bool, questsPerDay)
	chosen := make([]questTemplate, questsPerDay)

	// Slot 1: the guaranteed easy quest. play_2 is always available (min 0
	// matches) and is the 7/7 safety net from the spec's risk list.
	steady := questTemplateByID("play_2")
	if steady == nil {
		steady = questTemplateByID("play_3")
	}
	if steady == nil {
		return nil
	}
	chosen[1] = *steady
	usedIDs[steady.ID] = true
	usedCategories[steady.Category] = true

	// Slot 0: combat. Medium/hard keeps the easy count at exactly one.
	active := questPickTemplate(rng, questFilterTemplates(func(t questTemplate) bool {
		return t.Difficulty != questEasy && (t.Category == "kills" || t.Category == "damage") &&
			questTemplateAvailable(t, matchesPlayed, novice, usedIDs, usedCategories)
	}))
	if active == nil {
		active = questPickTemplate(rng, questFilterTemplates(func(t questTemplate) bool {
			return t.Difficulty != questEasy && !questIsWinMetric(t) &&
				questTemplateAvailable(t, matchesPlayed, novice, usedIDs, usedCategories)
		}))
	}
	if active == nil {
		active = questPickTemplate(rng, questFilterTemplates(func(t questTemplate) bool {
			return t.Difficulty != questEasy &&
				questTemplateAvailable(t, matchesPlayed, novice, usedIDs, usedCategories)
		}))
	}
	if active == nil {
		active = questTemplateByID("damage_4000")
	}
	if active != nil {
		chosen[0] = *active
		usedIDs[active.ID] = true
		usedCategories[active.Category] = true
	}

	// Slot 2: flex. New category, and never a second win-metric quest.
	winUsed := questIsWinMetric(chosen[0]) || questIsWinMetric(chosen[1])
	flex := questPickTemplate(rng, questFilterTemplates(func(t questTemplate) bool {
		if winUsed && questIsWinMetric(t) {
			return false
		}
		return t.Difficulty != questEasy &&
			questTemplateAvailable(t, matchesPlayed, novice, usedIDs, usedCategories)
	}))
	if flex == nil {
		flex = questPickTemplate(rng, questFilterTemplates(func(t questTemplate) bool {
			return t.Difficulty == questEasy && !questIsWinMetric(t) &&
				questTemplateAvailable(t, matchesPlayed, novice, usedIDs, usedCategories)
		}))
	}
	if flex == nil {
		flex = questPickTemplate(rng, questFilterTemplates(func(t questTemplate) bool {
			return questTemplateAvailable(t, matchesPlayed, novice, usedIDs, usedCategories)
		}))
	}
	if flex == nil {
		flex = questTemplateByID("play_3")
	}
	if flex != nil {
		chosen[2] = *flex
	}

	// Keep the daily sum inside the 15-25 minute band: swap a hard quest for
	// the medium quest of the same category when the total is too long.
	if questEstimateMinutes(chosen) > questTargetMinutes {
		for index := range chosen {
			if chosen[index].Difficulty != questHard {
				continue
			}
			if lighter := questLighterAlternative(chosen[index], chosen, matchesPlayed, novice); lighter != nil {
				chosen[index] = *lighter
			}
		}
	}
	if chosen[0].ID == "" {
		if fallback := questTemplateByID("damage_4000"); fallback != nil {
			chosen[0] = *fallback
		}
	}

	quests := make([]dailyQuest, 0, questsPerDay)
	for slot, template := range chosen {
		if template.ID == "" {
			continue
		}
		quests = append(quests, questRowFromTemplate(slot, template))
	}
	return quests
}

// questLighterAlternative is the medium template of the same category, so a
// swap never changes the category layout.
func questLighterAlternative(current questTemplate, chosen []questTemplate, matchesPlayed int, novice bool) *questTemplate {
	usedIDs := make(map[string]bool, len(chosen))
	for _, template := range chosen {
		if template.ID != current.ID {
			usedIDs[template.ID] = true
		}
	}
	var best *questTemplate
	for index := range questTemplateRegistry {
		template := &questTemplateRegistry[index]
		if !template.Enabled || template.Category != current.Category || template.Difficulty != questMedium {
			continue
		}
		if template.ID == current.ID || usedIDs[template.ID] {
			continue
		}
		if matchesPlayed < template.MinMatches || (novice && questNoviceExcludedIDs[template.ID]) {
			continue
		}
		if best == nil || template.Minutes < best.Minutes {
			best = template
		}
	}
	return best
}

// ------------------------------ quest rows ------------------------------

type dailyQuest struct {
	Slot         int    `json:"slot"`
	TemplateID   string `json:"template_id"`
	Title        string `json:"title"`
	Metric       string `json:"metric"`
	Target       int    `json:"target"`
	Progress     int    `json:"progress"`
	Difficulty   string `json:"difficulty"`
	RewardShards int    `json:"reward_shards"`
	RewardXP     int    `json:"reward_xp"`
	Rerolled     bool   `json:"rerolled"`
	Completed    bool   `json:"completed"`
	CompletedAt  int64  `json:"completed_at,omitempty"`
}

func questRowFromTemplate(slot int, template questTemplate) dailyQuest {
	return dailyQuest{
		Slot:         slot,
		TemplateID:   template.ID,
		Title:        template.Title,
		Metric:       template.Metric,
		Target:       template.Target,
		Difficulty:   template.Difficulty,
		RewardShards: template.RewardShards,
		RewardXP:     template.RewardXP,
	}
}

func questTitleFor(templateID string) string {
	if template := questTemplateByID(templateID); template != nil {
		return template.Title
	}
	return ""
}

func questDifficultyFor(templateID string) string {
	if template := questTemplateByID(templateID); template != nil {
		return template.Difficulty
	}
	return ""
}

// questStorage is the subset of *sql.DB and *sql.Tx used here, so the same
// helpers run inside the match transaction and on the profile read path.
type questStorage interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

type dailyQuestDayState struct {
	Seed           int64
	RerollSeq      int
	FreeRerollUsed bool
	PaidRerolls    int
	CompletedCount int
	AllDoneBonus   bool
}

func questDayStateScan(row *sql.Row, state *dailyQuestDayState) error {
	return row.Scan(&state.Seed, &state.RerollSeq, &state.FreeRerollUsed,
		&state.PaidRerolls, &state.CompletedCount, &state.AllDoneBonus)
}

// ensureDailyQuests creates today's row and its three quests once. It is safe
// to call on every profile/quests read: existing rows are left untouched.
func ensureDailyQuests(ctx context.Context, db questStorage, playerID int64, day string) error {
	if db == nil || playerID <= 0 {
		return errors.New("invalid quest day request")
	}
	if _, ok := questParseDay(day); !ok {
		return errors.New("invalid quest day")
	}
	var matchesPlayed int
	if err := db.QueryRowContext(ctx,
		`SELECT COALESCE(matches_played, 0) FROM players WHERE id = $1`,
		playerID,
	).Scan(&matchesPlayed); err != nil {
		return err
	}
	seed := int64(questFNV1a64(fmt.Sprintf("dq|%d|%s", playerID, day)))
	rerollSeq := 0
	err := db.QueryRowContext(ctx, `
		INSERT INTO daily_quest_days (player_id, quest_day, seed)
		VALUES ($1, $2::date, $3)
		ON CONFLICT (player_id, quest_day) DO NOTHING
		RETURNING reroll_seq`, playerID, day, seed).Scan(&rerollSeq)
	if errors.Is(err, sql.ErrNoRows) {
		if err := db.QueryRowContext(ctx,
			`SELECT reroll_seq FROM daily_quest_days WHERE player_id = $1 AND quest_day = $2::date`,
			playerID, day,
		).Scan(&rerollSeq); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	var questCount int
	if err := db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM daily_quests WHERE player_id = $1 AND quest_day = $2::date`,
		playerID, day,
	).Scan(&questCount); err != nil {
		return err
	}
	if questCount >= questsPerDay {
		return nil
	}
	for _, quest := range generateQuests(playerID, day, matchesPlayed, rerollSeq) {
		if _, err := db.ExecContext(ctx, `
			INSERT INTO daily_quests
				(player_id, quest_day, slot, template_id, metric, target, progress, reward_shards, reward_xp)
			VALUES ($1, $2::date, $3, $4, $5, $6, 0, $7, $8)
			ON CONFLICT (player_id, quest_day, slot) DO NOTHING`,
			playerID, day, quest.Slot, quest.TemplateID, quest.Metric, quest.Target,
			quest.RewardShards, quest.RewardXP,
		); err != nil {
			return err
		}
	}
	return nil
}

func loadDailyQuestDay(ctx context.Context, db questStorage, playerID int64, day string) (dailyQuestDayState, error) {
	var state dailyQuestDayState
	err := questDayStateScan(db.QueryRowContext(ctx, `
		SELECT seed, reroll_seq, free_reroll_used, paid_rerolls, completed_count, all_done_bonus
		FROM daily_quest_days
		WHERE player_id = $1 AND quest_day = $2::date`, playerID, day), &state)
	return state, err
}

func loadDailyQuestDayForUpdate(ctx context.Context, db questStorage, playerID int64, day string) (dailyQuestDayState, error) {
	var state dailyQuestDayState
	err := questDayStateScan(db.QueryRowContext(ctx, `
		SELECT seed, reroll_seq, free_reroll_used, paid_rerolls, completed_count, all_done_bonus
		FROM daily_quest_days
		WHERE player_id = $1 AND quest_day = $2::date
		FOR UPDATE`, playerID, day), &state)
	return state, err
}

func loadDailyQuests(ctx context.Context, db questStorage, playerID int64, day string) ([]dailyQuest, error) {
	rows, err := db.QueryContext(ctx, `
		SELECT slot, template_id, metric, target, progress, reward_shards, reward_xp,
		       rerolled, COALESCE(EXTRACT(EPOCH FROM completed_at)::bigint, 0)
		FROM daily_quests
		WHERE player_id = $1 AND quest_day = $2::date
		ORDER BY slot`, playerID, day)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	quests := make([]dailyQuest, 0, questsPerDay)
	for rows.Next() {
		var quest dailyQuest
		if err := rows.Scan(&quest.Slot, &quest.TemplateID, &quest.Metric, &quest.Target,
			&quest.Progress, &quest.RewardShards, &quest.RewardXP, &quest.Rerolled,
			&quest.CompletedAt); err != nil {
			return nil, err
		}
		quest.Title = questTitleFor(quest.TemplateID)
		quest.Difficulty = questDifficultyFor(quest.TemplateID)
		quest.Completed = quest.CompletedAt > 0
		quests = append(quests, quest)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return quests, nil
}

// ------------------------------ weekly helpers ------------------------------

type questWeekSummary struct {
	ActiveDays  int    `json:"active_days"`
	Required    int    `json:"required"`
	Tier        int    `json:"tier"`
	RewardKind  string `json:"reward_kind"`
	RewardValue int    `json:"reward_value"`
	Claimable   bool   `json:"claimable"`
	Claimed     bool   `json:"claimed"`
}

// questDayClosed reports whether a day counts toward the strict 7/7 week.
// A day is closed only when all three daily quests are complete.
func questDayClosed(completedCount int) bool {
	return completedCount >= questsPerDay
}

// questWeekClaimable is the single 7/7 claim rule: seven closed days and no
// grant for this week yet.
func questWeekClaimable(activeDays int, claimed bool) bool {
	return activeDays >= questWeekDays && !claimed
}

// questWeekActiveDaysFromCounts counts closed days in a week's worth of
// per-day completion counters (used by tests and the week view).
func questWeekActiveDaysFromCounts(completedCounts []int) int {
	activeDays := 0
	for _, completedCount := range completedCounts {
		if questDayClosed(completedCount) {
			activeDays++
		}
	}
	return activeDays
}

type questWeekReward struct {
	Kind   string `json:"kind"`
	Shards int    `json:"shards"`
}

type questWeekDay struct {
	Day            string `json:"day"`
	Completed      int    `json:"completed"`
	CompletedCount int    `json:"completed_count"`
	Total          int    `json:"total"`
	Closed         bool   `json:"closed"`
	Active         bool   `json:"active"`
	Today          bool   `json:"today"`
	Future         bool   `json:"future"`
}

type questPreviousWeek struct {
	Start       string          `json:"start"`
	ActiveDays  int             `json:"active_days"`
	Required    int             `json:"required"`
	Tier        int             `json:"tier"`
	RewardKind  string          `json:"reward_kind"`
	RewardValue int             `json:"reward_value"`
	Reward      questWeekReward `json:"reward"`
	Claimable   bool            `json:"claimable"`
	Claimed     bool            `json:"claimed"`
}

type questWeekView struct {
	Start       string            `json:"start"`
	Days        []questWeekDay    `json:"days"`
	ActiveDays  int               `json:"active_days"`
	Required    int               `json:"required"`
	Tier        int               `json:"tier"`
	RewardKind  string            `json:"reward_kind"`
	RewardValue int               `json:"reward_value"`
	Reward      questWeekReward   `json:"reward"`
	Claimable   bool              `json:"claimable"`
	Claimed     bool              `json:"claimed"`
	Missed      int               `json:"missed"`
	Previous    questPreviousWeek `json:"previous"`
}

// questWeekRewardView is the constant weekly reward block.
func questWeekRewardView() questWeekReward {
	return questWeekReward{Kind: "shards", Shards: questWeeklyReward()}
}

func questWeekActiveDays(ctx context.Context, db questStorage, playerID int64, weekStart string) (int, error) {
	var activeDays int
	err := db.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM daily_quest_days
		WHERE player_id = $1
		  AND quest_day >= $2::date
		  AND quest_day < $2::date + 7
		  AND completed_count >= $3`, playerID, weekStart, questsPerDay).Scan(&activeDays)
	return activeDays, err
}

func questWeekClaimed(ctx context.Context, db questStorage, playerID int64, weekStart string) (bool, error) {
	var claimed bool
	err := db.QueryRowContext(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM weekly_grants WHERE player_id = $1 AND week_start = $2::date
		)`, playerID, weekStart).Scan(&claimed)
	return claimed, err
}

func buildQuestWeekSummary(ctx context.Context, db questStorage, playerID int64, day string) (questWeekSummary, error) {
	weekStart := questWeekStart(day)
	if weekStart == "" {
		return questWeekSummary{}, errors.New("invalid quest day")
	}
	tier := 1
	reward := questWeekRewardView()
	activeDays, err := questWeekActiveDays(ctx, db, playerID, weekStart)
	if err != nil {
		return questWeekSummary{}, err
	}
	claimed, err := questWeekClaimed(ctx, db, playerID, weekStart)
	if err != nil {
		return questWeekSummary{}, err
	}
	return questWeekSummary{
		ActiveDays:  activeDays,
		Required:    questWeekDays,
		Tier:        tier,
		RewardKind:  reward.Kind,
		RewardValue: reward.Shards,
		Claimable:   questWeekClaimable(activeDays, claimed),
		Claimed:     claimed,
	}, nil
}

func buildQuestWeekView(ctx context.Context, db questStorage, playerID int64, day string) (questWeekView, error) {
	weekStart := questWeekStart(day)
	if weekStart == "" {
		return questWeekView{}, errors.New("invalid quest day")
	}
	tier := 1
	reward := questWeekRewardView()
	today := questDayKey(time.Now())

	rows, err := db.QueryContext(ctx, `
		SELECT d.quest_day::text, d.completed_count,
		       (SELECT COUNT(*) FROM daily_quests q
		         WHERE q.player_id = d.player_id AND q.quest_day = d.quest_day)
		FROM daily_quest_days d
		WHERE d.player_id = $1
		  AND d.quest_day >= $2::date
		  AND d.quest_day < $2::date + 7`, playerID, weekStart)
	if err != nil {
		return questWeekView{}, err
	}
	type dayCounters struct {
		completed int
		total     int
	}
	counters := make(map[string]dayCounters, questWeekDays)
	for rows.Next() {
		var dayKey string
		var countersForDay dayCounters
		if err := rows.Scan(&dayKey, &countersForDay.completed, &countersForDay.total); err != nil {
			rows.Close()
			return questWeekView{}, err
		}
		counters[dayKey] = countersForDay
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return questWeekView{}, err
	}
	rows.Close()

	days := make([]questWeekDay, 0, questWeekDays)
	missed := 0
	activeDays := 0
	for index := 0; index < questWeekDays; index++ {
		dayKey := questAddDays(weekStart, index)
		counter := counters[dayKey]
		closed := questDayClosed(counter.completed)
		if closed {
			activeDays++
		}
		future := dayKey > today
		if !closed && dayKey < today {
			missed++
		}
		days = append(days, questWeekDay{
			Day:            dayKey,
			Completed:      counter.completed,
			CompletedCount: counter.completed,
			Total:          counter.total,
			Closed:         closed,
			Active:         closed,
			Today:          dayKey == today,
			Future:         future,
		})
	}
	claimed, err := questWeekClaimed(ctx, db, playerID, weekStart)
	if err != nil {
		return questWeekView{}, err
	}

	previousStart := questAddDays(weekStart, -7)
	previousTier := 1
	previousReward := questWeekRewardView()
	previousActiveDays, err := questWeekActiveDays(ctx, db, playerID, previousStart)
	if err != nil {
		return questWeekView{}, err
	}
	previousClaimed, err := questWeekClaimed(ctx, db, playerID, previousStart)
	if err != nil {
		return questWeekView{}, err
	}

	return questWeekView{
		Start:       weekStart,
		Days:        days,
		ActiveDays:  activeDays,
		Required:    questWeekDays,
		Tier:        tier,
		RewardKind:  reward.Kind,
		RewardValue: reward.Shards,
		Reward:      reward,
		Claimable:   questWeekClaimable(activeDays, claimed),
		Claimed:     claimed,
		Missed:      missed,
		Previous: questPreviousWeek{
			Start:       previousStart,
			ActiveDays:  previousActiveDays,
			Required:    questWeekDays,
			Tier:        previousTier,
			RewardKind:  previousReward.Kind,
			RewardValue: previousReward.Shards,
			Reward:      previousReward,
			Claimable:   questWeekClaimable(previousActiveDays, previousClaimed),
			Claimed:     previousClaimed,
		},
	}, nil
}

// ------------------------------ daily summary (/profile) ------------------------------

type dailySummary struct {
	Completed int              `json:"completed"`
	Total     int              `json:"total"`
	ResetsAt  int64            `json:"resets_at"`
	Week      questWeekSummary `json:"week"`
}

// buildDailySummary is the compact block embedded into /profile. It always
// uses the current quest day. It returns nil on error (the profile keeps
// working without the quest block).
func buildDailySummary(ctx context.Context, db *sql.DB, playerID int64) (*dailySummary, error) {
	if db == nil {
		return nil, errors.New("nil database")
	}
	transaction, err := db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer transaction.Rollback()
	summary, err := buildDailySummaryTx(ctx, transaction, playerID, questDayKey(time.Now()))
	if err != nil {
		return nil, err
	}
	if err := transaction.Commit(); err != nil {
		return nil, err
	}
	return &summary, nil
}

func buildDailySummaryTx(ctx context.Context, db questStorage, playerID int64, day string) (dailySummary, error) {
	if err := ensureDailyQuests(ctx, db, playerID, day); err != nil {
		return dailySummary{}, err
	}
	state, err := loadDailyQuestDay(ctx, db, playerID, day)
	if err != nil {
		return dailySummary{}, err
	}
	week, err := buildQuestWeekSummary(ctx, db, playerID, day)
	if err != nil {
		return dailySummary{}, err
	}
	return dailySummary{
		Completed: state.CompletedCount,
		Total:     questsPerDay,
		ResetsAt:  questResetsAtForDay(day),
		Week:      week,
	}, nil
}

// ------------------------------ progress ------------------------------

// questPerMatchCap is floor(60% of target), at least one point.
func questPerMatchCap(target int) int {
	if target <= 0 {
		return 0
	}
	limit := target * questProgressPercent / 100
	if limit < 1 {
		limit = 1
	}
	if limit > target {
		limit = target
	}
	return limit
}

func questClampNonNegative(value int) int {
	if value < 0 {
		return 0
	}
	return value
}

func questMinInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func questMaxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

// questProgressAfterMatch applies one validated match to one quest metric.
// Cumulative metrics are capped at 60% of the target per match; "one match"
// metrics (max kills, shop purchases) keep the best single-match value.
func questProgressAfterMatch(metric string, target, progress int, stats matchStats) int {
	if target <= 0 {
		return progress
	}
	if progress < 0 {
		progress = 0
	}
	if progress > target {
		progress = target
	}
	cap := questPerMatchCap(target)
	accumulate := func(value int) int {
		return questMinInt(target, progress+questMinInt(questClampNonNegative(value), cap))
	}
	switch metric {
	case "kills":
		return accumulate(stats.kills)
	case "damage":
		return accumulate(stats.damage)
	case "crystals":
		return accumulate(stats.crystals)
	case "shells":
		return accumulate(stats.shells)
	case "matches":
		return questMinInt(target, progress+1)
	case "wins":
		if stats.won {
			return questMinInt(target, progress+1)
		}
	case "fast_wins":
		if stats.won && stats.durationSec <= questFastWinSeconds {
			return questMinInt(target, progress+1)
		}
	case "max_kills_one":
		return questMinInt(target, questMaxInt(progress, questClampNonNegative(stats.kills)))
	case "shop_items_one":
		return questMinInt(target, questMaxInt(progress, questClampNonNegative(stats.shopItems)))
	case "survive_wins":
		if stats.won && stats.deaths == 0 {
			return questMinInt(target, progress+1)
		}
	}
	return progress
}

// questMatchQualifies ignores sub-90-second matches: they cannot be used to
// farm quest progress.
func questMatchQualifies(stats matchStats) bool {
	return stats.durationSec >= questMinMatchSeconds
}

// questAllDoneBonus is paid once per day when all three quests are done.
func questAllDoneBonus(completedCount int, alreadyPaid bool) int {
	if alreadyPaid || completedCount < questsPerDay {
		return 0
	}
	return questAllDoneBonusShards
}

// applyQuestProgress moves today's quests with one saved match result and pays
// completed quests (and the all-done bonus) inside the match transaction.
// A short match and an unknown player are not errors: the match is saved.
func applyQuestProgress(tx *sql.Tx, playerID int64, stats matchStats) error {
	if tx == nil || playerID <= 0 || !questMatchQualifies(stats) {
		return nil
	}
	ctx := context.Background()
	day := questDayKey(time.Now())
	if err := ensureDailyQuests(ctx, tx, playerID, day); err != nil {
		return err
	}
	state, err := loadDailyQuestDayForUpdate(ctx, tx, playerID, day)
	if err != nil {
		return err
	}
	quests, err := loadDailyQuests(ctx, tx, playerID, day)
	if err != nil {
		return err
	}

	awardShards := 0
	awardXP := 0
	completedNow := 0
	for index := range quests {
		quest := &quests[index]
		if quest.Completed {
			continue
		}
		next := questProgressAfterMatch(quest.Metric, quest.Target, quest.Progress, stats)
		completed := next >= quest.Target && quest.Target > 0
		if next == quest.Progress && !completed {
			continue
		}
		if completed {
			next = quest.Target
		}
		if _, err := tx.ExecContext(ctx, `
			UPDATE daily_quests
			SET progress = $4,
			    completed_at = CASE WHEN $5 THEN NOW() ELSE completed_at END
			WHERE player_id = $1 AND quest_day = $2::date AND slot = $3`,
			playerID, day, quest.Slot, next, completed,
		); err != nil {
			return err
		}
		quest.Progress = next
		if completed {
			quest.Completed = true
			awardShards += quest.RewardShards
			awardXP += quest.RewardXP
			completedNow++
		}
	}

	completedCount := questMinInt(questsPerDay, state.CompletedCount+completedNow)
	bonus := questAllDoneBonus(completedCount, state.AllDoneBonus)
	allDone := state.AllDoneBonus || bonus > 0
	if completedNow > 0 {
		if _, err := tx.ExecContext(ctx, `
			UPDATE daily_quest_days
			SET completed_count = $3, all_done_bonus = $4
			WHERE player_id = $1 AND quest_day = $2::date`,
			playerID, day, completedCount, allDone,
		); err != nil {
			return err
		}
	}

	if awardXP > 0 && validCharacterKey(stats.classKey) {
		_, _, _, levelUpShards, err := applyCharacterXP(ctx, tx, playerID, stats.classKey, awardXP)
		if err != nil {
			return err
		}
		awardShards += levelUpShards
	}
	payout := awardShards + bonus
	if payout > 0 {
		if _, err := tx.ExecContext(ctx,
			`UPDATE players SET sky_shards = COALESCE(sky_shards, 0) + $1 WHERE id = $2`,
			payout, playerID,
		); err != nil {
			return err
		}
	}
	return nil
}

// ------------------------------ reroll ------------------------------

// questRerollMode decides what a reroll costs: the free one first, then up to
// two paid rerolls for one shard each.
func questRerollMode(freeUsed bool, paidRerolls int) (string, int) {
	if !freeUsed {
		return "free", 0
	}
	if paidRerolls < questPaidRerolls {
		return "paid", questPaidRerollCost
	}
	return "", 0
}

// questPickReroll returns a replacement for one slot. It never returns the
// current template or a template already used by another slot, preserves the
// category (and difficulty when possible), and keeps the one-win rule.
func questPickReroll(rng *questRNG, current dailyQuest, quests []dailyQuest, matchesPlayed int, novice bool) *questTemplate {
	usedIDs := make(map[string]bool, len(quests))
	usedCategories := make(map[string]bool, len(quests))
	winUsed := false
	for _, quest := range quests {
		if quest.Slot == current.Slot {
			continue
		}
		usedIDs[quest.TemplateID] = true
		if template := questTemplateByID(quest.TemplateID); template != nil {
			usedCategories[template.Category] = true
		} else if quest.Metric == "wins" || quest.Metric == "fast_wins" {
			usedCategories["wins"] = true
			winUsed = true
		}
		if quest.Metric == "wins" || quest.Metric == "fast_wins" {
			winUsed = true
		}
	}
	currentTemplate := questTemplateByID(current.TemplateID)
	if currentTemplate == nil {
		currentTemplate = &questTemplate{
			ID:         current.TemplateID,
			Metric:     current.Metric,
			Category:   questCategoryForMetric(current.Metric),
			Difficulty: current.Difficulty,
		}
	}
	base := func(t questTemplate) bool {
		if t.ID == current.TemplateID || usedIDs[t.ID] || !t.Enabled {
			return false
		}
		if matchesPlayed < t.MinMatches {
			return false
		}
		if novice && questNoviceExcludedIDs[t.ID] {
			return false
		}
		if winUsed && questIsWinMetric(t) {
			return false
		}
		return true
	}
	// Keep the "exactly one easy quest" invariant: a medium/hard slot never
	// rerolls into an easy template. The final pool drops this guard only when
	// the pool is otherwise empty.
	keepDifficulty := func(t questTemplate) bool {
		return currentTemplate.Difficulty == questEasy || t.Difficulty != questEasy
	}
	guarded := func(t questTemplate) bool {
		return base(t) && keepDifficulty(t)
	}
	pools := [][]questTemplate{
		questFilterTemplates(func(t questTemplate) bool {
			return guarded(t) && t.Category == currentTemplate.Category && t.Difficulty == currentTemplate.Difficulty
		}),
		questFilterTemplates(func(t questTemplate) bool {
			return guarded(t) && t.Category == currentTemplate.Category
		}),
		questFilterTemplates(func(t questTemplate) bool {
			return guarded(t) && t.Difficulty == currentTemplate.Difficulty && !usedCategories[t.Category]
		}),
		questFilterTemplates(guarded),
		questFilterTemplates(base),
	}
	for _, pool := range pools {
		if picked := questPickTemplate(rng, pool); picked != nil {
			return picked
		}
	}
	return nil
}

func questCategoryForMetric(metric string) string {
	switch metric {
	case "kills", "max_kills_one":
		return "kills"
	case "damage":
		return "damage"
	case "crystals":
		return "crystals"
	case "shells":
		return "shells"
	case "matches":
		return "matches"
	case "wins":
		return "wins"
	case "fast_wins":
		return "fast_wins"
	case "shop_items_one":
		return "shop"
	default:
		return metric
	}
}

// ------------------------------ HTTP API ------------------------------

type questRerollState struct {
	FreeUsed      bool `json:"free_used"`
	Free          bool `json:"free"`
	PaidUsed      int  `json:"paid_used"`
	Paid          int  `json:"paid"`
	PaidMax       int  `json:"paid_max"`
	PaidRemaining int  `json:"paid_remaining"`
	Remaining     int  `json:"remaining"`
	Total         int  `json:"total"`
	Cost          int  `json:"cost"`
	FreeAvailable bool `json:"free_available"`
}

func questRerollStateFrom(state dailyQuestDayState) questRerollState {
	freeAvailable := !state.FreeRerollUsed
	paidRemaining := questPaidRerolls - state.PaidRerolls
	if paidRemaining < 0 {
		paidRemaining = 0
	}
	remaining := paidRemaining
	if freeAvailable {
		remaining++
	}
	return questRerollState{
		FreeUsed:      state.FreeRerollUsed,
		Free:          freeAvailable,
		PaidUsed:      state.PaidRerolls,
		Paid:          state.PaidRerolls,
		PaidMax:       questPaidRerolls,
		PaidRemaining: paidRemaining,
		Remaining:     remaining,
		Total:         questFreeRerolls + questPaidRerolls,
		Cost:          questPaidRerollCost,
		FreeAvailable: freeAvailable,
	}
}

type questToday struct {
	Completed    int  `json:"completed"`
	Total        int  `json:"total"`
	AllDoneBonus bool `json:"all_done_bonus"`
}

type questsResponse struct {
	Success  bool             `json:"success"`
	Day      string           `json:"day"`
	ResetsAt int64            `json:"resets_at"`
	Quests   []dailyQuest     `json:"quests"`
	Rerolls  questRerollState `json:"rerolls"`
	Today    questToday       `json:"today"`
	Week     questWeekView    `json:"week"`
	Error    string           `json:"error,omitempty"`
}

func (service *api) handleQuests(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeJSON(w, http.StatusMethodNotAllowed, questsResponse{Error: "Method not allowed"})
		return
	}
	playerID, err := strconv.ParseInt(strings.TrimSpace(r.URL.Query().Get("player_id")), 10, 64)
	if err != nil || playerID <= 0 {
		writeJSON(w, http.StatusBadRequest, questsResponse{Error: "Invalid player ID"})
		return
	}
	if !service.requireSession(w, r, playerID) {
		return
	}
	transaction, err := service.db.BeginTx(r.Context(), nil)
	if err != nil {
		log.Printf("begin quests: %v", err)
		writeJSON(w, http.StatusInternalServerError, questsResponse{Error: "Internal server error"})
		return
	}
	defer transaction.Rollback()

	day := questDayKey(time.Now())
	if err := ensureDailyQuests(r.Context(), transaction, playerID, day); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeJSON(w, http.StatusNotFound, questsResponse{Error: "Player not found"})
			return
		}
		log.Printf("ensure daily quests player=%d: %v", playerID, err)
		writeJSON(w, http.StatusInternalServerError, questsResponse{Error: "Internal server error"})
		return
	}
	state, err := loadDailyQuestDay(r.Context(), transaction, playerID, day)
	if err != nil {
		log.Printf("load quest day player=%d: %v", playerID, err)
		writeJSON(w, http.StatusInternalServerError, questsResponse{Error: "Internal server error"})
		return
	}
	quests, err := loadDailyQuests(r.Context(), transaction, playerID, day)
	if err != nil {
		log.Printf("load daily quests player=%d: %v", playerID, err)
		writeJSON(w, http.StatusInternalServerError, questsResponse{Error: "Internal server error"})
		return
	}
	week, err := buildQuestWeekView(r.Context(), transaction, playerID, day)
	if err != nil {
		log.Printf("load quest week player=%d: %v", playerID, err)
		writeJSON(w, http.StatusInternalServerError, questsResponse{Error: "Internal server error"})
		return
	}
	if err := transaction.Commit(); err != nil {
		log.Printf("commit quests player=%d: %v", playerID, err)
		writeJSON(w, http.StatusInternalServerError, questsResponse{Error: "Internal server error"})
		return
	}
	writeJSON(w, http.StatusOK, questsResponse{
		Success:  true,
		Day:      day,
		ResetsAt: questResetsAtForDay(day),
		Quests:   quests,
		Rerolls:  questRerollStateFrom(state),
		Today: questToday{
			Completed:    state.CompletedCount,
			Total:        questsPerDay,
			AllDoneBonus: state.AllDoneBonus,
		},
		Week: week,
	})
}

type questRerollRequest struct {
	PlayerID          int64  `json:"player_id"`
	Day               string `json:"day"`
	Slot              int    `json:"slot"`
	CurrentTemplateID string `json:"current_template_id"`
}

type questRerollResponse struct {
	Success   bool             `json:"success"`
	Day       string           `json:"day"`
	Quest     dailyQuest       `json:"quest"`
	Rerolls   questRerollState `json:"rerolls"`
	NewShards int              `json:"new_shards,omitempty"`
	Error     string           `json:"error,omitempty"`
}

func (service *api) handleQuestReroll(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if !requirePost(w, r) {
		return
	}
	var request questRerollRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, questRerollResponse{Error: "Invalid JSON"})
		return
	}
	if request.PlayerID <= 0 || request.Slot < 0 || request.Slot >= questsPerDay ||
		strings.TrimSpace(request.CurrentTemplateID) == "" {
		writeJSON(w, http.StatusBadRequest, questRerollResponse{Error: "Invalid reroll"})
		return
	}
	if !service.requireSession(w, r, request.PlayerID) {
		return
	}
	today := questDayKey(time.Now())
	day := strings.TrimSpace(request.Day)
	if day == "" {
		day = today
	}
	if _, ok := questParseDay(day); !ok {
		writeJSON(w, http.StatusBadRequest, questRerollResponse{Error: "Invalid quest day"})
		return
	}
	if day != today {
		writeJSON(w, http.StatusConflict, questRerollResponse{Error: "Quest day is closed"})
		return
	}

	transaction, err := service.db.BeginTx(r.Context(), nil)
	if err != nil {
		log.Printf("begin quest reroll: %v", err)
		writeJSON(w, http.StatusInternalServerError, questRerollResponse{Error: "Internal server error"})
		return
	}
	defer transaction.Rollback()

	state, err := loadDailyQuestDayForUpdate(r.Context(), transaction, request.PlayerID, day)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, questRerollResponse{Error: "Quest day not found"})
		return
	}
	if err != nil {
		log.Printf("load quest day for reroll player=%d: %v", request.PlayerID, err)
		writeJSON(w, http.StatusInternalServerError, questRerollResponse{Error: "Internal server error"})
		return
	}
	quests, err := loadDailyQuests(r.Context(), transaction, request.PlayerID, day)
	if err != nil {
		log.Printf("load daily quests for reroll player=%d: %v", request.PlayerID, err)
		writeJSON(w, http.StatusInternalServerError, questRerollResponse{Error: "Internal server error"})
		return
	}
	var current *dailyQuest
	for index := range quests {
		if quests[index].Slot == request.Slot {
			current = &quests[index]
			break
		}
	}
	if current == nil {
		writeJSON(w, http.StatusNotFound, questRerollResponse{Error: "Quest not found"})
		return
	}
	if current.Completed {
		writeJSON(w, http.StatusConflict, questRerollResponse{Error: "Quest already completed"})
		return
	}
	// current_template_id is the double-tap guard: a second request carries
	// the old template and must not spend another reroll.
	if current.TemplateID != strings.TrimSpace(request.CurrentTemplateID) {
		writeJSON(w, http.StatusConflict, questRerollResponse{Error: "Quest changed"})
		return
	}
	mode, cost := questRerollMode(state.FreeRerollUsed, state.PaidRerolls)
	if mode == "" {
		writeJSON(w, http.StatusConflict, questRerollResponse{Error: "No rerolls left"})
		return
	}

	newShards := 0
	if mode == "paid" {
		var shards int
		err := transaction.QueryRowContext(r.Context(),
			`SELECT COALESCE(sky_shards, 0) FROM players WHERE id = $1 FOR UPDATE`,
			request.PlayerID).Scan(&shards)
		if errors.Is(err, sql.ErrNoRows) {
			writeJSON(w, http.StatusNotFound, questRerollResponse{Error: "Player not found"})
			return
		}
		if err != nil {
			log.Printf("load shards for reroll player=%d: %v", request.PlayerID, err)
			writeJSON(w, http.StatusInternalServerError, questRerollResponse{Error: "Internal server error"})
			return
		}
		if shards < cost {
			writeJSON(w, http.StatusPaymentRequired, questRerollResponse{Error: "Not enough shards"})
			return
		}
		if _, err := transaction.ExecContext(r.Context(),
			`UPDATE players SET sky_shards = COALESCE(sky_shards, 0) - $1 WHERE id = $2`,
			cost, request.PlayerID); err != nil {
			log.Printf("charge quest reroll player=%d: %v", request.PlayerID, err)
			writeJSON(w, http.StatusInternalServerError, questRerollResponse{Error: "Internal server error"})
			return
		}
		newShards = shards - cost
	}

	var matchesPlayed int
	if err := transaction.QueryRowContext(r.Context(),
		`SELECT COALESCE(matches_played, 0) FROM players WHERE id = $1`,
		request.PlayerID).Scan(&matchesPlayed); err != nil {
		log.Printf("load matches for reroll player=%d: %v", request.PlayerID, err)
		writeJSON(w, http.StatusInternalServerError, questRerollResponse{Error: "Internal server error"})
		return
	}
	novice := matchesPlayed < questNoviceMatches
	replacement := questPickReroll(
		questRNGFromSeed(state.Seed, state.RerollSeq, request.Slot),
		*current, quests, matchesPlayed, novice,
	)
	if replacement == nil {
		writeJSON(w, http.StatusConflict, questRerollResponse{Error: "No replacement available"})
		return
	}
	if _, err := transaction.ExecContext(r.Context(), `
		UPDATE daily_quests
		SET template_id = $4, metric = $5, target = $6, progress = 0,
		    reward_shards = $7, reward_xp = $8, rerolled = TRUE, completed_at = NULL
		WHERE player_id = $1 AND quest_day = $2::date AND slot = $3`,
		request.PlayerID, day, request.Slot, replacement.ID, replacement.Metric,
		replacement.Target, replacement.RewardShards, replacement.RewardXP,
	); err != nil {
		log.Printf("reroll quest player=%d slot=%d: %v", request.PlayerID, request.Slot, err)
		writeJSON(w, http.StatusInternalServerError, questRerollResponse{Error: "Internal server error"})
		return
	}
	freeUsed := state.FreeRerollUsed || mode == "free"
	paidRerolls := state.PaidRerolls
	if mode == "paid" {
		paidRerolls++
	}
	if _, err := transaction.ExecContext(r.Context(), `
		UPDATE daily_quest_days
		SET reroll_seq = $3, free_reroll_used = $4, paid_rerolls = $5
		WHERE player_id = $1 AND quest_day = $2::date`,
		request.PlayerID, day, state.RerollSeq+1, freeUsed, paidRerolls,
	); err != nil {
		log.Printf("save quest reroll player=%d: %v", request.PlayerID, err)
		writeJSON(w, http.StatusInternalServerError, questRerollResponse{Error: "Internal server error"})
		return
	}
	if err := transaction.Commit(); err != nil {
		log.Printf("commit quest reroll player=%d: %v", request.PlayerID, err)
		writeJSON(w, http.StatusInternalServerError, questRerollResponse{Error: "Internal server error"})
		return
	}

	state.FreeRerollUsed = freeUsed
	state.PaidRerolls = paidRerolls
	state.RerollSeq++
	writeJSON(w, http.StatusOK, questRerollResponse{
		Success:   true,
		Day:       day,
		Quest:     questRowFromTemplate(request.Slot, *replacement),
		Rerolls:   questRerollStateFrom(state),
		NewShards: newShards,
	})
}

type weeklyClaimRequest struct {
	PlayerID  int64  `json:"player_id"`
	WeekStart string `json:"week_start"`
	ItemID    int    `json:"item_id"`
}

type weeklyClaimResponse struct {
	Success        bool   `json:"success"`
	AlreadyClaimed bool   `json:"already_claimed,omitempty"`
	Tier           int    `json:"tier"`
	RewardKind     string `json:"reward_kind"`
	ItemID         int    `json:"item_id"`
	Shards         int    `json:"shards"`
	NewShards      int    `json:"new_shards,omitempty"`
	Error          string `json:"error,omitempty"`
}

func (service *api) handleWeeklyClaim(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if !requirePost(w, r) {
		return
	}
	var request weeklyClaimRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, weeklyClaimResponse{Error: "Invalid JSON"})
		return
	}
	if request.PlayerID <= 0 {
		writeJSON(w, http.StatusBadRequest, weeklyClaimResponse{Error: "Invalid claim"})
		return
	}
	weekStart := strings.TrimSpace(request.WeekStart)
	if _, ok := questParseDay(weekStart); !ok || questWeekStart(weekStart) != weekStart {
		writeJSON(w, http.StatusBadRequest, weeklyClaimResponse{Error: "Invalid week start"})
		return
	}
	if !service.requireSession(w, r, request.PlayerID) {
		return
	}
	currentWeek := questWeekStart(questDayKey(time.Now()))
	previousWeek := questAddDays(currentWeek, -7)
	if weekStart != currentWeek && weekStart != previousWeek {
		writeJSON(w, http.StatusConflict, weeklyClaimResponse{Error: "Week is closed"})
		return
	}

	transaction, err := service.db.BeginTx(r.Context(), nil)
	if err != nil {
		log.Printf("begin weekly claim: %v", err)
		writeJSON(w, http.StatusInternalServerError, weeklyClaimResponse{Error: "Internal server error"})
		return
	}
	defer transaction.Rollback()

	// A claim is idempotent: an existing grant is reported, never paid twice.
	var grantedTier, grantedItem, grantedShards int
	var grantedKind string
	err = transaction.QueryRowContext(r.Context(), `
		SELECT tier, reward_kind, item_id, shards
		FROM weekly_grants
		WHERE player_id = $1 AND week_start = $2::date`,
		request.PlayerID, weekStart).Scan(&grantedTier, &grantedKind, &grantedItem, &grantedShards)
	if err == nil {
		if err := transaction.Commit(); err != nil {
			log.Printf("commit weekly claim read: %v", err)
			writeJSON(w, http.StatusInternalServerError, weeklyClaimResponse{Error: "Internal server error"})
			return
		}
		writeJSON(w, http.StatusOK, weeklyClaimResponse{
			Success:        true,
			AlreadyClaimed: true,
			Tier:           grantedTier,
			RewardKind:     grantedKind,
			ItemID:         grantedItem,
			Shards:         grantedShards,
		})
		return
	}
	if !errors.Is(err, sql.ErrNoRows) {
		log.Printf("load weekly grant player=%d: %v", request.PlayerID, err)
		writeJSON(w, http.StatusInternalServerError, weeklyClaimResponse{Error: "Internal server error"})
		return
	}

	activeDays, err := questWeekActiveDays(r.Context(), transaction, request.PlayerID, weekStart)
	if err != nil {
		log.Printf("count weekly active days player=%d: %v", request.PlayerID, err)
		writeJSON(w, http.StatusInternalServerError, weeklyClaimResponse{Error: "Internal server error"})
		return
	}
	if !questWeekClaimable(activeDays, false) {
		writeJSON(w, http.StatusConflict, weeklyClaimResponse{
			Error: fmt.Sprintf("Week is not complete: %d/%d", activeDays, questWeekDays),
		})
		return
	}

	// Flat weekly prize: 300 shards for any 7/7 week, no ladder or items.
	tier := 1
	rewardKind := "shards"
	itemID := 0
	shardGrant := questWeeklyReward()

	var shards int
	err = transaction.QueryRowContext(r.Context(),
		`SELECT COALESCE(sky_shards, 0) FROM players WHERE id = $1 FOR UPDATE`,
		request.PlayerID).Scan(&shards)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, weeklyClaimResponse{Error: "Player not found"})
		return
	}
	if err != nil {
		log.Printf("load player for weekly claim: %v", err)
		writeJSON(w, http.StatusInternalServerError, weeklyClaimResponse{Error: "Internal server error"})
		return
	}

	// The primary key of weekly_grants is the idempotency guard. Insert first,
	// then grant, so a crash between the two never pays twice.
	result, err := transaction.ExecContext(r.Context(), `
		INSERT INTO weekly_grants (player_id, week_start, tier, reward_kind, item_id, shards)
		VALUES ($1, $2::date, $3, $4, $5, $6)
		ON CONFLICT (player_id, week_start) DO NOTHING`,
		request.PlayerID, weekStart, tier, rewardKind, itemID, shardGrant)
	if err != nil {
		log.Printf("insert weekly grant player=%d: %v", request.PlayerID, err)
		writeJSON(w, http.StatusInternalServerError, weeklyClaimResponse{Error: "Internal server error"})
		return
	}
	if affected, _ := result.RowsAffected(); affected == 0 {
		if err := transaction.Commit(); err != nil {
			log.Printf("commit weekly claim race: %v", err)
			writeJSON(w, http.StatusInternalServerError, weeklyClaimResponse{Error: "Internal server error"})
			return
		}
		writeJSON(w, http.StatusOK, weeklyClaimResponse{
			Success:        true,
			AlreadyClaimed: true,
			Tier:           tier,
			RewardKind:     rewardKind,
			ItemID:         itemID,
			Shards:         shardGrant,
		})
		return
	}

	newShards := shards
	if shardGrant > 0 {
		if err := transaction.QueryRowContext(r.Context(), `
			UPDATE players SET sky_shards = COALESCE(sky_shards, 0) + $1
			WHERE id = $2
			RETURNING sky_shards`, shardGrant, request.PlayerID).Scan(&newShards); err != nil {
			log.Printf("grant weekly shards player=%d: %v", request.PlayerID, err)
			writeJSON(w, http.StatusInternalServerError, weeklyClaimResponse{Error: "Internal server error"})
			return
		}
	}
	if err := transaction.Commit(); err != nil {
		log.Printf("commit weekly claim player=%d: %v", request.PlayerID, err)
		writeJSON(w, http.StatusInternalServerError, weeklyClaimResponse{Error: "Internal server error"})
		return
	}
	writeJSON(w, http.StatusOK, weeklyClaimResponse{
		Success:    true,
		Tier:       tier,
		RewardKind: rewardKind,
		ItemID:     itemID,
		Shards:     shardGrant,
		NewShards:  newShards,
	})
}

// ------------------------------ runtime schema ------------------------------

// questSchemaStatements is the single DDL list for the daily-quest tables and
// the `matches` counters. It must stay equivalent to the quest part of
// schema.sql: the production server applies this list at startup, so a table
// that exists only in schema.sql would never reach a deployed database.
// TestQuestSchemaMatchesSQLFile enforces the parity.
var questSchemaStatements = []string{
	`CREATE TABLE IF NOT EXISTS daily_quest_days (
    player_id        BIGINT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    quest_day        DATE   NOT NULL,
    seed             BIGINT NOT NULL,
    reroll_seq       SMALLINT NOT NULL DEFAULT 0,
    free_reroll_used BOOLEAN  NOT NULL DEFAULT FALSE,
    paid_rerolls     SMALLINT NOT NULL DEFAULT 0,
    completed_count  SMALLINT NOT NULL DEFAULT 0,
    all_done_bonus   BOOLEAN  NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (player_id, quest_day)
)`,
	`CREATE INDEX IF NOT EXISTS daily_quest_days_day_idx ON daily_quest_days (quest_day)`,
	`CREATE TABLE IF NOT EXISTS daily_quests (
    player_id     BIGINT NOT NULL,
    quest_day     DATE   NOT NULL,
    slot          SMALLINT NOT NULL,
    template_id   TEXT NOT NULL,
    metric        TEXT NOT NULL,
    target        INTEGER NOT NULL,
    progress      INTEGER NOT NULL DEFAULT 0,
    reward_shards SMALLINT NOT NULL,
    reward_xp     SMALLINT NOT NULL,
    rerolled      BOOLEAN NOT NULL DEFAULT FALSE,
    completed_at  TIMESTAMPTZ,
    PRIMARY KEY (player_id, quest_day, slot),
    FOREIGN KEY (player_id, quest_day)
        REFERENCES daily_quest_days (player_id, quest_day) ON DELETE CASCADE
)`,
	`CREATE INDEX IF NOT EXISTS daily_quests_day_idx ON daily_quests (quest_day)`,
	`CREATE TABLE IF NOT EXISTS weekly_grants (
    player_id   BIGINT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    week_start  DATE   NOT NULL,
    tier        SMALLINT NOT NULL,
    reward_kind TEXT NOT NULL,
    item_id     INTEGER NOT NULL DEFAULT 0,
    shards      INTEGER NOT NULL DEFAULT 0,
    granted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (player_id, week_start)
)`,
	`ALTER TABLE matches ADD COLUMN IF NOT EXISTS duration_sec INTEGER NOT NULL DEFAULT 0`,
	`ALTER TABLE matches ADD COLUMN IF NOT EXISTS kills INTEGER NOT NULL DEFAULT 0`,
	`ALTER TABLE matches ADD COLUMN IF NOT EXISTS deaths INTEGER NOT NULL DEFAULT 0`,
	`ALTER TABLE matches ADD COLUMN IF NOT EXISTS damage INTEGER NOT NULL DEFAULT 0`,
	`ALTER TABLE matches ADD COLUMN IF NOT EXISTS crystals INTEGER NOT NULL DEFAULT 0`,
	`ALTER TABLE matches ADD COLUMN IF NOT EXISTS shells INTEGER NOT NULL DEFAULT 0`,
	`ALTER TABLE matches ADD COLUMN IF NOT EXISTS shop_items INTEGER NOT NULL DEFAULT 0`,
	`ALTER TABLE matches ADD COLUMN IF NOT EXISTS class_key TEXT NOT NULL DEFAULT ''`,
}

// ensureQuestSchema applies the daily-quest DDL at startup, after the base
// players/matches tables exist. Every statement is idempotent.
func ensureQuestSchema(ctx context.Context, db *sql.DB) error {
	if db == nil {
		return errors.New("nil database")
	}
	for index, statement := range questSchemaStatements {
		if _, err := db.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("quest schema statement %d: %w", index+1, err)
		}
	}
	return nil
}
