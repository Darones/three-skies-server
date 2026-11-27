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
	var legal := overlay.find_child("WelcomeLegal", true, false) as Control
	var logo: TextureRect = overlay.get("welcome_logo")
	var age := overlay.find_child("WelcomeAgeRating", true, false) as Label
	var screen := Rect2(Vector2.ZERO, size)
	var play_rect := play.get_global_rect()
	var legal_rect := Rect2()
	var legal_font := 0
	if legal != null:
		legal_rect = legal.get_global_rect()
		legal_font = legal.get_theme_font_size("normal_font_size")
	var legal_visible := legal != null and legal.visible
	var legal_inside := legal_visible and screen.encloses(legal_rect)
	var legal_clear := legal != null and not play_rect.intersects(legal_rect)
	var legal_text := ""
	var legal_lines := 0
	if legal is RichTextLabel:
		legal_text = (legal as RichTextLabel).text
		legal_lines = (legal as RichTextLabel).get_line_count()
	var legal_links := (
		legal_text.contains("/privacy")
		and legal_text.contains("/terms")
		and legal_text.contains("UGC")
	)
	# Landscape/desktop: the consent line must stay one or two rows. Narrow
	# portrait screens legitimately wrap into three or four.
	var legal_lines_ok := size.x < 700.0 or legal_lines <= 2
	print("WELCOME viewport=", size, " overlay=", overlay.get_global_rect())
	print("WELCOME play=", play_rect, " font=", play.get_theme_font_size("font_size"))
	print("WELCOME logo=", logo.get_global_rect(), " age_badge=", age != null, " legal=", legal != null)
	print(
		"WELCOME legal_rect=", legal_rect,
		" visible=", legal_visible,
		" inside=", legal_inside,
		" clear_of_play=", legal_clear,
		" links=", legal_links,
		" lines=", legal_lines,
		" chars=", legal_text.length(),
		" font=", legal_font
	)
	# The consent line belongs to Welcome only: it must disappear with warmup.
	overlay.call("show_warming")
	for i in 3:
		await get_tree().process_frame
	var legal_in_warming := legal != null and legal.visible
	print("WELCOME legal_hidden_in_warming=", not legal_in_warming)
	var legal_ok := (
		legal_inside and legal_clear and legal_links
		and legal_lines_ok and not legal_in_warming
	)
	print("WELCOME LEGAL_RESULT=", "PASS" if legal_ok else "FAIL")
	print("WELCOME_DIR=", ProjectSettings.globalize_path("user://ui_shots"))
	get_tree().quit()
