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
	wsMaxMessageSize = 16384
	wsSendBuffer     = 64

	roomSlots        = 6
	// Временное значение для тестов: боты заполняют комнату через 15 секунд.
	// Перед релизом вернуть 30 * time.Second.
	roomBotFillDelay = 15 * time.Second

	matchLength      = 10 * time.Minute
	crystalsToWin    = 3
	deliveryLockout  = 500 * time.Millisecond
	botStateBotLimit = roomSlots
)

var classNames = []string{"warrior", "mage", "fairy"}
var classBaseHP = []float64{1050.0, 1000.0, 950.0}
var classBaseDamage = []float64{44.0, 26.0, 60.0}
var classAttackRange = []float64{3.5, 9.0, 11.0}

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
	id           int64
	players      [roomSlots]*wsClient
	bots         [roomSlots]*wsBot
	humanCount   int
	hostID       int64
	state        string
	fillTimer    *time.Timer
	finishTimer  *time.Timer
	resultSaved  bool
	score        [2]int
	suddenDeath  bool
	lastDelivery [2]time.Time
}

type wsBot struct {
	id           int64
	name         string
	class        int
	team         int
	x            float64
	y            float64
	z            float64
	rotation     float64
	maxHP        float64
	hp           float64
	attackDamage float64
	alive        bool
	animation    string
	hasState     bool
	lastDamaged  time.Time
	deadSince    time.Time
	lastAttacks  map[string]time.Time
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
	lastAttacks  map[string]time.Time
}

type wsIncoming struct {
	Type         string          `json:"type"`
	PlayerID     int64           `json:"player_id"`
	Name         string          `json:"name"`
	Class        int             `json:"class"`
	ClassName    string          `json:"class_name"`
	Team         int             `json:"team"`
	X            float64         `json:"x"`
	Y            float64         `json:"y"`
	Z            float64         `json:"z"`
	Rotation     float64         `json:"rotation"`
	TargetID     int64           `json:"target_id"`
	SourceID     int64           `json:"source_id"`
	AttackType   string          `json:"attack_type"`
	Skill        string          `json:"skill"`
	Amount       float64         `json:"amount"`
	MaxHP        float64         `json:"max_hp"`
	HP           float64         `json:"hp"`
	AttackDamage float64         `json:"attack_damage"`
	WinningTeam  int             `json:"winning_team"`
	Event        string          `json:"event"`
	Bots         []wsBotSnapshot `json:"bots"`
}

type wsBotSnapshot struct {
	ID           int64   `json:"id"`
	Name         string  `json:"name,omitempty"`
	Class        int     `json:"class"`
	Team         int     `json:"team"`
	X            float64 `json:"x"`
	Y            float64 `json:"y"`
	Z            float64 `json:"z"`
	Rotation     float64 `json:"rotation"`
	MaxHP        float64 `json:"max_hp,omitempty"`
	HP           float64 `json:"hp,omitempty"`
	AttackDamage float64 `json:"attack_damage,omitempty"`
	Alive        bool    `json:"alive"`
	Animation    string  `json:"animation,omitempty"`
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
	Bots         []wsBotSnapshot `json:"bots,omitempty"`
	Score0       int             `json:"score_0,omitempty"`
	Score1       int             `json:"score_1,omitempty"`
	SuddenDeath  bool            `json:"sudden_death,omitempty"`
	Event        string          `json:"event,omitempty"`
	Reason       string          `json:"reason,omitempty"`
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
		conn:        conn,
		hub:         h,
		send:        make(chan []byte, wsSendBuffer),
		done:        make(chan struct{}),
		alive:       true,
		lastAttacks: make(map[string]time.Time),
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
			if room.finishTimer != nil {
				room.finishTimer.Stop()
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
		slot = 0
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

func (h *wsHub) findRoomLocked(_ int) (*wsRoom, int) {
	var best *wsRoom
	for _, room := range h.rooms {
		if room.state != "waiting" || room.humanCount >= roomSlots {
			continue
		}
		if !hasFreeSlot(room) {
			continue
		}
		if best == nil || room.humanCount > best.humanCount || (room.humanCount == best.humanCount && room.id < best.id) {
			best = room
		}
	}
	if best == nil {
		return nil, -1
	}
	for index := 0; index < roomSlots; index++ {
		if best.players[index] == nil && best.bots[index] == nil {
			return best, index
		}
	}
	return best, -1
}

func hasFreeSlot(room *wsRoom) bool {
	for index := 0; index < roomSlots; index++ {
		if room.players[index] == nil && room.bots[index] == nil {
			return true
		}
	}
	return false
}

func clampClass(value int) int {
	if value < 0 {
		return 0
	}
	if value > 2 {
		return 2
	}
	return value
}

func balanceHumansLocked(room *wsRoom) {
	humans := make([]*wsClient, 0, roomSlots)
	for index := 0; index < roomSlots; index++ {
		if player := room.players[index]; player != nil {
			humans = append(humans, player)
		}
	}
	if len(humans) == 0 {
		return
	}
	byClass := [3][]*wsClient{}
	for _, player := range humans {
		class := clampClass(player.class)
		player.class = class
		byClass[class] = append(byClass[class], player)
	}
	teams := make(map[*wsClient]int, len(humans))
	teamCounts := [2]int{}
	classCounts := [2][3]int{}
	for class := 0; class < 3; class++ {
		for _, player := range byClass[class] {
			team := 0
			if classCounts[0][class] > classCounts[1][class] {
				team = 1
			} else if classCounts[0][class] == classCounts[1][class] && teamCounts[0] > teamCounts[1] {
				team = 1
			}
			teams[player] = team
			teamCounts[team]++
			classCounts[team][class]++
		}
	}
	for index := 0; index < roomSlots; index++ {
		room.players[index] = nil
	}
	for _, player := range humans {
		team := teams[player]
		placed := false
		for slot := team * 3; slot < team*3+3; slot++ {
			if room.players[slot] == nil {
				room.players[slot] = player
				placed = true
				break
			}
		}
		if !placed {
			for slot := 0; slot < roomSlots; slot++ {
				if room.players[slot] == nil {
					room.players[slot] = player
					break
				}
			}
		}
	}
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
	room.score = [2]int{}
	room.suddenDeath = false
	room.resultSaved = false
	room.lastDelivery = [2]time.Time{}
	if room.hostID == 0 {
		for index := 0; index < roomSlots; index++ {
			if player := room.players[index]; player != nil {
				room.hostID = player.id
				break
			}
		}
	}
	balanceHumansLocked(room)
	players := make([]wsMatchPlayer, 0, roomSlots)
	clients := make([]*wsClient, 0, room.humanCount)
	for slot := 0; slot < roomSlots; slot++ {
		class := slot % 3
		team := slot / 3
		if player := room.players[slot]; player != nil {
			class = clampClass(player.class)
			team = slot / 3
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
			if !player.hasState {
				player.x = float64((slot%3)-1) * 2.0
				player.y = 0.76
				player.z = 27.5
				player.rotation = 0.0
				if team == 1 {
					player.z = -27.5
					player.rotation = math.Pi
				}
				player.hasState = true
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
		botID := -int64(slot + 1)
		botName := fmt.Sprintf("Игрок %04d", 1000+int((room.id*37+int64(slot)*211)%9000))
		botZ := 27.5
		botRotation := 0.0
		if team == 1 {
			botZ = -27.5
			botRotation = math.Pi
		}
		room.bots[slot] = &wsBot{
			id:           botID,
			name:         botName,
			class:        class,
			team:         team,
			x:            float64((slot%3)-1) * 2.0,
			y:            0.76,
			z:            botZ,
			rotation:     botRotation,
			maxHP:        classBaseHP[class],
			hp:           classBaseHP[class],
			attackDamage: classBaseDamage[class],
			alive:        true,
			hasState:     true,
			lastAttacks:  make(map[string]time.Time),
		}
		players = append(players, wsMatchPlayer{
			ID:           botID,
			Bot:          true,
			Name:         botName,
			Class:        class,
			Team:         team,
			Slot:         slot,
			MaxHP:        classBaseHP[class],
			HP:           classBaseHP[class],
			AttackDamage: classBaseDamage[class],
		})
	}
	if room.finishTimer != nil {
		room.finishTimer.Stop()
	}
	roomID := room.id
	room.finishTimer = time.AfterFunc(matchLength, func() { h.finishMatchByTimeout(roomID) })
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

type wsCombatant struct {
	id           int64
	class        int
	team         int
	alive        bool
	hp           float64
	maxHP        float64
	attackDamage float64
	x            float64
	y            float64
	z            float64
	rotation     float64
	hasState     bool
	lastAttacks  map[string]time.Time
	client       *wsClient
	bot          *wsBot
}

func (h *wsHub) relayBotStates(client *wsClient, message wsIncoming) {
	if len(message.Bots) == 0 || len(message.Bots) > botStateBotLimit {
		return
	}
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || room.hostID != client.id {
		h.mu.Unlock()
		return
	}
	changed := false
	now := time.Now()
	for _, state := range message.Bots {
		bot := findRoomBotLocked(room, state.ID)
		if bot == nil {
			continue
		}
		if !finite(state.X) || !finite(state.Y) || !finite(state.Z) || !finite(state.Rotation) || !finite(state.HP) || !finite(state.MaxHP) {
			continue
		}
		if math.Abs(state.X) > 1000 || math.Abs(state.Z) > 1000 {
			continue
		}
		if state.MaxHP > 0 && state.MaxHP <= 100000 {
			bot.maxHP = state.MaxHP
		}
		bot.x = state.X
		bot.y = state.Y
		bot.z = state.Z
		bot.rotation = state.Rotation
		bot.animation = truncateText(state.Animation, 24)
		if state.AttackDamage >= 0 && state.AttackDamage <= 100000 {
			bot.attackDamage = state.AttackDamage
		}
		hp := math.Max(0, math.Min(state.HP, bot.maxHP))
		switch {
		case !state.Alive:
			bot.hp = 0
			bot.alive = false
			if bot.deadSince.IsZero() {
				bot.deadSince = now
			}
		case !bot.alive && hp > 0:
			// A host packet sent before it applied a server kill must not
			// resurrect the bot. Real respawns wait for the respawn timer.
			if !bot.deadSince.IsZero() && now.Sub(bot.deadSince) >= 1500*time.Millisecond {
				bot.hp = hp
				bot.alive = true
				bot.deadSince = time.Time{}
			}
		case hp < bot.hp:
			bot.hp = hp
			if hp <= 0 {
				bot.alive = false
				if bot.deadSince.IsZero() {
					bot.deadSince = now
				}
			}
		case hp > bot.hp && now.Sub(bot.lastDamaged) >= 500*time.Millisecond:
			bot.hp = hp
		}
		changed = true
	}
	if !changed {
		h.mu.Unlock()
		return
	}
	roomID := room.id
	snapshots := botSnapshotsLocked(room)
	targets := roomClientsLocked(room, client.id)
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
		Type:   "bot_states",
		RoomID: roomID,
		Bots:   snapshots,
	})
}

func (h *wsHub) handleAttackIntent(client *wsClient, message wsIncoming) {
	skill := normalizeSkill(message.Skill)
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" {
		h.mu.Unlock()
		return
	}
	var source *wsCombatant
	switch {
	case message.SourceID == 0 || message.SourceID == client.id:
		source = combatantFromClient(client)
	case message.SourceID < 0 && room.hostID == client.id:
		if bot := findRoomBotLocked(room, message.SourceID); bot != nil {
			source = combatantFromBot(bot)
		}
	}
	if source == nil || !source.alive {
		h.mu.Unlock()
		denyAttack(client, message.TargetID, skill, "invalid_source")
		return
	}
	target := findCombatantLocked(room, message.TargetID)
	if target == nil || target.id == source.id || target.team == source.team || !target.alive {
		h.mu.Unlock()
		denyAttack(client, message.TargetID, skill, "invalid_target")
		return
	}
	if !inAttackRange(source, target, skill) {
		h.mu.Unlock()
		denyAttack(client, message.TargetID, skill, "out_of_range")
		return
	}
	if !source.cooldownReady(skill) {
		h.mu.Unlock()
		denyAttack(client, message.TargetID, skill, "cooldown")
		return
	}
	damage := calculateDamageFor(source.attackDamage, source.class, skill)
	died := target.applyDamage(damage)
	sourceID := source.id
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

func (h *wsHub) handleMatchEvent(client *wsClient, message wsIncoming) {
	event := strings.ToLower(strings.TrimSpace(message.Event))
	if event == "" || len([]rune(event)) > 32 {
		return
	}
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || room.resultSaved {
		h.mu.Unlock()
		return
	}
	roomID := room.id
	switch event {
	case "shard_delivered":
		team := message.Team
		if team < 0 || team > 1 {
			h.mu.Unlock()
			return
		}
		if client.id != room.hostID && team != client.team {
			h.mu.Unlock()
			return
		}
		if !room.lastDelivery[team].IsZero() && time.Since(room.lastDelivery[team]) < deliveryLockout {
			score0, score1, sudden := room.score[0], room.score[1], room.suddenDeath
			h.mu.Unlock()
			client.sendJSON(wsOutgoing{Type: "match_score", Score0: score0, Score1: score1, SuddenDeath: sudden})
			return
		}
		room.lastDelivery[team] = time.Now()
		room.score[team]++
		score0, score1, sudden := room.score[0], room.score[1], room.suddenDeath
		winner := -1
		if sudden || room.score[team] >= crystalsToWin {
			winner = team
		}
		var players []matchResultPlayer
		if winner >= 0 {
			players = h.finishMatchLocked(room)
		}
		h.mu.Unlock()

		h.broadcastRoom(roomID, 0, wsOutgoing{
			Type:        "match_score",
			RoomID:      roomID,
			Score0:      score0,
			Score1:      score1,
			SuddenDeath: sudden,
		})
		if winner >= 0 {
			h.saveMatch(roomID, players, winner)
			h.broadcastRoom(roomID, 0, wsOutgoing{
				Type:        "match_finished",
				RoomID:      roomID,
				WinningTeam: winner,
				Score0:      score0,
				Score1:      score1,
			})
		}
	case "shell_destroyed":
		team := message.Team
		if team < 0 || team > 1 || (client.id != room.hostID && team != client.team) {
			h.mu.Unlock()
			return
		}
		h.mu.Unlock()
		h.broadcastRoom(roomID, 0, wsOutgoing{
			Type:   "match_event",
			RoomID: roomID,
			Event:  "shell_destroyed",
			Team:   team,
		})
	default:
		h.mu.Unlock()
	}
}

func (h *wsHub) finishMatchByTimeout(roomID int64) {
	h.mu.Lock()
	room := h.rooms[roomID]
	if room == nil || room.state != "live" || room.resultSaved {
		h.mu.Unlock()
		return
	}
	score0, score1 := room.score[0], room.score[1]
	if score0 == score1 {
		room.suddenDeath = true
		h.mu.Unlock()
		h.broadcastRoom(roomID, 0, wsOutgoing{
			Type:        "match_score",
			RoomID:      roomID,
			Score0:      score0,
			Score1:      score1,
			SuddenDeath: true,
		})
		h.broadcastRoom(roomID, 0, wsOutgoing{
			Type:   "match_event",
			RoomID: roomID,
			Event:  "sudden_death",
		})
		return
	}
	winner := 0
	if score1 > score0 {
		winner = 1
	}
	players := h.finishMatchLocked(room)
	h.mu.Unlock()

	h.saveMatch(roomID, players, winner)
	h.broadcastRoom(roomID, 0, wsOutgoing{
		Type:        "match_score",
		RoomID:      roomID,
		Score0:      score0,
		Score1:      score1,
		SuddenDeath: false,
	})
	h.broadcastRoom(roomID, 0, wsOutgoing{
		Type:        "match_finished",
		RoomID:      roomID,
		WinningTeam: winner,
		Score0:      score0,
		Score1:      score1,
	})
}

func (h *wsHub) finishMatchLocked(room *wsRoom) []matchResultPlayer {
	room.resultSaved = true
	room.state = "finished"
	if room.finishTimer != nil {
		room.finishTimer.Stop()
		room.finishTimer = nil
	}
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
	return players
}

func denyAttack(client *wsClient, targetID int64, skill string, reason string) {
	client.sendJSON(wsOutgoing{
		Type:     "attack_denied",
		ID:       client.id,
		TargetID: targetID,
		Skill:    skill,
		Reason:   reason,
	})
}

func combatantFromClient(client *wsClient) *wsCombatant {
	return &wsCombatant{
		id:           client.id,
		class:        client.class,
		team:         client.team,
		alive:        client.alive,
		hp:           client.hp,
		maxHP:        client.maxHP,
		attackDamage: client.attackDamage,
		x:            client.x,
		y:            client.y,
		z:            client.z,
		rotation:     client.rotation,
		hasState:     client.hasState,
		lastAttacks:  client.lastAttacks,
		client:       client,
	}
}

func combatantFromBot(bot *wsBot) *wsCombatant {
	return &wsCombatant{
		id:           bot.id,
		class:        bot.class,
		team:         bot.team,
		alive:        bot.alive,
		hp:           bot.hp,
		maxHP:        bot.maxHP,
		attackDamage: bot.attackDamage,
		x:            bot.x,
		y:            bot.y,
		z:            bot.z,
		rotation:     bot.rotation,
		hasState:     bot.hasState,
		lastAttacks:  bot.lastAttacks,
		bot:          bot,
	}
}

func findCombatantLocked(room *wsRoom, id int64) *wsCombatant {
	if client := findRoomPlayerLocked(room, id); client != nil {
		return combatantFromClient(client)
	}
	if bot := findRoomBotLocked(room, id); bot != nil {
		return combatantFromBot(bot)
	}
	return nil
}

func findRoomBotLocked(room *wsRoom, id int64) *wsBot {
	for index := 0; index < roomSlots; index++ {
		bot := room.bots[index]
		if bot != nil && bot.id == id {
			return bot
		}
	}
	return nil
}

func botSnapshotsLocked(room *wsRoom) []wsBotSnapshot {
	snapshots := make([]wsBotSnapshot, 0, roomSlots)
	for index := 0; index < roomSlots; index++ {
		bot := room.bots[index]
		if bot == nil {
			continue
		}
		snapshots = append(snapshots, wsBotSnapshot{
			ID:           bot.id,
			Name:         bot.name,
			Class:        bot.class,
			Team:         bot.team,
			X:            bot.x,
			Y:            bot.y,
			Z:            bot.z,
			Rotation:     bot.rotation,
			MaxHP:        bot.maxHP,
			HP:           bot.hp,
			AttackDamage: bot.attackDamage,
			Alive:        bot.alive,
			Animation:    bot.animation,
		})
	}
	return snapshots
}

func (combatant *wsCombatant) applyDamage(amount float64) bool {
	combatant.hp = math.Max(0, combatant.hp-amount)
	if combatant.hp <= 0 {
		combatant.alive = false
	}
	if combatant.client != nil {
		combatant.client.hp = combatant.hp
		combatant.client.alive = combatant.alive
	}
	if combatant.bot != nil {
		combatant.bot.hp = combatant.hp
		combatant.bot.alive = combatant.alive
		combatant.bot.lastDamaged = time.Now()
		if !combatant.bot.alive && combatant.bot.deadSince.IsZero() {
			combatant.bot.deadSince = time.Now()
		}
	}
	return !combatant.alive
}

func (combatant *wsCombatant) cooldownReady(skill string) bool {
	if combatant.lastAttacks == nil {
		combatant.lastAttacks = make(map[string]time.Time)
		if combatant.client != nil {
			combatant.client.lastAttacks = combatant.lastAttacks
		}
		if combatant.bot != nil {
			combatant.bot.lastAttacks = combatant.lastAttacks
		}
	}
	now := time.Now()
	if last, ok := combatant.lastAttacks[skill]; ok && now.Sub(last) < attackCooldownFor(combatant.class, skill) {
		return false
	}
	combatant.lastAttacks[skill] = now
	return true
}

func normalizeSkill(skill string) string {
	skill = strings.TrimSpace(skill)
	if skill == "" {
		return "auto"
	}
	return truncateText(skill, 32)
}

func truncateText(value string, limit int) string {
	runes := []rune(value)
	if len(runes) <= limit {
		return value
	}
	return string(runes[:limit])
}

func attackCooldownFor(class int, skill string) time.Duration {
	switch strings.ToLower(skill) {
	case "auto":
		return 250 * time.Millisecond
	case "shadow_assassin":
		return 5 * time.Second
	case "fear_ult":
		return 15 * time.Second
	case "root":
		return 5500 * time.Millisecond
	case "stun", "stun_shot":
		return 7 * time.Second
	case "ult_lightning_storm":
		return 700 * time.Millisecond
	default:
		return 500 * time.Millisecond
	}
}

func inAttackRange(source *wsCombatant, target *wsCombatant, skill string) bool {
	if !source.hasState || !target.hasState {
		return false
	}
	distance := math.Hypot(source.x-target.x, source.z-target.z)
	return distance <= maxAttackRange(source.class, skill)
}

func maxAttackRange(class int, skill string) float64 {
	base := 6.0
	if class >= 0 && class < len(classAttackRange) {
		base = classAttackRange[class]
	}
	switch strings.ToLower(skill) {
	case "shadow_assassin":
		return 12.0
	case "fear_ult":
		return 10.0
	case "root":
		return 14.0
	case "stun", "stun_shot":
		return 18.0
	case "ult_lightning_storm":
		return 13.0
	default:
		return base + 3.0
	}
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

func calculateDamageFor(attackDamage float64, class int, skill string) float64 {
	base := attackDamage
	if base <= 0 {
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
		case "bot_states":
			c.hub.relayBotStates(c, message)
		case "match_event":
			c.hub.handleMatchEvent(c, message)
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
