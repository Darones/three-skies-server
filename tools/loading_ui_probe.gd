extends Node

## Loading/search screen: no 12+ badge, no consent text, and a 390/1440 shot.

var failures := 0


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
		# Match the real mobile UI canvas (DeviceProfile.MOBILE_CONTENT_SCALE);
		# using 844x390 as the canvas made the probe lie about the game.
		get_tree().root.content_scale_size = Vector2i(960, 540)
	else:
		get_tree().root.content_scale_size = target
	DisplayServer.window_set_size(target)
	for i in 3:
		await get_tree().process_frame
	var scene := (load("res://scenes/LoadingScreen.tscn") as PackedScene).instantiate()
	add_child(scene)
	for i in 6:
		await get_tree().process_frame
	var badge := scene.find_child("AgeRatingBadge", true, false)
	var consent := scene.find_child("LegalConsent", true, false) as Label
	_check(badge == null, "12+ badge is not in the match search")
	_check(consent == null, "legal consent label is removed from the match search")
	var tag := "%dx%d" % [int(get_viewport().get_visible_rect().size.x), int(get_viewport().get_visible_rect().size.y)]
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://ui_shots/loading_search_%s.png" % tag)
	# The failure state adds a "В ЛОББИ" button above the tip. Capture it too:
	# this is the state a player sees when the server is unreachable.
	scene.call("_on_network_failed", "Сервер недоступен")
	for i in 5:
		await get_tree().process_frame
	image = get_viewport().get_texture().get_image()
	image.save_png("user://ui_shots/loading_failed_%s.png" % tag)
	print("LOADING_UI_DIR=", ProjectSettings.globalize_path("user://ui_shots"))
	print("LOADING_UI_FAILURES=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
