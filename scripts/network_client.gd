extends Node

signal match_started
signal connected
signal players_list(players: Array)
signal connection_failed
signal registration_completed(success: bool, player_id: int)
signal profile_loaded(success: bool, player_id: int, sky_shards: int, unlocked_wings: Array, unlocked_weapons: Array)
signal purchase_completed(success: bool, purchase_type: String, item_id: int, new_shards: int)
signal match_reward_completed(success: bool, amount: int, new_shards: int)

const API_BASE_URL := "https://three-skies-server.relaxdev.ru"

var api_base_url := API_BASE_URL
var peer: WebSocketMultiplayerPeer
var current_class: int = 1
var http_request: HTTPRequest
var http_request_busy := false
var current_http_request: Dictionary = {}
var http_request_queue: Array[Dictionary] = []
var players_list_received := false


func _ready() -> void:
	var env_url := OS.get_environment("THREE_SKIES_API_BASE_URL").strip_edges()
	if not env_url.is_empty():
		api_base_url = env_url
	else:
		var setting_url := String(ProjectSettings.get_setting("network/api_base_url", API_BASE_URL)).strip_edges()
		api_base_url = setting_url if not setting_url.is_empty() else API_BASE_URL
	api_base_url = api_base_url.trim_suffix("/")
	print("[NET] REST URL: ", api_base_url)
	http_request = HTTPRequest.new()
	http_request.name = "NetworkHTTPRequest"
	http_request.timeout = 10.0
	add_child(http_request)
	http_request.request_completed.connect(_on_http_request_completed)


func register_player(nickname: String) -> void:
	_send_post("/register", {"nickname": nickname}, "register")


func buy_wing_server(player_id: int, wing_id: int, cost: int) -> void:
	_send_post("/buy_wing", {
		"player_id": player_id,
		"wing_id": wing_id,
		"cost": cost,
	}, "purchase", "wing", wing_id)


func buy_weapon_server(player_id: int, weapon_id: int, cost: int) -> void:
	_send_post("/buy_weapon", {
		"player_id": player_id,
		"weapon_id": weapon_id,
		"cost": cost,
	}, "purchase", "weapon", weapon_id)


func grant_match_reward(player_id: int, amount: int) -> void:
	if player_id <= 0 or amount <= 0:
		match_reward_completed.emit(false, amount, 0)
		return
	_send_post("/match_reward", {
		"player_id": player_id,
		"amount": amount,
	}, "match_reward")


func load_player_profile(player_id: int) -> void:
	if player_id <= 0:
		profile_loaded.emit(false, player_id, 0, [], [])
		return
	http_request_queue.append({
		"path": "/profile?player_id=%d" % player_id,
		"payload": {},
		"method": HTTPClient.METHOD_GET,
		"request_type": "profile",
		"purchase_type": "",
		"item_id": 0,
		"player_id": player_id,
	})
	_start_next_http_request()


func _send_post(path: String, payload: Dictionary, request_type: String, purchase_type := "", item_id := 0) -> void:
	http_request_queue.append({
		"path": path,
		"payload": payload,
		"method": HTTPClient.METHOD_POST,
		"request_type": request_type,
		"purchase_type": purchase_type,
		"item_id": item_id,
		"player_id": int(payload.get("player_id", 0)),
	})
	_start_next_http_request()


func _start_next_http_request() -> void:
	if http_request_busy or http_request_queue.is_empty():
		return
	current_http_request = http_request_queue.pop_front()
	http_request_busy = true
	var headers := PackedStringArray(["Content-Type: application/json"])
	var request_method := int(current_http_request["method"])
	var request_body := "" if request_method == HTTPClient.METHOD_GET else JSON.stringify(current_http_request["payload"])
	var error := http_request.request(api_base_url + String(current_http_request["path"]), headers, request_method, request_body)
	if error != OK:
		http_request_busy = false
		_emit_http_failure(current_http_request)
		current_http_request.clear()
		_start_next_http_request()


func _on_http_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var request := current_http_request
	http_request_busy = false
	current_http_request = {}
	var response: Variant = JSON.parse_string(body.get_string_from_utf8())
	var success := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	if not response is Dictionary or not bool(response.get("success", false)):
		success = false
	if request["request_type"] == "register":
		var player_id := int(response.get("player_id", 0)) if response is Dictionary else 0
		registration_completed.emit(success and player_id > 0, player_id if success else 0)
	elif request["request_type"] == "profile":
		var player_id := int(request["player_id"])
		var sky_shards := int(response.get("sky_shards", 0)) if response is Dictionary else 0
		var wings_value: Variant = response.get("unlocked_wings", []) if response is Dictionary else []
		var weapons_value: Variant = response.get("unlocked_weapons", []) if response is Dictionary else []
		var unlocked_wings: Array = wings_value if wings_value is Array else []
		var unlocked_weapons: Array = weapons_value if weapons_value is Array else []
		profile_loaded.emit(success, player_id, sky_shards if success else 0, unlocked_wings if success else [], unlocked_weapons if success else [])
	elif request["request_type"] == "purchase":
		var new_shards := int(response.get("new_shards", 0)) if response is Dictionary else 0
		purchase_completed.emit(success, String(request["purchase_type"]), int(request["item_id"]), new_shards if success else 0)
	elif request["request_type"] == "match_reward":
		var awarded := int(request["payload"].get("amount", 0))
		var new_shards := int(response.get("new_shards", 0)) if response is Dictionary else 0
		match_reward_completed.emit(success, awarded, new_shards if success else 0)
	_start_next_http_request()


func _emit_http_failure(request: Dictionary) -> void:
	if request["request_type"] == "register":
		registration_completed.emit(false, 0)
	elif request["request_type"] == "profile":
		profile_loaded.emit(false, int(request["player_id"]), 0, [], [])
	elif request["request_type"] == "purchase":
		purchase_completed.emit(false, String(request["purchase_type"]), int(request["item_id"]), 0)
	elif request["request_type"] == "match_reward":
		match_reward_completed.emit(false, int(request["payload"].get("amount", 0)), 0)

func connect_and_join(hero_class: int) -> Error:
	current_class = hero_class
	players_list_received = false
	peer = WebSocketMultiplayerPeer.new()
	print("=== ПОПЫТКА ПОДКЛЮЧЕНИЯ К СЕРВЕРУ ===")
	var err = peer.create_client("wss://three-skies-server.relaxdev.ru/ws")
	if err != OK:
		print("=== ОШИБКА СОЗДАНИЯ КЛИЕНТА: ", err, " ===")
		connection_failed.emit()
		return err
	
	multiplayer.multiplayer_peer = peer
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK

func _on_connected() -> void:
	print("=== ПОДКЛЮЧЕНО К СЕРВЕРУ ===")
	rpc_id(1, "join_queue", current_class)
	connected.emit()
	get_tree().create_timer(1.0).timeout.connect(_emit_empty_players_list_if_missing)


func _emit_empty_players_list_if_missing() -> void:
	if not players_list_received:
		players_list_received = true
		players_list.emit([])


@rpc("authority")
func receive_players_list(players: Array) -> void:
	players_list_received = true
	players_list.emit(players)

func _on_connection_failed() -> void:
	print("=== ОШИБКА ПОДКЛЮЧЕНИЯ К СЕРВЕРУ ===")
	connection_failed.emit()

func _on_server_disconnected() -> void:
	print("=== СЕРВЕР ОТКЛЮЧЕН ===")
	connection_failed.emit()

@rpc("authority")
func start_match() -> void:
	print("=== МАТЧ НАЙДЕН! СЕРВЕР ДАЛ КОМАНДУ НА СТАРТ ===")
	match_started.emit()

@rpc("any_peer")
func join_queue(hero_class: int) -> void:
	# Эта функция нужна только для того, чтобы Godot разрешил клиенту отправить RPC на сервер.
	# Клиент сам её не вызывает.
	pass
