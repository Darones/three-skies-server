extends Node3D

## Screen-space nickname probe (read-only QA tool).
##
## Verifies that every nickname above a hero or a remote player is now a 2D
## Label in scripts/world_name_layer.gd, not a Label3D:
##   * label is a Label parented to the shared CanvasLayer (index 0, below HUD),
##     with the Philosopher font, a real outline and a readable size;
##   * the bot prefix comes from the game name: "БОТ <callsign>";
##   * a human name (local player, RemotePlayer guest) has no prefix;
##   * the label follows Camera3D.unproject_position every frame;
##   * labels are parked off-screen (but stay `visible`) when behind the camera;
##   * bush stealth still hides the 2D name, and the 3D HP bar keeps its green
##     fill for both teams;
##   * low quality (scaling_3d_scale 0.5) does not touch canvas text.
##
## Writes screenshots for the report:
##   godot --path . tools/NameTagProbe.tscn -- --layout=1440x734 --quality=low --tag=desktop
##   godot --path . tools/NameTagProbe.tscn -- --layout=844x390 --mobile --quality=low --tag=mobile
##
## Prints PASS/FAIL, NAME_TAG_CHECKS=... FAILURES=... and exits non-zero on any
## failure. Nothing here changes gameplay, damage or balance.

const MAIN_SCENE := "res://scenes/Main.tscn"
const OUT_DIR := "res://docs/qa-name-layer"
const REMOTE_SCRIPT: Script = preload("res://scripts/remote_player.gd")

var failures := 0
var checks := 0
var game: Node = null
var player: HeroUnit = null
var layer: CanvasLayer = null
var target_size := Vector2i(1440, 734)
var force_mobile := false
var quality := "low"
var tag := "desktop"
var shots := true
var guests: Array = []


func _ready() -> void:
	_parse_args()
	if force_mobile or target_size.x < 500:
		DeviceProfile.mobile_ui = true
		DeviceProfile.touch_controls = true
		get_tree().root.content_scale_size = Vector2i(960, 540)
	else:
		DeviceProfile.mobile_ui = false
		get_tree().root.content_scale_size = target_size
	if DeviceProfile.QUALITY_VALUES.has(quality):
		DeviceProfile.graphics_quality = quality
		DeviceProfile.quality_override = ""
	DeviceProfile.apply_graphics_quality()
	DisplayServer.window_set_size(target_size)

	MetaProgression.player_nickname = "Странник"
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		print("FAIL: Main.tscn did not load")
		get_tree().quit(1)
		return
	game = packed.instantiate()
	add_child(game)
	for _i in 14:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	var deadline := Time.get_ticks_msec() + 30000
	while String(game.get("state")) != "live" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	for _i in 6:
		await get_tree().process_frame
	player = game.get("player") as HeroUnit
	if player == null:
		print("FAIL: no local player")
		get_tree().quit(1)
		return

	layer = _find_layer()
	_check(layer != null, "shared WorldNameLayer exists")
	if layer != null:
		_check(layer.layer == 0, "name layer index 0 (below HUD CanvasLayer 1)")

	var guest_nodes := _spawn_guests()
	guests = guest_nodes
	_arrange_lineup(guests)
	for _i in 4:
		await get_tree().process_frame

	_checks_hero_labels()
	_checks_remote_labels(guests)
	_checks_hp_bar_color()
	_checks_projection()
	_checks_low_quality()
	await _checks_offscreen()
	await _checks_bush()

	print("NAME_TAG_CHECKS=%d FAILURES=%d" % [checks, failures])
	if shots:
		await _save_shot()
	get_tree().quit(1 if failures > 0 else 0)


func _parse_args() -> void:
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
		elif arg == "--no-shot":
			shots = false


func _find_layer() -> CanvasLayer:
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	var found := scene.find_child("WorldNameLayer", true, false)
	return found as CanvasLayer


func _spawn_guests() -> Array:
	var guests: Array = []
	# Human guests come from the network; the probe fakes the same node the
	# server would create, with a human nickname (no bot prefix).
	var specs := [
		{"id": 9101, "name": "Светлана", "team": player.team, "pos": Vector3(-2.6, 0.76, 24.4), "bot": false},
		{"id": 9102, "name": "Даромир", "team": 1 - player.team, "pos": Vector3(3.6, 0.76, 21.6), "bot": false},
	]
	for spec in specs:
		var remote = REMOTE_SCRIPT.new()
		remote.name = "NameProbeGuest_%d" % int(spec["id"])
		game.add_child(remote)
		remote.game = game
		remote.setup(int(spec["id"]), {
			"name": String(spec["name"]),
			"class": HeroUnit.Cls.MAGE,
			"team": int(spec["team"]),
			"bot": bool(spec["bot"]),
			"has_state": true,
			"position": spec["pos"],
			"rotation": 0.0,
			"hp": 780.0,
			"max_hp": 1000.0,
		})
		game.remote_players[int(spec["id"])] = remote
		guests.append(remote)
	return guests


func _arrange_lineup(guests: Array) -> void:
	# Freeze the bots and lay them out in front of the player so the screenshot
	# shows a real fight with several names at once. No AI, damage or balance
	# code is touched: this is the same set_physics_process(false) trick as
	# BushStealthProbe.
	var side := 1.0 if player.team == 0 else -1.0
	# Offsets are relative to the local player and mirrored for team 1.
	# A 2:1 phone window has little vertical room and a taller top HUD bar, so
	# the mobile lineup also stands to the sides and in the foreground: names
	# then spread over the free middle of the frame instead of the top edge.
	var offsets: Array = []
	var guest_spots: Array = []
	if DeviceProfile.mobile_ui:
		offsets = [
			Vector3(-4.6, 0.0, 0.4),
			Vector3(5.0, 0.0, 0.6),
			Vector3(-2.6, 0.0, -3.4),
			Vector3(1.4, 0.0, -4.4),
			Vector3(0.6, 0.0, 3.4),
		]
		guest_spots = [
			Vector3(-4.0, 0.0, 3.2),
			Vector3(4.6, 0.0, -1.6),
		]
	else:
		offsets = [
			Vector3(-4.0, 0.0, -4.4),
			Vector3(-1.2, 0.0, -6.6),
			Vector3(1.6, 0.0, -4.2),
			Vector3(4.2, 0.0, -6.4),
			Vector3(2.6, 0.0, -8.6),
		]
		guest_spots = [
			Vector3(-6.4, 0.0, -4.0),
			Vector3(6.4, 0.0, -4.6),
		]
	var base := player.global_position
	var index := 0
	for hero in game.get("heroes"):
		if hero == null or not is_instance_valid(hero) or hero is not HeroUnit:
			continue
		var unit := hero as HeroUnit
		if unit == player:
			continue
		unit.set_physics_process(false)
		unit.velocity = Vector3.ZERO
		unit.bush_zones.clear()
		unit.in_bush = false
		if index < offsets.size():
			var offset: Vector3 = offsets[index]
			_park_hero(unit, base + Vector3(offset.x, 0.0, offset.z * side))
			unit.health = unit.max_health * [0.85, 0.55, 0.28, 0.7, 0.95][index]
			unit._update_health_display()
			unit._update_name_visibility()
			index += 1
	if not guests.is_empty():
		var ally_spot: Vector3 = guest_spots[0]
		_park_remote(guests[0], base + Vector3(ally_spot.x, 0.0, ally_spot.z * side))
	if guests.size() > 1:
		var enemy_spot: Vector3 = guest_spots[1]
		_park_remote(guests[1], base + Vector3(enemy_spot.x, 0.0, enemy_spot.z * side))


## Teleports a hero whose physics is off. The 3D status root is top_level and is
## normally moved in _physics_process, so a frozen hero needs it placed by hand;
## the 2D nickname follows global_position and needs no help.
func _park_hero(unit: HeroUnit, position: Vector3) -> void:
	unit.global_position = position
	unit.velocity = Vector3.ZERO
	if unit.status_root != null and is_instance_valid(unit.status_root):
		unit.status_root.global_position = position


func _park_remote(remote, position: Vector3) -> void:
	remote.global_position = position
	remote.target_position = position


func _checks_hero_labels() -> void:
	var heroes: Array = game.get("heroes")
	_check(heroes.size() >= 5, "match spawned heroes (%d)" % heroes.size())
	var bots := 0
	var label3d_names := 0
	for node in game.find_children("*", "Label3D", true, false):
		if String(node.name).contains("NameLabel"):
			label3d_names += 1
	_check(label3d_names == 0, "no Label3D is used for a nickname")
	for hero in heroes:
		if hero == null or not is_instance_valid(hero) or hero is not HeroUnit:
			continue
		var unit := hero as HeroUnit
		var label := unit.name_label
		_check(label is Label, "%s nickname is a 2D Label" % unit.display_name)
		if label is not Label:
			continue
		_check(layer != null and (label.get_parent() == layer or layer.is_ancestor_of(label)),
			"%s nickname lives in the shared canvas layer" % unit.display_name)
		var font := label.get_theme_font("font")
		_check(font != null and String(font.resource_path).ends_with("Philosopher-Bold.ttf"),
			"%s nickname uses Philosopher" % unit.display_name)
		_check(label.get_theme_constant("outline_size") >= 3,
			"%s nickname has an outline (%d)" % [unit.display_name, label.get_theme_constant("outline_size")])
		_check(label.get_theme_font_size("font_size") >= 16,
			"%s nickname font size >= 16 (%d)" % [unit.display_name, label.get_theme_font_size("font_size")])
		if unit == player:
			_check(not label.text.begins_with("БОТ"), "local player name has no bot prefix (%s)" % label.text)
			_check(label.text == player.display_name, "local player name shows the nickname")
			_check(label.visible, "local player nickname is visible")
		else:
			bots += 1
			_check(label.text == _expected_bot_text(unit.display_name),
				"bot nickname is 'БОТ <name>' (%s)" % label.text)
	_check(bots >= 4, "bot nicknames checked (%d)" % bots)
	# Team is told apart by the text colour, not by a second 3D label.
	var ally := _ally_bot()
	var enemy := _enemy_bot()
	if ally != null:
		_check(ally.name_label.get_theme_color("font_color") == HeroUnit.NAME_COLOR_ALLY,
			"ally nickname is green")
	if enemy != null:
		_check(enemy.name_label.get_theme_color("font_color") == HeroUnit.NAME_COLOR_ENEMY,
			"enemy nickname is red")
	_check(player.name_label.get_theme_color("font_color") == HeroUnit.NAME_COLOR_SELF,
		"local player nickname has its own colour")


func _expected_bot_text(unit_name: String) -> String:
	var upper := unit_name.to_upper()
	if upper.begins_with("БОТ") or upper.begins_with("BOT"):
		return unit_name
	return "БОТ %s" % unit_name


func _checks_remote_labels(guests: Array) -> void:
	for remote in guests:
		var label: Label = remote.get("_name_label")
		_check(label is Label, "remote %s nickname is a 2D Label" % remote.display_name)
		if label == null:
			continue
		_check(layer != null and layer.is_ancestor_of(label),
			"remote %s nickname lives in the shared canvas layer" % remote.display_name)
		_check(label.text == remote.display_name,
			"human guest name has no bot prefix (%s)" % label.text)


func _checks_hp_bar_color() -> void:
	for hero in game.get("heroes"):
		if hero == null or not is_instance_valid(hero) or hero is not HeroUnit:
			continue
		var unit := hero as HeroUnit
		unit._update_name_color()
		var bar := unit.health_back
		var color := _fill_color(bar)
		_check(color.g > 0.6 and color.r < 0.5,
			"%s 3D HP fill is green (%s)" % [unit.display_name, color])
	for remote in game.remote_players.values():
		if remote == null or not is_instance_valid(remote):
			continue
		var color := _fill_color(remote.get("_health_back"))
		_check(color.g > 0.6 and color.r < 0.5,
			"remote %s 3D HP fill is green (%s)" % [remote.display_name, color])


func _fill_color(bar) -> Color:
	if bar == null or not is_instance_valid(bar):
		return Color.BLACK
	var material := bar.material_override as ShaderMaterial
	if material == null:
		return Color.BLACK
	return material.get_shader_parameter("fill_color")


func _checks_projection() -> void:
	var camera: Camera3D = game.get("camera")
	_check(camera != null and is_instance_valid(camera), "game camera exists")
	if camera == null:
		return
	var hero := player
	var label := hero.name_label
	var expected := camera.unproject_position(hero.global_position + Vector3(0.0, HeroUnit.NAME_TAG_HEIGHT, 0.0))
	var actual := label.position + Vector2(label.size.x * 0.5, label.size.y)
	var error := expected.distance_to(actual)
	_check(error <= 1.5, "nickname is projected onto the head (error %.2f px)" % error)
	_check(label.position.y + label.size.y * 0.5 < expected.y,
		"nickname text sits above the head point")
	# Fighting heroes too, not just the player.
	for other in game.get("heroes"):
		if other == null or not is_instance_valid(other) or other is not HeroUnit or other == hero:
			continue
		if not other.name_label.visible:
			continue
		var other_expected: Vector2 = camera.unproject_position(
			other.global_position + Vector3(0.0, HeroUnit.NAME_TAG_HEIGHT, 0.0))
		var other_actual: Vector2 = other.name_label.position + Vector2(
			other.name_label.size.x * 0.5, other.name_label.size.y)
		_check(other_expected.distance_to(other_actual) <= 1.5,
			"%s nickname follows in screen space" % other.display_name)
		break


func _checks_low_quality() -> void:
	var render_scale := get_tree().root.scaling_3d_scale
	if quality == "low":
		_check(is_equal_approx(render_scale, 0.5), "3D render scale is 0.5 at q=low (%.2f)" % render_scale)
	else:
		_check(render_scale > 0.49, "3D render scale is %.2f at q=%s" % [render_scale, quality])
	# Canvas text ignores scaling_3d_scale: the label keeps its font size and
	# stays a canvas item, so it is not resampled from a 0.5-scale 3D buffer.
	_check(player.name_label.get_canvas_layer_node() != null, "nickname is drawn by the canvas pipeline")
	_check(player.name_label.get_theme_font_size("font_size") >= 16,
		"nickname font size survives q=%s" % quality)


func _checks_offscreen() -> void:
	var camera: Camera3D = game.get("camera")
	if camera == null:
		return
	var ally := _ally_bot()
	if ally == null:
		_check(false, "ally bot exists for the off-screen check")
		return
	# The camera follows the local player, so park a bot behind it instead.
	# An ally's name never depends on distance: after parking it must still be
	# `visible`, only its screen position moves out of the viewport.
	ally.set_physics_process(false)
	ally.bush_zones.clear()
	ally.in_bush = false
	ally.bush_reveal_timer = 0.0
	var label := ally.name_label
	var was_visible := label.visible
	_park_hero(ally, camera.global_position + camera.global_transform.basis.z * 30.0)
	for _i in 4:
		await get_tree().process_frame
	_check(label.position.x < -1000.0, "nickname is parked off-screen behind the camera")
	# Parking only moves the label: whatever bush/stealth visibility it had
	# before must stay as it is.
	_check(label.visible == was_visible, "off-screen parking does not change visible")


func _checks_bush() -> void:
	var zone := _bush_zone(0)
	var enemy := _enemy_bot()
	if zone == null or enemy == null:
		_check(false, "bush zone and enemy bot exist for the stealth check")
		return
	enemy.bush_reveal_timer = 0.0
	_park_hero(enemy, zone.global_position + Vector3(0.0, 0.76, 0.0))
	player.global_position = zone.global_position + Vector3(6.5, 0.76, 0.0)
	for _i in 4:
		await get_tree().physics_frame
		await get_tree().process_frame
	enemy._update_name_visibility()
	_check(enemy.in_bush, "enemy bot is tracked inside the bush")
	_check(not enemy.name_label.visible, "2D enemy nickname is hidden in the bush")
	player.global_position = enemy.global_position + Vector3(1.9, 0.0, 0.0)
	enemy._update_name_visibility()
	_check(enemy.name_label.visible, "2D enemy nickname appears at 1.9 m")


func _bush_zone(index: int) -> Area3D:
	var bushes := game.get_node_or_null("Arena/Bushes")
	if bushes == null:
		return null
	var zones: Array[Area3D] = []
	for child in bushes.get_children():
		if child is Area3D and String(child.name).begins_with("BushZone_"):
			zones.append(child as Area3D)
	if index < 0 or index >= zones.size():
		return null
	return zones[index]


func _enemy_bot() -> HeroUnit:
	for hero in game.get("heroes"):
		if hero is HeroUnit and not hero.is_player and int(hero.team) != int(player.team) and not hero.dead:
			return hero as HeroUnit
	return null


func _ally_bot() -> HeroUnit:
	for hero in game.get("heroes"):
		if hero is HeroUnit and not hero.is_player and int(hero.team) == int(player.team) and not hero.dead:
			return hero as HeroUnit
	return null


func _save_shot() -> void:
	# Staging for the report: the camera follows the local player, so move the
	# player to the middle of the arena and put the lineup in front of it, then
	# let the camera lerp settle before the frame is captured.
	player.global_position = Vector3(0.0, player.global_position.y, 10.0)
	player.velocity = Vector3.ZERO
	player._update_name_visibility()
	_arrange_lineup(guests)
	for _i in 60:
		await get_tree().process_frame
	for remote in guests:
		var tag_label: Label = remote.get("_name_label")
		if tag_label != null and is_instance_valid(tag_label):
			print("[NameTagProbe] guest %s pos=%s visible=%s in_bush=%s hidden=%s visual_hidden=%s dead=%s zones=%d text=%s" % [
				remote.display_name, tag_label.position, str(tag_label.visible),
				str(remote.get("in_bush")), str(remote.get("bush_hidden")),
				str(remote.get("_bush_visual_hidden")), str(remote.get("dead")),
				(remote.get("bush_zones") as Array).size(), tag_label.text])
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := "%s/name_tags_%s_%s_%dx%d.png" % [
		OUT_DIR, tag, quality, target_size.x, target_size.y
	]
	var error := image.save_png(path)
	print("[NameTagProbe] screenshot %s error=%d size=%s" % [path, error, image.get_size()])


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
