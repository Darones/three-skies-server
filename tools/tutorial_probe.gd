extends Node3D


func _ready() -> void:
	get_tree().set_meta("tutorial_mode", true)
	get_tree().set_meta("selected_class", HeroUnit.Cls.WARRIOR)
	get_tree().set_meta("selected_team", 0)
	var game := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	for i in 12:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	for i in 3:
		await get_tree().process_frame
	var tutorial: Node = game.get("tutorial_controller")
	print("TUTORIAL_START stage=", tutorial.get("stage"))
	# Имитируем баг: игрок уже несёт осколок, но обучение стоит на шаге фонтана
	tutorial.set("stage", "go_fountain")
	game.hud.call("show_tutorial_hint", "Сходи к фонтану и собери 15 монет")
	game.player.global_position = Vector3(0.0, 0.76, 0.0)
	game.call("spawn_crystal", game.player.global_position, false)
	game.set("crystal_state", "carried")
	game.set("carrier", game.player)
	game.player.carrying = true
	await get_tree().create_timer(0.4).timeout
	print("AFTER_PICKUP stage=", tutorial.get("stage"))
	print("AFTER_PICKUP hint=", game.hud.get("tutorial_hint").text)
	print("AFTER_PICKUP target=", game.get("tutorial_target_position"))
	# Доставляем на свою базу
	game.player.global_position = Vector3(0.0, 0.76, float(game.BASE_POSITION_Z))
	await get_tree().create_timer(0.6).timeout
	print("AFTER_DELIVERY stage=", tutorial.get("stage"))
	print("AFTER_DELIVERY completed=", tutorial.get("completed"))
	print("AFTER_DELIVERY state=", game.get("state"))
	print("AFTER_DELIVERY hint=", game.hud.get("tutorial_hint").text)
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	image.save_png("user://ui_shots/tutorial_delivery_probe.png")
	print("TUTORIAL_PROBE_DONE")
	get_tree().quit()
