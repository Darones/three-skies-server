extends Node

signal connection_state_changed(state: int)
signal connection_succeeded
signal connection_failed(reason: String)
signal disconnected
signal welcome_received(player_id: int)
signal remote_player_joined(player_id: int, info: Dictionary)
signal remote_player_state(player_id: int, position: Vector3, rotation: float)
signal remote_player_left(player_id: int)
signal remote_attack_received(player_id: int, attack_type: String, target_id: int)
signal remote_damage_received(source_id: int, target_id: int, amount: float, skill: String)
signal remote_death_received(player_id: int)
signal remote_respawn_received(player_id: int, position: Vector3, rotation: float)
signal remote_heal_received(source_id: int, target_id: int, amount: float)
signal remote_stats_updated(player_id: int, max_hp: float, hp: float, attack_damage: float)
signal bot_state_updated(bot_id: int, info: Dictionary)
signal attack_denied(target_id: int, skill: String, reason: String)
signal match_started(room_id: int, host_id: int, players: Array)
signal match_finished(winning_team: int)
signal match_score_updated(score_0: int, score_1: int, sudden_death: bool)
signal match_event_received(event: String, team: int)
signal host_changed(new_host_id: int)

enum State { DISCONNECTED, CONNECTING, CONNECTED }

const DEFAULT_WS_URL := "ws://127.0.0.1:8080/ws"
const CONNECT_TIMEOUT := 6.0
const SEND_INTERVAL := 1.0 / 12.0

var state: int = State.DISCONNECTED
var ws_url := DEFAULT_WS_URL
var socket: WebSocketPeer = null
var local_peer_id := 0
var local_hero: Node3D = null
var local_bots: Array[Node3D] = []
var remote_players: Dictionary = {}
var room_id := 0
var host_id := 0
var assigned_team := 0
var local_class := 0
var is_host := false
var match_players: Array = []

var _pending_class := 0
var _pending_team := 0
var _pending_name := ""
var _pending_player_id := 0
var _connect_deadline_msec := 0
var _send_accumulator := 0.0
var _bot_send_accumulator := 0.0


func _ready() -> void:
	var env_url := OS.get_environment("THREE_SKIES_WS_URL").strip_edges()
	if not env_url.is_empty():
		ws_url = env_url
	else:
		var setting_url := String(ProjectSettings.get_setting("network/ws_url", DEFAULT_WS_URL)).strip_edges()
		ws_url = setting_url if not setting_url.is_empty() else DEFAULT_WS_URL
	print("[NET] WebSocket URL: ", ws_url)


func is_server_connected() -> bool:
	return state == State.CONNECTED


func is_connecting() -> bool:
	return state == State.CONNECTING


func connect_to_server(hero_class: int = 0, team: int = 0, player_name := "", player_id := 0) -> Error:
	if state == State.CONNECTED:
		return OK
	if state == State.CONNECTING:
		return ERR_BUSY

	_pending_class = clampi(hero_class, 0, 2)
	_pending_team = clampi(team, 0, 1)
	_pending_name = String(player_name).strip_edges()
	_pending_player_id = int(player_id)
	local_peer_id = 0
	local_bots.clear()
	remote_players.clear()
	match_players.clear()
	room_id = 0
	host_id = 0
	assigned_team = 0
	local_class = clampi(hero_class, 0, 2)
	is_host = false

	socket = WebSocketPeer.new()
	if "handshake_timeout" in socket:
		socket.handshake_timeout = CONNECT_TIMEOUT
	var error := socket.connect_to_url(ws_url)
	if error != OK:
		socket = null
		state = State.DISCONNECTED
		connection_state_changed.emit(state)
		connection_failed.emit("Не удалось создать WebSocket-клиент.")
		return error

	state = State.CONNECTING
	_connect_deadline_msec = Time.get_ticks_msec() + int(CONNECT_TIMEOUT * 1000.0)
	_send_accumulator = 0.0
	_bot_send_accumulator = 0.0
	connection_state_changed.emit(state)
	print("[NET] Подключение к ", ws_url)
	return OK


func disconnect_from_server(notify := true) -> void:
	var was_active := state != State.DISCONNECTED
	if socket != null:
		socket.close()
		socket = null
	state = State.DISCONNECTED
	local_peer_id = 0
	local_hero = null
	local_bots.clear()
	remote_players.clear()
	match_players.clear()
	room_id = 0
	host_id = 0
	assigned_team = 0
	local_class = 0
	is_host = false
	if was_active:
		connection_state_changed.emit(state)
		if notify:
			disconnected.emit()


func register_local_player(hero: Node3D) -> void:
	local_hero = hero


func unregister_local_player() -> void:
	local_hero = null


func register_bot(bot: Node3D) -> void:
	if bot == null or not is_instance_valid(bot):
		return
	if not local_bots.has(bot):
		local_bots.append(bot)


func clear_bots() -> void:
	local_bots.clear()


func get_remote_snapshot() -> Dictionary:
	return remote_players.duplicate(true)


func send_attack_intent(target_id: int, skill: String, source_id: int = 0) -> void:
	if state != State.CONNECTED or target_id == 0:
		return
	var payload := {
		"type": "attack_intent",
		"target_id": target_id,
		"skill": skill,
	}
	if source_id != 0:
		payload["source_id"] = source_id
	_send_json(payload)


func send_match_event(event: String, team: int) -> void:
	if state != State.CONNECTED or event.is_empty():
		return
	_send_json({
		"type": "match_event",
		"event": event,
		"team": clampi(team, 0, 1),
	})


func send_attack(attack_type: String, target_id: int = 0) -> void:
	if state != State.CONNECTED:
		return
	var payload := {
		"type": "attack",
		"attack_type": attack_type,
		"target_id": target_id,
	}
	if local_hero != null and is_instance_valid(local_hero):
		var position := local_hero.global_position
		payload["x"] = position.x
		payload["y"] = position.y
		payload["z"] = position.z
		var visual: Variant = local_hero.get("visual")
		payload["rotation"] = (visual as Node3D).global_rotation.y if visual is Node3D else local_hero.global_rotation.y
	_send_json(payload)


func send_heal(target_id: int, amount: float) -> void:
	if state != State.CONNECTED or target_id <= 0 or amount <= 0.0:
		return
	_send_json({
		"type": "heal",
		"target_id": target_id,
		"amount": amount,
	})


func send_stats(max_hp: float, hp: float, attack_damage: float) -> void:
	if state != State.CONNECTED or max_hp <= 0.0:
		return
	_send_json({
		"type": "stats",
		"max_hp": max_hp,
		"hp": clampf(hp, 0.0, max_hp),
		"attack_damage": maxf(attack_damage, 0.0),
	})


func send_death() -> void:
	if state != State.CONNECTED:
		return
	_send_json({"type": "death"})


func send_respawn(position: Vector3, rotation_y: float) -> void:
	if state != State.CONNECTED:
		return
	_send_json({
		"type": "respawn",
		"x": position.x,
		"y": position.y,
		"z": position.z,
		"rotation": rotation_y,
	})


func _process(delta: float) -> void:
	if socket == null:
		return

	socket.poll()
	var ready_state := socket.get_ready_state()
	if ready_state == WebSocketPeer.STATE_OPEN:
		if state != State.CONNECTED:
			state = State.CONNECTED
			_send_join()
			connection_state_changed.emit(state)
			connection_succeeded.emit()
			print("[NET] Подключено")
		_drain_packets()
		_send_local_state(delta)
		_send_bot_states(delta)
		return

	if ready_state == WebSocketPeer.STATE_CLOSED:
		var was_connected := state == State.CONNECTED
		var was_connecting := state == State.CONNECTING
		var reason := ""
		if socket != null:
			reason = socket.get_close_reason()
		socket = null
		state = State.DISCONNECTED
		local_peer_id = 0
		local_bots.clear()
		remote_players.clear()
		connection_state_changed.emit(state)
		if was_connected:
			disconnected.emit()
		elif was_connecting:
			connection_failed.emit(reason if not reason.is_empty() else "Сервер недоступен.")
		return

	if state == State.CONNECTING and Time.get_ticks_msec() >= _connect_deadline_msec:
		socket.close()
		socket = null
		state = State.DISCONNECTED
		connection_state_changed.emit(state)
		connection_failed.emit("Таймаут подключения к серверу.")


func _send_join() -> void:
	_send_json({
		"type": "join",
		"name": _pending_name if not _pending_name.is_empty() else "Игрок",
		"class": _pending_class,
		"class_name": ["warrior", "mage", "fairy"][_pending_class],
		"team": _pending_team,
		"player_id": _pending_player_id,
	})


func _send_local_state(delta: float) -> void:
	if local_hero == null or not is_instance_valid(local_hero):
		return
	if local_hero.get("dead") == true:
		return
	_send_accumulator += delta
	if _send_accumulator < SEND_INTERVAL:
		return
	_send_accumulator = 0.0
	var position := local_hero.global_position
	var rotation_y := local_hero.global_rotation.y
	var visual: Variant = local_hero.get("visual")
	if visual is Node3D:
		rotation_y = (visual as Node3D).global_rotation.y
	_send_json({
		"type": "state",
		"x": position.x,
		"y": position.y,
		"z": position.z,
		"rotation": rotation_y,
	})


func _send_bot_states(delta: float) -> void:
	if not is_host or local_bots.is_empty():
		return
	_bot_send_accumulator += delta
	if _bot_send_accumulator < SEND_INTERVAL:
		return
	_bot_send_accumulator = 0.0
	var bots: Array = []
	for bot in local_bots:
		if bot == null or not is_instance_valid(bot):
			continue
		var bot_id := int(bot.get("network_id"))
		if bot_id == 0:
			continue
		var position: Vector3 = bot.global_position
		var rotation_y: float = bot.global_rotation.y
		var visual: Variant = bot.get("visual")
		if visual is Node3D:
			rotation_y = (visual as Node3D).global_rotation.y
		bots.append({
			"id": bot_id,
			"x": snappedf(position.x, 0.01),
			"y": snappedf(position.y, 0.01),
			"z": snappedf(position.z, 0.01),
			"rotation": snappedf(rotation_y, 0.01),
			"max_hp": maxf(float(bot.get("max_health")), 0.0),
			"hp": maxf(float(bot.get("health")), 0.0),
			"attack_damage": maxf(float(bot.get("attack_damage")), 0.0),
			"alive": not bool(bot.get("dead")),
			"animation": String(bot.get("current_anim")),
		})
	if bots.is_empty():
		return
	_send_json({
		"type": "bot_states",
		"bots": bots,
	})


func _send_json(message: Dictionary) -> void:
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	socket.send_text(JSON.stringify(message))


func _drain_packets() -> void:
	while socket != null and socket.get_available_packet_count() > 0:
		var packet := socket.get_packet()
		_handle_message(packet.get_string_from_utf8())


func _handle_message(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	var message: Dictionary = parsed
	match String(message.get("type", "")):
		"welcome":
			_handle_welcome(message)
		"player_joined":
			_upsert_remote(message, true)
		"state":
			_handle_state(message)
		"player_left":
			_handle_player_left(message)
		"attack":
			_handle_attack(message)
		"damage":
			_handle_damage(message)
		"heal":
			_handle_heal(message)
		"stats":
			_handle_stats(message)
		"death":
			_handle_death(message)
		"respawn":
			_handle_respawn(message)
		"room_joined":
			_handle_room_joined(message)
		"match_start":
			_handle_match_start(message)
		"match_score":
			match_score_updated.emit(
				int(message.get("score_0", 0)),
				int(message.get("score_1", 0)),
				bool(message.get("sudden_death", false))
			)
		"match_event":
			match_event_received.emit(
				String(message.get("event", "")),
				int(message.get("team", 0))
			)
		"match_finished":
			if message.has("score_0") or message.has("score_1"):
				match_score_updated.emit(
					int(message.get("score_0", 0)),
					int(message.get("score_1", 0)),
					bool(message.get("sudden_death", false))
				)
			match_finished.emit(int(message.get("winning_team", 0)))
		"bot_states":
			_handle_bot_states(message)
		"attack_denied":
			attack_denied.emit(
				int(message.get("target_id", 0)),
				String(message.get("skill", "")),
				String(message.get("reason", "denied"))
			)
		"host_changed":
			host_id = int(message.get("host_id", message.get("id", 0)))
			is_host = host_id == local_peer_id
			host_changed.emit(host_id)


func _handle_welcome(message: Dictionary) -> void:
	local_peer_id = int(message.get("id", 0))
	welcome_received.emit(local_peer_id)
	var players: Variant = message.get("players", [])
	if players is Array:
		for entry in players:
			if entry is Dictionary:
				_upsert_remote(entry, true)


func _handle_state(message: Dictionary) -> void:
	var player_id := int(message.get("id", 0))
	if player_id <= 0 or player_id == local_peer_id:
		return
	var position := Vector3(
		float(message.get("x", 0.0)),
		float(message.get("y", 0.0)),
		float(message.get("z", 0.0))
	)
	var rotation_y := float(message.get("rotation", 0.0))
	if not remote_players.has(player_id):
		var info := _make_remote_info(message)
		info["position"] = position
		info["rotation"] = rotation_y
		info["has_state"] = true
		remote_players[player_id] = info
		remote_player_joined.emit(player_id, info)
	else:
		var info: Dictionary = remote_players[player_id]
		if message.has("class"):
			info["class"] = clampi(int(message.get("class", 0)), 0, 2)
		if message.has("team"):
			info["team"] = clampi(int(message.get("team", 0)), 0, 1)
		info["position"] = position
		info["rotation"] = rotation_y
		info["has_state"] = true
	remote_player_state.emit(player_id, position, rotation_y)


func _upsert_remote(message: Dictionary, emit_join: bool) -> void:
	var player_id := int(message.get("id", 0))
	if player_id <= 0 or player_id == local_peer_id:
		return
	var is_new := not remote_players.has(player_id)
	var info: Dictionary
	if is_new:
		info = _make_remote_info(message)
		remote_players[player_id] = info
	else:
		info = remote_players[player_id]
		if message.has("name"):
			var updated_name := String(message.get("name", "")).strip_edges()
			if not updated_name.is_empty():
				info["name"] = updated_name
		if message.has("class"):
			info["class"] = clampi(int(message.get("class", 0)), 0, 2)
		if message.has("team"):
			info["team"] = clampi(int(message.get("team", 0)), 0, 1)
		if message.has("alive"):
			info["alive"] = bool(message.get("alive", true))
		if message.has("max_hp"):
			info["max_hp"] = maxf(float(message.get("max_hp", 0.0)), 0.0)
		if message.has("hp"):
			info["hp"] = maxf(float(message.get("hp", 0.0)), 0.0)
		if message.has("attack_damage"):
			info["attack_damage"] = maxf(float(message.get("attack_damage", 0.0)), 0.0)
		if message.has("max_hp") or message.has("hp") or message.has("attack_damage"):
			remote_stats_updated.emit(
				player_id,
				float(info.get("max_hp", 0.0)),
				float(info.get("hp", 0.0)),
				float(info.get("attack_damage", 0.0))
			)
	if emit_join and is_new:
		remote_player_joined.emit(player_id, info)
	if bool(message.get("has_state", false)):
		var position := Vector3(
			float(message.get("x", 0.0)),
			float(message.get("y", 0.0)),
			float(message.get("z", 0.0))
		)
		var rotation_y := float(message.get("rotation", 0.0))
		info["position"] = position
		info["rotation"] = rotation_y
		info["has_state"] = true
		remote_player_state.emit(player_id, position, rotation_y)


func _make_remote_info(message: Dictionary) -> Dictionary:
	var player_id := int(message.get("id", 0))
	var remote_name := String(message.get("name", "")).strip_edges()
	if remote_name.is_empty():
		remote_name = "Игрок %d" % player_id
	return {
		"id": player_id,
		"name": remote_name,
		"class": clampi(int(message.get("class", 0)), 0, 2),
		"team": clampi(int(message.get("team", 0)), 0, 1),
		"bot": bool(message.get("bot", false)),
		"position": Vector3.ZERO,
		"rotation": 0.0,
		"has_state": false,
		"alive": bool(message.get("alive", true)),
		"max_hp": maxf(float(message.get("max_hp", 0.0)), 0.0),
		"hp": maxf(float(message.get("hp", 0.0)), 0.0),
		"attack_damage": maxf(float(message.get("attack_damage", 0.0)), 0.0),
		"animation": "",
	}


func _handle_room_joined(message: Dictionary) -> void:
	room_id = int(message.get("room_id", 0))
	host_id = int(message.get("host_id", 0))
	assigned_team = int(message.get("team", assigned_team))
	local_class = clampi(int(message.get("class", local_class)), 0, 2)
	print("[NET] room=", room_id, " team=", assigned_team, " host=", host_id)


func _handle_match_start(message: Dictionary) -> void:
	room_id = int(message.get("room_id", 0))
	host_id = int(message.get("host_id", 0))
	var players: Variant = message.get("match_players", [])
	match_players = players if players is Array else []
	remote_players.clear()
	assigned_team = 0
	is_host = host_id == local_peer_id and local_peer_id > 0
	for entry in match_players:
		if not entry is Dictionary:
			continue
		var player_id := int(entry.get("id", 0))
		if player_id == local_peer_id:
			assigned_team = int(entry.get("team", 0))
			local_class = clampi(int(entry.get("class", local_class)), 0, 2)
		elif not bool(entry.get("bot", false)) or not is_host:
			var info := _make_remote_info(entry)
			if bool(entry.get("bot", false)):
				info["position"] = Vector3(0.0, 0.76, 27.5 if int(info["team"]) == 0 else -27.5)
				info["rotation"] = 0.0 if int(info["team"]) == 0 else PI
				info["has_state"] = true
			remote_players[player_id] = info
			remote_player_joined.emit(player_id, info)
	print("[NET] match_start room=", room_id, " host=", is_host, " team=", assigned_team, " players=", match_players.size())
	match_started.emit(room_id, host_id, match_players)


func _handle_bot_states(message: Dictionary) -> void:
	if is_host:
		return
	var bots: Variant = message.get("bots", [])
	if not bots is Array:
		return
	for entry in bots:
		if not entry is Dictionary:
			continue
		var bot_id := int(entry.get("id", 0))
		if bot_id >= 0:
			continue
		var info: Dictionary = remote_players.get(bot_id, _make_remote_info(entry))
		info["bot"] = true
		if entry.has("name"):
			var bot_name := String(entry.get("name", "")).strip_edges()
			if not bot_name.is_empty():
				info["name"] = bot_name
		if entry.has("class"):
			info["class"] = clampi(int(entry.get("class", 0)), 0, 2)
		if entry.has("team"):
			info["team"] = clampi(int(entry.get("team", 0)), 0, 1)
		info["position"] = Vector3(
			float(entry.get("x", 0.0)),
			float(entry.get("y", 0.0)),
			float(entry.get("z", 0.0))
		)
		info["rotation"] = float(entry.get("rotation", 0.0))
		info["has_state"] = true
		info["alive"] = bool(entry.get("alive", true))
		info["max_hp"] = maxf(float(entry.get("max_hp", 0.0)), 0.0)
		info["hp"] = maxf(float(entry.get("hp", 0.0)), 0.0)
		info["attack_damage"] = maxf(float(entry.get("attack_damage", 0.0)), 0.0)
		info["animation"] = String(entry.get("animation", ""))
		var is_new := not remote_players.has(bot_id)
		remote_players[bot_id] = info
		if is_new:
			remote_player_joined.emit(bot_id, info)
		bot_state_updated.emit(bot_id, info.duplicate(true))


func _handle_attack(message: Dictionary) -> void:
	var source_id := int(message.get("source_id", message.get("id", 0)))
	if source_id <= 0 or source_id == local_peer_id:
		return
	remote_attack_received.emit(
		source_id,
		String(message.get("attack_type", "auto")),
		int(message.get("target_id", 0))
	)


func _handle_damage(message: Dictionary) -> void:
	var source_id := int(message.get("source_id", message.get("id", 0)))
	var target_id := int(message.get("target_id", 0))
	var amount := float(message.get("amount", 0.0))
	if target_id == 0 or amount <= 0.0:
		return
	remote_damage_received.emit(source_id, target_id, amount, String(message.get("skill", "auto")))


func _handle_heal(message: Dictionary) -> void:
	var source_id := int(message.get("source_id", message.get("id", 0)))
	var target_id := int(message.get("target_id", 0))
	var amount := float(message.get("amount", 0.0))
	if target_id <= 0 or amount <= 0.0:
		return
	remote_heal_received.emit(source_id, target_id, amount)


func _handle_stats(message: Dictionary) -> void:
	var player_id := int(message.get("id", 0))
	if player_id <= 0 or player_id == local_peer_id:
		return
	if not remote_players.has(player_id):
		var info := _make_remote_info(message)
		remote_players[player_id] = info
		remote_player_joined.emit(player_id, info)
	var info: Dictionary = remote_players[player_id]
	info["max_hp"] = maxf(float(message.get("max_hp", 0.0)), 0.0)
	info["hp"] = maxf(float(message.get("hp", 0.0)), 0.0)
	info["attack_damage"] = maxf(float(message.get("attack_damage", 0.0)), 0.0)
	remote_stats_updated.emit(
		player_id,
		float(info["max_hp"]),
		float(info["hp"]),
		float(info["attack_damage"])
	)


func _handle_death(message: Dictionary) -> void:
	var player_id := int(message.get("id", message.get("player_id", 0)))
	if player_id == 0 or player_id == local_peer_id:
		return
	if remote_players.has(player_id):
		var info: Dictionary = remote_players[player_id]
		info["alive"] = false
	remote_death_received.emit(player_id)


func _handle_respawn(message: Dictionary) -> void:
	var player_id := int(message.get("id", message.get("player_id", 0)))
	if player_id <= 0 or player_id == local_peer_id:
		return
	var position := Vector3(
		float(message.get("x", 0.0)),
		float(message.get("y", 0.0)),
		float(message.get("z", 0.0))
	)
	var rotation_y := float(message.get("rotation", 0.0))
	if remote_players.has(player_id):
		var info: Dictionary = remote_players[player_id]
		info["alive"] = true
		info["position"] = position
		info["rotation"] = rotation_y
		info["has_state"] = true
	remote_respawn_received.emit(player_id, position, rotation_y)


func _handle_player_left(message: Dictionary) -> void:
	var player_id := int(message.get("id", 0))
	if player_id <= 0:
		return
	remote_players.erase(player_id)
	remote_player_left.emit(player_id)


func _exit_tree() -> void:
	if socket != null:
		socket.close()
		socket = null
