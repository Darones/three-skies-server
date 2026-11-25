extends Node3D

## Stage 1 tutorial combat contract: fixed 10 damage, HP floor at 1, a
## stationary Huntress duel, 2v2/3v3 compositions, one-shot bots and the base
## push-out. Normal matches are not touched.

var failures := 0


func _ready() -> void:
	get_tree().set_meta("tutorial_mode", true)
	get_tree().set_meta("selected_class", HeroUnit.Cls.WARRIOR)
	get_tree().set_meta("selected_team", 0)
	var game := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	for i in 12:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	for i in 4:
		await get_tree().process_frame
	var tutorial: Node = game.get("tutorial_controller")
	_check(tutorial != null, "tutorial controller created")
	if tutorial == null:
		_finish()
		return
	var player: HeroUnit = game.player
	_check(player.hero_class == HeroUnit.Cls.WARRIOR, "tutorial player is the Warrior")

	# 1.1: exactly 10 damage per hit, HP floor at 1, no death.
	player.global_position = Vector3(0.0, 0.76, 0.0)
	player.health = player.max_health
	player.take_damage(999.0, null)
	_check(player.health == player.max_health - 10.0, "player takes exactly 10 damage")
	player.health = 11.0
	player.take_damage(999.0, null)
	_check(player.health == 1.0, "player HP floors at 1")
	player.take_damage(999.0, null)
	_check(player.health == 1.0 and not player.dead, "player cannot die in the tutorial")
	player.health = player.max_health

	# 1.2: duel is a stationary Huntress with training HP.
	tutorial.set("stage", "reach_center")
	tutorial.call("_start_duel")
	await get_tree().process_frame
	var duel_enemy: HeroUnit = null
	for bot in game.tutorial_bots:
		if bot.team != player.team:
			duel_enemy = bot
	_check(duel_enemy != null, "duel spawns one enemy")
	if duel_enemy != null:
		_check(duel_enemy.hero_class == HeroUnit.Cls.FAIRY, "duel enemy is the Huntress")
		_check(duel_enemy.tutorial_stationary, "duel Huntress is stationary")
		_check(duel_enemy.move_speed == 0.0, "duel Huntress cannot walk")
		_check(duel_enemy.attack_damage == 10.0, "duel Huntress shoots for 10")
		_check(duel_enemy.max_health == 120.0, "duel Huntress has training HP")
		duel_enemy.take_damage(99999.0, player)
		await get_tree().create_timer(1.2).timeout
		_check(not game.heroes.has(duel_enemy), "killed duel bot leaves the hero list")
		_check(not game.tutorial_bots.has(duel_enemy), "killed duel bot leaves the tutorial list")
		_check(not is_instance_valid(duel_enemy) or duel_enemy.respawn_timer > 100.0, "duel bot has no respawn timer")
	_check(String(tutorial.get("stage")) == "duel_done", "duel completes on the kill")

	# 1.3: 2v2 is Warrior + Huntress vs Mage + Huntress, 60 seconds.
	tutorial.set("stage", "team_fight_intro")
	tutorial.call("_start_team_fight")
	await get_tree().process_frame
	var pair_allies: Array[HeroUnit] = []
	var pair_enemies: Array[HeroUnit] = []
	for bot in game.tutorial_bots:
		if bot.team == player.team:
			pair_allies.append(bot)
		else:
			pair_enemies.append(bot)
	_check(pair_allies.size() == 1 and pair_allies[0].hero_class == HeroUnit.Cls.FAIRY, "2v2 ally is the Huntress")
	_check(pair_enemies.size() == 2, "2v2 has two enemies")
	if pair_enemies.size() == 2:
		var pair_classes := [pair_enemies[0].hero_class, pair_enemies[1].hero_class]
		pair_classes.sort()
		_check(pair_classes == [HeroUnit.Cls.MAGE, HeroUnit.Cls.FAIRY], "2v2 enemies are Mage + Huntress")
	if pair_allies.size() == 1:
		var ally := pair_allies[0]
		ally.global_position = Vector3(0.0, 0.76, 0.0)
		ally.health = 5.0
		ally.take_damage(999.0, pair_enemies[0] if not pair_enemies.is_empty() else null)
		_check(ally.health == 1.0 and not ally.dead, "2v2 ally HP floors at 1 and does not die")
	_check(float(tutorial.get("stage_timer")) > 59.0 and float(tutorial.get("stage_timer")) <= 60.0, "2v2 timer is 60s")

	# 1.4/1.5: 3v3 composition, short spawn hold and base push-out.
	tutorial.set("stage", "team_fight_done")
	tutorial.call("_start_team_fight_final")
	await get_tree().process_frame
	var final_allies: Array[HeroUnit] = []
	var final_enemies: Array[HeroUnit] = []
	for bot in game.tutorial_bots:
		if bot.team == player.team:
			final_allies.append(bot)
		else:
			final_enemies.append(bot)
	_check(final_allies.size() == 2 and final_enemies.size() == 3, "3v3 has two allies and three enemies")
	var ally_classes: Array[int] = []
	for bot in final_allies:
		ally_classes.append(bot.hero_class)
	ally_classes.sort()
	_check(ally_classes == [HeroUnit.Cls.MAGE, HeroUnit.Cls.FAIRY], "3v3 allies are Mage + Huntress")
	var enemy_classes: Array[int] = []
	for bot in final_enemies:
		enemy_classes.append(bot.hero_class)
	enemy_classes.sort()
	_check(
		enemy_classes == [HeroUnit.Cls.WARRIOR, HeroUnit.Cls.MAGE, HeroUnit.Cls.FAIRY],
		"3v3 enemies are Warrior + Mage + Huntress"
	)
	_check(float(tutorial.get("final_wave_release_timer")) > 1.0, "3v3 spawns hold for at most 1.5s")
	if not final_enemies.is_empty():
		var base_enemy := final_enemies[0]
		var base_z: float = -game.BASE_POSITION_Z if base_enemy.team == 0 else game.BASE_POSITION_Z
		base_enemy.global_position = Vector3(0.0, 0.76, base_z + 2.0)
		await get_tree().create_timer(2.2).timeout
		_check(not base_enemy._is_at_own_base(), "enemy is pushed out of its own base")
		base_enemy.take_damage(99999.0, player)
		await get_tree().create_timer(1.2).timeout
		_check(not is_instance_valid(base_enemy) or not game.heroes.has(base_enemy), "killed 3v3 enemy does not respawn")

	# 1.6: the timeout is a pass, removes bots and heals the player.
	player.health = 1.0
	tutorial.set("stage", "team_fight_final")
	tutorial.set("stage_timer", 0.05)
	await get_tree().create_timer(0.3).timeout
	_check(String(tutorial.get("stage")) == "team_fight_final_done", "3v3 timeout passes the stage")
	_check(player.health == player.max_health, "timeout heals the player")
	_check(game.tutorial_bots.is_empty(), "timeout removes the bots")

	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _finish() -> void:
	print("TUTORIAL_COMBAT_FAILURES=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
