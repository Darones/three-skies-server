extends Node3D

## Read-only performance audit probe.
##
## Starts a normal bot match and, once it is live, records what actually costs
## frames: rendered lights (with the full tree visible, not just the node flag),
## particles, shadow casters, transparent/additive materials, WorldEnvironment
## post effects, draw calls and memory. Also keeps a per-frame timeline so the
## audit can be read together with hitches.
##
## One configuration per process:
##   godot_console --path . tools/PerfAuditProbe.tscn -- --layout=1440x734 --quality=high --tag=desktop_high
##   godot_console --path . tools/PerfAuditProbe.tscn -- --layout=844x390 --mobile --quality=low --tag=mobile_low
##
## Writes user://perf_logs/perf_audit_<tag>.json and prints AUDIT_JSON plus a
## short AUDIT_SUMMARY line.

const MAIN_SCENE := "res://scenes/Main.tscn"

var tag := "audit"
var run_seconds := 16.0
var sample_interval := 0.25
var target_size := Vector2i(1440, 734)
var force_mobile := false
var quality := ""
var render_scale_override := 0.0
var fx_shot := false

var game: Node = null
var phase := "boot"
var live_usec := 0
var frame_usec := 0
var last_sample_usec := 0
var frames: Array = []
var light_peak := 0
var light_paths := {}
var particle_peak := {}
var samples: Array = []
var snapshots: Array = []


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
		elif arg.begins_with("--seconds="):
			run_seconds = maxf(4.0, float(arg.trim_prefix("--seconds=")))
		elif arg.begins_with("--render-scale="):
			render_scale_override = maxf(0.25, float(arg.trim_prefix("--render-scale=")))
		elif arg == "--fx-shot":
			fx_shot = true

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
	if render_scale_override > 0.0:
		get_tree().root.scaling_3d_scale = render_scale_override
	DisplayServer.window_set_size(target_size)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for _i in 3:
		await get_tree().process_frame
	await _run()


func _run() -> void:
	phase = "load"
	var packed := load(MAIN_SCENE) as PackedScene
	phase = "instantiate"
	game = packed.instantiate()
	add_child(game)
	for _i in 12:
		await get_tree().process_frame
	phase = "start_match"
	var started := Time.get_ticks_usec()
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	var deadline := started + 90_000_000
	while String(game.get("state")) != "live" and Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
	live_usec = Time.get_ticks_usec()
	frame_usec = live_usec
	last_sample_usec = live_usec
	phase = "live"
	snapshots.append(_snapshot("live_0s"))
	if fx_shot:
		await _capture_fx_shot()

	var end_usec := live_usec + int(run_seconds * 1_000_000.0)
	var next_snapshot_ms := 2500.0
	while Time.get_ticks_usec() < end_usec:
		await get_tree().process_frame

	_report()
	get_tree().quit()


func _process(_delta: float) -> void:
	if phase != "live" or live_usec == 0:
		return
	var now := Time.get_ticks_usec()
	var elapsed_ms := float(now - live_usec) / 1000.0
	if frame_usec > 0:
		var frame_ms := float(now - frame_usec) / 1000.0
		if String(game.get("state")) == "live":
			frames.append([snappedf(elapsed_ms, 1.0), snappedf(frame_ms, 0.01)])
	frame_usec = now
	if now - last_sample_usec >= int(sample_interval * 1_000_000.0):
		last_sample_usec = now
		_sample()
	if elapsed_ms >= 6000.0 and snapshots.size() == 1:
		snapshots.append(_snapshot("clash_6s"))


func _capture_fx_shot() -> void:
	var player: Node = game.get("player")
	for _i in 20:
		await get_tree().process_frame
	if player == null or not is_instance_valid(player):
		return
	var base: Vector3 = (player as Node3D).global_position
	for index in 4:
		var offset := Vector3(cos(index * 1.57) * 1.2, 0.9 + index * 0.25, sin(index * 1.57) * 1.2)
		player.call("spawn_attack_impact_vfx", base + offset, "")
	player.call("spawn_ability_vfx", 1, base + Vector3(0.0, 1.2, 0.0))
	var fx_amount := 0
	var fx_nodes := 0
	var fx_lights := 0
	for node in game.find_children("*", "GPUParticles3D", true, false):
		var particles := node as GPUParticles3D
		if not particles.is_visible_in_tree():
			continue
		fx_nodes += 1
		fx_amount += particles.amount
	for node in game.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if String(light.name) == "VFXOmniLightBB" and light.is_visible_in_tree():
			fx_lights += 1
	print("AUDIT_FX_AMOUNT nodes=%d amount=%d vfx_lights=%d" % [fx_nodes, fx_amount, fx_lights])
	await get_tree().create_timer(0.12).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://perf_logs")
	var path := "user://perf_logs/audit_fx_%s.png" % tag
	image.save_png(path)
	print("AUDIT_FX_SHOT ", ProjectSettings.globalize_path(path))


func _sample() -> void:
	var lights := _rendered_lights()
	if lights.size() > light_peak:
		light_peak = lights.size()
	for path in lights:
		light_paths[path] = int(light_paths.get(path, 0)) + 1
	var gpu := 0
	var gpu_amount := 0
	var cpu := 0
	var cpu_amount := 0
	for node in game.find_children("*", "GPUParticles3D", true, false):
		var particles := node as GPUParticles3D
		if not particles.is_visible_in_tree():
			continue
		if particles.emitting:
			gpu += 1
			gpu_amount += particles.amount
	for node in game.find_children("*", "CPUParticles3D", true, false):
		var particles := node as CPUParticles3D
		if not particles.is_visible_in_tree():
			continue
		if particles.emitting:
			cpu += 1
			cpu_amount += particles.amount
	particle_peak["gpu"] = maxi(int(particle_peak.get("gpu", 0)), gpu)
	particle_peak["gpu_amount"] = maxi(int(particle_peak.get("gpu_amount", 0)), gpu_amount)
	particle_peak["cpu"] = maxi(int(particle_peak.get("cpu", 0)), cpu)
	particle_peak["cpu_amount"] = maxi(int(particle_peak.get("cpu_amount", 0)), cpu_amount)
	particle_peak["lights"] = maxi(int(particle_peak.get("lights", 0)), lights.size())
	samples.append({
		"t": snappedf(float(last_sample_usec - live_usec) / 1000.0, 10.0),
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects_drawn": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"video_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"lights": lights.size(),
		"gpu_particles": gpu,
		"gpu_amount": gpu_amount,
		"cpu_particles": cpu,
		"cpu_amount": cpu_amount,
	})


func _rendered_lights() -> Array:
	var result := []
	for node in game.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light.is_visible_in_tree():
			result.append(String(game.get_path_to(light)))
	return result


func _snapshot(label: String) -> Dictionary:
	var light_rows := []
	var shadow_lights := 0
	for node in game.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light is DirectionalLight3D:
			var sun := light as DirectionalLight3D
			if sun.shadow_enabled:
				shadow_lights += 1
		elif light.shadow_enabled:
			shadow_lights += 1
		if not light.is_visible_in_tree():
			continue
		var parent := light.get_parent()
		light_rows.append({
			"name": String(light.name),
			"parent": String(parent.name) if parent != null else "",
			"type": light.get_class(),
			"shadow": light.shadow_enabled,
			"energy": snappedf(light.light_energy, 0.01),
			"range": snappedf(light.omni_range, 0.1) if light is OmniLight3D else 0.0,
		})
	var mesh_count := 0
	var shadow_casters := 0
	var transparent_materials := {}
	var shader_materials := {}
	var multi_mesh := 0
	var label3d := 0
	for node in game.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry is MeshInstance3D:
			mesh_count += 1
		if geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_casters += 1
		if geometry is MultiMeshInstance3D:
			multi_mesh += 1
	for node in game.find_children("*", "Label3D", true, false):
		label3d += 1
	var env_rows := []
	for node in game.find_children("*", "WorldEnvironment", true, false):
		var world_env := node as WorldEnvironment
		if world_env.environment == null:
			continue
		var env := world_env.environment
		env_rows.append({
			"node": String(world_env.name),
			"glow": env.glow_enabled,
			"ssao": env.ssao_enabled,
			"ssil": env.ssil_enabled,
			"fog": env.fog_enabled,
			"volumetric_fog": env.volumetric_fog_enabled,
			"sdfgi": env.sdfgi_enabled,
			"tonemap": env.tonemap_mode,
			"ambient_energy": snappedf(env.ambient_light_energy, 0.01),
		})
	var mesh_rows := []
	var texture_rows := {}
	var seen_meshes := {}
	var seen_materials := {}
	var triangles := 0
	for node in game.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh
		if mesh == null:
			continue
		var mesh_id := mesh.get_instance_id()
		if seen_meshes.has(mesh_id):
			continue
		seen_meshes[mesh_id] = true
		var mesh_triangles := 0
		var mesh_vertices := 0
		for surface in mesh.get_surface_count():
			if mesh is ArrayMesh:
				var array_mesh := mesh as ArrayMesh
				var surface_vertices: int = array_mesh.surface_get_array_len(surface)
				var surface_indices: int = array_mesh.surface_get_array_index_len(surface)
				mesh_vertices += surface_vertices
				mesh_triangles += (surface_indices if surface_indices > 0 else surface_vertices) / 3
			elif mesh is PrimitiveMesh:
				var primitive := mesh as PrimitiveMesh
				var face_count := primitive.get_faces().size()
				mesh_vertices += face_count
				mesh_triangles += face_count / 3
		triangles += mesh_triangles
		mesh_rows.append({
			"name": String(mesh_instance.name),
			"mesh": String(mesh.resource_path).get_file() if not String(mesh.resource_path).is_empty() else String(mesh.get_class()),
			"vertices": mesh_vertices,
			"triangles": mesh_triangles,
		})
	mesh_rows.sort_custom(func(a, b): return int(a["triangles"]) > int(b["triangles"]))
	# Count every material once across all geometry (mesh, particles, labels).
	for node in game.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		for material in _materials_of(geometry):
			if material == null or seen_materials.has(material.get_instance_id()):
				continue
			seen_materials[material.get_instance_id()] = true
			_collect_textures(material, texture_rows)
			if material is ShaderMaterial:
				var shader := (material as ShaderMaterial).shader
				var path := shader.resource_path if shader != null else "runtime_shader"
				shader_materials[path] = int(shader_materials.get(path, 0)) + 1
				if path.contains("hit_fx") or path.contains("glow") or path.contains("flare") or path.contains("star") or path.contains("streaks") or path.contains("impact"):
					var fx_key := "fx:" + path.get_file()
					transparent_materials[fx_key] = int(transparent_materials.get(fx_key, 0)) + 1
			elif material is StandardMaterial3D:
				var std := material as StandardMaterial3D
				if std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					var key := "std:%s" % ("alpha" if std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA else "other")
					transparent_materials[key] = int(transparent_materials.get(key, 0)) + 1
	var texture_list := []
	var texture_bytes := 0
	for path in texture_rows.keys():
		var row: Dictionary = texture_rows[path]
		texture_list.append(row)
		texture_bytes += int(row["bytes"])
	texture_list.sort_custom(func(a, b): return int(a["bytes"]) > int(b["bytes"]))
	var viewport := get_viewport()
	return {
		"label": label,
		"at_ms": snappedf(float(Time.get_ticks_usec() - live_usec) / 1000.0, 1.0),
		"render_scale": snappedf(viewport.scaling_3d_scale, 0.01),
		"msaa": viewport.msaa_3d,
		"screen_aa": viewport.screen_space_aa,
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects_drawn": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"video_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"lights_visible": light_rows.size(),
		"shadow_lights": shadow_lights,
		"meshes": mesh_count,
		"shadow_casters": shadow_casters,
		"multimesh": multi_mesh,
		"label3d": label3d,
		"triangles_unique_meshes": triangles,
		"meshes_top": mesh_rows.slice(0, 10),
		"textures_top": texture_list.slice(0, 12),
		"texture_mb_estimate": snappedf(float(texture_bytes) / 1048576.0, 0.1),
		"transparent_materials": transparent_materials,
		"shader_materials_top": _top(shader_materials, 12),
		"lights": light_rows,
		"environment": env_rows,
	}


func _materials_of(geometry: GeometryInstance3D) -> Array:
	var result := []
	if geometry.material_override != null:
		result.append(geometry.material_override)
		return result
	if geometry.material_overlay != null:
		result.append(geometry.material_overlay)
	if not geometry is MeshInstance3D:
		return result
	var mesh_instance := geometry as MeshInstance3D
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return result
	for surface in mesh.get_surface_count():
		var material: Material = mesh_instance.get_surface_override_material(surface)
		if material == null:
			material = mesh.surface_get_material(surface)
		if material != null:
			result.append(material)
	return result


func _collect_textures(material: Material, rows: Dictionary) -> void:
	if material is StandardMaterial3D:
		var std := material as StandardMaterial3D
		for key in ["albedo_texture", "normal_texture", "orm_texture", "emission_texture", "heightmap_texture"]:
			_add_texture(std.get(key) as Texture2D, rows)
	elif material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		for key in ["albedo_texture", "noise_texture", "flare_texture", "texture_albedo", "flow_texture"]:
			_add_texture(shader_material.get_shader_parameter(key) as Texture2D, rows)


func _add_texture(texture: Texture2D, rows: Dictionary) -> void:
	if texture == null:
		return
	var path := texture.resource_path
	var key := path if not path.is_empty() else "runtime_%d" % texture.get_instance_id()
	if rows.has(key):
		return
	var width := texture.get_width()
	var height := texture.get_height()
	rows[key] = {
		"path": key.get_file(),
		"size": [width, height],
		"bytes": int(float(width) * float(height) * 4.0 * 1.333),
		"raw_mb": snappedf(float(width) * float(height) * 4.0 * 1.333 / 1048576.0, 0.01),
		"mipmaps": texture.has_mipmaps(),
	}


func _transient(rows: Array, total_samples: int) -> Array:
	var result := []
	for row in rows:
		if int(row["samples"]) < total_samples:
			result.append(row)
	return result.slice(0, 25)


func _top(values: Dictionary, count: int) -> Array:
	var rows := []
	for key in values.keys():
		rows.append({"key": String(key).get_file(), "count": int(values[key])})
	rows.sort_custom(func(a, b): return int(a["count"]) > int(b["count"]))
	return rows.slice(0, count)


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
	var over_20 := 0
	var over_33 := 0
	var over_50 := 0
	for value in values:
		total += value
		if value > 20.0:
			over_20 += 1
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
		"over_20ms": over_20,
		"over_33ms": over_33,
		"over_50ms": over_50,
	}


func _report() -> void:
	var draws := []
	var video := []
	var lights := []
	for sample in samples:
		draws.append(float(sample["draws"]))
		video.append(float(sample["video_mb"]))
		lights.append(float(sample["lights"]))
	draws.sort()
	video.sort()
	lights.sort()
	var peak_paths := []
	for path in light_paths.keys():
		peak_paths.append({"path": String(path), "samples": int(light_paths[path])})
	peak_paths.sort_custom(func(a, b): return int(a["samples"]) > int(b["samples"]))
	var report := {
		"tag": tag,
		"window": [target_size.x, target_size.y],
		"canvas": [int(get_viewport().get_visible_rect().size.x), int(get_viewport().get_visible_rect().size.y)],
		"mobile": DeviceProfile.mobile_ui,
		"quality": DeviceProfile.effective_quality(),
		"render_scale": DeviceProfile.quality_render_scale(),
		"frames": {
			"first_3s": _window_stats(0.0, 3000.0),
			"first_10s": _window_stats(0.0, 10000.0),
			"all": _window_stats(0.0, 1.0e9),
		},
		"draws": {"avg": snappedf(_avg(draws), 0.1), "max": snappedf(_maxf(draws), 0.1)},
		"video_mb": {"avg": snappedf(_avg(video), 0.1), "max": snappedf(_maxf(video), 0.1)},
		"lights": {"avg": snappedf(_avg(lights), 0.1), "max": snappedf(_maxf(lights), 0.1), "peak": light_peak},
		"light_paths_peak": peak_paths.slice(0, 20),
		"light_paths_transient": _transient(peak_paths, maxi(1, samples.size())),
		"particles_peak": particle_peak,
		"snapshots": snapshots,
		"samples": samples,
	}
	DirAccess.make_dir_recursive_absolute("user://perf_logs")
	var path := "user://perf_logs/perf_audit_%s.json" % tag
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("AUDIT_JSON ", ProjectSettings.globalize_path(path))
	print("AUDIT_SUMMARY=", JSON.stringify({
		"tag": tag, "quality": report["quality"], "render_scale": report["render_scale"],
		"canvas": report["canvas"], "frames": report["frames"],
		"draws": report["draws"], "video_mb": report["video_mb"], "lights": report["lights"],
		"particles_peak": particle_peak,
	}))


func _avg(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())


func _maxf(values: Array) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, float(value))
	return result
