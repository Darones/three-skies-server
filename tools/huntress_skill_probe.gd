extends Node3D

## Huntress (Fairy) 2nd ability hitch probe.
##
## Starts a real match as the Huntress, lets the opening brawl settle, then
## alternates CONTROL rounds (nothing cast) with CAST rounds (use_ability(1) as
## soon as it is off cooldown). For every round it records:
##   * the synchronous cost of the use_ability call,
##   * the frames right after the call (where cast-time shader compiles land),
##   * the frames around the shot release (~1 s later),
##   * the worst frame in the whole 2.2 s window, and every frame above 12 ms.
##
## Run:
##   godot --path . tools/HuntressSkillProbe.tscn
##   godot --path . tools/HuntressSkillProbe.tscn -- --mobile
##   godot --path . tools/HuntressSkillProbe.tscn -- --stock
##   godot --path . tools/HuntressSkillProbe.tscn -- --legendary
##   godot --path . tools/HuntressSkillProbe.tscn -- --shot       (save a channel frame)
##   godot --path . tools/HuntressSkillProbe.tscn -- --only=sound
##   (--only=: noop, noop_long, sound, sound0, sound2, burst, anim, impact,
##    weapon, weapon_parts, cast, multi)
## Web/phone renderer:
##   ... --rendering-method gl_compatibility --rendering-driver opengl3 -- --mobile

const ROUNDS := 8
const SETTLE_SECONDS := 5.0
const WINDOW_SECONDS := 2.2
const SPIKE_MS := 12.0

var game: Node = null
var player: Node = null

var _frame_usec := 0
var _frame_ms: Array[float] = []


func _ready() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	MetaProgression.unlocked_weapons = [1, 2, 3, 4, 5, 6, 7, 8, 9]
	MetaProgression.weapons_enabled = {"warrior": true, "mage": true, "fairy": true}
	if OS.get_cmdline_user_args().has("--legendary"):
		print("[HSP] equip legendary bow: %s" % str(MetaProgression.set_equipped_weapon("fairy", 8)))
	if OS.get_cmdline_user_args().has("--stock"):
		# In-memory only: the default built-in crossbows, no external weapon.
		MetaProgression.equipped_weapons["fairy"] = 0
	game = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	for i in 10:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.FAIRY, 0)
	await _wait_for_player()
	await _run()
	get_tree().quit()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _frame_usec > 0:
		_frame_ms.append(float(now - _frame_usec) / 1000.0)
	_frame_usec = now


func _wait_for_player() -> void:
	for i in 600:
		await get_tree().process_frame
		if not is_instance_valid(game):
			return
		if String(game.get("state")) != "live":
			continue
		var candidate := game.get("player") as Node
		if candidate == null or not is_instance_valid(candidate):
			continue
		player = candidate
		break
	print("[HSP] player ready=%s weapon_instance=%s" % [
		str(player != null), str(player != null and player.get("weapon_instance") != null)
	])


func _run() -> void:
	if player == null:
		print("[HSP] FAIL no player")
		return
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var baseline := _frame_ms.slice(maxi(0, _frame_ms.size() - 60))
	print("[HSP] baseline avg=%.2fms max=%.2fms nodes=%d mobile=%s quality=%s" % [
		_avg(baseline), _max(baseline), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		str(DeviceProfile.mobile_ui), DeviceProfile.effective_quality()
	])
	var only := _only_mode()
	if not only.is_empty():
		await _attribute(only)
		print("HSP_DONE")
		return

	var node_start := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var cast_max := 0.0
	var control_max := 0.0
	var cast_total := 0.0
	var control_total := 0.0
	var cast_windows := 0
	var control_windows := 0
	var used := 0
	var call_max := 0.0
	var release_max := 0.0
	for round_index in ROUNDS:
		var is_cast := round_index % 2 == 1
		var result := await _round(round_index, is_cast)
		if bool(result["used"]):
			used += 1
		print("[HSP] round=%d kind=%s used=%s sync=%.2f cast_frame=%.2f release_frame=%.2f window_max=%.2f window_avg=%.2f nodes=%+d spikes=%s" % [
			round_index + 1, "cast" if is_cast else "control", str(result["used"]),
			float(result["sync"]), float(result["cast_frame"]), float(result["release_frame"]),
			float(result["max"]), float(result["avg"]),
			int(result["nodes"]), String(result["spikes"])
		])
		if is_cast:
			cast_max = maxf(cast_max, float(result["max"]))
			cast_total += float(result["avg"])
			cast_windows += 1
			if bool(result["used"]):
				call_max = maxf(call_max, float(result["cast_frame"]))
				release_max = maxf(release_max, float(result["release_frame"]))
		else:
			control_max = maxf(control_max, float(result["max"]))
			control_total += float(result["avg"])
			control_windows += 1
		if is_cast and not bool(result["used"]):
			print("[HSP]   blocked: dead=%s stun=%.2f storm=%.2f cd=%s cds=%s hp=%.0f" % [
				str(player.get("dead")), float(player.get("stun_timer")),
				float(player.get("lightning_storm_timer")), str(player.get("crit_cast_timer")),
				str(player.get("ability_cds")), float(player.get("health"))
			])
		await _verify(round_index)
	var node_end := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("[HSP] SUMMARY used=%d/%d cast_max=%.2f control_max=%.2f cast_avg=%.2f control_avg=%.2f cast_frame_max=%.2f release_frame_max=%.2f nodes_delta=%d" % [
		used, ROUNDS / 2, cast_max, control_max,
		cast_total / maxf(1.0, float(cast_windows)), control_total / maxf(1.0, float(control_windows)),
		call_max, release_max, node_end - node_start
	])
	print("[HSP] VERDICT %s" % ("HITCH" if cast_max > maxf(50.0, control_max * 2.0) else "OK"))
	print("HSP_DONE")


func _round(round_index: int, is_cast: bool) -> Dictionary:
	for i in 120:
		if float(player.get("crit_cast_timer")) <= 0.0:
			break
		await get_tree().process_frame
	_force_ready()
	# Give the build a live, close target inside the Huntress attack range.
	var target := _stage_target()
	if target == null:
		return {"used": false, "sync": 0.0, "max": 0.0, "avg": 0.0, "spikes": "no target", "nodes": 0, "cast_frame": 0.0, "release_frame": 0.0}
	player.set("attack_cd", 60.0)
	for i in 4:
		await get_tree().process_frame
	if is_cast and player.call("_crit_shot_target") == null:
		# The staged bot died or drifted while the match ran; restage once.
		_stage_target()
		for i in 2:
			await get_tree().process_frame
	var start := _frame_ms.size()
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var t0 := Time.get_ticks_usec()
	var used := false
	if is_cast:
		used = bool(player.call("use_ability", 1))
	var sync := float(Time.get_ticks_usec() - t0) / 1000.0
	var call_frames := _frame_ms.size()
	if is_cast and used and OS.get_cmdline_user_args().has("--shot"):
		await get_tree().create_timer(0.45).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://ui_shots")
		get_viewport().get_texture().get_image().save_png("user://ui_shots/huntress_crit_channel.png")
	# A cast lasts 1 s and the shot lands ~0.3 s later.
	await get_tree().create_timer(WINDOW_SECONDS).timeout
	var end := _frame_ms.size()
	var slice := _frame_ms.slice(start, end)
	var release_start := start
	var elapsed := 0.0
	while release_start < end and elapsed < 900.0:
		elapsed += _frame_ms[release_start]
		release_start += 1
	return {
		"used": used,
		"sync": sync,
		"max": _max(slice),
		"avg": _avg(slice),
		"spikes": _spikes_text(start, end),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - nodes_before,
		"cast_frame": _max(_frame_ms.slice(start, mini(end, call_frames + 2))),
		"release_frame": _max(_frame_ms.slice(release_start, mini(end, release_start + 20))),
	}


func _only_mode() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			return arg.trim_prefix("--only=")
	return ""


func _attribute(mode: String) -> void:
	_force_ready()
	var target := _stage_target()
	if target != null:
		player.set("attack_cd", 60.0)
	for i in 4:
		await get_tree().process_frame
	var start := _frame_ms.size()
	var pos: Vector3 = player.global_position + Vector3(0.0, 0.6, 0.0)
	var t0 := Time.get_ticks_usec()
	match mode:
		"noop":
			pass
		"noop_long":
			await get_tree().create_timer(WINDOW_SECONDS).timeout
		"multi":
			game.call("burst", pos, Color(1.0, 0.16, 0.1), 12)
			for i in 40:
				await get_tree().process_frame
			player.call("_play_ability_sfx", 1)
			for i in 40:
				await get_tree().process_frame
			player.call("_play_anim", "cast", true)
		"sound":
			player.call("_play_ability_sfx", 1)
		"sound0":
			player.call("_play_ability_sfx", 0)
		"sound2":
			player.call("_play_ability_sfx", 2)
		"burst":
			game.call("burst", pos, Color(1.0, 0.16, 0.1), 12)
		"anim":
			player.call("_play_anim", "cast", true)
		"impact":
			player.call("spawn_attack_impact_vfx", pos, "")
		"weapon":
			player.call("_begin_crit_cast_visuals")
		"weapon_parts":
			_weapon_parts()
		"cast":
			player.call("use_ability", 1)
		_:
			print("[HSP] unknown --only=%s" % mode)
			return
	var sync := float(Time.get_ticks_usec() - t0) / 1000.0
	await get_tree().create_timer(WINDOW_SECONDS).timeout
	var end := _frame_ms.size()
	var slice := _frame_ms.slice(start, end)
	print("[HSP] attribute mode=%s sync=%.2fms window_max=%.2fms window_avg=%.2fms spikes=%s" % [
		mode, sync, _max(slice), _avg(slice), _spikes_text(start, end)
	])


func _force_ready() -> void:
	if float(player.get("health")) <= 0.0 or bool(player.get("dead")):
		player.set("dead", false)
		player.set("health", float(player.get("max_health")))
	player.set("stun_timer", 0.0)
	player.set("lightning_storm_timer", 0.0)
	player.set("crit_cast_timer", 0.0)
	var cds: Array = player.get("ability_cds")
	for i in cds.size():
		cds[i] = 0.0


func _stage_target() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for hero in game.get("heroes"):
		var unit := hero as Node3D
		if unit == null or not is_instance_valid(unit):
			continue
		if int(unit.get("team")) == int(player.get("team")):
			continue
		if bool(unit.get("dead")):
			continue
		unit.set("health", float(unit.get("max_health")))
		var dist: float = unit.global_position.distance_to(player.global_position)
		if dist < best_dist:
			best_dist = dist
			best = unit
	if best == null:
		return null
	var facing: Vector3 = player.call("_facing_direction")
	facing.y = 0.0
	if facing.length_squared() < 0.001:
		facing = Vector3.FORWARD
	var spot: Vector3 = player.global_position + facing.normalized() * 5.0
	best.global_position = Vector3(spot.x, player.global_position.y, spot.z)
	return best


func _weapon_parts() -> void:
	var weapon = player.get("weapon_instance")
	if weapon == null:
		print("[HSP] weapon_parts no weapon_instance")
		return
	var t := Time.get_ticks_usec()
	var meshes: Array = weapon.find_children("*", "MeshInstance3D", true, false)
	var find_ms := float(Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	var duplicated := 0
	for child in meshes:
		var mesh_node := child as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		if mesh_node.material_override is StandardMaterial3D:
			var copy := (mesh_node.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
			if copy != null:
				duplicated += 1
		for surface in range(mesh_node.mesh.get_surface_count()):
			var active := mesh_node.get_active_material(surface)
			if active is StandardMaterial3D:
				var copy := (active as StandardMaterial3D).duplicate() as StandardMaterial3D
				if copy != null:
					duplicated += 1
	var dup_ms := float(Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	var texture: Texture2D = player.call("_weapon_glow_texture")
	var texture_ms := float(Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	player.call("_build_crit_cast_particles")
	var particles_ms := float(Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	player.call("_stop_crit_cast_visuals")
	var stop_ms := float(Time.get_ticks_usec() - t) / 1000.0
	print("[HSP] weapon_parts meshes=%d duplicated=%d find=%.2fms dup=%.2fms texture=%.2fms particles=%.2fms stop=%.2fms texture_valid=%s" % [
		meshes.size(), duplicated, find_ms, dup_ms, texture_ms, particles_ms, stop_ms, str(texture != null)
	])


func _verify(round_index: int) -> void:
	var weapon = player.get("weapon_instance")
	if weapon == null or not is_instance_valid(weapon):
		return
	var meshes: Array = weapon.find_children("*", "MeshInstance3D", true, false)
	var shader_surfaces := 0
	var standard_surfaces := 0
	var red_materials := 0
	for child in meshes:
		var mesh_node := child as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		for surface in range(mesh_node.mesh.get_surface_count()):
			var material := mesh_node.get_surface_override_material(surface)
			if material is ShaderMaterial:
				shader_surfaces += 1
			elif material is StandardMaterial3D:
				standard_surfaces += 1
				var emission := (material as StandardMaterial3D).emission
				if emission.r > 0.8 and emission.g < 0.4:
					red_materials += 1
	var particles = player.get("crit_cast_particles")
	print("[HSP] verify round=%d bow_shader_surfaces=%d standard_surfaces=%d left_red=%d sparks_valid=%s sparks_emitting=%s ready=%s" % [
		round_index + 1, shader_surfaces, standard_surfaces, red_materials,
		str(particles != null and is_instance_valid(particles)),
		str(particles != null and is_instance_valid(particles) and bool(particles.get("emitting"))),
		str(bool(player.get("crit_cast_visuals_ready")))
	])


func _spikes_text(start: int, end: int) -> String:
	var elapsed := 0.0
	var lines: Array[String] = []
	var index := maxi(0, start)
	while index < mini(end, _frame_ms.size()):
		if _frame_ms[index] >= SPIKE_MS:
			lines.append("%.1fms@%.0fms" % [_frame_ms[index], elapsed])
		elapsed += _frame_ms[index]
		index += 1
	return "none" if lines.is_empty() else ", ".join(lines)


func _avg(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += float(v)
	return total / float(values.size())


func _max(values: Array) -> float:
	var top := 0.0
	for v in values:
		top = maxf(top, float(v))
	return top
