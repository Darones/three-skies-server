extends Node3D

## Network desync probe (client side).
##
## Feeds the real NetworkManager message handler with the exact packet orders a
## live match produces, and checks what the RemotePlayer shows:
##   * an older state packet must not undo a confirmed hit or heal,
##   * an older damage/heal must not be applied twice,
##   * a stale state packet must not kill or resurrect after death/respawn,
##   * bot snapshots (guest and host paths) obey the same rules,
##   * stale sync packets may not roll the local player's HP back,
##   * a bot heal echo is not dropped,
##   * legacy servers without HP revisions still get a debounce,
##   * interpolation lag is measured and printed.
##
## Prints PASS/FAIL, a summary and exits non-zero when anything diverges.

const REMOTE_PLAYER := preload("res://scripts/remote_player.gd")
const ENEMY_ID := 200
const BOT_ID := -2
const HOST_BOT_ID := -3

var failures := 0
var checks := 0
var nm: Node = NetworkManager
var remote: Node3D = null
var bot: Node3D = null
var sync_events: Array = []
var host_bot_events: Array = []
var heal_events: Array = []
var death_events: Array = []
var score_events: Array = []


func _ready() -> void:
	nm._handle_message(JSON.stringify({"type": "welcome", "id": 100, "protocol": 4}))
	nm.assigned_team = 0
	nm.is_host = false
	_connect_signals()
	remote = _make_remote(ENEMY_ID, 1, 1050.0)
	bot = _make_remote(BOT_ID, 1, 1000.0)
	bot.is_bot = true
	bot.hero_class = 1

	await _case_baseline()
	await _case_stale_state_after_damage()
	await _case_stale_damage_after_state()
	await _case_death_and_respawn_order()
	await _case_heal_order()
	await _case_bot_snapshot_order()
	await _case_host_bot_snapshot_order()
	await _case_sync_order()
	await _case_bot_heal_echo()
	await _case_legacy_server()
	await _case_protocol_smoke()
	_measure_interpolation()

	print("NET_DESYNC_CHECKS=%d FAILURES=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _make_remote(player_id: int, team: int, max_hp: float) -> Node3D:
	var node := REMOTE_PLAYER.new()
	node.name = "ProbeRemote_%d" % player_id
	add_child(node)
	node.peer_id = player_id
	node.display_name = "Probe %d" % player_id
	node.team = team
	node.max_health = max_hp
	node.health = max_hp
	node.set_process(false)
	return node


func _connect_signals() -> void:
	nm.remote_player_joined.connect(func(player_id: int, _info: Dictionary): pass)
	nm.remote_player_state.connect(_on_state)
	nm.remote_stats_updated.connect(_on_stats)
	nm.remote_damage_received.connect(_on_damage)
	nm.remote_heal_received.connect(_on_heal)
	nm.remote_death_received.connect(_on_death)
	nm.remote_respawn_received.connect(_on_respawn)
	nm.bot_state_updated.connect(_on_bot_state)
	nm.sync_received.connect(func(hp: float, max_hp: float, alive: bool): sync_events.append([hp, max_hp, alive]))
	nm.match_score_updated.connect(func(score_0: int, score_1: int, sudden: bool): score_events.append([score_0, score_1, sudden]))


func _on_state(player_id: int, position: Vector3, rotation_y: float) -> void:
	if player_id == ENEMY_ID and remote != null:
		remote.apply_state(position, rotation_y)


func _on_stats(player_id: int, max_hp: float, hp: float, attack_damage: float) -> void:
	if player_id == ENEMY_ID and remote != null:
		remote.apply_stats(max_hp, hp, attack_damage)


func _on_damage(_source_id: int, target_id: int, amount: float, _skill: String, crit: bool, _stun: float) -> void:
	if target_id == ENEMY_ID and remote != null:
		remote.apply_network_damage(amount, false, crit)
	elif target_id == BOT_ID and bot != null:
		bot.apply_network_damage(amount, false, crit)


func _on_heal(source_id: int, target_id: int, amount: float) -> void:
	heal_events.append([source_id, target_id, amount])
	if target_id == ENEMY_ID and remote != null:
		remote.apply_network_heal(amount)
	elif target_id == BOT_ID and bot != null:
		bot.apply_network_heal(amount)


func _on_death(player_id: int, _source_id: int) -> void:
	death_events.append(player_id)
	if player_id == ENEMY_ID and remote != null:
		remote.apply_network_death()
	elif player_id == BOT_ID and bot != null:
		bot.apply_network_death()


func _on_respawn(player_id: int, position: Vector3, rotation_y: float) -> void:
	if player_id == ENEMY_ID and remote != null:
		remote.apply_network_respawn(position, rotation_y)


func _on_bot_state(bot_id: int, info: Dictionary) -> void:
	if nm.is_host:
		host_bot_events.append([bot_id, float(info.get("hp", 0.0)), bool(info.get("alive", true))])
		return
	if bot_id == BOT_ID and bot != null:
		bot.apply_bot_state(info)


func _feed(message: Dictionary) -> void:
	nm._handle_message(JSON.stringify(message))


func _state(hp: float, alive: bool, tick: int, pos_z := 2.0) -> void:
	_feed({
		"type": "state", "id": ENEMY_ID, "x": 1.0, "y": 0.76, "z": pos_z,
		"rotation": 0.0, "hp": hp, "max_hp": 1050.0, "alive": alive, "tick": tick,
	})


func _damage(amount: float, tick: int, target_id := ENEMY_ID) -> void:
	_feed({"type": "damage", "source_id": 100, "target_id": target_id, "amount": amount, "skill": "auto", "tick": tick})


func _heal(amount: float, tick: int, target_id := ENEMY_ID, source_id := 200) -> void:
	_feed({"type": "heal", "source_id": source_id, "target_id": target_id, "amount": amount, "tick": tick})


func _bot_snapshot(hp: float, alive: bool, tick: int, bot_id := BOT_ID) -> void:
	_feed({"type": "bot_states", "bots": [{
		"id": bot_id, "class": 1, "team": 1, "x": 2.0, "y": 0.76, "z": 1.0,
		"rotation": 0.0, "max_hp": 1000.0, "hp": hp, "attack_damage": 39.0,
		"alive": alive, "animation": "run", "tick": tick,
	}]})


func _case_baseline() -> void:
	print("--- baseline ---")
	_feed({
		"type": "player_joined", "id": ENEMY_ID, "name": "Enemy", "class": 0,
		"team": 1, "hp": 1050.0, "max_hp": 1050.0, "alive": true,
		"has_state": true, "x": 1.0, "y": 0.76, "z": 2.0,
	})
	_state(900.0, true, 2)
	_check(is_equal_approx(remote.health, 900.0), "fresh state applies HP (900)")
	_check(is_equal_approx(remote.max_health, 1050.0), "fresh state keeps max HP (1050)")


func _case_stale_state_after_damage() -> void:
	print("--- stale state after confirmed damage ---")
	_damage(300.0, 3)
	_check(is_equal_approx(remote.health, 600.0), "damage applies exactly once (600)")
	# Older than 600 ms by now: the hit-hold guard must not be what rejects
	# the stale packet, the revision must be.
	remote.last_damage_msec = 0
	_state(900.0, true, 2)
	_check(is_equal_approx(remote.health, 600.0), "older state cannot heal the hit back (600)")
	_state(600.0, true, 4)
	_check(is_equal_approx(remote.health, 600.0), "fresh state matches the hit (600)")
	_state(620.0, true, 5)
	_check(is_equal_approx(remote.health, 620.0), "newer state still applies regen (620)")


func _case_stale_damage_after_state() -> void:
	print("--- stale damage after a state that already contains it ---")
	_state(620.0, true, 6)
	_damage(50.0, 5)
	_check(is_equal_approx(remote.health, 620.0), "older damage is not subtracted twice (620)")


func _case_death_and_respawn_order() -> void:
	print("--- death / respawn ordering ---")
	_damage(620.0, 7)
	_check(remote.dead, "lethal damage kills the remote")
	_check(is_zero_approx(remote.health), "dead remote is at 0 HP")
	_state(620.0, true, 6)
	_check(remote.dead, "older alive=true state cannot resurrect the corpse")
	_feed({"type": "death", "id": ENEMY_ID, "source_id": 100, "tick": 7})
	_check(death_events.size() == 1, "death packet shares the lethal hit revision (got %d)" % death_events.size())
	_state(0.0, false, 8)
	_check(remote.dead, "fresh alive=false state keeps it dead")
	_check(death_events.size() == 1, "death was applied exactly once (got %d)" % death_events.size())
	_feed({"type": "respawn", "id": ENEMY_ID, "x": 0.0, "y": 0.76, "z": 27.5, "rotation": 0.0, "tick": 9})
	_check(not remote.dead, "respawn makes the remote alive")
	_check(is_equal_approx(remote.health, remote.max_health), "respawn restores full HP")
	_state(0.0, false, 8)
	_check(not remote.dead, "older alive=false state cannot kill after respawn")
	_state(1050.0, true, 10)
	_check(not remote.dead and is_equal_approx(remote.health, 1050.0), "newer alive=true state is a no-op")


func _case_heal_order() -> void:
	print("--- heal ordering ---")
	_damage(500.0, 11)
	_check(is_equal_approx(remote.health, 550.0), "damage before heal lands (550)")
	_heal(200.0, 12)
	_check(is_equal_approx(remote.health, 750.0), "heal echo applies once (750)")
	_state(550.0, true, 11)
	_check(is_equal_approx(remote.health, 750.0), "older state cannot undo the heal (750)")
	_state(750.0, true, 13)
	_check(is_equal_approx(remote.health, 750.0), "fresh state matches the heal (750)")
	_heal(200.0, 12)
	_check(is_equal_approx(remote.health, 750.0), "duplicate heal echo is not applied twice (750)")


func _case_bot_snapshot_order() -> void:
	print("--- guest bot snapshots ---")
	nm.is_host = false
	_bot_snapshot(800.0, true, 5)
	_check(is_equal_approx(bot.health, 800.0), "bot snapshot applies HP (800)")
	_damage(200.0, 6, BOT_ID)
	_check(is_equal_approx(bot.health, 600.0), "guest hit applies to the remote bot (600)")
	_bot_snapshot(800.0, true, 5)
	_check(is_equal_approx(bot.health, 600.0), "older bot snapshot cannot heal the hit (600)")
	_damage(600.0, 7, BOT_ID)
	_check(bot.dead, "lethal bot damage kills it")
	_bot_snapshot(600.0, true, 6)
	_check(bot.dead, "older alive=true snapshot cannot resurrect the bot")
	_bot_snapshot(600.0, false, 8)
	_check(bot.dead, "fresh alive=false snapshot keeps it dead")
	_bot_snapshot(1000.0, true, 9)
	_check(not bot.dead and is_equal_approx(bot.health, 1000.0), "newer snapshot respawns the bot")


func _case_host_bot_snapshot_order() -> void:
	print("--- host bot snapshots ---")
	nm.is_host = true
	host_bot_events.clear()
	_bot_snapshot(900.0, true, 20, HOST_BOT_ID)
	_check(host_bot_events.size() == 1, "host applies a fresh bot snapshot")
	_damage(300.0, 21, HOST_BOT_ID)
	_bot_snapshot(900.0, true, 20, HOST_BOT_ID)
	_check(host_bot_events.size() == 1, "host drops an older bot snapshot (no HP rollback)")
	_bot_snapshot(600.0, true, 22, HOST_BOT_ID)
	_check(host_bot_events.size() == 2, "host applies the next fresh bot snapshot")
	nm.is_host = false


func _case_sync_order() -> void:
	print("--- local player sync ordering ---")
	sync_events.clear()
	_damage(200.0, 14, 100)
	_feed({"type": "sync", "hp": 500.0, "max_hp": 1050.0, "alive": true, "tick": 13, "match_time_left_ms": 300000})
	_check(sync_events.is_empty(), "older sync cannot roll the local HP back")
	_feed({"type": "sync", "hp": 500.0, "max_hp": 1050.0, "alive": true, "tick": 15, "match_time_left_ms": 300000})
	_check(sync_events.size() == 1 and is_equal_approx(float(sync_events[0][0]), 500.0), "newer sync applies the server HP")
	# Old servers have no score in sync: it must not wipe a delivered score.
	score_events.clear()
	_feed({"type": "match_score", "score_0": 2, "score_1": 1, "sudden_death": false})
	_feed({"type": "sync", "hp": 500.0, "max_hp": 1050.0, "alive": true, "match_time_left_ms": 300000})
	_check(score_events.size() == 1 and int(score_events[0][0]) == 2, "legacy sync without score does not reset it (2:1)")
	# A dropped match_score must be repaired by the next sync, and the same
	# score must not be re-announced every second.
	score_events.clear()
	_feed({"type": "sync", "hp": 500.0, "max_hp": 1050.0, "alive": true, "tick": 16, "score_0": 1, "score_1": 0, "match_time_left_ms": 299000})
	_check(score_events.size() == 1 and int(score_events[0][0]) == 1, "sync repairs a dropped score (1:0)")
	_feed({"type": "sync", "hp": 500.0, "max_hp": 1050.0, "alive": true, "tick": 17, "score_0": 1, "score_1": 0, "match_time_left_ms": 298000})
	_check(score_events.size() == 1, "unchanged score is not re-announced every second")
	_feed({"type": "sync", "hp": 500.0, "max_hp": 1050.0, "alive": true, "tick": 18, "score_0": 1, "score_1": 1, "sudden_death": true, "match_time_left_ms": 297000})
	_check(score_events.size() == 2 and bool(score_events[1][2]), "sync repair carries score and sudden death (1:1)")


func _case_bot_heal_echo() -> void:
	print("--- bot heal echo ---")
	heal_events.clear()
	_bot_snapshot(400.0, true, 30)
	_heal(100.0, 31, BOT_ID, 100)
	_check(heal_events.size() == 1, "bot heal echo is delivered (got %d)" % heal_events.size())
	_check(is_equal_approx(bot.health, 500.0), "bot heal echo raises the bot HP (500)")


func _case_legacy_server() -> void:
	print("--- legacy server (no revisions) ---")
	var info: Dictionary = nm.remote_players[ENEMY_ID]
	info["hp_tick"] = 0
	remote.apply_network_respawn(Vector3.ZERO, 0.0)
	info["alive"] = true
	info["death_msec"] = 0
	info["respawn_msec"] = 0
	info["alive_pending"] = -1
	info["alive_pending_count"] = 0
	_damage(400.0, 0)
	_check(is_equal_approx(remote.health, 650.0), "legacy damage applies (650)")
	_state(900.0, true, 0)
	_check(is_equal_approx(remote.health, 650.0), "legacy hit-hold stops an immediate HP rollback (650)")
	remote.last_damage_msec = 0
	_feed({"type": "death", "id": ENEMY_ID, "tick": 0})
	_check(remote.dead, "legacy death packet applies")
	# A single stale alive=true sample (no revision) must not resurrect.
	_feed({"type": "state", "id": ENEMY_ID, "x": 0.0, "y": 0.76, "z": 27.5, "rotation": 0.0, "hp": 650.0, "max_hp": 1050.0, "alive": true, "tick": 0})
	_check(remote.dead, "one stale legacy alive=true sample does not resurrect")
	# A genuinely old death timestamp (as after a missed respawn packet) does.
	info["death_msec"] = Time.get_ticks_msec() - 2000
	_feed({"type": "state", "id": ENEMY_ID, "x": 0.0, "y": 0.76, "z": 27.5, "rotation": 0.0, "hp": 1050.0, "max_hp": 1050.0, "alive": true, "tick": 0})
	_feed({"type": "state", "id": ENEMY_ID, "x": 0.0, "y": 0.76, "z": 27.5, "rotation": 0.0, "hp": 1050.0, "max_hp": 1050.0, "alive": true, "tick": 0})
	_check(not remote.dead, "legacy state repairs a missed respawn after the grace")


func _case_protocol_smoke() -> void:
	print("--- protocol smoke (every message type parses) ---")
	var messages := [
		{"type": "room_joined", "room_id": 7, "host_id": 100, "team": 0, "class": 0},
		{"type": "lobby_state", "match_players": [{"id": 100, "team": 0, "class": 0}], "starts_in_ms": 1000},
		{"type": "match_start", "room_id": 7, "host_id": 100, "bot_difficulty": "normal", "match_players": [
			{"id": 100, "team": 0, "class": 0, "bot": false},
			{"id": -4, "team": 1, "class": 1, "bot": true, "name": "Bot", "hp": 1000.0, "max_hp": 1000.0},
		]},
		{"type": "bot_roster", "bots": [{"id": -4, "team": 1, "class": 1, "x": 0.0, "y": 0.76, "z": -27.5, "rotation": 0.0, "max_hp": 1000.0, "hp": 1000.0, "alive": true, "tick": 3}]},
		{"type": "stats", "id": 200, "max_hp": 1200.0, "hp": 1200.0, "attack_damage": 44.0, "tick": 4},
		{"type": "attack", "source_id": 200, "attack_type": "auto", "target_id": 100},
		{"type": "attack_denied", "target_id": 200, "skill": "auto", "reason": "out_of_range"},
		{"type": "shell_state", "shell": {"alive": true, "hp": 900.0, "max_hp": 1000.0, "x": 0.0, "y": 0.45, "z": 0.0, "phase": "active", "timer": 30.0, "spawn_id": 2}},
		{"type": "shell_damage", "amount": 100.0, "source_id": 100},
		{"type": "crystal_state", "crystal": {"state": "ground", "x": 0.0, "y": 0.5, "z": 0.0}},
		{"type": "crystal_sync", "crystal": {"state": "carried", "x": 1.0, "y": 0.5, "z": 2.0, "carrier_id": 100}},
		{"type": "gold", "gold": 250},
		{"type": "shop_purchase", "item_id": "life_amulet", "ok": true, "gold": 150},
		{"type": "match_event", "event": "shard_delivered", "team": 0, "source_id": 100},
		{"type": "match_score", "score_0": 1, "score_1": 0, "sudden_death": false},
		{"type": "match_finished", "winning_team": 0, "score_0": 3, "score_1": 1, "reason": "score"},
		{"type": "host_changed", "host_id": 200},
		{"type": "player_left", "id": 200},
		{"type": "respawn", "id": 200, "x": 0.0, "y": 0.76, "z": 27.5, "rotation": 0.0, "tick": 5},
		{"type": "death", "id": 200, "source_id": 100, "tick": 6},
	]
	for message in messages:
		_feed(message)
	_check(true, "all %d message types handled without a script error" % messages.size())


func _measure_interpolation() -> void:
	var mover: Node3D = _make_remote(999, 1, 1050.0)
	mover.set_process(false)
	mover.global_position = Vector3.ZERO
	var target := Vector3.ZERO
	mover.target_position = target
	mover._has_target = true
	var speed := 7.0
	var update_interval := 1.0 / 12.0
	var frame := 1.0 / 60.0
	var next_update := 0.0
	var elapsed := 0.0
	var samples: Array[float] = []
	while elapsed < 2.0:
		elapsed += frame
		if elapsed >= next_update:
			next_update += update_interval
			target += Vector3(speed * update_interval, 0.0, 0.0)
			mover.apply_state(target, 0.0)
		mover._process(frame)
		if elapsed > 1.0:
			samples.append(Vector2(mover.global_position.x, mover.global_position.z).distance_to(Vector2(target.x, target.z)))
	var worst := 0.0
	var total := 0.0
	for sample in samples:
		worst = maxf(worst, sample)
		total += sample
	var average := total / maxf(1.0, float(samples.size()))
	print("[INTERP] speed=%.1f m/s updates=12Hz rate=14 -> lag avg=%.2f m worst=%.2f m" % [speed, average, worst])
	_check(average < 0.75, "interpolation lag stays below 0.75 m at running speed (avg %.2f m)" % average)
	mover.queue_free()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
