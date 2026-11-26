extends Node

## Loading/search screen battle-warmup probe (network_play=false → bot fallback).
##
## Verifies that the match search now does the full battle warmup:
##  - WarmupFlow starts inside LoadingScreen and its progress is shown;
##  - the search keeps ticking (matched slots / progress bar) while it runs;
##  - the match does not open before the warmup is finished (early-match test);
##  - battle_prewarmed is set and Main.tscn receives it;
##  - LoadingScreen does not start a second VfxPreloader.
##
## Run windowed (screenshots need a real renderer):
##   godot_console --path . tools/LoadingWarmupSearchProbe.tscn -- --layout=1440x734
##   godot_console --path . tools/LoadingWarmupSearchProbe.tscn -- --layout=844x390 --mobile
##
## Options:
##   --early-match   finish the search at ~25% warmup (checks the wait gate).
##                   On by default; pass --no-early-match to let the normal
##                   15 s bot search finish after the warmup.
##   --budget=3      shrink the warmup budget (checks the 30 s fallback).

var target := Vector2i(1440, 734)
var force_mobile := false
var early_match := true
var budget := 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			var parts := arg.trim_prefix("--layout=").split("x")
			if parts.size() == 2:
				target = Vector2i(int(parts[0]), int(parts[1]))
		elif arg == "--mobile":
			force_mobile = true
		elif arg == "--no-early-match":
			early_match = false
		elif arg.begins_with("--budget="):
			budget = float(arg.trim_prefix("--budget="))
	if force_mobile or target.x < 500:
		DeviceProfile.mobile_ui = true
		DeviceProfile.touch_controls = true
		# Same canvas as the real phone build (see DeviceProfile).
		get_tree().root.content_scale_size = Vector2i(960, 540)
	else:
		get_tree().root.content_scale_size = target
	DisplayServer.window_set_size(target)
	for _i in 3:
		await get_tree().process_frame

	# Bot fallback flow: no server, but a normal (non-tutorial) match.
	get_tree().set_meta("tutorial_mode", false)
	get_tree().set_meta("network_play", false)
	get_tree().set_meta("selected_class", 0)
	get_tree().set_meta("selected_team", 0)
	get_tree().set_meta("battle_prewarmed", false)
	get_tree().set_meta("fill_with_bots", false)

	var watcher := Watcher.new()
	watcher.name = "LoadingWarmupWatcher"
	watcher.tag = "%dx%d" % [target.x, target.y]
	watcher.early_match = early_match
	watcher.budget = budget
	get_tree().root.add_child(watcher)
	get_tree().change_scene_to_file.call_deferred("res://scenes/LoadingScreen.tscn")


## Lives on the SceneTree root, so it survives the change to Main.tscn.
class Watcher extends Node:
	var failures := 0
	var tag := ""
	var early_match := true
	var budget := 0.0
	var fallback_mode := false
	var shot_prefix := "qa-loading-warmup-search"

	var phase := "wait_search"
	var loading: Node = null
	var flow: Node = null
	var started_ms := 0
	var budget_applied := false

	var percents: Array[float] = []
	var stages: Array[String] = []
	var search_values: Array[float] = []
	var label_samples: Array[String] = []
	var flow_started := false
	var flow_stopped_at := -1
	var transition_at := -1
	var early_sent_at := -1
	var meta_after_stop := false
	var warmup_failed := false
	var no_extra_preloader := false
	var shot_taken := false
	var main_checked := false
	var failures_reported := false
	var missing_frames := 0
	var main_frames := 0
	var saw_load_failed := false
	var match_scene_ready := false
	## The flow's report is a Dictionary, so this stays valid after the node is
	## freed and lets the pacing numbers be checked here too.
	var flow_report: Dictionary = {}

	func _ready() -> void:
		started_ms = Time.get_ticks_msec()
		fallback_mode = budget > 0.0 and budget < 10.0
		if fallback_mode:
			shot_prefix = "qa-loading-warmup-fallback"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://ui_shots"))

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_msec() - started_ms
		match phase:
			"wait_search":
				var scene := get_tree().current_scene
				if scene != null and scene.name == "LoadingScreen":
					loading = scene
					if budget > 0.0:
						loading.set("warmup_budget_seconds", budget)
						budget_applied = true
					no_extra_preloader = loading.get_node_or_null("VfxPreloader") == null
					phase = "watch"
			"watch":
				_watch_search(now)
			"main":
				main_frames += 1
				if main_frames >= 8 and not main_checked:
					_check_main(now)
		if now > 120000 and not failures_reported:
			_fail("переход в Main не случился за 120 с (warmup_active=%s)" % str(loading.get("warmup_active") if is_instance_valid(loading) else "?"))
			_report_and_quit(now)

	func _watch_search(now: int) -> void:
		# The change to Main frees the search screen first and assigns
		# current_scene on the same or the next frame — check Main before the
		# "screen disappeared" guard.
		var scene := get_tree().current_scene
		if scene != null and scene.name == "Main":
			transition_at = now
			phase = "main"
			return
		if not is_instance_valid(loading):
			missing_frames += 1
			if missing_frames > 30 and not failures_reported:
				_fail("экран поиска исчез до перехода в Main")
				_report_and_quit(now)
			return
		var active := bool(loading.get("warmup_active"))
		flow = loading.get_node_or_null("WarmupFlow") as Node
		if flow == null and flow_started:
			# The finished handler queue_frees the flow; keep the last state.
			if flow_stopped_at < 0:
				flow_stopped_at = now
			_on_warmup_stopped()
		elif flow != null:
			flow_started = true
			if flow_report.is_empty():
				flow_report = flow.get("report") as Dictionary
			var percent := clampf(float(flow.get("_progress")), 0.0, 100.0)
			var stage := String(flow.get("_stage"))
			if percents.is_empty() or percent != percents[percents.size() - 1]:
				percents.append(percent)
				if not stage.is_empty():
					stages.append(stage)
			if early_match and early_sent_at < 0 and percent >= 25.0 and bool(flow.call("is_running")):
				early_sent_at = now
				loading.call("_complete_match_search")
			if percent >= 35.0 and not shot_taken and active:
				_capture()
		# Search UI must keep working while the warmup runs (bot slots fill).
		var bar := loading.get_node_or_null("MatchProgress") as ProgressBar
		if bar != null:
			if search_values.is_empty() or bar.value != search_values[search_values.size() - 1]:
				search_values.append(bar.value)
		var label := loading.find_child("WarmupPercent", true, false) as Label
		if label != null and not label.text.is_empty():
			if label_samples.is_empty() or label_samples[label_samples.size() - 1] != label.text:
				label_samples.append(label.text)
		if flow_started and not active and flow_stopped_at < 0:
			flow_stopped_at = now
			_on_warmup_stopped()
		if bool(loading.get("load_failed")):
			saw_load_failed = true
		if loading.get("match_scene") != null:
			match_scene_ready = true
		if flow_started and now > 45000 and early_match and early_sent_at < 0:
			# Safety: never let the probe sit on the search screen forever.
			loading.call("_complete_match_search")
			early_sent_at = now

	func _on_warmup_stopped() -> void:
		warmup_failed = bool(loading.get("warmup_failed"))
		meta_after_stop = bool(get_tree().get_meta("battle_prewarmed", false))
		var report: Dictionary = {}
		if is_instance_valid(flow):
			report = flow.get("report") as Dictionary
		if bool(report.get("failed", false)):
			warmup_failed = true
		# Keep the last percent now that the flow node may be gone. Only a
		# completed warmup ends at 100; a budget cut-off stops lower on purpose.
		if meta_after_stop and not warmup_failed:
			if percents.is_empty() or percents[percents.size() - 1] < 100.0:
				percents.append(100.0)

	func _check_main(now: int) -> void:
		main_checked = true
		var main := get_tree().current_scene
		if main == null:
			_fail("Main не появился")
			_report_and_quit(now)
			return
		var main_prewarmed := bool(main.get("battle_prewarmed"))
		var search_ticks := search_values.size()
		var max_percent := 0.0
		for value in percents:
			max_percent = maxf(max_percent, value)
		if fallback_mode:
			_check(flow_started, "WarmupFlow запустился на экране поиска")
			_check(max_percent > 0.0, "прогрев реально начался (%.0f%%)" % max_percent)
			_check(max_percent < 99.0, "прогрев не успел закончиться до бюджета (%.0f%%)" % max_percent)
			_check(transition_at >= 0, "переход в Main состоялся")
			_check(not saw_load_failed, "сцена матча загрузилась без ошибки")
			_check(match_scene_ready, "Main PackedScene получена до перехода")
			_check(not meta_after_stop, "battle_prewarmed НЕ выставлен при fallback")
			_check(not main_prewarmed, "Main не считает бой прогретым при fallback")
			_check(
				transition_at >= 0 and transition_at < int((budget + 12.0) * 1000.0),
				"fallback не держит игрока дольше бюджета (%d мс)" % transition_at
			)
		else:
			_check(flow_started, "WarmupFlow запустился на экране поиска")
			_check(no_extra_preloader, "второй VfxPreloader не запускался")
			_check(max_percent >= 99.0, "прогрев дошёл до 100%% (макс %.0f%%)" % max_percent)
			_check(percents.size() >= 4, "прогресс менялся по шагам (%d значений)" % percents.size())
			_check(not stages.is_empty(), "stage показывается (%s)" % (stages[0] if not stages.is_empty() else ""))
			_check(not label_samples.is_empty(), "статус 'Прогрев боя: N%%' нарисован (%s)" % (label_samples[0] if not label_samples.is_empty() else ""))
			var labelled := false
			for sample in label_samples:
				if sample.begins_with("Прогрев боя:"):
					labelled = true
					break
			_check(labelled, "подпись статуса прогрева корректна")
			_check(search_ticks >= 2, "поиск не заблокирован прогревом (%d значений прогресс-бара)" % search_ticks)
			_check(not warmup_failed, "прогрев завершился без ошибок")
			_check(meta_after_stop, "battle_prewarmed выставлен после прогрева")
			_check(not saw_load_failed, "сцена матча загрузилась без ошибки")
			_check(match_scene_ready, "Main PackedScene получена после прогрева (без второго полного preload)")
			_check(transition_at >= 0, "переход в Main состоялся")
			_check(
				early_sent_at < 0 or flow_stopped_at < 0 or transition_at >= flow_stopped_at,
				"Main не открылся раньше окончания прогрева (переход %d, прогрев %d)" % [transition_at, flow_stopped_at]
			)
			_check(main_prewarmed, "Main получил battle_prewarmed (не греет бой повторно)")
			_check_pacing(now)
		_report_and_quit(now)

	## Pacing/load profile of the warmup that ran behind the search screen.
	## In fallback mode the flow is cut by the budget on purpose, so only the
	## transition time is checked there.
	func _check_pacing(_now: int) -> void:
		var elapsed := float(flow_report.get("elapsed", 0.0))
		var pauses := float(flow_report.get("pauses_s", 0.0))
		var p95 := float(flow_report.get("frame_ms_p95", 0.0))
		var first2s := float(flow_report.get("first2s_max_frame_ms", 0.0))
		var settled := float(flow_report.get("first2s_settled_max_frame_ms", 0.0))
		print("LOADING_WARMUP_PACING total=%.2f work=%.2f pauses=%.2f target=%.1f"
			% [
				elapsed,
				float(flow_report.get("work_s", 0.0)),
				pauses,
				float(flow_report.get("pacing_target_s", 0.0)),
			])
		print("LOADING_WARMUP_FRAMES avg=%.1f p95=%.1f max=%.1f first2s_max=%.1f at=%.2fs settled=%.1f viewport=%d"
			% [
				float(flow_report.get("frame_ms_avg", 0.0)),
				p95,
				float(flow_report.get("frame_ms_max", 0.0)),
				first2s,
				float(flow_report.get("first2s_max_at_s", 0.0)),
				settled,
				int(flow_report.get("frames_rendered", 0)),
			])
		_check(flow_report.size() > 0, "report прогрева прочитан")
		_check(elapsed > 0.0 and elapsed <= 30.0, "прогрев уложился в 30 с (%.2f с)" % elapsed)
		_check(elapsed >= 15.0, "прогрев растянут (%.2f с)" % elapsed)
		_check(pauses >= 3.0, "паузы между шагами (%.2f с)" % pauses)
		_check(not bool(flow_report.get("deadline_hit", false)), "жёсткий бюджет не понадобился")
		_check(p95 <= 250.0, "p95 кадра в норме (%.1f мс)" % p95)
		_check(first2s <= 200.0,
			"первый кадр экрана не завис (%.1f мс; это первый draw экрана)"
			% first2s)
		_check(settled <= 100.0,
			"прогрев не даёт пика в первые 2 с (%.1f мс)" % settled)

	func _capture() -> void:
		if shot_taken:
			return
		shot_taken = true
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path("user://ui_shots/%s-%s.png" % [shot_prefix, tag])
		image.save_png(path)
		print("LOADING_WARMUP_SHOT=%s" % path)

	func _check(condition: bool, label: String) -> void:
		if condition:
			print("PASS: ", label)
		else:
			failures += 1
			print("FAIL: ", label)

	func _fail(label: String) -> void:
		failures += 1
		print("FAIL: ", label)

	func _report_and_quit(now: int) -> void:
		if failures_reported:
			return
		failures_reported = true
		print("LOADING_WARMUP_TAG=%s" % tag)
		print("LOADING_WARMUP_MATCH_FOUND_MS=%d" % early_sent_at)
		print("LOADING_WARMUP_ELAPSED_MS=%d" % now)
		print("LOADING_WARMUP_STOP_MS=%d" % flow_stopped_at)
		print("LOADING_WARMUP_TRANSITION_MS=%d" % transition_at)
		print("LOADING_WARMUP_PERCENT_STEPS=%d" % percents.size())
		print("LOADING_WARMUP_SEARCH_TICKS=%d" % search_values.size())
		print("LOADING_WARMUP_STAGES=%s" % str(stages))
		print("LOADING_WARMUP_FAILURES=%d" % failures)
		get_tree().quit(1 if failures > 0 else 0)
