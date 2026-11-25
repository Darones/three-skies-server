extends Node3D

## Rules screen readability probe.
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

	var panel := preload("res://scripts/rules_panel.gd").new() as Control
	add_child(panel)
	panel.call("open")
	for i in 6:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout

	var size := get_viewport().get_visible_rect().size
	var tag := "%dx%d" % [int(size.x), int(size.y)]
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://ui_shots/rules_%s.png" % tag)
	print("RULES viewport=", size, " panel=", panel.get_global_rect())
	var scroll: ScrollContainer = panel.get("scroll")
	var content: Control = scroll.get_child(0)
	var labels: Array[Label] = []
	_collect_labels(panel, labels)
	var min_font := 999
	for label in labels:
		min_font = mini(min_font, label.get_theme_font_size("font_size"))
	print("RULES scroll=", scroll.get_global_rect(), " content_h=", content.size.y,
		" v_max=", scroll.get_v_scroll_bar().max_value,
		" labels=", labels.size(), " min_font=", min_font)
	for label in labels:
		print("RULES label size=", label.get_theme_font_size("font_size"),
			" rect=", label.get_global_rect(), " text=", label.text.substr(0, 24))
	print("RULES_DIR=", ProjectSettings.globalize_path("user://ui_shots"))
	get_tree().quit()


func _collect_labels(node: Node, out: Array[Label]) -> void:
	if node is Label:
		out.append(node)
	for child in node.get_children():
		_collect_labels(child, out)
