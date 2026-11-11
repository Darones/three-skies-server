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
		name:         "Бот-Фея-3",
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
		room.lastDelivery = time.Time{}
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
