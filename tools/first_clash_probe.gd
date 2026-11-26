extends Node3D

## First-clash hitch probe (read-only QA tool).
##
## Starts the real Main.tscn with bots, waits for `state == "live"`, then forces
## one deterministic clash at a known moment (player teleported next to an
## enemy, attack / damage / VFX / ability / kill) and records:
##   * per-frame wall time (Time.get_ticks_usec),
##   * Performance TIME_PROCESS / TIME_PHYSICS,
##   * render pipeline compilation counters (when the engine exposes them),
##   * draw calls, nodes, resources, VRAM,
##   * first hit / VFX / sound / damage number / kill / bot spawn / cast,
##   * CombatProfiler marks (spawn durations are already instrumented there).
##
## It changes no gameplay, balance or cooldowns: the forced clash only calls
## existing public-ish methods on the already spawned heroes.
##
## Run windowed, one configuration per process:
##   godot_console --path . tools/FirstClashProbe.tscn -- --warm --tag=warm-desktop-high --quality=high --novsync
##   godot_console --path . tools/FirstClashProbe.tscn -- --no-warm --tag=nowarm-desktop-high --quality=high --novsync
##   godot_console --path . tools/FirstClashProbe.tscn -- --warm --layout=844x390 --mobile --quality=low --tag=warm-mobile-low
##   godot_console --path . tools/FirstClashProbe.tscn -- --warm --rendering-method gl_compatibility --tag=warm-compat
##
## Diagnostic actions (isolate one subsystem at the forced moment):
##   --action=clash (default) | attack | hit | vfx | number | ability | kill
##   --ability=2   index for --action=ability (warrior: 2 = ultimate)
##
## Writes res://docs/qa-first-clash/first_clash_<tag>.json + .png and prints
## FIRST_CLASH_SUMMARY=... / FIRST_CLASH_JSON=...

const MAIN_SCENE := "res://scenes/Main.tscn"
const WARMUP_FLOW_PATH := "res://scripts/warmup_flow.gd"
const OUT_DIR := "res://docs/qa-first-clash"

const HITCH_16_MS := 16.67
const HITCH_33_MS := 33.34
const HITCH_50_MS := 50.0

var tag := "run"
var target_size := Vector2i(1440, 734)
var force_mobile := false
var quality := "high"
var no_vsync := true
var use_warmup := false
var action := "clash"
var ability_index := 2
var delay_ms := 300.0
var observe_ms := 5000.0
var dump_frames := false
var prewarm_real := false
var skip_clash_warm := false

var game: Node = null
var phase := "boot"
var live_usec := 0
var forced_usec := 0
var frame_usec := 0

# One entry per rendered frame:
# [t_ms, frame_ms, process_s, physics_s, nodes, resources, draws,
#  pipe_scene, pipe_canvas, pipe_surface, pipe_draw, video_mb, setup_ms]
var raw_frames: Array = []

var events: Array = []
var first: Dictionary = {}
var seen_marks: Dictionary = {}
var pipeline_monitors: Array = []

var prev_health: Dictionary = {}
var prev_dead: Dictionary = {}
var prev_audio: Dictionary = {}
var prev_feed := 0
var prev_hero_count := 0
var hero_spawns: Array = []

var frame_signal_usec := 0
var prev_probe_usec := 0

var warm_report: Dictionary = {}
var load_main_ms := 0.0
var ready_ms := 0.0
var start_match_ms := 0.0
var forced_cpu_ms := 0.0
var forced_steps: Array = []
var shot_path := ""


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
		elif arg == "--no-warm":
			use_warmup = false
		elif arg.begins_with("--action="):
			action = arg.trim_prefix("--action=")
		elif arg.begins_with("--ability="):
			ability_index = int(arg.trim_prefix("--ability="))
		elif arg.begins_with("--delay="):
			delay_ms = maxf(0.0, float(arg.trim_prefix("--delay=")))
		elif arg.begins_with("--seconds="):
			observe_ms = maxf(600.0, float(arg.trim_prefix("--seconds=")) * 1000.0)
		elif arg == "--dump":
			dump_frames = true
		elif arg == "--prewarm-real":
			prewarm_real = true
		elif arg == "--skip-clash-warm":
			skip_clash_warm = true

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
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0

	_resolve_pipeline_monitors()
	if dump_frames:
		_dump_constants()
	# CombatProfiler marks spawn_vfx / damage_number / take_damage / attack /
	# ability durations. Its own hitch print stays; we only read the ring.
	CombatProfiler.set("enabled", true)
	process_priority = 1000
	get_tree().process_frame.connect(_on_process_frame)

	for _i in 3:
		await get_tree().process_frame
	await _run()


func _resolve_pipeline_monitors() -> void:
	# Both counter families exist in 4.7.2:
	#  * Performance.PIPELINE_COMPILATIONS_* are running totals (delta per frame),
	#  * RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_* are per-frame.
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


func _dump_constants() -> void:
	for cls_name in ["Performance", "RenderingServer"]:
		for name in ClassDB.class_get_integer_constant_list(cls_name):
			var upper := String(name).to_upper()
			if upper.contains("PIPELINE") or upper.contains("COMPIL"):
				print("CONST ", cls_name, ".", name, "=", ClassDB.class_get_integer_constant(cls_name, name))


func _on_process_frame() -> void:
	frame_signal_usec = Time.get_ticks_usec()


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


func _run() -> void:
	if use_warmup:
		await _run_warmup()
		get_tree().set_meta("battle_prewarmed", true)
	else:
		get_tree().set_meta("battle_prewarmed", false)

	phase = "load_main"
	var load_started := Time.get_ticks_usec()
	var packed := load(MAIN_SCENE) as PackedScene
	load_main_ms = float(Time.get_ticks_usec() - load_started) / 1000.0
	if packed == null:
		_fail("Main.tscn did not load")
		return
	phase = "instantiate"
	var ready_started := Time.get_ticks_usec()
	game = packed.instantiate()
	add_child(game)
	if skip_clash_warm:
		# A/B control: cancel the game's real-world first-clash warm, so this
		# run measures the pre-fix behaviour while everything else is identical.
		game.set("_clash_warm_done", true)
		game.set("_clash_warm_running", false)
	var deadline := ready_started + 40_000_000
	while Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
		if game.get("hud") != null and String(game.get("state")) == "select":
			break
	ready_ms = float(Time.get_ticks_usec() - ready_started) / 1000.0
	for _i in 10:
		await get_tree().process_frame
	if prewarm_real:
		await _prewarm_real_assets()

	phase = "start_match"
	var start_started := Time.get_ticks_usec()
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	deadline = start_started + 90_000_000
	prev_hero_count = (game.get("heroes") as Array).size()
	while String(game.get("state")) != "live" and Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
		_poll_spawns(Time.get_ticks_usec())
	start_match_ms = float(Time.get_ticks_usec() - start_started) / 1000.0
	live_usec = Time.get_ticks_usec()
	phase = "live"
	frame_usec = live_usec

	# Let two frames pass so the "live" frame itself is not the clash frame.
	var force_at := live_usec + int(delay_ms * 1000.0)
	while Time.get_ticks_usec() < force_at:
		await get_tree().process_frame

	forced_usec = Time.get_ticks_usec()
	phase = "clash"
	_event("probe", "forced_%s" % action, float(forced_usec) / 1000.0, true)
	await _force_clash()
	phase = "observe"
	var end_usec := forced_usec + int(observe_ms * 1000.0)
	while Time.get_ticks_usec() < end_usec:
		await get_tree().process_frame

	await _save_shot()
	phase = "report"
	_report()
	await RenderingServer.frame_post_draw
	get_tree().quit(0)


func _prewarm_real_assets() -> void:
	# Experiment: draw the first-clash assets in the real World3D (same
	# environment/fog/shadow state as the match), unlike WarmupFlow's own-world
	# SubViewport. This is the candidate fix for game.gd.
	var started := Time.get_ticks_usec()
	var viewport := SubViewport.new()
	viewport.name = "ProbeRealWarmViewport"
	viewport.size = Vector2i(192, 192)
	viewport.own_world_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	game.add_child(viewport)
	var camera := Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.1
	camera.far = 60.0
	camera.position = Vector3(0.0, -94.0, 8.0)
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, -100.0, 0.0), Vector3.UP)
	camera.current = true
	for _frame in 2:
		await get_tree().process_frame

	var vfx_paths := [
		"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/hit/vfx_hit_01.tscn",
		"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/hit/vfx_hit_02.tscn",
		"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/big_impact/vfx_big_impact_01.tscn",
		"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/big_impact/vfx_big_impact_02.tscn",
		"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/impact/vfx_impact_01.tscn",
		"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/impact/vfx_impact_02.tscn",
	]
	for path in vfx_paths:
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var effect := packed.instantiate() as Node3D
		if effect == null:
			continue
		game.add_child(effect)
		effect.global_position = Vector3(0.0, -100.0, 0.0)
		effect.visible = true
		for node in effect.find_children("*", "GeometryInstance3D", true, false):
			var material := node.get("material_override") as StandardMaterial3D
			if material != null:
				material.emission_enabled = true
				material.emission = Color.WHITE
				material.emission_energy_multiplier = 1.6
		for node in effect.find_children("*", "Light3D", true, false):
			var light := node as Light3D
			light.light_energy = 2.0
			light.light_color = Color(1.0, 0.8, 0.4)
		if effect.has_method("play"):
			effect.call("play")
		for _frame in 2:
			await get_tree().process_frame
		effect.queue_free()
		await get_tree().process_frame

	var font := preload("res://assets/fonts/Philosopher-Regular.ttf")
	for size in [64, 76]:
		var label := Label3D.new()
		label.text = "1234"
		label.font = font
		label.font_size = size
		label.pixel_size = 0.008
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.outline_size = 12
		label.outline_modulate = Color(0.05, 0.03, 0.08, 0.9)
		label.modulate = Color(1.0, 0.92, 0.65)
		game.add_child(label)
		label.global_position = Vector3(0.0, -100.0, 0.0)
		for _frame in 2:
			await get_tree().process_frame
		label.queue_free()
		await get_tree().process_frame

	if is_instance_valid(viewport):
		viewport.queue_free()
	await get_tree().process_frame
	print("FIRST_CLASH_PREWARM_REAL_MS=%.1f" % (float(Time.get_ticks_usec() - started) / 1000.0))


func _run_warmup() -> void:
	phase = "warmup"
	var script: Script = load(WARMUP_FLOW_PATH) as Script
	if script == null or not script.can_instantiate():
		print("FIRST_CLASH_WARMUP_UNAVAILABLE")
		return
	var flow: Node = script.new()
	flow.name = "WarmupFlow"
	add_child(flow)
	var deadline := Time.get_ticks_msec() + 120000
	flow.call("start")
	while not bool(flow.call("is_finished")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var rep: Dictionary = flow.get("report")
	warm_report = rep.duplicate(true)
	print("FIRST_CLASH_WARMUP=", JSON.stringify(warm_report))
	flow.queue_free()
	for _i in 3:
		await get_tree().process_frame


func _process(_delta: float) -> void:
	if game == null:
		return
	var now := Time.get_ticks_usec()
	if frame_usec == 0:
		frame_usec = now
		return
	var frame_ms := float(now - frame_usec) / 1000.0
	frame_usec = now
	if live_usec == 0:
		return
	if String(game.get("state")) != "live" and phase != "report":
		return
	var t_ms := float(now - live_usec) / 1000.0
	var proc_span := 0.0
	if frame_signal_usec > 0:
		proc_span = float(now - frame_signal_usec) / 1000.0
	var render_span := 0.0
	if prev_probe_usec > 0 and frame_signal_usec > 0:
		render_span = float(frame_signal_usec - prev_probe_usec) / 1000.0
	prev_probe_usec = now
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
	])
	_poll_live(now)
	if dump_frames:
		print("FRAME t=%.1f wall=%.2f proc_span=%.2f render_span=%.2f perf_proc=%.1f draws=%d setup=%.2f"
			% [t_ms, frame_ms, proc_span, render_span,
				float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				_setup_ms()])


func _poll_spawns(now: int) -> void:
	if game == null:
		return
	var heroes = game.get("heroes")
	var count: int = heroes.size()
	if count > prev_hero_count:
		for index in range(prev_hero_count, count):
			var hero = heroes[index]
			var entry := {
				"t_ms": snappedf(float(now - live_usec) / 1000.0, 0.1) if live_usec > 0 else 0.0,
				"name": String(hero.get("display_name")),
				"team": int(hero.get("team")),
				"player": bool(hero.get("is_player")),
			}
			hero_spawns.append(entry)
			_event("bot_spawn", "%s team=%d" % [entry["name"], int(entry["team"])], float(now) / 1000.0, true)
		prev_hero_count = count


func _poll_live(now: int) -> void:
	_poll_spawns(now)
	_poll_marks(now)
	if game == null:
		return
	var heroes = game.get("heroes")
	for hero in heroes:
		if hero == null or not is_instance_valid(hero):
			continue
		var id: int = hero.get_instance_id()
		var hp := float(hero.get("health"))
		if prev_health.has(id) and hp < float(prev_health[id]) - 0.01:
			_event("damage", "%s %.0f->%.0f" % [String(hero.get("display_name")), float(prev_health[id]), hp], float(now) / 1000.0, false)
		prev_health[id] = hp
		var dead := bool(hero.get("dead"))
		if dead and not bool(prev_dead.get(id, false)):
			_event("death", String(hero.get("display_name")), float(now) / 1000.0, false)
		prev_dead[id] = dead
		_poll_audio(hero, now)
	var sfx = game.get("sfx_players")
	for player in sfx:
		_poll_player_audio(player, "game_sfx", now)
	var hud: Node = game.get("hud")
	if hud != null:
		var feed: Node = hud.get("kill_feed_box")
		if feed != null:
			var rows := feed.get_child_count()
			if rows > prev_feed:
				_event("kill_feed", "rows=%d" % rows, now / 1000, false)
			prev_feed = rows


func _poll_audio(hero: Node, now: int) -> void:
	for child in hero.get_children():
		var name := String(child.name)
		if name.begins_with("CombatAudio_") or name == "Footsteps" or name == "AbilitySfx":
			_poll_player_audio(child, name, now)


func _poll_player_audio(player: Node, label: String, now: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var id := player.get_instance_id()
	var playing := false
	var stream_path := ""
	if player is AudioStreamPlayer:
		playing = (player as AudioStreamPlayer).playing
		var stream := (player as AudioStreamPlayer).stream
		if stream != null:
			stream_path = stream.resource_path
	elif player is AudioStreamPlayer3D:
		playing = (player as AudioStreamPlayer3D).playing
		var stream3 := (player as AudioStreamPlayer3D).stream
		if stream3 != null:
			stream_path = stream3.resource_path
	if playing and not bool(prev_audio.get(id, false)):
		var detail := "%s %s" % [label, stream_path.get_file()]
		_event("sound", detail, float(now) / 1000.0, false)
		if label.contains("Impact"):
			_event("sound_hit", detail, float(now) / 1000.0, true)
	prev_audio[id] = playing


func _poll_marks(now: int) -> void:
	var marks: Array = CombatProfiler.get("_events")
	for entry in marks:
		var key := String(entry)
		if seen_marks.has(key):
			continue
		seen_marks[key] = true
		var parts := key.split(" ", true, 2)
		if parts.size() < 2:
			continue
		var at_ms := int(parts[0])
		var kind := String(parts[1])
		var detail := String(parts[2]) if parts.size() > 2 else ""
		_event("mark_" + kind, detail, at_ms, true)
		if kind == "vfx":
			_event("vfx", detail, at_ms, false)
		elif kind == "number":
			_event("damage_number", detail, at_ms, false)
		elif kind == "hit":
			_event("hit", detail, at_ms, false)
		elif kind == "ability":
			_event("cast", detail, at_ms, false)
		elif kind == "attack":
			_event("attack", detail, at_ms, false)
		elif kind == "shell":
			_event("shell", detail, at_ms, false)


## Records the first occurrence of `kind` and appends every event to the
## timeline. `critical` kinds set the first-* flags used in the summary.
func _event(kind: String, detail: String, at_ms: float, _critical: bool) -> void:
	var t := 0.0
	if live_usec > 0:
		t = snappedf((at_ms * 1000.0 - float(live_usec)) / 1000000.0, 0.001)
	if not first.has(kind):
		first[kind] = {
			"t_ms": snappedf(t * 1000.0, 1.0),
			"frame": raw_frames.size(),
			"detail": detail,
		}
	events.append({
		"t_ms": snappedf(t * 1000.0, 1.0),
		"frame": raw_frames.size(),
		"kind": kind,
		"detail": detail,
	})


func _pick_enemy(player: Node) -> Node:
	var team := int(player.get("team"))
	var heroes: Array = game.get("heroes")
	for hero in heroes:
		if hero == null or not is_instance_valid(hero):
			continue
		if int(hero.get("team")) == team or bool(hero.get("dead")):
			continue
		return hero
	return null


func _face_target(hero: Node, target: Node) -> void:
	var target_pos: Vector3 = target.get("global_position")
	var hero_pos: Vector3 = hero.get("global_position")
	var direction: Vector3 = target_pos - hero_pos
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return
	hero.call("_face", direction, 1.0)
	var facing: Vector3 = hero.call("_facing_direction")
	if facing.dot(direction.normalized()) < 0.0:
		var visual: Node3D = hero.get("visual")
		if visual != null:
			visual.rotation.y += PI


func _force_clash() -> void:
	var player: Node = game.get("player")
	if player == null or not is_instance_valid(player):
		_fail("no player at clash time")
		return
	var enemy := _pick_enemy(player)
	if enemy == null:
		_fail("no enemy at clash time")
		return
	# Centre of the arena: neither base shield blocks outgoing damage.
	var spot := Vector3(0.0, 0.76, 0.0)
	player.set("spawn_protection", 0.0)
	enemy.set("spawn_protection", 0.0)
	(player as Node3D).global_position = spot
	(enemy as Node3D).global_position = spot + Vector3(0.0, 0.0, 2.2)
	(player as Node3D).velocity = Vector3.ZERO
	(enemy as Node3D).velocity = Vector3.ZERO
	_face_target(player, enemy)

	var at := Time.get_ticks_usec()
	match action:
		"vfx":
			player.call("spawn_attack_impact_vfx", (enemy as Node3D).global_position + Vector3(0.0, 0.9, 0.0))
		"number":
			game.call("damage_number", (player as Node3D).global_position + Vector3(0.0, 2.0, 0.0), 123.0, 0, false, false)
		"hit":
			enemy.call("take_damage", 120.0, player)
		"ability":
			player.set("attack_cd", 0.0)
			player.call("use_ability", ability_index, true)
		"kill":
			enemy.set("health", 1.0)
			player.set("attack_cd", 0.0)
			player.call("_try_auto_attack", Vector3.ZERO)
		_:
			player.set("attack_cd", 0.0)
			player.call("_try_auto_attack", Vector3.ZERO)
	forced_cpu_ms = float(Time.get_ticks_usec() - at) / 1000.0
	forced_steps.append({"step": action, "cpu_ms": snappedf(forced_cpu_ms, 0.01)})
	if action == "clash":
		await get_tree().create_timer(0.16).timeout
		if is_instance_valid(enemy) and not bool(enemy.get("dead")):
			_face_target(enemy, player)
			enemy.set("attack_cd", 0.0)
			var at2 := Time.get_ticks_usec()
			enemy.call("_try_auto_attack", Vector3.ZERO)
			forced_steps.append({"step": "enemy_attack", "cpu_ms": snappedf(float(Time.get_ticks_usec() - at2) / 1000.0, 0.01)})


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
		# row[k] is sampled at the start of the next process callback: its
		# wall delta describes the frame that ENDED here, so process work comes
		# from the previous row, render time and render info from this one.
		out.append({
			"t_ms": float(prev[0]) if index > 0 else 0.0,
			"end_ms": float(row[0]),
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
		})
	return out


func _window_stats(frames: Array, from_ms: float, to_ms: float) -> Dictionary:
	var values: Array[float] = []
	var proc_values: Array[float] = []
	var render_values: Array[float] = []
	for frame in frames:
		var at := float(frame["t_ms"])
		if at >= from_ms and at < to_ms:
			values.append(float(frame["frame_ms"]))
			proc_values.append(float(frame["process_ms"]))
			render_values.append(float(frame["render_ms"]))
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
	}


func _events_between(from_ms: float, to_ms: float) -> Array:
	var out: Array = []
	for event in events:
		var at := float(event["t_ms"])
		if at >= from_ms and at <= to_ms:
			out.append(event)
	return out


func _spike_frames(frames: Array, threshold: float, limit := 120) -> Array:
	var out: Array = []
	for frame in frames:
		if float(frame["frame_ms"]) < threshold:
			continue
		var at := float(frame["t_ms"])
		out.append({
			"t_ms": snappedf(at, 1.0),
			"frame_ms": float(frame["frame_ms"]),
			"process_ms": float(frame["process_ms"]),
			"render_ms": float(frame["render_ms"]),
			"perf_process_ms": float(frame["perf_process_ms"]),
			"perf_physics_ms": float(frame["perf_physics_ms"]),
			"draws": int(frame["draws"]),
			"nodes": int(frame["nodes"]),
			"pipe_compiled": frame["pipe_compiled"],
			"pipe_frame": frame["pipe_frame"],
			"setup_ms": float(frame["setup_ms"]),
			"near_events": _events_between(at - 400.0, at + 40.0),
		})
		if out.size() >= limit:
			break
	return out


func _report() -> void:
	var frames := _finalize_frames()
	var forced_t := float(forced_usec - live_usec) / 1000.0
	var clash_window := _window_stats(frames, forced_t, forced_t + 1500.0)
	var start_window := _window_stats(frames, 0.0, maxf(0.001, forced_t))
	var render_method := String(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))
	if RenderingServer.has_method("get_current_rendering_method"):
		render_method = String(RenderingServer.call("get_current_rendering_method"))
	var adapter := ""
	if RenderingServer.has_method("get_video_adapter_name"):
		adapter = String(RenderingServer.call("get_video_adapter_name"))
	var monitors: Array[String] = []
	for entry in pipeline_monitors:
		monitors.append(String(entry["name"]))
	var summary := {
		"tag": tag,
		"warmup": use_warmup,
		"action": action,
		"window": [target_size.x, target_size.y],
		"canvas": [int(get_viewport().get_visible_rect().size.x), int(get_viewport().get_visible_rect().size.y)],
		"mobile": DeviceProfile.mobile_ui,
		"quality": DeviceProfile.effective_quality(),
		"renderer": render_method,
		"adapter": adapter,
		"novsync": no_vsync,
		"load_main_ms": snappedf(load_main_ms, 0.1),
		"ready_ms": snappedf(ready_ms, 0.1),
		"start_match_to_live_ms": snappedf(start_match_ms, 0.1),
		"first_clash_warm_ms": int(game.get("first_clash_warm_ms")),
		"first_clash_warm_done": bool(game.get("_clash_warm_done")),
		"forced_t_ms": snappedf(forced_t, 1.0),
		"forced_cpu_ms": snappedf(forced_cpu_ms, 0.01),
		"forced_steps": forced_steps,
		"first_clash_window": clash_window,
		"first_clash_max_ms": float(clash_window.get("max_ms", 0.0)),
		"first": first,
		"hero_spawns": hero_spawns,
		"frames": {
			"start_0_to_clash": start_window,
			"clash_0_200ms": _window_stats(frames, forced_t, forced_t + 200.0),
			"clash_0_1500ms": clash_window,
			"post_1500ms": _window_stats(frames, forced_t + 1500.0, 1.0e9),
			"all": _window_stats(frames, 0.0, 1.0e9),
		},
		"pipeline_monitors": monitors,
		"spikes_33": _spike_frames(frames, HITCH_33_MS),
		"spikes_16": _spike_frames(frames, HITCH_16_MS, 60),
		"events": events,
		"warmup_report": warm_report,
		"screenshot": shot_path,
	}
	if dump_frames:
		summary["raw_frames"] = raw_frames
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := "%s/first_clash_%s.json" % [OUT_DIR, tag]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(summary, "  "))
		file.close()
	print("FIRST_CLASH_JSON=", ProjectSettings.globalize_path(path))
	print("FIRST_CLASH_SUMMARY=", JSON.stringify({
		"tag": tag,
		"warmup": use_warmup,
		"action": action,
		"max_ms": summary["first_clash_max_ms"],
		"over_33": clash_window.get("over_33", 0),
		"over_50": clash_window.get("over_50", 0),
		"all_max_ms": (summary["frames"] as Dictionary)["all"].get("max_ms", 0.0),
		"forced_cpu_ms": summary["forced_cpu_ms"],
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
	var path := "%s/first_clash_%s.png" % [OUT_DIR, tag]
	image.save_png(path)
	shot_path = ProjectSettings.globalize_path(path)
	print("FIRST_CLASH_SHOT=", shot_path)


func _fail(message: String) -> void:
	print("FIRST_CLASH_FAIL: ", message)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := "%s/first_clash_%s.json" % [OUT_DIR, tag]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"tag": tag, "error": message, "first": first, "events": events}, "  "))
		file.close()
	get_tree().quit(2)
