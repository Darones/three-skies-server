extends Node3D

## Captures the tutorial "press ability" plate at the right edge.
## Run: --layout=844x390 --mobile, --layout=1440x734

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
	var hud: Node = game.get("hud")
	if hud == null:
		print("PRESS_HINT_NO_HUD")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.5).timeout
	hud.call("set_tutorial_ability", 2)
	for i in 4:
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

	var size := get_viewport().get_visible_rect().size
	var tag := "%dx%d" % [int(size.x), int(size.y)]
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://ui_shots/tutorial_press_hint_%s.png" % tag)
	var hint: Label = hud.get("tutorial_press_label")
	var button: Button = hud.get("ability_buttons")[2]
	var hint_rect := hint.get_global_rect()
	var text_size := hint.get_theme_font("font").get_string_size(
		hint.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		hint.get_theme_font_size("font_size")
	)
	var inside: bool = (
		hint_rect.position.x >= 0.0
		and hint_rect.position.y >= 0.0
		and hint_rect.end.x <= size.x
		and hint_rect.end.y <= size.y
	)
	var text_fits := text_size.x <= hint_rect.size.x - 16.0
	print("PRESS_HINT viewport=", size, " text=", hint.text,
		" hint=", hint_rect, " button=", button.get_global_rect(),
		" text_width=", text_size.x, " plate_width=", hint_rect.size.x,
		" inside=", inside, " text_fits=", text_fits,
		" visible=", hint.visible)
	print("PRESS_HINT_DIR=", ProjectSettings.globalize_path("user://ui_shots"))
	get_tree().quit(0 if inside and text_fits and hint.visible else 1)
