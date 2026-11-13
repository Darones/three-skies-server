extends Node3D

# Открывает магазин в лобби и снимает скриншот, чтобы проверить,
# что карточки помещаются и не обрезаются.

func _ready() -> void:
	var scene := load("res://scenes/Lobby.tscn") as PackedScene
	if scene == null:
		print("PROBE: lobby load failed")
		get_tree().quit()
		return
	var lobby := scene.instantiate()
	add_child(lobby)
	for i in 6:
		await get_tree().process_frame

	if lobby.has_method("_open_shard_shop"):
		lobby.call("_open_shard_shop")
		print("PROBE: shop opened")
	for i in 6:
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://shop_probe.png")
	print("PROBE: saved user://shop_probe.png")
	get_tree().quit()
