extends Node3D

## Windowed evidence for the revised tutorial: rules, duel, fountain, pair,
## 3v3 waiting at the enemy base, and the separate Shell finale.

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://ui_shots")

	var lobby := (load("res://scenes/Lobby.tscn") as PackedScene).instantiate()
	add_child(lobby)
	for i in 12:
		await get_tree().process_frame
	lobby.call("_open_rules")
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://ui_shots/d1_rules.png")
	print("SHOT: d1_rules.png")
	lobby.queue_free()
	for i in 4:
		await get_tree().process_frame

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
	game.hud.call("hide_tutorial_card")
	tutorial.set("stage", "reach_center")
	game.player.global_position = Vector3(0.0, 0.76, 0.0)
	for i in 8:
		await get_tree().process_frame
	await _shot("d1_tutorial_duel.png")

	if game.tutorial_bots.size() > 0:
		game.tutorial_bots[0].take_damage(99999.0, game.player)
	for i in 4:
		await get_tree().process_frame
	game.hud.call("hide_tutorial_card")
	game.player.global_position = Vector3(37.0, 0.76, 0.0)
	tutorial.set("stage", "go_fountain")
	tutorial.call("_show_fountain_card")
	tutorial.call("_start_coin_collection")
	await get_tree().create_timer(1.1).timeout
	await _shot("d1_tutorial_fountain.png")

	game.hud.call("hide_tutorial_card")
	game.player.global_position = Vector3(0.0, 0.76, 6.0)
	tutorial.set("stage", "buy_item")
	tutorial.call("_start_team_fight_intro")
	tutorial.call("_start_team_fight")
	await get_tree().create_timer(1.4).timeout
	await _shot("d1_tutorial_2v2.png")

	tutorial.call("_finish_team_fight")
	game.player.global_position = Vector3(37.0, 0.76, 0.0)
	tutorial.call("_start_team_fight_final")
	for i in 6:
		await get_tree().process_frame
	# Bring the camera near the enemy base without releasing the wave, so the
	# screenshot actually shows the three bots waiting at their base.
	game.player.global_position = Vector3(0.0, 0.76, -14.0)
	tutorial.set("stage", "screenshot_hold")
	for bot in game.tutorial_bots:
		bot.tutorial_hold = true
	# Frame the enemy base explicitly for the evidence shot; the normal camera
	# follows the player and would keep the three bots at the edge of the view.
	game.set_process(false)
	game.camera.global_position = Vector3(0.0, 9.0, -8.0)
	game.camera.look_at(Vector3(0.0, 1.0, -26.0), Vector3.UP)
	for i in 8:
		await get_tree().process_frame
	await _shot("d1_tutorial_3v3_base.png")
	game.set_process(true)

	# Continue the real flow: release, clear the three enemies, enter the Shell.
	game.player.global_position = Vector3(0.0, 0.76, 0.0)
	tutorial.set("stage", "team_fight_final_wait")
	for i in 4:
		await get_tree().process_frame
	var final_enemies: Array[HeroUnit] = []
	for bot in game.tutorial_bots:
		if bot.team != game.player.team:
			final_enemies.append(bot)
	for bot in final_enemies:
		bot.global_position = Vector3(0.0, 0.76, 0.0)
		bot.take_damage(99999.0, game.player)
		await get_tree().process_frame
	tutorial.call("_start_shell_lesson")
	tutorial.call("_begin_shell_prepare")
	game.player.global_position = Vector3(0.0, 0.76, 12.0)
	await get_tree().create_timer(3.5).timeout
	await _shot("d1_tutorial_shell.png")

	tutorial.call("request_skip")
	for i in 6:
		await get_tree().process_frame
	await _shot("d1_tutorial_skip.png")
	print("D1_UI_PROBE_DONE")
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://ui_shots/" + name)
	print("SHOT: ", name)
