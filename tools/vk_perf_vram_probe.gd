extends Node3D

## VRAM attribution probe (read-only QA).
##
## Loads Main.tscn the way WarmupFlow does, renders the arena, then frees it and
## reports video/texture memory at each step. Built for the 27.11.2026 shader
## work: it shows whether a change keeps arena textures alive after the warmup
## instance is freed (the two-pass mode of WarmupFlow exists to avoid exactly
## that) and it prints the quality/fog/shadow state the arena is rendered with.
##
## Run windowed:
##   godot_console --path . tools/vk_perf_vram_probe.tscn -- --tag=high --quality=high
##   godot_console --path . tools/vk_perf_vram_probe.tscn -- --tag=low --quality=low

const MAIN_SCENE := "res://scenes/Main.tscn"

var tag := "vram"
var quality := "high"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			tag = arg.trim_prefix("--tag=")
		elif arg.begins_with("--quality="):
			quality = arg.trim_prefix("--quality=")
	DeviceProfile.graphics_quality = quality
	get_viewport().scaling_3d_scale = 0.5
	var packed := load(MAIN_SCENE) as PackedScene
	var arena := packed.instantiate() as Node3D
	arena.set_script(null)
	var baked_camera := arena.get_node_or_null("Camera3D") as Camera3D
	if baked_camera != null:
		baked_camera.current = false
	add_child(arena)
	var camera := Camera3D.new()
	camera.fov = 46.0
	camera.position = Vector3(0.0, 16.0, 15.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)
	camera.current = true
	var arena_root := arena.get_node_or_null("Arena") as Node3D
	_mark("loaded")
	ArenaKit.ensure_perimeter_ridge(arena_root)
	ArenaKit.ensure_arena_features(arena_root)
	var world_env := arena_root.get_node_or_null("Stage/WorldEnvironment") as WorldEnvironment
	var sun := arena_root.get_node_or_null("Stage/Sun") as DirectionalLight3D
	if world_env != null and world_env.environment != null and sun != null:
		print("VRAM_PROBE_STATE quality=%s fog=%s sun_shadow=%s"
			% [quality, str(world_env.environment.fog_enabled), str(sun.shadow_enabled)])
	await _frames(6)
	_mark("arena_built")
	arena.queue_free()
	await _frames(6)
	_mark("arena_freed")
	print("VRAM_PROBE_DONE tag=%s quality=%s" % [tag, quality])
	get_tree().quit(0)


func _mark(label: String) -> void:
	var video := float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0
	var static_mb := float(OS.get_static_memory_usage()) / 1048576.0
	var textures := float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0
	print("VRAM_PROBE tag=%s step=%s video=%.1f texture=%.1f static=%.1f"
		% [tag, label, video, textures, static_mb])


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
