extends Node

## Tutorial loading screen probe (tutorial_mode + warmup_pending).
##
## The lesson must not warm up on the Welcome card or at game start any more:
## pressing "Играть" opens LoadingScreen, it runs WarmupFlow, shows its own
## title/progress/stage/elapsed, then opens Main.tscn in tutorial mode with
## battle_prewarmed=true. No network search is started.
##
## Run windowed (screenshots need a real renderer):
##   godot_console --path . tools/TutorialLoadingProbe.tscn -- --layout=1440x734
##   godot_console --path . tools/TutorialLoadingProbe.tscn -- --layout=844x390 --mobile

var target := Vector2i(1440, 734)
var force_mobile := false


func _ready() -> void:
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
	for _i in 3:
		await get_tree().process_frame

	# Exactly the metas lobby.gd sets in _start_tutorial().
	get_tree().set_meta("tutorial_mode", true)
	get_tree().set_meta("network_play", false)
	get_tree().set_meta("warmup_pending", true)
	get_tree().set_meta("battle_prewarmed", false)
	get_tree().set_meta("selected_class", 0)
	get_tree().set_meta("selected_team", 0)

	var watcher := Watcher.new()
	watcher.name = "TutorialLoadingWatcher"
	watcher.tag = "%dx%d" % [target.x, target.y]
	watcher.mobile = force_mobile or target.x < 500
	get_tree().root.add_child(watcher)
	get_tree().change_scene_to_file.call_deferred("res://scenes/LoadingScreen.tscn")


## Lives on the SceneTree root, so it survives the change to Main.tscn.
class Watcher extends Node:
	var failures := 0
	var tag := ""
	var phase := "wait_search"
	var loading: Node = null
	var flow: Node = null
	var started_ms := 0
	var percents: Array[float] = []
	var bar_values: Array[float] = []
	var stages: Array[String] = []
	var stage_samples: Array[String] = []
	var title_seen := ""
	var card_seen := false
	var card_keyart := ""
	var card_no_age := false
	var card_no_legal := false
	var card_warmup_hidden := false
	var found_count_hidden := false
	var search_bg_hidden := false
	var bar_left := -1.0
	var bar_right := -1.0
	var bar_top := -1.0
	var bar_bottom := -1.0
	var logo_width := 0.0
	var logo_bottom := 0.0
	var title_top := 0.0
	var bar_rect_top := 0.0
	var viewport_width := 0.0
	var layout_seen := false
	var mobile := false
	var flow_started := false
	var flow_stopped_at := -1
	var transition_at := -1
	var meta_after_stop := false
	var warmup_failed := false
	var shot_taken := false
	var main_checked := false
	var failures_reported := false
	var missing_frames := 0
	var main_frames := 0
	var no_extra_preloader := false
	var network_flow_seen := false
	var flow_signal_connected := false
	## The flow's report is a Dictionary: it stays readable after the node is
	## freed, so the pacing numbers can be checked at the end.
	var flow_report: Dictionary = {}

	func _ready() -> void:
		started_ms = Time.get_ticks_msec()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://ui_shots"))

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_msec() - started_ms
		match phase:
			"wait_search":
				var scene := get_tree().current_scene
				if scene != null and scene.name == "LoadingScreen":
					loading = scene
					phase = "watch"
			"watch":
				_watch(now)
			"main":
				main_frames += 1
				if main_frames >= 10 and not main_checked:
					_check_main(now)
		if now > 90000 and not failures_reported:
			_fail("экран обучения не дошёл до Main за 90 с")
			_report_and_quit(now)

	func _watch(now: int) -> void:
		var scene := get_tree().current_scene
		if scene != null and scene.name == "Main":
			transition_at = now
			phase = "main"
			return
		if not is_instance_valid(loading):
			missing_frames += 1
			if missing_frames > 30 and not failures_reported:
				_fail("экран загрузки обучения исчез до перехода в Main")
				_report_and_quit(now)
			return
		var title := loading.get("search_label") as Label
		if title != null:
			title_seen = title.text
		var card := loading.get("welcome_card") as Control
		if card != null and not card_seen:
			card_seen = true
			var keyart := card.get("_keyart") as TextureRect
			if keyart != null and keyart.texture != null:
				card_keyart = keyart.texture.resource_path
			# The 12+ badge belongs to the initial HTML loader only; the consent
			# line exists on Welcome and must stay hidden on the loading card.
			card_no_age = card.find_child("WelcomeAgeRating", true, false) == null
			# Consent belongs to Welcome: on the tutorial loading card it must
			# be invisible (the node itself may exist, hidden).
			var legal_card := card.find_child("WelcomeLegal", true, false) as CanvasItem
			card_no_legal = legal_card == null or not legal_card.visible
			var warmup_box := card.get("warmup_box") as Control
			card_warmup_hidden = warmup_box != null and not warmup_box.visible
			var found := loading.get("found_count_label") as Control
			found_count_hidden = found != null and not found.visible
			var capacity_bar := loading.get("progress_bar") as ProgressBar
			if capacity_bar != null:
				bar_left = capacity_bar.anchor_left
				bar_right = capacity_bar.anchor_right
				bar_top = capacity_bar.anchor_top
				bar_bottom = capacity_bar.anchor_bottom
			var search_bg := loading.get_node_or_null("LoadingBackground") as Control
			search_bg_hidden = search_bg != null and not search_bg.visible
		flow = loading.get_node_or_null("WarmupFlow") as Node
		if flow != null:
			flow_started = true
			if flow_report.is_empty():
				flow_report = flow.get("report") as Dictionary
			no_extra_preloader = loading.get_node_or_null("VfxPreloader") == null
			network_flow_seen = bool(loading.get("network_flow"))
			if not flow_signal_connected:
				flow_signal_connected = true
				flow.finished.connect(_on_flow_finished)
			var percent := clampf(float(flow.get("_progress")), 0.0, 100.0)
			if percents.is_empty() or percent != percents[percents.size() - 1]:
				percents.append(percent)
			var stage := String(flow.get("_stage"))
			if stages.is_empty() or stages[stages.size() - 1] != stage:
				stages.append(stage)
			var bar := loading.get("progress_bar") as ProgressBar
			if bar != null:
				if bar_values.is_empty() or bar.value != bar_values[bar_values.size() - 1]:
					bar_values.append(bar.value)
			var stage_label := loading.get("connection_hint") as Label
			if stage_label != null:
				if stage_samples.is_empty() or stage_samples[stage_samples.size() - 1] != stage_label.text:
					stage_samples.append(stage_label.text)
			if percent > 0.0 and not layout_seen:
				layout_seen = true
				var card_for_layout := loading.get("welcome_card") as Control
				var logo := card_for_layout.get("welcome_logo") as TextureRect
				if logo != null:
					logo_width = logo.get_global_rect().size.x
					logo_bottom = logo.get_global_rect().end.y
				var title_control := loading.get("search_label") as Control
				if title_control != null:
					title_top = title_control.get_global_rect().position.y
				var bar_control := loading.get("progress_bar") as Control
				if bar_control != null:
					bar_rect_top = bar_control.get_global_rect().position.y
				viewport_width = get_viewport().get_visible_rect().size.x
			if percent >= 35.0 and not shot_taken:
				_capture()
		elif flow_started and flow_stopped_at < 0:
			_record_flow_stopped(now)

	func _on_flow_finished() -> void:
		# Runs right after LoadingScreen's own handler (connected first), which
		# already set battle_prewarmed and requested the scene change.
		if flow_stopped_at < 0:
			_record_flow_stopped(Time.get_ticks_msec() - started_ms)

	func _record_flow_stopped(now: int) -> void:
		flow_stopped_at = now
		meta_after_stop = bool(get_tree().get_meta("battle_prewarmed", false))
		if is_instance_valid(flow):
			var report := flow.get("report") as Dictionary
			if report != null:
				warmup_failed = bool(report.get("failed", false))
		if is_instance_valid(loading):
			warmup_failed = warmup_failed or bool(loading.get("warmup_failed"))

	func _check_main(now: int) -> void:
		main_checked = true
		var main := get_tree().current_scene
		var max_percent := 0.0
		for value in percents:
			max_percent = maxf(max_percent, value)
		var main_tutorial := false
		var main_prewarmed := false
		var pending_left := bool(get_tree().get_meta("warmup_pending", false))
		if main != null:
			main_tutorial = bool(main.get("tutorial_mode"))
			main_prewarmed = bool(main.get("battle_prewarmed"))
		_check(flow_started, "WarmupFlow запустился на экране обучения")
		_check(card_seen, "экран обучения использует карточку Welcome")
		_check(
			card_keyart == "res://ui/welcome/welcome_keyart.webp",
			"фон совпадает с Welcome новичка (%s)" % card_keyart
		)
		_check(card_no_age, "бейджа 12+ нет на карточке Welcome")
		_check(card_no_legal, "правовой строки не видно на карточке Welcome")
		_check(card_warmup_hidden, "прогресс не нарисован на месте кнопки «Играть»")
		_check(search_bg_hidden, "фон поиска матча скрыт")
		_check(found_count_hidden, "нет дублирующей строки над полоской")
		_check(title_seen == "ЗАГРУЗКА ОБУЧЕНИЯ", "заголовок «ЗАГРУЗКА ОБУЧЕНИЯ» (%s)" % title_seen)
		var html_source := FileAccess.get_file_as_string("res://tools/web_export.py")
		var html_age := html_source.contains('id="age-rating"') and html_source.contains("12+")
		var html_legal := html_source.contains('id="legal-consent"') and html_source.contains("Продолжая игру")
		var welcome_source := FileAccess.get_file_as_string("res://scripts/welcome_overlay.gd")
		var loading_source := FileAccess.get_file_as_string("res://scripts/loading_screen.gd")
		_check(html_age, "12+ есть на стартовом HTML-загрузчике (#age-rating)")
		_check(html_legal, "правовая строка есть на стартовом HTML-загрузчике (#legal-consent)")
		_check(
			not welcome_source.contains("12+") and not loading_source.contains("12+"),
			"12+ не встречается в Welcome/экране обучения"
		)
		_check(
			welcome_source.contains("Продолжая игру") and not loading_source.contains("Продолжая игру"),
			"строка согласия есть на Welcome и не дублируется на экране загрузки"
		)
		var progress_line_ok := false
		for sample in stage_samples:
			if sample.contains("%") and sample.contains("·") and sample.contains("с"):
				progress_line_ok = true
				break
		_check(
			progress_line_ok,
			"под полоской «N%% · stage · X с» (%s)" % (stage_samples[0] if not stage_samples.is_empty() else "")
		)
		var min_logo_fraction := 0.45 if mobile else 0.35
		_check(
			viewport_width > 0.0 and logo_width >= viewport_width * min_logo_fraction,
			"логотип крупный (%.0f px = %.0f%% экрана)" % [logo_width, 100.0 * logo_width / maxf(1.0, viewport_width)]
		)
		_check(logo_bottom <= title_top - 1.0, "логотип не налезает на заголовок (%.0f <= %.0f)" % [logo_bottom, title_top])
		_check(logo_bottom <= bar_rect_top - 1.0, "логотип не налезает на полоску (%.0f <= %.0f)" % [logo_bottom, bar_rect_top])
		_check(
			is_equal_approx(bar_left, 0.12) and is_equal_approx(bar_right, 0.88),
			"полоска по ширине как у поиска матча (%.2f..%.2f)" % [bar_left, bar_right]
		)
		var expected_top := 0.76 if mobile else 0.835
		var expected_bottom := 0.788 if mobile else 0.87
		_check(
			is_equal_approx(bar_top, expected_top) and is_equal_approx(bar_bottom, expected_bottom),
			"полоска на месте поиска матча (%.3f..%.3f)" % [bar_top, bar_bottom]
		)
		var stage_display_ok := false
		for sample in stage_samples:
			if sample.contains("·") and sample.contains("с"):
				stage_display_ok = true
				break
		_check(stage_display_ok, "stage и время показаны (%s)" % (stage_samples[0] if not stage_samples.is_empty() else ""))
		_check(bar_values.size() >= 4, "полоска прогресса двигалась (%d значений)" % bar_values.size())
		_check(not stages.is_empty(), "stage приходит от WarmupFlow (%s)" % (stages[0] if not stages.is_empty() else ""))
		_check(max_percent >= 99.0, "загрузка дошла до 100%% (макс %.0f%%)" % max_percent)
		_check(not warmup_failed, "прогрев завершился без ошибок")
		_check(meta_after_stop, "battle_prewarmed выставлен после прогрева")
		_check(no_extra_preloader, "нет второго VfxPreloader")
		_check(not network_flow_seen, "сетевой поиск не запускался")
		_check(not NetworkManager.is_connecting(), "NetworkManager не подключался")
		_check(transition_at >= 0, "переход в Main состоялся")
		_check(transition_at >= flow_stopped_at, "Main открылся после прогрева (%d >= %d)" % [transition_at, flow_stopped_at])
		_check(main_tutorial, "Main запустился в tutorial-режиме")
		_check(main_prewarmed, "Main получил battle_prewarmed (без повторного прогрева)")
		_check(not pending_left, "warmup_pending снят после перехода")
		_check_pacing()
		_report_and_quit(now)

	## The tutorial screen has no match search, so the warmup itself must stay
	## inside the 30 s budget and stay even from the first second.
	func _check_pacing() -> void:
		var elapsed := float(flow_report.get("elapsed", 0.0))
		var pauses := float(flow_report.get("pauses_s", 0.0))
		var p95 := float(flow_report.get("frame_ms_p95", 0.0))
		var first2s := float(flow_report.get("first2s_max_frame_ms", 0.0))
		var settled := float(flow_report.get("first2s_settled_max_frame_ms", 0.0))
		print("TUTORIAL_LOADING_PACING total=%.2f work=%.2f pauses=%.2f target=%.1f"
			% [
				elapsed,
				float(flow_report.get("work_s", 0.0)),
				pauses,
				float(flow_report.get("pacing_target_s", 0.0)),
			])
		print("TUTORIAL_LOADING_FRAMES avg=%.1f p95=%.1f max=%.1f first2s_max=%.1f at=%.2fs settled=%.1f viewport=%d"
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
		_check(elapsed > 0.0 and elapsed <= 30.0, "прогрев обучения в 30 с (%.2f с)" % elapsed)
		_check(elapsed >= 15.0, "прогрев обучения растянут (%.2f с)" % elapsed)
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
		var path := ProjectSettings.globalize_path("user://ui_shots/qa-tutorial-loading-welcomebg-%s.png" % tag)
		image.save_png(path)
		print("TUTORIAL_LOADING_SHOT=%s" % path)

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
		print("TUTORIAL_LOADING_TAG=%s" % tag)
		print("TUTORIAL_LOADING_ELAPSED_MS=%d" % now)
		print("TUTORIAL_LOADING_STOP_MS=%d" % flow_stopped_at)
		print("TUTORIAL_LOADING_TRANSITION_MS=%d" % transition_at)
		print("TUTORIAL_LOADING_PERCENT_STEPS=%d" % percents.size())
		print("TUTORIAL_LOADING_FAILURES=%d" % failures)
		get_tree().quit(1 if failures > 0 else 0)
