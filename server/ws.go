package main

import (
	"context"
	"database/sql"
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

	roomSlots        = 6
	roomBotFillDelay = 8 * time.Second
)

var classNames = []string{"warrior", "mage", "fairy"}
var classBaseHP = []float64{550.0, 500.0, 450.0}
var classBaseDamage = []float64{44.0, 26.0, 30.0}

var wsUpgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

type wsHub struct {
	mu           sync.Mutex
	clients      map[int64]*wsClient
	rooms        map[int64]*wsRoom
	nextClientID int64
	nextRoomID   int64
	db           *sql.DB
}

type wsRoom struct {
	id          int64
	players     [roomSlots]*wsClient
	bots        [roomSlots]bool
	humanCount  int
	hostID      int64
	state       string
	fillTimer   *time.Timer
	resultSaved bool
}

type wsClient struct {
	id        int64
	conn      *websocket.Conn
	hub       *wsHub
	send      chan []byte
	done      chan struct{}
	closeOnce sync.Once

	roomID       int64
	playerID     int64
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
	PlayerID     int64   `json:"player_id"`
	Name         string  `json:"name"`
	Class        int     `json:"class"`
	ClassName    string  `json:"class_name"`
	Team         int     `json:"team"`
	X            float64 `json:"x"`
	Y            float64 `json:"y"`
	Z            float64 `json:"z"`
	Rotation     float64 `json:"rotation"`
	TargetID     int64   `json:"target_id"`
	SourceID     int64   `json:"source_id"`
	AttackType   string  `json:"attack_type"`
	Skill        string  `json:"skill"`
	Amount       float64 `json:"amount"`
	MaxHP        float64 `json:"max_hp"`
	HP           float64 `json:"hp"`
	AttackDamage float64 `json:"attack_damage"`
	WinningTeam  int     `json:"winning_team"`
}

type matchResultPlayer struct {
	playerID int64
	team     int
}

type wsMatchPlayer struct {
	ID           int64   `json:"id"`
	Bot          bool    `json:"bot"`
	Name         string  `json:"name"`
	Class        int     `json:"class"`
	Team         int     `json:"team"`
	Slot         int     `json:"slot"`
	MaxHP        float64 `json:"max_hp"`
	HP           float64 `json:"hp"`
	AttackDamage float64 `json:"attack_damage"`
}

type wsOutgoing struct {
	Type         string          `json:"type"`
	ID           int64           `json:"id,omitempty"`
	RoomID       int64           `json:"room_id,omitempty"`
	HostID       int64           `json:"host_id,omitempty"`
	Name         string          `json:"name,omitempty"`
	Class        int             `json:"class"`
	Team         int             `json:"team"`
	Slot         int             `json:"slot,omitempty"`
	X            float64         `json:"x"`
	Y            float64         `json:"y"`
	Z            float64         `json:"z"`
	Rotation     float64         `json:"rotation"`
	TargetID     int64           `json:"target_id,omitempty"`
	SourceID     int64           `json:"source_id,omitempty"`
	AttackType   string          `json:"attack_type,omitempty"`
	Skill        string          `json:"skill,omitempty"`
	Amount       float64         `json:"amount,omitempty"`
	MaxHP        float64         `json:"max_hp,omitempty"`
	HP           float64         `json:"hp,omitempty"`
	AttackDamage float64         `json:"attack_damage,omitempty"`
	WinningTeam  int             `json:"winning_team,omitempty"`
	MatchPlayers []wsMatchPlayer `json:"match_players,omitempty"`
	Error        string          `json:"error,omitempty"`
}

func newWebSocketHub(db *sql.DB) *wsHub {
	return &wsHub{
		clients: make(map[int64]*wsClient),
		rooms:   make(map[int64]*wsRoom),
		db:      db,
	}
}

func (h *wsHub) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("websocket upgrade: %v", err)
		return
	}
	_ = conn.SetReadDeadline(time.Time{})
	_ = conn.SetWriteDeadline(time.Time{})

	client := &wsClient{
		conn:  conn,
		hub:   h,
		send:  make(chan []byte, wsSendBuffer),
		done:  make(chan struct{}),
		alive: true,
	}
	h.mu.Lock()
	h.nextClientID++
	client.id = h.nextClientID
	h.clients[client.id] = client
	h.mu.Unlock()

	client.sendJSON(wsOutgoing{Type: "welcome", ID: client.id})
	log.Printf("ws client %d connected", client.id)

	go client.writePump()
	client.readPump()
}

func (h *wsHub) removeClient(client *wsClient) {
	var roomID int64
	var hostChanged *wsOutgoing
	h.mu.Lock()
	delete(h.clients, client.id)
	room := h.rooms[client.roomID]
	if room != nil {
		slot := roomSlotOf(room, client)
		if slot >= 0 {
			room.players[slot] = nil
			room.humanCount--
		}
		if room.hostID == client.id {
			room.hostID = 0
			for index := 0; index < roomSlots; index++ {
				if other := room.players[index]; other != nil {
					room.hostID = other.id
					break
				}
			}
			if room.hostID != 0 {
				hostChanged = &wsOutgoing{Type: "host_changed", RoomID: room.id, ID: room.hostID, HostID: room.hostID}
			}
		}
		if room.humanCount <= 0 {
			if room.fillTimer != nil {
				room.fillTimer.Stop()
			}
			delete(h.rooms, room.id)
		} else {
			roomID = room.id
		}
	}
	h.mu.Unlock()

	client.close()
	if roomID != 0 {
		h.broadcastRoom(roomID, client.id, wsOutgoing{Type: "player_left", ID: client.id})
	}
	if hostChanged != nil && roomID != 0 {
		h.broadcastRoom(roomID, 0, *hostChanged)
	}
}

func (h *wsHub) joinMatchmaking(client *wsClient, message wsIncoming) {
	class := resolveClass(message)
	if class < 0 {
		return
	}
	name := strings.TrimSpace(message.Name)
	if name == "" {
		name = fmt.Sprintf("Игрок %d", client.id)
	}
	runes := []rune(name)
	if len(runes) > 32 {
		name = string(runes[:32])
	}

	h.mu.Lock()
	if client.roomID != 0 {
		h.mu.Unlock()
		return
	}
	room, slot := h.findRoomLocked(class)
	if room == nil {
		h.nextRoomID++
		room = &wsRoom{id: h.nextRoomID, state: "waiting"}
		h.rooms[room.id] = room
		slot = class
	}
	client.roomID = room.id
	client.playerID = message.PlayerID
	client.name = name
	client.class = class
	client.team = slot / 3
	client.joined = true
	room.players[slot] = client
	room.humanCount++
	if room.hostID == 0 {
		room.hostID = client.id
	}
	if room.fillTimer == nil && room.humanCount < roomSlots {
		roomID := room.id
		room.fillTimer = time.AfterFunc(roomBotFillDelay, func() { h.startRoom(roomID) })
	}

	var startMessage wsOutgoing
	var startClients []*wsClient
	if room.humanCount >= roomSlots {
		startMessage, startClients = h.startRoomLocked(room)
	}
	roomID := room.id
	hostID := room.hostID
	team := client.team
	h.mu.Unlock()

	if len(startClients) > 0 {
		h.sendToClients(startClients, startMessage)
		return
	}
	client.sendJSON(wsOutgoing{
		Type:   "room_joined",
		ID:     client.id,
		RoomID: roomID,
		HostID: hostID,
		Class:  class,
		Team:   team,
		Slot:   slot,
	})
}

func (h *wsHub) findRoomLocked(class int) (*wsRoom, int) {
	var best *wsRoom
	for _, room := range h.rooms {
		if room.state != "waiting" || room.humanCount >= roomSlots {
			continue
		}
		hasSlot := false
		for _, slot := range []int{class, class + 3} {
			if room.players[slot] == nil && !room.bots[slot] {
				hasSlot = true
				break
			}
		}
		if !hasSlot {
			continue
		}
		if best == nil || room.humanCount > best.humanCount || (room.humanCount == best.humanCount && room.id < best.id) {
			best = room
		}
	}
	if best == nil {
		return nil, -1
	}
	slotA := class
	slotB := class + 3
	if best.players[slotA] == nil && !best.bots[slotA] && best.players[slotB] == nil && !best.bots[slotB] {
		if teamHumanCount(best, 0) <= teamHumanCount(best, 1) {
			return best, slotA
		}
		return best, slotB
	}
	if best.players[slotA] == nil && !best.bots[slotA] {
		return best, slotA
	}
	return best, slotB
}

func (h *wsHub) startRoom(roomID int64) {
	h.mu.Lock()
	room := h.rooms[roomID]
	if room == nil || room.state != "waiting" || room.humanCount == 0 {
		h.mu.Unlock()
		return
	}
	message, clients := h.startRoomLocked(room)
	h.mu.Unlock()
	h.sendToClients(clients, message)
}

func (h *wsHub) startRoomLocked(room *wsRoom) (wsOutgoing, []*wsClient) {
	if room.fillTimer != nil {
		room.fillTimer.Stop()
		room.fillTimer = nil
	}
	room.state = "live"
	if room.hostID == 0 {
		for index := 0; index < roomSlots; index++ {
			if player := room.players[index]; player != nil {
				room.hostID = player.id
				break
			}
		}
	}
	players := make([]wsMatchPlayer, 0, roomSlots)
	clients := make([]*wsClient, 0, room.humanCount)
	for slot := 0; slot < roomSlots; slot++ {
		class := slot % 3
		team := slot / 3
		if player := room.players[slot]; player != nil {
			player.class = class
			player.team = team
			player.alive = true
			if player.maxHP <= 0 {
				player.maxHP = classBaseHP[class]
			}
			if player.hp <= 0 || player.hp > player.maxHP {
				player.hp = player.maxHP
			}
			if player.attackDamage <= 0 {
				player.attackDamage = classBaseDamage[class]
			}
			players = append(players, wsMatchPlayer{
				ID:           player.id,
				Bot:          false,
				Name:         player.name,
				Class:        class,
				Team:         team,
				Slot:         slot,
				MaxHP:        player.maxHP,
				HP:           player.hp,
				AttackDamage: player.attackDamage,
			})
			clients = append(clients, player)
			continue
		}
		room.bots[slot] = true
		players = append(players, wsMatchPlayer{
			ID:           -int64(slot + 1),
			Bot:          true,
			Name:         fmt.Sprintf("Бот-%s-%d", classNames[class], slot+1),
			Class:        class,
			Team:         team,
			Slot:         slot,
			MaxHP:        classBaseHP[class],
			HP:           classBaseHP[class],
			AttackDamage: classBaseDamage[class],
		})
	}
	return wsOutgoing{
		Type:         "match_start",
		RoomID:       room.id,
		HostID:       room.hostID,
		MatchPlayers: players,
	}, clients
}

func (h *wsHub) updateState(client *wsClient, message wsIncoming) {
	if !finite(message.X) || !finite(message.Y) || !finite(message.Z) || !finite(message.Rotation) {
		return
	}
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || client.roomID == 0 {
		h.mu.Unlock()
		return
	}
	client.x = message.X
	client.y = message.Y
	client.z = message.Z
	client.rotation = message.Rotation
	client.hasState = true
	targets := roomClientsLocked(room, client.id)
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
		Type:     "state",
		ID:       client.id,
		X:        client.x,
		Y:        client.y,
		Z:        client.z,
		Rotation: client.rotation,
	})
}

func (h *wsHub) relayAttack(client *wsClient, message wsIncoming) {
	attackType := strings.TrimSpace(message.AttackType)
	if attackType == "" {
		attackType = "auto"
	}
	if len([]rune(attackType)) > 32 {
		attackType = string([]rune(attackType)[:32])
	}
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" {
		h.mu.Unlock()
		return
	}
	targets := roomClientsLocked(room, client.id)
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
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

func (h *wsHub) relayStats(client *wsClient, message wsIncoming) {
	if !finite(message.MaxHP) || message.MaxHP <= 0 || message.MaxHP > 100000 {
		return
	}
	if !finite(message.HP) || message.HP < 0 || !finite(message.AttackDamage) || message.AttackDamage < 0 || message.AttackDamage > 100000 {
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
	room := h.rooms[client.roomID]
	var targets []*wsClient
	if room != nil {
		targets = roomClientsLocked(room, client.id)
	}
	h.mu.Unlock()
	if room == nil {
		return
	}
	h.sendToClients(targets, wsOutgoing{
		Type:         "stats",
		ID:           client.id,
		MaxHP:        message.MaxHP,
		HP:           hp,
		AttackDamage: message.AttackDamage,
	})
}

func (h *wsHub) relayHeal(client *wsClient, message wsIncoming) {
	if message.TargetID <= 0 || message.TargetID == client.id || !finite(message.Amount) || message.Amount <= 0 || message.Amount > 100000 {
		return
	}
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" {
		h.mu.Unlock()
		return
	}
	target := findRoomPlayerLocked(room, message.TargetID)
	if target == nil || !target.alive || target.team != client.team {
		h.mu.Unlock()
		return
	}
	if target.maxHP > 0 {
		target.hp = math.Min(target.maxHP, target.hp+message.Amount)
	}
	targets := roomClientsLocked(room, client.id)
	roomID := room.id
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
		Type:     "heal",
		ID:       client.id,
		RoomID:   roomID,
		SourceID: client.id,
		TargetID: target.id,
		Amount:   message.Amount,
	})
}

func (h *wsHub) relayDeath(client *wsClient) {
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || !client.alive {
		h.mu.Unlock()
		return
	}
	client.alive = false
	client.hp = 0
	targets := roomClientsLocked(room, client.id)
	roomID := room.id
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{Type: "death", ID: client.id, RoomID: roomID})
}

func (h *wsHub) relayRespawn(client *wsClient, message wsIncoming) {
	if !finite(message.X) || !finite(message.Y) || !finite(message.Z) || !finite(message.Rotation) {
		return
	}
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" {
		h.mu.Unlock()
		return
	}
	client.alive = true
	client.hp = client.maxHP
	client.x = message.X
	client.y = message.Y
	client.z = message.Z
	client.rotation = message.Rotation
	client.hasState = true
	targets := roomClientsLocked(room, client.id)
	roomID := room.id
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
		Type:     "respawn",
		ID:       client.id,
		RoomID:   roomID,
		X:        message.X,
		Y:        message.Y,
		Z:        message.Z,
		Rotation: message.Rotation,
	})
}

func (h *wsHub) handleAttackIntent(client *wsClient, message wsIncoming) {
	skill := strings.TrimSpace(message.Skill)
	if skill == "" {
		skill = "auto"
	}
	if len([]rune(skill)) > 32 {
		skill = string([]rune(skill)[:32])
	}
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || !client.alive {
		h.mu.Unlock()
		return
	}
	target := findRoomPlayerLocked(room, message.TargetID)
	if target == nil || target.id == client.id || !target.alive || target.team == client.team {
		h.mu.Unlock()
		return
	}
	damage := calculateDamage(client, skill)
	target.hp = math.Max(0, target.hp-damage)
	died := target.hp <= 0
	if died {
		target.alive = false
	}
	sourceID := client.id
	targetID := target.id
	roomID := room.id
	h.mu.Unlock()

	h.broadcastRoom(roomID, 0, wsOutgoing{
		Type:     "damage",
		ID:       sourceID,
		RoomID:   roomID,
		SourceID: sourceID,
		TargetID: targetID,
		Skill:    skill,
		Amount:   damage,
	})
	if died {
		h.broadcastRoom(roomID, 0, wsOutgoing{Type: "death", ID: targetID, RoomID: roomID})
	}
}

func (h *wsHub) handleMatchResult(client *wsClient, message wsIncoming) {
	if message.WinningTeam < 0 || message.WinningTeam > 1 {
		return
	}
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || room.resultSaved {
		h.mu.Unlock()
		return
	}
	room.resultSaved = true
	room.state = "finished"
	roomID := room.id
	players := make([]matchResultPlayer, 0, room.humanCount)
	for index := 0; index < roomSlots; index++ {
		player := room.players[index]
		if player == nil {
			continue
		}
		playerID := player.playerID
		if playerID <= 0 {
			playerID = player.id
		}
		players = append(players, matchResultPlayer{playerID: playerID, team: player.team})
	}
	h.mu.Unlock()

	h.saveMatch(roomID, players, message.WinningTeam)
	h.broadcastRoom(roomID, 0, wsOutgoing{
		Type:        "match_finished",
		RoomID:      roomID,
		WinningTeam: message.WinningTeam,
	})
}

func (h *wsHub) saveMatch(roomID int64, players []matchResultPlayer, winningTeam int) {
	if h.db == nil || len(players) == 0 {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	transaction, err := h.db.BeginTx(ctx, nil)
	if err != nil {
		log.Printf("begin match result: %v", err)
		return
	}
	defer transaction.Rollback()
	for _, player := range players {
		_, err := transaction.ExecContext(ctx,
			`INSERT INTO matches (room_id, player_id, team, won) VALUES ($1, $2, $3, $4)`,
			roomID,
			player.playerID,
			player.team,
			player.team == winningTeam,
		)
		if err != nil {
			log.Printf("save match result: %v", err)
			return
		}
	}
	if err := transaction.Commit(); err != nil {
		log.Printf("commit match result: %v", err)
	}
}

func (h *wsHub) broadcastRoom(roomID int64, exceptID int64, message wsOutgoing) {
	h.mu.Lock()
	room := h.rooms[roomID]
	var targets []*wsClient
	if room != nil {
		targets = roomClientsLocked(room, exceptID)
	}
	h.mu.Unlock()
	h.sendToClients(targets, message)
}

func (h *wsHub) sendToClients(clients []*wsClient, message wsOutgoing) {
	if len(clients) == 0 {
		return
	}
	data, err := json.Marshal(message)
	if err != nil {
		log.Printf("websocket marshal: %v", err)
		return
	}
	for _, client := range clients {
		client.trySend(data)
	}
}

func roomClientsLocked(room *wsRoom, exceptID int64) []*wsClient {
	clients := make([]*wsClient, 0, room.humanCount)
	for index := 0; index < roomSlots; index++ {
		client := room.players[index]
		if client != nil && client.id != exceptID {
			clients = append(clients, client)
		}
	}
	return clients
}

func findRoomPlayerLocked(room *wsRoom, playerID int64) *wsClient {
	for index := 0; index < roomSlots; index++ {
		client := room.players[index]
		if client != nil && client.id == playerID {
			return client
		}
	}
	return nil
}

func roomSlotOf(room *wsRoom, client *wsClient) int {
	for index := 0; index < roomSlots; index++ {
		if room.players[index] == client {
			return index
		}
	}
	return -1
}

func teamHumanCount(room *wsRoom, team int) int {
	count := 0
	for index := team * 3; index < team*3+3; index++ {
		if room.players[index] != nil {
			count++
		}
	}
	return count
}

func resolveClass(message wsIncoming) int {
	switch strings.ToLower(strings.TrimSpace(message.ClassName)) {
	case "warrior":
		return 0
	case "mage":
		return 1
	case "fairy":
		return 2
	}
	if message.Class >= 0 && message.Class <= 2 {
		return message.Class
	}
	return -1
}

func calculateDamage(client *wsClient, skill string) float64 {
	base := client.attackDamage
	if base <= 0 {
		class := client.class
		if class < 0 || class >= len(classBaseDamage) {
			class = 0
		}
		base = classBaseDamage[class]
	}
	multiplier := 1.0
	switch strings.ToLower(skill) {
	case "shadow_assassin":
		multiplier = 1.4
	case "fear_ult":
		multiplier = 1.3
	case "crit_shot":
		multiplier = 2.5
	case "stun_shot", "stun":
		multiplier = 0.9
	case "root":
		multiplier = 0.8
	case "ult_lightning_storm":
		multiplier = 0.4
	}
	damage := math.Round(base*multiplier*100) / 100
	if damage < 1 {
		return 1
	}
	if damage > 100000 {
		return 100000
	}
	return damage
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
			c.hub.joinMatchmaking(c, message)
		case "state":
			c.hub.updateState(c, message)
		case "attack":
			c.hub.relayAttack(c, message)
		case "attack_intent":
			c.hub.handleAttackIntent(c, message)
		case "stats":
			c.hub.relayStats(c, message)
		case "heal":
			c.hub.relayHeal(c, message)
		case "death":
			c.hub.relayDeath(c)
		case "respawn":
			c.hub.relayRespawn(c, message)
		case "match_result":
			c.hub.handleMatchResult(c, message)
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
