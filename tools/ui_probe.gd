extends Node3D

# Снимает игровые экраны: пауза, магазин на карте, результаты боя.

var game: Node = null
var out_dir := "user://ui_shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene := load("res://scenes/Main.tscn") as PackedScene
	game = scene.instantiate()
	add_child(game)
	for i in 12:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.FAIRY, 0)
	for i in 20:
		await get_tree().process_frame

	game.hud.call("_open_pause_menu")
	for i in 6:
		await get_tree().process_frame
	await _shot("pause")

	game.hud.call("_resume_game")
	for i in 6:
		await get_tree().process_frame

	game.call("set_shop_open", true)
	for i in 8:
		await get_tree().process_frame
	await _shot("shop_ingame")
	game.call("set_shop_open", false)
	for i in 6:
		await get_tree().process_frame

	game.call("end_match", true)
	for i in 150:
		await get_tree().process_frame
	await _shot("results")
	print("UI_PROBE_DONE")
	get_tree().quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s.png" % shot_name))
	print("UI_SHOT ", shot_name)
