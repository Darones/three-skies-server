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
## Safety: Main.tscn is instantiated with its game.gd script removed, so no
## match starts, no HUD is created, no network connection is opened and no
## music plays. The instance is freed at the end; only the resource cache
## (meshes, textures, materials) stays warm for the real scene load.
##
## API:
##   var flow := WarmupFlow.new()
##   add_child(flow)
##   flow.progress_changed.connect(_on_progress)  # percent, elapsed, stage
##   flow.finished.connect(_on_ready)
##   flow.start()

signal progress_changed(percent: float, elapsed: float, stage: String)
signal finished

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const VFX_PRELOADER := preload("res://scripts/vfx_preloader.gd")

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
const STAGE_INSTANCE := "Инстанс арены"
const STAGE_ARENA := "Материалы арены"
const STAGE_HEROES := "Бойцы и скины"
const STAGE_WEAPONS := "Оружие и предметы"
const STAGE_VFX := "Эффекты и шейдеры"
const STAGE_SHADERS := "Шейдеры"
const STAGE_FINAL := "Финальный рендер"
const STAGE_DONE := "Готово"

var report := {
	"main_scene_loaded": false,
	"main_script_stripped": false,
	"arena_children": 0,
	"heroes_warmed": 0,
	"props_warmed": 0,
	"vfx_scenes_warmed": 0,
	"sounds_warmed": 0,
	"shaders_warmed": 0,
	"frames_rendered": 0,
	"main_freed": false,
	"failed": false,
	"error": "",
	"stage_times": {},
	"elapsed": 0.0,
	"peak_static_mb": 0.0,
	"peak_video_mb": 0.0,
}

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


func start() -> void:
	if _running or _done:
		return
	_running = true
	_started_ms = Time.get_ticks_msec()
	_stage_started_ms = _started_ms
	_stage = STAGE_LOAD
	_emit(0.0)
	_run()


func is_running() -> bool:
	return _running and not _done


func is_finished() -> bool:
	return _done


func _run() -> void:
	var packed := await _load_threaded(MAIN_SCENE_PATH)
	report["main_scene_loaded"] = packed != null
	if not _alive():
		return
	if packed == null:
		_fail("Main.tscn не загрузился")
		return
	_emit(8.0)

	_setup_viewport()
	await _render_frames(1)
	if not _alive():
		return
	_emit(11.0, STAGE_INSTANCE)

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
	await _render_frames(3)
	if not _alive():
		return
	_emit(18.0)

	# The same two calls game.gd makes on the baked arena: perimeter ridge and
	# runtime props/materials (grass, paths, crystals, ruin columns...).
	if _arena != null:
		ArenaKit.ensure_perimeter_ridge(_arena)
		await _render_frames(2)
		if not _alive():
			return
		_emit(24.0, STAGE_ARENA)
		ArenaKit.ensure_arena_features(_arena)
		await _render_frames(2)
		report["arena_children"] = _arena.get_child_count()
	if not _alive():
		return
	_emit(31.0)
	await _render_arena_views()
	if not _alive():
		return
	_emit(36.0)
	report["video_after_arena_mb"] = snappedf(
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0, 0.1
	)

	await _warm_characters()
	if not _alive():
		return
	_emit(56.0)

	await _warm_props()
	if not _alive():
		return
	_emit(64.0)

	await _warm_vfx()
	if not _alive():
		return
	_emit(88.0)
	report["video_after_vfx_mb"] = snappedf(
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0, 0.1
	)

	_set_stage(STAGE_SHADERS)
	_emit(88.0)
	await _warm_shaders()
	if not _alive():
		return
	_emit(94.0)

	_set_stage(STAGE_FINAL)
	_emit(94.0)
	await _render_final_views()
	if not _alive():
		return
	var reload_started := Time.get_ticks_msec()
	var cached_main := load(MAIN_SCENE_PATH)
	report["reload_ms"] = Time.get_ticks_msec() - reload_started
	report["main_cached"] = cached_main != null
	_emit(99.0)

	report["elapsed"] = _elapsed()
	_emit(100.0, STAGE_DONE)
	_cleanup()
	# Give the viewport and the stripped arena two frames to actually leave
	# the tree before lobby.gd switches scenes.
	await _render_frames(2)
	if not is_inside_tree():
		return
	_done = true
	_running = false
	report["stage_times"] = _stage_times()
	finished.emit()


func _setup_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "WarmupFlowViewport"
	_viewport.size = Vector2i(384, 216)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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


func _warm_characters() -> void:
	_set_stage(STAGE_HEROES)
	var total := CHARACTER_SCENES.size()
	for index in total:
		if not _alive():
			return
		var path: String = CHARACTER_SCENES[index]
		var packed := await _load_threaded(path)
		if packed is PackedScene:
			var model := (packed as PackedScene).instantiate() as Node3D
			if model != null:
				model.position = Vector3(-4.6 + 2.3 * float(index), 0.05, 1.4)
				_viewport.add_child(model)
				_play_first_animation(model)
				await _render_frames(3)
				model.queue_free()
				await _render_frames(1)
				report["heroes_warmed"] = int(report["heroes_warmed"]) + 1
		_emit(36.0 + 20.0 * float(index + 1) / float(total))
	await _render_frames(1)


func _warm_props() -> void:
	_set_stage(STAGE_WEAPONS)
	var total := PROP_SCENES.size()
	for index in total:
		if not _alive():
			return
		var packed := await _load_threaded(PROP_SCENES[index])
		if packed is PackedScene:
			var prop := (packed as PackedScene).instantiate() as Node3D
			if prop != null:
				prop.position = Vector3(-5.0 + 1.1 * float(index), 1.0, -1.6)
				_viewport.add_child(prop)
				await _render_frames(2)
				prop.queue_free()
				await _render_frames(1)
				report["props_warmed"] = int(report["props_warmed"]) + 1
		_emit(56.0 + 8.0 * float(index + 1) / float(total))


func _warm_vfx() -> void:
	_set_stage(STAGE_VFX)
	_emit(64.0)
	var preloader: Variant = VFX_PRELOADER.new()
	preloader.name = "WarmupVfxPreloader"
	preloader.step_progress.connect(_on_vfx_step)
	add_child(preloader)
	var deadline := Time.get_ticks_msec() + 30000
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
	# Hero hit-flash copies materials at runtime; render an emissive copy once.
	await _warm_emissive_flash()
	# Mobile fireflies: the first GPUParticles3D draw compiles a separate
	# particle shader, which used to hitch right after the arena appears.
	await _warm_gpu_particles()
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
	await _warm_canvas_shaders()
	await _render_frames(1)


func _warm_canvas_shaders() -> void:
	# HUD shaders are canvas_item, so they need a 2D draw pass, not a 3D mesh.
	# They compile in the same hidden viewport and are freed right away.
	var canvas := SubViewport.new()
	_canvas = canvas
	canvas.name = "WarmupFlowCanvas"
	canvas.size = Vector2i(64, 64)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(canvas)
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(layer)
	for path in CANVAS_SHADERS:
		if not _alive():
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
		_camera.position = position
		_camera.look_at(Vector3(0.0, 0.6, 0.0), Vector3.UP)
		await _render_frames(2)


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
		_camera.position = position
		_camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)
		await _render_frames(2)
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
		await get_tree().process_frame
		_frames += 1
		report["frames_rendered"] = _frames


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


func _alive() -> bool:
	if is_inside_tree():
		return true
	_running = false
	_done = true
	return false


func _cleanup() -> void:
	if _viewport != null and is_instance_valid(_viewport):
		report["main_freed"] = _main != null
		_viewport.queue_free()
	if _canvas != null and is_instance_valid(_canvas):
		_canvas.queue_free()
	_viewport = null
	_canvas = null
	_camera = null
	_main = null
	_arena = null


func _fail(message: String) -> void:
	report["failed"] = true
	report["error"] = message
	report["elapsed"] = _elapsed()
	push_error("[WarmupFlow] " + message)
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
	_peak_static_mb = maxf(_peak_static_mb, float(OS.get_static_memory_usage()) / 1048576.0)
	_peak_video_mb = maxf(
		_peak_video_mb,
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0
	)
	report["peak_static_mb"] = snappedf(_peak_static_mb, 0.1)
	report["peak_video_mb"] = snappedf(_peak_video_mb, 0.1)
	_progress = clampf(percent, 0.0, 100.0)
	progress_changed.emit(_progress, _elapsed(), _stage)


func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _started_ms) / 1000.0
