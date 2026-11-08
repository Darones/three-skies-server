extends Node

signal match_started
signal connected
signal players_list(players: Array)
signal connection_failed
signal registration_completed(success: bool, player_id: int)
signal purchase_completed(success: bool, new_shards: int)

const API_BASE_URL := "http://127.0.0.1:8080"

var peer: WebSocketMultiplayerPeer
var current_class: int = 1
var http_request: HTTPRequest
var http_request_busy := false
var current_http_request_type := ""
var players_list_received := false


func _ready() -> void:
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
	}, "purchase")


func _send_post(path: String, payload: Dictionary, request_type: String) -> void:
	if http_request_busy:
		_emit_http_failure(request_type)
		return
	http_request_busy = true
	current_http_request_type = request_type
	var headers := PackedStringArray(["Content-Type: application/json"])
	var error := http_request.request(API_BASE_URL + path, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		http_request_busy = false
		current_http_request_type = ""
		_emit_http_failure(request_type)


func _on_http_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var request_type := current_http_request_type
	http_request_busy = false
	current_http_request_type = ""
	var response: Variant = JSON.parse_string(body.get_string_from_utf8())
	var success := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	if not response is Dictionary or not bool(response.get("success", false)):
		success = false
	if request_type == "register":
		var player_id := int(response.get("player_id", 0)) if response is Dictionary else 0
		registration_completed.emit(success and player_id > 0, player_id if success else 0)
	elif request_type == "purchase":
		var new_shards := int(response.get("new_shards", 0)) if response is Dictionary else 0
		purchase_completed.emit(success, new_shards if success else 0)


func _emit_http_failure(request_type: String) -> void:
	if request_type == "register":
		registration_completed.emit(false, 0)
	elif request_type == "purchase":
		purchase_completed.emit(false, 0)

func connect_and_join(hero_class: int) -> Error:
	current_class = hero_class
	players_list_received = false
	peer = WebSocketMultiplayerPeer.new()
	print("=== ПОПЫТКА ПОДКЛЮЧЕНИЯ К СЕРВЕРУ ===")
	var err = peer.create_client("wss://three-skies-server.relaxdev.ru")
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
