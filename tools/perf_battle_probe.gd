extends Node3D

## Battle performance probe (read-only: it starts a normal bot match and
## measures, it does not change gameplay, balance or scenes).
##
## Run windowed, one configuration per process:
##   godot_console --path . tools/PerfBattleProbe.tscn -- --layout=1440x734 --quality=high --tag=desktop
##   godot_console --path . tools/PerfBattleProbe.tscn -- --layout=844x390  --mobile --quality=low --tag=mobile
##
## Writes user://perf_logs/perf_battle_<tag>.json and prints PERF_BATTLE_*
## lines. Measures: scene load, time from start_match() to the first live
## frame, per-frame time distribution (avg/p50/p95/max, spikes), node and draw
## call counts, active particles (instances + amount), static/video memory and
## every frame above the hitch threshold with the phase it happened in.

const MAIN_SCENE := "res://scenes/Main.tscn"
const HITCH_MS := 50.0
const SAMPLE_PARTICLES_EVERY := 5

var tag := "run"
var run_seconds := 22.0
var target_size := Vector2i(1440, 734)
var force_mobile := false
var quality := ""
var no_vsync := false

var game: Node = null
var frame_usec := 0
var started_usec := 0
var live_usec := 0
var call_usec := 0
var load_ms := 0.0
var instantiate_ms := 0.0
var phase := "boot"
var frames: Array = []
var hitches: Array = []
var particle_samples: Array = []
var monitor_max := {}
var monitor_sum := {}
var monitor_count := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			var parts := arg.trim_prefix("--layout=").split("x")
			if parts.size() == 2:
				target_size = Vector2i(int(parts[0]), int(parts[1]))
		elif arg == "--mobile":
			force_mobile = true
		elif arg.begins_with("--quality="):
			quality = arg.trim_prefix("--quality=")
		elif arg.begins_with("--tag="):
			tag = arg.trim_prefix("--tag=")
		elif arg == "--novsync":
			no_vsync = true
		elif arg.begins_with("--seconds="):
			run_seconds = maxf(5.0, float(arg.trim_prefix("--seconds=")))

	if force_mobile or target_size.x < 500:
		DeviceProfile.mobile_ui = true
		DeviceProfile.touch_controls = true
		get_tree().root.content_scale_size = Vector2i(960, 540)
	else:
		DeviceProfile.mobile_ui = false
		get_tree().root.content_scale_size = target_size
	if not quality.is_empty() and DeviceProfile.QUALITY_VALUES.has(quality):
		DeviceProfile.graphics_quality = quality
		DeviceProfile.quality_override = "" if quality != "full" else "full"
	DeviceProfile.apply_graphics_quality()
	DisplayServer.window_set_size(target_size)
	if no_vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	for _i in 3:
		await get_tree().process_frame
	await _run()


func _run() -> void:
	phase = "load"
	var load_started := Time.get_ticks_usec()
	var packed := load(MAIN_SCENE) as PackedScene
	load_ms = float(Time.get_ticks_usec() - load_started) / 1000.0
	phase = "instantiate"
	var instantiate_started := Time.get_ticks_usec()
	game = packed.instantiate()
	add_child(game)
	for _i in 12:
		await get_tree().process_frame
	instantiate_ms = float(Time.get_ticks_usec() - instantiate_started) / 1000.0

	phase = "start_match"
	started_usec = Time.get_ticks_usec()
	call_usec = started_usec
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	# start_match is a coroutine: the call returns after the first await, the
	# match is playable once it sets state to "live" (after the warmups).
	var deadline := started_usec + 90_000_000
	while String(game.get("state")) != "live" and Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
	live_usec = Time.get_ticks_usec()
	phase = "live"
	frame_usec = live_usec

	var ability_slots := [0, 1, 2]
	var ability_index := 0
	var next_ability_ms := 4000
	var end_usec := live_usec + int(run_seconds * 1_000_000.0)
	while Time.get_ticks_usec() < end_usec:
		await get_tree().process_frame
		var elapsed_ms := float(Time.get_ticks_usec() - live_usec) / 1000.0
		if elapsed_ms >= float(next_ability_ms) and ability_index < ability_slots.size():
			var player: Node = game.get("player")
			if player != null and is_instance_valid(player):
				player.call("use_ability", int(ability_slots[ability_index]), true)
			ability_index += 1
			next_ability_ms += 3500

	_report()
	await RenderingServer.frame_post_draw
	get_tree().quit()


func _process(_delta: float) -> void:
	if game == null:
		return
	var now := Time.get_ticks_usec()
	if phase == "load" or phase == "instantiate" or frame_usec == 0:
		frame_usec = now
		return
	var frame_ms := float(now - frame_usec) / 1000.0
	frame_usec = now
	if phase != "live" and String(game.get("state")) != "live":
		return
	if String(game.get("state")) != "live":
		return
	var elapsed_ms := float(now - live_usec) / 1000.0
	frames.append([snappedf(elapsed_ms, 1.0), snappedf(frame_ms, 0.01)])
	if frame_ms >= HITCH_MS:
		hitches.append({
			"ms": snappedf(elapsed_ms, 1.0),
			"frame_ms": snappedf(frame_ms, 0.01),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		})
	_collect_monitors()
	if frames.size() % SAMPLE_PARTICLES_EVERY == 0:
		particle_samples.append(_count_particles())


func _collect_monitors() -> void:
	var values := {
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects_drawn": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
	}
	for key in values.keys():
		var value := float(values[key])
		monitor_max[key] = maxf(float(monitor_max.get(key, 0.0)), value)
		monitor_sum[key] = float(monitor_sum.get(key, 0.0)) + value
	monitor_count += 1


func _count_particles() -> Dictionary:
	if game == null or not is_instance_valid(game):
		return {}
	var gpu := 0
	var gpu_amount := 0
	var gpu_emitting := 0
	var cpu := 0
	var cpu_amount := 0
	var cpu_emitting := 0
	for node in game.find_children("*", "GPUParticles3D", true, false):
		var particles := node as GPUParticles3D
		gpu += 1
		gpu_amount += particles.amount
		if particles.emitting:
			gpu_emitting += 1
	for node in game.find_children("*", "CPUParticles3D", true, false):
		var particles := node as CPUParticles3D
		cpu += 1
		cpu_amount += particles.amount
		if particles.emitting:
			cpu_emitting += 1
	var lights := 0
	for node in game.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light.visible:
			lights += 1
	return {
		"gpu": gpu, "gpu_amount": gpu_amount, "gpu_emitting": gpu_emitting,
		"cpu": cpu, "cpu_amount": cpu_amount, "cpu_emitting": cpu_emitting,
		"lights": lights,
	}


func _window_stats(from_ms: float, to_ms: float) -> Dictionary:
	var values: Array[float] = []
	for entry in frames:
		var at := float(entry[0])
		if at >= from_ms and at < to_ms:
			values.append(float(entry[1]))
	if values.is_empty():
		return {}
	values.sort()
	var total := 0.0
	var over_33 := 0
	var over_50 := 0
	for value in values:
		total += value
		if value > 33.33:
			over_33 += 1
		if value > 50.0:
			over_50 += 1
	return {
		"frames": values.size(),
		"avg_ms": snappedf(total / float(values.size()), 0.01),
		"p50_ms": snappedf(values[int(float(values.size() - 1) * 0.50)], 0.01),
		"p95_ms": snappedf(values[mini(values.size() - 1, int(float(values.size()) * 0.95))], 0.01),
		"p99_ms": snappedf(values[mini(values.size() - 1, int(float(values.size()) * 0.99))], 0.01),
		"max_ms": snappedf(values[values.size() - 1], 0.01),
		"fps_avg": snappedf(1000.0 / maxf(0.01, total / float(values.size())), 0.1),
		"spikes_33": over_33,
		"spikes_50": over_50,
	}


func _report() -> void:
	var monitors := {}
	for key in monitor_max.keys():
		monitors[key] = {
			"max": snappedf(float(monitor_max[key]), 0.01),
			"avg": snappedf(float(monitor_sum[key]) / float(maxi(1, monitor_count)), 0.01),
		}
	var particles_peak := {}
	for key in ["gpu", "gpu_amount", "gpu_emitting", "cpu", "cpu_amount", "cpu_emitting", "lights"]:
		var peak := 0
		for sample in particle_samples:
			peak = maxi(peak, int(sample.get(key, 0)))
		particles_peak[key] = peak
	var report := {
		"tag": tag,
		"window": [target_size.x, target_size.y],
		"canvas": [int(get_viewport().get_visible_rect().size.x), int(get_viewport().get_visible_rect().size.y)],
		"mobile": DeviceProfile.mobile_ui,
		"quality": DeviceProfile.effective_quality(),
		"render_scale": DeviceProfile.quality_render_scale(),
		"novsync": no_vsync,
		"os": OS.get_name(),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", ""),
		"load_ms": snappedf(load_ms, 0.1),
		"instantiate_ms": snappedf(instantiate_ms, 0.1),
		"start_match_ms": snappedf(float(live_usec - call_usec) / 1000.0, 0.1),
		"total_to_live_ms": snappedf(float(live_usec - started_usec) / 1000.0, 0.1),
		"frames": {
			"first_3s": _window_stats(0.0, 3000.0),
			"first_10s": _window_stats(0.0, 10000.0),
			"after_10s": _window_stats(10000.0, 1.0e9),
			"all": _window_stats(0.0, 1.0e9),
		},
		"monitors": monitors,
		"particles_peak": particles_peak,
		"hitch_count": hitches.size(),
		"hitches": hitches.slice(0, 40),
	}
	DirAccess.make_dir_recursive_absolute("user://perf_logs")
	var path := "user://perf_logs/perf_battle_%s.json" % tag
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("PERF_BATTLE_JSON ", ProjectSettings.globalize_path(path))
	print("PERF_BATTLE=", JSON.stringify(report))
