extends Node3D

## Fog of war / damage number / bot name / respawn probe (read-only QA tool).
##
## Starts a normal bot match, then reports and photographs:
##   * the visual fog of war (node, height, shader params, vision orbs),
##   * every hero's display name (bots must read "БОТ 1234"),
##   * respawn_delay_for() at 0 / 1000 / 1500 / 2000 gold for the player and a bot,
##   * the outgoing (gold, big) and incoming (red, small) damage numbers,
##   * an enemy standing at the vision border, inside the fog band,
##   * the same view without the fog (--no-fog) for an A/B comparison.
##
## Run windowed, one configuration per process:
##   godot_console --path . tools/FogProbe.tscn -- --layout=844x390 --mobile --quality=low --tag=mobile-low --novsync
##   godot_console --path . tools/FogProbe.tscn -- --layout=1440x734 --quality=high --tag=desktop-high --novsync
##   godot_console --path . tools/FogProbe.tscn -- --layout=1440x734 --quality=high --tag=compat --rendering-method gl_compatibility
##   godot_console --path . tools/FogProbe.tscn -- --layout=844x390 --mobile --quality=low --tag=mobile-nofog --no-fog
##
## Writes res://docs/qa-fog/fog_<tag>_*.png and prints FOG_PROBE_* lines.

const MAIN_SCENE := "res://scenes/Main.tscn"
const OUT_DIR := "res://docs/qa-fog"

var tag := "run"
var target_size := Vector2i(844, 390)
var force_mobile := false
var quality := ""
var no_vsync := false
var run_seconds := 4.0
var shots_enabled := true
var hide_fog := false
var tutorial := false

var game: Node = null
var shots: Array[String] = []


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
			run_seconds = maxf(2.0, float(arg.trim_prefix("--seconds=")))
		elif arg == "--no-shots":
			shots_enabled = false
		elif arg == "--no-fog":
			hide_fog = true
		elif arg == "--tutorial":
			tutorial = true

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
	process_priority = 1000
	for _i in 3:
		await get_tree().process_frame
	await _run()


func _run() -> void:
	if tutorial:
		get_tree().set_meta("tutorial_mode", true)
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		print("FOG_PROBE_FAIL load")
		get_tree().quit(2)
		return
	game = packed.instantiate()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if game.get("hud") != null and String(game.get("state")) == "select":
			break
	for _i in 10:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	deadline = Time.get_ticks_msec() + 60000
	while String(game.get("state")) != "live" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var live_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - live_at < int(run_seconds * 1000.0):
		await get_tree().process_frame

	_report_fog()
	_report_names()
	_report_respawn()
	if hide_fog:
		# A/B control: keep the node but stop game.gd from updating it, so the
		# same camera angles can be captured without the fog.
		var fog := _fog_node() as MeshInstance3D
		if fog != null:
			fog.visible = false
		game.set("fog_of_war_plane", null)
	if shots_enabled and not tutorial:
		await _shoot_sequence()
	print("FOG_PROBE_SHOTS=", JSON.stringify(shots))
	print("FOG_PROBE_DONE")
	get_tree().quit(0)


func _fog_node() -> Node:
	var arena := game.get_node_or_null("Arena")
	if arena == null:
		return null
	return arena.get_node_or_null("FogOfWar")


func _report_fog() -> void:
	var fog := _fog_node()
	var material: ShaderMaterial = null
	var report := {
		"tag": tag,
		"mobile": DeviceProfile.mobile_ui,
		"quality": DeviceProfile.effective_quality(),
		"renderer": String(RenderingServer.call("get_current_rendering_method")) if RenderingServer.has_method("get_current_rendering_method") else "",
		"exists": fog != null,
	}
	if fog != null:
		report["visible"] = (fog as MeshInstance3D).visible
		report["height"] = snappedf((fog as Node3D).global_position.y, 0.01)
		report["cast_shadow"] = int((fog as GeometryInstance3D).cast_shadow)
		material = (fog as MeshInstance3D).material_override as ShaderMaterial
	if material != null:
		report["hole_radius"] = snappedf(float(material.get_shader_parameter("view_radius")), 0.01)
		report["edge_softness"] = snappedf(float(material.get_shader_parameter("edge_softness")), 0.01)
		report["opacity"] = snappedf(float(material.get_shader_parameter("fog_opacity")), 0.01)
		report["vision_count"] = int(material.get_shader_parameter("vision_count"))
		var player_pos: Vector3 = (material.get_shader_parameter("player_position") as Vector3)
		report["player_orb"] = [snappedf(player_pos.x, 0.1), snappedf(player_pos.z, 0.1)]
	var player = game.get("player")
	if player != null and is_instance_valid(player):
		report["player"] = [snappedf(player.global_position.x, 0.1), snappedf(player.global_position.z, 0.1)]
		report["dead"] = bool(player.dead)
	print("FOG_PROBE_FOG=", JSON.stringify(report))


func _report_names() -> void:
	var names: Array[String] = []
	for hero in game.get("heroes"):
		if hero == null or not is_instance_valid(hero):
			continue
		names.append("%s%s" % ["P:" if bool(hero.is_player) else "", String(hero.display_name)])
	print("FOG_PROBE_NAMES=", JSON.stringify(names))


func _report_respawn() -> void:
	var rows: Array = []
	var player = game.get("player")
	if player != null and is_instance_valid(player):
		for gold in [0, 1000, 1500, 2000, 5000]:
			game.set("gold_earned_this_match", gold)
			rows.append({"who": "player", "gold": gold, "delay": snappedf(float(game.call("respawn_delay_for", player)), 0.01)})
		game.set("gold_earned_this_match", 0)
	for hero in game.get("heroes"):
		if hero == null or not is_instance_valid(hero) or bool(hero.is_player):
			continue
		var before := int(hero.bot_gold)
		var spent := int(hero.match_gold_spent)
		hero.set("bot_gold", 1500)
		hero.set("match_gold_spent", 500)
		rows.append({
			"who": "bot:%s" % String(hero.display_name),
			"gold": 2000,
			"delay": snappedf(float(game.call("respawn_delay_for", hero)), 0.01),
		})
		hero.set("bot_gold", before)
		hero.set("match_gold_spent", spent)
		break
	print("FOG_PROBE_RESPAWN=", JSON.stringify(rows))


func _shoot_sequence() -> void:
	var player = game.get("player")
	if player == null or not is_instance_valid(player):
		return
	# 1. Natural view from the spawn/base, fog untouched.
	await _shot("spawn")

	# 2. Arena centre, camera settled: the fog band must sit at the vision edge.
	var spot := Vector3(0.0, 0.76, 0.0)
	(player as Node3D).global_position = spot
	(player as Node3D).velocity = Vector3.ZERO
	await _wait(0.9)
	await _shot("center")

	var enemy = _pick_enemy(player)
	if enemy == null:
		return
	enemy.set("spawn_protection", 0.0)
	player.set("spawn_protection", 0.0)
	# 3. An enemy at the vision border (10 units in front of the camera). The
	# shot is taken within one frame: bots chase the player and would close the
	# gap before the screenshot.
	(enemy as Node3D).global_position = spot + Vector3(0.0, 0.0, -9.6)
	(enemy as Node3D).velocity = Vector3.ZERO
	(enemy as Node3D).rotation.y = PI
	print("FOG_PROBE_EDGE_DISTANCE=", snappedf((enemy as Node3D).global_position.distance_to((player as Node3D).global_position), 0.01))
	await get_tree().process_frame
	await _shot("fog_edge")

	# 4. Melee clash: gold outgoing number above the enemy, red incoming on us.
	(enemy as Node3D).global_position = spot + Vector3(0.0, 0.0, 2.4)
	player.set("attack_cd", 0.0)
	player.call("_face", (enemy as Node3D).global_position - (player as Node3D).global_position, 1.0)
	await _wait(0.2)
	enemy.call("take_damage", 120.0, player)
	await _wait(0.05)
	await _shot("clash_out")
	player.call("take_damage", 80.0, enemy)
	await _wait(0.05)
	await _shot("clash_in")


func _pick_enemy(player: Node) -> Node:
	for hero in game.get("heroes"):
		if hero == null or not is_instance_valid(hero) or bool(hero.dead):
			continue
		if int(hero.team) != int(player.team):
			return hero
	return null


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _shot(suffix: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return
	var path := "%s/fog_%s_%s.png" % [OUT_DIR, tag, suffix]
	image.save_png(path)
	shots.append(ProjectSettings.globalize_path(path))
