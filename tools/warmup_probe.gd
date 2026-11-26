extends Node3D

## Warmup flow + Welcome WARMING card probe.
##
## Runs the real WarmupFlow (hidden arena, fighters, weapons, VFX, shaders),
## checks 0 -> 100 / monotonic progress / one `finished`, then shows the
## WelcomeOverlay in WARMING and captures a frame.
##
## Run windowed:
##   godot_console --path . tools/WarmupProbe.tscn -- --layout=844x390 --mobile
##   godot_console --path . tools/WarmupProbe.tscn -- --layout=1440x734

var failures := 0
var percents: Array[float] = []
var stages: Array[String] = []
var elapsed_series: Array[float] = []
var finished_count := 0
var warmup_checks_done := false
var target_size := Vector2i(1440, 734)

const WARMUP_FLOW_SCRIPT := preload("res://scripts/warmup_flow.gd")


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
		get_tree().root.content_scale_size = Vector2i(960, 540)
	else:
		get_tree().root.content_scale_size = target
	DisplayServer.window_set_size(target)
	target_size = target
	for _i in 3:
		await get_tree().process_frame

	await _run_warmup()
	await _run_overlay()
	if not warmup_checks_done:
		_check(false, "проверки warmup дошли до конца")
	for _i in 3:
		await get_tree().process_frame

	print("WARMUP_FAILURES=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _run_warmup() -> void:
	var flow: Node = WARMUP_FLOW_SCRIPT.new()
	if flow == null or not flow.has_method("start"):
		_check(false, "WarmupFlow создаётся")
		return
	flow.name = "WarmupFlow"
	add_child(flow)
	flow.progress_changed.connect(_on_progress)
	flow.finished.connect(_on_finished)
	var started := Time.get_ticks_msec()
	flow.start()
	var deadline := started + 120000
	while not flow.is_finished() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var total := float(Time.get_ticks_msec() - started) / 1000.0
	print("WARMUP_TOTAL t=%.2f s" % total)

	_check(finished_count == 1, "finished сработал ровно один раз (%d)" % finished_count)
	_check(not percents.is_empty(), "есть сигналы progress_changed")
	if percents.is_empty():
		return
	_check(is_equal_approx(percents[0], 0.0), "первый прогресс 0.0 (%.1f)" % percents[0])
	_check(is_equal_approx(percents[percents.size() - 1], 100.0),
		"последний прогресс 100.0 (%.1f)" % percents[percents.size() - 1])
	var monotonic := true
	for index in range(1, percents.size()):
		if percents[index] + 0.001 < percents[index - 1]:
			monotonic = false
	_check(monotonic, "прогресс не убывает")
	var in_range := true
	for value in percents:
		if value < 0.0 or value > 100.0:
			in_range = false
	_check(in_range, "прогресс в диапазоне 0..100")
	var elapsed_ok := true
	for index in range(1, elapsed_series.size()):
		if elapsed_series[index] + 0.0001 < elapsed_series[index - 1]:
			elapsed_ok = false
	_check(elapsed_ok, "elapsed реальное и не убывает")
	_check(percents.size() >= 12, "достаточно шагов прогресса (%d)" % percents.size())

	var seen := {}
	for stage in stages:
		seen[stage] = true
	for required in [
		"Загрузка арены",
		"Материалы арены",
		"Бойцы и скины",
		"Оружие и предметы",
		"Эффекты и шейдеры",
		"Готово",
	]:
		_check(seen.has(required), "этап «%s» доложен" % required)

	var report: Dictionary = flow.report
	print("WARMUP_REPORT=", report)
	print("WARMUP_MEMORY static_peak=%.1f MB video_peak=%.1f MB"
		% [float(report.get("peak_static_mb", 0.0)), float(report.get("peak_video_mb", 0.0))])
	_check(bool(report.get("main_scene_loaded", false)), "Main.tscn загружен")
	_check(bool(report.get("main_script_stripped", false)),
		"game.gd снят с инстанса (без матча/HUD)")
	_check(bool(report.get("main_freed", false)), "инстанс Main освобождён")
	_check(bool(report.get("main_cached", false)), "Main.tscn остаётся в кэше после прогрева")
	_check(int(report.get("heroes_warmed", 0)) == 5,
		"прогрето 5 моделей бойцов (%d)" % int(report.get("heroes_warmed", 0)))
	_check(int(report.get("props_warmed", 0)) >= 18,
		"прогрето оружие/предметы (%d)" % int(report.get("props_warmed", 0)))
	_check(int(report.get("vfx_scenes_warmed", 0)) >= 10,
		"VFX-сцены прогреты (%d)" % int(report.get("vfx_scenes_warmed", 0)))
	_check(int(report.get("sounds_warmed", 0)) >= 30,
		"звуки декодированы (%d)" % int(report.get("sounds_warmed", 0)))
	_check(int(report.get("shaders_warmed", 0)) >= 9,
		"шейдеры прогреты (%d)" % int(report.get("shaders_warmed", 0)))
	_check(int(report.get("frames_rendered", 0)) >= 40,
		"отрисовано кадров (%d)" % int(report.get("frames_rendered", 0)))
	_check(not bool(report.get("failed", false)), "warmup без ошибок")
	_check(get_tree().root.find_child("HUD", true, false) == null,
		"скрытый прогрев не создал HUD")
	var leftovers: Array = flow.find_children("*WarmupFlowViewport*", "", true, false)
	_check(leftovers.is_empty(), "скрытый viewport освобождён")
	var canvases: Array = flow.find_children("*WarmupFlowCanvas*", "", true, false)
	_check(canvases.is_empty(), "скрытый canvas-viewport освобождён")
	for child in flow.get_children():
		if child is SubViewport:
			_check(false, "после прогрева не осталось SubViewport: %s" % child.name)
	flow.queue_free()
	warmup_checks_done = true


func _on_progress(percent: float, elapsed: float, stage: String) -> void:
	percents.append(percent)
	elapsed_series.append(elapsed)
	if stages.is_empty() or stages[stages.size() - 1] != stage:
		stages.append(stage)
	print("WARMUP_STEP t=%.2f pct=%.1f stage=%s" % [elapsed, percent, stage])


func _on_finished() -> void:
	finished_count += 1


func _run_overlay() -> void:
	for _i in 3:
		await get_tree().process_frame
	var overlay := preload("res://scripts/welcome_overlay.gd").new() as Control
	overlay.name = "WelcomeOverlay"
	add_child(overlay)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.95, 0.76, 0.38)
	normal.set_corner_radius_all(10)
	overlay.call("apply_play_styles", normal, normal, normal, normal)
	overlay.call("show_welcome")
	for _i in 4:
		await get_tree().process_frame
	overlay.call("show_warming")
	overlay.call("set_warmup_progress", 47.0, 3.8, "Бойцы и скины")
	for _i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

	var viewport_rect := get_viewport().get_visible_rect()
	var tag := "%dx%d" % [int(viewport_rect.size.x), int(viewport_rect.size.y)]
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://ui_shots/warmup_welcome_%s.png" % tag)
	if target_size != Vector2i(int(viewport_rect.size.x), int(viewport_rect.size.y)):
		# The canvas expands (1168x540 for a 844x390 phone), so keep a copy
		# under the requested window size too.
		image.save_png("user://ui_shots/warmup_welcome_window_%dx%d.png"
			% [target_size.x, target_size.y])
	print("WARMUP_SHOT=", ProjectSettings.globalize_path("user://ui_shots/warmup_welcome_%s.png" % tag))
	print("WARMUP_WINDOW=%dx%d CANVAS=%s" % [target_size.x, target_size.y, tag])

	var play: Button = overlay.get("play_button")
	var legal: Label = overlay.get("legal_label")
	var keyart: TextureRect = overlay.get("_keyart")
	var logo: TextureRect = overlay.get("welcome_logo")
	var age: Label = overlay.get("age_label")
	var box: VBoxContainer = overlay.get("warmup_box")
	var bar: ProgressBar = overlay.get("warmup_bar")
	var stage_label: Label = overlay.get("warmup_stage")
	var elapsed_label: Label = overlay.get("warmup_elapsed")
	print("WARMUP_OVERLAY state=", overlay.call("state_name"),
		" viewport=", viewport_rect.size, " overlay=", overlay.get_global_rect())
	print("WARMUP_BAR rect=", bar.get_global_rect(), " value=", bar.value,
		" stage=", stage_label.text, " elapsed=", elapsed_label.text)
	print("WARMUP_LEGAL rect=", legal.get_global_rect())

	_check(overlay.call("state_name") == "warming", "состояние WARMING")
	_check(keyart.visible and logo.visible and age.visible,
		"key art, логотип и 12+ видны в WARMING")
	_check(not play.visible and play.disabled, "Play скрыт и неактивен")
	_check(box.visible and bar.visible and stage_label.visible and elapsed_label.visible,
		"полоска прогресса и текст этапа видны")
	_check(absf(bar.value - 47.0) < 0.01, "полоска показывает процент (%.1f)" % bar.value)
	_check("3.8" in elapsed_label.text, "время прогрева показано (%s)" % elapsed_label.text)
	_check("Бойцы" in stage_label.text, "этап показан (%s)" % stage_label.text)
	_check(legal.visible, "юридическая строка видна внизу")

	var bar_rect := bar.get_global_rect()
	var legal_rect := legal.get_global_rect()
	var title_rect: Rect2 = (overlay.get("warmup_title") as Label).get_global_rect()
	_check(viewport_rect.encloses(bar_rect), "полоска внутри экрана %s" % bar_rect)
	_check(viewport_rect.encloses(legal_rect), "legal внутри экрана %s" % legal_rect)
	_check(bar_rect.end.y <= legal_rect.position.y + 1.0,
		"полоска не перекрывает legal (bar_bottom=%.1f legal_top=%.1f)"
		% [bar_rect.end.y, legal_rect.position.y])
	_check(title_rect.end.y <= bar_rect.position.y + 1.0,
		"заголовок не перекрывает полоску")
	_check(bar_rect.size.x >= 140.0, "полоска достаточно широкая (%.0f)" % bar_rect.size.x)

	overlay.call("finish_warming")
	await get_tree().process_frame
	_check(is_equal_approx(bar.value, 100.0), "finish_warming доводит полоску до 100")
	_check(stage_label.text == "Готово", "finish_warming пишет «Готово»")
	_check(overlay.visible, "карточка остаётся на экране до смены сцены")
	overlay.queue_free()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
