extends Node3D

## HP desync probe.
##
## Compares the real state (`health` / `max_health`) of the player, bots and
## remote bot snapshots with everything that draws it:
##   * HUD player panel (number text and ProgressBar value/max),
##   * the 3D health bar above a hero (`fill_ratio` shader parameter),
##   * RemotePlayer bot bars fed by server snapshots.
##
## Covers damage, heal, field regen, base heal, +max HP shop item, an
## authoritative max-HP-only sync, death and respawn. Prints PASS/FAIL and
## exits non-zero when anything diverges.

const TOL := 0.004

var failures := 0
var checks := 0
var game: Node = null
var hud: Node = null
var player: HeroUnit = null


func _ready() -> void:
	var packed := load("res://scenes/Main.tscn") as PackedScene
	game = packed.instantiate()
	add_child(game)
	for i in 14:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	for i in 6:
		await get_tree().process_frame
	hud = game.get("hud")
	player = game.get("player") as HeroUnit
	if hud == null or player == null:
		print("FAIL: no HUD or player")
		get_tree().quit(1)
		return

	await _case_initial()
	await _case_damage_and_heal()
	await _case_max_health_item()
	await _case_max_only_sync()
	await _case_death_and_respawn()
	await _case_base_heal()
	await _case_field_regen()
	await _case_bot_damage()
	await _case_bot_field_regen()
	await _case_bot_death_and_respawn()
	await _case_remote_bot_snapshots()

	print("HP_DESYNC_CHECKS=%d FAILURES=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _case_initial() -> void:
	print("--- initial ---")
	await _check_hud("initial")
	_check_bar(player, "initial")


func _case_damage_and_heal() -> void:
	print("--- damage / heal ---")
	# Leave the base shield: damage at the spawn point is intentionally ignored.
	player.global_position = Vector3(0.0, 0.76, 0.0)
	player.spawn_protection = 0.0
	player.health = player.max_health
	player._update_health_display()
	player.take_damage(260.0, null)
	await _check_hud("after 260 damage")
	_check_bar(player, "after 260 damage")
	player.heal(75.0)
	await _check_hud("after 75 heal")
	_check_bar(player, "after 75 heal")


func _case_max_health_item() -> void:
	print("--- +max HP item ---")
	player.apply_shop_item("life_amulet")
	await _check_hud("after life_amulet")
	_check_bar(player, "after life_amulet")


func _case_max_only_sync() -> void:
	print("--- authoritative max-HP-only sync ---")
	var old_max := player.max_health
	var new_max := maxf(1.0, old_max - 100.0)
	# The server owns max HP; health is already identical, only the cap moves.
	player.apply_network_sync(player.health, new_max, true)
	_check(
		is_equal_approx(player.max_health, new_max),
		"max-only sync updated max_health to %.0f" % new_max
	)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_bar(player, "after max-only sync")
	await _check_hud("after max-only sync")
	player.max_health = old_max
	player._update_health_display()


func _case_death_and_respawn() -> void:
	print("--- death / respawn ---")
	player.global_position = Vector3(0.0, 0.76, 0.0)
	player.spawn_protection = 0.0
	player.health = 120.0
	player._update_health_display()
	player.take_damage(99999.0, null)
	_check(player.dead, "player is dead after lethal hit")
	_check(is_zero_approx(player.health), "player health is 0 after lethal hit")
	_check(not _bar_visible(player), "player 3D bar hidden while dead")
	await _check_hud("dead")
	player.respawn_timer = 0.05
	await get_tree().create_timer(0.3).timeout
	_check(not player.dead, "player respawned")
	_check(is_equal_approx(player.health, player.max_health), "player respawned at full HP")
	_check(_bar_visible(player), "player 3D bar visible after respawn")
	_check_bar(player, "after respawn")
	await _check_hud("after respawn")


func _case_base_heal() -> void:
	print("--- base heal ---")
	player.set_physics_process(false)
	player.dead = false
	player.health = player.max_health * 0.25
	player.seconds_since_damage = 1.0
	player.base_stand_timer = 3.0
	player.base_heal_tick = 0.0
	player.global_position = Vector3(0.0, 0.76, game.BASE_POSITION_Z)
	player._update_health_display()
	var before := player.health
	player._physics_process(0.5)
	_check(player.health > before, "base heal raised health %.0f -> %.0f" % [before, player.health])
	_check_bar(player, "after base heal")
	await _check_hud("after base heal")
	player.set_physics_process(true)


func _case_field_regen() -> void:
	print("--- field regen ---")
	player.set_physics_process(false)
	player.dead = false
	player.global_position = Vector3(0.0, 0.76, 0.0)
	player.spawn_protection = 0.0
	player.health = player.max_health * 0.4
	player.seconds_since_damage = 5.0
	player.base_stand_timer = 0.0
	player.base_heal_tick = 0.0
	player._update_health_display()
	var ratio_before := _hero_bar_ratio(player)
	var before := player.health
	player._physics_process(1.0)
	var expected := player.health / player.max_health
	_check(
		player.health > before,
		"field regen raised health %.0f -> %.0f" % [before, player.health]
	)
	await get_tree().process_frame
	_check(
		absf(_hero_bar_ratio(player) - expected) <= TOL,
		"field regen 3D bar %.3f == health/max %.3f (was %.3f)" % [
			_hero_bar_ratio(player), expected, ratio_before
		]
	)
	await _check_hud("after field regen")
	player.set_physics_process(true)


func _case_bot_damage() -> void:
	print("--- bot damage ---")
	# Stop all hero physics so only the scripted damage moves bot HP; the
	# player's auto-attack would otherwise hit the test bot from 2 m away.
	for hero in game.heroes:
		if hero is HeroUnit:
			hero.set_physics_process(false)
	var bot := _enemy_bot()
	if bot == null:
		_check(false, "enemy bot exists")
		return
	bot.set_physics_process(false)
	bot.global_position = Vector3(2.0, 0.76, 0.0)
	bot.spawn_protection = 0.0
	bot.set_occluded_from_player(false)
	bot.health = bot.max_health
	bot._update_health_display()
	bot.take_damage(200.0, null)
	_check_bar(bot, "bot after 200 damage")
	bot.set_physics_process(true)


func _case_bot_field_regen() -> void:
	print("--- bot field regen ---")
	var bot := _enemy_bot()
	if bot == null:
		_check(false, "enemy bot exists")
		return
	bot.set_physics_process(false)
	bot.global_position = Vector3(2.0, 0.76, 0.0)
	bot.spawn_protection = 0.0
	bot.set_occluded_from_player(false)
	bot.health = bot.max_health * 0.4
	bot.seconds_since_damage = 5.0
	bot.base_stand_timer = 0.0
	bot.base_heal_tick = 0.0
	bot._update_health_display()
	var before := bot.health
	bot._physics_process(1.0)
	var expected := bot.health / bot.max_health
	_check(
		bot.health > before,
		"bot field regen raised health %.0f -> %.0f" % [before, bot.health]
	)
	await get_tree().process_frame
	_check(
		absf(_hero_bar_ratio(bot) - expected) <= TOL,
		"bot field regen 3D bar %.3f == health/max %.3f" % [_hero_bar_ratio(bot), expected]
	)
	bot.set_physics_process(true)


func _case_bot_death_and_respawn() -> void:
	print("--- bot death / respawn ---")
	var bot := _enemy_bot()
	if bot == null:
		_check(false, "enemy bot exists")
		return
	bot.set_physics_process(false)
	bot.global_position = Vector3(2.0, 0.76, 0.0)
	bot.spawn_protection = 0.0
	bot.set_occluded_from_player(false)
	bot.health = bot.max_health
	bot._update_health_display()
	bot.take_damage(999999.0, null)
	_check(bot.dead, "bot is dead after lethal hit")
	_check(not _bar_visible(bot), "bot 3D bar hidden while dead")
	bot.respawn_timer = 0.05
	bot._physics_process(0.1)
	bot.set_occluded_from_player(false)
	_check(not bot.dead, "bot respawned")
	_check(is_equal_approx(bot.health, bot.max_health), "bot respawned at full HP")
	_check(_bar_visible(bot), "bot 3D bar visible after respawn")
	_check_bar(bot, "bot after respawn")
	bot.set_physics_process(true)


func _case_remote_bot_snapshots() -> void:
	print("--- remote bot snapshots ---")
	var remote := preload("res://scripts/remote_player.gd").new()
	remote.name = "RemoteBotProbe"
	game.add_child(remote)
	remote.game = game
	remote.setup(-9001, {
		"name": "ProbeBot",
		"class": HeroUnit.Cls.WARRIOR,
		"team": 1,
		"max_hp": 1050.0,
		"hp": 1050.0,
	})
	await get_tree().process_frame
	_check(is_equal_approx(remote.health, 1050.0), "remote bot starts at 1050 HP")
	_check_remote_bar(remote, "remote initial")
	var snapshots := [
		[1050.0, 900.0],
		[1050.0, 700.0],
		[1050.0, 351.0],
		[1050.0, 1050.0],
		[1200.0, 800.0],
		[1200.0, 1200.0],
		[840.0, 420.0],
	]
	for snapshot in snapshots:
		remote.apply_bot_state({
			"max_hp": float(snapshot[0]),
			"hp": float(snapshot[1]),
			"alive": true,
			"x": 2.0,
			"y": 0.76,
			"z": 0.0,
			"rotation": 0.0,
		})
		_check_remote_bar(remote, "remote %d/%d" % [int(snapshot[1]), int(snapshot[0])])
	remote.apply_bot_state({
		"max_hp": 840.0,
		"hp": 0.0,
		"alive": false,
		"x": 2.0,
		"y": 0.76,
		"z": 0.0,
		"rotation": 0.0,
	})
	_check(remote.dead, "remote bot dead from alive=false snapshot")
	_check(not _bar_visible(remote), "remote bot bar hidden while dead")
	remote.apply_bot_state({
		"max_hp": 840.0,
		"hp": 840.0,
		"alive": true,
		"x": 2.0,
		"y": 0.76,
		"z": 0.0,
		"rotation": 0.0,
	})
	_check(not remote.dead, "remote bot respawned from alive=true snapshot")
	_check_remote_bar(remote, "remote after respawn")
	remote.queue_free()


func _enemy_bot() -> HeroUnit:
	var heroes: Array = game.get("heroes")
	for hero in heroes:
		if hero is HeroUnit and not hero.is_player and hero.team != player.team and not hero.dead:
			return hero
	return null


func _check_hud(label: String) -> void:
	# The HP card must be current on the very next rendered frames, not on a
	# 10 Hz panel tick: the 3D bar already is, and the two must not disagree.
	await get_tree().process_frame
	await get_tree().process_frame
	var bar: ProgressBar = hud.get("player_hp_bar")
	var text_label: Label = hud.get("player_hp_label")
	if bar == null or text_label == null:
		_check(false, "%s: HUD HP widgets exist" % label)
		return
	var expected_max := maxf(1.0, player.max_health)
	var expected_value := clampf(player.health, 0.0, expected_max)
	var expected_ratio := expected_value / expected_max
	var got_ratio := bar.value / maxf(1.0, bar.max_value)
	_check(
		absf(bar.max_value - expected_max) <= 0.01,
		"%s: HUD bar max %.1f == max_health %.1f" % [label, bar.max_value, expected_max]
	)
	_check(
		absf(bar.value - expected_value) <= 0.51,
		"%s: HUD bar value %.1f == health %.1f" % [label, bar.value, expected_value]
	)
	_check(
		absf(got_ratio - expected_ratio) <= TOL,
		"%s: HUD bar ratio %.3f == health/max %.3f" % [label, got_ratio, expected_ratio]
	)
	var parts := text_label.text.split("/")
	_check(parts.size() == 2, "%s: HUD text has hp/max (%s)" % [label, text_label.text])
	if parts.size() == 2:
		var shown_hp := int(parts[0].strip_edges())
		var shown_max := int(parts[1].strip_edges())
		_check(
			shown_hp == roundi(expected_value),
			"%s: HUD text hp %d == health %d" % [label, shown_hp, roundi(expected_value)]
		)
		_check(
			shown_max == roundi(player.max_health),
			"%s: HUD text max %d == max_health %d" % [label, shown_max, roundi(player.max_health)]
		)


func _check_bar(hero: HeroUnit, label: String) -> void:
	var expected := 0.0
	if hero.max_health > 0.0:
		expected = clampf(hero.health / hero.max_health, 0.0, 1.0)
	var got := _hero_bar_ratio(hero)
	_check(
		absf(got - expected) <= TOL,
		"%s: 3D bar %.3f == health/max %.3f (hp %.1f/%.1f)" % [
			label, got, expected, hero.health, hero.max_health
		]
	)
	if hero.dead:
		_check(not _bar_visible(hero), "%s: 3D bar hidden while dead" % label)


func _check_remote_bar(remote: Node, label: String) -> void:
	var expected := 0.0
	if float(remote.get("max_health")) > 0.0:
		expected = clampf(float(remote.get("health")) / float(remote.get("max_health")), 0.0, 1.0)
	var bar := remote.get("_health_back") as MeshInstance3D
	var got := _bar_ratio(bar)
	_check(
		absf(got - expected) <= TOL,
		"%s: remote 3D bar %.3f == health/max %.3f (hp %.1f/%.1f)" % [
			label, got, expected, float(remote.get("health")), float(remote.get("max_health"))
		]
	)


func _hero_bar_ratio(hero: HeroUnit) -> float:
	return _bar_ratio(hero.get("health_back") as MeshInstance3D)


func _bar_ratio(bar: MeshInstance3D) -> float:
	if bar == null or not is_instance_valid(bar):
		return -1.0
	var material := bar.material_override as ShaderMaterial
	if material == null:
		return -1.0
	return float(material.get_shader_parameter("fill_ratio"))


func _bar_visible(hero: Node) -> bool:
	var bar := hero.get("health_back") as MeshInstance3D
	return bar != null and is_instance_valid(bar) and bar.visible


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
