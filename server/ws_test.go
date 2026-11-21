package main

import (
	"encoding/json"
	"testing"
	"time"
)

func newTestClient(id int64, team int, x, z float64) *wsClient {
	return &wsClient{
		id:           id,
		team:         team,
		class:        team % 3,
		x:            x,
		z:            z,
		hasState:     true,
		alive:        true,
		maxHP:        classBaseHP[team%3],
		hp:           classBaseHP[team%3],
		attackDamage: classBaseDamage[team%3],
		send:         make(chan []byte, 64),
		done:         make(chan struct{}),
		lastAttacks:  make(map[string]time.Time),
	}
}

func newTestRoom(clients ...*wsClient) *wsRoom {
	room := &wsRoom{id: 1, state: "live", humanCount: len(clients), hostID: clients[0].id}
	for index, client := range clients {
		client.roomID = room.id
		client.team = index % 2
		client.class = index % 3
		client.maxHP = classBaseHP[client.class]
		client.hp = client.maxHP
		client.attackDamage = classBaseDamage[client.class]
		client.alive = true
		room.players[index] = client
	}
	return room
}

func collectMessages(t *testing.T, client *wsClient) []wsOutgoing {
	t.Helper()
	messages := make([]wsOutgoing, 0)
	for {
		select {
		case data := <-client.send:
			var message wsOutgoing
			if err := json.Unmarshal(data, &message); err != nil {
				t.Fatalf("unmarshal outgoing: %v", err)
			}
			messages = append(messages, message)
		default:
			return messages
		}
	}
}

// deliverTestShard hands the test client a carried shard and runs the real
// delivery path, so tests exercise the same validation as a live match.
func deliverTestShard(hub *wsHub, room *wsRoom, client *wsClient) {
	hub.mu.Lock()
	room.crystal = &wsCrystalState{State: "carried", CarrierID: client.id}
	hub.mu.Unlock()
	baseZ := 27.5
	if client.team == 1 {
		baseZ = -27.5
	}
	client.x = 0
	client.z = baseZ
	hub.handleCrystalDeliver(client, wsIncoming{})
}

func TestServerOwnsMatchGoldAndPurchases(t *testing.T) {
	hub := newWebSocketHub(nil)
	first := newTestClient(1, 0, -40, 0)
	room := newTestRoom(first)
	hub.rooms[room.id] = room

	hub.handleCoinPickup(first, wsIncoming{Amount: 1})
	if first.gold != 1 {
		t.Fatalf("coin pickup did not credit gold: %d", first.gold)
	}

	first.gold = 600
	hub.handleBuyItem(first, wsIncoming{ItemID: "life_amulet"})
	messages := collectMessages(t, first)
	purchased := false
	for _, message := range messages {
		if message.Type == "shop_purchase" && message.ItemID == "life_amulet" && message.OK && message.Gold == 100 {
			purchased = true
		}
	}
	if !purchased {
		t.Fatalf("server did not confirm the item purchase: %+v", messages)
	}
	hub.handleBuyItem(first, wsIncoming{ItemID: "life_amulet"})
	messages = collectMessages(t, first)
	for _, message := range messages {
		if message.Type == "shop_purchase" && message.OK {
			t.Fatalf("duplicate purchase was accepted: %+v", message)
		}
	}

	// A purchase without enough gold must be rejected.
	second := newTestClient(2, 1, -40, 0)
	room.players[1] = second
	second.roomID = room.id
	second.gold = 10
	hub.handleBuyItem(second, wsIncoming{ItemID: "power_glove"})
	messages = collectMessages(t, second)
	for _, message := range messages {
		if message.Type == "shop_purchase" && message.OK {
			t.Fatalf("purchase without gold was accepted: %+v", message)
		}
	}
}

func TestKillCreditsGoldOnce(t *testing.T) {
	hub := newWebSocketHub(nil)
	first := newTestClient(1, 0, 0, 0)
	second := newTestClient(2, 1, 0, 3)
	room := newTestRoom(first, second)
	hub.rooms[room.id] = room

	second.hp = 10
	hub.handleAttackIntent(first, wsIncoming{TargetID: second.id, Skill: "auto", Amount: 50})
	if first.gold != 50 {
		t.Fatalf("kill did not credit 50 gold: %d", first.gold)
	}
	// A second hit on a dead target must not pay again.
	hub.handleAttackIntent(first, wsIncoming{TargetID: second.id, Skill: "auto", Amount: 50})
	if first.gold != 50 {
		t.Fatalf("dead target paid gold twice: %d", first.gold)
	}
}

func TestItemsAffectServerDamageAndLifesteal(t *testing.T) {
	hub := newWebSocketHub(nil)
	first := newTestClient(1, 0, 0, 0)
	second := newTestClient(2, 1, 0, 3)
	room := newTestRoom(first, second)
	hub.rooms[room.id] = room

	first.bought = map[string]bool{"vampire_fang": true, "power_glove": true}
	first.maxHP, first.attackDamage = statsForClient(first)
	if first.attackDamage != classBaseDamage[0]+25 {
		t.Fatalf("power glove was not applied: %v", first.attackDamage)
	}
	first.hp = first.maxHP - 100

	second.bought = map[string]bool{"titan_shell": true}
	second.maxHP, second.attackDamage = statsForClient(second)
	hub.handleAttackIntent(first, wsIncoming{TargetID: second.id, Skill: "auto", Amount: 100})
	expected := second.maxHP - 85 // -15% from titan shell
	if second.hp != expected {
		t.Fatalf("titan shell reduction not applied: hp=%v want=%v", second.hp, expected)
	}
	if first.hp <= first.maxHP-100 {
		t.Fatalf("vampire fang did not heal the attacker: %v", first.hp)
	}

	// Stun is derived from the skill and sent with the damage packet.
	hub.handleAttackIntent(first, wsIncoming{TargetID: second.id, Skill: "fear_ult", Amount: 10})
	messages := collectMessages(t, first)
	stunned := false
	for _, message := range messages {
		if message.Type == "damage" && message.Skill == "fear_ult" && message.Stun > 0 {
			stunned = true
		}
	}
	if !stunned {
		t.Fatalf("fear_ult did not carry a stun: %+v", messages)
	}
}

func TestAttackIntentRejectsDistanceAndCooldown(t *testing.T) {
	hub := newWebSocketHub(nil)
	first := newTestClient(1, 0, 0, 0)
	second := newTestClient(2, 1, 0, 3)
	room := newTestRoom(first, second)
	hub.rooms[room.id] = room

	hub.handleAttackIntent(first, wsIncoming{TargetID: second.id, Skill: "auto"})
	messages := collectMessages(t, first)
	if len(messages) != 1 || messages[0].Type != "damage" {
		t.Fatalf("expected damage, got %+v", messages)
	}
	if second.hp >= second.maxHP {
		t.Fatal("server did not apply in-range damage")
	}

	hpBeforeDenied := second.hp
	hub.handleAttackIntent(first, wsIncoming{TargetID: second.id, Skill: "auto"})
	messages = collectMessages(t, first)
	if len(messages) != 1 || messages[0].Type != "attack_denied" || messages[0].Reason != "cooldown" {
		t.Fatalf("expected cooldown denial, got %+v", messages)
	}
	if second.hp != hpBeforeDenied {
		t.Fatal("denied attack changed target hp")
	}

	second.z = 40
	first.lastAttacks["auto"] = time.Now().Add(-time.Second)
	hub.handleAttackIntent(first, wsIncoming{TargetID: second.id, Skill: "auto"})
	messages = collectMessages(t, first)
	if len(messages) != 1 || messages[0].Type != "attack_denied" || messages[0].Reason != "out_of_range" {
		t.Fatalf("expected out_of_range denial, got %+v", messages)
	}
}

func TestBotAttackIntentUsesBotSource(t *testing.T) {
	hub := newWebSocketHub(nil)
	host := newTestClient(1, 0, 0, 0)
	guest := newTestClient(2, 1, 0, 2)
	room := newTestRoom(host, guest)
	room.bots[2] = &wsBot{
		id:           -3,
		class:        2,
		team:         0,
		x:            0,
		z:            0,
		hasState:     true,
		alive:        true,
		maxHP:        450,
		hp:           450,
		attackDamage: 30,
		lastAttacks:  make(map[string]time.Time),
	}
	hub.rooms[room.id] = room

	hub.handleAttackIntent(host, wsIncoming{SourceID: -3, TargetID: guest.id, Skill: "auto"})
	messages := collectMessages(t, host)
	if len(messages) != 1 || messages[0].Type != "damage" || messages[0].SourceID != -3 {
		t.Fatalf("expected bot damage, got %+v", messages)
	}
	if guest.hp >= guest.maxHP {
		t.Fatal("bot attack did not damage guest")
	}
}

func TestGuestCannotImpersonateBot(t *testing.T) {
	hub := newWebSocketHub(nil)
	host := newTestClient(1, 0, 0, 0)
	guest := newTestClient(2, 1, 0, 2)
	room := newTestRoom(host, guest)
	room.bots[2] = &wsBot{
		id:           -3,
		class:        2,
		team:         0,
		x:            0,
		z:            0,
		hasState:     true,
		alive:        true,
		maxHP:        450,
		hp:           450,
		attackDamage: 30,
		lastAttacks:  make(map[string]time.Time),
	}
	hub.rooms[room.id] = room

	hub.handleAttackIntent(guest, wsIncoming{SourceID: -3, TargetID: host.id, Skill: "auto"})
	messages := collectMessages(t, guest)
	if len(messages) != 1 || messages[0].Type != "attack_denied" || messages[0].Reason != "invalid_source" {
		t.Fatalf("expected invalid_source denial, got %+v", messages)
	}
	if host.hp != host.maxHP {
		t.Fatal("impersonated bot attack damaged host")
	}
}

func TestBotStatesReachGuests(t *testing.T) {
	hub := newWebSocketHub(nil)
	host := newTestClient(1, 0, 0, 0)
	guest := newTestClient(2, 1, 0, 2)
	room := newTestRoom(host, guest)
	room.bots[2] = &wsBot{
		id:           -3,
		name:         "Бот-Лучница-3",
		class:        2,
		team:         0,
		x:            0,
		z:            -4,
		hasState:     true,
		alive:        true,
		maxHP:        450,
		hp:           450,
		attackDamage: 30,
		lastAttacks:  make(map[string]time.Time),
	}
	hub.rooms[room.id] = room

	hub.relayBotStates(host, wsIncoming{Bots: []wsBotSnapshot{{
		ID: -3, X: 8, Y: 0.76, Z: -6, Rotation: 1.2, MaxHP: 450, HP: 412, AttackDamage: 30, Alive: true, Animation: "run",
	}}})
	hostMessages := collectMessages(t, host)
	if len(hostMessages) != 1 || hostMessages[0].Type != "bot_states" || len(hostMessages[0].Bots) != 1 {
		t.Fatalf("host should receive the server bot state: %+v", hostMessages)
	}
	if hostMessages[0].Bots[0].HP != 450 {
		t.Fatalf("host packet must not change server bot HP: %+v", hostMessages[0].Bots[0])
	}
	messages := collectMessages(t, guest)
	if len(messages) != 1 || messages[0].Type != "bot_states" || len(messages[0].Bots) != 1 {
		t.Fatalf("expected relayed bot state, got %+v", messages)
	}
	bot := messages[0].Bots[0]
	if bot.ID != -3 || bot.X != 8 || bot.HP != 450 || bot.Animation != "run" {
		t.Fatalf("unexpected bot snapshot: %+v", bot)
	}
}

func TestStaleBotStateCannotResurrect(t *testing.T) {
	hub := newWebSocketHub(nil)
	host := newTestClient(1, 0, 0, 0)
	guest := newTestClient(2, 1, 0, 2)
	room := newTestRoom(host, guest)
	bot := &wsBot{
		id:           -3,
		class:        2,
		team:         0,
		hasState:     true,
		alive:        true,
		maxHP:        450,
		hp:           450,
		attackDamage: 30,
		lastAttacks:  make(map[string]time.Time),
	}
	room.bots[2] = bot
	hub.rooms[room.id] = room

	hub.mu.Lock()
	bot.hp = 0
	bot.alive = false
	bot.deadSince = time.Now()
	hub.mu.Unlock()
	hub.relayBotStates(host, wsIncoming{Bots: []wsBotSnapshot{{
		ID: -3, MaxHP: 450, HP: 450, Alive: true,
	}}})
	if bot.alive || bot.hp != 0 {
		t.Fatalf("stale packet resurrected bot: alive=%v hp=%v", bot.alive, bot.hp)
	}

	hub.mu.Lock()
	bot.deadSince = time.Now().Add(-2 * time.Second)
	hub.mu.Unlock()
	hub.relayBotStates(host, wsIncoming{Bots: []wsBotSnapshot{{
		ID: -3, MaxHP: 450, HP: 450, Alive: true,
	}}})
	if !bot.alive || bot.hp != 450 {
		t.Fatalf("legit respawn was rejected: alive=%v hp=%v", bot.alive, bot.hp)
	}
}

func TestServerDeterminesWinnerFromDeliveries(t *testing.T) {
	hub := newWebSocketHub(nil)
	first := newTestClient(1, 0, 0, 0)
	second := newTestClient(2, 1, 0, 2)
	room := newTestRoom(first, second)
	hub.rooms[room.id] = room

	hub.handleMatchEvent(second, wsIncoming{Event: "shard_delivered", Team: 0})
	if room.score[0] != 0 {
		t.Fatal("guest was allowed to score for the enemy team")
	}

	for delivery := 0; delivery < crystalsToWin; delivery++ {
		deliverTestShard(hub, room, first)
	}
	if room.state != "finished" || room.score[0] != crystalsToWin {
		t.Fatalf("server did not finish match: state=%s score=%v", room.state, room.score)
	}
	messages := collectMessages(t, first)
	finished := false
	for _, message := range messages {
		if message.Type == "match_finished" && message.WinningTeam == 0 {
			finished = true
		}
	}
	if !finished {
		t.Fatalf("match_finished with winning team 0 not broadcast: %+v", messages)
	}
}

func TestDeliveriesFromBothTeamsWithinLockoutBothCount(t *testing.T) {
	hub := newWebSocketHub(nil)
	first := newTestClient(1, 0, 0, 0)
	second := newTestClient(2, 1, 0, 0)
	room := newTestRoom(first, second)
	hub.rooms[room.id] = room

	deliverTestShard(hub, room, first)
	deliverTestShard(hub, room, second)
	if room.score[0] != 1 || room.score[1] != 1 {
		t.Fatalf("deliveries from both teams must count, got %v", room.score)
	}

	// A duplicate event without a carried shard must not score again.
	hub.handleMatchEvent(first, wsIncoming{Event: "shard_delivered", Team: 0})
	if room.score[0] != 1 {
		t.Fatalf("delivery without a carried shard must be ignored, got %v", room.score)
	}
}

func TestMatchTimeoutAwardsHigherScore(t *testing.T) {
	hub := newWebSocketHub(nil)
	first := newTestClient(1, 0, 0, 0)
	second := newTestClient(2, 1, 0, 2)
	room := newTestRoom(first, second)
	room.score = [2]int{2, 1}
	hub.rooms[room.id] = room

	hub.finishMatchByTimeout(room.id)
	if room.state != "finished" {
		t.Fatalf("expected finished, got %s", room.state)
	}
	messages := collectMessages(t, first)
	finished := false
	for _, message := range messages {
		if message.Type == "match_finished" && message.WinningTeam == 0 {
			finished = true
		}
	}
	if !finished {
		t.Fatalf("expected winning team 0, got %+v", messages)
	}
}

func TestDisconnectReplacesHumanWithBot(t *testing.T) {
	hub := newWebSocketHub(nil)
	host := newTestClient(1, 0, 5, 7)
	guest := newTestClient(2, 1, 0, 3)
	room := newTestRoom(host, guest)
	hub.rooms[room.id] = room
	hub.clients[host.id] = host
	hub.clients[guest.id] = guest

	host.name = "Даронес"
	host.class = 2
	host.team = 0
	host.maxHP = 950
	host.hp = 123
	host.attackDamage = 60
	host.hasState = true

	hub.removeClient(host)

	if room.players[0] != nil {
		t.Fatal("disconnected human slot should be empty")
	}
	if room.bots[0] == nil {
		t.Fatal("disconnected human should be replaced by a bot")
	}
	bot := room.bots[0]
	if bot.id != -1 || bot.name != "Даронес" || bot.class != 2 || bot.team != 0 {
		t.Fatalf("unexpected replacement bot: %+v", bot)
	}
	if bot.x != 5 || bot.z != 7 || bot.hp != 123 || !bot.alive {
		t.Fatalf("replacement bot lost player state: %+v", bot)
	}
	if room.hostID != guest.id {
		t.Fatalf("expected host migration to guest, got %d", room.hostID)
	}
	messages := collectMessages(t, guest)
	types := make([]string, 0, len(messages))
	for _, message := range messages {
		types = append(types, message.Type)
	}
	want := []string{"player_left", "host_changed", "bot_roster"}
	if len(types) != len(want) {
		t.Fatalf("expected messages %v, got %v", want, types)
	}
	for index := range want {
		if types[index] != want[index] {
			t.Fatalf("expected messages %v, got %v", want, types)
		}
	}
	if len(messages[2].Bots) != 1 || messages[2].Bots[0].ID != -1 {
		t.Fatalf("bot_roster missing replacement bot: %+v", messages[2].Bots)
	}
}

func TestMatchmakingKeepsFirstJoinDeadline(t *testing.T) {
	hub := newWebSocketHub(nil)
	first := newTestClient(1, 0, 0, 0)
	second := newTestClient(2, 0, 0, 0)
	third := newTestClient(3, 0, 0, 0)

	hub.joinMatchmaking(first, wsIncoming{PlayerID: 101, Name: "First", Class: 0})
	hub.mu.Lock()
	roomID := first.roomID
	room := hub.rooms[roomID]
	deadline := room.startsAt
	firstTimer := room.fillTimer
	hub.mu.Unlock()
	if roomID == 0 || room == nil || firstTimer == nil || deadline.IsZero() {
		t.Fatal("first player did not create a waiting room with a deadline")
	}

	hub.joinMatchmaking(second, wsIncoming{PlayerID: 102, Name: "Second", Class: 1})
	hub.mu.Lock()
	secondDeadline := room.startsAt
	secondTimer := room.fillTimer
	hub.mu.Unlock()
	if second.roomID != roomID {
		t.Fatalf("second player joined room %d, want %d", second.roomID, roomID)
	}
	if !secondDeadline.Equal(deadline) {
		t.Fatal("second join reset the countdown; variant 1 forbids that")
	}
	if secondTimer != firstTimer {
		t.Fatal("second join replaced the bot timer")
	}

	hub.joinMatchmaking(third, wsIncoming{PlayerID: 103, Name: "Third", Class: 2})
	hub.mu.Lock()
	thirdDeadline := room.startsAt
	thirdTimer := room.fillTimer
	humans := room.humanCount
	if thirdTimer != nil {
		thirdTimer.Stop()
	}
	hub.mu.Unlock()
	if third.roomID != roomID {
		t.Fatalf("third player joined room %d, want %d", third.roomID, roomID)
	}
	if !thirdDeadline.Equal(deadline) {
		t.Fatal("third join reset the countdown; variant 1 forbids that")
	}
	if humans != 3 {
		t.Fatalf("expected 3 humans in one room, got %d", humans)
	}
}

func TestShellStateAndDamageAreServerOwned(t *testing.T) {
	hub := newWebSocketHub(nil)
	host := newTestClient(1, 0, 0, 0)
	guest := newTestClient(2, 1, 0, 2)
	room := newTestRoom(host, guest)
	hub.rooms[room.id] = room
	host.x, host.z = 0, 2
	host.hasState = true
	host.alive = true
	host.maxHP, host.hp = 1050, 1050
	host.lastAttacks = make(map[string]time.Time)

	hub.relayShellState(host, wsIncoming{Shell: &wsShellState{
		Alive: true, X: 0, Y: 0.45, Z: 0, Phase: "active",
	}})
	if room.shell == nil || !room.shell.Alive || room.shell.HP != 1000 || room.shell.MaxHP != 1000 {
		t.Fatalf("unexpected server shell: %+v", room.shell)
	}
	guestMessages := collectMessages(t, guest)
	if len(guestMessages) != 1 || guestMessages[0].Type != "shell_state" {
		t.Fatalf("guest did not receive shell state: %+v", guestMessages)
	}

	// The host's HP is not authoritative.
	hub.relayShellState(host, wsIncoming{Shell: &wsShellState{
		Alive: true, X: 0, Y: 0.45, Z: 0, Phase: "active", HP: 100, MaxHP: 100,
	}})
	if room.shell.HP != 1000 {
		t.Fatalf("host shell HP changed the server value: %v", room.shell.HP)
	}

	hub.handleShellAttack(host, wsIncoming{Amount: 800, SourceID: 0})
	if room.shell == nil || room.shell.HP != 200 || !room.shell.Alive {
		t.Fatalf("shell damage not applied by server: %+v", room.shell)
	}
	host.lastAttacks["shell"] = time.Now().Add(-time.Second)
	hub.handleShellAttack(host, wsIncoming{Amount: 300, SourceID: 0})
	if room.shell.Alive || room.shell.HP != 0 {
		t.Fatalf("shell death not owned by server: %+v", room.shell)
	}
}

func TestNewShellSpawnsWhileShardActive(t *testing.T) {
	hub := newWebSocketHub(nil)
	host := newTestClient(1, 0, 0, 0)
	guest := newTestClient(2, 1, 0, 2)
	room := newTestRoom(host, guest)
	hub.rooms[room.id] = room
	// The previous shell's shard is still on the field. It must not block the
	// two-minute shell cycle: the old code forced Alive=false and every client
	// hid the freshly spawned shell.
	room.crystal = &wsCrystalState{State: "ground", X: 4, Y: 0.5, Z: -3, GroundSince: time.Now()}

	hub.relayShellState(host, wsIncoming{Shell: &wsShellState{
		Alive: true, X: 0, Y: 0.45, Z: 0, Phase: "active",
	}})
	if room.shell == nil || !room.shell.Alive {
		t.Fatalf("shell was rejected while a shard was active: %+v", room.shell)
	}

	// The shard must survive the spawn, and the shell death must not create a
	// second one while the first is still active.
	host.lastAttacks["shell"] = time.Now().Add(-time.Second)
	hub.handleShellAttack(host, wsIncoming{Amount: 800, SourceID: 0})
	host.lastAttacks["shell"] = time.Now().Add(-time.Second)
	hub.handleShellAttack(host, wsIncoming{Amount: 300, SourceID: 0})
	if room.shell.Alive {
		t.Fatalf("shell death not owned by server: %+v", room.shell)
	}
	if room.crystal == nil || room.crystal.State != "ground" || room.crystal.X != 4 {
		t.Fatalf("active shard was replaced: %+v", room.crystal)
	}
}

func TestCarriedShardTimesOutInsteadOfBlockingTheMatch(t *testing.T) {
	hub := newWebSocketHub(nil)
	carrier := newTestClient(1, 0, 5, 7)
	room := newTestRoom(carrier)
	hub.rooms[room.id] = room
	room.crystal = &wsCrystalState{
		State:        "carried",
		CarrierID:    carrier.id,
		CarriedSince: time.Now().Add(-time.Minute),
	}

	hub.updateState(carrier, wsIncoming{X: 5, Y: 0.76, Z: 7, Rotation: 0})
	if room.crystal.State != "ground" || room.crystal.CarrierID != 0 {
		t.Fatalf("stale carried shard was not dropped: %+v", room.crystal)
	}
	if room.crystal.X != 5 || room.crystal.Z != 7 {
		t.Fatalf("shard dropped away from the carrier: %+v", room.crystal)
	}
	if !room.crystal.CarriedSince.IsZero() || room.crystal.GroundSince.IsZero() {
		t.Fatalf("shard timers not reset: %+v", room.crystal)
	}
}

func TestHealEchoReachesTheHealer(t *testing.T) {
	hub := newWebSocketHub(nil)
	mage := newTestClient(1, 0, 0, 0)
	room := newTestRoom(mage)
	hub.rooms[room.id] = room
	mage.hp = 400

	hub.relayHeal(mage, wsIncoming{TargetID: mage.id, Amount: 150})
	if mage.hp != 550 {
		t.Fatalf("server did not apply self-heal: hp=%v", mage.hp)
	}
	messages := collectMessages(t, mage)
	healEcho := false
	for _, message := range messages {
		if message.Type == "heal" && message.TargetID == mage.id && message.SourceID == mage.id && message.Amount == 150 {
			healEcho = true
		}
	}
	if !healEcho {
		t.Fatalf("healer did not receive its own heal echo: %+v", messages)
	}

	// Healing a full-HP target must not fabricate a heal number.
	mage.hp = mage.maxHP
	hub.relayHeal(mage, wsIncoming{TargetID: mage.id, Amount: 150})
	for _, message := range collectMessages(t, mage) {
		if message.Type == "heal" {
			t.Fatalf("full-HP heal produced an echo: %+v", message)
		}
	}
}

func TestShellSpawnIDBeatsTheDeathCooldown(t *testing.T) {
	hub := newWebSocketHub(nil)
	host := newTestClient(1, 0, 0, 0)
	room := newTestRoom(host)
	hub.rooms[room.id] = room
	host.x, host.z = 0, 0
	host.hasState = true
	host.alive = true
	host.lastAttacks = make(map[string]time.Time)

	spawn := func(id int64) {
		hub.relayShellState(host, wsIncoming{Shell: &wsShellState{
			Alive: true, X: 0, Y: 0.45, Z: 0, Phase: "active", SpawnID: id,
		}})
	}
	kill := func() {
		host.lastAttacks["shell"] = time.Now().Add(-time.Second)
		hub.handleShellAttack(host, wsIncoming{Amount: 800, SourceID: 0})
		host.lastAttacks["shell"] = time.Now().Add(-time.Second)
		hub.handleShellAttack(host, wsIncoming{Amount: 300, SourceID: 0})
	}

	spawn(1)
	if room.shell == nil || !room.shell.Alive || room.shellSpawnID != 1 {
		t.Fatalf("first spawn not accepted: %+v id=%d", room.shell, room.shellSpawnID)
	}
	kill()
	if room.shell.Alive {
		t.Fatalf("shell did not die: %+v", room.shell)
	}
	// A genuinely new shell may start immediately after a death.
	spawn(2)
	if !room.shell.Alive || room.shellSpawnID != 2 {
		t.Fatalf("new spawn id rejected by the old cooldown: %+v id=%d", room.shell, room.shellSpawnID)
	}
	kill()
	// The old packet must not resurrect the dead shell.
	spawn(2)
	if room.shell.Alive {
		t.Fatalf("stale spawn id resurrected the shell: %+v", room.shell)
	}
}

func TestAoESkillAllowsMultipleTargetsInOneCast(t *testing.T) {
	combatant := &wsCombatant{class: 0, lastAttacks: make(map[string]time.Time)}
	if !combatant.cooldownReady("fear_ult") {
		t.Fatal("first AoE target was rejected")
	}
	if !combatant.cooldownReady("fear_ult") {
		t.Fatal("second target of the same AoE cast was rejected")
	}
	auto := &wsCombatant{class: 0, lastAttacks: make(map[string]time.Time)}
	if !auto.cooldownReady("auto") {
		t.Fatal("first auto attack was rejected")
	}
	if auto.cooldownReady("auto") {
		t.Fatal("auto attack spam was accepted")
	}
}

func TestRelayStatsNeverLowersServerHP(t *testing.T) {
	hub := newWebSocketHub(nil)
	client := newTestClient(1, 0, 0, 0)
	room := newTestRoom(client)
	client.maxHP = 1050
	client.hp = 700
	client.alive = true
	hub.rooms[room.id] = room
	hub.clients[client.id] = client

	hub.relayStats(client, wsIncoming{MaxHP: 1050, HP: 0, AttackDamage: 50})
	if client.hp != 700 {
		t.Fatalf("stale 0 HP packet lowered server HP to %v", client.hp)
	}
	if !client.alive {
		t.Fatal("stale packet killed the client")
	}

	hub.relayStats(client, wsIncoming{MaxHP: 1050, HP: 950, AttackDamage: 50})
	if client.hp != 700 {
		t.Fatalf("client-declared HP must not change authoritative HP: %v", client.hp)
	}
	if client.maxHP != classBaseHP[0] || client.attackDamage != classBaseDamage[0] {
		t.Fatalf("stats must come from class+items, got max=%v dmg=%v", client.maxHP, client.attackDamage)
	}

	hub.relayStats(client, wsIncoming{MaxHP: 1050, HP: 500, AttackDamage: 50})
	if client.hp != 700 {
		t.Fatalf("client lowered authoritative HP to %v", client.hp)
	}
}

func TestUpdateStateSendsAuthoritativeSync(t *testing.T) {
	hub := newWebSocketHub(nil)
	client := newTestClient(1, 0, 0, 0)
	room := newTestRoom(client)
	client.maxHP = 1050
	client.hp = 730
	client.alive = true
	hub.rooms[room.id] = room

	hub.updateState(client, wsIncoming{X: 1, Y: 0.76, Z: 2, Rotation: 0})
	messages := collectMessages(t, client)
	if len(messages) != 1 || messages[0].Type != "sync" {
		t.Fatalf("expected one sync message, got %+v", messages)
	}
	if messages[0].HP != 730 || messages[0].MaxHP != 1050 || !messages[0].Alive {
		t.Fatalf("sync lost authoritative HP: %+v", messages[0])
	}
}

func TestServerOwnsBotHP(t *testing.T) {
	hub := newWebSocketHub(nil)
	host := newTestClient(1, 0, 0, 0)
	room := newTestRoom(host)
	room.bots[0] = &wsBot{id: -1, team: 0, alive: true, hp: 300, maxHP: 450, lastAttacks: make(map[string]time.Time)}
	hub.rooms[room.id] = room

	snapshot := wsBotSnapshot{ID: -1, X: 0, Y: 0.76, Z: 0, Rotation: 0, HP: 450, MaxHP: 450, Alive: true}
	hub.relayBotStates(host, wsIncoming{Bots: []wsBotSnapshot{snapshot}})
	if room.bots[0].hp != 300 {
		t.Fatalf("host snapshot raised server bot HP to %v", room.bots[0].hp)
	}

	room.bots[0].hp = 120
	room.bots[0].lastDamaged = time.Now()
	hub.relayBotStates(host, wsIncoming{Bots: []wsBotSnapshot{snapshot}})
	if room.bots[0].hp != 120 {
		t.Fatalf("host snapshot healed server bot back to %v", room.bots[0].hp)
	}
}

func TestLobbyStateBroadcastsPlayersImmediately(t *testing.T) {
	hub := newWebSocketHub(nil)
	first := newTestClient(1, 0, 0, 0)
	second := newTestClient(2, 0, 0, 0)

	hub.joinMatchmaking(first, wsIncoming{PlayerID: 201, Name: "First", Class: 0})
	firstMessages := collectMessages(t, first)
	if len(firstMessages) != 2 || firstMessages[0].Type != "room_joined" || firstMessages[1].Type != "lobby_state" {
		t.Fatalf("expected room_joined + lobby_state, got %+v", firstMessages)
	}
	if len(firstMessages[1].MatchPlayers) != 1 {
		t.Fatalf("lobby_state should show the first player, got %+v", firstMessages[1].MatchPlayers)
	}
	if firstMessages[1].StartsInMS <= 0 {
		t.Fatalf("lobby_state must carry a positive countdown, got %d", firstMessages[1].StartsInMS)
	}

	hub.joinMatchmaking(second, wsIncoming{PlayerID: 202, Name: "Second", Class: 1})
	update := collectMessages(t, first)
	if len(update) != 1 || update[0].Type != "lobby_state" {
		t.Fatalf("existing client should get a lobby update, got %+v", update)
	}
	if len(update[0].MatchPlayers) != 2 {
		t.Fatalf("lobby update should show both players, got %+v", update[0].MatchPlayers)
	}
	if update[0].MatchPlayers[0].Team == update[0].MatchPlayers[1].Team {
		t.Fatalf("two humans were not split between teams: %+v", update[0].MatchPlayers)
	}
	if update[0].StartsInMS < 25000 {
		t.Fatalf("join should reset the countdown, got %d ms", update[0].StartsInMS)
	}
}

func TestBotClassesFillMissingTeamClasses(t *testing.T) {
	room := &wsRoom{}
	human := newTestClient(1, 0, 0, 0)
	human.class = 2
	room.players[0] = human
	classes := botClassesForRoom(room)
	want := [roomSlots]int{2, 0, 1, 0, 1, 2}
	if classes != want {
		t.Fatalf("bot classes = %v, want %v", classes, want)
	}
}
