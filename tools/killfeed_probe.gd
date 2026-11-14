extends Node3D

# Проверяет значки команд в килл-фиде.

var game: Node = null


func _ready() -> void:
	game = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	for i in 12:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.FAIRY, 0)
	for i in 10:
		await get_tree().process_frame
	var hud = game.get("hud")
	if hud == null:
		print("KILLFEED_FAIL no hud")
		get_tree().quit()
		return
	hud.call("show_kill_feed", "Даронес", "Тёмный Лис", 0, 1)
	hud.call("show_kill_feed", "Северный Ветер", "Искра", 1, 0)
	hud.call("show_kill_feed", "Белый Ворон", "Пепел", 0, 0)
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	get_viewport().get_texture().get_image().save_png("user://ui_shots/killfeed_teams.png")
	print("KILLFEED_PROBE_DONE")
	get_tree().quit()
