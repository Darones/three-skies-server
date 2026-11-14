extends Control

# Временный отладочный оверлей: FPS, кадры, draw calls, ноды, память.
# Пишет JSON-отчёт в user://perf_logs после матча. Убрать после тестов.

const SAMPLE_INTERVAL := 0.5
const MAX_SAMPLES := 4000
const LOG_DIR := "user://perf_logs"
const WARMUP_SECONDS := 2.0

var game: Node = null
var started_at := ""
var started_ms := 0
var elapsed := 0.0
var sample_timer := 0.0
var samples: Array = []
var fps_min := 9999.0
var fps_max := 0.0
var fps_sum := 0.0
var fps_count := 0
var frame_max := 0.0
var draw_max := 0
var nodes_max := 0
var memory_max := 0.0
var spikes := 0

var panel: PanelContainer
var fps_label: Label
var frame_label: Label
var draw_label: Label
var nodes_label: Label
var memory_label: Label
var time_label: Label


func configure(game_node: Node) -> void:
	game = game_node


func _ready() -> void:
	started_at = Time.get_datetime_string_from_system()
	started_ms = Time.get_ticks_msec()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_place_panel()
	set_process(true)


func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "PerfPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	fps_label = _make_line(box, Color(0.55, 1.0, 0.6))
	frame_label = _make_line(box, Color(0.75, 0.9, 1.0))
	draw_label = _make_line(box, Color(0.85, 0.85, 0.95))
	nodes_label = _make_line(box, Color(0.75, 0.8, 0.9))
	memory_label = _make_line(box, Color(0.8, 0.85, 0.95))
	time_label = _make_line(box, Color(0.95, 0.82, 0.5))


func _make_line(parent: VBoxContainer, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.05, 0.62)
	style.border_color = Color(0.5, 0.6, 0.75, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


func _place_panel() -> void:
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	var bottom := -12.0
	if OS.has_feature("mobile") or OS.has_feature("web") or OS.get_cmdline_user_args().has("--touch"):
		bottom = -264.0
	offset_left = 12.0
	offset_right = 278.0
	offset_top = bottom - 122.0
	offset_bottom = bottom


func _process(delta: float) -> void:
	elapsed = (Time.get_ticks_msec() - started_ms) / 1000.0
	if elapsed < WARMUP_SECONDS:
		return
	sample_timer += delta
	if sample_timer < SAMPLE_INTERVAL:
		return
	sample_timer = 0.0
	var fps := float(Engine.get_frames_per_second())
	var frame_ms := 1000.0 / maxf(fps, 1.0)
	fps_min = minf(fps_min, fps)
	fps_max = maxf(fps_max, fps)
	fps_sum += fps
	fps_count += 1
	frame_max = maxf(frame_max, frame_ms)
	if frame_ms > 33.0:
		spikes += 1
	var draw := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var memory := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	draw_max = maxi(draw_max, draw)
	nodes_max = maxi(nodes_max, nodes)
	memory_max = maxf(memory_max, memory)
	if samples.size() < MAX_SAMPLES:
		samples.append([
			snappedf(elapsed, 0.1),
			snappedf(fps, 0.1),
			snappedf(frame_ms, 0.01),
			draw,
			nodes,
			snappedf(memory, 0.1),
			snappedf(physics_ms, 0.01),
		])
	_update_labels(fps, frame_ms, draw, nodes, memory, physics_ms)


func _update_labels(fps: float, frame_ms: float, draw: int, nodes: int, memory: float, physics_ms: float) -> void:
	var average := fps_sum / maxf(fps_count, 1.0)
	fps_label.text = "FPS %d  мин %d  ср %d" % [int(fps), int(fps_min), int(average)]
	fps_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6) if fps >= 50.0 else (Color(1.0, 0.85, 0.4) if fps >= 30.0 else Color(1.0, 0.45, 0.4)))
	frame_label.text = "Кадр %.1f мс  макс %.1f  физ %.1f" % [frame_ms, frame_max, physics_ms]
	draw_label.text = "Draw calls %d  макс %d" % [draw, draw_max]
	nodes_label.text = "Ноды %d  макс %d" % [nodes, nodes_max]
	memory_label.text = "Память %.0f МБ  макс %.0f" % [memory, memory_max]
	var minutes := int(elapsed) / 60
	var seconds := int(elapsed) % 60
	time_label.text = "Время %02d:%02d  спайки %d" % [minutes, seconds, spikes]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_F3:
		visible = not visible


func _exit_tree() -> void:
	if elapsed < WARMUP_SECONDS + 0.2 or samples.is_empty():
		return
	var stats: Dictionary = get_tree().get_meta("last_match_stats", {}) if get_tree() != null else {}
	var report := {
		"started_at": started_at,
		"duration_seconds": snappedf(elapsed, 0.1),
		"hero_class": _hero_class_name(),
		"network_play": bool(game.network_play) if game != null and "network_play" in game else false,
		"match_finished": not stats.is_empty(),
		"result": {
			"kills": int(stats.get("p_kills", 0)),
			"deaths": int(stats.get("p_deaths", 0)),
			"damage": int(stats.get("p_damage", 0)),
			"crystals": int(stats.get("p_crystals", 0)),
			"gold": int(stats.get("p_gold_earned", 0)),
		},
		"fps": {"avg": snappedf(fps_sum / maxf(fps_count, 1.0), 0.1), "min": snappedf(fps_min, 0.1), "max": snappedf(fps_max, 0.1)},
		"frame_ms": {"max": snappedf(frame_max, 0.01), "spikes_over_33ms": spikes},
		"draw_calls": {"max": draw_max},
		"nodes": {"max": nodes_max},
		"memory_mb": {"max": snappedf(memory_max, 0.1)},
		"platform": {
			"os": OS.get_name(),
			"model": OS.get_model_name(),
			"cpu_count": OS.get_processor_count(),
			"godot": Engine.get_version_info().get("string", ""),
			"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", ""),
			"time_scale": Engine.time_scale,
			"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		},
		"samples": samples,
	}
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var path := "%s/perf_%s.json" % [LOG_DIR, stamp]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("PerfMonitor: cannot write %s" % path)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("PERF_REPORT ", ProjectSettings.globalize_path(path))
	if OS.has_feature("editor"):
		DirAccess.make_dir_recursive_absolute("res://perf_logs")
		var project_path := "res://perf_logs/perf_%s.json" % stamp
		var project_file := FileAccess.open(project_path, FileAccess.WRITE)
		if project_file != null:
			project_file.store_string(JSON.stringify(report, "  "))
			project_file.close()
			print("PERF_REPORT_PROJECT ", ProjectSettings.globalize_path(project_path))


func _hero_class_name() -> String:
	if game == null:
		return ""
	var player = game.get("player")
	if player == null or not is_instance_valid(player):
		return ""
	match int(player.hero_class):
		HeroUnit.Cls.WARRIOR:
			return "warrior"
		HeroUnit.Cls.MAGE:
			return "mage"
		HeroUnit.Cls.FAIRY:
			return "fairy"
	return ""
