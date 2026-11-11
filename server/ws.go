package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	wsWriteWait      = 10 * time.Second
	wsPongWait       = 60 * time.Second
	wsPingPeriod     = (wsPongWait * 9) / 10
	wsMaxMessageSize = 4096
	wsSendBuffer     = 64
)

var wsUpgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	// The first version is used by Godot clients and future web builds from
	// different origins; authentication is not implemented yet.
	CheckOrigin: func(r *http.Request) bool { return true },
}

type wsHub struct {
	mu      sync.RWMutex
	clients map[int64]*wsClient
	nextID  int64
}

type wsClient struct {
	id        int64
	conn      *websocket.Conn
	hub       *wsHub
	send      chan []byte
	done      chan struct{}
	closeOnce sync.Once

	name     string
	class    int
	team     int
	x        float64
	y        float64
	z        float64
	rotation float64
	hasState bool
	joined   bool
}

type wsIncoming struct {
	Type     string  `json:"type"`
	Name     string  `json:"name"`
	Class    int     `json:"class"`
	Team     int     `json:"team"`
	X        float64 `json:"x"`
	Y        float64 `json:"y"`
	Z        float64 `json:"z"`
	Rotation float64 `json:"rotation"`
}

type wsPlayerSnapshot struct {
	ID       int64   `json:"id"`
	Name     string  `json:"name"`
	Class    int     `json:"class"`
	Team     int     `json:"team"`
	X        float64 `json:"x"`
	Y        float64 `json:"y"`
	Z        float64 `json:"z"`
	Rotation float64 `json:"rotation"`
	HasState bool    `json:"has_state"`
}

type wsOutgoing struct {
	Type     string             `json:"type"`
	ID       int64              `json:"id"`
	Name     string             `json:"name,omitempty"`
	Class    int                `json:"class"`
	Team     int                `json:"team"`
	X        float64            `json:"x"`
	Y        float64            `json:"y"`
	Z        float64            `json:"z"`
	Rotation float64            `json:"rotation"`
	Players  []wsPlayerSnapshot `json:"players,omitempty"`
	Error    string             `json:"error,omitempty"`
}

func newWebSocketHub() *wsHub {
	return &wsHub{clients: make(map[int64]*wsClient)}
}

func (h *wsHub) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("websocket upgrade: %v", err)
		return
	}
	// Clear the HTTP server's request deadlines; the WebSocket pumps below
	// manage their own read and write deadlines.
	_ = conn.SetReadDeadline(time.Time{})
	_ = conn.SetWriteDeadline(time.Time{})

	client := &wsClient{
		conn: conn,
		hub:  h,
		send: make(chan []byte, wsSendBuffer),
		done: make(chan struct{}),
	}
	h.addClient(client)
	log.Printf("ws client %d connected", client.id)

	go client.writePump()
	client.readPump()
}

func (h *wsHub) addClient(client *wsClient) {
	h.mu.Lock()
	h.nextID++
	client.id = h.nextID
	h.clients[client.id] = client
	players := make([]wsPlayerSnapshot, 0, len(h.clients)-1)
	for id, other := range h.clients {
		if id == client.id {
			continue
		}
		players = append(players, other.snapshot())
	}
	h.mu.Unlock()

	client.sendJSON(wsOutgoing{Type: "welcome", ID: client.id, Players: players})
}

func (h *wsHub) removeClient(client *wsClient) {
	h.mu.Lock()
	_, exists := h.clients[client.id]
	if exists {
		delete(h.clients, client.id)
	}
	h.mu.Unlock()
	if !exists {
		return
	}
	client.close()
	log.Printf("ws client %d disconnected", client.id)
	h.broadcast(wsOutgoing{Type: "player_left", ID: client.id})
}

func (h *wsHub) updateJoin(client *wsClient, message wsIncoming) {
	name := strings.TrimSpace(message.Name)
	if name == "" {
		name = fmt.Sprintf("Игрок %d", client.id)
	}
	runes := []rune(name)
	if len(runes) > 32 {
		name = string(runes[:32])
	}
	class := message.Class
	if class < 0 || class > 2 {
		class = 0
	}
	team := message.Team
	if team < 0 || team > 1 {
		team = 0
	}

	h.mu.Lock()
	if _, exists := h.clients[client.id]; !exists {
		h.mu.Unlock()
		return
	}
	client.name = name
	client.class = class
	client.team = team
	client.joined = true
	h.mu.Unlock()

	h.broadcastExcept(client.id, wsOutgoing{
		Type:  "player_joined",
		ID:    client.id,
		Name:  name,
		Class: class,
		Team:  team,
	})
}

func (h *wsHub) updateState(client *wsClient, message wsIncoming) {
	if !finite(message.X) || !finite(message.Y) || !finite(message.Z) || !finite(message.Rotation) {
		return
	}

	h.mu.Lock()
	if _, exists := h.clients[client.id]; !exists {
		h.mu.Unlock()
		return
	}
	client.x = message.X
	client.y = message.Y
	client.z = message.Z
	client.rotation = message.Rotation
	client.hasState = true
	firstPacket := !client.joined
	if firstPacket {
		client.joined = true
		if client.name == "" {
			client.name = fmt.Sprintf("Игрок %d", client.id)
		}
	}
	name := client.name
	class := client.class
	team := client.team
	x := client.x
	y := client.y
	z := client.z
	rotation := client.rotation
	h.mu.Unlock()

	if firstPacket {
		h.broadcastExcept(client.id, wsOutgoing{
			Type:  "player_joined",
			ID:    client.id,
			Name:  name,
			Class: class,
			Team:  team,
		})
	}
	h.broadcastExcept(client.id, wsOutgoing{
		Type:     "state",
		ID:       client.id,
		Class:    class,
		Team:     team,
		X:        x,
		Y:        y,
		Z:        z,
		Rotation: rotation,
	})
}

func (h *wsHub) broadcast(message wsOutgoing) {
	h.broadcastExcept(0, message)
}

func (h *wsHub) broadcastExcept(exceptID int64, message wsOutgoing) {
	data, err := json.Marshal(message)
	if err != nil {
		log.Printf("websocket marshal: %v", err)
		return
	}
	h.mu.RLock()
	targets := make([]*wsClient, 0, len(h.clients))
	for id, client := range h.clients {
		if id != exceptID {
			targets = append(targets, client)
		}
	}
	h.mu.RUnlock()
	for _, client := range targets {
		client.trySend(data)
	}
}

func (c *wsClient) snapshot() wsPlayerSnapshot {
	name := c.name
	if name == "" {
		name = fmt.Sprintf("Игрок %d", c.id)
	}
	return wsPlayerSnapshot{
		ID:       c.id,
		Name:     name,
		Class:    c.class,
		Team:     c.team,
		X:        c.x,
		Y:        c.y,
		Z:        c.z,
		Rotation: c.rotation,
		HasState: c.hasState,
	}
}

func (c *wsClient) readPump() {
	defer func() {
		c.hub.removeClient(c)
		c.close()
	}()
	c.conn.SetReadLimit(wsMaxMessageSize)
	_ = c.conn.SetReadDeadline(time.Now().Add(wsPongWait))
	c.conn.SetPongHandler(func(string) error {
		return c.conn.SetReadDeadline(time.Now().Add(wsPongWait))
	})

	for {
		_, data, err := c.conn.ReadMessage()
		if err != nil {
			return
		}
		var message wsIncoming
		if err := json.Unmarshal(data, &message); err != nil {
			continue
		}
		switch message.Type {
		case "join":
			c.hub.updateJoin(c, message)
		case "state":
			c.hub.updateState(c, message)
		}
	}
}

func (c *wsClient) writePump() {
	ticker := time.NewTicker(wsPingPeriod)
	defer func() {
		ticker.Stop()
		c.close()
	}()

	for {
		select {
		case <-c.done:
			_ = c.conn.WriteControl(
				websocket.CloseMessage,
				websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""),
				time.Now().Add(wsWriteWait),
			)
			return
		case data := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(wsWriteWait))
			if err := c.conn.WriteMessage(websocket.TextMessage, data); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(wsWriteWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (c *wsClient) sendJSON(message wsOutgoing) {
	data, err := json.Marshal(message)
	if err != nil {
		log.Printf("websocket marshal: %v", err)
		return
	}
	c.trySend(data)
}

func (c *wsClient) trySend(data []byte) {
	select {
	case <-c.done:
		return
	default:
	}
	select {
	case c.send <- data:
	default:
		// Slow client: drop this frame instead of blocking the hub.
	}
}

func (c *wsClient) close() {
	c.closeOnce.Do(func() {
		close(c.done)
		_ = c.conn.Close()
	})
}

func finite(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0) && math.Abs(value) < 1e7
}
