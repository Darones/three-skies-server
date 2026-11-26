extends Node3D

## Touch scroll probe.
##
## Proves that scripts/touch_scroll.gd scrolls a real list with a synthetic
## finger drag, scrolls exactly once (no double step from the emulated mouse
## motion), never eats a plain tap, and is actually wired into the lobby
## inventory/profile and the results stats/players lists.
##
## Run: godot_console --path . tools/TouchScrollProbe.tscn -- --layout=844x390 --mobile
##      godot_console --path . tools/TouchScrollProbe.tscn -- --layout=1440x734
##
## Prints TOUCH_SCROLL_FAILURES=<n> and exits non-zero when anything fails.

const TOUCH_SCROLL := preload("res://scripts/touch_scroll.gd")

var failures := 0
var checks := 0
var scroll: ScrollContainer = null
var buttons: Array[Button] = []
var clicks := 0


func _ready() -> void:
	var target := Vector2i(1440, 734)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			var parts := arg.trim_prefix("--layout=").split("x")
			if parts.size() == 2:
				target = Vector2i(int(parts[0]), int(parts[1]))
		elif arg == "--mobile":
			DeviceProfile.mobile_ui = true
			DeviceProfile.touch_controls = true
	if DeviceProfile.mobile_ui:
		get_tree().root.content_scale_size = Vector2i(960, 540)
	else:
		get_tree().root.content_scale_size = target
	DisplayServer.window_set_size(target)
	for i in 3:
		await get_tree().process_frame
	print("TOUCH_SCROLL viewport=", get_viewport().get_visible_rect().size,
		" mobile=", DeviceProfile.mobile_ui)

	await _case_unit_drag()
	await _case_double_input()
	await _case_tap_click()
	await _case_outside_and_hidden()
	_cleanup_unit()

	await _case_lobby_inventory()
	await _case_results_lists()

	print("TOUCH_SCROLL_CHECKS=%d FAILURES=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- unit cases -------------------------------------------------------------

func _build_unit() -> void:
	var holder := Control.new()
	holder.name = "UnitHolder"
	holder.position = Vector2(40, 40)
	holder.size = Vector2(400, 200)
	add_child(holder)
	scroll = TOUCH_SCROLL.new()
	scroll.name = "UnitScroll"
	scroll.position = Vector2.ZERO
	scroll.size = Vector2(400, 200)
	holder.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	scroll.add_child(content)
	for i in 12:
		var button := Button.new()
		button.text = "R%d" % i
		button.custom_minimum_size = Vector2(380, 60)
		button.pressed.connect(_on_button_pressed)
		content.add_child(button)
		buttons.append(button)


func _cleanup_unit() -> void:
	if scroll != null:
		var holder := scroll.get_parent()
		holder.queue_free()
		scroll = null
		buttons.clear()


func _case_unit_drag() -> void:
	_build_unit()
	for i in 4:
		await get_tree().process_frame
	scroll.scroll_vertical = 200
	await get_tree().process_frame
	var start := scroll.scroll_vertical
	var point := _center(scroll)
	_touch(0, point, true)
	var moved := 0.0
	for i in 12:
		moved += 10.0
		_drag(0, point + Vector2(0, moved), Vector2(0, 10))
	_drag_end(0)
	await get_tree().process_frame
	_check(scroll.scroll_vertical == start - 120,
		"finger drag down 120px: %d -> %d (expected %d)" % [start, scroll.scroll_vertical, start - 120])

	var up_start := scroll.scroll_vertical
	var up_point := _center(scroll)
	_touch(1, up_point, true)
	var up_moved := 0.0
	for i in 5:
		up_moved -= 20.0
		_drag(1, up_point + Vector2(0, up_moved), Vector2(0, -20))
	_drag_end(1)
	await get_tree().process_frame
	_check(scroll.scroll_vertical == up_start + 100,
		"finger drag up 100px: %d -> %d (expected %d)" % [up_start, scroll.scroll_vertical, up_start + 100])

	scroll.scroll_vertical = 0
	await get_tree().process_frame
	var top_point := _center(scroll)
	_touch(2, top_point, true)
	var down_moved := 0.0
	for i in 6:
		down_moved += 12.0
		_drag(2, top_point + Vector2(0, down_moved), Vector2(0, 12))
	_drag_end(2)
	await get_tree().process_frame
	_check(scroll.scroll_vertical == 0,
		"drag down at the top clamps at 0 (got %d)" % scroll.scroll_vertical)

	scroll.scroll_vertical = 200
	await get_tree().process_frame
	var tap_point := _center(scroll)
	_touch(3, tap_point, true)
	# A tap that moves less than the threshold must not scroll.
	_drag(3, tap_point + Vector2(0, 2), Vector2(0, 2))
	_drag_end(3)
	await get_tree().process_frame
	_check(scroll.scroll_vertical == 200,
		"sub-threshold wobble does not scroll (got %d)" % scroll.scroll_vertical)


func _case_double_input() -> void:
	# emulate_mouse_from_touch turns every touch drag into a mouse drag as
	# well. The touch path consumes the drag, and the mouse path ignores it
	# while the setting is on, so the list must move exactly once.
	scroll.scroll_vertical = 200
	await get_tree().process_frame
	var point := _center(scroll)
	_touch(0, point, true)
	var moved := 0.0
	for i in 8:
		moved += 15.0
		var position := point + Vector2(0, moved)
		_drag(0, position, Vector2(0, 15))
		# The mouse motion the same finger produces.
		_mouse_motion(position, Vector2(0, 15), MOUSE_BUTTON_MASK_LEFT)
	_drag_end(0)
	await get_tree().process_frame
	_check(scroll.scroll_vertical == 200 - 120,
		"touch + emulated mouse motion scrolls once: expected %d got %d" % [
			200 - 120, scroll.scroll_vertical])


func _case_tap_click() -> void:
	clicks = 0
	scroll.scroll_vertical = 0
	await get_tree().process_frame
	var target := buttons[0]
	var point := target.get_global_rect().get_center()
	_tap(point)
	await get_tree().process_frame
	_check(clicks == 1, "plain tap still presses the button (clicks=%d)" % clicks)
	_check(scroll.scroll_vertical == 0, "tap does not scroll (got %d)" % scroll.scroll_vertical)

	clicks = 0
	_mouse_button(point, true)
	_mouse_button(point, false)
	await get_tree().process_frame
	_check(clicks == 1, "plain mouse click still presses the button (clicks=%d)" % clicks)

	# A scroll that starts on a card must not also press that card: the
	# finger only wanted to move the list.
	clicks = 0
	scroll.scroll_vertical = 0
	await get_tree().process_frame
	var card_point := buttons[2].get_global_rect().get_center()
	_touch(0, card_point, true)
	_mouse_button(card_point, true)
	var drag := 0.0
	for i in 6:
		drag -= 14.0
		_drag(0, card_point + Vector2(0, drag), Vector2(0, -14))
	_touch(0, card_point + Vector2(0, drag), false)
	_mouse_button(card_point + Vector2(0, drag), false)
	await get_tree().process_frame
	_check(clicks == 0, "drag that scrolled does not press the card (clicks=%d)" % clicks)

	clicks = 0
	var again := _visible_button_center()
	_tap(again)
	await get_tree().process_frame
	_check(clicks == 1, "tap after a scroll still presses a card (clicks=%d)" % clicks)


func _case_outside_and_hidden() -> void:
	scroll.scroll_vertical = 200
	await get_tree().process_frame
	var outside := scroll.get_global_rect().position + Vector2(-60, 60)
	_touch(0, outside, true)
	for i in 6:
		_drag(0, outside + Vector2(0, i * 12.0 + 12.0), Vector2(0, 12))
	_drag_end(0)
	await get_tree().process_frame
	_check(scroll.scroll_vertical == 200,
		"drag outside the rect does nothing (got %d)" % scroll.scroll_vertical)

	scroll.visible = false
	await get_tree().process_frame
	var point := _center(scroll)
	_touch(1, point, true)
	for i in 6:
		_drag(1, point + Vector2(0, i * 12.0 + 12.0), Vector2(0, 12))
	_drag_end(1)
	await get_tree().process_frame
	_check(scroll.scroll_vertical == 200,
		"hidden list ignores drags (got %d)" % scroll.scroll_vertical)
	scroll.visible = true

	# A modal on top (nickname popup, dim layer) owns the touch; the list
	# behind it must stay where it is.
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	scroll.scroll_vertical = 200
	await get_tree().process_frame
	var covered := _center(scroll)
	_mouse_motion(covered, Vector2.ZERO, 0)
	await get_tree().process_frame
	_touch(2, covered, true)
	for i in 6:
		_drag(2, covered + Vector2(0, i * 12.0 + 12.0), Vector2(0, 12))
	_drag_end(2)
	await get_tree().process_frame
	_check(scroll.scroll_vertical == 200,
		"drag under a modal does not scroll (got %d)" % scroll.scroll_vertical)
	dim.queue_free()
	await get_tree().process_frame


# --- real screens -----------------------------------------------------------

func _case_lobby_inventory() -> void:
	_seed_player()
	MetaProgression.profile_loaded = true
	var lobby := (load("res://scenes/Lobby.tscn") as PackedScene).instantiate() as Control
	add_child(lobby)
	for i in 20:
		await get_tree().process_frame
	lobby.call("_open_player_menu")
	for i in 10:
		await get_tree().process_frame
	var menu := lobby.get("player_menu_panel") as Control
	var inventory := menu.find_child("InventoryScroll", true, false) as ScrollContainer
	_check(inventory != null, "inventory scroll exists")
	if inventory != null:
		_check(inventory.has_method("is_drag_scrolling"),
			"inventory scroll is a TouchScroll (%s)" % inventory.get_script().resource_path)
		await _drag_list(inventory, "inventory")
	var profile_panel := menu.find_child("PlayerMenuProfile", true, false) as Control
	var profile := _find_touch_scroll(profile_panel)
	_check(profile != null, "profile scroll is a TouchScroll")
	if profile != null:
		# The profile column can be short on desktop, so only require that the
		# drag path runs and leaves a clamped, sane value.
		await _drag_list(profile, "profile", false)
	lobby.call("_close_player_menu")
	lobby.queue_free()
	for i in 4:
		await get_tree().process_frame


func _case_results_lists() -> void:
	get_tree().set_meta("last_match_won", true)
	get_tree().set_meta("last_match_score", [3, 1])
	get_tree().set_meta("last_match_team", 0)
	get_tree().set_meta("last_match_place", 1)
	get_tree().set_meta("last_match_is_mvp", true)
	get_tree().set_meta("selected_class", HeroUnit.Cls.FAIRY)
	get_tree().set_meta("last_match_stats", {
		"p_kills": 4, "p_deaths": 2, "p_damage": 3200, "p_crystals": 3,
		"p_shells_destroyed": 1, "p_coins_collected": 42, "p_gold_earned": 1850,
	})
	var players: Array = []
	for i in 9:
		players.append({
			"name": "Игрок %d" % (i + 1), "team": i % 2, "kills": 9 - i,
			"deaths": i, "damage": 3000 - i * 200, "crystals": i % 3,
			"is_player": i == 0,
		})
	get_tree().set_meta("last_match_players", players)
	var screen := (load("res://scenes/ResultsScreen.tscn") as PackedScene).instantiate()
	add_child(screen)
	for i in 20:
		await get_tree().process_frame
	var stats := screen.get("stats_scroll") as ScrollContainer
	_check(stats != null and stats.has_method("is_drag_scrolling"),
		"results stats scroll is a TouchScroll")
	if stats != null:
		await _drag_list(stats, "results stats", false)
	screen.call("_switch_result_tab", true)
	for i in 6:
		await get_tree().process_frame
	var table := screen.get("players_scroll") as ScrollContainer
	_check(table != null and table.has_method("is_drag_scrolling"),
		"results players scroll is a TouchScroll")
	if table != null:
		await _drag_list(table, "results players")
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	get_viewport().get_texture().get_image().save_png("user://ui_shots/touch_scroll_results.png")
	screen.queue_free()
	for i in 4:
		await get_tree().process_frame


func _drag_list(list: ScrollContainer, label: String, require_move := true) -> void:
	list.scroll_vertical = 0
	await get_tree().process_frame
	var point := _center(list)
	var before := list.scroll_vertical
	var bar := list.get_v_scroll_bar()
	var scrollable := int(bar.max_value - bar.page)
	_touch(0, point, true)
	var moved := 0.0
	for i in 8:
		moved -= 24.0
		_drag(0, point + Vector2(0, moved), Vector2(0, -24))
	_drag_end(0)
	for i in 3:
		await get_tree().process_frame
	var after := list.scroll_vertical
	print("DRAG %s rect=%s scroll %d -> %d range=%d" % [
		label, list.get_global_rect(), before, after, scrollable])
	if require_move and scrollable >= 32:
		_check(after > before, "%s: drag up scrolls down (%d -> %d)" % [label, before, after])
		# The list must stop exactly at the last row, not past it.
		_check(after == mini(scrollable, 192),
			"%s: drag stops inside the list (%d of %d)" % [label, after, scrollable])
	else:
		_check(after >= before, "%s: drag up never scrolls backwards (%d -> %d)" % [label, before, after])
		if scrollable < 32:
			print("NOTE %s content fits (range=%d), direction only" % [label, scrollable])


func _find_touch_scroll(root: Node) -> ScrollContainer:
	if root == null:
		return null
	for child in root.get_children():
		if child is ScrollContainer and child.has_method("is_drag_scrolling"):
			return child as ScrollContainer
		var found := _find_touch_scroll(child)
		if found != null:
			return found
	return null


func _seed_player() -> void:
	NetworkClient.api_base_url = "http://127.0.0.1:9"
	MetaProgression.player_id = 424242
	MetaProgression.player_nickname = "Александр77"
	MetaProgression.nickname_custom = true
	MetaProgression.sky_shards = 195321
	MetaProgression.account_level = 7
	MetaProgression.matches_played = 128
	MetaProgression.char_levels = {"warrior": 7, "mage": 5, "fairy": 4}
	MetaProgression.char_xps = {"warrior": 650, "mage": 210, "fairy": 0}
	MetaProgression.unlocked_weapons.assign([1, 2, 3, 4, 5, 6, 7, 8, 9, 101, 102])
	MetaProgression.equipped_weapons = {"warrior": 4, "mage": 3, "fairy": 2}
	MetaProgression.equipped_skins = {"warrior": 1, "mage": 0, "fairy": 0}


# --- input helpers ----------------------------------------------------------

func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	get_viewport().push_input(event, true)


func _drag(index: int, position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	get_viewport().push_input(event, true)


func _drag_end(index: int) -> void:
	_touch(index, Vector2.ZERO, false)


func _tap(point: Vector2) -> void:
	# A real phone delivers the touch and the mouse events the engine emulates
	# from it; the probe sends both so the click path is the same.
	_touch(0, point, true)
	_mouse_button(point, true)
	_touch(0, point, false)
	_mouse_button(point, false)


func _mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	get_viewport().push_input(event, true)


func _mouse_motion(position: Vector2, relative: Vector2, mask: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.relative = relative
	event.button_mask = mask
	get_viewport().push_input(event, true)


func _center(control: Control) -> Vector2:
	return control.get_global_rect().get_center()


func _visible_button_center() -> Vector2:
	var view := scroll.get_global_rect()
	for button in buttons:
		var point := button.get_global_rect().get_center()
		if view.has_point(point):
			return point
	return view.get_center()


func _on_button_pressed() -> void:
	clicks += 1


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
