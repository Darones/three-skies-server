extends Node3D

# Снимает витрину магазина: вкладки героев и страницы товаров.

var lobby: Node = null


func _ready() -> void:
	lobby = (load("res://scenes/Lobby.tscn") as PackedScene).instantiate()
	add_child(lobby)
	for i in 20:
		await get_tree().process_frame
	lobby.call("_open_shard_shop")
	for i in 8:
		await get_tree().process_frame
	await _shot("shop_fairy")
	lobby.call("_open_topup_panel")
	for i in 6:
		await get_tree().process_frame
	await _shot("shop_topup")
	lobby.call("_close_topup_panel")
	lobby.call("_select_shop_hero", 2)
	for i in 6:
		await get_tree().process_frame
	await _shot("shop_warrior")
	lobby.call("_change_shop_page", 1)
	for i in 6:
		await get_tree().process_frame
	await _shot("shop_warrior_page2")
	lobby.call("_select_shop_hero", 1)
	lobby.call("_change_shop_page", 1)
	for i in 6:
		await get_tree().process_frame
	await _shot("shop_mage_page2")
	print("SHOP_PROBE_DONE")
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	get_viewport().get_texture().get_image().save_png("user://ui_shots/%s.png" % name)
	print("SHOT ", name)
