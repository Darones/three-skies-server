package main

import "testing"

func TestSanitizeProgressClampsAndKeepsKnownCharacters(t *testing.T) {
	state := sanitizeProgress(
		map[string]int{"warrior": 99, "mage": 0, "fairy": 3, "unknown": 7},
		map[string]int{"warrior": 999999, "mage": -5, "fairy": 2500},
		true,
		true,
		999999,
	)
	if state.CharLevels["warrior"] != maxCharacterLevel {
		t.Fatalf("warrior level=%d", state.CharLevels["warrior"])
	}
	if state.CharLevels["mage"] != 1 {
		t.Fatalf("mage level=%d", state.CharLevels["mage"])
	}
	if state.CharLevels["fairy"] != 3 {
		t.Fatalf("fairy level=%d", state.CharLevels["fairy"])
	}
	if _, ok := state.CharLevels["unknown"]; ok {
		t.Fatal("unknown character leaked into progress")
	}
	if state.CharXPs["warrior"] != 0 {
		t.Fatalf("max-level warrior xp=%d, want 0", state.CharXPs["warrior"])
	}
	if state.CharXPs["fairy"] != 2500 {
		t.Fatalf("fairy xp=%d", state.CharXPs["fairy"])
	}
	if !state.TutorialCompleted || state.TutorialSkipped {
		t.Fatalf("tutorial state=%+v", state)
	}
	if state.TutorialBattlesUsed != maxTutorialBattles {
		t.Fatalf("battles=%d", state.TutorialBattlesUsed)
	}
	if !state.ProgressInitialized {
		t.Fatal("sanitized progress must be initialized")
	}
}

func TestDecodeStoredProgressDefaults(t *testing.T) {
	state := decodeStoredProgress("", "", false, false, 0, false)
	if state.CharLevels["warrior"] != 1 || state.CharXPs["warrior"] != 0 {
		t.Fatalf("defaults=%+v", state)
	}
	if state.ProgressInitialized {
		t.Fatal("stored false must stay false")
	}
}

func TestMergeProgressUpdateImportsOnlyBeforeInitialized(t *testing.T) {
	imported := sanitizeProgress(
		map[string]int{"warrior": 5, "mage": 2},
		map[string]int{"warrior": 1200, "mage": 300},
		false,
		false,
		0,
	)
	next := mergeProgressUpdate(decodeStoredProgress("", "", false, false, 0, false), imported)
	if next.CharLevels["warrior"] != 5 || next.CharXPs["warrior"] != 1200 {
		t.Fatalf("first import was rejected: %+v", next)
	}
	if next.CharLevels["mage"] != 2 {
		t.Fatalf("first import lost mage: %+v", next)
	}
	if !next.ProgressInitialized {
		t.Fatal("import must initialize progress")
	}

	stored := decodeStoredProgress(
		`{"warrior":5,"mage":2,"fairy":1}`,
		`{"warrior":1200,"mage":300,"fairy":0}`,
		false, false, 0, true,
	)
	// A client tries to roll the level back to farm level-up shards, then a
	// second call tries to raise it. Both must be ignored.
	lowered := sanitizeProgress(
		map[string]int{"warrior": 1, "mage": 2},
		map[string]int{"warrior": 0, "mage": 300},
		true, false, 3,
	)
	merged := mergeProgressUpdate(stored, lowered)
	if merged.CharLevels["warrior"] != 5 || merged.CharXPs["warrior"] != 1200 {
		t.Fatalf("client rolled progress back: %+v", merged)
	}
	if merged.TutorialCompleted != true || merged.TutorialBattlesUsed != 3 {
		t.Fatalf("tutorial update was lost: %+v", merged)
	}

	raised := sanitizeProgress(
		map[string]int{"warrior": 15},
		map[string]int{"warrior": 999999},
		false, false, 0,
	)
	merged = mergeProgressUpdate(stored, raised)
	if merged.CharLevels["warrior"] != 5 || merged.CharXPs["warrior"] != 1200 {
		t.Fatalf("client raised progress: %+v", merged)
	}
}
