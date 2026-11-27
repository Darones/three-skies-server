extends Node3D

## Screen-space nickname probe (read-only QA tool).
##
## Verifies that every nickname above a hero or a remote player is a 2D
## Label in scripts/world_name_layer.gd, not a Label3D, and that the HP bar is
## now a child of that label:
##   * label is a Label parented to the shared CanvasLayer (index 0, below HUD),
##     with the Philosopher font, a real outline and a readable size;
##   * the bot prefix comes from the game name: "БОТ <callsign>";
##   * a human name (local player, RemotePlayer guest) has no prefix;
##   * the HP bar is one Control inside the nickname, fixed 96x7, centred with a
##     fixed 2 px gap under the text, and drawn exactly while the name is drawn;
##   * self and allies get a green bar, enemies a red one (heroes and remotes);
##   * the 3D compatibility quad stays hidden for good;
##   * the label follows Camera3D.unproject_position every frame, reading the
##     interpolated render pose (no jitter while running, error <= 1 px);
##   * labels are parked off-screen (but stay `visible`) when behind the camera;
##   * bush stealth still hides the 2D name together with its bar;
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
	_checks_hp_bars(guests)
	_checks_projection()
	_checks_low_quality()
	await _checks_motion(guests)
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
	unit.reset_physics_interpolation()
	if unit.status_root != null and is_instance_valid(unit.status_root):
		unit.status_root.global_position = position


func _park_remote(remote, position: Vector3) -> void:
	remote.global_position = position
	remote.target_position = position
	remote.reset_physics_interpolation()


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


## The visible HP bar moved from the 3D quad above the head into the nickname
## block: colour comes from the team (same source as the nickname), and the bar
## is drawn exactly while the name is drawn.
func _checks_hp_bars(guests: Array) -> void:
	for hero in game.get("heroes"):
		if hero == null or not is_instance_valid(hero) or hero is not HeroUnit:
			continue
		var unit := hero as HeroUnit
		var expected := HeroUnit.NAME_COLOR_SELF
		if not unit.is_player:
			expected = HeroUnit.NAME_COLOR_ALLY if int(unit.team) == int(player.team) else HeroUnit.NAME_COLOR_ENEMY
		var label_visible := unit.name_label != null and is_instance_valid(unit.name_label) \
			and unit.name_label.visible
		_check_name_bar(
			unit.name_label, unit.display_name, expected,
			label_visible and not unit.dead, unit.dead)
		_check(not _mesh_bar_visible(unit.health_back),
			"%s 3D compatibility bar stays hidden" % unit.display_name)
	for remote in guests:
		var is_ally := int(remote.team) == int(player.team)
		var color := HeroUnit.NAME_COLOR_ALLY if is_ally else HeroUnit.NAME_COLOR_ENEMY
		_check_name_bar(
			remote.get("_name_label"), "remote %s" % remote.display_name, color,
			not remote.dead and not bool(remote.get("_bush_visual_hidden")),
			bool(remote.dead))
		_check(not _mesh_bar_visible(remote.get("_health_back")),
			"remote %s 3D compatibility bar stays hidden" % remote.display_name)


func _check_name_bar(tag_label: Control, who: String, expected_color: Color,
		visible_expected: bool, dead: bool) -> void:
	if tag_label == null or not is_instance_valid(tag_label):
		_check(false, "%s has a nickname label for its HP bar" % who)
		return
	var back := tag_label.get("bar_back") as ColorRect
	var fill := tag_label.get("bar_fill") as ColorRect
	_check(back != null and fill != null, "%s has a 2D HP bar inside the nickname" % who)
	if back == null or fill == null:
		return
	_check(back.get_parent() == tag_label, "%s HP bar is a child of the nickname label" % who)
	_check(absf(back.size.x - 96.0) <= 0.6 and absf(back.size.y - 7.0) <= 0.6,
		"%s HP bar keeps the fixed 96x7 size (%s)" % [who, back.size])
	# Both numbers below are the NameTag constants: a fixed pixel gap under the
	# text box and a horizontal centre, independent of the nickname width.
	var gap := back.position.y - tag_label.size.y
	_check(absf(gap - 2.0) <= 0.6,
		"%s HP bar keeps the fixed 2 px gap under the text (%.2f px)" % [who, gap])
	var centre_error := absf((back.position.x + back.size.x * 0.5) - tag_label.size.x * 0.5)
	_check(centre_error <= 0.6,
		"%s HP bar is centred under the text (%.2f px off)" % [who, centre_error])
	_check(fill.color == expected_color,
		"%s HP bar colour matches the nickname source (%s)" % [who, fill.color])
	if expected_color == HeroUnit.NAME_COLOR_ENEMY:
		_check(_is_red(fill.color), "%s HP bar is red for an enemy" % who)
	else:
		_check(_is_green(fill.color), "%s HP bar is green for self/ally" % who)
	_check(back.visible == visible_expected,
		"%s HP bar visibility matches the health state (%s)" % [who, str(visible_expected)])
	# The bar is a child of the label: hidden parent, hidden bar, always.
	_check(back.is_visible_in_tree() == (tag_label.is_visible_in_tree() and back.visible and not dead),
		"%s HP bar is drawn exactly while the nickname is drawn" % who)


func _is_green(color: Color) -> bool:
	# NAME_COLOR_SELF / ALLY are pale greens (red channel is high too), so the
	# test is "green dominates", not "red is low".
	return color.g > 0.6 and color.g > color.r


func _is_red(color: Color) -> bool:
	return color.r > 0.6 and color.g < 0.5


func _mesh_bar_visible(bar) -> bool:
	if bar == null or not is_instance_valid(bar):
		return false
	return bool(bar.get("visible"))


func _checks_projection() -> void:
	var camera: Camera3D = game.get("camera")
	_check(camera != null and is_instance_valid(camera), "game camera exists")
	if camera == null:
		return
	var hero := player
	var label := hero.name_label
	var expected := camera.unproject_position(
		hero.get_global_transform_interpolated().origin + Vector3(0.0, HeroUnit.NAME_TAG_HEIGHT, 0.0))
	var actual := label.position + Vector2(label.size.x * 0.5, label.size.y)
	var error := expected.distance_to(actual)
	_check(error <= 1.5, "nickname is projected onto the head (error %.2f px)" % error)
	_check(label.position.y + label.size.y * 0.5 < expected.y,
		"nickname text sits above the head point")
	# Fighting heroes too, not just the player.
	for other in game.get("heroes"):
		if other == null or not is_instance_valid(other) or other is not HeroUnit or other == hero:
			continue
		if not other.name_label.visible or other.name_label.position.x < -1000.0:
			continue
		var other_expected: Vector2 = camera.unproject_position(
			other.get_global_transform_interpolated().origin
				+ Vector3(0.0, HeroUnit.NAME_TAG_HEIGHT, 0.0))
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


## The nickname reads the interpolated render pose, so it must sit exactly on the
## moving head and never freeze while the screen point moves. Two passes:
## the local hero (the camera aims at it, so this is the "no jitter" test) and a
## remote guest (visibly crossing the screen, so this is the "keeps moving" test).
func _checks_motion(guests: Array) -> void:
	var camera: Camera3D = game.get("camera")
	if camera == null or not is_instance_valid(camera):
		_check(false, "game camera exists for the shake check")
		return
	if player.name_label == null or not is_instance_valid(player.name_label):
		_check(false, "local nickname exists for the shake check")
		return
	var lateral := camera.global_transform.basis.x
	lateral.y = 0.0
	if lateral.length_squared() < 0.001:
		lateral = Vector3.RIGHT
	lateral = lateral.normalized()

	# Pass 1: the local hero, moved on a flat stretch for 60 frames.
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	player.bush_zones.clear()
	player.in_bush = false
	var start := player.global_position
	player.global_position = Vector3(0.0, start.y, 6.0)
	player.reset_physics_interpolation()
	for _i in 8:
		await get_tree().process_frame
	var hero_error := 0.0
	var hero_frames := 0
	for i in 60:
		await get_tree().physics_frame
		var swing := -1.0 if i % 30 >= 15 else 1.0
		player.global_position += lateral * (0.25 * swing)
		await RenderingServer.frame_post_draw
		if player.name_label.position.x < -1000.0:
			continue
		var expected := _expected_head_point(camera, player)
		if expected == Vector2.INF:
			continue
		var actual := player.name_label.position + Vector2(
			player.name_label.size.x * 0.5, player.name_label.size.y)
		hero_frames += 1
		hero_error = maxf(hero_error, expected.distance_to(actual))
	_check(hero_frames >= 30,
		"running hero nickname was sampled on %d of 60 frames" % hero_frames)
	_check(hero_error <= 1.0,
		"running hero nickname stays within 1 px of the interpolated pose (max %.2f px)" % hero_error)
	player.global_position = start
	player.reset_physics_interpolation()
	player.set_physics_process(true)

	# Pass 2: a remote guest crossing the screen. The camera does not follow it,
	# so the label has to travel, and two identical frames in a row while the
	# expected point moved would be the old physics-tick jitter.
	if guests.is_empty():
		_check(false, "remote guest exists for the moving nickname check")
		return
	var remote = guests[0]
	var remote_label: Label = remote.get("_name_label")
	if remote_label == null or not is_instance_valid(remote_label):
		_check(false, "remote nickname exists for the moving nickname check")
		return
	var remote_start: Vector3 = remote.global_position
	remote.set_process(false)
	remote.bush_hidden = false
	remote.bush_reveal_timer = 0.0
	remote.dead = false
	remote.global_position = remote_start
	remote.reset_physics_interpolation()
	for _i in 4:
		await get_tree().process_frame
	var max_error := 0.0
	var moved_frames := 0
	var consecutive_stuck := 0
	var max_consecutive_stuck := 0
	var prev_expected := Vector2.INF
	var prev_actual := Vector2.INF
	for i in 60:
		await get_tree().physics_frame
		# Two smooth cycles over 60 frames: always moving except at the turns.
		var phase := (float(i) / 60.0) * TAU * 2.0
		remote.global_position = remote_start + lateral * (sin(phase) * 1.6)
		await RenderingServer.frame_post_draw
		if remote_label.position.x < -1000.0:
			continue
		var expected := _expected_head_point(camera, remote)
		if expected == Vector2.INF:
			continue
		var actual := remote_label.position + Vector2(remote_label.size.x * 0.5, remote_label.size.y)
		max_error = maxf(max_error, expected.distance_to(actual))
		if prev_expected != Vector2.INF:
			var wanted := expected.distance_to(prev_expected)
			var happened := remote_label.position.distance_to(prev_actual)
			if wanted > 0.5:
				moved_frames += 1
				# One frozen frame is normal: rounding to whole pixels keeps the
				# label on the same pixel while the sub-pixel point creeps past
				# 0.5 px, and the sine turns around. Only two frames in a row
				# would be the old physics-tick jitter.
				if happened < 0.5:
					consecutive_stuck += 1
					max_consecutive_stuck = maxi(max_consecutive_stuck, consecutive_stuck)
				else:
					consecutive_stuck = 0
		prev_expected = expected
		prev_actual = remote_label.position
	_check(moved_frames >= 10,
		"moving nickname was checked on %d frames with real screen travel" % moved_frames)
	_check(max_consecutive_stuck < 2,
		"moving nickname never freezes for two frames in a row (max %d)" % max_consecutive_stuck)
	_check(max_error <= 1.0,
		"moving nickname stays within 1 px of the interpolated pose (max %.2f px)" % max_error)
	remote.global_position = remote_start
	remote.target_position = remote_start
	remote.reset_physics_interpolation()
	remote.set_process(true)


## Screen point of a hero's nickname anchor for the current rendered frame, or
## Vector2.INF when the point is behind the camera.
func _expected_head_point(camera: Camera3D, node: Node3D) -> Vector2:
	var world: Vector3 = node.get_global_transform_interpolated().origin \
		+ Vector3(0.0, HeroUnit.NAME_TAG_HEIGHT, 0.0)
	if camera.is_position_behind(world):
		return Vector2.INF
	return camera.unproject_position(world)


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
	var label := ally.name_label
	# Baseline in a clean, bush-free, on-screen spot next to the local player:
	# `_arrange_lineup` can leave a bot overlapping a bush Area3D, and such a
	# leftover would hide the name and make "parking changed visible" a lie.
	_park_hero(ally, player.global_position + Vector3(2.5, 0.0, -2.5))
	ally.bush_zones.clear()
	ally.in_bush = false
	ally.bush_reveal_timer = 0.0
	ally._update_name_visibility()
	for _i in 4:
		await get_tree().physics_frame
		await get_tree().process_frame
	ally.bush_zones.clear()
	ally.in_bush = false
	ally._update_name_visibility()
	var was_visible := label.visible
	var bar_was_drawn := _bar_drawn(label)
	_check(was_visible, "ally nickname is visible before the off-screen check")
	# Behind the camera and 8 m above the arena: high enough that no bush Area3D
	# can pick the body up again, so parking changes the screen position only.
	_park_hero(ally, camera.global_position + camera.global_transform.basis.z * 30.0
		+ Vector3(0.0, 8.0, 0.0))
	for _i in 4:
		await get_tree().physics_frame
		await get_tree().process_frame
	ally.bush_zones.clear()
	ally.in_bush = false
	ally._update_name_visibility()
	_check(label.position.x < -1000.0, "nickname is parked off-screen behind the camera")
	# Parking only moves the label: whatever bush/stealth visibility it had
	# before must stay as it is.
	_check(label.visible == was_visible, "off-screen parking does not change visible")
	_check(_bar_drawn(label) == bar_was_drawn, "off-screen parking moves the HP bar with the nickname")


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
	_check(not _bar_drawn(enemy.name_label), "enemy HP bar hides together with the nickname in the bush")
	player.global_position = enemy.global_position + Vector3(1.9, 0.0, 0.0)
	enemy._update_name_visibility()
	_check(enemy.name_label.visible, "2D enemy nickname appears at 1.9 m")
	_check(_bar_drawn(enemy.name_label), "enemy HP bar is drawn with the nickname at 1.9 m")


func _bar_drawn(tag_label) -> bool:
	if tag_label == null or not is_instance_valid(tag_label):
		return false
	var back := tag_label.get("bar_back") as ColorRect
	return back != null and is_instance_valid(back) and back.is_visible_in_tree()


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
	player.reset_physics_interpolation()
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
