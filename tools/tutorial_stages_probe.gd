extends Node3D

## D1 headless check: the tutorial really walks 1v1 -> 2v2 with an ally ->
## 3v3, uses easy bots, and exposes the skip button. Combat is simulated by
## killing the tutorial bots directly; this checks the state machine, not feel.

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
	_check(String(tutorial.get("stage")) == "welcome", "starts at welcome")
	_check(game.hud.get("tutorial_skip_button") != null and game.hud.get("tutorial_skip_button").visible, "skip button visible")

	# Skip the timed UI tour: the stage after it is reach_center.
	tutorial.set("stage", "reach_center")
	game.player.global_position = Vector3(0.0, 0.76, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(String(tutorial.get("stage")) == "duel", "1v1 stage starts at arena center")
	_check(game.tutorial_bots.size() == 1, "duel has exactly one enemy bot")
	if game.tutorial_bots.size() == 1:
		var duel_bot: HeroUnit = game.tutorial_bots[0]
		_check(duel_bot.bot_difficulty == "easy", "duel bot is easy")
		_check(duel_bot.team != game.player.team, "duel bot is an enemy")
		duel_bot.take_damage(99999.0, game.player)
		await get_tree().process_frame
		_check(String(tutorial.get("stage")) == "duel_done", "duel completes on enemy death")
	_check(game.tutorial_bots.is_empty(), "duel bots are cleared")

	# Stage 2: one ally + two enemies.
	tutorial.set("stage", "buy_item")
	tutorial.call("_start_team_fight_intro")
	tutorial.call("_start_team_fight")
	await get_tree().process_frame
	_check(String(tutorial.get("stage")) == "team_fight", "2v2 stage starts")
	_check(game.tutorial_bots.size() == 3, "2v2 has one ally and two enemies")
	var allies := 0
	var enemies := 0
	for bot in game.tutorial_bots:
		if bot.team == game.player.team:
			allies += 1
		else:
			enemies += 1
		_check(bot.bot_difficulty == "easy", "2v2 bot is easy")
	_check(allies == 1 and enemies == 2, "2v2 composition is 1 ally / 2 enemies")
	var enemy_bots: Array[HeroUnit] = []
	for bot in game.tutorial_bots:
		if bot.team != game.player.team:
			enemy_bots.append(bot)
	for bot in enemy_bots:
		bot.take_damage(99999.0, game.player)
		await get_tree().process_frame
	_check(String(tutorial.get("stage")) == "team_fight_done", "2v2 completes after two enemy deaths")

	# Stage 3: two allies + three enemies, then the shell lesson.
	tutorial.call("_start_final")
	await get_tree().process_frame
	_check(String(tutorial.get("stage")) == "shell_warning", "3v3 stage starts with the shell countdown")
	_check(game.tutorial_bots.size() == 5, "3v3 has two allies and three enemies")
	allies = 0
	enemies = 0
	for bot in game.tutorial_bots:
		if bot.team == game.player.team:
			allies += 1
		else:
			enemies += 1
		_check(bot.bot_difficulty == "easy", "3v3 bot is easy")
	_check(allies == 2 and enemies == 3, "3v3 composition is 2 allies / 3 enemies")

	game.clear_tutorial_bots()
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
