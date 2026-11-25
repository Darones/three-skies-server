extends Node3D

## Layout check for the tutorial top strip and the (removed) side plaque.
## Run: --layout=844x390 --mobile, --layout=960x540 --mobile, --layout=1440x734.

func _ready() -> void:
	var target := Vector2i(1440, 734)
	var force_mobile := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			var parts := arg.trim_prefix("--layout=").split("x")
			if parts.size() == 2:
				target = Vector2i(int(parts[0]), int(parts[1]))
		elif arg == "--mobile":
			force_mobile = true
	if force_mobile or target.x < 500:
		DeviceProfile.mobile_ui = true
		DeviceProfile.touch_controls = true
	if force_mobile:
		get_tree().root.content_scale_size = Vector2i(960, 540)
	else:
		get_tree().root.content_scale_size = target
	DisplayServer.window_set_size(target)
	for i in 3:
		await get_tree().process_frame
	get_tree().set_meta("tutorial_mode", true)
	get_tree().set_meta("selected_class", HeroUnit.Cls.WARRIOR)
	get_tree().set_meta("selected_team", 0)
	var game := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	for i in 12:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	for i in 120:
		await get_tree().process_frame
		if game.get("tutorial_controller") != null:
			break
	var tutorial: Node = game.get("tutorial_controller")
	if tutorial == null:
		print("LAYOUT_NO_TUTORIAL")
		get_tree().quit(1)
		return
	var size := get_viewport().get_visible_rect().size
	var tag := "%dx%d" % [int(size.x), int(size.y)]
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	await get_tree().create_timer(0.4).timeout
	_save("tutorial_layout_%s_welcome.png" % tag)
	print("LAYOUT_WELCOME card=", game.hud.get("tutorial_overlay").visible,
		" avatar=", game.hud.get("player_panel").visible,
		" skip=", game.hud.get("tutorial_skip_button").visible)

	# The always-visible strip: top edge, between the avatar card and the
	# skip button, never covering either corner.
	game.hud.call("hide_tutorial_card")
	game.hud.call("show_tutorial_hint", "Этап 1/3 · Дуэль: победи тренировочного бота")
	await get_tree().create_timer(0.4).timeout
	_save("tutorial_layout_%s_strip.png" % tag)
	var hint_rect: Rect2 = game.hud.get("tutorial_hint").get_global_rect()
	var card_rect: Rect2 = game.hud.get("player_panel").get_global_rect()
	var skip_rect: Rect2 = game.hud.get("tutorial_skip_button").get_global_rect()
	print("LAYOUT_STRIP hint=", hint_rect, " card=", card_rect, " skip=", skip_rect,
		" no_card_overlap=", hint_rect.position.x >= card_rect.end.x,
		" no_skip_overlap=", hint_rect.end.x <= skip_rect.position.x,
		" same_top=", absf(hint_rect.position.y - skip_rect.position.y) <= 2.0,
		" above_dialog=", hint_rect.end.y <= 102.0)
	print("LAYOUT_PAUSED=", get_tree().paused,
		" hint_buttons=", game.hud.get("tutorial_hint").get_child_count(),
		" side_buttons=", game.hud.get("tutorial_side_hint").get_child_count())

	tutorial.set("stage", "go_fountain")
	game.hud.call("hide_tutorial_card")
	game.player.global_position = Vector3(37.0, 0.76, 0.0)
	await get_tree().process_frame
	tutorial.call("_start_coin_collection")
	await get_tree().create_timer(0.4).timeout
	_save("tutorial_layout_%s_fountain.png" % tag)
	var side: Control = game.hud.get("tutorial_side_hint")
	var top_hint: Control = game.hud.get("tutorial_hint")
	print("LAYOUT_FOUNTAIN side=", side.visible,
		" hint=", top_hint.visible,
		" text=", top_hint.get("text"))
	print("LAYOUT_SIDE_HIDDEN side=", side.visible,
		" top_hint=", top_hint.visible,
		" no_side_buttons=", side.get_child_count() == 0)

	tutorial.set("stage", "go_shop")
	game.player.global_position = game.SHOP_INTERACTION_POINT + Vector3(3.5, 0.0, 0.0)
	game.player.seconds_since_damage = 0.0
	await get_tree().process_frame
	tutorial.call("_show_shop_hint")
	await get_tree().create_timer(0.4).timeout
	_save("tutorial_layout_%s_shop.png" % tag)
	print("LAYOUT_SHOP side=", game.hud.get("tutorial_side_hint").visible,
		" hint=", game.hud.get("tutorial_hint").visible,
		" text=", game.hud.get("tutorial_hint").get("text"))
	print("LAYOUT_DIR=", ProjectSettings.globalize_path("user://ui_shots"))
	get_tree().quit()


func _save(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://ui_shots/" + file_name)
