extends Node3D

## Battle-start probe (read-only QA tool).
##
## The user reports hitches in the first 2-3 seconds of a match, and the
## battle-start sound arriving late. FirstClashProbe starts measuring only at
## `state == "live"` + 300 ms, so it cannot see the scene load, Main._ready,
## start_match and the first frames of the live match. This probe measures
## exactly that window:
##  * per-frame wall time from the Main instantiate call through live + 3 s,
##  * process / render spans, pipeline compilation deltas, draw calls, setup ms,
##  * audio: when music/ambient/sfx players actually start and when the Master
##    bus first carries sound (peak dB), plus AudioServer mix/output timing.
##
## Run windowed (rendering matters):
##   godot_console --path . tools/BattleStartProbe.tscn -- --warm --tag=warm-desktop-high --novsync
##   godot_console --path . tools/BattleStartProbe.tscn -- --warm --skip-clash-warm --tag=nowarm-warm-desktop
##   godot_console --path . --rendering-method gl_compatibility tools/BattleStartProbe.tscn -- --warm --mobile --layout=844x390 --quality=low --tag=warm-mobile-compat
##
## Writes res://docs/qa-battle-start/battle_start_<tag>.json + .png and prints
## BATTLE_START_SUMMARY=...

const MAIN_SCENE := "res://scenes/Main.tscn"
const WARMUP_FLOW_PATH := "res://scripts/warmup_flow.gd"
const OUT_DIR := "res://docs/qa-battle-start"

const MUSIC_PATH := "res://audio/music/dread/6adcd384-a1c6-4d03-ab8f-2885c6220fd5_music_dark_fantasy_arena_battle_them__1793744175999.mp3"
const AMBIENT_PATH := "res://audio/ambient/arena_wind.mp3"

const HITCH_16_MS := 16.67
const HITCH_33_MS := 33.34
const HITCH_50_MS := 50.0
## Silence floor for "the player hears the match": below this the Master bus
## carries no meaningful sound.
const AUDIBLE_DB := -45.0
## Assets the match loads itself; used to check whether the loading-screen
## warm still holds them in the resource cache when Main opens.
const PROBE_CACHE_PATHS := [
	"res://scenes/Main.tscn",
	"res://art/generated/warrior/character.tscn",
	"res://art/generated/mage/character.tscn",
	"res://art/generated/fairy/character.tscn",
	"res://art/generated/warrior_barbarian/character.tscn",
	"res://art/generated/fairy_hooded/character.tscn",
	"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/hit/vfx_hit_01.tscn",
	"res://assets/models/detail-crystal.glb",
]

var tag := "run"
var target_size := Vector2i(1440, 734)
var force_mobile := false
var quality := "high"
var no_vsync := true
var use_warmup := false
var warm_seconds := 10.0
var warm_budget := 24.0
var skip_clash_warm := false
var observe_live_ms := 5000.0
var dump_frames := false

var game: Node = null
var phase := "boot"
var instantiate_usec := 0
var ready_usec := 0
var live_usec := 0
var frame_usec := 0

var raw_frames: Array = []
var events: Array = []
var pipeline_monitors: Array = []
var sfx_paths: Array = []
var music_sfx_paths: Array = []

var prev_frame_signal_usec := 0
var prev_probe_usec := 0
var prev_audio := {}
var prev_hero_count := 0
var prev_state := ""

var warm_report: Dictionary = {}
var load_main_ms := 0.0
var instantiate_to_ready_ms := 0.0
var start_match_ms := 0.0
var shot_path := ""

# Audio evidence, filled from the frame samples / event poll.
var audio := {
	"music_play_calls": 0,
	"music_started_at_ms": -1.0,
	"music_position_at_live_ms": -1.0,
	"ambient_started_at_ms": -1.0,
	"first_sfx_at_ms": -1.0,
	"first_audible_db": 0.0,
	"first_audible_at_ms": -1.0,
	"output_latency_ms": 0.0,
	"mix_rate": 0.0,
	"cache_music": false,
	"cache_ambient": false,
	"sfx_cached": 0,
	"sfx_total": 0,
}

var audio_cost := {"music_cached_ms": 0.0, "music_cold_ms": 0.0, "ambient_cached_ms": 0.0, "ambient_cold_ms": 0.0}
## What is still in the loader cache right before Main is instantiated.
var cache_before: Dictionary = {}
## Optional diagnostic: time each `_spawn_hero` call separately.
var action := "match"
var spawn_steps: Array = []
## A/B: keep the assets WarmupFlow loaded alive across the scene switch (the
## fix being tested), so the match finds them in the loader cache.
var retain_assets := false
var retained: Array = []
var retain_ms := 0.0
var retain_paths := 0
## A/B control: throw the warmup's retained list away (pre-fix behaviour).
var drop_retained := false


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
		elif arg == "--vsync":
			no_vsync = false
		elif arg == "--warm":
			use_warmup = true
		elif arg.begins_with("--warm="):
			use_warmup = true
			warm_seconds = maxf(3.0, float(arg.trim_prefix("--warm=")))
		elif arg == "--no-warm":
			use_warmup = false
		elif arg.begins_with("--warm-budget="):
			warm_budget = maxf(5.0, float(arg.trim_prefix("--warm-budget=")))
		elif arg == "--skip-clash-warm":
			skip_clash_warm = true
		elif arg.begins_with("--seconds="):
			observe_live_ms = maxf(500.0, float(arg.trim_prefix("--seconds=")) * 1000.0)
		elif arg == "--dump":
			dump_frames = true
		elif arg.begins_with("--action="):
			action = arg.trim_prefix("--action=")
		elif arg == "--retain":
			retain_assets = true
		elif arg == "--retain-audio":
			retain_assets = true
		elif arg == "--drop-retained":
			drop_retained = true

	if force_mobile or target_size.x < 500:
		DeviceProfile.mobile_ui = true
		DeviceProfile.touch_controls = true
		get_tree().root.content_scale_size = Vector2i(960, 540)
	else:
		DeviceProfile.mobile_ui = false
		get_tree().root.content_scale_size = target_size
	if not quality.is_empty() and DeviceProfile.QUALITY_VALUES.has(quality):
		DeviceProfile.graphics_quality = quality
		DeviceProfile.quality_override = ""
	DeviceProfile.apply_graphics_quality()
	DisplayServer.window_set_size(target_size)
	if no_vsync:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0

	_resolve_pipeline_monitors()
	CombatProfiler.set("enabled", true)
	process_priority = 1000
	get_tree().process_frame.connect(_on_process_frame)

	audio["mix_rate"] = AudioServer.get_mix_rate()
	audio["output_latency_ms"] = snappedf(float(AudioServer.get_output_latency()) * 1000.0, 0.01)

	for _i in 3:
		await get_tree().process_frame
	await _run()


func _resolve_pipeline_monitors() -> void:
	for name in [
		"PIPELINE_COMPILATIONS_CANVAS",
		"PIPELINE_COMPILATIONS_MESH",
		"PIPELINE_COMPILATIONS_SURFACE",
		"PIPELINE_COMPILATIONS_DRAW",
		"PIPELINE_COMPILATIONS_SPECIALIZATION",
	]:
		if ClassDB.class_has_integer_constant("Performance", name):
			pipeline_monitors.append({
				"name": name.trim_prefix("PIPELINE_COMPILATIONS_").to_lower(),
				"perf": ClassDB.class_get_integer_constant("Performance", name),
				"info": ClassDB.class_get_integer_constant("RenderingServer", "RENDERING_INFO_" + name),
			})


func _on_process_frame() -> void:
	prev_frame_signal_usec = Time.get_ticks_usec()


func _monitor(id: int) -> float:
	return float(Performance.get_monitor(id))


func _pipeline_totals() -> Array:
	var out: Array = []
	for entry in pipeline_monitors:
		out.append(_monitor(int(entry["perf"])))
	return out


func _pipeline_frame_counts() -> Array:
	var out: Array = []
	for entry in pipeline_monitors:
		out.append(float(RenderingServer.get_rendering_info(int(entry["info"]))))
	return out


func _setup_ms() -> float:
	if RenderingServer.has_method("get_frame_setup_time_cpu"):
		return float(RenderingServer.call("get_frame_setup_time_cpu"))
	return 0.0


func _master_db() -> float:
	var master := AudioServer.get_bus_index("Master")
	if master < 0:
		return -80.0
	# The default Master bus is mono here; asking for channel 1 raises an error.
	return float(AudioServer.get_bus_peak_volume_left_db(master, 0))


func _run() -> void:
	if use_warmup:
		await _run_warmup()
		get_tree().set_meta("battle_prewarmed", true)
	else:
		get_tree().set_meta("battle_prewarmed", false)

	phase = "load_main"
	_sample_cache_before()
	if retain_assets:
		await _retain_warmup_assets()
	var load_started := Time.get_ticks_usec()
	var packed := load(MAIN_SCENE) as PackedScene
	load_main_ms = float(Time.get_ticks_usec() - load_started) / 1000.0
	if packed == null:
		_fail("Main.tscn did not load")
		return
	phase = "instantiate"
	var ready_started := Time.get_ticks_usec()
	instantiate_usec = ready_started
	var node := packed.instantiate()
	game = node
	add_child(game)
	_collect_audio_constants()
	if skip_clash_warm:
		game.set("_clash_warm_done", true)
		game.set("_clash_warm_running", false)
	audio["cache_music"] = ResourceLoader.has_cached(MUSIC_PATH)
	audio["cache_ambient"] = ResourceLoader.has_cached(AMBIENT_PATH)
	var cached := 0
	for path in sfx_paths:
		if ResourceLoader.has_cached(path):
			cached += 1
	audio["sfx_cached"] = cached
	audio["sfx_total"] = sfx_paths.size()

	var deadline := ready_started + 40_000_000
	while Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
		if game.get("hud") != null and String(game.get("state")) == "select":
			break
	ready_usec = Time.get_ticks_usec()
	instantiate_to_ready_ms = float(ready_usec - instantiate_usec) / 1000.0
	for _i in 10:
		await get_tree().process_frame

	# A/B: the preload we are adding to the loading screen. Everything else is
	# identical, so the difference is exactly the audio resource cost.
	if OS.get_cmdline_user_args().has("--prewarm-audio"):
		await _prewarm_audio()

	phase = "start_match"
	var start_started := Time.get_ticks_usec()
	if action == "spawn":
		await _run_spawn_steps()
		_report()
		get_tree().quit(0)
		return
	if action == "hud":
		await _run_hud_steps()
		_report()
		get_tree().quit(0)
		return
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	prev_hero_count = (game.get("heroes") as Array).size()
	deadline = start_started + 90_000_000
	while String(game.get("state")) != "live" and Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
	start_match_ms = float(Time.get_ticks_usec() - start_started) / 1000.0
	live_usec = Time.get_ticks_usec()
	phase = "live"
	_event("live", "state=live", live_usec)
	if game.get("music") != null:
		audio["music_position_at_live_ms"] = snappedf(
			float((game.get("music") as AudioStreamPlayer).get_playback_position()) * 1000.0, 0.1
		)

	var end_usec := live_usec + int(observe_live_ms * 1000.0)
	while Time.get_ticks_usec() < end_usec:
		await get_tree().process_frame

	await _save_shot()
	_collect_audio_cost()
	phase = "report"
	_report()
	await RenderingServer.frame_post_draw
	get_tree().quit(0)


func _retain_warmup_assets() -> void:
	# Repeats what the loading screen would do after the fix: load every asset
	# the match needs in its first second and hold a reference, so ResourceLoader
	# serves them from the cache instead of reading the pack again.
	var started := Time.get_ticks_usec()
	var paths: Array = [MAIN_SCENE, MUSIC_PATH, AMBIENT_PATH]
	var flow_script := load(WARMUP_FLOW_PATH) as GDScript
	if flow_script != null:
		var consts: Dictionary = flow_script.get_script_constant_map()
		for key in ["CHARACTER_SCENES", "PROP_SCENES"]:
			if consts.has(key):
				for entry in (consts[key] as Array):
					paths.append(String(entry))
	for path in sfx_paths:
		paths.append(path)
	retain_paths = paths.size()
	for path in paths:
		var resource := load(String(path))
		if resource != null:
			retained.append(resource)
	retain_ms = float(Time.get_ticks_usec() - started) / 1000.0
	print("BATTLE_START_RETAIN_MS=%.1f paths=%d" % [retain_ms, retain_paths])


func _sample_cache_before() -> void:
	# The loading screen's warm only keeps a resource in memory while something
	# still references it, so this answers whether the match has to load the
	# hero models / VFX / Main again from the pack.
	cache_before["main"] = ResourceLoader.has_cached("res://scenes/Main.tscn")
	cache_before["music"] = ResourceLoader.has_cached(MUSIC_PATH)
	cache_before["ambient"] = ResourceLoader.has_cached(AMBIENT_PATH)
	var paths: Array = []
	for path in PROBE_CACHE_PATHS:
		paths.append(path)
	var cached := 0
	for path in paths:
		if ResourceLoader.has_cached(String(path)):
			cached += 1
	cache_before["assets"] = "%d/%d" % [cached, paths.size()]
	for path in paths:
		cache_before[String(path).get_file()] = ResourceLoader.has_cached(String(path))
	print("BATTLE_START_CACHE_BEFORE=", JSON.stringify(cache_before))


## Times a second HUD build against the live game: shows how much of Main's
## one scene-open frame is hud.gd's `_ready` (game.gd owns both, so this is
## evidence for the fix there, not a change).
func _run_hud_steps() -> void:
	if game == null or not is_instance_valid(game):
		return
	var at := Time.get_ticks_usec()
	var hud: Node = load("res://scripts/hud.gd").new()
	var script_ms := float(Time.get_ticks_usec() - at) / 1000.0
	hud.name = "ProbeHUD"
	hud.set("game", game)
	at = Time.get_ticks_usec()
	game.add_child(hud)
	var ready_ms := float(Time.get_ticks_usec() - at) / 1000.0
	await get_tree().process_frame
	spawn_steps.append({"step": "hud_script_load", "ms": snappedf(script_ms, 0.01)})
	spawn_steps.append({"step": "hud_ready_build", "ms": snappedf(ready_ms, 0.01)})
	print("BATTLE_START_HUD_BUILD=", JSON.stringify(spawn_steps))
	hud.queue_free()
	await get_tree().process_frame


## Times the six `_spawn_hero` calls start_match makes in one frame. Pure
## measurement: the real start_match is not called in this mode.
func _run_spawn_steps() -> void:
	var spots := {
		"light": [
			Vector3(-2.0, 0.76, -11.5), Vector3(0.0, 0.76, -11.0), Vector3(2.0, 0.76, -11.5)
		],
		"dark": [
			Vector3(2.0, 0.76, 11.5), Vector3(0.0, 0.76, 11.0), Vector3(-2.0, 0.76, 11.5)
		],
	}
	var plan := [
		[HeroUnit.Cls.WARRIOR, 0, true, "light", 0],
		[HeroUnit.Cls.MAGE, 0, false, "light", 1],
		[HeroUnit.Cls.FAIRY, 0, false, "light", 2],
		[HeroUnit.Cls.WARRIOR, 1, false, "dark", 0],
		[HeroUnit.Cls.MAGE, 1, false, "dark", 1],
		[HeroUnit.Cls.FAIRY, 1, false, "dark", 2],
	]
	var total := 0.0
	for step in plan:
		var at := Time.get_ticks_usec()
		var spot: Array = spots[String(step[3])]
		game.call("_spawn_hero", int(step[0]), int(step[1]), bool(step[2]), spot[int(step[4])])
		var ms := float(Time.get_ticks_usec() - at) / 1000.0
		total += ms
		spawn_steps.append({"class": int(step[0]), "team": int(step[1]), "player": bool(step[2]), "ms": snappedf(ms, 0.01)})
		await get_tree().process_frame
	print("BATTLE_START_SPAWN_STEPS=", JSON.stringify({"steps": spawn_steps, "total_ms": snappedf(total, 0.01)}))


func _collect_audio_constants() -> void:
	# game.gd keeps the paths in script constants; read them so the probe never
	# drifts from the real asset list.
	var script := game.get_script() as GDScript
	if script != null:
		var consts: Dictionary = script.get_script_constant_map()
		if consts.has("SFX_PATHS") and consts["SFX_PATHS"] is Dictionary:
			for key in (consts["SFX_PATHS"] as Dictionary).keys():
				sfx_paths.append(String(consts["SFX_PATHS"][key]))
	if sfx_paths.is_empty():
		print("BATTLE_START_WARN: SFX_PATHS constants not readable")


func _prewarm_audio() -> void:
	var started := Time.get_ticks_usec()
	ResourceLoader.load_threaded_request(MUSIC_PATH)
	ResourceLoader.load_threaded_request(AMBIENT_PATH)
	for path in sfx_paths:
		ResourceLoader.load_threaded_request(path)
	var deadline := Time.get_ticks_usec() + 15_000_000
	while Time.get_ticks_usec() < deadline:
		var pending := 0
		for entry in ([MUSIC_PATH, AMBIENT_PATH] + sfx_paths):
			var status := ResourceLoader.load_threaded_get_status(String(entry))
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				pending += 1
		if pending == 0:
			break
		await get_tree().process_frame
	print("BATTLE_START_PREWARM_AUDIO_MS=%.1f" % (float(Time.get_ticks_usec() - started) / 1000.0))


func _collect_audio_cost() -> void:
	# Cached (what the match sees after a loading-screen preload) vs cold
	# (reading + parsing the import again) cost of the two long streams.
	var started := Time.get_ticks_usec()
	load(MUSIC_PATH)
	audio_cost["music_cached_ms"] = snappedf(float(Time.get_ticks_usec() - started) / 1000.0, 0.01)
	started = Time.get_ticks_usec()
	load(AMBIENT_PATH)
	audio_cost["ambient_cached_ms"] = snappedf(float(Time.get_ticks_usec() - started) / 1000.0, 0.01)
	started = Time.get_ticks_usec()
	ResourceLoader.load(MUSIC_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	audio_cost["music_cold_ms"] = snappedf(float(Time.get_ticks_usec() - started) / 1000.0, 0.01)
	started = Time.get_ticks_usec()
	ResourceLoader.load(AMBIENT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	audio_cost["ambient_cold_ms"] = snappedf(float(Time.get_ticks_usec() - started) / 1000.0, 0.01)
	started = Time.get_ticks_usec()
	for path in sfx_paths:
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	audio_cost["sfx_cold_ms"] = snappedf(float(Time.get_ticks_usec() - started) / 1000.0, 0.01)


func _run_warmup() -> void:
	phase = "warmup"
	var script: Script = load(WARMUP_FLOW_PATH) as Script
	if script == null or not script.can_instantiate():
		print("BATTLE_START_WARMUP_UNAVAILABLE")
		return
	var flow: Node = script.new()
	flow.name = "WarmupFlow"
	add_child(flow)
	if flow.get("target_seconds") != null:
		flow.set("target_seconds", warm_seconds)
	if flow.get("budget_seconds") != null:
		flow.set("budget_seconds", warm_budget)
	var deadline := Time.get_ticks_msec() + int((warm_budget + 20.0) * 1000.0)
	flow.call("start")
	while not bool(flow.call("is_finished")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var rep: Dictionary = flow.get("report")
	warm_report = rep.duplicate(true)
	# Exactly what loading_screen.gd does: keep the loaded assets until the match
	# is up. --drop-retained is the pre-fix control.
	var kept: Variant = flow.get("retained_resources")
	if kept is Array and not drop_retained:
		retained = (kept as Array).duplicate()
	retain_paths = retained.size()
	print("BATTLE_START_WARMUP=", JSON.stringify({
		"elapsed": warm_report.get("elapsed", 0.0),
		"failed": warm_report.get("failed", false),
		"truncated": warm_report.get("truncated", false),
		"sounds_warmed": warm_report.get("sounds_warmed", 0),
		"audio_preloaded": warm_report.get("audio_preloaded", 0),
		"retained": warm_report.get("retained_resources", 0),
		"kept_by_probe": retained.size(),
	}))
	flow.queue_free()
	for _i in 3:
		await get_tree().process_frame
	print("BATTLE_START_FLOW_ALIVE=", str(is_instance_valid(flow)))


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if frame_usec == 0:
		frame_usec = now
		return
	var frame_ms := float(now - frame_usec) / 1000.0
	frame_usec = now
	if instantiate_usec == 0:
		return
	var t_ms := float(now - instantiate_usec) / 1000.0
	# Stop sampling a moment after the observation window so the report and the
	# screenshot do not pollute the timeline.
	if live_usec > 0 and float(now - live_usec) / 1000.0 > observe_live_ms + 500.0:
		return
	var proc_span := 0.0
	if prev_frame_signal_usec > 0:
		proc_span = float(now - prev_frame_signal_usec) / 1000.0
	var render_span := 0.0
	if prev_probe_usec > 0 and prev_frame_signal_usec > 0:
		render_span = float(prev_frame_signal_usec - prev_probe_usec) / 1000.0
	prev_probe_usec = now
	var db := _master_db()
	raw_frames.append([
		snappedf(t_ms, 0.001),
		snappedf(frame_ms, 0.001),
		snappedf(proc_span, 0.001),
		snappedf(render_span, 0.001),
		float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
		float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0,
		_monitor(Performance.OBJECT_NODE_COUNT),
		_monitor(Performance.OBJECT_RESOURCE_COUNT),
		_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		_setup_ms(),
		_pipeline_totals(),
		_pipeline_frame_counts(),
		snappedf(db, 0.1),
	])
	_poll_live(now, db)
	if dump_frames:
		print("FRAME t=%.1f wall=%.2f proc=%.2f render=%.2f db=%.1f draws=%d"
			% [t_ms, frame_ms, proc_span, render_span, db,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])


func _poll_live(now: int, db: float) -> void:
	if game == null or not is_instance_valid(game):
		return
	var state := String(game.get("state"))
	if state != prev_state:
		prev_state = state
		_event("state", state, now)
	# Hero spawns (start_match cost, spread over frames on mobile).
	var heroes = game.get("heroes")
	if heroes != null:
		var count: int = (heroes as Array).size()
		if count > prev_hero_count:
			_event("hero_spawn", "%d heroes" % count, now)
			prev_hero_count = count
	# Audio: when each player actually starts, and when the bus is audible.
	if live_usec > 0 and db > AUDIBLE_DB and float(audio["first_audible_at_ms"]) < 0.0:
		audio["first_audible_db"] = snappedf(db, 0.1)
		audio["first_audible_at_ms"] = snappedf(float(now - live_usec) / 1000.0, 1.0)
		_event("audible", "%.1f dB" % db, now)
	var music = game.get("music")
	if music != null and is_instance_valid(music):
		_poll_player_audio(music, "music", now)
	var ambient = game.get("ambient")
	if ambient != null and is_instance_valid(ambient):
		_poll_player_audio(ambient, "ambient", now)
	for player in game.get("sfx_players"):
		_poll_player_audio(player, "game_sfx", now)


func _poll_player_audio(player: Node, label: String, now: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var id := player.get_instance_id()
	var playing := false
	var stream_path := ""
	var position := 0.0
	if player is AudioStreamPlayer:
		var stream_player := player as AudioStreamPlayer
		playing = stream_player.playing
		position = stream_player.get_playback_position()
		if stream_player.stream != null:
			stream_path = stream_player.stream.resource_path
	var was := bool(prev_audio.get(id, false))
	if playing and not was:
		_event("audio_play", "%s %s" % [label, stream_path.get_file()], now)
		var at := snappedf(float(now - live_usec) / 1000.0, 1.0) if live_usec > 0 else -1.0
		if label == "music":
			audio["music_play_calls"] = int(audio["music_play_calls"]) + 1
			if float(audio["music_started_at_ms"]) < 0.0:
				audio["music_started_at_ms"] = at
		elif label == "ambient" and float(audio["ambient_started_at_ms"]) < 0.0:
			audio["ambient_started_at_ms"] = at
		elif label == "game_sfx" and float(audio["first_sfx_at_ms"]) < 0.0:
			audio["first_sfx_at_ms"] = at
	prev_audio[id] = playing
	if label == "music" and playing and position > 0.0 and float(audio["music_position_at_live_ms"]) == -1.0:
		audio["music_position_at_live_ms"] = snappedf(position * 1000.0, 0.1)


func _event(kind: String, detail: String, at_usec: int) -> void:
	var t := 0.0
	if instantiate_usec > 0:
		t = float(at_usec - instantiate_usec) / 1000.0
	events.append({
		"t_ms": snappedf(t, 1.0),
		"since_live_ms": snappedf(float(at_usec - live_usec) / 1000.0, 1.0) if live_usec > 0 else -1.0,
		"kind": kind,
		"detail": detail,
	})


func _finalize_frames() -> Array:
	var out: Array = []
	for index in raw_frames.size():
		var row: Array = raw_frames[index]
		var prev: Array = raw_frames[maxi(index - 1, 0)]
		var pipe_delta: Array = []
		var totals_now: Array = row[11]
		var totals_prev: Array = prev[11]
		for pipe_index in totals_now.size():
			pipe_delta.append(int(float(totals_now[pipe_index]) - float(totals_prev[pipe_index])))
		var pipe_frame: Array = []
		for value in (row[12] as Array):
			pipe_frame.append(int(float(value)))
		out.append({
			"t_ms": float(prev[0]) if index > 0 else 0.0,
			"end_ms": float(row[0]),
			"since_live_ms": snappedf(float(prev[0]) - float(live_usec - instantiate_usec) / 1000.0, 1.0),
			"frame_ms": float(row[1]),
			"process_ms": snappedf(float(prev[2]) if index > 0 else float(row[2]), 0.01),
			"render_ms": snappedf(float(row[3]), 0.01),
			"perf_process_ms": snappedf(float(row[4]), 0.01),
			"perf_physics_ms": snappedf(float(row[5]), 0.01),
			"nodes": int(prev[6]),
			"resources": int(prev[7]),
			"draws": int(row[8]),
			"video_mb": snappedf(float(row[9]), 0.1),
			"setup_ms": snappedf(float(row[10]), 0.01),
			"pipe_compiled": pipe_delta,
			"pipe_frame": pipe_frame,
			"master_db": float(row[13]),
		})
	return out


func _window_stats(frames: Array, from_ms: float, to_ms: float) -> Dictionary:
	var values: Array[float] = []
	var proc_values: Array[float] = []
	var render_values: Array[float] = []
	var pipe_total := 0
	for frame in frames:
		var at := float(frame["t_ms"])
		if at >= from_ms and at < to_ms:
			values.append(float(frame["frame_ms"]))
			proc_values.append(float(frame["process_ms"]))
			render_values.append(float(frame["render_ms"]))
			for value in (frame["pipe_compiled"] as Array):
				pipe_total += int(value)
	if values.is_empty():
		return {}
	values.sort()
	proc_values.sort()
	render_values.sort()
	var total := 0.0
	var over_16 := 0
	var over_33 := 0
	var over_50 := 0
	for value in values:
		total += value
		if value > HITCH_16_MS:
			over_16 += 1
		if value > HITCH_33_MS:
			over_33 += 1
		if value > HITCH_50_MS:
			over_50 += 1
	return {
		"frames": values.size(),
		"avg_ms": snappedf(total / float(values.size()), 0.01),
		"p50_ms": snappedf(values[int(float(values.size() - 1) * 0.50)], 0.01),
		"p95_ms": snappedf(values[mini(values.size() - 1, int(float(values.size()) * 0.95))], 0.01),
		"p99_ms": snappedf(values[mini(values.size() - 1, int(float(values.size()) * 0.99))], 0.01),
		"max_ms": snappedf(values[values.size() - 1], 0.01),
		"fps_avg": snappedf(1000.0 / maxf(0.01, total / float(values.size())), 0.1),
		"over_16": over_16,
		"over_33": over_33,
		"over_50": over_50,
		"process_max_ms": snappedf(proc_values[proc_values.size() - 1], 0.01),
		"render_max_ms": snappedf(render_values[render_values.size() - 1], 0.01),
		"pipeline_compiled": pipe_total,
	}


func _spike_frames(frames: Array, threshold: float, limit := 80) -> Array:
	var out: Array = []
	for frame in frames:
		if float(frame["frame_ms"]) < threshold:
			continue
		var at := float(frame["t_ms"])
		var near: Array = []
		for event in events:
			if absf(float(event["t_ms"]) - at) <= 400.0:
				near.append(event)
		out.append({
			"t_ms": snappedf(at, 1.0),
			"since_live_ms": frame["since_live_ms"],
			"frame_ms": float(frame["frame_ms"]),
			"process_ms": float(frame["process_ms"]),
			"render_ms": float(frame["render_ms"]),
			"perf_process_ms": float(frame["perf_process_ms"]),
			"draws": int(frame["draws"]),
			"pipe_compiled": frame["pipe_compiled"],
			"master_db": float(frame["master_db"]),
			"near_events": near,
		})
		if out.size() >= limit:
			break
	return out


func _report() -> void:
	var frames := _finalize_frames()
	var live_t := float(live_usec - instantiate_usec) / 1000.0
	var render_method := String(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))
	if RenderingServer.has_method("get_current_rendering_method"):
		render_method = String(RenderingServer.call("get_current_rendering_method"))
	var adapter := ""
	if RenderingServer.has_method("get_video_adapter_name"):
		adapter = String(RenderingServer.call("get_video_adapter_name"))
	var summary := {
		"tag": tag,
		"warmup": use_warmup,
		"warm_seconds": warm_seconds if use_warmup else 0.0,
		"skip_clash_warm": skip_clash_warm,
		"window": [target_size.x, target_size.y],
		"mobile": DeviceProfile.mobile_ui,
		"quality": DeviceProfile.effective_quality(),
		"renderer": render_method,
		"adapter": adapter,
		"novsync": no_vsync,
		"load_main_ms": snappedf(load_main_ms, 0.1),
		"instantiate_to_ready_ms": snappedf(instantiate_to_ready_ms, 0.1),
		"start_match_to_live_ms": snappedf(start_match_ms, 0.1),
		"live_t_ms": snappedf(live_t, 1.0),
		"first_clash_warm_ms": int(game.get("first_clash_warm_ms")) if game != null else 0,
		"audio": audio,
		"audio_cost": audio_cost,
		"cache_before": cache_before,
		"spawn_steps": spawn_steps,
		"retain": {"on": retain_assets, "paths": retain_paths, "ms": snappedf(retain_ms, 0.1), "drop": drop_retained},
		"frames": {
			"prelive": _window_stats(frames, 0.0, maxf(0.001, live_t)),
			"live_0_300ms": _window_stats(frames, live_t, live_t + 300.0),
			"live_300_1000ms": _window_stats(frames, live_t + 300.0, live_t + 1000.0),
			"live_1000_3000ms": _window_stats(frames, live_t + 1000.0, live_t + 3000.0),
			"live_0_3000ms": _window_stats(frames, live_t, live_t + 3000.0),
			"live_0_5000ms": _window_stats(frames, live_t, live_t + 5000.0),
			"first_5s": _window_stats(frames, 0.0, live_t + 5000.0),
			"all": _window_stats(frames, 0.0, 1.0e9),
		},
		"spikes_33": _spike_frames(frames, HITCH_33_MS),
		"spikes_16": _spike_frames(frames, HITCH_16_MS, 40),
		"events": events,
		"warmup_report": warm_report,
		"screenshot": shot_path,
	}
	if dump_frames:
		summary["raw_frames"] = frames
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := "%s/battle_start_%s.json" % [OUT_DIR, tag]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(summary, "  "))
		file.close()
	var live_window: Dictionary = summary["frames"]["live_0_3000ms"]
	print("BATTLE_START_JSON=", ProjectSettings.globalize_path(path))
	print("BATTLE_START_SUMMARY=", JSON.stringify({
		"tag": tag,
		"warmup": use_warmup,
		"action": action,
		"live_t_ms": summary["live_t_ms"],
		"start_match_to_live_ms": summary["start_match_to_live_ms"],
		"live_0_3000": live_window,
		"live_0_5000": (summary["frames"] as Dictionary)["live_0_5000ms"],
		"first_5s": (summary["frames"] as Dictionary)["first_5s"],
		"prelive": (summary["frames"] as Dictionary)["prelive"],
		"audio": audio,
		"audio_cost": audio_cost,
		"cache_before": cache_before,
		"spawn_steps": spawn_steps,
		"source": path,
	}))


func _save_shot() -> void:
	if shot_path != "":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := "%s/battle_start_%s.png" % [OUT_DIR, tag]
	image.save_png(path)
	shot_path = ProjectSettings.globalize_path(path)
	print("BATTLE_START_SHOT=", shot_path)


func _fail(message: String) -> void:
	print("BATTLE_START_FAIL: ", message)
	get_tree().quit(2)
