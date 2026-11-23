package main

import (
	"math"
	"testing"
	"time"
)

func TestUpdateStateRegenUsesClientMultiplier(t *testing.T) {
	hub := newWebSocketHub(nil)
	client := newTestClient(1, 0, 0, 0)
	room := newTestRoom(client)
	hub.rooms[room.id] = room
	client.hp = 100
	client.lastRegen = time.Now().Add(-time.Second)
	client.lastDamaged = time.Time{}

	hub.updateState(client, wsIncoming{X: 0, Y: 0.76, Z: 0, Rotation: 0, Regen: 2})

	// 10 HP/s base rate x2 for bush/blessing, one second of regen.
	if math.Abs(client.hp-120.0) > 0.01 {
		t.Fatalf("expected 120 HP after doubled regen, got %.2f", client.hp)
	}
}

func TestUpdateStateBaseRegenUsesClientBasePosition(t *testing.T) {
	hub := newWebSocketHub(nil)
	client := newTestClient(1, 0, 0, 0)
	room := newTestRoom(client)
	hub.rooms[room.id] = room
	client.x = 0
	client.z = 21.2
	client.hp = 100
	client.lastRegen = time.Now().Add(-time.Second)
	client.lastDamaged = time.Time{}

	hub.updateState(client, wsIncoming{X: 0, Y: 0.76, Z: 21.2, Rotation: 0, Regen: 2})

	// 6.8 units from the real base (z=28) is outside the 6.5 radius. The old
	// z=27.5 center treated this spot as "at base" and healed 100 HP/s.
	if math.Abs(client.hp-120.0) > 0.01 {
		t.Fatalf("expected field regen outside base (120 HP), got %.2f", client.hp)
	}
}

func TestUpdateStateBaseRegenIsNotMultiplied(t *testing.T) {
	hub := newWebSocketHub(nil)
	client := newTestClient(1, 0, 0, 0)
	room := newTestRoom(client)
	hub.rooms[room.id] = room
	client.x = 0
	client.z = 28.0
	client.hp = 100
	client.lastRegen = time.Now().Add(-time.Second)
	client.baseStandSince = time.Now().Add(-10 * time.Second)

	hub.updateState(client, wsIncoming{X: 0, Y: 0.76, Z: 28.0, Rotation: 0, Regen: 2})

	if math.Abs(client.hp-200.0) > 0.01 {
		t.Fatalf("expected 100 HP/s base heal on top of 100 HP, got %.2f", client.hp)
	}
}
