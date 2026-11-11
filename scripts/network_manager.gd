extends Node

signal connection_state_changed(state: int)
signal connection_succeeded
signal connection_failed(reason: String)
signal disconnected
signal welcome_received(player_id: int)
signal remote_player_joined(player_id: int, info: Dictionary)
signal remote_player_state(player_id: int, position: Vector3, rotation: float)
signal remote_player_left(player_id: int)

enum State { DISCONNECTED, CONNECTING, CONNECTED }

const DEFAULT_WS_URL := "ws://127.0.0.1:8080/ws"
const CONNECT_TIMEOUT := 6.0
const SEND_INTERVAL := 1.0 / 12.0

var state: int = State.DISCONNECTED
var ws_url := DEFAULT_WS_URL
var socket: WebSocketPeer = null
var local_peer_id := 0
var local_hero: Node3D = null
var remote_players: Dictionary = {}

var _pending_class := 0
var _pending_team := 0
var _pending_name := ""
var _connect_deadline_msec := 0
var _send_accumulator := 0.0


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


func connect_to_server(hero_class: int = 0, team: int = 0, player_name := "") -> Error:
	if state == State.CONNECTED:
		return OK
	if state == State.CONNECTING:
		return ERR_BUSY

	_pending_class = clampi(hero_class, 0, 2)
	_pending_team = clampi(team, 0, 1)
	_pending_name = String(player_name).strip_edges()
	local_peer_id = 0
	remote_players.clear()

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
	remote_players.clear()
	if was_active:
		connection_state_changed.emit(state)
		if notify:
			disconnected.emit()


func register_local_player(hero: Node3D) -> void:
	local_hero = hero


func unregister_local_player() -> void:
	local_hero = null


func get_remote_snapshot() -> Dictionary:
	return remote_players.duplicate(true)


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
		"team": _pending_team,
	})


func _send_local_state(delta: float) -> void:
	if local_hero == null or not is_instance_valid(local_hero):
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
		"position": Vector3.ZERO,
		"rotation": 0.0,
		"has_state": false,
	}


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
