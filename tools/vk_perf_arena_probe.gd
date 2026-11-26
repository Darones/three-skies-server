extends Node3D

## Arena look/regression probe (read-only QA).
##
## Builds the real arena the way the match does (Main.tscn without game.gd, then
## ArenaKit.ensure_perimeter_ridge + ensure_arena_features) and saves frames from
## a fixed set of cameras. Used to prove that a material change (cull mode,
## rim, quality budget) does not remove any of the floor/plaza/grass/void and
## does not change the arena look.
##
## Run windowed:
##   godot_console --path . tools/vk_perf_arena_probe.tscn -- --tag=after
##   godot_console --path . tools/vk_perf_arena_probe.tscn -- --tag=before --cull=disabled
##   godot_console --path . tools/vk_perf_arena_probe.tscn -- --tag=high --quality=high
##
## --cull=disabled forces CULL_DISABLED on the shared arena materials, which is
## what the code did before the 27.11.2026 variant work, so the two runs are an
## A/B of the same scene. Writes res://docs/qa-vk-arena-cull/<tag>-<view>.png
## plus one ARENA_PROBE_* line per view.

const MAIN_SCENE := "res://scenes/Main.tscn"
const OUT_DIR := "res://docs/qa-vk-arena-cull"

const VIEWS := [
	{"name": "match", "pos": Vector3(0.0, 16.0, 15.0), "look": Vector3(0.0, 0.8, 0.0)},
	{"name": "top", "pos": Vector3(0.0, 34.0, 20.0), "look": Vector3(0.0, 0.0, 0.0)},
	{"name": "edge", "pos": Vector3(38.0, 10.0, 44.0), "look": Vector3(0.0, 0.5, 0.0)},
	{"name": "low", "pos": Vector3(0.0, 2.2, 30.0), "look": Vector3(0.0, 1.0, 0.0)},
]

var tag := "arena"
var quality := ""
var cull_mode := "keep"
var target_size := Vector2i(1280, 720)

var arena: Node3D = null
var camera: Camera3D = null


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			tag = arg.trim_prefix("--tag=")
		elif arg.begins_with("--quality="):
			quality = arg.trim_prefix("--quality=")
		elif arg.begins_with("--cull="):
			cull_mode = arg.trim_prefix("--cull=")
		elif arg.begins_with("--layout="):
			var parts := arg.trim_prefix("--layout=").split("x")
			if parts.size() == 2:
				target_size = Vector2i(int(parts[0]), int(parts[1]))
	if not quality.is_empty():
		# Runtime only: does not touch user://settings.cfg.
		DeviceProfile.graphics_quality = quality
	if target_size.x > 0:
		DisplayServer.window_set_size(target_size)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		print("ARENA_PROBE_FAIL scene")
		get_tree().quit(1)
		return
	arena = packed.instantiate() as Node3D
	arena.set_script(null)
	# The baked scene's own camera stays out of the way.
	var baked_camera := arena.get_node_or_null("Camera3D") as Camera3D
	if baked_camera != null:
		baked_camera.current = false
	add_child(arena)
	var arena_root := arena.get_node_or_null("Arena") as Node3D
	if arena_root != null:
		ArenaKit.ensure_perimeter_ridge(arena_root)
		ArenaKit.ensure_arena_features(arena_root)

	camera = Camera3D.new()
	camera.name = "ArenaProbeCamera"
	camera.fov = 46.0
	camera.near = 0.1
	camera.far = 400.0
	add_child(camera)
	camera.current = true

	if cull_mode == "disabled":
		_force_cull_disabled(arena)
	_cull_report()

	for _frame in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for view in VIEWS:
		camera.position = view["pos"]
		camera.look_at(view["look"], Vector3.UP)
		for _frame in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := "%s/%s-%s.png" % [OUT_DIR, tag, view["name"]]
		var error := image.save_png(path)
		print("ARENA_PROBE_VIEW tag=%s view=%s path=%s error=%d size=%dx%d cull=%s"
			% [tag, view["name"], path, error, image.get_width(), image.get_height(), cull_mode])
	print("ARENA_PROBE_DONE tag=%s" % tag)
	get_tree().quit(0)


## Emulates the pre-change materials: the arena floor/rock/plaza/grass and the
## void backdrop go back to CULL_DISABLED. Leaves are already CULL_DISABLED.
func _force_cull_disabled(root: Node) -> void:
	for material in [
		ArenaKit.floor_light_material(),
		ArenaKit.rock_material(),
		ArenaKit.plaza_material(),
		ArenaKit.grass_material(),
	]:
		if material is BaseMaterial3D:
			(material as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var material := mesh_instance.material_override as BaseMaterial3D
		if material == null:
			continue
		# The void backdrop: unshaded black annulus under the arena.
		if material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and material.albedo_color == Color.BLACK:
			material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _cull_report() -> void:
	var disabled := 0
	var total := 0
	for node in arena.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or not mesh_instance.is_visible_in_tree():
			continue
		var material := mesh_instance.material_override as BaseMaterial3D
		if material == null:
			continue
		total += 1
		if material.cull_mode == BaseMaterial3D.CULL_DISABLED:
			disabled += 1
	print("ARENA_PROBE_CULL visible_materials=%d disabled=%d cull=%s" % [total, disabled, cull_mode])
