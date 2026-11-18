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
	if hostMessages := collectMessages(t, host); len(hostMessages) != 0 {
		t.Fatalf("host should not receive its own bot states: %+v", hostMessages)
	}
	messages := collectMessages(t, guest)
	if len(messages) != 1 || messages[0].Type != "bot_states" || len(messages[0].Bots) != 1 {
		t.Fatalf("expected relayed bot state, got %+v", messages)
	}
	bot := messages[0].Bots[0]
	if bot.ID != -3 || bot.X != 8 || bot.HP != 412 || bot.Animation != "run" {
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

	hub.relayBotStates(host, wsIncoming{Bots: []wsBotSnapshot{{
		ID: -3, MaxHP: 450, HP: 0, Alive: false,
	}}})
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
		hub.mu.Lock()
		room.lastDelivery = [2]time.Time{}
		hub.mu.Unlock()
		hub.handleMatchEvent(first, wsIncoming{Event: "shard_delivered", Team: 0})
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

	hub.handleMatchEvent(first, wsIncoming{Event: "shard_delivered", Team: 0})
	hub.handleMatchEvent(second, wsIncoming{Event: "shard_delivered", Team: 1})
	if room.score[0] != 1 || room.score[1] != 1 {
		t.Fatalf("deliveries from both teams must count, got %v", room.score)
	}

	// Повторное событие той же команды в пределах блокировки не должно начислять очко
	hub.handleMatchEvent(first, wsIncoming{Event: "shard_delivered", Team: 0})
	if room.score[0] != 1 {
		t.Fatalf("duplicate delivery must be ignored, got %v", room.score)
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

func TestMatchmakingRestartsBotTimerForEachJoin(t *testing.T) {
	hub := newWebSocketHub(nil)
	first := newTestClient(1, 0, 0, 0)
	second := newTestClient(2, 0, 0, 0)
	third := newTestClient(3, 0, 0, 0)

	hub.joinMatchmaking(first, wsIncoming{PlayerID: 101, Name: "First", Class: 0})
	hub.mu.Lock()
	roomID := first.roomID
	room := hub.rooms[roomID]
	firstTimer := room.fillTimer
	hub.mu.Unlock()
	if roomID == 0 || room == nil || firstTimer == nil {
		t.Fatal("first player did not create a waiting room with a bot timer")
	}

	hub.joinMatchmaking(second, wsIncoming{PlayerID: 102, Name: "Second", Class: 1})
	hub.mu.Lock()
	secondTimer := room.fillTimer
	hub.mu.Unlock()
	if second.roomID != roomID {
		t.Fatalf("second player joined room %d, want %d", second.roomID, roomID)
	}
	if secondTimer == firstTimer {
		t.Fatal("bot timer was not restarted for the second player")
	}

	hub.joinMatchmaking(third, wsIncoming{PlayerID: 103, Name: "Third", Class: 2})
	hub.mu.Lock()
	thirdTimer := room.fillTimer
	humans := room.humanCount
	if thirdTimer != nil {
		thirdTimer.Stop()
	}
	hub.mu.Unlock()
	if third.roomID != roomID {
		t.Fatalf("third player joined room %d, want %d", third.roomID, roomID)
	}
	if thirdTimer == secondTimer {
		t.Fatal("bot timer was not restarted for the third player")
	}
	if humans != 3 {
		t.Fatalf("expected 3 humans in one room, got %d", humans)
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
	if client.hp != 950 {
		t.Fatalf("respawn/heal packet did not raise HP: %v", client.hp)
	}

	hub.relayStats(client, wsIncoming{MaxHP: 1050, HP: 500, AttackDamage: 50})
	if client.hp != 950 {
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

func TestBotStatesCannotHealAliveBot(t *testing.T) {
	hub := newWebSocketHub(nil)
	host := newTestClient(1, 0, 0, 0)
	room := newTestRoom(host)
	room.bots[0] = &wsBot{id: -1, team: 0, alive: true, hp: 300, maxHP: 450, lastAttacks: make(map[string]time.Time)}
	hub.rooms[room.id] = room

	snapshot := wsBotSnapshot{ID: -1, X: 0, Y: 0.76, Z: 0, Rotation: 0, HP: 450, MaxHP: 450, Alive: true}
	hub.relayBotStates(host, wsIncoming{Bots: []wsBotSnapshot{snapshot}})
	if room.bots[0].hp != 300 {
		t.Fatalf("host packet healed a live bot to %v", room.bots[0].hp)
	}

	snapshot.HP = 120
	hub.relayBotStates(host, wsIncoming{Bots: []wsBotSnapshot{snapshot}})
	if room.bots[0].hp != 120 {
		t.Fatalf("host damage was not applied: %v", room.bots[0].hp)
	}

	snapshot.HP = 450
	hub.relayBotStates(host, wsIncoming{Bots: []wsBotSnapshot{snapshot}})
	if room.bots[0].hp != 120 {
		t.Fatalf("host packet healed a damaged bot back to %v", room.bots[0].hp)
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
	if update[0].StartsInMS < 25000 {
		t.Fatalf("join should reset the countdown, got %d ms", update[0].StartsInMS)
	}
}
