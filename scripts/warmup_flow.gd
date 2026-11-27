class_name WarmupFlow
extends Node

## Pre-match warmup that runs while the welcome card is still on screen.
##
## The arena, the three fighters (plus shop skins), weapons, props, VFX,
## 3D/2D shaders and the first-clash sounds are loaded and rendered once in a
## hidden SubViewport before the scene switches to Main.tscn. The player never
## sees a dark screen: lobby.gd shows WelcomeOverlay in WARMING and starts the
## match from the `finished` signal.
##
## Pacing: the search screen gives ~30 s, so the work is spread over ~21 s (see
## PACING_* below) instead of running flat out in ~10 s. A short quiet start,
## then one step at a time with a measured pause between steps, and the hidden
## viewport draws only the frames the flow asks for. The machine is never pegged
## from the first second, and the loading screen stays smooth.
##
## Safety: Main.tscn is instantiated with its game.gd script removed, so no
## match starts, no HUD is created, no network connection is opened and no
## music plays. The instance is freed at the end; the resources the flow loaded
## (Main, the fighter models, the arena props, the battle audio) are handed to
## the loading screen's keeper instead, so Main finds them in the loader cache
## and does not read them from the pack again in its first frames.
##
## API:
##   var flow := WarmupFlow.new()
##   add_child(flow)
##   flow.progress_changed.connect(_on_progress)  # percent, elapsed, stage
##   flow.finished.connect(_on_ready)
##   flow.start()
##
## Mobile two-pass mode: the arena is rendered first, then freed (with its
## viewport), and a second viewport warms fighters, weapons, VFX and shaders.
## The arena therefore never shares VRAM with the fighter/prop/VFX set, which
## is the moment the weakest phones used to run out of texture memory. The mode
## is automatic on mobile only when the arena pass alone is already heavy
## (TWO_PASS_TRIGGER_MB); `two_pass_policy` ("auto"/"on"/"off") and the
## --warmup-two-pass / --warmup-single-pass user args override it for testing.

signal progress_changed(percent: float, elapsed: float, stage: String)
signal finished

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const GAME_SCRIPT_PATH := "res://scripts/game.gd"
const VFX_PRELOADER := preload("res://scripts/vfx_preloader.gd")
const BATTLE_AUDIO := preload("res://scripts/audio_preloader.gd")

const TWO_PASS_POLICY_AUTO := "auto"
const TWO_PASS_POLICY_ON := "on"
const TWO_PASS_POLICY_OFF := "off"
## Video memory after the arena pass above which a second pass is worth it.
const TWO_PASS_TRIGGER_MB := 380.0
## Mobile floor: the arena pass is only part of the peak — the fighter, weapon
## and VFX set measured another ~60-70 MB on top of it. A phone whose arena
## alone is already past 320 MB has no room for that overlap.
const TWO_PASS_MOBILE_BUDGET_MB := 320.0

## Base rigs and the two cosmetic skins that HeroUnit can spawn.
const CHARACTER_SCENES := [
	"res://art/generated/warrior/character.tscn",
	"res://art/generated/mage/character.tscn",
	"res://art/generated/fairy/character.tscn",
	"res://art/generated/warrior_barbarian/character.tscn",
	"res://art/generated/fairy_hooded/character.tscn",
]

## External weapons, the legendary bow and the arena props game.gd adds at
## runtime (shop stall, crystals) — the exact assets the first frame needs.
const PROP_SCENES := [
	"res://addons/low_poly_rpg_items/models/battle_axe_model.glb",
	"res://addons/low_poly_rpg_items/models/short_bow_model.glb",
	"res://addons/low_poly_rpg_items/models/staff_wizard_model.glb",
	"res://addons/low_poly_rpg_items/models/longsword_model.glb",
	"res://addons/low_poly_rpg_items/models/round_shield_model.glb",
	"res://addons/low_poly_rpg_items/models/helmet_nasal_model.glb",
	"res://scenes/LegendaryBow.tscn",
	"res://assets/shop_stall/3d_4f92fe433b084100af7a1d7f_1790958942025.glb",
	"res://assets/models/detail-crystal.glb",
	"res://assets/kaykit_arena/medieval/building_well_green.gltf",
	"res://assets/kaykit_arena/resource/Gold_Bars.gltf",
	"res://assets/kaykit_arena/resource/Gold_Nuggets.gltf",
	"res://assets/kaykit_arena/dungeon/coin_stack_large.glb",
	"res://assets/kaykit_arena/dungeon/crates_stacked.glb",
	"res://assets/kaykit_arena/dungeon/barrel_large.glb",
	"res://assets/kaykit_arena/resource/Wood_Log_Stack.gltf",
	"res://assets/kaykit_arena/resource/Textiles_A.gltf",
	"res://assets/kaykit_arena/restaurant/pot_A.gltf",
]

const SPATIAL_SHADERS := [
	"res://shaders/health_bar.gdshader",
	"res://shaders/legendary_bow.gdshader",
	"res://shaders/cloud_wall.gdshader",
	"res://shaders/soft_ground_glow.gdshader",
	"res://shaders/fog_of_war.gdshader",
]

const CANVAS_SHADERS := [
	"res://shaders/ability_cooldown_mask.gdshader",
	"res://shaders/ability_icon_mask.gdshader",
	"res://shaders/low_health_vignette.gdshader",
	"res://shaders/card_portrait.gdshader",
]

const STAGE_LOAD := "Загрузка арены"
const STAGE_AUDIO := "Звук боя"
const STAGE_CACHE := "Кэш боя"
const STAGE_INSTANCE := "Инстанс арены"
const STAGE_ARENA := "Материалы арены"
const STAGE_HEROES := "Бойцы и скины"
const STAGE_WEAPONS := "Оружие и предметы"
const STAGE_VFX := "Эффекты и шейдеры"
const STAGE_SHADERS := "Шейдеры"
const STAGE_SWITCH := "Второй проход"
const STAGE_FINAL := "Финальный рендер"
const STAGE_DONE := "Готово"

## Pacing. The player is already waiting for the match search (30 s), so the
## same amount of work is deliberately spread over ~21 s instead of ~10 s: a
## short quiet start, then one step at a time with a measured pause between
## steps. The machine is never pegged from the first second, the search screen
## keeps animating smoothly and the warmup still fits the search window.
const PACING_TARGET_SECONDS := 21.0
const PACING_TARGET_SECONDS_MOBILE := 23.0
## Hard ceiling. The search screen waits for the warmup at most 30 s and needs
## a couple of frames for the scene switch, so the flow stops itself at 28 s
## and reports a truncation instead of risking a hang.
const PACING_HARD_BUDGET_SECONDS := 28.0
## Quiet start on the loading screen before the first heavy step.
const PACING_START_DELAY_SECONDS := 1.4
## Share of wall time the warmup may keep the machine busy. The rest is the
## loading screen at idle between steps.
const PACING_DUTY := 0.45
const PACING_MAX_PAUSE_SECONDS := 1.5
const PACING_MIN_PAUSE_SECONDS := 0.12
## The loading screen's own first draw (background + font atlas upload) lands in
## the first frames and existed before any warmup. Frame samples after this mark
## describe the warmup itself.
const PACING_START_SETTLED_SECONDS := 0.25

## Hidden viewports are small on purpose: shader and pipeline compilation does
## not depend on resolution, and a smaller target keeps the fill rate cheap.
## The arena pass keeps its original size: `video_after_arena_mb` is measured
## there and the two-pass VRAM guard is calibrated against it, so shrinking it
## would make the guard under-report the real arena by ~0.7 MB.
const ARENA_VIEWPORT_SIZE := Vector2i(384, 216)
const VIEWPORT_WIDTH_DESKTOP := 320
const VIEWPORT_WIDTH_MOBILE := 288
const CANVAS_VIEWPORT_SIZE := 32

var report := {
	"main_scene_loaded": false,
	"main_script_stripped": false,
	"arena_children": 0,
	"heroes_warmed": 0,
	"props_warmed": 0,
	"vfx_scenes_warmed": 0,
	"sounds_warmed": 0,
	"audio_preloaded": 0,
	"retained_resources": 0,
	"retain_ms": 0,
	"shaders_warmed": 0,
	"frames_rendered": 0,
	"main_freed": false,
	"failed": false,
	"error": "",
	"stage_times": {},
	"elapsed": 0.0,
	"peak_static_mb": 0.0,
	"peak_video_mb": 0.0,
	"pass1_video_mb": 0.0,
	"pass2_video_mb": 0.0,
	"video_after_arena_mb": 0.0,
	"video_after_vfx_mb": 0.0,
	"video_after_arena_free_mb": 0.0,
	"two_pass": false,
	"two_pass_policy": TWO_PASS_POLICY_AUTO,
	"two_pass_reason": "",
	"two_pass_switch_ms": 0,
	"two_pass_switch_s": 0.0,
	"video_mem_available": false,
	"mobile": false,
	"quality": "unknown",
	"stats_tracked": false,
	"frame_ms_avg": 0.0,
	"frame_ms_p95": 0.0,
	"frame_ms_max": 0.0,
	"first2s_max_frame_ms": 0.0,
	"first2s_max_at_s": 0.0,
	"first2s_settled_max_frame_ms": 0.0,
	"frames_sampled": 0,
	"pauses_s": 0.0,
	"work_s": 0.0,
	"pacing_target_s": 0.0,
	"paced": false,
	"deadline_hit": false,
	"truncated": false,
}

## "auto" (mobile + heavy arena), "on" (always) or "off". Probes and the
## --warmup-two-pass / --warmup-single-pass args override it before start().
var two_pass_policy := TWO_PASS_POLICY_AUTO

## A/B probe hook: retain the fighter/prop scenes as they are loaded (the
## behaviour that broke the mobile two-pass budget). Off by default.
var retain_early := false

## Resources the flow loaded and keeps referenced for the match. The loader
## cache alone does not keep a resource alive: as soon as the warmed instance is
## freed, Main has to read the same character/prop scenes from the pack again —
## measured as one ~320 ms frame inside start_match (118 + 93 + 86 ms for the
## three classes) right at the start of the match.
##
## The list is filled at the very END of the flow (see `_retain_battle_cache`),
## never while the flow still draws: a retained scene whose textures were drawn
## keeps them in video memory, which raised the mobile two-pass peak above the
## arena pass (338.7 MB vs 320.2). Audio is the exception — it is retained at
## the start because a stream costs no video memory.
var retained_resources: Array[Resource] = []

var _running := false
var _done := false
var _progress := 0.0
var _started_ms := 0
var _stage := ""
var _stage_started_ms := 0
var _viewport: SubViewport
var _camera: Camera3D
var _canvas: SubViewport
var _arena: Node3D
var _main: Node3D
var _frames := 0
var _peak_static_mb := 0.0
var _peak_video_mb := 0.0
var _video_mem_available := false
var _two_pass := false
var _pass := 1
var _pass_peak_mb := 0.0
## Frame-time sampling. It answers the two questions the pacing has to solve:
## is there a spike in the first seconds, and what is the typical frame during
## the warmup? A delta over one second is a window drag or a debugger stop, not
## warmup load, so it is skipped.
var _frame_ms: Array[float] = []
var _first2s_max_ms := 0.0
var _first2s_settled_max_ms := 0.0
var _frame_ema_ms := 16.7
## 0 = auto by platform. Probes set it to shrink or stretch the run.
var target_seconds := 0.0
## 0 = PACING_HARD_BUDGET_SECONDS. Probes shrink it to exercise the truncation
## path without waiting half a minute.
var budget_seconds := 0.0
var _paced := true
var _pause_ms := 0.0
var _last_step_ms := 0
var _deadline_hit := false
var _truncated := false


func start() -> void:
	if _running or _done:
		return
	retain_early = OS.get_cmdline_user_args().has("--warmup-retain-early")
	if two_pass_policy == TWO_PASS_POLICY_AUTO:
		for arg in OS.get_cmdline_user_args():
			if arg == "--warmup-two-pass":
				two_pass_policy = TWO_PASS_POLICY_ON
			elif arg == "--warmup-single-pass":
				two_pass_policy = TWO_PASS_POLICY_OFF
	report["two_pass_policy"] = two_pass_policy
	_running = true
	_started_ms = Time.get_ticks_msec()
	_stage_started_ms = _started_ms
	_last_step_ms = _started_ms
	_stage = STAGE_LOAD
	_emit(0.0)
	_run()


func is_running() -> bool:
	return _running and not _done


func is_finished() -> bool:
	return _done


func _run() -> void:
	# Quiet start: the search screen keeps animating, the machine is idle and
	# the first heavy step does not land in the first second of the screen.
	await _wait_seconds(PACING_START_DELAY_SECONDS)
	if not _alive():
		return
	_emit(1.0)

	var load_started := Time.get_ticks_msec()
	var packed := await _load_threaded(MAIN_SCENE_PATH)
	report["main_scene_loaded"] = packed != null
	report["main_load_ms"] = Time.get_ticks_msec() - load_started
	if not _alive():
		return
	if packed == null:
		_fail("Main.tscn не загрузился")
		return
	_emit(8.0)
	await _pace()

	# Battle audio, while the search screen is still up: game.gd loads the
	# theme, the ambience and every SFX synchronously in Main._ready, inside the
	# scene-switch frame. Preloading here makes those calls cache hits. Audio
	# streams carry no video memory, so keeping them costs nothing for the
	# two-pass VRAM budget — this is the only thing retained during the flow.
	_set_stage(STAGE_AUDIO)
	_emit(8.5)
	await _warm_audio()
	if not _alive():
		return
	_emit(10.0)
	await _pace()
	if _over_budget():
		await _finish_truncated()
		return

	_setup_viewport()
	await _render_frames(1)
	if not _alive():
		return
	_emit(11.0, STAGE_INSTANCE)
	await _pace()

	_main = packed.instantiate() as Node3D
	if _main == null:
		_fail("Main.tscn не инстанцировался")
		return
	# Strip game.gd before it enters the tree: no match, no HUD, no audio, no
	# network, no tutorial controller. Only the baked arena is left.
	_main.set_script(null)
	report["main_script_stripped"] = _main.get_script() == null
	_viewport.add_child(_main)
	_arena = _main.get_node_or_null("Arena") as Node3D
	if _arena != null:
		report["arena_children"] = _arena.get_child_count()
	await _render_frames(2)
	if not _alive():
		return
	_emit(16.0)
	await _pace()

	# The same two calls game.gd makes on the baked arena: perimeter ridge and
	# runtime props/materials (grass, paths, crystals, ruin columns...).
	if _arena != null:
		ArenaKit.ensure_perimeter_ridge(_arena)
		await _render_frames(1)
		if not _alive():
			return
		_emit(20.0, STAGE_ARENA)
		await _pace()
		ArenaKit.ensure_arena_features(_arena)
		await _render_frames(2)
		report["arena_children"] = _arena.get_child_count()
	if not _alive():
		return
	_emit(26.0)
	await _pace()
	if _over_budget():
		await _finish_truncated()
		return
	await _render_arena_views()
	if not _alive():
		return
	_emit(34.0)
	await _pace()
	if _over_budget():
		await _finish_truncated()
		return
	report["video_after_arena_mb"] = _video_mb()
	report["mobile"] = _is_mobile()
	report["quality"] = _quality()
	report["video_mem_available"] = _video_mem_available
	_decide_two_pass(float(report["video_after_arena_mb"]))
	if _two_pass:
		await _switch_to_second_pass()
		if not _alive():
			return
		_emit(36.0, STAGE_SWITCH)
		await _pace()

	await _warm_characters()
	if not _alive():
		return
	_emit(54.0)
	await _pace()
	if _over_budget():
		await _finish_truncated()
		return

	await _warm_props()
	if not _alive():
		return
	_emit(64.0)
	await _pace()
	if _over_budget():
		await _finish_truncated()
		return

	await _warm_vfx()
	if not _alive():
		return
	_emit(88.0)
	report["video_after_vfx_mb"] = _video_mb()
	await _pace()
	if _over_budget():
		await _finish_truncated()
		return

	_set_stage(STAGE_SHADERS)
	_emit(88.0)
	await _warm_shaders()
	if not _alive():
		return
	_emit(94.0)
	await _pace()
	if _over_budget():
		await _finish_truncated()
		return

	_set_stage(STAGE_FINAL)
	_emit(94.0)
	await _render_final_views()
	if not _alive():
		return
	# Free the arena and the second-pass viewport BEFORE refilling the loader
	# cache: the cache tail allocates the fighter/prop textures' video memory
	# (measured +42 MB on Forward+), and it must not do that while the arena is
	# still resident. That is the "second pass first, keeper after" order — with
	# it the two-pass peak stays at the pass-2 drawing peak (295 MB) instead of
	# 337 MB.
	_cleanup()
	await _render_frames(2)
	if not is_inside_tree():
		return
	_set_stage(STAGE_CACHE)
	await _retain_battle_cache()
	if not _alive():
		return
	_emit(99.0)

	report["elapsed"] = _elapsed()
	_record_metrics()
	_emit(100.0, STAGE_DONE)
	# Give the freed viewport and arena two more frames to leave the tree before
	# the loading screen switches scenes.
	await _render_frames(2)
	if not is_inside_tree():
		return
	_done = true
	_running = false
	_finalize_pass()
	report["stage_times"] = _stage_times()
	_track_stats()
	finished.emit()


func _setup_viewport(pass_two := false) -> void:
	_viewport = SubViewport.new()
	if pass_two:
		_viewport.name = "WarmupFlowViewport2"
	else:
		_viewport.name = "WarmupFlowViewport"
	# Small by design: shader/pipeline compilation is resolution independent,
	# and the arena fill rate plus the shadow pass stay cheap.
	if pass_two:
		var width := VIEWPORT_WIDTH_MOBILE if _is_mobile() else VIEWPORT_WIDTH_DESKTOP
		_viewport.size = Vector2i(width, int(round(float(width) * 9.0 / 16.0)))
	else:
		_viewport.size = ARENA_VIEWPORT_SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	# The shadow atlas keeps the project default on purpose: the two-pass VRAM
	# decision below is measured on this viewport, so it must not under-report
	# what the real arena costs.
	# Only the frames the flow asks for are drawn. UPDATE_ALWAYS would keep
	# the hidden arena at full GPU load through every pause between steps,
	# which is exactly the first-second spike the pacing is here to remove.
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.name = "WarmupFlowCamera"
	_camera.fov = 55.0
	_camera.near = 0.1
	_camera.far = 300.0
	_camera.position = Vector3(0.0, 18.0, 17.0)
	_viewport.add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.5, 0.0), Vector3.UP)
	_camera.current = true
	if pass_two:
		# The arena instance (and its lighting) is gone by now; fighters and
		# PBR shaders still need one lit draw or the lit variant stays cold.
		var light := DirectionalLight3D.new()
		light.name = "WarmupFlowKeyLight"
		light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
		light.light_energy = 1.1
		_viewport.add_child(light)
		var ground := MeshInstance3D.new()
		ground.name = "WarmupFlowGround"
		var plane := PlaneMesh.new()
		plane.size = Vector2(30.0, 30.0)
		ground.mesh = plane
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.32, 0.3, 0.27)
		material.roughness = 0.95
		ground.material_override = material
		ground.position = Vector3(0.0, -0.05, 0.0)
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_viewport.add_child(ground)


func _warm_characters() -> void:
	_set_stage(STAGE_HEROES)
	var total := CHARACTER_SCENES.size()
	for index in total:
		if not _alive():
			return
		# Never start an item that could cross the hard budget by a whole
		# stage: one model is the largest unit left here.
		if _over_budget():
			return
		var path: String = CHARACTER_SCENES[index]
		var packed := await _load_threaded(path)
		if retain_early and packed is Resource:
			_retain(packed)
		if packed is PackedScene:
			var model := (packed as PackedScene).instantiate() as Node3D
			if model != null:
				model.position = Vector3(-4.6 + 2.3 * float(index), 0.05, 1.4)
				_viewport.add_child(model)
				_play_first_animation(model)
				# One drawn frame compiles the materials, the second makes sure
				# the upload finished before the model is freed.
				await _render_frames(2)
				model.queue_free()
				await _render_frames(1)
				report["heroes_warmed"] = int(report["heroes_warmed"]) + 1
		_emit(34.0 + 20.0 * float(index + 1) / float(total))
		await _pace()
	await _render_frames(1)


func _warm_props() -> void:
	_set_stage(STAGE_WEAPONS)
	var total := PROP_SCENES.size()
	for index in total:
		if not _alive():
			return
		if _over_budget():
			return
		var packed := await _load_threaded(PROP_SCENES[index])
		if retain_early and packed is Resource:
			_retain(packed)
		if packed is PackedScene:
			var prop := (packed as PackedScene).instantiate() as Node3D
			if prop != null:
				prop.position = Vector3(-5.0 + 1.1 * float(index), 1.0, -1.6)
				_viewport.add_child(prop)
				# A prop is a single mesh: one drawn frame is enough to compile
				# its material, the second is the queue_free frame.
				await _render_frames(1)
				prop.queue_free()
				await _render_frames(1)
				report["props_warmed"] = int(report["props_warmed"]) + 1
		_emit(54.0 + 10.0 * float(index + 1) / float(total))
		await _pace()


func _warm_vfx() -> void:
	_set_stage(STAGE_VFX)
	_emit(64.0)
	await _pace()
	var preloader: Variant = VFX_PRELOADER.new()
	preloader.name = "WarmupVfxPreloader"
	preloader.step_progress.connect(_on_vfx_step)
	add_child(preloader)
	# The preloader drives its own small viewport; the only thing worth doing
	# here is to stop waiting for it when the hard budget is gone.
	var deadline := Time.get_ticks_msec() + int(
		maxf(1.0, _budget_seconds() - _elapsed()) * 1000.0
	)
	while is_instance_valid(preloader) and not bool(preloader.completed):
		if not _alive():
			return
		if Time.get_ticks_msec() > deadline:
			push_warning("[WarmupFlow] vfx preloader timeout")
			break
		await get_tree().process_frame
	if is_instance_valid(preloader):
		report["vfx_scenes_warmed"] = preloader.scenes_warmed
		report["sounds_warmed"] = preloader.sounds_warmed
		preloader.queue_free()
	await _render_frames(2)
	await _pace()
	# Hero hit-flash copies materials at runtime; render an emissive copy once.
	await _warm_emissive_flash()
	await _pace()
	# Mobile fireflies: the first GPUParticles3D draw compiles a separate
	# particle shader, which used to hitch right after the arena appears.
	await _warm_gpu_particles()
	await _pace()
	# Base spawn domes use the rim-lit transparent StandardMaterial variant.
	await _warm_rim_material()


func _on_vfx_step(done: int, total: int) -> void:
	var ratio := float(done) / float(maxi(1, total))
	_emit(64.0 + 24.0 * ratio, STAGE_VFX)


func _warm_emissive_flash() -> void:
	if not _alive():
		return
	var probe := MeshInstance3D.new()
	probe.mesh = SphereMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.95, 0.9)
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 1.6
	probe.material_override = material
	probe.position = Vector3(0.0, 1.2, 1.0)
	_viewport.add_child(probe)
	await _render_frames(2)
	probe.queue_free()
	await _render_frames(1)


func _warm_rim_material() -> void:
	if not _alive():
		return
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 2.0
	sphere.height = 4.0
	dome.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.72, 1.0, 0.012)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.9
	material.rim_enabled = true
	material.rim = 0.25
	material.rim_tint = 0.35
	dome.material_override = material
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.position = Vector3(0.0, 2.0, 1.0)
	_viewport.add_child(dome)
	await _render_frames(2)
	dome.queue_free()
	await _render_frames(1)


func _warm_gpu_particles() -> void:
	if not _alive():
		return
	var particles := GPUParticles3D.new()
	particles.amount = 12
	particles.lifetime = 1.0
	particles.preprocess = 0.2
	particles.position = Vector3(0.0, 1.8, 1.2)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 1.0
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.25
	particles.process_material = process
	var dot := SphereMesh.new()
	dot.radius = 0.05
	dot.height = 0.1
	dot.radial_segments = 6
	dot.rings = 3
	var dot_material := StandardMaterial3D.new()
	dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_material.albedo_color = Color(1.0, 0.85, 0.45)
	dot_material.emission_enabled = true
	dot_material.emission = Color(1.0, 0.85, 0.45)
	dot_material.emission_energy_multiplier = 2.0
	dot.material = dot_material
	particles.draw_pass_1 = dot
	particles.emitting = true
	_viewport.add_child(particles)
	await _render_frames(3)
	particles.queue_free()
	await _render_frames(1)


func _warm_shaders() -> void:
	if _camera != null:
		_camera.position = Vector3(0.0, 2.4, 7.0)
		_camera.look_at(Vector3(0.0, 1.4, 1.0), Vector3.UP)
	var total := SPATIAL_SHADERS.size() + CANVAS_SHADERS.size()
	var done := 0
	for path in SPATIAL_SHADERS:
		if not _alive():
			return
		if _over_budget():
			return
		var shader := load(path) as Shader
		if shader != null:
			var quad := MeshInstance3D.new()
			var mesh := QuadMesh.new()
			mesh.size = Vector2(1.6, 1.6)
			quad.mesh = mesh
			var material := ShaderMaterial.new()
			material.shader = shader
			quad.material_override = material
			quad.position = Vector3(-4.0 + 2.0 * float(done), 1.5, 1.0)
			quad.rotation_degrees = Vector3(0.0, 0.0, 0.0)
			_viewport.add_child(quad)
			await _render_frames(2)
			quad.queue_free()
			report["shaders_warmed"] = int(report["shaders_warmed"]) + 1
		done += 1
		_emit(88.0 + 5.0 * float(done) / float(total))
		await _pace()
	await _warm_canvas_shaders()
	await _render_frames(1)


func _warm_canvas_shaders() -> void:
	# HUD shaders are canvas_item, so they need a 2D draw pass, not a 3D mesh.
	# They compile in the same hidden viewport and are freed right away.
	var canvas := SubViewport.new()
	_canvas = canvas
	canvas.name = "WarmupFlowCanvas"
	canvas.size = Vector2i(CANVAS_VIEWPORT_SIZE, CANVAS_VIEWPORT_SIZE)
	canvas.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(canvas)
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(layer)
	for path in CANVAS_SHADERS:
		if not _alive():
			return
		if _over_budget():
			return
		var shader := load(path) as Shader
		if shader == null:
			continue
		var rect := ColorRect.new()
		rect.color = Color(1.0, 0.7, 0.3, 0.9)
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var material := ShaderMaterial.new()
		material.shader = shader
		rect.material = material
		layer.add_child(rect)
		await _render_frames(2)
		rect.queue_free()
		report["shaders_warmed"] = int(report["shaders_warmed"]) + 1
		await _pace()
	await _render_frames(1)
	canvas.queue_free()
	_canvas = null


func _render_arena_views() -> void:
	if _camera == null:
		return
	var views := [
		Vector3(0.0, 17.0, 16.0),
		Vector3(9.0, 12.0, 9.0),
		Vector3(0.0, 9.0, 5.0),
	]
	for position in views:
		if not _alive():
			return
		if _over_budget():
			return
		_camera.position = position
		_camera.look_at(Vector3(0.0, 0.6, 0.0), Vector3.UP)
		# A new camera angle is the most expensive frame of the arena pass;
		# it gets its own render and a break before the next one.
		await _render_frames(2)
		await _pace()


func _render_final_views() -> void:
	if _camera == null:
		return
	var views := [
		Vector3(0.0, 16.0, 15.0),
		Vector3(6.0, 8.0, 8.0),
		Vector3(0.0, 5.0, 4.0),
	]
	for position in views:
		if not _alive():
			return
		if _over_budget():
			return
		_camera.position = position
		_camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)
		await _render_frames(1)
		await _pace()
	await RenderingServer.frame_post_draw


func _play_first_animation(model: Node3D) -> void:
	var animations := model.find_children("*", "AnimationPlayer", true, false)
	if animations.is_empty():
		return
	var player := animations[0] as AnimationPlayer
	if player == null:
		return
	var names := player.get_animation_list()
	var pick := ""
	for wanted in ["idle", "Idle", "walk", "Walk", "run", "Run"]:
		if names.has(wanted):
			pick = wanted
			break
	if pick.is_empty() and not names.is_empty():
		pick = String(names[0])
	if pick.is_empty():
		return
	player.play(pick)
	player.advance(0.2)


func _render_frames(count: int) -> void:
	for _index in count:
		if not is_inside_tree():
			return
		# Draw only the frames that were asked for. UPDATE_ALWAYS would render
		# the hidden arena on every frame of every pause, keeping the machine
		# busy the whole time the loading screen shows.
		if _viewport != null and is_instance_valid(_viewport):
			_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		if _canvas != null and is_instance_valid(_canvas):
			_canvas.render_target_update_mode = SubViewport.UPDATE_ONCE
		await get_tree().process_frame
		_frames += 1
		report["frames_rendered"] = _frames
		_sample_memory()


func _load_threaded(path: String) -> Resource:
	var error := ResourceLoader.load_threaded_request(path)
	if error != OK:
		return load(path)
	while true:
		if not is_inside_tree():
			return null
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
			continue
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			return ResourceLoader.load_threaded_get(path)
		push_warning("[WarmupFlow] не удалось загрузить %s (%s)" % [path, error_string(error)])
		return null
	return null


## Keeps a loaded resource referenced for the match (see `retained_resources`).
func _retain(resource: Resource) -> void:
	if resource == null or retained_resources.has(resource):
		return
	retained_resources.append(resource)
	report["retained_resources"] = retained_resources.size()


## Battle music, arena ambience and every game SFX, loaded while the search
## screen is still up. game.gd reads them with a synchronous `load()` inside
## Main._ready; after this they are loader cache hits there, and the first
## `play()` does not wait for a cold stream.
func _warm_audio() -> void:
	var paths: Array = BATTLE_AUDIO.stream_paths()
	if paths.is_empty():
		return
	for path in paths:
		var request_error := ResourceLoader.load_threaded_request(String(path))
		if request_error != OK and request_error != ERR_BUSY:
			continue
	var deadline := Time.get_ticks_msec() + 5000
	while true:
		if not _alive():
			return
		var pending := 0
		for path in paths:
			if ResourceLoader.load_threaded_get_status(String(path)) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				pending += 1
		if pending == 0:
			break
		if Time.get_ticks_msec() > deadline:
			push_warning("[WarmupFlow] прогрев звука не успел за 5 с")
			break
		await get_tree().process_frame
	var loaded := 0
	for path in paths:
		if ResourceLoader.load_threaded_get_status(String(path)) != ResourceLoader.THREAD_LOAD_LOADED:
			continue
		var stream := ResourceLoader.load_threaded_get(String(path)) as Resource
		if stream == null:
			continue
		_retain(stream)
		loaded += 1
	report["audio_preloaded"] = loaded


## Refills the loader cache for the match after the last draw of the flow.
##
## Order matters: everything here is *loaded* but never drawn again, so it
## allocates RAM only. Retaining the fighter/prop scenes before the second pass
## would keep their textures resident in VRAM once pass 2 draws them — measured
## as pass2 338.7 MB on top of pass1 320.2 MB on mobile, which broke the
## two-pass budget. Audio is retained earlier (START of the flow) because a
## stream never touches video memory.
func _retain_battle_cache() -> void:
	# Two-pass exists to keep the arena and the fighter set out of video memory
	# at the same time, so the second pass must stay under the arena peak. The
	# cache tail loads the fighter/prop scenes and their textures become video
	# memory (measured +42 MB on Forward+), which pushed pass2 to 337 MB against
	# a 320 MB pass1. VRAM comes first on two-pass: only the audio is kept
	# (retained at the start of the flow, a stream costs no video memory) and
	# the match loads the scenes itself, exactly as before this change.
	if _two_pass:
		report["cache_tail_skipped"] = "two_pass"
		report["retained_resources"] = retained_resources.size()
		report["main_cached"] = ResourceLoader.has_cached(MAIN_SCENE_PATH)
		return
	# A/B hook: measure the flow without the cache tail.
	if OS.get_cmdline_user_args().has("--warmup-no-cache"):
		report["main_cached"] = ResourceLoader.has_cached(MAIN_SCENE_PATH)
		return
	var started := Time.get_ticks_msec()
	var paths: Array[String] = []
	for path in [MAIN_SCENE_PATH]:
		paths.append(String(path))
	for path in CHARACTER_SCENES:
		paths.append(String(path))
	for path in PROP_SCENES:
		paths.append(String(path))
	for path in _game_const_paths("FIRST_CLASH_WARM_VFX"):
		paths.append(path)
	for path in paths:
		if not _alive():
			return
		if _over_budget():
			return
		var resource := await _load_threaded(path)
		if resource != null:
			_retain(resource)
	report["main_cached"] = ResourceLoader.has_cached(MAIN_SCENE_PATH)
	report["retain_ms"] = Time.get_ticks_msec() - started


## A constant array of resource paths from game.gd (defensive: a game.gd that
## fails to parse or a renamed constant just means "nothing extra to cache").
func _game_const_paths(constant_name: String) -> Array[String]:
	var paths: Array[String] = []
	var script := load(GAME_SCRIPT_PATH) as GDScript
	if script == null:
		return paths
	var constants: Dictionary = script.get_script_constant_map()
	var value: Variant = constants.get(constant_name, [])
	if not value is Array:
		return paths
	for entry in (value as Array):
		paths.append(String(entry))
	return paths


func _alive() -> bool:
	if is_inside_tree():
		return true
	_running = false
	_done = true
	return false


func _cleanup() -> void:
	if _viewport != null and is_instance_valid(_viewport):
		if _main != null:
			report["main_freed"] = true
		_viewport.queue_free()
	if _canvas != null and is_instance_valid(_canvas):
		_canvas.queue_free()
	_viewport = null
	_canvas = null
	_camera = null
	_main = null
	_arena = null


func _decide_two_pass(arena_video_mb: float) -> void:
	var policy := String(two_pass_policy)
	var mobile := _is_mobile()
	var reason := ""
	_two_pass = false
	if policy == TWO_PASS_POLICY_ON:
		_two_pass = true
		reason = "forced"
	elif policy != TWO_PASS_POLICY_AUTO and policy != "":
		reason = "disabled"
	elif not mobile:
		reason = "desktop"
	elif not _video_mem_available:
		reason = "video_mem_unavailable"
	elif arena_video_mb >= TWO_PASS_TRIGGER_MB:
		_two_pass = true
		reason = "arena_peak_%.0f_mb>=%.0f" % [arena_video_mb, TWO_PASS_TRIGGER_MB]
	elif arena_video_mb >= TWO_PASS_MOBILE_BUDGET_MB:
		_two_pass = true
		reason = "arena_peak_%.0f_mb>=%.0f" % [arena_video_mb, TWO_PASS_MOBILE_BUDGET_MB]
	else:
		reason = "arena_peak_%.0f_mb" % arena_video_mb
	report["two_pass"] = _two_pass
	report["two_pass_policy"] = policy
	report["two_pass_reason"] = reason
	report["mobile"] = mobile
	if _two_pass:
		print("[WarmupFlow] two-pass: %s (arena %.1f MB)" % [reason, arena_video_mb])


## Frees the arena instance and its viewport so the second pass never shares
## VRAM (arena textures, generated meshes, shadow atlas, world buffers) with
## the fighters/weapons/VFX set. The Main.tscn resource stays in the loader
## cache, so the real scene switch still gets a warm cache.
func _switch_to_second_pass() -> void:
	_set_stage(STAGE_SWITCH)
	var started := Time.get_ticks_msec()
	_finalize_pass()
	# Two-pass exists to keep arena textures and fighter textures out of VRAM
	# at the same time. The shared arena materials hold the big floor/rock/plaza
	# textures, so the references drop here; the match builds fresh ones.
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
		report["main_freed"] = true
	_main = null
	_arena = null
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.queue_free()
	_viewport = null
	_camera = null
	await _render_frames(2)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	report["video_after_arena_free_mb"] = _video_mb()
	_pass = 2
	_pass_peak_mb = 0.0
	_setup_viewport(true)
	await _render_frames(2)
	report["two_pass_switch_ms"] = Time.get_ticks_msec() - started
	report["two_pass_switch_s"] = snappedf(float(report["two_pass_switch_ms"]) / 1000.0, 0.01)


func _finalize_pass() -> void:
	if _pass <= 1:
		report["pass1_video_mb"] = snappedf(_pass_peak_mb, 0.1)
	else:
		report["pass2_video_mb"] = snappedf(_pass_peak_mb, 0.1)


func _is_mobile() -> bool:
	var profile := get_node_or_null("/root/DeviceProfile")
	if profile != null and bool(profile.get("mobile_ui")):
		return true
	return OS.has_feature("mobile")


func _quality() -> String:
	var profile := get_node_or_null("/root/DeviceProfile")
	if profile != null and profile.has_method("effective_quality"):
		return String(profile.call("effective_quality"))
	return "unknown"


func _video_mb() -> float:
	return snappedf(
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0, 0.1
	)


## Samples static and video memory. Video memory is sampled on every rendered
## frame, otherwise a short-lived spike between progress steps goes unnoticed.
func _sample_memory() -> void:
	_peak_static_mb = maxf(_peak_static_mb, float(OS.get_static_memory_usage()) / 1048576.0)
	var video := float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0
	if video > 0.0:
		_video_mem_available = true
	_peak_video_mb = maxf(_peak_video_mb, video)
	_pass_peak_mb = maxf(_pass_peak_mb, video)
	report["peak_static_mb"] = snappedf(_peak_static_mb, 0.1)
	report["peak_video_mb"] = snappedf(_peak_video_mb, 0.1)
	report["video_mem_available"] = _video_mem_available
	if _pass <= 1:
		report["pass1_video_mb"] = snappedf(_pass_peak_mb, 0.1)
	else:
		report["pass2_video_mb"] = snappedf(_pass_peak_mb, 0.1)


## Fire-and-forget analytics. Warmup must never fail because Stats (or its
## network client) is missing, so every access is guarded.
func _track_stats() -> void:
	report["stats_tracked"] = false
	var stats := get_node_or_null("/root/Stats")
	if stats == null or not stats.has_method("track"):
		return
	var payload := {
		"elapsed": snappedf(float(report["elapsed"]), 0.01),
		"stage_times": report["stage_times"],
		"peak_static_mb": report["peak_static_mb"],
		"peak_video_mb": report["peak_video_mb"],
		"pass1_video_mb": report["pass1_video_mb"],
		"pass2_video_mb": report["pass2_video_mb"],
		"video_after_arena_mb": report["video_after_arena_mb"],
		"heroes": int(report["heroes_warmed"]),
		"props": int(report["props_warmed"]),
		"vfx": int(report["vfx_scenes_warmed"]),
		"shaders": int(report["shaders_warmed"]),
		"audio_preloaded": int(report.get("audio_preloaded", 0)),
		"retained": int(report.get("retained_resources", 0)),
		"retain_ms": int(report.get("retain_ms", 0)),
		"frames": int(report["frames_rendered"]),
		"mobile": bool(report["mobile"]),
		"quality": String(report["quality"]),
		"two_pass": _two_pass,
		"two_pass_reason": String(report["two_pass_reason"]),
		"failed": bool(report["failed"]),
		"paced": _paced,
		"frame_ms_avg": report["frame_ms_avg"],
		"frame_ms_p95": report["frame_ms_p95"],
		"frame_ms_max": report["frame_ms_max"],
		"first2s_max_frame_ms": report["first2s_max_frame_ms"],
		"first2s_settled_max_frame_ms": report["first2s_settled_max_frame_ms"],
		"pauses_s": report["pauses_s"],
		"truncated": _truncated,
	}
	stats.call("track", "warmup_done", payload)
	report["stats_tracked"] = true


func _fail(message: String) -> void:
	report["failed"] = true
	report["error"] = message
	report["elapsed"] = _elapsed()
	report["stage_times"] = _stage_times()
	_finalize_pass()
	_record_metrics()
	push_error("[WarmupFlow] " + message)
	_track_stats()
	_cleanup()
	_done = true
	_running = false
	progress_changed.emit(100.0, _elapsed(), message)
	finished.emit()


func _set_stage(stage_name: String) -> void:
	if stage_name == _stage:
		return
	if not _stage.is_empty():
		var spent := float(Time.get_ticks_msec() - _stage_started_ms) / 1000.0
		report["stage_times"][_stage] = spent
	_stage = stage_name
	_stage_started_ms = Time.get_ticks_msec()


func _stage_times() -> Dictionary:
	var times: Dictionary = (report["stage_times"] as Dictionary).duplicate()
	if not _stage.is_empty():
		times[_stage] = float(Time.get_ticks_msec() - _stage_started_ms) / 1000.0
	return times


func _emit(percent: float, stage_name := "") -> void:
	if not stage_name.is_empty():
		_set_stage(stage_name)
	_sample_memory()
	_progress = clampf(percent, 0.0, 100.0)
	progress_changed.emit(_progress, _elapsed(), _stage)


func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _started_ms) / 1000.0


## Samples every frame the warmup is running, including the pauses: those are
## real frames of the loading screen and count towards the load profile.
func _process(delta: float) -> void:
	if not _running or _done:
		return
	var frame_ms := delta * 1000.0
	if frame_ms <= 0.0 or frame_ms > 1000.0:
		return
	_frame_ema_ms = lerpf(_frame_ema_ms, frame_ms, 0.12)
	if _frame_ms.size() < 8192:
		_frame_ms.append(frame_ms)
	if _elapsed() <= 2.0:
		if frame_ms > _first2s_max_ms:
			_first2s_max_ms = frame_ms
			report["first2s_max_at_s"] = snappedf(_elapsed(), 0.01)
		# The loading scene's own first draw (background and font upload) sits
		# in the first frames and predates the warmup; the warmup profile is
		# measured after it has settled.
		if _elapsed() >= PACING_START_SETTLED_SECONDS:
			_first2s_settled_max_ms = maxf(_first2s_settled_max_ms, frame_ms)


## Aggregates the frame samples into the report. `work_s` is the wall clock
## minus the deliberate pauses, so work/pauses shows how even the load is.
func _record_metrics() -> void:
	var samples := _frame_ms.duplicate()
	samples.sort()
	var count := samples.size()
	var total := 0.0
	for value in samples:
		total += value
	report["frames_sampled"] = count
	report["frame_ms_avg"] = snappedf(total / maxf(1.0, float(count)), 0.1)
	report["frame_ms_max"] = snappedf(samples[count - 1] if count > 0 else 0.0, 0.1)
	report["frame_ms_p95"] = snappedf(_percentile(samples, 0.95), 0.1)
	report["first2s_max_frame_ms"] = snappedf(_first2s_max_ms, 0.1)
	report["first2s_settled_max_frame_ms"] = snappedf(_first2s_settled_max_ms, 0.1)
	report["pauses_s"] = snappedf(_pause_ms / 1000.0, 0.01)
	report["work_s"] = snappedf(maxf(0.0, _elapsed() - _pause_ms / 1000.0), 0.01)
	report["pacing_target_s"] = snappedf(_target_seconds(), 0.1)
	report["paced"] = _paced
	report["deadline_hit"] = _deadline_hit
	report["truncated"] = _truncated
	print(
		(
			"[WarmupFlow] pacing total=%.2fs work=%.2fs pauses=%.2fs frames=%d "
			+ "avg=%.1fms p95=%.1fms max=%.1fms first2s_max=%.1fms(settled %.1fms) target=%.1fs truncated=%s"
		)
		% [
			_elapsed(),
			float(report["work_s"]),
			float(report["pauses_s"]),
			count,
			float(report["frame_ms_avg"]),
			float(report["frame_ms_p95"]),
			float(report["frame_ms_max"]),
			float(report["first2s_max_frame_ms"]),
			float(report["first2s_settled_max_frame_ms"]),
			float(report["pacing_target_s"]),
			str(_truncated),
		]
	)


func _percentile(sorted_values: Array, ratio: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := int(ceil(ratio * float(sorted_values.size()))) - 1
	return float(sorted_values[clampi(index, 0, sorted_values.size() - 1)])


func _target_seconds() -> float:
	if target_seconds > 0.0:
		return target_seconds
	return PACING_TARGET_SECONDS_MOBILE if _is_mobile() else PACING_TARGET_SECONDS


func _budget_seconds() -> float:
	if budget_seconds > 0.0:
		return budget_seconds
	return PACING_HARD_BUDGET_SECONDS


func _wait_seconds(seconds: float) -> void:
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout


## Spreads the warmup over the target time instead of running it flat out.
##
## Two rules, whichever asks for the longer break:
##  - duty cycle: the pause is proportional to what the previous step cost, so a
##    heavy step (arena view, shader compile, VFX scene) gets a longer break and
##    a cheap one does not turn the run into a sprint;
##  - schedule: the reported percent is also a time mark (8% = 8% of the
##    target), so the flow cannot finish far ahead of the target and leave the
##    player with a 10 s warmup that pegs the machine.
## A heavy average frame time adds a little extra back-off, and everything is
## capped by the target and the hard budget (see `_over_budget`). When the work
## itself is slower than the schedule the pauses simply disappear, so a weak
## device is never pushed past the budget by the pacing.
func _pace(weight := 1.0) -> void:
	if not _alive():
		return
	var now := Time.get_ticks_msec()
	var worked_ms := float(now - _last_step_ms)
	_last_step_ms = now
	if not _paced or worked_ms <= 1.0:
		return
	var target := _target_seconds()
	var remaining := target - _elapsed()
	if remaining <= 0.0:
		return
	var wanted := worked_ms / 1000.0 * (1.0 - PACING_DUTY) / PACING_DUTY
	wanted *= clampf(_frame_ema_ms / 16.7, 0.85, 1.5)
	wanted *= maxf(0.1, weight)
	# The percent shown in the UI doubles as the time mark of the run.
	var schedule := target * clampf(_progress / 100.0, 0.0, 1.0)
	wanted = maxf(wanted, schedule - _elapsed())
	wanted = clampf(minf(wanted, remaining), 0.0, PACING_MAX_PAUSE_SECONDS)
	if wanted < PACING_MIN_PAUSE_SECONDS:
		return
	_pause_ms += wanted * 1000.0
	await get_tree().create_timer(wanted).timeout
	# The pause itself must not count as work for the next step.
	_last_step_ms = Time.get_ticks_msec()


## True once the hard budget is gone. The caller then finishes the warmup with
## `_finish_truncated` instead of running a step that could overrun the 30 s
## search window.
func _over_budget() -> bool:
	if _elapsed() < _budget_seconds():
		return false
	_deadline_hit = true
	report["deadline_hit"] = true
	return true


## Ends the warmup early on a slow device. It is reported as a failed warmup,
## so the loading screen opens the match without `battle_prewarmed` and game.gd
## falls back to its own first-frame warmup. Finishing early with a warning is
## always better than leaving the player on a frozen loading screen.
func _finish_truncated() -> void:
	if _truncated or _done:
		return
	_truncated = true
	report["truncated"] = true
	report["failed"] = true
	report["error"] = "прогрев прерван по бюджету %.0f с" % _budget_seconds()
	report["elapsed"] = _elapsed()
	report["stage_times"] = _stage_times()
	_finalize_pass()
	_record_metrics()
	push_warning("[WarmupFlow] " + String(report["error"]))
	_track_stats()
	_set_stage(STAGE_DONE)
	_progress = 100.0
	progress_changed.emit(100.0, _elapsed(), _stage)
	_cleanup()
	await _render_frames(2)
	if not is_inside_tree():
		return
	_done = true
	_running = false
	finished.emit()


