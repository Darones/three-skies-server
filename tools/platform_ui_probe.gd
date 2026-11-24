extends Node3D

## Windowed M1 UI evidence: the standalone shop has no buy-shards entry point,
## and the topup panel shows an honest "unavailable" state instead of a mock
## payment. Run without --headless so the viewport has pixels.

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	var scene := load("res://scenes/Lobby.tscn") as PackedScene
	var lobby := scene.instantiate()
	add_child(lobby)
	for i in 12:
		await get_tree().process_frame

	lobby.call("_open_shard_shop")
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://ui_shots/m1_shop_standalone.png")
	print("SHOT: m1_shop_standalone.png")

	lobby.call("_open_topup_panel")
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://ui_shots/m1_topup_standalone.png")
	print("SHOT: m1_topup_standalone.png")
	print("PLATFORM_UI_PROBE_DONE")
	get_tree().quit()
