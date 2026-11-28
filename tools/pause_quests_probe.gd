extends Node3D

## Battle pause menu → "Задания дня" (read-only daily quests).
##
## Run:
##   godot_console --path . tools/PauseQuestsProbe.tscn -- --layout=1280x720
##   godot_console --path . tools/PauseQuestsProbe.tscn -- --layout=1440x734
##   godot_console --path . tools/PauseQuestsProbe.tscn -- --layout=844x390 --mobile
##
## Loads the real Main.tscn, starts a local match and checks that
##   * the pause menu has "Задания дня" between "Продолжить" and "Правила",
##   * it opens a read-only quests overlay: 3 cards, week footer, 300 chip,
##     the "Осталось N ..." status and "Назад",
##   * there is no "Забрать"/"Заменить" button and no typed check glyph,
##   * the drawn check mark is a Control (Philosopher has no U+2713),
##   * the panel fits the logical viewport on 1280x720, 1440x734 and 844x390,
##   * "Назад" returns to the pause menu and the tree stays paused.
##
## Saves user://ui_shots/pause_quests_<menu|panel|back>_<layout>.png.
## Prints "PAUSE_QUESTS checks pass=N fail=M" and "PAUSE_QUESTS_RESULT=PASS|FAIL".

const DEAD_API := "http://127.0.0.1:9"
const SCENE_LIVE_TIMEOUT_USEC := 60_000_000
const SHOTS_DIR := "user://ui_shots"
const BANNED_GLYPHS := ["\u2713", "\u2714", "\u25C6", "\u21BB", "\u2717"]

var checks := 0
var failures := 0
var layout_tag := "1280x720"
var mobile := false
var game: Node = null
var hud: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var target := Vector2i(1280, 720)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			var parts := arg.trim_prefix("--layout=").split("x")
			if parts.size() == 2:
				target = Vector2i(int(parts[0]), int(parts[1]))
		elif arg == "--mobile":
			mobile = true
	if mobile or target.x < 500:
		mobile = true
		DeviceProfile.mobile_ui = true
		DeviceProfile.touch_controls = true
		get_tree().root.content_scale_size = Vector2i(960, 540)
	else:
		DeviceProfile.mobile_ui = false
		get_tree().root.content_scale_size = target
	layout_tag = "%dx%d" % [target.x, target.y]
	DisplayServer.window_set_size(target)
	# Never talk to the live server from a probe.
	NetworkClient.api_base_url = DEAD_API
	for i in 3:
		await get_tree().process_frame

	_seed_daily_quests()
	game = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	var ready_deadline := Time.get_ticks_usec() + 40_000_000
	while Time.get_ticks_usec() < ready_deadline:
		await get_tree().process_frame
		if game.get("hud") != null and String(game.get("state")) == "select":
			break
	for i in 10:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	var deadline := Time.get_ticks_usec() + SCENE_LIVE_TIMEOUT_USEC
	while String(game.get("state")) != "live" and Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
	_check(String(game.get("state")) == "live", "match reached live (state=%s)" % String(game.get("state")))
	if String(game.get("state")) != "live":
		_finish()
		return
	hud = game.get("hud")
	_check(hud != null, "HUD is attached to the match")
	if hud == null:
		_finish()
		return
	await _wait(0.4)

	hud.call("_open_pause_menu")
	await get_tree().process_frame
	await get_tree().process_frame
	var overlay := hud.get("pause_overlay") as Control
	var menu := hud.get("pause_menu_panel") as Control
	var button := hud.get("pause_quests_button") as Button
	var quests := hud.get("pause_quests_panel") as Control
	_check(overlay != null and overlay.visible, "pause overlay opens")
	_check(menu != null and menu.visible, "pause menu panel is visible")
	_check(button != null, "'Задания дня' button exists")
	_check(quests != null, "pause quests panel is created")
	if button == null or quests == null or menu == null:
		_finish()
		return

	_check(String(button.text) == "Задания дня", "button text is 'Задания дня' (got '%s')" % String(button.text))
	_check(String(button.name) == "PauseQuestsButton", "button node name is PauseQuestsButton")
	_check(get_tree().paused, "local match pauses the tree")

	# Order in the menu: title, Продолжить, Задания дня, Правила, ...
	var resume := hud.get("pause_resume_button") as Button
	var menu_layout := button.get_parent()
	var resume_index := resume.get_index() if resume != null else -1
	var quests_index := button.get_index()
	var rules_index := -1
	for child in menu_layout.get_children():
		if child is Button and String((child as Button).text) == "Правила":
			rules_index = child.get_index()
			break
	_check(quests_index == resume_index + 1,
		"'Задания дня' sits right after 'Продолжить' (%d/%d)" % [quests_index, resume_index])
	_check(rules_index == quests_index + 1,
		"'Правила' stays right after 'Задания дня' (%d/%d)" % [rules_index, quests_index])
	_check(_inside(button.get_global_rect(), menu.get_global_rect()),
		"button fits inside the 420x404 pause menu")
	var menu_overflow := _overflowing_menu_items(menu)
	_check(menu_overflow.is_empty(), "no pause menu item overflows the panel %s" % str(menu_overflow))

	await _shot("menu")
	button.pressed.emit()
	await _wait(0.45)
	_check(quests.visible, "'Задания дня' opens the quests overlay")
	_check(not menu.visible, "pause menu is hidden behind the quests overlay")
	_check(get_tree().paused, "opening the quests overlay keeps the tree paused")
	_check(overlay.visible, "pause overlay stays visible")

	var inner := quests.get("panel") as Control
	var cards: Array = quests.get("card_nodes")
	var claim := quests.get("claim_button") as Button
	var back := quests.get("back_button") as Button
	var title := quests.get("title_label") as Label
	var timer := quests.get("timer_label") as Label
	var count := quests.get("count_label") as Label
	var week := quests.get("week_label") as Label
	var status := quests.get("status_label") as Label
	var reward_amount := quests.get("reward_amount_label") as Label

	_check(inner != null and inner.visible, "quests panel body is visible")
	_check(cards.size() == 3, "3 quest cards (got %d)" % cards.size())
	for index in cards.size():
		var card := cards[index] as Control
		_check(card.visible, "card %d is visible" % index)
		_check(card.find_child("DailyQuestsRing%d" % index, true, false) != null,
			"card %d keeps its progress ring" % index)
		_check(card.find_child("DailyQuestsProgress%d" % index, true, false) != null,
			"card %d keeps its X/Y progress text" % index)
		var chip := card.find_child("DailyQuestsRewardChip%d" % index, true, false) as Control
		_check(chip != null and chip.visible, "card %d keeps its shard reward chip" % index)
	_check(title != null and title.text == "ЕЖЕДНЕВНЫЕ ЗАДАНИЯ", "overlay header title")
	_check(timer != null and timer.visible, "overlay header timer")
	_check(count != null and count.text == "1/3", "header shows 1/3 (got '%s')" % (
		String(count.text) if count != null else "<none>"))
	_check(claim != null and not claim.visible, "'Забрать' is hidden")
	_check(back != null and back.visible and String(back.text) == "Назад", "'Назад' button is visible")
	var action_buttons := _action_buttons(quests)
	_check(action_buttons.is_empty(), "no 'Забрать'/'Заменить' buttons in the read-only panel %s" % str(action_buttons))

	var diamonds := 0
	for index in 7:
		var diamond := quests.find_child("DailyQuestsDay%d" % index, true, false) as Control
		if diamond != null and diamond.visible and diamond.find_child("DiamondOuter", true, false) != null:
			diamonds += 1
	_check(diamonds == 7, "week footer has 7 drawn diamonds (got %d)" % diamonds)
	_check(week != null and week.text.contains("5/7"), "week footer shows 5/7 (got '%s')" % (
		String(week.text) if week != null else "<none>"))
	_check(status != null and status.text.contains("Осталось 2"), "week status says 'Осталось 2' (got '%s')" % (
		String(status.text) if status != null else "<none>"))
	_check(reward_amount != null and String(reward_amount.text) == "300", "reward chip shows 300")

	# No tofu glyphs: Philosopher has no U+2700-27BF and web has no fallback.
	var garbage := _banned_glyph_labels(quests)
	_check(garbage.is_empty(), "no typed check/reload/diamond glyphs %s" % str(garbage))
	var drawn_check := quests.find_child("DailyQuestsCheck0", true, false)
	_check(drawn_check is Control and not (drawn_check is Label), "completed card check is a Control, not text")
	if drawn_check is Control:
		_check((drawn_check as Control).visible, "completed card check is visible")
		_check(drawn_check.has_method("_draw"), "completed card check is drawn in _draw")
		_check((drawn_check as Control).size.x >= 24.0 and (drawn_check as Control).size.y >= 24.0,
			"completed card check is 26 px (got %s)" % (drawn_check as Control).size)

	# Geometry: the whole overlay must fit the logical viewport with a margin.
	var view := get_viewport().get_visible_rect().size
	var screen := Rect2(Vector2.ZERO, view)
	var panel_rect := inner.get_global_rect()
	print("PAUSE_QUESTS_RECT viewport=%s panel=%s layout=%s" % [view, panel_rect, layout_tag])
	_check(screen.encloses(panel_rect), "quests panel is inside the viewport")
	_check(panel_rect.size.x <= view.x - 40.0 + 1.0 and panel_rect.size.y <= view.y - 40.0 + 1.0,
		"quests panel fits viewport minus 40 (%s)" % panel_rect.size)
	_check(panel_rect.size.x >= 400.0 and panel_rect.size.y >= 280.0,
		"quests panel keeps a readable size (%s)" % panel_rect.size)
	await _shot("panel")

	back.pressed.emit()
	await _wait(0.3)
	_check(not quests.visible, "'Назад' closes the quests overlay")
	_check(menu.visible, "'Назад' returns to the pause menu")
	_check(overlay.visible, "pause overlay stays open after 'Назад'")
	_check(get_tree().paused, "'Назад' does not unpause the match")
	await _shot("back")

	# Offline / empty snapshot: the read-only panel must still offer a way back.
	hud.call("_open_pause_quests")
	await _wait(0.3)
	quests.call("apply_data", {})
	await _wait(0.3)
	_check(quests.visible, "empty snapshot keeps the quests panel open")
	_check(back != null and back.visible, "empty snapshot still shows 'Назад'")
	back.pressed.emit()
	await _wait(0.3)
	_check(not quests.visible and menu.visible, "empty snapshot 'Назад' returns to the menu")

	_finish()


func _seed_daily_quests() -> void:
	# Deterministic snapshot, no server: 1 of 3 done, 5 of 7 week days closed.
	var daily := get_node_or_null("/root/DailyQuests")
	if daily == null:
		return
	var quests: Array[Dictionary] = [
		{
			"slot": 1, "template_id": "kills_8", "title": "Убить 8 врагов",
			"metric": "kills", "target": 8, "progress": 8, "reward_shards": 3,
			"completed": true,
		},
		{
			"slot": 2, "template_id": "damage_4000", "title": "Нанести урон 4000",
			"metric": "damage", "target": 4000, "progress": 1650, "reward_shards": 4,
			"completed": false,
		},
		{
			"slot": 3, "template_id": "buy_2", "title": "Купить 2 усиления",
			"metric": "shop_items_one", "target": 2, "progress": 1, "reward_shards": 5,
			"completed": false,
		},
	]
	var days: Array = []
	for index in 7:
		days.append({
			"day": "2026-11-%02d" % (23 + index),
			"completed": index < 5,
			"full": index < 5,
			"today": index == 3,
		})
	var week := {
		"required": 7, "active_days": 5, "tier": 0,
		"claimable": false, "claimed": false,
		"start": "2026-11-23", "days": days,
	}
	daily.set("quests", quests)
	daily.set("week", week)
	daily.set("rerolls", {"free": true, "free_used": false, "paid": 0, "paid_max": 2, "cost": 1, "remaining": 3})
	daily.set("summary", {"completed": 1, "total": 3, "week": week})
	daily.set("day", "2026-11-28")
	daily.set("resets_at", int(Time.get_unix_time_from_system()) + 5 * 3600 + 720)
	daily.set("loaded", true)


func _action_buttons(root: Control) -> Array:
	var found: Array = []
	var buttons: Array[Node] = root.find_children("*", "Button", true, false)
	for node in buttons:
		var button := node as Button
		if not button.is_visible_in_tree():
			continue
		if button.text.contains("Забрать") or button.text.contains("Заменить"):
			found.append("%s '%s'" % [String(button.name), button.text])
	return found


func _banned_glyph_labels(root: Control) -> Array:
	var found: Array = []
	var nodes: Array[Node] = root.find_children("*", "", true, false)
	for node in nodes:
		var text := ""
		if node is Label:
			text = (node as Label).text
		elif node is Button:
			text = (node as Button).text
		elif node is RichTextLabel:
			text = (node as RichTextLabel).text
		else:
			continue
		for glyph in BANNED_GLYPHS:
			if text.contains(glyph):
				found.append("%s '%s'" % [String(node.name), text])
				break
	return found


func _overflowing_menu_items(menu: Control) -> Array:
	var bad: Array = []
	var rect := menu.get_global_rect()
	for child in menu.get_children():
		if child is Label or child is Button:
			var control := child as Control
			if not control.visible:
				continue
			if not _inside(control.get_global_rect(), rect):
				bad.append(String(control.name))
	return bad


func _inside(inner: Rect2, outer: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 1.0 \
		and inner.position.y >= outer.position.y - 1.0 \
		and inner.end.x <= outer.end.x + 1.0 \
		and inner.end.y <= outer.end.y + 1.0


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(screen: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var image := get_viewport().get_texture().get_image()
	var path := "%s/pause_quests_%s_%s.png" % [SHOTS_DIR, screen, layout_tag]
	var error := image.save_png(path)
	if error != OK:
		failures += 1
		print("PAUSE_QUESTS SHOT_FAIL ", screen, " ", error)
	else:
		print("PAUSE_QUESTS SHOT ", path)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PAUSE_QUESTS PASS: ", label)
	else:
		failures += 1
		print("PAUSE_QUESTS FAIL: ", label)


func _finish() -> void:
	print("PAUSE_QUESTS checks pass=%d fail=%d" % [checks, failures])
	print("PAUSE_QUESTS_RESULT=", "FAIL" if failures > 0 else "PASS")
	print("PAUSE_QUESTS_DIR=", ProjectSettings.globalize_path(SHOTS_DIR))
	get_tree().quit(1 if failures > 0 else 0)
