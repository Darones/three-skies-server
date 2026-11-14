extends Node3D


func _ready() -> void:
	MetaProgression.unlocked_weapons = []
	MetaProgression.weapons_enabled = {"warrior": true, "mage": true, "fairy": true}
	var game := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	for i in 12:
		await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var hero_class := int(args[0]) if args.size() > 0 else 0
	game.call("start_match", hero_class, 0)
	await get_tree().create_timer(2.5).timeout
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	image.save_png("user://ui_shots/simple_%d.png" % hero_class)
	print("SIMPLE_SHOT_DONE %d" % hero_class)
	get_tree().quit()
