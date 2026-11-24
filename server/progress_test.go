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
