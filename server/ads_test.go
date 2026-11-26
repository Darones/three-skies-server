package main

import (
	"strings"
	"testing"
)

// The x2 rewarded-ad bonus must pay exactly the base reward a second time.
func TestBonusPayoutUsesStoredBase(t *testing.T) {
	for _, stored := range []int{1, 3, 5} {
		for _, won := range []bool{true, false} {
			payout, legacy := bonusPayoutShards(stored, 2*stored, won)
			if legacy {
				t.Fatalf("stored base %d reported as legacy", stored)
			}
			if payout != stored {
				t.Fatalf("bonus payout = %d for stored base %d, want x2 total", payout, stored)
			}
		}
	}
}

// Rows rewarded before reward_shards existed carry no stored base. The client
// sends the already doubled total there, so the fallback must never be paid
// as-is: that paid 3x.
func TestBonusPayoutLegacyIsCappedToTheBase(t *testing.T) {
	cases := []struct {
		request int
		won     bool
		want    int
	}{
		{request: 10, won: true, want: 5},
		{request: 10, won: false, want: 3},
		{request: 6, won: false, want: 3},
		{request: 2, won: false, want: 2},
		{request: 1, won: true, want: 1},
	}
	for _, test := range cases {
		payout, legacy := bonusPayoutShards(0, test.request, test.won)
		if !legacy {
			t.Fatalf("request %d without a stored base is not flagged legacy", test.request)
		}
		if payout != test.want {
			t.Fatalf("legacy bonus for request %d won=%t = %d, want %d", test.request, test.won, payout, test.want)
		}
		if payout > baseRewardCap(test.won) {
			t.Fatalf("legacy bonus %d exceeds the base cap %d", payout, baseRewardCap(test.won))
		}
	}
}

func TestBaseRewardCapMatchesTheClientTier(t *testing.T) {
	if got := baseRewardCap(true); got != 5 {
		t.Fatalf("win cap = %d, want 5", got)
	}
	if got := baseRewardCap(false); got != 3 {
		t.Fatalf("loss cap = %d, want 3", got)
	}
}

// A bonus claim may only match a row whose base reward was already paid, and
// the two payouts must stay separately idempotent.
func TestMatchRewardBonusWaitsForTheBase(t *testing.T) {
	if !strings.Contains(matchRewardBonusClaimQuery, "COALESCE(rewarded, FALSE) = TRUE") {
		t.Fatalf("bonus claim does not require the base reward: %s", matchRewardBonusClaimQuery)
	}
	if !strings.Contains(matchRewardBonusClaimQuery, "COALESCE(rewarded_bonus, FALSE) = FALSE") {
		t.Fatalf("bonus claim can pay twice: %s", matchRewardBonusClaimQuery)
	}
	if !strings.Contains(matchRewardBonusClaimQuery, "reward_shards") {
		t.Fatalf("bonus claim cannot read the stored base payout: %s", matchRewardBonusClaimQuery)
	}
	if !strings.Contains(matchRewardBaseClaimQuery, "COALESCE(rewarded, FALSE) = FALSE") {
		t.Fatalf("base claim can pay twice: %s", matchRewardBaseClaimQuery)
	}
}

// The client drops a base reward on "Reward already claimed" and keeps
// everything else for a retry, so the three answers must stay distinct.
func TestMatchRewardErrorsAreDistinguishable(t *testing.T) {
	answers := []string{rewardAlreadyClaimedError, rewardBasePendingError, matchNotRecordedError}
	for i := range answers {
		if strings.TrimSpace(answers[i]) == "" {
			t.Fatalf("match reward answer %d is empty", i)
		}
		for j := i + 1; j < len(answers); j++ {
			if answers[i] == answers[j] {
				t.Fatalf("match reward answers are not distinguishable: %q", answers[i])
			}
		}
	}
	// The outbox retries any error it does not recognise; only the paid base
	// is terminal for the client, and it must keep exactly that wording.
	if rewardAlreadyClaimedError != "Reward already claimed" {
		t.Fatalf("terminal base answer changed: %q", rewardAlreadyClaimedError)
	}
}
