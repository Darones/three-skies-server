extends Node3D

## Welcome overlay layout probe (no lobby / no profile needed).
## Run: --layout=844x390 --mobile, --layout=1440x734, --layout=360x640 --mobile

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
	if force_mobile or target.x < 500:
		get_tree().root.content_scale_size = Vector2i(960, 540)
	else:
		get_tree().root.content_scale_size = target
	DisplayServer.window_set_size(target)
	for i in 3:
		await get_tree().process_frame

	var overlay := preload("res://scripts/welcome_overlay.gd").new() as Control
	add_child(overlay)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.95, 0.76, 0.38)
	normal.set_corner_radius_all(10)
	overlay.call("apply_play_styles", normal, normal, normal, normal)
	overlay.call("show_welcome")
	for i in 6:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout

	var size := get_viewport().get_visible_rect().size
	var tag := "%dx%d" % [int(size.x), int(size.y)]
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://ui_shots/welcome_%s.png" % tag)
	var play: Button = overlay.get("play_button")
	var legal: Label = overlay.get("legal_label")
	var logo: TextureRect = overlay.get("welcome_logo")
	var age: Label = overlay.get("age_label")
	print("WELCOME viewport=", size, " overlay=", overlay.get_global_rect())
	print("WELCOME play=", play.get_global_rect(), " font=", play.get_theme_font_size("font_size"))
	print("WELCOME legal=", legal.get_global_rect(), " font=", legal.get_theme_font_size("font_size"))
	print("WELCOME logo=", logo.get_global_rect(), " age=", age.get_global_rect(),
		" age_font=", age.get_theme_font_size("font_size"))
	print("WELCOME_DIR=", ProjectSettings.globalize_path("user://ui_shots"))
	get_tree().quit()
