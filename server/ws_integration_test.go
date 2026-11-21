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
	hostWelcome := readUntilType(t, host, "welcome")
	guestWelcome := readUntilType(t, guest, "welcome")
	if hostWelcome.Protocol != 4 || guestWelcome.Protocol != 4 {
		t.Fatalf("expected protocol 4, got host=%d guest=%d", hostWelcome.Protocol, guestWelcome.Protocol)
	}

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
	var enemyBotMaxHP float64
	for _, player := range hostStart.MatchPlayers {
		if player.Bot && player.Team == 0 {
			enemyBotID = player.ID
			enemyBotMaxHP = player.MaxHP
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
	if relayedEnemy == nil || relayedEnemy.HP != enemyBotMaxHP || relayedEnemy.Animation != "run" {
		t.Fatalf("unexpected relayed bot state: %+v", relayed.Bots)
	}
	// Drain the host's copy of the same initial snapshot.
	_ = readUntilType(t, host, "bot_states")

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

	// Server owns bot HP: the host's own snapshot must not raise it.
	if err := host.WriteJSON(map[string]any{"type": "bot_states", "bots": []map[string]any{{
		"id": enemyBotID, "x": -2.0, "y": 0.76, "z": 26.0, "rotation": 0.0,
		"max_hp": enemyBotMaxHP, "hp": enemyBotMaxHP, "attack_damage": 30.0, "alive": true, "animation": "run",
	}}}); err != nil {
		t.Fatalf("host bot state after damage: %v", err)
	}
	hostBotState := readUntilType(t, host, "bot_states")
	findBot := func(state wsOutgoing) *wsBotSnapshot {
		for index := range state.Bots {
			if state.Bots[index].ID == enemyBotID {
				return &state.Bots[index]
			}
		}
		return nil
	}
	serverBot := findBot(hostBotState)
	if serverBot == nil || serverBot.HP != enemyBotMaxHP-damage.Amount {
		t.Fatalf("server bot HP did not follow confirmed damage: %+v", hostBotState.Bots)
	}
	if err := host.WriteJSON(map[string]any{"type": "bot_states", "bots": []map[string]any{{
		"id": enemyBotID, "x": -2.0, "y": 0.76, "z": 26.0, "rotation": 0.0,
		"max_hp": enemyBotMaxHP, "hp": enemyBotMaxHP, "attack_damage": 30.0, "alive": true, "animation": "run",
	}}}); err != nil {
		t.Fatalf("host stale bot state: %v", err)
	}
	hostBotState = readUntilType(t, host, "bot_states")
	serverBot = findBot(hostBotState)
	if serverBot == nil || serverBot.HP != enemyBotMaxHP-damage.Amount {
		t.Fatalf("host snapshot raised server bot HP: %+v", hostBotState.Bots)
	}

	// A host heal is applied by the server for a negative target (bot).
	if err := host.WriteJSON(map[string]any{"type": "heal", "target_id": enemyBotID, "amount": 100.0}); err != nil {
		t.Fatalf("host bot heal: %v", err)
	}
	if err := host.WriteJSON(map[string]any{"type": "bot_states", "bots": []map[string]any{{
		"id": enemyBotID, "x": -2.0, "y": 0.76, "z": 26.0, "rotation": 0.0,
		"max_hp": enemyBotMaxHP, "hp": enemyBotMaxHP, "attack_damage": 30.0, "alive": true, "animation": "run",
	}}}); err != nil {
		t.Fatalf("host bot state after heal: %v", err)
	}
	hostBotState = readUntilType(t, host, "bot_states")
	serverBot = findBot(hostBotState)
	expectedHealHP := enemyBotMaxHP - damage.Amount + 100
	if expectedHealHP > enemyBotMaxHP {
		expectedHealHP = enemyBotMaxHP
	}
	if serverBot == nil || serverBot.HP != expectedHealHP {
		t.Fatalf("server bot heal did not apply: %+v", hostBotState.Bots)
	}

	// Server owns the shell HP/state and applies shell damage.
	if err := host.WriteJSON(map[string]any{"type": "shell_state", "shell": map[string]any{
		"alive": true, "x": 0.0, "y": 0.45, "z": 0.0, "phase": "active",
	}}); err != nil {
		t.Fatalf("shell state: %v", err)
	}
	shellState := readUntilType(t, guest, "shell_state")
	if shellState.Shell == nil || !shellState.Shell.Alive || shellState.Shell.HP != 1000 {
		t.Fatalf("server shell did not start at full HP: %+v", shellState.Shell)
	}
	_ = readUntilType(t, host, "shell_state")
	if err := guest.WriteJSON(map[string]any{"type": "state", "x": 0.0, "y": 0.76, "z": 2.0, "rotation": 0.0}); err != nil {
		t.Fatalf("guest shell position: %v", err)
	}
	if err := guest.WriteJSON(map[string]any{"type": "shell_attack", "amount": 300.0}); err != nil {
		t.Fatalf("guest shell attack: %v", err)
	}
	shellState = readUntilType(t, guest, "shell_state")
	if shellState.Shell == nil || shellState.Shell.HP != 700 {
		t.Fatalf("server shell damage not applied: %+v", shellState.Shell)
	}
	if err := host.WriteJSON(map[string]any{"type": "shell_state", "shell": map[string]any{
		"alive": true, "x": 0.0, "y": 0.45, "z": 0.0, "phase": "active", "hp": 100.0, "max_hp": 100.0,
	}}); err != nil {
		t.Fatalf("host shell HP snapshot: %v", err)
	}
	shellState = readUntilType(t, host, "shell_state")
	if shellState.Shell == nil || shellState.Shell.HP != 700 {
		t.Fatalf("host shell HP overwrote server HP: %+v", shellState.Shell)
	}
	// The same 700 broadcast is queued for the guest; drain it before the kill.
	_ = readUntilType(t, guest, "shell_state")
	time.Sleep(600 * time.Millisecond)
	if err := guest.WriteJSON(map[string]any{"type": "shell_attack", "amount": 800.0}); err != nil {
		t.Fatalf("guest killing shell attack: %v", err)
	}
	shellState = readUntilType(t, guest, "shell_state")
	if shellState.Shell == nil || shellState.Shell.Alive || shellState.Shell.HP != 0 {
		t.Fatalf("shell death was not server-owned: %+v", shellState.Shell)
	}
	shellEvent := readUntilType(t, guest, "match_event")
	if shellEvent.Event != "shell_destroyed" {
		t.Fatalf("expected shell_destroyed, got %+v", shellEvent)
	}
	if shellEvent.Team != 1 || shellEvent.SourceID != guestWelcome.ID {
		t.Fatalf("shell kill was not attributed to the guest: %+v", shellEvent)
	}
	crystalState := readUntilType(t, guest, "crystal_state")
	if crystalState.Crystal == nil || crystalState.Crystal.State != "ground" {
		t.Fatalf("shell death did not spawn a ground crystal: %+v", crystalState.Crystal)
	}
	if err := guest.WriteJSON(map[string]any{"type": "crystal_pickup"}); err != nil {
		t.Fatalf("crystal pickup: %v", err)
	}
	crystalState = readUntilType(t, guest, "crystal_state")
	if crystalState.Crystal == nil || crystalState.Crystal.State != "carried" || crystalState.Crystal.CarrierID == 0 {
		t.Fatalf("crystal pickup not owned by server: %+v", crystalState.Crystal)
	}
	if err := guest.WriteJSON(map[string]any{"type": "state", "x": 0.0, "y": 0.76, "z": -27.0, "rotation": 0.0}); err != nil {
		t.Fatalf("guest base state: %v", err)
	}
	if err := guest.WriteJSON(map[string]any{"type": "crystal_deliver"}); err != nil {
		t.Fatalf("crystal deliver: %v", err)
	}
	crystalState = readUntilType(t, guest, "crystal_state")
	if crystalState.Crystal == nil || crystalState.Crystal.State != "none" {
		t.Fatalf("crystal delivery not owned by server: %+v", crystalState.Crystal)
	}
	deliveryEvent := readUntilType(t, guest, "match_event")
	if deliveryEvent.Event != "shard_delivered" || deliveryEvent.Team != 1 || deliveryEvent.SourceID != guestWelcome.ID {
		t.Fatalf("shard delivery was not attributed to the guest: %+v", deliveryEvent)
	}
	crystalScore := readUntilType(t, guest, "match_score")
	if crystalScore.Score0 != 0 || crystalScore.Score1 != 1 {
		t.Fatalf("unexpected score after crystal delivery: %+v", crystalScore)
	}
	// The host also received the 0:1 score; drain it before the 3 shard loop.
	_ = readUntilType(t, host, "match_score")

	if err := host.WriteJSON(map[string]any{"type": "state", "x": 0.0, "y": 0.76, "z": 27.0, "rotation": 0.0}); err != nil {
		t.Fatalf("host base state: %v", err)
	}
	for delivery := 0; delivery < crystalsToWin; delivery++ {
		hub.mu.Lock()
		if room := hub.rooms[hostJoined.RoomID]; room != nil {
			room.crystal = &wsCrystalState{State: "carried", CarrierID: hostWelcome.ID}
		}
		hub.mu.Unlock()
		if err := host.WriteJSON(map[string]any{"type": "crystal_deliver"}); err != nil {
			t.Fatalf("host crystal delivery %d: %v", delivery+1, err)
		}
		scoreMessage := readUntilType(t, host, "match_score")
		if scoreMessage.Score0 != delivery+1 {
			t.Fatalf("unexpected score after delivery %d: %+v", delivery+1, scoreMessage)
		}
	}
	finished := readUntilType(t, guest, "match_finished")
	if finished.WinningTeam != 0 {
		t.Fatalf("expected server winner team 0, got %+v", finished)
	}
}

// TestHumanCarrierDropsCrystalOnDeath covers the bug where a human carrier
// kept the shard after dying: the server only dropped it for bots, so the
// crystal stayed "carried" by a corpse and could never be picked up.
func TestHumanCarrierDropsCrystalOnDeath(t *testing.T) {
	hub := newWebSocketHub(nil)
	server := httptest.NewServer(http.HandlerFunc(hub.handleWebSocket))
	defer server.Close()

	host := dialTestClient(t, server.URL)
	guest := dialTestClient(t, server.URL)
	hostWelcome := readUntilType(t, host, "welcome")
	guestWelcome := readUntilType(t, guest, "welcome")

	if err := host.WriteJSON(map[string]any{
		"type": "join", "name": "Host", "class": 0, "class_name": "warrior", "player_id": 201,
	}); err != nil {
		t.Fatalf("host join: %v", err)
	}
	if err := guest.WriteJSON(map[string]any{
		"type": "join", "name": "Guest", "class": 1, "class_name": "mage", "player_id": 202,
	}); err != nil {
		t.Fatalf("guest join: %v", err)
	}
	hostJoined := readUntilType(t, host, "room_joined")
	_ = readUntilType(t, guest, "room_joined")
	hub.startRoom(hostJoined.RoomID)
	_ = readUntilType(t, host, "match_start")
	_ = readUntilType(t, guest, "match_start")

	if err := host.WriteJSON(map[string]any{"type": "shell_state", "shell": map[string]any{
		"alive": true, "x": 0.0, "y": 0.45, "z": 0.0, "phase": "active",
	}}); err != nil {
		t.Fatalf("shell state: %v", err)
	}
	_ = readUntilType(t, host, "shell_state")
	_ = readUntilType(t, guest, "shell_state")

	if err := host.WriteJSON(map[string]any{"type": "state", "x": 0.0, "y": 0.76, "z": 2.0, "rotation": 0.0}); err != nil {
		t.Fatalf("host state: %v", err)
	}
	if err := guest.WriteJSON(map[string]any{"type": "state", "x": 0.0, "y": 0.76, "z": -2.0, "rotation": 0.0}); err != nil {
		t.Fatalf("guest state: %v", err)
	}
	if err := host.WriteJSON(map[string]any{"type": "shell_attack", "amount": 500.0}); err != nil {
		t.Fatalf("host shell attack: %v", err)
	}
	for {
		state := readUntilType(t, host, "shell_state")
		if state.Shell != nil && state.Shell.HP == 500 {
			break
		}
	}
	if err := guest.WriteJSON(map[string]any{"type": "shell_attack", "amount": 500.0}); err != nil {
		t.Fatalf("guest shell attack: %v", err)
	}
	for {
		state := readUntilType(t, guest, "shell_state")
		if state.Shell != nil && !state.Shell.Alive {
			break
		}
	}

	var ground *wsCrystalState
	for {
		state := readUntilType(t, guest, "crystal_state")
		if state.Crystal != nil && state.Crystal.State == "ground" {
			ground = state.Crystal
			break
		}
	}
	if ground == nil {
		t.Fatal("shell death did not drop a crystal")
	}

	if err := guest.WriteJSON(map[string]any{"type": "state", "x": ground.X, "y": 0.76, "z": ground.Z, "rotation": 0.0}); err != nil {
		t.Fatalf("guest pickup position: %v", err)
	}
	if err := guest.WriteJSON(map[string]any{"type": "crystal_pickup"}); err != nil {
		t.Fatalf("crystal pickup: %v", err)
	}
	for {
		state := readUntilType(t, host, "crystal_state")
		if state.Crystal != nil && state.Crystal.State == "carried" && state.Crystal.CarrierID == guestWelcome.ID {
			break
		}
	}

	if err := host.WriteJSON(map[string]any{"type": "state", "x": ground.X + 1.0, "y": 0.76, "z": ground.Z, "rotation": 0.0}); err != nil {
		t.Fatalf("host attack position: %v", err)
	}
	// 400 is within the server's per-hit cap for every class; the auto skill
	// has a 250 ms cooldown, so a few spaced hits kill any class.
	for hit := 0; hit < 4; hit++ {
		if err := host.WriteJSON(map[string]any{
			"type": "attack_intent", "target_id": guestWelcome.ID, "skill": "auto", "amount": 400.0,
		}); err != nil {
			t.Fatalf("host attack %d: %v", hit, err)
		}
		time.Sleep(300 * time.Millisecond)
	}
	death := readUntilType(t, host, "death")
	if death.ID != guestWelcome.ID {
		t.Fatalf("expected guest death, got %+v", death)
	}
	if death.SourceID != hostWelcome.ID {
		t.Fatalf("death was not attributed to the host: %+v", death)
	}
	for {
		state := readUntilType(t, guest, "crystal_state")
		if state.Crystal != nil && state.Crystal.State == "ground" {
			if state.Crystal.CarrierID != 0 {
				t.Fatalf("dropped crystal still has a carrier: %+v", state.Crystal)
			}
			return
		}
	}
}
