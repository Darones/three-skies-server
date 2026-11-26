package main

import (
	"math"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// These probes pin the HP revision contract the client relies on (network_manager.gd
// `tick`): a state packet and a damage/heal packet come from different server
// goroutines, so every HP-bearing message carries a per-entity revision and the
// client applies only newer revisions. Before this, an in-flight state could
// undo a confirmed hit or resurrect a corpse for a frame or two.

func findMessage(messages []wsOutgoing, kind string) *wsOutgoing {
	for index := range messages {
		if messages[index].Type == kind {
			return &messages[index]
		}
	}
	return nil
}

func TestHPTickOrderingContract(t *testing.T) {
	hub := newWebSocketHub(nil)
	first := newTestClient(1, 0, 0, 0)  // observer / attacker (team 0)
	second := newTestClient(2, 1, 0, 3) // target (team 1), sends the states
	room := newTestRoom(first, second)
	hub.rooms[room.id] = room

	// 1. A state sample is a revision.
	hub.updateState(second, wsIncoming{X: 0, Y: 0.76, Z: 3, Rotation: 0})
	messages := collectMessages(t, first)
	state1 := findMessage(messages, "state")
	if state1 == nil || state1.Tick <= 0 {
		t.Fatalf("state packet lost its revision: %+v", messages)
	}

	// 2. A confirmed hit gets a newer revision than the state before it.
	hub.handleAttackIntent(first, wsIncoming{TargetID: second.id, Skill: "auto", Amount: 100})
	messages = collectMessages(t, first)
	damage := findMessage(messages, "damage")
	if damage == nil {
		t.Fatalf("no damage packet: %+v", messages)
	}
	if damage.Tick <= state1.Tick {
		t.Fatalf("damage tick %d is not newer than the state before it %d", damage.Tick, state1.Tick)
	}
	if second.hp != second.maxHP-100 {
		t.Fatalf("server HP did not follow the confirmed hit: %v/%v", second.hp, second.maxHP)
	}

	// 3. The next state sample outranks the hit and carries the new HP.
	hub.updateState(second, wsIncoming{X: 0, Y: 0.76, Z: 3, Rotation: 0})
	messages = collectMessages(t, first)
	state2 := findMessage(messages, "state")
	if state2 == nil || state2.Tick <= damage.Tick {
		t.Fatalf("state after the hit lost the revision order: %+v", messages)
	}
	if state2.HP != second.hp {
		t.Fatalf("state HP %v != authoritative %v", state2.HP, second.hp)
	}

	// 4. A heal is its own revision, newer than the state before it.
	hub.relayHeal(second, wsIncoming{TargetID: second.id, Amount: 50})
	messages = collectMessages(t, first)
	heal := findMessage(messages, "heal")
	if heal == nil || heal.Tick <= state2.Tick {
		t.Fatalf("heal revision %+v is not newer than the state before it", messages)
	}
	if heal.Amount != 50 {
		t.Fatalf("heal amount %v, want 50", heal.Amount)
	}
	if second.hp != second.maxHP-50 {
		t.Fatalf("heal was not applied exactly once: %v/%v", second.hp, second.maxHP)
	}

	// 5. A lethal hit and its death share one revision: the client accepts the
	//    death with an equal tick and rejects an older one.
	second.hp = 10
	first.lastAttacks = make(map[string]time.Time)
	hub.handleAttackIntent(first, wsIncoming{TargetID: second.id, Skill: "auto", Amount: 100})
	messages = collectMessages(t, first)
	damage = findMessage(messages, "damage")
	death := findMessage(messages, "death")
	if damage == nil || death == nil {
		t.Fatalf("expected damage + death, got %+v", messages)
	}
	if death.Tick != damage.Tick {
		t.Fatalf("death tick %d does not match its lethal hit %d", death.Tick, damage.Tick)
	}
	if second.alive || second.hp != 0 {
		t.Fatalf("server did not register the death: alive=%v hp=%v", second.alive, second.hp)
	}

	// 6. Respawn outranks the death, and the next state outranks the respawn.
	second.diedAt = time.Now().Add(-7 * time.Second)
	hub.relayRespawn(second, wsIncoming{X: 0, Y: 0.76, Z: 28, Rotation: 0})
	messages = collectMessages(t, first)
	respawn := findMessage(messages, "respawn")
	if respawn == nil || respawn.Tick <= death.Tick {
		t.Fatalf("respawn revision is not newer than the death: %+v", messages)
	}
	if !second.alive || second.hp != second.maxHP {
		t.Fatalf("respawn did not restore the server HP: alive=%v hp=%v", second.alive, second.hp)
	}
	hub.updateState(second, wsIncoming{X: 0, Y: 0.76, Z: 28, Rotation: 0})
	messages = collectMessages(t, first)
	stateAfter := findMessage(messages, "state")
	if stateAfter == nil || stateAfter.Tick <= respawn.Tick {
		t.Fatalf("state after respawn is not newer than the respawn: %+v", messages)
	}
	if !stateAfter.Alive || stateAfter.HP != second.maxHP {
		t.Fatalf("state after respawn disagrees with the server: %+v", stateAfter)
	}
}

func TestCrystalHeartbeatRepairsDroppedState(t *testing.T) {
	hub := newWebSocketHub(nil)
	client := newTestClient(1, 0, 0, 0)
	room := newTestRoom(client)
	hub.rooms[room.id] = room
	room.crystal = &wsCrystalState{State: "carried", CarrierID: 2, X: 5, Y: 1, Z: 6}
	room.score = [2]int{1, 2}
	room.suddenDeath = true

	// No pickup/deliver event happened; only the periodic sync tick. A client
	// that missed the carrier's pickup must still learn who holds the shard.
	client.lastSync = time.Now().Add(-2 * time.Second)
	hub.updateState(client, wsIncoming{X: 0, Y: 0.76, Z: 0})
	messages := collectMessages(t, client)
	heartbeat := findMessage(messages, "crystal_sync")
	if heartbeat == nil || heartbeat.Crystal == nil {
		t.Fatalf("no crystal heartbeat on sync: %+v", messages)
	}
	if heartbeat.Crystal.State != "carried" || heartbeat.Crystal.CarrierID != 2 {
		t.Fatalf("heartbeat lost the carrier: %+v", heartbeat.Crystal)
	}
	// The same sync repairs a dropped match_score.
	sync := findMessage(messages, "sync")
	if sync == nil || sync.Score0 != 1 || sync.Score1 != 2 || !sync.SuddenDeath {
		t.Fatalf("sync lost the server score: %+v", sync)
	}
}

func TestBotSnapshotRevisions(t *testing.T) {
	hub := newWebSocketHub(nil)
	host := newTestClient(1, 0, 0, 0)
	room := newTestRoom(host)
	room.state = "live"
	room.bots[0] = &wsBot{
		id: -1, class: 0, team: 1, alive: true, hp: 1050, maxHP: 1050,
		x: 0, y: 0.76, z: 3, hasState: true,
		lastAttacks: make(map[string]time.Time),
	}
	hub.rooms[room.id] = room
	snapshot := wsBotSnapshot{ID: -1, X: 0, Y: 0.76, Z: 3, Rotation: 0, MaxHP: 1050, HP: 1050, Alive: true, Animation: "run"}

	hub.relayBotStates(host, wsIncoming{Bots: []wsBotSnapshot{snapshot}})
	messages := collectMessages(t, host)
	first := findMessage(messages, "bot_states")
	if first == nil || len(first.Bots) != 1 || first.Bots[0].Tick <= 0 {
		t.Fatalf("bot snapshot lost its revision: %+v", messages)
	}
	snapshotTick := first.Bots[0].Tick

	hub.handleBotDamage(host, wsIncoming{TargetID: -1, Amount: 50})
	messages = collectMessages(t, host)
	hit := findMessage(messages, "damage")
	if hit == nil || hit.Tick <= snapshotTick {
		t.Fatalf("bot damage revision %+v is not newer than the snapshot %d", messages, snapshotTick)
	}
	if room.bots[0].hp != 1000 {
		t.Fatalf("server bot HP did not follow the hit: %v", room.bots[0].hp)
	}

	snapshot.HP = room.bots[0].hp
	hub.relayBotStates(host, wsIncoming{Bots: []wsBotSnapshot{snapshot}})
	messages = collectMessages(t, host)
	next := findMessage(messages, "bot_states")
	if next == nil || next.Bots[0].Tick <= hit.Tick {
		t.Fatalf("next bot snapshot is not newer than the hit: %+v", messages)
	}
	if next.Bots[0].HP != room.bots[0].hp {
		t.Fatalf("bot snapshot HP %v != authoritative %v", next.Bots[0].HP, room.bots[0].hp)
	}
}

// TestStateRelayKeepsEveryPacket drives two real WebSocket clients: movement
// must be relayed one-for-one (no loss, no duplicates) and the HP revision must
// ride along on the wire.
func TestStateRelayKeepsEveryPacket(t *testing.T) {
	hub := newWebSocketHub(nil)
	server := httptest.NewServer(http.HandlerFunc(hub.handleWebSocket))
	defer server.Close()

	host := dialTestClient(t, server.URL)
	guest := dialTestClient(t, server.URL)
	hostWelcome := readUntilType(t, host, "welcome")
	guestWelcome := readUntilType(t, guest, "welcome")
	if hostWelcome.ID == guestWelcome.ID {
		t.Fatalf("clients share an id: %d", hostWelcome.ID)
	}

	if err := host.WriteJSON(map[string]any{"type": "join", "name": "Host", "class": 0, "class_name": "warrior", "player_id": 301}); err != nil {
		t.Fatalf("host join: %v", err)
	}
	if err := guest.WriteJSON(map[string]any{"type": "join", "name": "Guest", "class": 1, "class_name": "mage", "player_id": 302}); err != nil {
		t.Fatalf("guest join: %v", err)
	}
	roomJoined := readUntilType(t, host, "room_joined")
	_ = readUntilType(t, guest, "room_joined")
	hub.startRoom(roomJoined.RoomID)
	hostStart := readUntilType(t, host, "match_start")
	_ = readUntilType(t, guest, "match_start")

	var hostID int64
	for _, player := range hostStart.MatchPlayers {
		if !player.Bot && player.ID != guestWelcome.ID {
			hostID = player.ID
		}
	}
	if hostID == 0 {
		t.Fatalf("no human host in match_start: %+v", hostStart.MatchPlayers)
	}

	const states = 12
	lastX := 0.0
	lastTick := int64(0)
	for index := 0; index < states; index++ {
		lastX = float64(index) * 0.25
		if err := guest.WriteJSON(map[string]any{
			"type": "state", "x": lastX, "y": 0.76, "z": 0.0, "rotation": 0.0, "regen": 1.0,
		}); err != nil {
			t.Fatalf("guest state %d: %v", index, err)
		}
		state := readUntilType(t, host, "state")
		if state.ID != guestWelcome.ID {
			t.Fatalf("state for %d, want guest %d", state.ID, guestWelcome.ID)
		}
		if state.X != lastX {
			t.Fatalf("state %d relayed x=%v, want %v", index, state.X, lastX)
		}
		if state.Tick <= lastTick {
			t.Fatalf("state revisions are not increasing: %d then %d", lastTick, state.Tick)
		}
		lastTick = state.Tick
	}

	// Put both humans away from the base shield, then land one hit.
	if err := host.WriteJSON(map[string]any{"type": "state", "x": -10.0, "y": 0.76, "z": 0.0, "rotation": 0.0}); err != nil {
		t.Fatalf("host state: %v", err)
	}
	if err := guest.WriteJSON(map[string]any{"type": "state", "x": -9.0, "y": 0.76, "z": 0.0, "rotation": 0.0}); err != nil {
		t.Fatalf("guest near state: %v", err)
	}
	// The host's own state is not sent back to the host; wait until the server
	// has stored it so the range check uses the real positions.
	deadline := time.Now().Add(3 * time.Second)
	for {
		hub.mu.Lock()
		ready := false
		if room := hub.rooms[roomJoined.RoomID]; room != nil {
			if hostClient := findRoomPlayerLocked(room, hostID); hostClient != nil {
				ready = math.Abs(hostClient.x-(-10.0)) < 0.01 && hostClient.hasState
			}
		}
		hub.mu.Unlock()
		if ready {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("server never stored the host position")
		}
		time.Sleep(5 * time.Millisecond)
	}
	if err := guest.WriteJSON(map[string]any{"type": "attack_intent", "target_id": hostID, "skill": "auto"}); err != nil {
		t.Fatalf("guest attack: %v", err)
	}
	damage := readUntilType(t, host, "damage")
	if damage.TargetID != hostID || damage.Amount <= 0 {
		t.Fatalf("unexpected damage: %+v", damage)
	}
	if damage.Tick <= 0 {
		t.Fatalf("damage packet lost its revision: %+v", damage)
	}
}
