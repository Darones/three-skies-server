extends Node

# ============================================================
# Sky Shards — WebSocket Matchmaking Server
# Port: 9080 | Max players: 6 | Teams: Light vs Dark
# ============================================================

const DEFAULT_PORT := 9080
var PORT : int = int(OS.get_environment("PORT")) if OS.get_environment("PORT") != "" else DEFAULT_PORT
const MAX_PLAYERS := 6
const QUEUE_TIMEOUT := 2.0  # seconds

enum PlayerClass {
	WARRIOR = 1
	MAGE = 2
	FAIRY = 3
}

enum Team {
	NONE = 0
	LIGHT = 1
	DARK = 2
}

# ---------- internal state ----------

var _server: WebSocketServer = null
var _peers: Dictionary = {}			# client_id -> WebSocketPeer
var _players: Dictionary = {}		# client_id -> { peer, class, team, is_bot }
var _queue: Array = []				# waiting players (non-bot)
var _queue_timer: Timer = null
var _match_started: bool = false
var _next_id: int = 1


func _ready() -> void:
	print("=== СКРИПТ СЕРВЕРА НАЧАЛ РАБОТУ ===")
	print("\n========================================")
	print("   SKY SHARDS MATCHMAKING SERVER")
	print("========================================")
	print("Port: ", PORT)
	print("Max players: ", MAX_PLAYERS)
	print("Queue timeout: ", QUEUE_TIMEOUT, "s")
	print("========================================\n")

	_server = WebSocketServer.new()
	var err := _server.listen(PORT)
	if err != OK:
		printerr("FAILED to listen on port ", PORT, ": ", err)
		return

	print("Server is listening on port ", PORT, "\n")
	print("=== СЕРВЕР УСПЕШНО ЗАПУЩЕН НА ПОРТУ: ", PORT, " ===")

	# Timer for matchmaking queue
	_queue_timer = Timer.new()
	_queue_timer.wait_time = QUEUE_TIMEOUT
	_queue_timer.one_shot = true
	_queue_timer.timeout.connect(_on_queue_timeout)
	add_child(_queue_timer)


func _process(_delta: float) -> void:
	if _server == null:
		return

	_server.poll()
	var status := _server.get_status()

	if status == WebSocketServer.SERVER_STATE_CONNECTED:
		# Accept new peers
		for id in _server.get_peers():
			var peer: WebSocketPeer = _server.take_peer(id)
			if peer != null:
				_peers[id] = peer
				_players[id] = {
					peer = peer,
					class_id = PlayerClass.WARRIOR,
					team = Team.NONE,
					is_bot = false
				}
				print("[CONNECT] Player #", id, " joined")
				_send(peer, {"type": "welcome", "player_id": id})

		# Read incoming data from all peers
		for id in _peers.keys():
			var peer: WebSocketPeer = _peers[id]
			if peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
				while peer.get_available_packet_count() > 0:
					var raw := peer.get_packet()
					var text := raw.get_string_from_utf8()
					_handle_packet(id, text)


# ---------- packet handling ----------

func _handle_packet(client_id: int, raw_text: String) -> void:
	var parsed = JSON.parse_string(raw_text)
	if parsed == null or not parsed is Dictionary:
		return

	var pkt: Dictionary = parsed
	var ptype: String = pkt.get("type", "")

	if ptype == "join_queue":
		_join_queue(client_id, pkt)


func _join_queue(client_id: int, pkt: Dictionary) -> void:
	if _match_started:
		_send(_peers[client_id], {"type": "error", "message": "Match already in progress"})
		return

	var class_id: int = pkt.get("class", PlayerClass.WARRIOR)

	# Store class
	_players[client_id]["class_id"] = class_id
	_players[client_id]["team"] = Team.NONE

	print("[QUEUE] Player #", client_id, " class=", class_id, "  queue_size=", _queue.size() + 1)

	_queue.append(client_id)

	# First player in queue -> start countdown
	if _queue.size() == 1:
		print("[TIMER] First player — starting ", QUEUE_TIMEOUT, "s countdown...")
		_queue_timer.start()


# ---------- queue timeout / match start ----------

func _on_queue_timeout() -> void:
	print("\n[TIMER] Queue timeout reached!")
	print("[TIMER] Players in queue: ", _queue.size())

	if _queue.size() < 2:
		print("[TIMER] Not enough players (<2), clearing queue")
		_queue.clear()
		return

	_start_match()


func _start_match() -> void:
	_match_started = true
	_queue_timer.stop()

	var light_team: Array = []
	var dark_team: Array = []

	# Distribute queued players
	for pid in _queue:
		if _players.has(pid):
			_assign_team(pid, light_team, dark_team)

	var current_count := light_team.size() + dark_team.size()

	# Fill remaining slots with bots
	if current_count < MAX_PLAYERS:
		_fill_with_bots(light_team, dark_team, current_count)

	# Build match payload
	var match_data := {
		"light_team": _serialize_team(light_team),
		"dark_team": _serialize_team(dark_team),
		"light_count": light_team.size(),
		"dark_count": dark_team.size()
	}

	# Notify real players with their team
	for pid in light_team:
		if _players.has(pid) and not _players[pid]["is_bot"] and _peers.has(pid):
			_send(_peers[pid], {
				"type": "start_match",
				"team": "light",
				"match": match_data
			})
			print("[MATCH] Player #", pid, " -> LIGHT team")

	for pid in dark_team:
		if _players.has(pid) and not _players[pid]["is_bot"] and _peers.has(pid):
			_send(_peers[pid], {
				"type": "start_match",
				"team": "dark",
				"match": match_data
			})
			print("[MATCH] Player #", pid, " -> DARK team")

	print("[MATCH] Started! Light: ", light_team.size(), " | Dark: ", dark_team.size())
	print("========================================\n")


# ---------- team assignment with role balance ----------

func _assign_team(player_id: int, light_team: Array, dark_team: Array) -> void:
	var player := _players[player_id]
	var cls := player["class_id"]

	var light_classes := _get_team_classes(light_team)
	var dark_classes := _get_team_classes(dark_team)

	# Prefer the smaller team
	if light_team.size() <= dark_team.size():
		if not light_classes.has(cls):
			_commit_team(player_id, Team.LIGHT, light_team)
			return
		elif not dark_classes.has(cls):
			_commit_team(player_id, Team.DARK, dark_team)
			return
		else:
			# Both classes taken — go to smaller team anyway
			_commit_team(player_id, Team.LIGHT, light_team)
			return
	else:
		if not dark_classes.has(cls):
			_commit_team(player_id, Team.DARK, dark_team)
			return
		elif not light_classes.has(cls):
			_commit_team(player_id, Team.LIGHT, light_team)
			return
		else:
			_commit_team(player_id, Team.DARK, dark_team)


func _commit_team(player_id: int, team: int, team_array: Array) -> void:
	_players[player_id]["team"] = team
	team_array.append(player_id)


func _get_team_classes(team_arr: Array) -> Array:
	var classes := []
	for pid in team_arr:
		if _players.has(pid):
			var cls := _players[pid]["class_id"]
			if not classes.has(cls):
				classes.append(cls)
	return classes


# ---------- bot filling ----------

func _fill_with_bots(light_team: Array, dark_team: Array, current_count: int) -> void:
	var all_classes := [PlayerClass.WARRIOR, PlayerClass.MAGE, PlayerClass.FAIRY]

	while current_count < MAX_PLAYERS:
		var light_classes := _get_team_classes(light_team)
		var dark_classes := _get_team_classes(dark_team)

		# Pick the team that needs more players or has a missing role
		var target_team: Array
		var target_classes: Array

		if light_team.size() <= dark_team.size():
			target_team = light_team
			target_classes = light_classes
		else:
			target_team = dark_team
			target_classes = dark_classes

		# Find a role not yet in this team
		var bot_class: int = PlayerClass.WARRIOR
		for cls in all_classes:
			if not target_classes.has(cls):
				bot_class = cls
				break

		# Create bot entry
		var bot_id := _next_id
		_next_id += 1

		_players[bot_id] = {
			peer = null,
			class_id = bot_class,
			team = target_team[0] if not target_team.is_empty() else Team.NONE,
			is_bot = true
		}

		if target_team == light_team:
			_players[bot_id]["team"] = Team.LIGHT
			light_team.append(bot_id)
		else:
			_players[bot_id]["team"] = Team.DARK
			dark_team.append(bot_id)

		print("[BOT] Added #", bot_id, " class=", bot_class, " team=", target_team[0])
		current_count += 1

		# Safety: if both teams are full with all 3 roles, stop
		if light_classes.has_all(all_classes) and dark_classes.has_all(all_classes):
			break


# ---------- helpers ----------

func _serialize_team(team_arr: Array) -> Array:
	var result := []
	for pid in team_arr:
		if _players.has(pid):
			var p := _players[pid]
			result.append({
				"player_id": pid,
				"class": p["class_id"],
				"is_bot": p["is_bot"]
			})
	return result


func _send(peer: WebSocketPeer, data: Dictionary) -> void:
	if peer == null:
		return
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var json_str := JSON.stringify(data)
	peer.send_text(json_str)
