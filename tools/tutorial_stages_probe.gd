extends Node3D

## D1 tutorial pacing check: duel -> fountain -> pair -> 3v3 at the enemy base
## -> separate passive Shell finale. Combat is simulated by direct kills.

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
	for i in 6:
		await get_tree().process_frame
	var tutorial: Node = game.get("tutorial_controller")
	_check(tutorial != null, "tutorial controller created")
	if tutorial == null:
		_finish()
		return
	# Welcome plate: no splash timer, no "Продолжить", no UI tour. The run to
	# the arena center starts at once and the plate stays until the duel is won.
	var welcome_msec := Time.get_ticks_msec()
	var card_overlay: Control = game.hud.get("tutorial_overlay")
	var card_panel: Control = game.hud.get("tutorial_card_panel")
	var card_title: Label = game.hud.get("tutorial_title")
	var card_button: Control = game.hud.get("tutorial_primary_button")
	_check(String(tutorial.get("stage")) == "reach_center", "welcome starts the run-to-center stage immediately")
	_check(
		game.hud.get("tutorial_hint").text == "Беги вперёд — к центру арены"
		and game.hud.get("tutorial_hint").visible,
		"welcome card is followed by the run-to-center hint"
	)
	_check(card_overlay.visible, "welcome plate is visible")
	_check(card_title.text == "Добро пожаловать!", "welcome plate keeps its title")
	_check(not card_button.visible, "welcome plate has no continue button")
	_check(
		card_overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and card_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"welcome plate does not block input"
	)
	_check(game.hud.get("tutorial_skip_button") != null and game.hud.get("tutorial_skip_button").visible, "skip button visible")
	_check(game.hud.find_child("MobilePauseButton", true, false) == null, "old HUD pause button is gone")

	# Longer than the old 2.2 s auto-hide: the plate stays while the player
	# has not reached the center yet; there is no UI tour and no highlight.
	await get_tree().create_timer(2.6).timeout
	_check(String(tutorial.get("stage")) == "reach_center", "run-to-center stage waits for the player")
	_check(card_overlay.visible and card_title.text == "Добро пожаловать!", "welcome plate is still there after 2.6s")
	_check(not game.hud.get("focus_panel").visible, "no UI tour highlight under the welcome plate")
	_check(
		game.hud.get("tutorial_hint").text == "Беги вперёд — к центру арены",
		"run-to-center hint stays under the welcome plate"
	)

	tutorial.set("stage", "reach_center")
	game.player.global_position = Vector3(0.0, 0.76, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(String(tutorial.get("stage")) == "duel", "1v1 stage starts")
	_check(game.tutorial_bots.size() == 1, "duel has one enemy")
	_check(
		card_overlay.visible and card_title.text == "Добро пожаловать!",
		"welcome plate stays during the duel"
	)
	if game.tutorial_bots.size() == 1:
		var duel_bot: HeroUnit = game.tutorial_bots[0]
		_check(duel_bot.bot_difficulty == "easy", "duel bot is easy")
		duel_bot.take_damage(99999.0, game.player)
		await get_tree().process_frame
		_check(String(tutorial.get("stage")) == "duel_done", "duel completes on enemy death")
	_check(game.tutorial_bots.is_empty(), "duel bots are cleared")
	print("WELCOME_VISIBLE_MS=", Time.get_ticks_msec() - welcome_msec)
	_check(
		card_overlay.visible and card_title.text == "Этап 1/3 пройден",
		"stage 1 card replaces the welcome plate"
	)
	_check(not game.hud.get("tutorial_hint").visible, "duel hint is cleared under the stage 1 card")
	await get_tree().create_timer(2.5).timeout
	_check(String(tutorial.get("stage")) == "go_fountain", "fountain stage follows the stage 1 card")
	_check(not card_overlay.visible, "stage 1 card closes by itself")

	# Fountain: coins must spawn in a ring around the fountain, not at the feet.
	game.player.global_position = Vector3(37.0, 0.76, 0.0)
	tutorial.set("stage", "go_fountain")
	tutorial.call("_show_fountain_card")
	tutorial.call("_start_coin_collection")
	await get_tree().create_timer(0.7).timeout
	_check(String(tutorial.get("stage")) == "collect_coins", "fountain coin stage starts")
	_check(game.tutorial_coins_on_ground() == 5, "fountain spawns a batch of five coins")
	var fountain_distance := 0.0
	if game.gold_coins.size() > 0 and is_instance_valid(game.gold_coins[0]):
		var coin: Node3D = game.gold_coins[0]
		fountain_distance = Vector2(coin.global_position.x - 37.0, coin.global_position.z).length()
	_check(fountain_distance >= 4.9 and fountain_distance <= 6.3, "tutorial coin lies 5-6.2m from the fountain")
	_check(game.tutorial_coins_on_ground() > 0, "coins are visible on the ground")
	game.player.global_position = Vector3(37.0, 0.76, 0.0)
	await get_tree().create_timer(1.5).timeout
	_check(int(tutorial.get("coins_collected")) == 0, "standing at the fountain does not collect coins")
	if game.gold_coins.size() > 0 and is_instance_valid(game.gold_coins[0]):
		var walk_coin: Node3D = game.gold_coins[0]
		game.player.global_position = walk_coin.global_position
		await get_tree().create_timer(0.6).timeout
		_check(int(tutorial.get("coins_collected")) > 0, "walking into a coin collects it")

	# Shop teleport is wrapped in the 0.25s fade.
	game.player.global_position = Vector3(-36.0, 0.76, 0.0)
	tutorial.set("stage", "go_shop")
	tutorial.call("_show_shop_card")
	tutorial.call("_open_shop_for_tutorial")
	_check(String(tutorial.get("stage")) == "buy_item", "shop opens the buy stage")
	await get_tree().create_timer(0.5).timeout
	_check(game.hud.get("fade_overlay") != null and not game.hud.get("fade_overlay").visible, "shop fade completes")

	# Pair 2v2, with cooldowns/HP deliberately dirty to prove the reset.
	for index in 3:
		game.player.ability_cds[index] = 9.0
	game.player.health = 100.0
	tutorial.call("on_shop_item_bought", "wind_boots")
	tutorial.call("_start_team_fight")
	await get_tree().process_frame
	_check(String(tutorial.get("stage")) == "team_fight", "2v2 stage starts")
	_check(game.tutorial_bots.size() == 3, "2v2 has one ally and two enemies")
	_check(
		game.player.ability_cds[0] == 0.0
		and game.player.ability_cds[1] == 0.0
		and game.player.ability_cds[2] == 0.0,
		"ability cooldowns reset before 2v2"
	)
	_check(game.player.health == game.player.max_health, "HP is full before 2v2")
	var allies := 0
	var enemies := 0
	for bot in game.tutorial_bots:
		if bot.team == game.player.team:
			allies += 1
		else:
			enemies += 1
	_check(allies == 1 and enemies == 2, "2v2 composition is 1 ally / 2 enemies")
	var pair_enemies: Array[HeroUnit] = []
	for bot in game.tutorial_bots:
		if bot.team != game.player.team:
			pair_enemies.append(bot)
	for bot in pair_enemies:
		bot.take_damage(99999.0, game.player)
		await get_tree().process_frame
	_check(String(tutorial.get("stage")) == "team_fight_done", "2v2 completes after two enemy deaths")

	# 3v3: enemies hold at their base, no Shell yet.
	game.player.global_position = Vector3(37.0, 0.76, 0.0)
	tutorial.call("_start_team_fight_final")
	await get_tree().process_frame
	_check(String(tutorial.get("stage")) == "team_fight_final_wait", "3v3 spawns immediately")
	_check(game.tutorial_bots.size() == 5, "3v3 has two allies and three enemies")
	_check(game.shell == null, "3v3 does not spawn the Shell")
	var held_enemies := 0
	var held_allies := 0
	for bot in game.tutorial_bots:
		_check(bot.tutorial_hold, "3v3 bot holds before release")
		if bot.team == game.player.team:
			held_allies += 1
		else:
			held_enemies += 1
			_check(absf(bot.global_position.z) > 20.0, "3v3 enemy spawns at its base")
			_check(game.player.global_position.distance_to(bot.global_position) >= 12.0, "3v3 enemy spawns at least 12m away")
	_check(held_allies == 2 and held_enemies == 3, "3v3 composition is 2 allies / 3 enemies")
	_check(float(tutorial.get("stage_timer")) > 59.0 and float(tutorial.get("stage_timer")) <= 60.0, "3v3 timer starts at 60")
	_check(float(tutorial.get("final_wave_release_timer")) > 1.0 and float(tutorial.get("final_wave_release_timer")) <= 1.5, "3v3 release timer is 1.5s")

	await get_tree().create_timer(1.8).timeout
	_check(String(tutorial.get("stage")) == "team_fight_final", "3v3 releases after the short spawn grace")
	var released := true
	for bot in game.tutorial_bots:
		if bot.tutorial_hold:
			released = false
	_check(released, "all 3v3 bots release together")

	var final_enemies: Array[HeroUnit] = []
	for bot in game.tutorial_bots:
		if bot.team != game.player.team:
			final_enemies.append(bot)
	for bot in final_enemies:
		bot.global_position = Vector3(0.0, 0.76, 0.0)
		bot.take_damage(99999.0, game.player)
		await get_tree().process_frame
	_check(String(tutorial.get("stage")) == "team_fight_final_done", "3v3 completes after three enemy deaths")

	# Finale: no enemies, Shell appears 2s after the wake-up message.
	tutorial.call("_start_shell_lesson")
	_check(String(tutorial.get("stage")) == "shell_intro", "Shell lesson shows the final card")
	_check(
		game.player.ability_cds[0] == 0.0
		and game.player.ability_cds[1] == 0.0
		and game.player.ability_cds[2] == 0.0,
		"ability cooldowns reset before the Shell finale"
	)
	tutorial.call("_begin_shell_prepare")
	_check(String(tutorial.get("stage")) == "shell_telegraph", "Shell telegraph starts immediately")
	_check(game.tutorial_bots.is_empty(), "Shell finale has no enemies")
	_check(game.shell == null, "Shell is still absent during the telegraph")
	await get_tree().create_timer(2.3).timeout
	_check(String(tutorial.get("stage")) == "destroy_shell", "Shell spawns after the 2s telegraph")
	_check(game.shell != null and is_instance_valid(game.shell), "Shell exists")
	if game.shell != null and is_instance_valid(game.shell):
		_check(game.shell.max_health == 1000.0, "Shell starts at 1000 HP")
		tutorial.set("shell_fight_timer", 25.0)
		tutorial.call("process", 0.2)
		_check(game.shell.max_health == 700.0, "Shell drops to 700 HP after 25 seconds")
		game.shell.take_damage(99999.0, game.player)
	await get_tree().create_timer(0.5).timeout
	_check(String(tutorial.get("stage")) == "pick_crystal", "Shell death starts the shard pickup")
	if game.crystal_node != null and is_instance_valid(game.crystal_node):
		game.player.global_position = game.crystal_node.global_position
		await get_tree().create_timer(0.8).timeout
	_check(game.carrier == game.player, "player picks up the shard")
	game.player.global_position = Vector3(0.0, 0.76, float(game.BASE_POSITION_Z))
	await get_tree().create_timer(1.2).timeout
	_check(bool(tutorial.get("completed")), "tutorial completes after delivery")
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _finish() -> void:
	print("TUTORIAL_STAGES_FAILURES=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
