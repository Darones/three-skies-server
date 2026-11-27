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
	// wsCriticalSendWait bounds how long a critical message (match_finished)
	// waits for room in a congested send buffer before the socket is closed.
	wsCriticalSendWait = 1 * time.Second

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
var classBaseDamage = []float64{44.0, 39.0, 60.0}
var classAttackRange = []float64{3.5, 9.0, 11.0}

// mageUltDamageCap is the hard ceiling for one lightning-storm tick. The client
// rolls 70 x 0.75-1.25 x 2 outgoing (105-175) and doubles a 10% crit
// (210-350), then clips the crit to 250; the server must allow exactly that and
// nothing above it. Regular attacks are untouched.
const mageUltDamageCap = 250.0

// Bot difficulty profiles mirror HeroUnit.BOT_PROFILES on the client. The
// server owns bot HP and validates damage, so the same multipliers must be
// applied here or bot_states would pull the client HP back to another value.
type botProfile struct {
	damage          float64
	hp              float64
	attackInterval  float64
	abilityCooldown float64
	aggressionMin   float64
	aggressionMax   float64
}

var botProfiles = map[string]botProfile{
	"easy": {
		damage: 0.6, hp: 0.8, attackInterval: 1.35, abilityCooldown: 1.5,
		aggressionMin: 0.2, aggressionMax: 0.5,
	},
	"normal": {
		damage: 0.8, hp: 1.0, attackInterval: 1.15, abilityCooldown: 1.2,
		aggressionMin: 0.2, aggressionMax: 1.0,
	},
	"hard": {
		damage: 1.0, hp: 1.1, attackInterval: 1.0, abilityCooldown: 1.0,
		aggressionMin: 0.6, aggressionMax: 1.0,
	},
}

func botProfileFor(difficulty string) botProfile {
	if profile, ok := botProfiles[difficulty]; ok {
		return profile
	}
	return botProfiles["normal"]
}

func botDifficultyForRoom(room *wsRoom) string {
	if room == nil || !room.novice {
		return "normal"
	}
	minMatches := 1 << 30
	humans := 0
	for _, player := range room.players {
		if player == nil {
			continue
		}
		humans++
		if player.matchesPlayed < minMatches {
			minMatches = player.matchesPlayed
		}
	}
	if humans == 0 || minMatches >= 8 {
		return "normal"
	}
	if minMatches <= 3 {
		return "easy"
	}
	return "normal"
}

// noviceAfterMatches only ever graduates a player; it never promotes an
// existing non-novice back into the novice pool.
func noviceAfterMatches(matches, wins int, current bool) bool {
	if matches >= 10 {
		return false
	}
	if matches >= 5 && wins*5 >= matches*4 {
		return false
	}
	return current
}

var wsUpgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	// The handshake must come from an allowed origin (same host, the public
	// host, VK/OK pages or a local test server); an empty Origin is allowed for
	// same-origin and non-browser clients.
	CheckOrigin: checkWebSocketOrigin,
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
	id            int64
	players       [roomSlots]*wsClient
	bots          [roomSlots]*wsBot
	humanCount    int
	hostID        int64
	state         string
	novice        bool
	botDifficulty string
	startsAt      time.Time
	// startedAt is when the room went live; the match result stores the real
	// duration from it for the daily quests. Zero until the match starts.
	startedAt    time.Time
	fillTimer    *time.Timer
	finishTimer  *time.Timer
	matchEndsAt  time.Time
	resultSaved  bool
	score        [2]int
	suddenDeath  bool
	lastDelivery [2]time.Time
	shell        *wsShellState
	shellDiedAt  time.Time
	shellSpawnID int64
	lastShellHit map[int64]time.Time
	crystal      *wsCrystalState
}

type wsBot struct {
	id       int64
	name     string
	class    int
	team     int
	x        float64
	y        float64
	z        float64
	rotation float64
	maxHP    float64
	// baseMaxHP is the spawn max HP, before any host-side purchase.
	baseMaxHP      float64
	hp             float64
	hpTick         int64
	attackDamage   float64
	alive          bool
	animation      string
	hasState       bool
	lastDamaged    time.Time
	lastRegen      time.Time
	deadSince      time.Time
	baseStandSince time.Time
	lastAttacks    map[string]time.Time
	castHits       map[string]map[int64]time.Time
}

type wsClient struct {
	id        int64
	conn      *websocket.Conn
	hub       *wsHub
	send      chan []byte
	done      chan struct{}
	closeOnce sync.Once

	roomID         int64
	playerID       int64
	novice         bool
	matchesPlayed  int
	name           string
	class          int
	team           int
	x              float64
	y              float64
	z              float64
	rotation       float64
	hasState       bool
	joined         bool
	alive          bool
	maxHP          float64
	hp             float64
	hpTick         int64
	attackDamage   float64
	lastAttacks    map[string]time.Time
	lastSync       time.Time
	lastDamaged    time.Time
	lastRegen      time.Time
	baseStandSince time.Time
	lastStatGain   time.Time
	statHpBudget   float64
	healTokens     float64
	lastHeal       time.Time
	diedAt         time.Time
	castHits       map[string]map[int64]time.Time
	gold           int
	bought         map[string]bool
	coinTokens     float64
	lastCoin       time.Time

	// Per-match daily-quest counters. They are written only inside the
	// existing validated event branches (confirmed damage/death, shard
	// delivery, shell death, shop) and read once when the result is saved.
	// No combat formula, HP value or reward reads them.
	killsDealt        int
	deaths            int
	damageDealt       float64
	crystalsDelivered int
	shellsDestroyed   int
	shopItems         int
	durationSec       int
	classKey          string
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
	Stun         float64         `json:"stun"`
	Regen        float64         `json:"regen"`
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
	Tick         int64   `json:"tick,omitempty"`
}

type wsShellState struct {
	Alive   bool    `json:"alive"`
	HP      float64 `json:"hp,omitempty"`
	MaxHP   float64 `json:"max_hp,omitempty"`
	X       float64 `json:"x"`
	Y       float64 `json:"y"`
	Z       float64 `json:"z"`
	Phase   string  `json:"phase,omitempty"`
	Timer   float64 `json:"timer,omitempty"`
	SpawnID int64   `json:"spawn_id,omitempty"`
}

type wsCrystalState struct {
	State        string    `json:"state"`
	X            float64   `json:"x"`
	Y            float64   `json:"y"`
	Z            float64   `json:"z"`
	CarrierID    int64     `json:"carrier_id,omitempty"`
	GroundSince  time.Time `json:"-"`
	CarriedSince time.Time `json:"-"`
}

type matchResultPlayer struct {
	playerID int64
	team     int
	// Counters below come from the validated match events only. They are
	// stored in `matches` and feed applyQuestProgress.
	kills       int
	deaths      int
	damage      int
	crystals    int
	shells      int
	shopItems   int
	durationSec int
	classKey    string
}

// matchStats is the per-player input of applyQuestProgress (quests.go). The
// only way to build it is from a saved match result, so a quest can never move
// on a client-reported number.
type matchStats struct {
	kills       int
	deaths      int
	damage      int
	crystals    int
	shells      int
	shopItems   int
	durationSec int
	classKey    string
	won         bool
}

// stats converts one saved match result into quest progress input. won is the
// server's own comparison of the player's team with the winning team.
func (player matchResultPlayer) stats(won bool) matchStats {
	return matchStats{
		kills:       player.kills,
		deaths:      player.deaths,
		damage:      player.damage,
		crystals:    player.crystals,
		shells:      player.shells,
		shopItems:   player.shopItems,
		durationSec: player.durationSec,
		classKey:    player.classKey,
		won:         won,
	}
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
	Type            string          `json:"type"`
	ID              int64           `json:"id,omitempty"`
	RoomID          int64           `json:"room_id,omitempty"`
	HostID          int64           `json:"host_id,omitempty"`
	Name            string          `json:"name,omitempty"`
	Class           int             `json:"class"`
	Team            int             `json:"team"`
	Slot            int             `json:"slot,omitempty"`
	X               float64         `json:"x"`
	Y               float64         `json:"y"`
	Z               float64         `json:"z"`
	Rotation        float64         `json:"rotation"`
	TargetID        int64           `json:"target_id,omitempty"`
	SourceID        int64           `json:"source_id,omitempty"`
	AttackType      string          `json:"attack_type,omitempty"`
	Skill           string          `json:"skill,omitempty"`
	Crit            bool            `json:"crit,omitempty"`
	Amount          float64         `json:"amount,omitempty"`
	MaxHP           float64         `json:"max_hp,omitempty"`
	HP              float64         `json:"hp,omitempty"`
	Alive           bool            `json:"alive"`
	AttackDamage    float64         `json:"attack_damage,omitempty"`
	WinningTeam     int             `json:"winning_team,omitempty"`
	MatchPlayers    []wsMatchPlayer `json:"match_players,omitempty"`
	BotDifficulty   string          `json:"bot_difficulty,omitempty"`
	StartsInMS      int64           `json:"starts_in_ms,omitempty"`
	MatchTimeLeftMS int64           `json:"match_time_left_ms,omitempty"`
	Bots            []wsBotSnapshot `json:"bots,omitempty"`
	Shell           *wsShellState   `json:"shell,omitempty"`
	Crystal         *wsCrystalState `json:"crystal,omitempty"`
	ShellSpawnID    int64           `json:"shell_spawn_id,omitempty"`
	Protocol        int             `json:"protocol,omitempty"`
	Score0          int             `json:"score_0,omitempty"`
	Score1          int             `json:"score_1,omitempty"`
	SuddenDeath     bool            `json:"sudden_death,omitempty"`
	Event           string          `json:"event,omitempty"`
	Reason          string          `json:"reason,omitempty"`
	Error           string          `json:"error,omitempty"`
	Gold            int             `json:"gold,omitempty"`
	ItemID          string          `json:"item_id,omitempty"`
	OK              bool            `json:"ok,omitempty"`
	Stun            float64         `json:"stun,omitempty"`
	// Tick is the per-entity HP revision this message was generated from.
	// State packets and damage/heal/death/respawn packets are produced by
	// different goroutines, so they can arrive swapped on the same socket.
	// The client applies HP/alive only when the revision is newer, which stops
	// a stale snapshot from undoing a confirmed hit or resurrecting a corpse.
	Tick int64 `json:"tick,omitempty"`
}

func newWebSocketHub(db *sql.DB) *wsHub {
	return &wsHub{
		clients:    make(map[int64]*wsClient),
		rooms:      make(map[int64]*wsRoom),
		nextRoomID: roomIDSeed(time.Now()),
		db:         db,
	}
}

// roomIDSeed makes room ids unique across process restarts. Matches in the
// database are keyed by room_id; a counter that restarts at 1 would let
// /match_reward claim an unrelated old match row. Microsecond time shifted by
// 2 bits stays below JavaScript's 2^53 exact-integer limit (~7.2e15 in 2026)
// and still leaves four ids per microsecond.
func roomIDSeed(now time.Time) int64 {
	const jsSafeMask = int64(1)<<53 - 1
	seed := (now.UnixMicro() << 2) & jsSafeMask
	if seed <= 0 {
		return 1
	}
	return seed
}

func (h *wsHub) liveMatchCount() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	count := 0
	for _, room := range h.rooms {
		if room != nil && room.state == "live" {
			count++
		}
	}
	return count
}

func (h *wsHub) connectedClientCount() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.clients)
}

// finishLiveMatches ends every live room with the current score and saves the
// result before the container goes down. A deploy used to cut a match and the
// player saw "МАТЧ ПРЕРВАН"; this turns a controlled restart into a normal
// result.
func (h *wsHub) finishLiveMatches(reason string) {
	type finishedRoom struct {
		roomID  int64
		players []matchResultPlayer
		score0  int
		score1  int
		winner  int
	}
	results := make([]finishedRoom, 0, 4)
	h.mu.Lock()
	for _, room := range h.rooms {
		if room == nil || room.state != "live" {
			continue
		}
		score0, score1 := room.score[0], room.score[1]
		winner := 0
		if score1 > score0 {
			winner = 1
		} else if score0 == score1 {
			winner = int(time.Now().UnixNano() % 2)
		}
		players := h.finishMatchLocked(room)
		results = append(results, finishedRoom{
			roomID: room.id, players: players, score0: score0, score1: score1, winner: winner,
		})
	}
	h.mu.Unlock()
	for _, result := range results {
		h.saveMatch(result.roomID, result.players, result.winner)
		h.broadcastRoom(result.roomID, 0, wsOutgoing{
			Type:        "match_score",
			RoomID:      result.roomID,
			Score0:      result.score0,
			Score1:      result.score1,
			SuddenDeath: false,
		})
		h.broadcastRoomCritical(result.roomID, 0, wsOutgoing{
			Type:        "match_finished",
			RoomID:      result.roomID,
			WinningTeam: result.winner,
			Score0:      result.score0,
			Score1:      result.score1,
			Reason:      reason,
		})
		log.Printf("match finished on shutdown room=%d score=%d:%d winner=%d", result.roomID, result.score0, result.score1, result.winner)
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
	var shellReset *wsOutgoing
	h.mu.Lock()
	delete(h.clients, client.id)
	room := h.rooms[client.roomID]
	if room != nil {
		slot := roomSlotOf(room, client)
		if slot >= 0 {
			if room.state == "live" {
				room.bots[slot] = botFromClient(room.id, client, slot)
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
				// A new host starts its local shell_spawn_id from 0/1. Reset the
				// server counter on every host change, even when the old shell is
				// already dead; otherwise the new host's first spawn is treated
				// as a stale packet and the shell never appears.
				room.shellSpawnID = 0
				// The guest copy of the shell cannot simulate strikes. Reset it
				// so the new host spawns a fresh local shell instead of the old
				// remote one standing idle for two minutes.
				if room.state == "live" && room.shell != nil && room.shell.Alive {
					room.shell.Alive = false
					room.shell.HP = 0
					room.shellDiedAt = time.Now()
					s := *room.shell
					shellReset = &wsOutgoing{Type: "shell_state", RoomID: room.id, Shell: &s}
				}
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
		if shellReset != nil {
			h.broadcastRoom(roomID, 0, *shellReset)
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

// botNickname is the single server-side name for every bot. The suffix depends
// only on the room and the slot, so one bot keeps exactly one name for the whole
// match: match_start, bot_roster, the kill feed and the results all read it from
// the same field. The client used to replace server names that began with
// "Игрок" with its own random callsign, so the host and every guest saw a
// different bot name in the kill feed; a "БОТ %04d" name is used verbatim.
func botNickname(roomID int64, slot int) string {
	suffix := (roomID*37 + int64(slot)*211) % 9000
	if suffix < 0 {
		suffix = -suffix
	}
	return fmt.Sprintf("БОТ %04d", 1000+suffix)
}

// botFromClient turns a disconnected player's slot into a bot. A real nickname
// is kept (the ally keeps its identity), but a generated "Игрок N" placeholder
// is never carried into the bot world: bots always use botNickname, so the
// client cannot swap the name for a callsign of its own.
func botFromClient(roomID int64, client *wsClient, slot int) *wsBot {
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
	name := strings.TrimSpace(client.name)
	if name == "" || strings.HasPrefix(name, "Игрок ") {
		name = botNickname(roomID, slot)
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
		baseMaxHP:    maxHP,
		hp:           hp,
		attackDamage: damage,
		alive:        alive,
		deadSince:    deadSince,
		hasState:     true,
		lastAttacks:  make(map[string]time.Time),
	}
}

func (h *wsHub) playerNovice(playerID int64) (bool, int) {
	if h.db == nil || playerID <= 0 {
		return false, 0
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	var novice bool
	var matchesPlayed int
	err := h.db.QueryRowContext(ctx,
		`SELECT COALESCE(novice, FALSE), COALESCE(matches_played, 0) FROM players WHERE id = $1`,
		playerID,
	).Scan(&novice, &matchesPlayed)
	if err != nil {
		// A database hiccup must not block matchmaking; the normal pool is
		// the safe fallback for a profile we cannot read.
		return false, 0
	}
	return novice, matchesPlayed
}

// playerMatchAccess is the moderation state a join needs: whether the account
// is banned, and whether its nickname must be replaced with a safe one.
type playerMatchAccess struct {
	Nickname  string
	Hidden    bool
	Banned    bool
	BanReason string
}

// playerMatchAccess reads the ban and hidden-nickname flags once per join.
// A database error is treated as "no moderation flags": a hiccup must not lock
// every player out, and the ban is re-checked on the next profile/session.
func (h *wsHub) playerMatchAccess(playerID int64) playerMatchAccess {
	if h.db == nil || playerID <= 0 {
		return playerMatchAccess{}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	var access playerMatchAccess
	if err := h.db.QueryRowContext(ctx,
		`SELECT COALESCE(nickname, ''), COALESCE(nickname_hidden, FALSE),
		        COALESCE(banned, FALSE), COALESCE(ban_reason, '')
		 FROM players WHERE id = $1`, playerID,
	).Scan(&access.Nickname, &access.Hidden, &access.Banned, &access.BanReason); err != nil {
		return playerMatchAccess{}
	}
	return access
}

// visibleJoinName picks the name that goes into lobby_state and match_start.
// A hidden nickname is replaced even if the client sends the original, and a
// readable server profile overrides a client-supplied name.
func visibleJoinName(requested string, access playerMatchAccess, clientID int64) string {
	name := strings.TrimSpace(requested)
	if access.Hidden {
		name = hiddenNickname
	} else if strings.TrimSpace(access.Nickname) != "" {
		name = strings.TrimSpace(access.Nickname)
	}
	if name == "" {
		name = fmt.Sprintf("Игрок %d", clientID)
	}
	runes := []rune(name)
	if len(runes) > 32 {
		name = string(runes[:32])
	}
	return name
}

func (h *wsHub) sessionAllowed(playerID int64, token string) bool {
	if playerID <= 0 {
		// A guest (player_id 0) never joins an online match: guests may only
		// play the offline tutorial. Without a profile there is nothing to
		// authenticate, so this is a hard rejection rather than a token check.
		return false
	}
	if h.db == nil {
		// Server-only/test mode: there is no database to verify tokens against,
		// so a positive profile id is the strongest check available.
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
		// No legacy bypass: an account without a token cannot join a match.
		// Such profiles are restored manually, after which they have a token.
		return false
	}
	return strings.TrimSpace(token) == stored
}

func (h *wsHub) joinMatchmaking(client *wsClient, message wsIncoming) {
	class := resolveClass(message)
	if class < 0 {
		return
	}
	if !h.sessionAllowed(message.PlayerID, message.Token) {
		client.sendJSON(wsOutgoing{Type: "error", Error: "invalid_session"})
		return
	}
	access := h.playerMatchAccess(message.PlayerID)
	if access.Banned {
		// A banned account never enters a room. The distinct code and reason
		// let the client show the ban screen instead of retrying.
		client.sendJSON(wsOutgoing{
			Type:   "error",
			Error:  accountBannedError,
			Reason: access.BanReason,
		})
		return
	}
	name := visibleJoinName(message.Name, access, client.id)
	novice, matchesPlayed := h.playerNovice(message.PlayerID)

	h.mu.Lock()
	if client.roomID != 0 {
		h.mu.Unlock()
		return
	}
	room, slot := h.findRoomLocked(class, novice)
	if room == nil {
		h.nextRoomID++
		room = &wsRoom{id: h.nextRoomID, state: "waiting", novice: novice}
		h.rooms[room.id] = room
		slot = 0
	}
	client.roomID = room.id
	client.playerID = message.PlayerID
	client.novice = novice
	client.matchesPlayed = matchesPlayed
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

func (h *wsHub) findRoomLocked(_ int, novice bool) (*wsRoom, int) {
	var best *wsRoom
	for _, room := range h.rooms {
		if room.state != "waiting" || room.humanCount >= roomSlots {
			continue
		}
		// Novices and experienced players never share a room: the whole point
		// of the first-ten-matches pool is that a new player does not meet a
		// veteran while still learning the shell and the shard.
		if room.novice != novice {
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

// resetQuestCounters clears the per-match daily-quest counters when a match
// starts, so a second match in the same room never inherits the first one.
// Nothing else is touched: HP, gold and purchases are reset by their own lines.
func (client *wsClient) resetQuestCounters() {
	client.killsDealt = 0
	client.deaths = 0
	client.damageDealt = 0
	client.crystalsDelivered = 0
	client.shellsDestroyed = 0
	client.shopItems = 0
	client.durationSec = 0
	client.classKey = ""
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
	room.botDifficulty = botDifficultyForRoom(room)
	botProfile := botProfileFor(room.botDifficulty)
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
			player.resetQuestCounters()
			player.maxHP, player.attackDamage = statsForClient(player)
			if player.hp <= 0 || player.hp > player.maxHP {
				player.hp = player.maxHP
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
		botName := botNickname(room.id, slot)
		botZ := 27.5
		botRotation := 0.0
		if team == 1 {
			botZ = -27.5
			botRotation = math.Pi
		}
		botMaxHP := classBaseHP[class] * botProfile.hp
		botDamage := classBaseDamage[class] * botProfile.damage
		room.bots[slot] = &wsBot{
			id:           botID,
			name:         botName,
			class:        class,
			team:         team,
			x:            float64((slot%3)-1) * 2.0,
			y:            0.76,
			z:            botZ,
			rotation:     botRotation,
			maxHP:        botMaxHP,
			baseMaxHP:    botMaxHP,
			hp:           botMaxHP,
			attackDamage: botDamage,
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
			MaxHP:        botMaxHP,
			HP:           botMaxHP,
			AttackDamage: botDamage,
		})
	}
	if room.finishTimer != nil {
		room.finishTimer.Stop()
	}
	roomID := room.id
	room.finishTimer = time.AfterFunc(matchLength, func() { h.finishMatchByTimeout(roomID) })
	room.startedAt = time.Now()
	room.matchEndsAt = room.startedAt.Add(matchLength)
	return wsOutgoing{
		Type:            "match_start",
		RoomID:          room.id,
		HostID:          room.hostID,
		MatchPlayers:    players,
		BotDifficulty:   room.botDifficulty,
		MatchTimeLeftMS: maxInt64(0, time.Until(room.matchEndsAt).Milliseconds()),
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
		if elapsed > 0.0 {
			if elapsed > 1.0 {
				// A short packet gap must not delete the regen for the whole
				// period: cap the step but keep healing.
				elapsed = 1.0
			}
			rate := 10.0
			if client.bought != nil && client.bought["revival_talisman"] {
				rate += 10.0
			}
			// The client owns bush stealth and the mage blessing, so it sends
			// the effective regen multiplier. Without it the server healed at
			// 10 HP/s while the player's bar showed 20-40 HP/s and every 1 Hz
			// sync pulled it back down.
			regenMultiplier := 1.0
			if finite(message.Regen) && message.Regen > 1.0 {
				regenMultiplier = math.Min(message.Regen, 4.0)
			}
			baseZ := 28.0
			if client.team == 1 {
				baseZ = -28.0
			}
			if math.Hypot(client.x, client.z-baseZ) <= 6.5 {
				// Base: 100 HP/s after three seconds of standing. Damage
				// resets the timer; leaving the base resets it to zero.
				if client.baseStandSince.IsZero() {
					client.baseStandSince = now
				}
				if now.Sub(client.baseStandSince) >= 3*time.Second {
					client.hp = math.Min(client.maxHP, client.hp+100.0*elapsed)
				}
			} else {
				client.baseStandSince = time.Time{}
				if client.lastDamaged.IsZero() || now.Sub(client.lastDamaged) >= 5*time.Second {
					client.hp = math.Min(client.maxHP, client.hp+rate*regenMultiplier*elapsed)
				}
			}
		}
		client.lastRegen = now
	}
	targets := roomClientsLocked(room, client.id)
	syncDue := time.Since(client.lastSync) >= time.Second
	if syncDue {
		client.lastSync = time.Now()
	}
	// A fresh state sample is a new HP revision: every state packet is a
	// complete snapshot, so a client that has already applied a newer sample
	// must not be dragged back by an older one in flight.
	stateTick := bumpHPTick(&client.hpTick)
	syncTick := int64(0)
	if syncDue {
		syncTick = bumpHPTick(&client.hpTick)
	}
	syncMessage := wsOutgoing{
		Type:            "sync",
		ID:              client.id,
		RoomID:          room.id,
		HP:              client.hp,
		MaxHP:           client.maxHP,
		Alive:           client.alive,
		Tick:            syncTick,
		Score0:          room.score[0],
		Score1:          room.score[1],
		SuddenDeath:     room.suddenDeath,
		MatchTimeLeftMS: maxInt64(0, time.Until(room.matchEndsAt).Milliseconds()),
	}
	var crystalMoved *wsCrystalState
	if room.crystal != nil && room.crystal.State == "ground" && !room.crystal.GroundSince.IsZero() && now.Sub(room.crystal.GroundSince) >= 30*time.Second {
		// A dropped shard must never stall the match: after 30 s it returns to
		// the altar and disappears, so the next shell can spawn.
		room.crystal.State = "none"
		room.crystal.CarrierID = 0
		room.crystal.X = 0
		room.crystal.Y = 0.5
		room.crystal.Z = 0
		room.crystal.GroundSince = time.Time{}
		room.crystal.CarriedSince = time.Time{}
		c := *room.crystal
		crystalMoved = &c
	}
	if room.crystal != nil && room.crystal.State == "carried" && !room.crystal.CarriedSince.IsZero() && now.Sub(room.crystal.CarriedSince) >= 45*time.Second {
		// A carried shard used to have no timeout: if the carrier stalled (lag,
		// disconnect race, bot stuck) every later shell spawn was rejected and
		// the match lost its shard. Drop it where the carrier stands.
		if carrier := findRoomPlayerLocked(room, room.crystal.CarrierID); carrier != nil && carrier.hasState {
			room.crystal.X = clampArenaX(carrier.x)
			room.crystal.Z = clampArenaZ(carrier.z)
		}
		room.crystal.State = "ground"
		room.crystal.CarrierID = 0
		room.crystal.Y = 0.5
		room.crystal.GroundSince = now
		room.crystal.CarriedSince = time.Time{}
		c := *room.crystal
		crystalMoved = &c
	}
	stateX, stateY, stateZ, stateRot := client.x, client.y, client.z, client.rotation
	stateHP, stateMaxHP, stateAlive := client.hp, client.maxHP, client.alive
	roomID := room.id
	// A dropped crystal_state has no other repair path: the shard would stay
	// on the ground (or on a corpse) for every later client until the next
	// pickup/drop. The 1 Hz sync carries a cheap heartbeat as well.
	var crystalHeartbeat *wsCrystalState
	if syncDue && room.crystal != nil {
		c := *room.crystal
		crystalHeartbeat = &c
	}
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
		Tick:     stateTick,
	})
	if syncDue {
		client.sendJSON(syncMessage)
	}
	if crystalHeartbeat != nil {
		// A distinct type: this is a repair snapshot, not a pickup/deliver
		// event, so event-only handlers keep their existing behaviour.
		client.sendJSON(wsOutgoing{
			Type:    "crystal_sync",
			RoomID:  roomID,
			Crystal: crystalHeartbeat,
		})
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
	// Combat stats are derived from the class and bought items; the packet's
	// values are ignored. The client's HP is not raised from this packet.
	client.maxHP, client.attackDamage = statsForClient(client)
	if client.hp > client.maxHP {
		client.hp = client.maxHP
	}
	hp = client.hp
	maxHP := client.maxHP
	attackDamage := client.attackDamage
	tick := bumpHPTick(&client.hpTick)
	targets := roomClientsLocked(room, client.id)
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
		Type:         "stats",
		ID:           client.id,
		MaxHP:        maxHP,
		HP:           hp,
		AttackDamage: attackDamage,
		Tick:         tick,
	})
}

func (h *wsHub) relayHeal(client *wsClient, message wsIncoming) {
	if message.TargetID == 0 || !finite(message.Amount) || message.Amount <= 0 {
		return
	}
	amount := math.Min(message.Amount, 300)
	h.mu.Lock()
	room := h.rooms[client.roomID]
	if room == nil || room.state != "live" || !client.alive {
		h.mu.Unlock()
		return
	}
	// A dead healer used to keep allies immortal, and an unlimited packet rate
	// meant infinite healing. An AoE heal sends one packet per ally, so allow a
	// burst of 8 and refill 2 tokens per second.
	now := time.Now()
	if client.lastHeal.IsZero() {
		client.healTokens = 8.0
	} else {
		client.healTokens = math.Min(8.0, client.healTokens+now.Sub(client.lastHeal).Seconds()*2.0)
	}
	client.lastHeal = now
	if client.healTokens < 1.0 {
		h.mu.Unlock()
		return
	}
	client.healTokens -= 1.0
	var targetID int64
	var targetTick int64
	applied := 0.0
	if target := findRoomPlayerLocked(room, message.TargetID); target != nil {
		if !target.alive || target.team != client.team || target.maxHP <= 0 {
			h.mu.Unlock()
			return
		}
		before := target.hp
		target.hp = math.Min(target.maxHP, target.hp+amount)
		applied = target.hp - before
		targetID = target.id
		targetTick = bumpHPTick(&target.hpTick)
	} else if bot := findRoomBotLocked(room, message.TargetID); bot != nil {
		if !bot.alive || bot.team != client.team {
			h.mu.Unlock()
			return
		}
		before := bot.hp
		bot.hp = math.Min(bot.maxHP, bot.hp+amount)
		applied = bot.hp - before
		targetID = bot.id
		targetTick = bumpHPTick(&bot.hpTick)
	} else {
		h.mu.Unlock()
		return
	}
	if applied <= 0 {
		// Full HP already: don't send a +0 number or a fake heal. Refund the
		// token so a heal that raced a regen tick does not waste a cast.
		client.healTokens = math.Min(8.0, client.healTokens+1.0)
		h.mu.Unlock()
		return
	}
	// Include the healer: self-heal was applied only on the server, so the
	// local HP bar waited for the next 1 Hz sync and showed no +N at all.
	targets := roomClientsLocked(room, 0)
	roomID := room.id
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{
		Type:     "heal",
		ID:       client.id,
		RoomID:   roomID,
		SourceID: client.id,
		TargetID: targetID,
		Amount:   applied,
		Tick:     targetTick,
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
	tick := bumpHPTick(&client.hpTick)
	crystal := h.dropCrystalForLocked(room, client.id, client.x, client.z)
	targets := roomClientsLocked(room, client.id)
	roomID := room.id
	h.mu.Unlock()
	h.sendToClients(targets, wsOutgoing{Type: "death", ID: client.id, RoomID: roomID, Tick: tick})
	if crystal != nil {
		h.broadcastRoom(roomID, 0, wsOutgoing{Type: "crystal_state", RoomID: roomID, Crystal: crystal})
	}
}

// Respawn timing is a client rule: scripts/game.gd respawn_delay_for waits
// 15 s plus 8 s scaled by the gold earned in the match (clamped to 2000), so a
// rich player waits longer. The server mirrors the same curve using the wallet,
// which is never larger than the gold the client has earned, so the gate can
// only ever be less strict than the client's own timer; it exists to reject a
// packet that arrived before any legal timer could finish.
const (
	respawnBaseDelay = 15.0
	respawnGoldBonus = 8.0
	respawnGoldScale = 2000.0
	// respawnDelaySlack absorbs the death packet's travel time (the client's
	// timer starts before the server sees the death) so a legitimate respawn is
	// never dropped, which would leave the hero dead on every other screen.
	respawnDelaySlack = 1 * time.Second
)

func respawnDelayFor(gold int) time.Duration {
	ratio := 0.0
	if gold > 0 {
		ratio = math.Min(float64(gold)/respawnGoldScale, 1.0)
	}
	return time.Duration((respawnBaseDelay + respawnGoldBonus*ratio) * float64(time.Second))
}

// botLifeAmuletMaxHP is the max HP a life amulet adds on the client. A bot whose
// max HP grew by that much spent 400 gold, which is the only bot purchase the
// server can observe.
const botLifeAmuletMaxHP = 150.0

// botRespawnDelayFor estimates how long the host keeps a dead bot down. Bots
// keep their own wallet on the host, and bot_states carries no gold, so the
// server cannot read "gold earned"; it uses the same 15 s + 8 s curve as the
// client with a deliberate lower bound:
//   - no visible purchase: 0 gold, i.e. the 15 s floor of the curve;
//   - a life amulet in the bot's max HP: at least the 400 gold it cost (16.6 s).
//
// Guessing low is the safe direction. The restore below also waits for the
// host's alive flag, so an estimate below the host's own timer can never wake a
// bot the host still keeps dead; an estimate above it would leave the bot
// frozen (untargetable, unable to attack) until the server caught up.
func botRespawnDelayFor(bot *wsBot) time.Duration {
	if bot == nil {
		return respawnDelayFor(0)
	}
	earned := 0
	if bot.maxHP >= bot.baseMaxHP+botLifeAmuletMaxHP-0.5 {
		earned = matchItemPrices["life_amulet"]
	}
	return respawnDelayFor(earned)
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
	// The client owns the respawn timer (15 s + 8 s scaled by gold, see
	// respawnDelayFor). The server still refuses a respawn that arrives sooner
	// than that timer could have finished, so a modified client cannot skip the
	// wait. The slack covers the death packet's travel time: the client starts
	// its timer the moment it dies, the server starts counting when the packet
	// arrives.
	if client.diedAt.IsZero() || deadFor < respawnDelayFor(client.gold)-respawnDelaySlack {
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
	tick := bumpHPTick(&client.hpTick)
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
		Tick:     tick,
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
		// Every snapshot below is a fresh HP sample for this bot, so give it
		// a new revision; a snapshot created before a confirmed hit must lose
		// against the hit's revision on the client.
		bumpHPTick(&bot.hpTick)
		// The host owns bot shop purchases. When a bot buys "+150 max HP",
		// accept the new maximum (with a cap) and mirror the heal, otherwise
		// the next server snapshot pulled the bot back to its old max HP.
		if finite(state.MaxHP) && state.MaxHP > bot.maxHP {
			class := clampClass(bot.class)
			maxAllowed := classBaseHP[class] * 1.6
			if state.MaxHP <= maxAllowed {
				delta := state.MaxHP - bot.maxHP
				bot.maxHP = state.MaxHP
				if bot.alive {
					bot.hp = math.Min(bot.maxHP, bot.hp+delta)
				}
			}
		}
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
			if elapsed > 0.0 {
				if elapsed > 1.0 {
					elapsed = 1.0
				}
				baseZ := 28.0
				if bot.team == 1 {
					baseZ = -28.0
				}
				if math.Hypot(bot.x, bot.z-baseZ) <= 6.5 {
					if bot.baseStandSince.IsZero() {
						bot.baseStandSince = now
					}
					if now.Sub(bot.baseStandSince) >= 3*time.Second {
						bot.hp = math.Min(bot.maxHP, bot.hp+100.0*elapsed)
					}
				} else {
					bot.baseStandSince = time.Time{}
					if bot.lastDamaged.IsZero() || now.Sub(bot.lastDamaged) >= 5*time.Second {
						bot.hp = math.Min(bot.maxHP, bot.hp+10.0*elapsed)
					}
				}
			}
			bot.lastRegen = now
		}
		if !bot.alive && state.Alive && !bot.deadSince.IsZero() && now.Sub(bot.deadSince) >= botRespawnDelayFor(bot) {
			// The host's respawn timer won. The server restores the bot and
			// broadcasts the new HP to every client. The gate matches the
			// client's 15-23 s curve: a flat 1.5 s here used to race the host,
			// so the server declared the bot alive while the host still had it
			// dead (and re-killed it on the next snapshot).
			bot.hp = bot.maxHP
			bot.alive = true
			bot.deadSince = time.Time{}
			bot.baseStandSince = now
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
	baseZ := 28.0
	if team == 1 {
		baseZ = -28.0
	}
	return math.Hypot(x, z-baseZ) <= 4.9
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
	base := calculateDamageFor(source.attackDamage, source.class, skill)
	// The client sends its rolled hit (crit/buffs); the offline hit is ×2
	// outgoing. There is no 400 floor: any class used to send 400 per packet.
	damage := base * 2.0
	if finite(message.Amount) && message.Amount > 0 {
		cap := math.Max(base*2.0*2.6, 1.0)
		damage = math.Min(message.Amount, cap)
		damage = math.Round(damage*100) / 100
	}
	// The storm has its own ceiling: a forged 800-damage crit tick must not
	// pass even though the generic 2.6x roll cap would allow ~284.
	if skill == "ult_lightning_storm" && damage > mageUltDamageCap {
		damage = mageUltDamageCap
	}
	if target.client != nil {
		damage *= 1.0 - damageReductionFor(target.client)
	}
	stun := stunForSkill(skill)
	hpBefore := target.hp
	died := target.applyDamage(damage)
	// Daily quests count the damage the server actually applied: an overkill
	// hit cannot inflate the metric, and only a validated hit reaches here.
	if source.client != nil && damage > 0 {
		applied := math.Min(damage, math.Max(0, hpBefore))
		source.client.damageDealt += applied
	}
	if died && target.client != nil {
		target.client.deaths++
	}
	targetTick := int64(0)
	if target.client != nil {
		target.client.lastDamaged = time.Now()
		target.client.baseStandSince = time.Time{}
		targetTick = bumpHPTick(&target.client.hpTick)
	}
	if target.bot != nil {
		target.bot.lastDamaged = time.Now()
		target.bot.baseStandSince = time.Time{}
		targetTick = bumpHPTick(&target.bot.hpTick)
	}
	// Lifesteal is a server rule too: 15% of the confirmed hit returns as HP.
	var stealHeal float64
	stealTick := int64(0)
	if damage > 0 && source.client != nil && source.client.bought != nil && source.client.bought["vampire_fang"] {
		stealHeal = math.Min(damage*0.15, source.client.maxHP-source.client.hp)
		if stealHeal > 0 {
			source.client.hp += stealHeal
			stealTick = bumpHPTick(&source.client.hpTick)
		}
	}
	if died && source.client != nil {
		source.client.gold += 50
		source.client.killsDealt++
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
		Stun:     stun,
		Amount:   damage,
		Tick:     targetTick,
	})
	if stealHeal > 0 {
		h.broadcastRoom(roomID, 0, wsOutgoing{
			Type:     "heal",
			ID:       sourceID,
			RoomID:   roomID,
			SourceID: sourceID,
			TargetID: sourceID,
			Amount:   stealHeal,
			Tick:     stealTick,
		})
	}
	if died {
		h.broadcastRoom(roomID, 0, wsOutgoing{Type: "death", ID: targetID, RoomID: roomID, SourceID: sourceID, Tick: targetTick})
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
		room.shell = &wsShellState{}
	}
	if !finite(state.X) || !finite(state.Y) || !finite(state.Z) {
		h.mu.Unlock()
		return
	}
	state.X = clampArenaX(state.X)
	state.Z = clampArenaZ(state.Z)
	if state.Alive && !room.shell.Alive {
		// A stale "alive" packet sent before the host learned about the death
		// must not resurrect the old shell. SpawnID lets a genuinely new shell
		// start even immediately after a death; without it fall back to the
		// old 2 s guard.
		stale := false
		if state.SpawnID > 0 {
			stale = state.SpawnID <= room.shellSpawnID
		} else {
			stale = !room.shellDiedAt.IsZero() && time.Since(room.shellDiedAt) < 2*time.Second
		}
		if stale {
			state.Alive = false
		} else {
			if state.SpawnID > 0 {
				room.shellSpawnID = state.SpawnID
			}
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
	// Every broadcast must carry the current spawn id. The client drops
	// shell_state packets with an older id, so an echo without it left the
	// host's shell health bar frozen at full HP.
	room.shell.SpawnID = room.shellSpawnID
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
	if !finite(message.Amount) || message.Amount <= 0 {
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
	// The shell is a PvE object; keep the legacy 800 cap so the shell kill
	// timing is unchanged. The PvP damage cap is enforced in handleAttackIntent.
	damage := math.Min(message.Amount, 800.0)
	room.shell.HP = math.Max(0, room.shell.HP-damage)
	died := room.shell.HP <= 0
	if died {
		room.shell.Alive = false
	}
	shell := *room.shell
	var crystal *wsCrystalState
	if died {
		room.shellDiedAt = time.Now()
		teamGoldLocked(room, source.team, 100)
		if source.client != nil {
			source.client.shellsDestroyed++
		}
		if room.crystal == nil || room.crystal.State == "none" {
			room.crystal = &wsCrystalState{State: "ground", X: shell.X, Y: 0.5, Z: shell.Z, GroundSince: time.Now()}
			c := *room.crystal
			crystal = &c
		}
	}
	roomID := room.id
	sourceID := source.id
	spawnID := room.shellSpawnID
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
		Amount:   damage,
	})
	if died {
		h.broadcastRoom(roomID, 0, wsOutgoing{
			Type:         "match_event",
			RoomID:       roomID,
			Event:        "shell_destroyed",
			Team:         source.team,
			SourceID:     sourceID,
			ShellSpawnID: spawnID,
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
	bot.baseStandSince = time.Time{}
	died := bot.hp <= 0
	if died {
		bot.alive = false
		if bot.deadSince.IsZero() {
			bot.deadSince = time.Now()
		}
	}
	tick := bumpHPTick(&bot.hpTick)
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
		Tick:     tick,
	})
	if died {
		h.broadcastRoom(roomID, 0, wsOutgoing{Type: "death", ID: targetID, RoomID: roomID, Tick: tick})
		if crystal != nil {
			h.broadcastRoom(roomID, 0, wsOutgoing{Type: "crystal_state", RoomID: roomID, Crystal: crystal})
		}
	}
}

// The host simulates the shell; its PvE damage on remote humans must go through
// the server, otherwise guests are immune to the shell (it only knows heroes).
// Match shop prices. Keep in sync with SHOP_ITEMS in scripts/game.gd:
// the client draws the price and the server validates the same amount.
var matchItemPrices = map[string]int{
	"life_amulet":      400,
	"revival_talisman": 350,
	"titan_shell":      350,
	"power_glove":      400,
	"vampire_fang":     400,
	"agility_mark":     350,
	"wind_boots":       250,
	"hourglass":        350,
	"cleansing_charm":  250,
}

// bumpHPTick returns the next revision for one entity's HP/alive state.
// Callers hold h.mu, so revisions follow the same order as the HP changes.
func bumpHPTick(tick *int64) int64 {
	*tick = *tick + 1
	return *tick
}

// The server derives combat stats from the class and the purchased items, so a
// modified client cannot declare 100000 damage or HP.
func statsForClient(client *wsClient) (float64, float64) {
	class := clampClass(client.class)
	maxHP := classBaseHP[class]
	damage := classBaseDamage[class]
	if client.bought != nil {
		if client.bought["life_amulet"] {
			maxHP += 150
		}
		if client.bought["power_glove"] {
			damage += 25
		}
	}
	return maxHP, damage
}

func damageReductionFor(client *wsClient) float64 {
	if client != nil && client.bought != nil && client.bought["titan_shell"] {
		return 0.15
	}
	return 0
}

func stunForSkill(skill string) float64 {
	switch strings.ToLower(skill) {
	case "fear_ult", "stun", "stun_shot":
		return 1.5
	case "shadow_assassin":
		return 1.0
	case "root":
		return 2.0
	case "shell":
		return 1.0
	}
	return 0
}

func (combatant *wsCombatant) cooldownFor(skill string) time.Duration {
	cooldown := attackCooldownFor(combatant.class, skill)
	if combatant.client != nil && combatant.client.bought != nil {
		if combatant.client.bought["hourglass"] {
			cooldown = time.Duration(float64(cooldown) * 0.85)
		}
		if combatant.client.bought["agility_mark"] && strings.ToLower(skill) == "auto" {
			cooldown = time.Duration(float64(cooldown) / 1.2)
		}
	}
	return cooldown
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
	client.maxHP, client.attackDamage = statsForClient(client)
	if itemID == "life_amulet" {
		client.hp = math.Min(client.maxHP, client.hp+150)
	}
	if client.hp > client.maxHP {
		client.hp = client.maxHP
	}
	maxHP, hp, attackDamage := client.maxHP, client.hp, client.attackDamage
	tick := bumpHPTick(&client.hpTick)
	targets := roomClientsLocked(room, client.id)
	h.mu.Unlock()
	client.sendJSON(wsOutgoing{Type: "shop_purchase", ItemID: itemID, OK: true, Gold: gold})
	h.sendToClients(targets, wsOutgoing{
		Type:         "stats",
		ID:           client.id,
		MaxHP:        maxHP,
		HP:           hp,
		AttackDamage: attackDamage,
		Tick:         tick,
	})
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
	if room.lastShellHit == nil {
		room.lastShellHit = make(map[int64]time.Time)
	}
	if last, ok := room.lastShellHit[target.id]; ok && time.Since(last) < 2*time.Second {
		h.mu.Unlock()
		return
	}
	room.lastShellHit[target.id] = time.Now()
	damage := message.Amount * (1.0 - damageReductionFor(target))
	stun := stunForSkill("shell")
	died := combatantFromClient(target).applyDamage(damage)
	tick := bumpHPTick(&target.hpTick)
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
		Stun:     stun,
		Amount:   damage,
		Tick:     tick,
	})
	if died {
		h.broadcastRoom(roomID, 0, wsOutgoing{Type: "death", ID: targetID, RoomID: roomID, Tick: tick})
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
	room.crystal.CarriedSince = time.Time{}
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
	room.crystal.CarriedSince = time.Now()
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
	// The carrier can be a bot (host-simulated); only a real client earns a
	// daily-quest delivery, which is why the counter lives on wsClient.
	if carrier := findRoomPlayerLocked(room, sourceID); carrier != nil {
		carrier.crystalsDelivered++
	}
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
	room.crystal.CarriedSince = time.Time{}
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
		h.broadcastRoomCritical(roomID, 0, wsOutgoing{
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
			Type:         "match_event",
			RoomID:       roomID,
			Event:        "shell_destroyed",
			Team:         team,
			ShellSpawnID: room.shellSpawnID,
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
	} else if score0 == score1 {
		// A draw after sudden death must not always favour team 0.
		winner = int(time.Now().UnixNano() % 2)
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
	h.broadcastRoomCritical(roomID, 0, wsOutgoing{
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
	durationSec := 0
	if !room.startedAt.IsZero() {
		durationSec = int(time.Since(room.startedAt).Seconds())
	}
	for index := 0; index < roomSlots; index++ {
		player := room.players[index]
		if player == nil {
			continue
		}
		playerID := player.playerID
		if playerID <= 0 {
			playerID = player.id
		}
		// The shop metric is the number of distinct items bought in this
		// match: the server owns the purchases, so the count cannot be faked.
		player.shopItems = len(player.bought)
		player.durationSec = durationSec
		player.classKey = classNames[clampClass(player.class)]
		players = append(players, matchResultPlayer{
			playerID:    playerID,
			team:        player.team,
			kills:       player.killsDealt,
			deaths:      player.deaths,
			damage:      int(math.Round(player.damageDealt)),
			crystals:    player.crystalsDelivered,
			shells:      player.shellsDestroyed,
			shopItems:   player.shopItems,
			durationSec: player.durationSec,
			classKey:    player.classKey,
		})
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
			Tick:         bot.hpTick,
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
		if elapsed < combatant.cooldownFor(skill) {
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
	if strings.ToLower(skill) == "ult_lightning_storm" {
		// The storm is one cast with 1 Hz ticks for ~5 s, then a 42 s cooldown.
		start := combatant.lastAttacks[skill]
		if !start.IsZero() && now.Sub(start) <= 6*time.Second {
			hits := combatant.castHits[skill]
			if hits == nil {
				hits = make(map[int64]time.Time)
				combatant.castHits[skill] = hits
			}
			if last, seen := hits[targetID]; seen && now.Sub(last) < 900*time.Millisecond {
				return false
			}
			hits[targetID] = now
			return true
		}
		if !start.IsZero() && now.Sub(start) < 42*time.Second {
			return false
		}
		combatant.lastAttacks[skill] = now
		combatant.castHits[skill] = map[int64]time.Time{targetID: now}
		return true
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
		if !start.IsZero() && now.Sub(start) < combatant.cooldownFor(skill) {
			return false
		}
		combatant.lastAttacks[skill] = now
		combatant.castHits[skill] = map[int64]time.Time{targetID: now}
		return true
	}
	if last, ok := combatant.lastAttacks[skill]; ok && now.Sub(last) < combatant.cooldownFor(skill) {
		return false
	}
	combatant.lastAttacks[skill] = now
	return true
}

func normalizeSkill(skill string) string {
	skill = strings.ToLower(strings.TrimSpace(skill))
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

func classAutoInterval(class int) time.Duration {
	switch class {
	case 0:
		return 600 * time.Millisecond
	case 1:
		return 1000 * time.Millisecond
	case 2:
		return 750 * time.Millisecond
	}
	return 600 * time.Millisecond
}

func attackCooldownFor(class int, skill string) time.Duration {
	switch strings.ToLower(skill) {
	case "auto":
		return classAutoInterval(class)
	case "shell":
		return classAutoInterval(class)
	case "shadow_assassin":
		return 8 * time.Second
	case "fear_ult":
		return 37500 * time.Millisecond
	case "root":
		return 10 * time.Second
	case "stun", "stun_shot":
		return 12 * time.Second
	case "crit_shot":
		return 15 * time.Second
	case "fairy_ult":
		return 36 * time.Second
	case "ult_lightning_storm":
		return 42 * time.Second
	default:
		return time.Second
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
	// A repeated finish of the same room must not pay twice: the match row is
	// the idempotency key here (the unique index is deliberately not added in
	// this wave because old rows already contain duplicates).
	inserted := make([]matchResultPlayer, 0, len(players))
	for _, player := range players {
		if player.playerID > 0 {
			var exists bool
			if err := transaction.QueryRowContext(ctx,
				`SELECT EXISTS(SELECT 1 FROM matches WHERE room_id = $1 AND player_id = $2)`,
				roomID, player.playerID,
			).Scan(&exists); err != nil {
				log.Printf("check match result: %v", err)
				return
			}
			if exists {
				log.Printf("match result already saved room=%d player=%d", roomID, player.playerID)
				continue
			}
		}
		_, err := transaction.ExecContext(ctx,
			`INSERT INTO matches (room_id, player_id, team, won,
			                      duration_sec, kills, deaths, damage,
			                      crystals, shells, shop_items, class_key)
			 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
			roomID,
			player.playerID,
			player.team,
			player.team == winningTeam,
			player.durationSec,
			player.kills,
			player.deaths,
			player.damage,
			player.crystals,
			player.shells,
			player.shopItems,
			player.classKey,
		)
		if err != nil {
			log.Printf("save match result: %v", err)
			return
		}
		inserted = append(inserted, player)
	}
	for _, player := range inserted {
		if player.playerID <= 0 {
			continue
		}
		// Quest progress comes from the same validated result and shares
		// the transaction, so a failed match save never pays a quest and a
		// quest error rolls the match row back instead of splitting them.
		if err := applyQuestProgress(transaction, player.playerID, player.stats(player.team == winningTeam)); err != nil {
			log.Printf("apply quest progress player=%d: %v", player.playerID, err)
			return
		}
		var matchesPlayed, wins int
		if err := transaction.QueryRowContext(ctx, `
			SELECT COUNT(DISTINCT room_id),
			       COUNT(DISTINCT room_id) FILTER (WHERE won)
			FROM matches WHERE player_id = $1
		`, player.playerID).Scan(&matchesPlayed, &wins); err != nil {
			log.Printf("count player matches: %v", err)
			continue
		}
		var currentNovice bool
		if err := transaction.QueryRowContext(ctx,
			`SELECT COALESCE(novice, FALSE) FROM players WHERE id = $1`,
			player.playerID,
		).Scan(&currentNovice); err != nil {
			log.Printf("load player novice flag: %v", err)
			continue
		}
		newNovice := noviceAfterMatches(matchesPlayed, wins, currentNovice)
		if _, err := transaction.ExecContext(ctx, `
			UPDATE players SET matches_played = $2, novice = $3 WHERE id = $1
		`, player.playerID, matchesPlayed, newNovice); err != nil {
			log.Printf("update player novice state: %v", err)
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

// broadcastRoomCritical is for the one message a client cannot infer or
// recover: match_finished. If the per-client send buffer is full, the sender
// waits briefly for the writer instead of silently dropping the result.
func (h *wsHub) broadcastRoomCritical(roomID int64, exceptID int64, message wsOutgoing) {
	h.mu.Lock()
	room := h.rooms[roomID]
	var targets []*wsClient
	if room != nil {
		targets = roomClientsLocked(room, exceptID)
	}
	h.mu.Unlock()
	h.sendToClientsCritical(targets, message)
}

func (h *wsHub) sendToClients(clients []*wsClient, message wsOutgoing) {
	h.sendToClientsMode(clients, message, false)
}

func (h *wsHub) sendToClientsCritical(clients []*wsClient, message wsOutgoing) {
	h.sendToClientsMode(clients, message, true)
}

func (h *wsHub) sendToClientsMode(clients []*wsClient, message wsOutgoing, critical bool) {
	if len(clients) == 0 {
		return
	}
	data, err := json.Marshal(message)
	if err != nil {
		log.Printf("websocket marshal: %v", err)
		return
	}
	for _, client := range clients {
		if critical {
			client.trySendCritical(data)
			continue
		}
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
		// The storm ticks at MAGE_STORM_DAMAGE (70) x 0.75-1.25 x 2 outgoing
		// on the client, i.e. 105-175 per normal tick (210-350 on an ultimate
		// crit, clipped to 250). 1.4 keeps the server base at 54.6 for the
		// client's 39 mage damage and its 70 damage tick, so a normal tick
		// arrives in full and the hard cap below stops a forged crit.
		multiplier = 1.4
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

// trySendCritical must not silently lose the message. It first tries the normal
// non-blocking path, then waits up to wsCriticalSendWait for the writer. If the
// buffer is still full the connection is closed: the client sees a disconnect
// and can abort locally, which is better than a results screen that never opens.
func (c *wsClient) trySendCritical(data []byte) bool {
	select {
	case <-c.done:
		return false
	default:
	}
	select {
	case c.send <- data:
		return true
	default:
	}
	timer := time.NewTimer(wsCriticalSendWait)
	defer timer.Stop()
	select {
	case c.send <- data:
		return true
	case <-c.done:
		return false
	case <-timer.C:
		log.Printf("[WS] critical message could not be queued (client buffer full); closing client")
		c.close()
		return false
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
	return math.Max(-52, math.Min(52, value))
}

func clampArenaZ(value float64) float64 {
	return math.Max(-37, math.Min(37, value))
}
