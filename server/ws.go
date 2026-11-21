package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
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
	wsSendBuffer     = 256

	roomSlots = 6
	// Р‘РѕС‚С‹ Р·Р°РїРѕР»РЅСЏСЋС‚ РєРѕРјРЅР°С‚Сѓ С‡РµСЂРµР· 30 СЃРµРєСѓРЅРґ РїРѕСЃР»Рµ РїРѕСЃР»РµРґРЅРµРіРѕ Р¶РёРІРѕРіРѕ РёРіСЂРѕРєР°.
	// РўР°Р№РјРµСЂ РїРµСЂРµР·Р°РїСѓСЃРєР°РµС‚СЃСЏ РЅР° РєР°Р¶РґРѕРј РІС…РѕРґРµ, С‡С‚РѕР±С‹ РґСЂСѓР·СЊСЏ, Р·Р°С€РµРґС€РёРµ СЃ
	// СЂР°Р·РЅРёС†РµР№ РІ 10-25 СЃРµРєСѓРЅРґ (С‚РµР»РµС„РѕРЅ/РџРљ/Р·Р°РіСЂСѓР·РєР°), РїРѕРїР°Р»Рё РІ РѕРґРЅСѓ РєРѕРјРЅР°С‚Сѓ.
	roomBotFillDelay = 30 * time.Second

	matchLength      = 10 * time.Minute
	crystalsToWin    = 3
	deliveryLockout  = 5 * time.Second
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
	startsAt     time.Time
	fillTimer    *time.Timer
	finishTimer  *time.Timer
	resultSaved  bool
	score        [2]int
	suddenDeath  bool
	lastDelivery [2]time.Time
	shell        *wsShellState
	shellDiedAt  time.Time
	crystal      *wsCrystalState
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
	lastRegen    time.Time
	deadSince    time.Time
	lastAttacks  map[string]time.Time
	castHits     map[string]map[int64]time.Time
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
	lastSync     time.Time
	lastDamaged  time.Time
	lastRegen    time.Time
	lastStatGain time.Time
	statHpBudget float64
	healTokens   float64
	lastHeal     time.Time
	diedAt       time.Time
	castHits     map[string]map[int64]time.Time
	gold         int
	bought       map[string]bool
	coinTokens   float64
	lastCoin     time.Time
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
	Crit         bool            `json:"crit"`
	MaxHP        float64         `json:"max_hp"`
	HP           float64         `json:"hp"`
	AttackDamage float64         `json:"attack_damage"`
	WinningTeam  int             `json:"winning_team"`
	Event        string          `json:"event"`
	Token        string          `json:"token"`
	ItemID       string          `json:"item_id"`
	Bots         []wsBotSnapshot `json:"bots"`
	Shell        *wsShellState   `json:"shell"`
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

type wsShellState struct {
	Alive bool    `json:"alive"`
	HP    float64 `json:"hp,omitempty"`
	MaxHP float64 `json:"max_hp,omitempty"`
	X     float64 `json:"x"`
	Y     float64 `json:"y"`
	Z     float64 `json:"z"`
	Phase string  `json:"phase,omitempty"`
	Timer float64 `json:"timer,omitempty"`
}

type wsCrystalState struct {
	State       string    `json:"state"`
	X           float64   `json:"x"`
	Y           float64   `json:"y"`
	Z           float64   `json:"z"`
	CarrierID   int64     `json:"carrier_id,omitempty"`
	GroundSince time.Time `json:"-"`
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
	Crit         bool            `json:"crit,omitempty"`
	Amount       float64         `json:"amount,omitempty"`
	MaxHP        float64         `json:"max_hp,omitempty"`
	HP           float64         `json:"hp,omitempty"`
	Alive        bool            `json:"alive"`
	AttackDamage float64         `json:"attack_damage,omitempty"`
	WinningTeam  int             `json:"winning_team,omitempty"`
	MatchPlayers []wsMatchPlayer `json:"match_players,omitempty"`
	StartsInMS   int64           `json:"starts_in_ms,omitempty"`
	Bots         []wsBotSnapshot `json:"bots,omitempty"`
	Shell        *wsShellState   `json:"shell,omitempty"`
	Crystal      *wsCrystalState `json:"crystal,omitempty"`
	Protocol     int             `json:"protocol,omitempty"`
	Score0       int             `json:"score_0,omitempty"`
	Score1       int             `json:"score_1,omitempty"`
	SuddenDeath  bool            `json:"sudden_death,omitempty"`
	Event        string          `json:"event,omitempty"`
	Reason       string          `json:"reason,omitempty"`
	Error        string          `json:"error,omitempty"`
	Gold         int             `json:"gold,omitempty"`
	ItemID       string          `json:"item_id,omitempty"`
	OK           bool            `json:"ok,omitempty"`
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

	client.sendJSON(wsOutgoing{Type: "welcome", ID: client.id, Protocol: 4})
	log.Printf("ws client %d connected", client.id)

	go client.writePump()
	client.readPump()
}

func (h *wsHub) removeClient(client *wsClient) {
	var roomID int64
	var hostChanged *wsOutgoing
	var botRoster *wsOutgoing
	var lobbyState *wsOutgoing
	var crystalState *wsOutgoing
	h.mu.Lock()
	delete(h.clients, client.id)
	room := h.rooms[client.roomID]
	if room != nil {
		slot := roomSlotOf(room, client)
		if slot >= 0 {
			if room.state == "live" {
				room.bots[slot] = botFromClient(client, slot)
				botRoster = &wsOutgoing{Type: "bot_roster", RoomID: room.id, Bots: botSnapshotsLocked(room)}
			}
			room.players[slot] = nil
			room.humanCount--
		}
		if room.state == "live" {
			if crystal := h.dropCrystalForLocked(room, client.id, client.x, client.z); crystal != nil {
				crystalState = &wsOutgoing{Type: "crystal_state", RoomID: room.id, Crystal: crystal}
			}
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
			if room.state == "waiting" {
				lobbyState = &wsOutgoing{
					Type:         "lobby_state",
					RoomID:       room.id,
					StartsInMS:   maxInt64(0, time.Until(room.startsAt).Milliseconds()),
					MatchPlayers: lobbyPlayersLocked(room),
				}
			}
		}
	}
	h.mu.Unlock()

	client.close()
	if roomID != 0 {
		h.broadcastRoom(roomID, client.id, wsOutgoing{Type: "player_left", ID: client.id})
		if hostChanged != nil {
			h.broadcastRoom(roomID, 0, *hostChanged)
		}
		if botRoster != nil {
			h.broadcastRoom(roomID, 0, *botRoster)
		}
		if crystalState != nil {
			h.broadcastRoom(roomID, 0, *crystalState)
		}
		if lobbyState != nil {
			h.broadcastRoom(roomID, 0, *lobbyState)
		}
	}
}

func botFromClient(client *wsClient, slot int) *wsBot {
	class := clampClass(client.class)
	maxHP := client.maxHP
	if maxHP <= 0 {
		maxHP = classBaseHP[class]
	}
	hp := client.hp
	if hp < 0 {
		hp = 0
	}
	if hp > maxHP {
		hp = maxHP
	}
	alive := client.alive
	if !alive {
		hp = 0
	}
	if alive && hp <= 0 {
		hp = maxHP
	}
	damage := client.attackDamage
	if damage <= 0 {
		damage = classBaseDamage[class]
	}
	x, y, z, rotation := client.x, client.y, client.z, client.rotation
	if !client.hasState {
		x = float64((slot%3)-1) * 2.0
		y = 0.76
		z = 27.5
		rotation = 0.0
		if slot/3 == 1 {
			z = -27.5
			rotation = math.Pi
		}
	}
	if y <= 0 {
		y = 0.76
	}
	name := client.name
	if name == "" {
		name = fmt.Sprintf("РРіСЂРѕРє %d", client.id)
	}
	var deadSince time.Time
	if !alive {
		deadSince = time.Now()
	}
	return &wsBot{
		id:           -int64(slot + 1),
		name:         name,
		class:        class,
		team:         slot / 3,
		x:            x,
		y:            y,
		z:            z,
		rotation:     rotation,
		maxHP:        maxHP,
		hp:           hp,
		attackDamage: damage,
		alive:        alive,
		deadSince:    deadSince,
		hasState:     true,
		lastAttacks:  make(map[string]time.Time),
	}
}

func (h *wsHub) sessionAllowed(playerID int64, token string) bool {
	if playerID <= 0 || h.db == nil {
		return true
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	var stored string
	err := h.db.QueryRowContext(ctx, `SELECT COALESCE(session_token, '') FROM players WHERE id = $1`, playerID).Scan(&stored)
	if errors.Is(err, sql.ErrNoRows) {
		return false
	}
	if err != nil {
		// A database hiccup must not lock players out of a match.
		return true
	}
	if stored == "" {
		// Legacy account that has not claimed a token yet.
		return true
	}
	return strings.TrimSpace(token) == stored
}

func (h *wsHub) joinMatchmaking(client *wsClient, message wsIncoming) {
	class := resolveClass(message)
	if class < 0 {
		return
	}
	name := strings.TrimSpace(message.Name)
	if name == "" {
		name = fmt.Sprintf("РРіСЂРѕРє %d", client.id)
	}
	runes := []rune(name)
	if len(runes) > 32 {
		name = string(runes[:32])
	}
	if !h.sessionAllowed(message.PlayerID, message.Token) {
		client.sendJSON(wsOutgoing{Type: "error", Error: "invalid_session"})
		return
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
	// Balance teams immediately so the search screen shows the real teams;
	// otherwise both players see themselves as allies and one is moved to
	// the other team only at match start.
	balanceHumansLocked(room)
	if balancedSlot := roomSlotOf(room, client); balancedSlot >= 0 {
		slot = balancedSlot
		client.team = slot / 3
	}
	// Variant 1: start exactly 30 seconds after the FIRST player. New joins
	// never reset the countdown; the room is locked 3 seconds before start.
	if room.startsAt.IsZero() {
		room.startsAt = time.Now().Add(roomBotFillDelay)
	}
	if room.hostID == 0 {
		room.hostID = client.id
	}
	if room.fillTimer == nil && room.humanCount < roomSlots {
		roomID := room.id
		room.fillTimer = time.AfterFunc(time.Until(room.startsAt), func() { h.startRoom(roomID) })
	}

	var startMessage wsOutgoing
	var startClients []*wsClient
	if room.humanCount >= roomSlots {
		startMessage, startClients = h.startRoomLocked(room)
	}
	roomID := room.id
	hostID := room.hostID
	team := client.team
	lobbyMessage := wsOutgoing{
		Type:         "lobby_state",
		RoomID:       roomID,
		StartsInMS:   maxInt64(0, time.Until(room.startsAt).Milliseconds()),
		MatchPlayers: lobbyPlayersLocked(room),
	}
	lobbyClients := roomClientsLocked(room, 0)
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
	h.sendToClients(lobbyClients, lobbyMessage)
}

func (h *wsHub) findRoomLocked(_ int) (*wsRoom, int) {
	var best *wsRoom
	for _, room := range h.rooms {
		if room.state != "waiting" || room.humanCount >= roomSlots {
			continue
		}
		// Lock the room for the last 3 seconds so a late join cannot appear
		// in the roster with one second left before the fight.
		if !room.startsAt.IsZero() && time.Until(room.startsAt) <= 3*time.Second {
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

func botClassesForRoom(room *wsRoom) [roomSlots]int {
	var classes [roomSlots]int
	for team := 0; team < 2; team++ {
		var used [3]bool
		for slot := team * 3; slot < team*3+3; slot++ {
			if player := room.players[slot]; player != nil {
				used[clampClass(player.class)] = true
			}
		}
		missing := make([]int, 0, 3)
		for class := 0; class < 3; class++ {
			if !used[class] {
				missing = append(missing, class)
			}
		}
		missingIndex := 0
		for slot := team * 3; slot < team*3+3; slot++ {
			if room.players[slot] != nil {
				classes[slot] = clampClass(room.players[slot].class)
				continue
			}
			class := slot % 3
			if missingIndex < len(missing) {
				class = missing[missingIndex]
				missingIndex++
			}
			classes[slot] = class
		}
	}
	return classes
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
	room.shell = nil
	room.crystal = nil
	if room.hostID == 0 {
		for index := 0; index < roomSlots; index++ {
			if player := room.players[index]; player != nil {
				room.hostID = player.id
				break
			}
		}
	}
	balanceHumansLocked(room)
	botClasses := botClassesForRoom(room)
	players := make([]wsMatchPlayer, 0, roomSlots)
	clients := make([]*wsClient, 0, room.humanCount)
	for slot := 0; slot < roomSlots; slot++ {
		class := botClasses[slot]
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
			player.gold = 0
			player.bought = nil
			player.coinTokens = 0
			player.lastCoin = time.Time{}
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
		botName := fmt.Sprintf("РРіСЂРѕРє %04d", 1000+int((room.id*37+int64(slot)*211)%9000))
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
	now := time.Now()
	if client.alive && client.maxHP > 0.0 {
		if client.lastRegen.IsZero() {
			client.lastRegen = now
		}
		elapsed := now.Sub(client.lastRegen).Seconds()
		if elapsed > 0.0 && elapsed <= 1.0 && (client.lastDamaged.IsZero() || now.Sub(client.lastDamaged) >= 5*time.Second) {
			rate := 10.0
			baseZ := 27.5
			if client.team == 1 {
				baseZ = -27.5
			}
			if math.Hypot(client.x, client.z-baseZ) <= 6.5 {
				// Base regen must stay below a warrior's ~55 DPS, otherwise
				// the defender cannot die while standing on the base.
				rate *= 2.0
			}
			client.hp = math.Min(client.maxHP, client.hp+rate*elapsed)
		}
		client.lastRegen = now
	}
	targets := roomClientsLocked(room, client.id)
	syncDue := time.Since(client.lastSync) >= time.Second
	if syncDue {
		client.lastSync = time.Now()
	}
	syncMessage := wsOutgoing{
		Type:   "sync",
		ID:     client.id,
		RoomID: room.id,
		HP:     client.hp,
		MaxHP:  client.maxHP,
		Alive:  client.alive,
	}
	var crystalMoved *wsCrystalState
	if room.crystal != nil && room.crystal.State == "ground" && !room.crystal.GroundSince.IsZero() && now.Sub(room.crystal.GroundSince) >= 30*time.Second {
		// A dropped shard must never stall the match: after 30 s it returns to
		// the altar, exactly like the offline rule.
		room.crystal.X = 0
		room.crystal.Y = 0.5
		room.crystal.Z = 0
		room.crystal.GroundSince = now
		c := *room.crystal
		crystalMoved = &c
	}
	stateX, stateY, stateZ, stateRot := client.x, client.y, client.z, client.rotation
	stateHP, stateMaxHP, stateAlive := client.hp, client.maxHP, client.alive
	roomID := room.id
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
		Type:     "state",
		ID:       client.id,
		RoomID:   roomID,
		Class:    client.class,
		Team:     client.team,
		X:        stateX,
		Y:        stateY,
		Z:        stateZ,
		Rotation: stateRot,
		HP:       stateHP,
		MaxHP:    stateMaxHP,
		Alive:    stateAlive,
	})
	if syncDue {
		client.sendJSON(syncMessage)
	}
	if crystalMoved != nil {
		h.broadcastRoom(roomID, 0, wsOutgoing{
			Type:    "crystal_state",
			RoomID:  roomID,
			Crystal: crystalMoved,
		})
	}
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
	if !finite(message.MaxHP) || message.MaxHP <= 0 {
		return
	}
	if !finite(message.HP) || message.HP < 0 || !finite(message.AttackDamage) || message.AttackDamage < 0 {
		return
	}
	h.mu.Lock()
	if _, exists := h.clients[client.id]; !exists {
		h.mu.Unlock()
		return
	}
	room := h.rooms[client.roomID]
	if room == nil {
		h.mu.Unlock()
		return
	}
	class := client.class
	if class < 0 || class >= len(classBaseHP) {
		class = 0
	}
	// The client may buy upgrades, but never declare arbitrary combat stats:
	// an unchecked stats packet used to allow 100000 HP / damage.
	maxCap := classBaseHP[class] * 1.6
	damageCap := classBaseDamage[class] * 2.5
	if message.MaxHP > maxCap || message.AttackDamage > damageCap {
		h.mu.Unlock()
		return
	}
	hp := math.Min(message.HP, message.MaxHP)
	newMax := math.Min(message.MaxHP, maxCap)
	client.maxHP = newMax
	client.attackDamage = message.AttackDamage
	// HP is owned by the server. A client "stats" packet may only add a
	// bounded amount of HP per second (lifesteal / a bought life amulet),
	// never restore a full bar after taking damage. Passive regen is applied
	// by the server from movement updates, and respawn sets full HP.
	now := time.Now()
	if now.Sub(client.lastStatGain) >= time.Second {
		client.lastStatGain = now
		client.statHpBudget = 300.0
	}
	if client.hp < client.maxHP {
		gain := math.Max(0.0, math.Min(hp, client.maxHP)-client.hp)
		gain = math.Min(gain, client.statHpBudget)
		client.hp = math.Min(client.maxHP, client.hp+gain)
		client.statHpBudget -= gain
	}
	hp = client.hp
	maxHP := client.maxHP
	attackDamage := client.attackDamage
	targets := roomClientsLocked(room, client.id)
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
		Type:         "stats",
		ID:           client.id,
		MaxHP:        maxHP,
		HP:           hp,
		AttackDamage: attackDamage,
	})
}

func (h *wsHub) relayHeal(client *wsClient, message wsIncoming) {
	if message.TargetID == 0 || message.TargetID == client.id || !finite(message.Amount) || message.Amount <= 0 {
		return
	}
	amount := math.Min(message.Amount, 400)
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || !client.alive {
		h.mu.Unlock()
		return
	}
	// A dead healer used to keep allies immortal, and an unlimited packet rate
	// meant infinite healing. Budget a few heals per second per client
	// (an AoE heal sends one packet per ally, so allow a small burst).
	now := time.Now()
	if client.lastHeal.IsZero() {
		client.healTokens = 4.0
	} else {
		client.healTokens = math.Min(4.0, client.healTokens+now.Sub(client.lastHeal).Seconds()*4.0)
	}
	client.lastHeal = now
	if client.healTokens < 1.0 {
		h.mu.Unlock()
		return
	}
	client.healTokens -= 1.0
	var targetID int64
	if target := findRoomPlayerLocked(room, message.TargetID); target != nil {
		if !target.alive || target.team != client.team || target.maxHP <= 0 {
			h.mu.Unlock()
			return
		}
		target.hp = math.Min(target.maxHP, target.hp+amount)
		targetID = target.id
	} else if bot := findRoomBotLocked(room, message.TargetID); bot != nil {
		if !bot.alive || bot.team != client.team {
			h.mu.Unlock()
			return
		}
		bot.hp = math.Min(bot.maxHP, bot.hp+amount)
		targetID = bot.id
	} else {
		h.mu.Unlock()
		return
	}
	targets := roomClientsLocked(room, client.id)
	roomID := room.id
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
		Type:     "heal",
		ID:       client.id,
		RoomID:   roomID,
		SourceID: client.id,
		TargetID: targetID,
		Amount:   amount,
	})
}

func (h *wsHub) relayDeath(client *wsClient) {
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || !client.alive {
		h.mu.Unlock()
		return
	}
	// Death is server-owned. A client could otherwise drop the shard anywhere
	// for free while still at full HP.
	if client.hp > 0 {
		h.mu.Unlock()
		return
	}
	client.alive = false
	client.hp = 0
	client.diedAt = time.Now()
	crystal := h.dropCrystalForLocked(room, client.id, client.x, client.z)
	targets := roomClientsLocked(room, client.id)
	roomID := room.id
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{Type: "death", ID: client.id, RoomID: roomID})
	if crystal != nil {
		h.broadcastRoom(roomID, 0, wsOutgoing{Type: "crystal_state", RoomID: roomID, Crystal: crystal})
	}
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
	// Respawn is only legal after a real death and after a minimum delay;
	// otherwise a live player could teleport home with a full health bar.
	if client.alive {
		h.mu.Unlock()
		return
	}
	deadFor := time.Since(client.diedAt)
	if client.diedAt.IsZero() || deadFor < 4*time.Second {
		h.mu.Unlock()
		return
	}
	client.alive = true
	client.hp = client.maxHP
	client.diedAt = time.Time{}
	client.lastDamaged = time.Time{}
	client.lastRegen = time.Now()
	client.x = clampArenaX(message.X)
	client.y = message.Y
	client.z = clampArenaZ(message.Z)
	client.rotation = message.Rotation
	client.hasState = true
	x, y, z, rotation := client.x, client.y, client.z, client.rotation
	targets := roomClientsLocked(room, client.id)
	roomID := room.id
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
		Type:     "respawn",
		ID:       client.id,
		RoomID:   roomID,
		X:        x,
		Y:        y,
		Z:        z,
		Rotation: rotation,
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
	castHits     map[string]map[int64]time.Time
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
	var crystalOut *wsCrystalState
	now := time.Now()
	for _, state := range message.Bots {
		bot := findRoomBotLocked(room, state.ID)
		if bot == nil {
			continue
		}
		if !finite(state.X) || !finite(state.Y) || !finite(state.Z) || !finite(state.Rotation) {
			continue
		}
		if math.Abs(state.X) > 1000 || math.Abs(state.Z) > 1000 {
			continue
		}
		bot.x = state.X
		bot.y = state.Y
		bot.z = state.Z
		bot.rotation = state.Rotation
		bot.animation = truncateText(state.Animation, 24)
		if bot.alive && !state.Alive {
			// The host saw the bot die (a local DoT, an environment kill, or
			// a hit the server did not confirm). Accept the death so a bot
			// carrying the shard cannot leave it stuck in "carried".
			bot.hp = 0
			bot.alive = false
			bot.deadSince = now
			if crystal := h.dropCrystalForLocked(room, bot.id, bot.x, bot.z); crystal != nil {
				crystalOut = crystal
			}
			changed = true
			continue
		}
		if bot.alive {
			if bot.lastRegen.IsZero() {
				bot.lastRegen = now
			}
			elapsed := now.Sub(bot.lastRegen).Seconds()
			if elapsed > 0.0 && elapsed <= 1.0 && (bot.lastDamaged.IsZero() || now.Sub(bot.lastDamaged) >= 5*time.Second) {
				rate := 10.0
				baseZ := 27.5
				if bot.team == 1 {
					baseZ = -27.5
				}
				if math.Hypot(bot.x, bot.z-baseZ) <= 6.5 {
					rate *= 2.0
				}
				bot.hp = math.Min(bot.maxHP, bot.hp+rate*elapsed)
			}
			bot.lastRegen = now
		}
		if !bot.alive && state.Alive && !bot.deadSince.IsZero() && now.Sub(bot.deadSince) >= 1500*time.Millisecond {
			// The host's respawn timer won. The server restores the bot and
			// broadcasts the new HP to every client.
			bot.hp = bot.maxHP
			bot.alive = true
			bot.deadSince = time.Time{}
			bot.lastRegen = now
		}
		changed = true
	}
	if !changed {
		h.mu.Unlock()
		return
	}
	roomID := room.id
	snapshots := botSnapshotsLocked(room)
	// Include the host: it applies the server's HP to its local bots.
	targets := roomClientsLocked(room, 0)
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
		Type:   "bot_states",
		RoomID: roomID,
		Bots:   snapshots,
	})
	if crystalOut != nil {
		h.broadcastRoom(roomID, 0, wsOutgoing{
			Type:    "crystal_state",
			RoomID:  roomID,
			Crystal: crystalOut,
		})
	}
}

// The base shield is a hard rule: a defender standing on their own base cannot
// be damaged. It used to exist only in the local client, so network attacks
// ignored it completely.
func underBaseShield(team int, x, z float64) bool {
	baseZ := 27.5
	if team == 1 {
		baseZ = -27.5
	}
	return math.Hypot(x, z-baseZ) <= 5.0
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
	if underBaseShield(target.team, target.x, target.z) {
		h.mu.Unlock()
		denyAttack(client, message.TargetID, skill, "base_shield")
		return
	}
	if !inAttackRange(source, target, skill) {
		h.mu.Unlock()
		denyAttack(client, message.TargetID, skill, "out_of_range")
		return
	}
	if !skillAllowedForClass(source.class, skill) {
		h.mu.Unlock()
		denyAttack(client, message.TargetID, skill, "invalid_skill")
		return
	}
	if !source.allowAttack(skill, target.id) {
		h.mu.Unlock()
		denyAttack(client, message.TargetID, skill, "cooldown")
		return
	}
	damage := calculateDamageFor(source.attackDamage, source.class, skill)
	if finite(message.Amount) && message.Amount > 0 {
		// The client sends the rolled hit (crits, buffs). Keep server authority
		// by clamping it to a sane multiple of the class attack value.
		cap := math.Max(source.attackDamage*6.0, 400.0)
		if message.Amount <= cap {
			damage = math.Round(message.Amount*100) / 100
		}
	}
	died := target.applyDamage(damage)
	if died && source.client != nil {
		source.client.gold += 50
		source.client.sendJSON(wsOutgoing{Type: "gold", Gold: source.client.gold})
	}
	sourceID := source.id
	targetID := target.id
	roomID := room.id
	var crystal *wsCrystalState
	if died {
		switch {
		case target.bot != nil:
			crystal = h.dropCrystalForLocked(room, target.bot.id, target.bot.x, target.bot.z)
		case target.client != nil:
			crystal = h.dropCrystalForLocked(room, target.client.id, target.client.x, target.client.z)
		}
	}
	h.mu.Unlock()

	h.broadcastRoom(roomID, 0, wsOutgoing{
		Type:     "damage",
		ID:       sourceID,
		RoomID:   roomID,
		SourceID: sourceID,
		TargetID: targetID,
		Skill:    skill,
		Crit:     message.Crit,
		Amount:   damage,
	})
	if died {
		h.broadcastRoom(roomID, 0, wsOutgoing{Type: "death", ID: targetID, RoomID: roomID, SourceID: sourceID})
		if crystal != nil {
			h.broadcastRoom(roomID, 0, wsOutgoing{Type: "crystal_state", RoomID: roomID, Crystal: crystal})
		}
	}
}

func (h *wsHub) relayShellState(client *wsClient, message wsIncoming) {
	if message.Shell == nil {
		return
	}
	state := *message.Shell
	if !finite(state.X) || !finite(state.Y) || !finite(state.Z) {
		return
	}
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || room.hostID != client.id {
		h.mu.Unlock()
		return
	}
	if room.shell == nil {
		room.shell = &wsShellState{Alive: true, HP: 1000, MaxHP: 1000}
	}
	if !finite(state.X) || !finite(state.Y) || !finite(state.Z) {
		h.mu.Unlock()
		return
	}
	state.X = clampArenaX(state.X)
	state.Z = clampArenaZ(state.Z)
	if state.Alive && !room.shell.Alive {
		// A new shell must not start while the shard from the previous one is
		// still on the field, and a stale "alive" packet sent before the host
		// learned about the death must not resurrect it.
		shardActive := room.crystal != nil && room.crystal.State != "none"
		tooSoon := !room.shellDiedAt.IsZero() && time.Since(room.shellDiedAt) < 2*time.Second
		if shardActive || tooSoon {
			state.Alive = false
		} else {
			room.shell.HP = 1000
			room.shell.MaxHP = 1000
		}
	}
	room.shell.Alive = state.Alive
	room.shell.X = state.X
	room.shell.Y = state.Y
	room.shell.Z = state.Z
	room.shell.Phase = truncateText(state.Phase, 16)
	room.shell.Timer = state.Timer
	shell := *room.shell
	roomID := room.id
	targets := roomClientsLocked(room, 0)
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
		Type:   "shell_state",
		RoomID: roomID,
		Shell:  &shell,
	})
}

func (h *wsHub) handleShellAttack(client *wsClient, message wsIncoming) {
	if !finite(message.Amount) || message.Amount <= 0 || message.Amount > 800 {
		return
	}
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || room.shell == nil || !room.shell.Alive {
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
	if source == nil || !source.alive || !source.hasState {
		h.mu.Unlock()
		return
	}
	distance := math.Hypot(source.x-room.shell.X, source.z-room.shell.Z)
	if distance > maxAttackRange(source.class, "shell")+1.5 {
		h.mu.Unlock()
		return
	}
	if !source.cooldownReady("shell") {
		h.mu.Unlock()
		return
	}
	room.shell.HP = math.Max(0, room.shell.HP-message.Amount)
	died := room.shell.HP <= 0
	if died {
		room.shell.Alive = false
	}
	shell := *room.shell
	var crystal *wsCrystalState
	if died {
		room.shellDiedAt = time.Now()
		teamGoldLocked(room, source.team, 100)
		if room.crystal == nil || room.crystal.State == "none" {
			room.crystal = &wsCrystalState{State: "ground", X: shell.X, Y: 0.5, Z: shell.Z, GroundSince: time.Now()}
			c := *room.crystal
			crystal = &c
		}
	}
	roomID := room.id
	sourceID := source.id
	targets := roomClientsLocked(room, 0)
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
		Type:   "shell_state",
		RoomID: roomID,
		Shell:  &shell,
	})
	h.broadcastRoom(roomID, 0, wsOutgoing{
		Type:     "shell_damage",
		RoomID:   roomID,
		SourceID: sourceID,
		Amount:   message.Amount,
	})
	if died {
		h.broadcastRoom(roomID, 0, wsOutgoing{
			Type:     "match_event",
			RoomID:   roomID,
			Event:    "shell_destroyed",
			Team:     source.team,
			SourceID: sourceID,
		})
		if crystal != nil {
			h.broadcastRoom(roomID, 0, wsOutgoing{
				Type:    "crystal_state",
				RoomID:  roomID,
				Crystal: crystal,
			})
		}
	}
}

func (h *wsHub) handleBotDamage(client *wsClient, message wsIncoming) {
	if !finite(message.Amount) || message.Amount <= 0 || message.Amount > 800 {
		return
	}
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || room.hostID != client.id {
		h.mu.Unlock()
		return
	}
	bot := findRoomBotLocked(room, message.TargetID)
	if bot == nil || !bot.alive {
		h.mu.Unlock()
		return
	}
	bot.hp = math.Max(0, bot.hp-message.Amount)
	bot.lastDamaged = time.Now()
	bot.lastRegen = time.Now()
	died := bot.hp <= 0
	if died {
		bot.alive = false
		if bot.deadSince.IsZero() {
			bot.deadSince = time.Now()
		}
	}
	roomID := room.id
	targetID := bot.id
	var crystal *wsCrystalState
	if died {
		crystal = h.dropCrystalForLocked(room, bot.id, bot.x, bot.z)
	}
	h.mu.Unlock()
	h.broadcastRoom(roomID, 0, wsOutgoing{
		Type:     "damage",
		RoomID:   roomID,
		TargetID: targetID,
		Skill:    "shell",
		Amount:   message.Amount,
	})
	if died {
		h.broadcastRoom(roomID, 0, wsOutgoing{Type: "death", ID: targetID, RoomID: roomID})
		if crystal != nil {
			h.broadcastRoom(roomID, 0, wsOutgoing{Type: "crystal_state", RoomID: roomID, Crystal: crystal})
		}
	}
}

// The host simulates the shell; its PvE damage on remote humans must go through
// the server, otherwise guests are immune to the shell (it only knows heroes).
var matchItemPrices = map[string]int{
	"life_amulet":      500,
	"revival_talisman": 450,
	"titan_shell":      450,
	"power_glove":      500,
	"vampire_fang":     500,
	"agility_mark":     450,
	"wind_boots":       350,
	"hourglass":        450,
	"cleansing_charm":  350,
}

// Gold is a match-scoped currency. The server owns the ledger so a modified
// client cannot buy items it did not earn; the client still applies the item
// effect after the server confirms the purchase.
func teamGoldLocked(room *wsRoom, team int, amount int) {
	for _, player := range room.players {
		if player == nil || player.team != team {
			continue
		}
		player.gold += amount
		if player.gold < 0 {
			player.gold = 0
		}
		player.sendJSON(wsOutgoing{Type: "gold", Gold: player.gold})
	}
}

func (h *wsHub) handleCoinPickup(client *wsClient, message wsIncoming) {
	amount := int(math.Round(message.Amount))
	if amount <= 0 || amount > 5 {
		return
	}
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || !client.alive {
		h.mu.Unlock()
		return
	}
	now := time.Now()
	if client.lastCoin.IsZero() {
		client.coinTokens = 6
	} else {
		client.coinTokens = math.Min(6, client.coinTokens+now.Sub(client.lastCoin).Seconds()*6)
	}
	client.lastCoin = now
	if client.coinTokens < float64(amount) {
		h.mu.Unlock()
		return
	}
	client.coinTokens -= float64(amount)
	client.gold += amount
	gold := client.gold
	h.mu.Unlock()
	client.sendJSON(wsOutgoing{Type: "gold", Gold: gold})
}

func (h *wsHub) handleBuyItem(client *wsClient, message wsIncoming) {
	itemID := strings.TrimSpace(message.ItemID)
	price, known := matchItemPrices[itemID]
	if !known {
		return
	}
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || !client.alive {
		h.mu.Unlock()
		return
	}
	if client.bought == nil {
		client.bought = make(map[string]bool)
	}
	reject := func() {
		client.sendJSON(wsOutgoing{Type: "shop_purchase", ItemID: itemID, OK: false, Gold: client.gold})
		h.mu.Unlock()
	}
	if client.bought[itemID] {
		reject()
		return
	}
	if math.Hypot(client.x-(-40.0), client.z-0.0) > 6.0 {
		reject()
		return
	}
	if client.gold < price {
		reject()
		return
	}
	client.gold -= price
	client.bought[itemID] = true
	gold := client.gold
	h.mu.Unlock()
	client.sendJSON(wsOutgoing{Type: "shop_purchase", ItemID: itemID, OK: true, Gold: gold})
}

func (h *wsHub) handleWorldDamage(client *wsClient, message wsIncoming) {
	if !finite(message.Amount) || message.Amount <= 0 || message.Amount > 300 {
		return
	}
	if message.TargetID <= 0 {
		return
	}
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || room.hostID != client.id {
		h.mu.Unlock()
		return
	}
	if room.shell == nil || !room.shell.Alive {
		h.mu.Unlock()
		return
	}
	target := findRoomPlayerLocked(room, message.TargetID)
	if target == nil || !target.alive || !target.hasState {
		h.mu.Unlock()
		return
	}
	if math.Hypot(target.x-room.shell.X, target.z-room.shell.Z) > 15.0 {
		h.mu.Unlock()
		return
	}
	if underBaseShield(target.team, target.x, target.z) {
		h.mu.Unlock()
		return
	}
	died := combatantFromClient(target).applyDamage(message.Amount)
	targetID := target.id
	roomID := room.id
	var crystal *wsCrystalState
	if died {
		crystal = h.dropCrystalForLocked(room, target.id, target.x, target.z)
	}
	h.mu.Unlock()
	h.broadcastRoom(roomID, 0, wsOutgoing{
		Type:     "damage",
		RoomID:   roomID,
		SourceID: 0,
		TargetID: targetID,
		Skill:    "shell",
		Amount:   message.Amount,
	})
	if died {
		h.broadcastRoom(roomID, 0, wsOutgoing{Type: "death", ID: targetID, RoomID: roomID})
		if crystal != nil {
			h.broadcastRoom(roomID, 0, wsOutgoing{Type: "crystal_state", RoomID: roomID, Crystal: crystal})
		}
	}
}

func (h *wsHub) dropCrystalForLocked(room *wsRoom, id int64, x float64, z float64) *wsCrystalState {
	if room.crystal == nil || room.crystal.State != "carried" || room.crystal.CarrierID != id {
		return nil
	}
	room.crystal.State = "ground"
	room.crystal.X = clampArenaX(x)
	room.crystal.Y = 0.5
	room.crystal.Z = clampArenaZ(z)
	room.crystal.CarrierID = 0
	room.crystal.GroundSince = time.Now()
	crystal := *room.crystal
	return &crystal
}

func (h *wsHub) handleCrystalPickup(client *wsClient, message wsIncoming) {
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || room.crystal == nil || room.crystal.State != "ground" {
		h.mu.Unlock()
		return
	}
	var sourceID int64
	var x, z float64
	var hasState, alive bool
	var team int
	switch {
	case message.SourceID == 0 || message.SourceID == client.id:
		sourceID, x, z, hasState, alive, team = client.id, client.x, client.z, client.hasState, client.alive, client.team
	case message.SourceID < 0 && room.hostID == client.id:
		if bot := findRoomBotLocked(room, message.SourceID); bot != nil {
			sourceID, x, z, hasState, alive, team = bot.id, bot.x, bot.z, bot.hasState, bot.alive, bot.team
		}
	}
	if sourceID == 0 || !hasState || !alive {
		h.mu.Unlock()
		return
	}
	if math.Hypot(x-room.crystal.X, z-room.crystal.Z) > 3.2 {
		h.mu.Unlock()
		return
	}
	_ = team
	room.crystal.State = "carried"
	room.crystal.CarrierID = sourceID
	room.crystal.GroundSince = time.Time{}
	crystal := *room.crystal
	roomID := room.id
	targets := roomClientsLocked(room, 0)
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
		Type:    "crystal_state",
		RoomID:  roomID,
		Crystal: &crystal,
	})
}

func (h *wsHub) handleCrystalDeliver(client *wsClient, message wsIncoming) {
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || room.crystal == nil || room.crystal.State != "carried" {
		h.mu.Unlock()
		return
	}
	var sourceID int64
	var x, z float64
	var hasState, alive bool
	var team int
	switch {
	case message.SourceID == 0 || message.SourceID == client.id:
		sourceID, x, z, hasState, alive, team = client.id, client.x, client.z, client.hasState, client.alive, client.team
	case message.SourceID < 0 && room.hostID == client.id:
		if bot := findRoomBotLocked(room, message.SourceID); bot != nil {
			sourceID, x, z, hasState, alive, team = bot.id, bot.x, bot.z, bot.hasState, bot.alive, bot.team
		}
	}
	if sourceID == 0 || !hasState || !alive || room.crystal.CarrierID != sourceID {
		h.mu.Unlock()
		return
	}
	baseZ := 27.5
	if team == 1 {
		baseZ = -27.5
	}
	if math.Hypot(x, z-baseZ) > 7.0 {
		h.mu.Unlock()
		return
	}
	room.score[team]++
	teamGoldLocked(room, team, 100)
	score0, score1 := room.score[0], room.score[1]
	winner := -1
	var players []matchResultPlayer
	if room.suddenDeath || room.score[team] >= crystalsToWin {
		winner = team
		players = h.finishMatchLocked(room)
	}
	room.crystal.State = "none"
	room.crystal.CarrierID = 0
	room.crystal.GroundSince = time.Time{}
	crystal := *room.crystal
	roomID := room.id
	deliveredBy := sourceID
	targets := roomClientsLocked(room, 0)
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
		Type:    "crystal_state",
		RoomID:  roomID,
		Crystal: &crystal,
	})
	// Gold is a client-side match reward, but the server must say who scored:
	// clients cannot infer the carrier after crystal_state drops to "none".
	h.broadcastRoom(roomID, 0, wsOutgoing{
		Type:     "match_event",
		RoomID:   roomID,
		Event:    "shard_delivered",
		Team:     team,
		SourceID: deliveredBy,
	})
	h.broadcastRoom(roomID, 0, wsOutgoing{
		Type:        "match_score",
		RoomID:      roomID,
		Score0:      score0,
		Score1:      score1,
		SuddenDeath: room.suddenDeath,
	})
	if winner >= 0 {
		h.saveMatch(roomID, players, winner)
		h.broadcastRoom(roomID, 0, wsOutgoing{
			Type:        "match_finished",
			RoomID:      roomID,
			WinningTeam: winner,
			Score0:      score0,
			Score1:      score1,
			Reason:      "score",
		})
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
		// Legacy clients report the delivery themselves. Never award a free
		// point: run the same checks as crystal_deliver (carried shard, the
		// sender is the carrier, own base) so the shard is actually consumed.
		h.mu.Unlock()
		delivery := message
		delivery.SourceID = 0
		h.handleCrystalDeliver(client, delivery)
	case "shell_destroyed":
		// Only the host simulates the shell; a guest could otherwise disable
		// every shard spawn by faking this event.
		team := message.Team
		if team < 0 || team > 1 || client.id != room.hostID {
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
	case "shell_bolt":
		// Visual only: guests cannot simulate the shell, so the host tells them
		// where the lightning landed. No damage is derived from this event.
		if client.id != room.hostID {
			h.mu.Unlock()
			return
		}
		x, z := message.X, message.Z
		if !finite(x) || !finite(z) {
			h.mu.Unlock()
			return
		}
		targets := roomClientsLocked(room, client.id)
		h.mu.Unlock()
		h.sendToClients(targets, wsOutgoing{
			Type:   "match_event",
			RoomID: roomID,
			Event:  "shell_bolt",
			X:      clampArenaX(x),
			Z:      clampArenaZ(z),
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
	if score0 == score1 && !room.suddenDeath {
		room.suddenDeath = true
		if room.finishTimer != nil {
			room.finishTimer.Stop()
		}
		// Sudden death must not hang forever if nobody can score.
		room.finishTimer = time.AfterFunc(2*time.Minute, func() {
			h.finishMatchByTimeout(roomID)
		})
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
		Reason:      "time",
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
	log.Printf("attack denied client=%d target=%d skill=%s reason=%s hp=%.0f alive=%v", client.id, targetID, skill, reason, client.hp, client.alive)
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
		castHits:     client.castHits,
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
		castHits:     bot.castHits,
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
		if !combatant.alive && combatant.client.diedAt.IsZero() {
			combatant.client.diedAt = time.Now()
		}
		combatant.client.lastDamaged = time.Now()
		combatant.client.lastRegen = time.Now()
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
	if last, ok := combatant.lastAttacks[skill]; ok {
		elapsed := now.Sub(last)
		if elapsed < attackCooldownFor(combatant.class, skill) {
			// One AoE cast sends one intent per target. Those targets arrive
			// within a few milliseconds; allow them without refreshing the
			// cooldown, otherwise only the first target took damage.
			if elapsed <= 350*time.Millisecond && isMultiTargetSkill(skill) {
				return true
			}
			return false
		}
	}
	combatant.lastAttacks[skill] = now
	return true
}

func isMultiTargetSkill(skill string) bool {
	switch strings.ToLower(skill) {
	case "fear_ult", "fairy_ult", "ult_lightning_storm":
		return true
	}
	return false
}

// Each class may only use its own abilities. Without this a warrior could
// spam the fairy's 18 m stun or the mage's storm, and every skill was accepted
// from any client.
func skillAllowedForClass(class int, skill string) bool {
	switch strings.ToLower(skill) {
	case "auto":
		return true
	case "shadow_assassin", "fear_ult":
		return class == 0
	case "root", "ult_lightning_storm":
		return class == 1
	case "stun", "stun_shot", "fairy_ult", "crit_shot":
		return class == 2
	}
	return false
}

// allowAttack applies the per-skill cooldown and, for one AoE cast that sends
// one intent per target, allows each target exactly once per cast window.
// The old check allowed unlimited hits for 350 ms after every cast.
func (combatant *wsCombatant) allowAttack(skill string, targetID int64) bool {
	now := time.Now()
	if combatant.lastAttacks == nil {
		combatant.lastAttacks = make(map[string]time.Time)
		if combatant.client != nil {
			combatant.client.lastAttacks = combatant.lastAttacks
		}
		if combatant.bot != nil {
			combatant.bot.lastAttacks = combatant.lastAttacks
		}
	}
	if combatant.castHits == nil {
		combatant.castHits = make(map[string]map[int64]time.Time)
		if combatant.client != nil {
			combatant.client.castHits = combatant.castHits
		}
		if combatant.bot != nil {
			combatant.bot.castHits = combatant.castHits
		}
	}
	if isMultiTargetSkill(skill) {
		start := combatant.lastAttacks[skill]
		if !start.IsZero() && now.Sub(start) <= 400*time.Millisecond {
			hits := combatant.castHits[skill]
			if hits == nil {
				hits = make(map[int64]time.Time)
				combatant.castHits[skill] = hits
			}
			if _, seen := hits[targetID]; seen {
				return false
			}
			hits[targetID] = now
			return true
		}
		if !start.IsZero() && now.Sub(start) < attackCooldownFor(combatant.class, skill) {
			return false
		}
		combatant.lastAttacks[skill] = now
		combatant.castHits[skill] = map[int64]time.Time{targetID: now}
		return true
	}
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
	// Small tolerance for interpolation: the target keeps moving while the
	// packet travels, so an exact radius check caused false rejections.
	return distance <= maxAttackRange(source.class, skill)+1.5
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

func lobbyPlayersLocked(room *wsRoom) []wsMatchPlayer {
	players := make([]wsMatchPlayer, 0, room.humanCount)
	for slot := 0; slot < roomSlots; slot++ {
		player := room.players[slot]
		if player == nil {
			continue
		}
		players = append(players, wsMatchPlayer{
			ID:           player.id,
			Name:         player.name,
			Class:        clampClass(player.class),
			Team:         slot / 3,
			Slot:         slot,
			MaxHP:        player.maxHP,
			HP:           player.hp,
			AttackDamage: player.attackDamage,
		})
	}
	return players
}

func maxInt64(a int64, b int64) int64 {
	if a > b {
		return a
	}
	return b
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
		case "bot_damage":
			c.hub.handleBotDamage(c, message)
		case "shell_state":
			c.hub.relayShellState(c, message)
		case "shell_attack":
			c.hub.handleShellAttack(c, message)
		case "world_damage":
			c.hub.handleWorldDamage(c, message)
		case "coin_pickup":
			c.hub.handleCoinPickup(c, message)
		case "buy_item":
			c.hub.handleBuyItem(c, message)
		case "crystal_pickup":
			c.hub.handleCrystalPickup(c, message)
		case "crystal_deliver":
			c.hub.handleCrystalDeliver(c, message)
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
		if c.conn != nil {
			_ = c.conn.Close()
		}
	})
}

func finite(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0) && math.Abs(value) < 1e7
}

// The arena is roughly 80x60; clamp every server-owned drop/respawn point so
// a broken or hostile client cannot park the shard out of reach.
func clampArenaX(value float64) float64 {
	return math.Max(-100, math.Min(100, value))
}

func clampArenaZ(value float64) float64 {
	return math.Max(-100, math.Min(100, value))
}
