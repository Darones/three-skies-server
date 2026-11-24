extends Node3D

## Windowed D1 evidence: rules screen and the tutorial's first 1v1 stage.

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
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://ui_shots/d1_tutorial_duel.png")
	print("SHOT: d1_tutorial_duel.png")

	if game.tutorial_bots.size() > 0:
		game.tutorial_bots[0].take_damage(99999.0, game.player)
	for i in 4:
		await get_tree().process_frame
	game.hud.call("hide_tutorial_card")
	tutorial.set("stage", "buy_item")
	tutorial.call("_start_team_fight_intro")
	tutorial.call("_start_team_fight")
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://ui_shots/d1_tutorial_2v2.png")
	print("SHOT: d1_tutorial_2v2.png")

	tutorial.call("_finish_team_fight")
	tutorial.call("_start_final")
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://ui_shots/d1_tutorial_3v3.png")
	print("SHOT: d1_tutorial_3v3.png")

	tutorial.call("request_skip")
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://ui_shots/d1_tutorial_skip.png")
	print("SHOT: d1_tutorial_skip.png")
	print("D1_UI_PROBE_DONE")
	get_tree().quit()
