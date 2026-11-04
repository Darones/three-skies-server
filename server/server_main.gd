extends Node

var peer: WebSocketMultiplayerPeer
var players_queue: Array = []
var timer_started: bool = false
var match_timer: float = 0.0

func _ready():
	print("=== SERVER SUCCESSFULLY STARTED ON PORT: ", OS.get_environment("PORT"), " ===")
	var port = int(OS.get_environment("PORT")) if OS.get_environment("PORT") != "" else 9080
	peer = WebSocketMultiplayerPeer.new()
	var err = peer.create_server(port)
	if err != OK:
		print("ERROR: Could not start server: ", err)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Listening for connections...")

func _on_peer_connected(id: int):
	print("Player connected: ", id)

func _on_peer_disconnected(id: int):
	print("Player disconnected: ", id)
	if id in players_queue:
		players_queue.erase(id)

func _process(delta: float) -> void:
	# Логика таймера матчмейкинга
	if players_queue.size() > 0:
		if not timer_started:
			timer_started = true
			match_timer = 2.0 # 2 секунды
			print("Waiting 2 seconds to fill match...")
		else:
			match_timer -= delta
			if match_timer <= 0:
				_start_match()

func _start_match():
	print("Starting match with players: ", players_queue)
	# Отправляем команду старта всем игрокам в очереди
	for id in players_queue:
		rpc_id(id, "start_match")
	# Здесь будет логика заполнения ботами и отправки RPC
	players_queue.clear()
	timer_started = false

# RPC-функция для клиента
@rpc("any_peer")
func join_queue(hero_class: int):
	var sender_id = multiplayer.get_remote_sender_id()
	if not sender_id in players_queue:
		players_queue.append(sender_id)
		print("Player ", sender_id, " joined queue with class ", hero_class)
