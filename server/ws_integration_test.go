package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

func dialTestClient(t *testing.T, serverURL string) *websocket.Conn {
	t.Helper()
	url := "ws" + strings.TrimPrefix(serverURL, "http")
	conn, _, err := websocket.DefaultDialer.Dial(url, nil)
	if err != nil {
		t.Fatalf("dial websocket: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	return conn
}

func readUntilType(t *testing.T, conn *websocket.Conn, messageType string) wsOutgoing {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	for {
		var message wsOutgoing
		if err := conn.ReadJSON(&message); err != nil {
			t.Fatalf("read %s: %v", messageType, err)
		}
		if message.Type == messageType {
			return message
		}
	}
}

func TestWebSocketBotSyncAndServerValidation(t *testing.T) {
	hub := newWebSocketHub(nil)
	server := httptest.NewServer(http.HandlerFunc(hub.handleWebSocket))
	defer server.Close()

	host := dialTestClient(t, server.URL)
	guest := dialTestClient(t, server.URL)
	readUntilType(t, host, "welcome")
	readUntilType(t, guest, "welcome")

	if err := host.WriteJSON(map[string]any{
		"type": "join", "name": "Host", "class": 0, "class_name": "warrior", "player_id": 101,
	}); err != nil {
		t.Fatalf("host join: %v", err)
	}
	if err := guest.WriteJSON(map[string]any{
		"type": "join", "name": "Guest", "class": 1, "class_name": "mage", "player_id": 102,
	}); err != nil {
		t.Fatalf("guest join: %v", err)
	}
	hostJoined := readUntilType(t, host, "room_joined")
	guestJoined := readUntilType(t, guest, "room_joined")
	if hostJoined.RoomID == 0 || hostJoined.RoomID != guestJoined.RoomID {
		t.Fatalf("clients did not share a room: %+v %+v", hostJoined, guestJoined)
	}

	hub.startRoom(hostJoined.RoomID)
	hostStart := readUntilType(t, host, "match_start")
	guestStart := readUntilType(t, guest, "match_start")
	if len(hostStart.MatchPlayers) != roomSlots || len(guestStart.MatchPlayers) != roomSlots {
		t.Fatalf("expected %d match players", roomSlots)
	}
	var enemyBotID int64
	for _, player := range hostStart.MatchPlayers {
		if player.Bot && player.Team == 0 {
			enemyBotID = player.ID
		}
	}
	if enemyBotID >= 0 {
		t.Fatal("no enemy bot in match_start")
	}

	botState := []map[string]any{{
		"id": enemyBotID, "x": -2.0, "y": 0.76, "z": 26.0, "rotation": 0.0,
		"max_hp": 450.0, "hp": 400.0, "attack_damage": 30.0, "alive": true, "animation": "run",
	}}
	if err := host.WriteJSON(map[string]any{"type": "bot_states", "bots": botState}); err != nil {
		t.Fatalf("host bot states: %v", err)
	}
	relayed := readUntilType(t, guest, "bot_states")
	var relayedEnemy *wsBotSnapshot
	for index := range relayed.Bots {
		if relayed.Bots[index].ID == enemyBotID {
			relayedEnemy = &relayed.Bots[index]
		}
	}
	if relayedEnemy == nil || relayedEnemy.HP != 400 || relayedEnemy.Animation != "run" {
		t.Fatalf("unexpected relayed bot state: %+v", relayed.Bots)
	}

	if err := guest.WriteJSON(map[string]any{
		"type": "state", "x": -2.0, "y": 0.76, "z": 25.0, "rotation": 0.0,
	}); err != nil {
		t.Fatalf("guest state: %v", err)
	}
	if err := guest.WriteJSON(map[string]any{
		"type": "attack_intent", "target_id": enemyBotID, "skill": "auto",
	}); err != nil {
		t.Fatalf("guest attack: %v", err)
	}
	damage := readUntilType(t, guest, "damage")
	if damage.TargetID != enemyBotID || damage.Amount <= 0 {
		t.Fatalf("unexpected damage: %+v", damage)
	}

	if err := guest.WriteJSON(map[string]any{
		"type": "attack_intent", "target_id": enemyBotID, "skill": "auto",
	}); err != nil {
		t.Fatalf("guest spam attack: %v", err)
	}
	denied := readUntilType(t, guest, "attack_denied")
	if denied.Reason != "cooldown" {
		t.Fatalf("expected cooldown denial, got %+v", denied)
	}

	if err := guest.WriteJSON(map[string]any{
		"type": "state", "x": 40.0, "y": 0.76, "z": -30.0, "rotation": 0.0,
	}); err != nil {
		t.Fatalf("guest far state: %v", err)
	}
	if err := guest.WriteJSON(map[string]any{
		"type": "attack_intent", "target_id": enemyBotID, "skill": "auto",
	}); err != nil {
		t.Fatalf("guest far attack: %v", err)
	}
	denied = readUntilType(t, guest, "attack_denied")
	if denied.Reason != "out_of_range" {
		t.Fatalf("expected out_of_range denial, got %+v", denied)
	}

	for delivery := 0; delivery < crystalsToWin; delivery++ {
		if err := host.WriteJSON(map[string]any{
			"type": "match_event", "event": "shard_delivered", "team": 0,
		}); err != nil {
			t.Fatalf("match event: %v", err)
		}
		scoreMessage := readUntilType(t, host, "match_score")
		if scoreMessage.Score0 != delivery+1 {
			t.Fatalf("unexpected score after delivery %d: %+v", delivery+1, scoreMessage)
		}
		hub.mu.Lock()
		if room := hub.rooms[hostJoined.RoomID]; room != nil {
			room.lastDelivery = [2]time.Time{}
		}
		hub.mu.Unlock()
	}
	finished := readUntilType(t, guest, "match_finished")
	if finished.WinningTeam != 0 {
		t.Fatalf("expected server winner team 0, got %+v", finished)
	}
}
