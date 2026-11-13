extends Node3D

# Снимает лобби и меню игрока (инвентарь), чтобы проверить карточки.

func _ready() -> void:
	var scene := load("res://scenes/Lobby.tscn") as PackedScene
	if scene == null:
		print("PROBE: lobby load failed")
		get_tree().quit()
		return
	var lobby := scene.instantiate()
	add_child(lobby)
	for i in 8:
		await get_tree().process_frame

	await _shot("lobby")
	if lobby.has_method("_open_player_menu"):
		lobby.call("_open_player_menu")
		print("PROBE: player menu opened")
	for i in 8:
		await get_tree().process_frame
	await _shot("inventory")
	print("PROBE: done")
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://%s.png" % name)
	print("PROBE: saved ", name)
