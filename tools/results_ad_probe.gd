extends Node

## Stage 3 results-screen ad contract: a failed rewarded ad shows only the
## small muted hint (no reason, no [object Object], no big banner), repeats no
## more than once per 30 s, and a completed ad still doubles the rewards.

var failures := 0


func _ready() -> void:
	var target := Vector2i(1440, 734)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			var parts := arg.trim_prefix("--layout=").split("x")
			if parts.size() == 2:
				target = Vector2i(int(parts[0]), int(parts[1]))
	if target.x < 500:
		DeviceProfile.mobile_ui = true
		DeviceProfile.touch_controls = true
	get_tree().root.content_scale_size = target
	DisplayServer.window_set_size(target)
	for i in 3:
		await get_tree().process_frame

	var original_adapter: Variant = Platform.adapter
	var original_id := Platform.platform_id
	var stub: PlatformAdapter = preload("res://tools/ad_stub.gd").new()
	Platform.adapter = stub
	Platform.platform_id = "vk"
	AdManager.begin_results()

	var screen := (load("res://scenes/ResultsScreen.tscn") as PackedScene).instantiate()
	add_child(screen)
	for i in 6:
		await get_tree().process_frame
	screen.set("match_aborted", false)
	screen.set("rewards_doubled", false)
	screen.set("server_match", false)
	screen.set("final_shards", 100)
	screen.set("final_xp", 10)
	screen.set("ad_in_progress", false)
	screen.call("_refresh_reward_ui")
	var button: Button = screen.get("double_reward_button")
	var label: Label = screen.get("ad_error_label")
	var banner: Label = screen.get("reward_banner")
	_check(button != null and button.visible, "x2 button is visible with a rewarded adapter")
	_check(label != null, "quiet ad error label exists")
	if banner != null:
		banner.visible = false

	# First failure: quiet line, no reason in the UI.
	stub.rewarded_result = false
	await screen.call("_double_rewards_for_ad")
	_check(label != null and label.visible, "failed rewarded shows the small hint")
	if label != null:
		_check(label.text == "Реклама временно недоступна. Попробуйте позже.", "hint uses the fixed message")
		_check(not label.text.contains("no_fill") and not label.text.contains("[object"), "hint hides the raw error")
	_check(banner == null or not banner.visible, "failed rewarded does not show a big banner")
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		DirAccess.make_dir_recursive_absolute("user://ui_shots")
		var image := get_viewport().get_texture().get_image()
		image.save_png("user://ui_shots/results_ad_error_%dx%d.png" % [target.x, target.y])

	# Second failure within 30 s: the hint is rate-limited.
	if label != null:
		label.visible = false
	screen.set("ad_in_progress", false)
	stub.rewarded_result = false
	await screen.call("_double_rewards_for_ad")
	_check(label != null and not label.visible, "ad error hint is rate-limited to once per 30 s")

	# Completed rewarded still grants x2.
	screen.set("ad_in_progress", false)
	screen.set("rewards_doubled", false)
	stub.rewarded_result = true
	await screen.call("_double_rewards_for_ad")
	_check(bool(screen.get("rewards_doubled")), "completed rewarded still doubles the rewards")
	_check(int(screen.get("final_shards")) == 200, "doubled shards are applied")
	_check(label == null or not label.visible, "success hides the ad error hint")

	Platform.adapter = original_adapter
	Platform.platform_id = original_id
	print("RESULTS_AD_FAILURES=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
