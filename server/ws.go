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

	name         string
	class        int
	team         int
	x            float64
	y            float64
	z            float64
	rotation     float64
	hasState     bool
	joined       bool
	alive        bool
	maxHP        float64
	hp           float64
	attackDamage float64
}

type wsIncoming struct {
	Type         string  `json:"type"`
	Name         string  `json:"name"`
	Class        int     `json:"class"`
	Team         int     `json:"team"`
	X            float64 `json:"x"`
	Y            float64 `json:"y"`
	Z            float64 `json:"z"`
	Rotation     float64 `json:"rotation"`
	TargetID     int64   `json:"target_id"`
	SourceID     int64   `json:"source_id"`
	AttackType   string  `json:"attack_type"`
	Amount       float64 `json:"amount"`
	MaxHP        float64 `json:"max_hp"`
	HP           float64 `json:"hp"`
	AttackDamage float64 `json:"attack_damage"`
}

type wsPlayerSnapshot struct {
	ID           int64   `json:"id"`
	Name         string  `json:"name"`
	Class        int     `json:"class"`
	Team         int     `json:"team"`
	X            float64 `json:"x"`
	Y            float64 `json:"y"`
	Z            float64 `json:"z"`
	Rotation     float64 `json:"rotation"`
	HasState     bool    `json:"has_state"`
	Alive        bool    `json:"alive"`
	MaxHP        float64 `json:"max_hp"`
	HP           float64 `json:"hp"`
	AttackDamage float64 `json:"attack_damage"`
}

type wsOutgoing struct {
	Type         string             `json:"type"`
	ID           int64              `json:"id"`
	Name         string             `json:"name,omitempty"`
	Class        int                `json:"class"`
	Team         int                `json:"team"`
	X            float64            `json:"x"`
	Y            float64            `json:"y"`
	Z            float64            `json:"z"`
	Rotation     float64            `json:"rotation"`
	TargetID     int64              `json:"target_id,omitempty"`
	SourceID     int64              `json:"source_id,omitempty"`
	AttackType   string             `json:"attack_type,omitempty"`
	Amount       float64            `json:"amount,omitempty"`
	MaxHP        float64            `json:"max_hp,omitempty"`
	HP           float64            `json:"hp,omitempty"`
	AttackDamage float64            `json:"attack_damage,omitempty"`
	Players      []wsPlayerSnapshot `json:"players,omitempty"`
	Error        string             `json:"error,omitempty"`
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
		conn:  conn,
		hub:   h,
		send:  make(chan []byte, wsSendBuffer),
		done:  make(chan struct{}),
		alive: true,
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
	// The relay assigns teams deterministically so two clients always start
	// on opposite sides, regardless of which value the client proposed.
	team := int((client.id - 1) % 2)

	h.mu.Lock()
	if _, exists := h.clients[client.id]; !exists {
		h.mu.Unlock()
		return
	}
	client.name = name
	client.class = class
	client.team = team
	client.joined = true
	maxHP := client.maxHP
	hp := client.hp
	attackDamage := client.attackDamage
	h.mu.Unlock()

	h.broadcastExcept(client.id, wsOutgoing{
		Type:         "player_joined",
		ID:           client.id,
		Name:         name,
		Class:        class,
		Team:         team,
		MaxHP:        maxHP,
		HP:           hp,
		AttackDamage: attackDamage,
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

func (h *wsHub) relayAttack(client *wsClient, message wsIncoming) {
	attackType := strings.TrimSpace(message.AttackType)
	if attackType == "" {
		attackType = "auto"
	}
	runes := []rune(attackType)
	if len(runes) > 32 {
		attackType = string(runes[:32])
	}
	h.broadcastExcept(client.id, wsOutgoing{
		Type:       "attack",
		ID:         client.id,
		SourceID:   client.id,
		TargetID:   message.TargetID,
		AttackType: attackType,
		X:          message.X,
		Y:          message.Y,
		Z:          message.Z,
		Rotation:   message.Rotation,
	})
}

func (h *wsHub) relayDamage(client *wsClient, message wsIncoming) {
	if message.TargetID <= 0 || message.TargetID == client.id {
		return
	}
	if !finite(message.Amount) || message.Amount <= 0.0 || message.Amount > 100000.0 {
		return
	}
	h.broadcastExcept(client.id, wsOutgoing{
		Type:     "damage",
		ID:       client.id,
		SourceID: client.id,
		TargetID: message.TargetID,
		Amount:   message.Amount,
	})
}

func (h *wsHub) relayHeal(client *wsClient, message wsIncoming) {
	if message.TargetID <= 0 || message.TargetID == client.id {
		return
	}
	if !finite(message.Amount) || message.Amount <= 0.0 || message.Amount > 100000.0 {
		return
	}
	h.broadcastExcept(client.id, wsOutgoing{
		Type:     "heal",
		ID:       client.id,
		SourceID: client.id,
		TargetID: message.TargetID,
		Amount:   message.Amount,
	})
}

func (h *wsHub) relayStats(client *wsClient, message wsIncoming) {
	if !finite(message.MaxHP) || message.MaxHP <= 0.0 || message.MaxHP > 100000.0 {
		return
	}
	if !finite(message.HP) || message.HP < 0.0 {
		return
	}
	if !finite(message.AttackDamage) || message.AttackDamage < 0.0 || message.AttackDamage > 100000.0 {
		return
	}
	hp := math.Min(message.HP, message.MaxHP)
	h.mu.Lock()
	if _, exists := h.clients[client.id]; !exists {
		h.mu.Unlock()
		return
	}
	client.maxHP = message.MaxHP
	client.hp = hp
	client.attackDamage = message.AttackDamage
	h.mu.Unlock()
	h.broadcastExcept(client.id, wsOutgoing{
		Type:         "stats",
		ID:           client.id,
		MaxHP:        message.MaxHP,
		HP:           hp,
		AttackDamage: message.AttackDamage,
	})
}

func (h *wsHub) relayDeath(client *wsClient) {
	h.mu.Lock()
	if _, exists := h.clients[client.id]; !exists {
		h.mu.Unlock()
		return
	}
	client.alive = false
	h.mu.Unlock()
	h.broadcastExcept(client.id, wsOutgoing{Type: "death", ID: client.id})
}

func (h *wsHub) relayRespawn(client *wsClient, message wsIncoming) {
	if !finite(message.X) || !finite(message.Y) || !finite(message.Z) || !finite(message.Rotation) {
		return
	}
	h.mu.Lock()
	if _, exists := h.clients[client.id]; !exists {
		h.mu.Unlock()
		return
	}
	client.alive = true
	client.x = message.X
	client.y = message.Y
	client.z = message.Z
	client.rotation = message.Rotation
	client.hasState = true
	h.mu.Unlock()
	h.broadcastExcept(client.id, wsOutgoing{
		Type:     "respawn",
		ID:       client.id,
		X:        message.X,
		Y:        message.Y,
		Z:        message.Z,
		Rotation: message.Rotation,
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
		ID:           c.id,
		Name:         name,
		Class:        c.class,
		Team:         c.team,
		X:            c.x,
		Y:            c.y,
		Z:            c.z,
		Rotation:     c.rotation,
		HasState:     c.hasState,
		Alive:        c.alive,
		MaxHP:        c.maxHP,
		HP:           c.hp,
		AttackDamage: c.attackDamage,
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
		case "attack":
			c.hub.relayAttack(c, message)
		case "damage":
			c.hub.relayDamage(c, message)
		case "heal":
			c.hub.relayHeal(c, message)
		case "stats":
			c.hub.relayStats(c, message)
		case "death":
			c.hub.relayDeath(c)
		case "respawn":
			c.hub.relayRespawn(c, message)
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
