extends Node3D


func _ready() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	var game := scene.instantiate()
	add_child(game)
	for i in 12:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.FAIRY, 0)
	await get_tree().create_timer(2.5).timeout
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	image.save_png("user://ui_shots/game_clean_probe.png")
	print("GAME_SHOT_DONE")
	get_tree().quit()
