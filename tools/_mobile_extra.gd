extends Node3D


func _ready() -> void:
	get_window().size = Vector2i(1600, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	var game := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	for i in 20:
		await get_tree().process_frame
	await _shot("mobile_select_1600")
	game.queue_free()
	await get_tree().process_frame

	get_tree().set_meta("last_match_won", true)
	get_tree().set_meta("last_match_score", [3, 1])
	get_tree().set_meta("last_match_team", 0)
	get_tree().set_meta("last_match_place", 1)
	get_tree().set_meta("last_match_is_mvp", true)
	get_tree().set_meta("selected_class", HeroUnit.Cls.FAIRY)
	get_tree().set_meta("last_match_stats", {
		"p_kills": 4, "p_deaths": 2, "p_damage": 3200, "p_crystals": 3, "p_shells_destroyed": 1,
		"p_coins_collected": 42, "p_gold_earned": 1850, "p_gold_spent": 900,
	})
	get_tree().set_meta("last_match_players", [])
	var results := (load("res://scenes/ResultsScreen.tscn") as PackedScene).instantiate()
	add_child(results)
	for i in 20:
		await get_tree().process_frame
	await _shot("mobile_results_1600")
	print("MOBILE_EXTRA_DONE")
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	get_viewport().get_texture().get_image().save_png("user://ui_shots/%s.png" % name)
	print("SHOT ", name)
