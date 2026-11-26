extends Node3D

## Bot respawn probe.
##
## Puts the player on a base, kills a bot, waits for its respawn and checks:
##   * the bot is alive and at full HP,
##   * it respawned on its own base,
##   * it is at least 2.5 m away from the player standing there,
##   * a respawn with nobody on the base still uses the old spread point,
##   * the network-host respawn path (`_on_bot_state_updated`) obeys the same
##     clearance,
##   * the player's own respawn is untouched.
##
## Prints PASS/FAIL and exits non-zero when anything diverges.

const CLEARANCE := 2.5
const BASE_RADIUS := 4.4
const BASE_POSITION_Z := 28.0

var failures := 0
var checks := 0
var game: Node = null
var player: HeroUnit = null


func _ready() -> void:
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		print("FAIL: Main.tscn did not load")
		get_tree().quit(1)
		return
	game = packed.instantiate()
	add_child(game)
	for i in 14:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	for i in 6:
		await get_tree().process_frame
	player = game.get("player") as HeroUnit
	if player == null or not is_instance_valid(player):
		print("FAIL: no player")
		get_tree().quit(1)
		return
	# The probe drives every timer itself: live physics would let the bots walk
	# away (or fight) between the scripted steps.
	for hero in game.get("heroes"):
		if hero is HeroUnit:
			(hero as HeroUnit).set_physics_process(false)

	await _case_respawn_far_from_player()
	await _case_ally_bot_next_to_player()
	await _case_enemy_bot_next_to_player()
	await _case_network_host_bot()
	await _case_player_respawn_unchanged()

	print("BOT_RESPAWN_CHECKS=%d FAILURES=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _case_respawn_far_from_player() -> void:
	print("--- respawn with nobody on the base ---")
	var bot := _ally_bot()
	if bot == null:
		_check(false, "ally bot exists")
		return
	_move_player(Vector3(0.0, 0.76, 0.0))
	bot.ai_offset = Vector3(2.0, 0.0, 1.0)
	_kill_bot(bot)
	bot._physics_process(0.1)
	_check(not bot.dead, "far: bot respawned")
	var expected := Vector3(2.0, 0.0, _base_z(bot.team) + 1.0)
	_check(
		_planar(bot.global_position).distance_to(_planar(expected)) <= 0.05,
		"far: respawn kept the old spread point (got %s, want %s)" % [
			_planar(bot.global_position), _planar(expected)
		]
	)
	_check(_on_own_base(bot), "far: bot is on its own base")


func _case_ally_bot_next_to_player() -> void:
	print("--- ally bot respawns where the player stands ---")
	var bot := _ally_bot()
	if bot == null:
		_check(false, "ally bot exists")
		return
	_move_player(_base_center(player.team))
	# Zero offset => the bot's own base point is exactly the player's point.
	bot.ai_offset = Vector3.ZERO
	_kill_bot(bot)
	_check(bot.dead, "ally: bot is dead before respawn")
	bot._physics_process(0.1)
	_check(not bot.dead, "ally: bot respawned")
	_check(is_equal_approx(bot.health, bot.max_health), "ally: bot respawned at full HP")
	_check(_on_own_base(bot), "ally: bot respawned on its own base (%.2f m from center)" % _base_distance(bot))
	var distance := _distance_to_player(bot)
	_check(distance >= CLEARANCE, "ally: distance to player %.2f m >= %.1f m" % [distance, CLEARANCE])


func _case_enemy_bot_next_to_player() -> void:
	print("--- enemy bot respawns where the player stands ---")
	var bot := _enemy_bot()
	if bot == null:
		_check(false, "enemy bot exists")
		return
	# Player walks onto the enemy base in this scripted case.
	_move_player(_base_center(bot.team))
	bot.ai_offset = Vector3.ZERO
	_kill_bot(bot)
	bot._physics_process(0.1)
	_check(not bot.dead, "enemy: bot respawned")
	_check(_on_own_base(bot), "enemy: bot respawned on its own base")
	var distance := _distance_to_player(bot)
	_check(distance >= CLEARANCE, "enemy: distance to player %.2f m >= %.1f m" % [distance, CLEARANCE])


func _case_network_host_bot() -> void:
	print("--- network-host bot respawn uses the same guard ---")
	var bot := _ally_bot()
	if bot == null:
		_check(false, "ally bot exists")
		return
	_move_player(_base_center(player.team))
	bot.network_id = -9101
	bot.ai_offset = Vector3.ZERO
	_kill_bot(bot)
	var old_protocol := int(NetworkManager.server_protocol)
	NetworkManager.server_protocol = 3
	game.network_play = true
	game.network_host = true
	game.get("network_bots")[bot.network_id] = bot
	game.call("_on_bot_state_updated", bot.network_id, {
		"max_hp": bot.max_health,
		"hp": bot.max_health,
		"alive": true,
	})
	game.network_play = false
	game.network_host = false
	NetworkManager.server_protocol = old_protocol
	game.get("network_bots").erase(bot.network_id)
	bot.network_id = -1
	_check(not bot.dead, "network host: bot respawned from alive=true snapshot")
	_check(_on_own_base(bot), "network host: bot respawned on its own base")
	var distance := _distance_to_player(bot)
	_check(distance >= CLEARANCE, "network host: distance to player %.2f m >= %.1f m" % [distance, CLEARANCE])


func _case_player_respawn_unchanged() -> void:
	print("--- player respawn is untouched ---")
	_move_player(Vector3(0.0, 0.76, 0.0))
	player.dead = false
	player.health = player.max_health
	player.spawn_protection = 0.0
	player.take_damage(999999.0, null)
	_check(player.dead, "player: dead after a lethal hit")
	player.respawn_timer = 0.01
	player._physics_process(0.1)
	_check(not player.dead, "player: respawned")
	var base_z := _base_z(player.team)
	var base_distance := _planar_distance(player.global_position, Vector3(0.0, 0.0, base_z))
	_check(base_distance <= BASE_RADIUS, "player: respawn is on the own base (%.2f m)" % base_distance)
	var expected := Vector3(
		clampf(player.ai_offset.x, -3.0, 3.0),
		0.0,
		base_z + clampf(player.ai_offset.z, -1.5, 1.5)
	)
	_check(
		_planar(player.global_position).distance_to(_planar(expected)) <= 0.05,
		"player: respawn point is the old spread point (got %s, want %s)" % [
			_planar(player.global_position), _planar(expected)
		]
	)


func _kill_bot(bot: HeroUnit) -> void:
	if bot.dead:
		bot.dead = false
		bot.health = bot.max_health
		bot.set_collision_layer_value(1, true)
		bot.set_collision_mask_value(1, true)
	# The base dome blocks damage: die in the middle of the arena, then respawn.
	bot.global_position = Vector3(0.0, 0.76, 0.0)
	bot.spawn_protection = 0.0
	bot.health = bot.max_health
	bot.take_damage(999999.0, null)
	bot.respawn_timer = 0.01


func _move_player(position: Vector3) -> void:
	player.dead = false
	player.health = player.max_health
	player.global_position = Vector3(position.x, 0.76, position.z)
	player.velocity = Vector3.ZERO


func _ally_bot() -> HeroUnit:
	for hero in game.get("heroes"):
		if hero is HeroUnit:
			var unit := hero as HeroUnit
			if unit != player and not unit.is_player and unit.team == player.team:
				return unit
	return null


func _enemy_bot() -> HeroUnit:
	for hero in game.get("heroes"):
		if hero is HeroUnit:
			var unit := hero as HeroUnit
			if unit != player and not unit.is_player and unit.team != player.team:
				return unit
	return null


func _base_z(team: int) -> float:
	return BASE_POSITION_Z if team == 0 else -BASE_POSITION_Z


func _base_center(team: int) -> Vector3:
	return Vector3(0.0, 0.76, _base_z(team))


func _base_distance(hero: HeroUnit) -> float:
	return _planar_distance(hero.global_position, Vector3(0.0, 0.0, _base_z(hero.team)))


func _on_own_base(hero: HeroUnit) -> bool:
	return _base_distance(hero) <= BASE_RADIUS + 0.01


func _distance_to_player(hero: HeroUnit) -> float:
	return _planar_distance(hero.global_position, player.global_position)


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _planar(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
