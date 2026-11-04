extends Node

signal match_started

var peer: WebSocketMultiplayerPeer
var current_class: int = 1

func connect_and_join(hero_class: int) -> void:
	current_class = hero_class
	peer = WebSocketMultiplayerPeer.new()
	print("=== ПОПЫТКА ПОДКЛЮЧЕНИЯ К СЕРВЕРУ ===")
	var err = peer.create_client("wss://three-skies-server.relaxdev.ru")
	if err != OK:
		print("=== ОШИБКА СОЗДАНИЯ КЛИЕНТА: ", err, " ===")
		return
	
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_connected() -> void:
	print("=== ПОДКЛЮЧЕНО К СЕРВЕРУ ===")
	rpc_id(1, "join_queue", current_class)

func _on_connection_failed() -> void:
	print("=== ОШИБКА ПОДКЛЮЧЕНИЯ К СЕРВЕРУ ===")

func _on_server_disconnected() -> void:
	print("=== СЕРВЕР ОТКЛЮЧЕН ===")

@rpc("authority")
func start_match() -> void:
	print("=== МАТЧ НАЙДЕН! СЕРВЕР ДАЛ КОМАНДУ НА СТАРТ ===")
	match_started.emit()
