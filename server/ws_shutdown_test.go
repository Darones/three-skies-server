package main

import "testing"

func TestFinishLiveMatchesMarksRoomFinished(t *testing.T) {
	hub := newWebSocketHub(nil)
	host := newTestClient(1, 0, 0, 0)
	guest := newTestClient(2, 1, 0, 0)
	room := newTestRoom(host, guest)
	room.score = [2]int{2, 1}
	hub.rooms[room.id] = room

	hub.finishLiveMatches("server_restart")

	if room.state != "finished" {
		t.Fatalf("expected finished room, got %q", room.state)
	}
	if !room.resultSaved {
		t.Fatal("expected the shutdown result to be saved")
	}
}
