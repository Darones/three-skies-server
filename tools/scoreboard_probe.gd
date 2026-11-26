extends Node3D

## Battle scoreboard probe: the Tab table, the touch button and the report dialog.
##
## Run with the real layouts:
##   godot_console --path . tools/ScoreboardProbe.tscn -- --layout=1440x734
##   godot_console --path . tools/ScoreboardProbe.tscn -- --layout=844x390 --mobile
##   godot_console --path . tools/ScoreboardProbe.tscn -- --layout=844x390 --mobile --tutorial
##
## The online branch cannot be exercised without a server, so the probe proves
## the offline shape: the local player and bots are listed, bots get no report
## button, and the report dialog works with player_id = 0 without sending.
## Frames go to user://ui_shots/scoreboard_*.png.

const OUT_DIR := "user://ui_shots"
const REPORT_NICK := "ТестовыйНик"

var failures := 0
var checks := 0
var target := Vector2i(1440, 734)
var mobile := false
var tutorial := false
var tag := "desktop"
var game: Node = null
var hud: Node = null


func _ready() -> void:
	_parse_args()
	DeviceProfile.mobile_ui = mobile
	DeviceProfile.touch_controls = mobile
	get_tree().root.content_scale_size = target
	DisplayServer.window_set_size(target)
	for i in 3:
		await get_tree().process_frame
	if tutorial:
		await _run_tutorial()
	else:
		await _run_match()

	print("SCOREBOARD_CHECKS=%d FAILURES=%d" % [checks, failures])
	print("SCOREBOARD_DIR=", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(1 if failures > 0 else 0)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			var parts := arg.trim_prefix("--layout=").split("x")
			if parts.size() == 2:
				target = Vector2i(int(parts[0]), int(parts[1]))
		elif arg == "--mobile":
			mobile = true
		elif arg == "--tutorial":
			tutorial = true
	tag = "tutorial" if tutorial else ("mobile" if mobile else "desktop")


func _spawn_game(as_tutorial: bool) -> bool:
	get_tree().set_meta("tutorial_mode", as_tutorial)
	get_tree().set_meta("network_play", false)
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_check(false, "Main.tscn loads")
		return false
	game = packed.instantiate()
	add_child(game)
	for i in 16:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	for i in 360:
		if String(game.state) == "live":
			break
		await get_tree().process_frame
	_check(String(game.state) == "live", "match reaches live")
	hud = game.get("hud")
	_check(hud != null, "HUD exists")
	return hud != null


func _run_match() -> void:
	var spawned := await _spawn_game(false)
	if not spawned:
		return
	for i in 90:
		if (game.get("heroes") as Array).size() >= 6:
			break
		await get_tree().process_frame
	await _wait_ticks(3)
	_check((game.get("heroes") as Array).size() >= 6, "offline match spawned player + bots")

	var panel := hud.get("scoreboard_panel") as Control
	var button := hud.get("scoreboard_button") as Button
	_check(panel != null and not panel.visible, "table starts hidden")
	_check(not get_tree().paused, "table does not pause the tree")

	hud.call("_open_scoreboard")
	await _wait_ticks(2)
	await _check_table("offline")
	await _check_columns()
	_check(_report_buttons().is_empty(), "offline bots and self have no report buttons")
	var human_row := hud.call("_make_scoreboard_row", {
		"name": REPORT_NICK, "team": 0, "kills": 1, "deaths": 0,
		"crystals": 2, "score": 9, "is_bot": false, "is_self": false,
		"reportable": true,
	}) as Control
	_check(_find_button(human_row, "!") != null, "human row renders a report button")
	var human_report := _find_button(human_row, "!")
	_check(human_report != null and human_report.mouse_filter == Control.MOUSE_FILTER_STOP, "report button receives clicks")
	var bot_row := hud.call("_make_scoreboard_row", {
		"name": "БОТ · Тест", "team": 0, "kills": 1, "deaths": 0,
		"crystals": 2, "score": 9, "is_bot": true, "is_self": false,
		"reportable": false,
	}) as Control
	_check(_find_button(bot_row, "!") == null, "bot row has no report button")
	_check(bool(hud.call("_scoreboard_name_reportable", REPORT_NICK)), "human nickname is reportable")
	_check(not bool(hud.call("_scoreboard_name_reportable", String(MetaProgression.player_nickname))), "own nickname is not reportable")
	_check(not bool(hud.call("_scoreboard_name_reportable", "БА")), "short nickname is not reportable")
	await _shot("scoreboard_%s_%s" % [tag, "%dx%d" % [target.x, target.y]])

	await _check_report_dialog()
	await _check_tab()
	var close_button := _find_button(panel, "×")
	_check(close_button != null, "table has a close button")
	if close_button != null:
		close_button.pressed.emit()
		await _wait_ticks(1)
	_check(not bool(panel.visible), "close button closes the table")
	hud.call("_open_scoreboard")
	await _wait_ticks(1)
	_check(bool(panel.visible), "table is open again before the touch check")
	await _check_touch_button(button)

	hud.call("_open_scoreboard")
	await get_tree().process_frame
	hud.call("_open_pause_menu")
	_check(not bool(panel.visible), "pause menu closes the table")
	get_tree().paused = false
	hud.call("_resume_game")

	hud.call("_open_scoreboard")
	await _wait_ticks(2)
	_check(bool(panel.visible), "table opens before the end-state check")
	game.state = "ended"
	await _wait_ticks(6)
	_check(not bool(panel.visible), "state ended closes the table")
	_check(not bool(button.visible), "touch button hidden outside live")


func _run_tutorial() -> void:
	var spawned := await _spawn_game(true)
	if not spawned:
		return
	_check(bool(game.get("tutorial_mode")), "game is in tutorial mode")
	# The real tutorial spawns its bots stage by stage. Spawn two through the
	# same public API now so the table has its tutorial rows to draw.
	game.call("spawn_tutorial_bot", HeroUnit.Cls.FAIRY, int(game.player.team), Vector3(2.0, 0.76, 0.0), "easy", "Союзник")
	game.call("spawn_tutorial_bot", HeroUnit.Cls.MAGE, 1 - int(game.player.team), Vector3(-2.0, 0.76, -2.0), "easy", "Тренировочный бот")
	await _wait_ticks(3)

	var panel := hud.get("scoreboard_panel") as Control
	var button := hud.get("scoreboard_button") as Button
	# Keep the tutorial rules (bots, no report buttons) but clear the welcome
	# card so the QA frame shows the table itself.
	hud.call("hide_tutorial_card")
	hud.call("hide_ui_highlight")
	hud.call("show_tutorial_hint", "")
	hud.call("_open_scoreboard")
	await _wait_ticks(2)
	await _check_table("tutorial")
	await _check_columns()
	_check(_report_buttons().is_empty(), "tutorial bots have no report buttons")
	await _check_touch_button(button)
	await _shot("scoreboard_tutorial_%dx%d" % [target.x, target.y])

	await _check_tab()
	_check(bool(panel.visible), "tutorial table opens with Tab")
	game.state = "ended"
	await _wait_ticks(6)
	_check(not bool(panel.visible), "tutorial table closes when the match ends")
	get_tree().set_meta("tutorial_mode", false)


func _check_table(context: String) -> void:
	var panel := hud.get("scoreboard_panel") as Control
	var entries: Array = hud.call("_scoreboard_entries")
	_check(panel != null and bool(panel.visible), "%s table is visible" % context)
	_check(entries.size() >= 2, "%s table has at least player + bot (%d)" % [context, entries.size()])
	_check(_row_count() >= 2, "%s visible rows >= 2 (%d)" % [context, _row_count()])
	_check(not get_tree().paused, "%s table leaves the tree unpaused" % context)
	var score_label := hud.get("scoreboard_score_label") as Label
	_check(score_label != null and score_label.text.begins_with("Свет ") and score_label.text.contains(" : "), "%s match score header" % context)
	_check(_has_team_headers(), "%s table groups by team" % context)
	var texts := _label_texts(hud.get("scoreboard_panel"))
	var light_index := texts.find("СВЕТ")
	var dark_index := texts.find("ТЬМА")
	_check(light_index >= 0 and dark_index > light_index, "%s light team is listed before dark" % context)


func _check_columns() -> void:
	var texts := _label_texts(hud.get("scoreboard_panel"))
	for column in ["ИГРОК", "У/С", "ОСК.", "СЧЁТ"]:
		_check(texts.has(column), "column %s exists" % column)


func _check_report_dialog() -> void:
	hud.call("_open_scoreboard_report", REPORT_NICK)
	await _wait_ticks(2)
	var overlay := hud.get("scoreboard_report_overlay") as Control
	var reason := hud.get("scoreboard_report_reason") as OptionButton
	var submit := hud.get("scoreboard_report_submit") as Button
	var status := hud.get("scoreboard_report_status") as Label
	_check(overlay != null and overlay.visible, "report dialog opens")
	_check(reason != null and reason.item_count == 3, "report dialog has 3 reasons")
	if reason != null:
		_check(reason.get_item_text(0) == "Оскорбительный ник", "reason 1 is insulting nickname")
		_check(reason.get_item_text(1) == "Читы / нечестная игра", "reason 2 is cheating")
		_check(reason.get_item_text(2) == "Другое", "reason 3 is other")
	_check(submit != null and not submit.disabled, "report submit starts enabled")
	await _shot("scoreboard_report_%s" % tag)

	var cancel := _find_button(overlay, "Отмена")
	_check(cancel != null, "report dialog has a Cancel button")
	if cancel != null:
		cancel.pressed.emit()
		await _wait_ticks(1)
	_check(overlay != null and not overlay.visible, "Cancel closes the report dialog")

	# No real network: player_id = 0 must stop before NetworkClient.report_player.
	hud.call("_open_scoreboard_report", REPORT_NICK)
	var old_player_id := MetaProgression.player_id
	MetaProgression.player_id = 0
	hud.call("_submit_scoreboard_report")
	await _wait_ticks(1)
	_check(status != null and status.text.contains("Нужен вход"), "report without login shows the login status")
	MetaProgression.player_id = old_player_id
	_check(submit != null and not submit.disabled, "report submit stays usable after the login error")

	# The signal the server would emit is wired to the dialog status.
	NetworkClient.report_completed.emit(true, "")
	await _wait_ticks(1)
	_check(status != null and status.text.contains("Жалоба отправлена"), "report_completed success updates the status")
	NetworkClient.report_completed.emit(false, "Too many reports")
	await _wait_ticks(1)
	_check(status != null and status.text.contains("слишком много"), "report_completed error is localized")
	hud.call("_close_scoreboard_report")

	hud.call("_open_scoreboard_report", REPORT_NICK)
	await _wait_ticks(1)
	await _send_tab()
	_check(hud.get("scoreboard_report_overlay") != null and not (hud.get("scoreboard_report_overlay") as Control).visible, "Tab closes the report dialog")
	_check((hud.get("scoreboard_panel") as Control).visible, "Tab on the dialog leaves the table open")


func _check_tab() -> void:
	var panel := hud.get("scoreboard_panel") as Control
	_check(bool(panel.visible), "table is visible before Tab")
	await _send_tab()
	_check(not bool(panel.visible), "Tab closes the table")
	await _send_tab()
	_check(bool(panel.visible), "Tab opens the table")


func _check_touch_button(button: Button) -> void:
	await _wait_ticks(4)
	_check(button != null, "touch button exists")
	if button == null:
		return
	_check(bool(button.visible) == mobile, "touch button visible only with mobile UI (visible=%s mobile=%s)" % [button.visible, mobile])
	if not mobile:
		return
	_check(button.size.is_equal_approx(Vector2(64.0, 64.0)), "touch button is 64x64 (%s)" % button.size)
	_check(absf(button.position.x - 436.0) <= 2.0, "touch button sits in the old pause spot x=436 (%.1f)" % button.position.x)
	_check(absf(button.position.y - 20.0) <= 2.0, "touch button sits at the old pause spot y=20 (%.1f)" % button.position.y)
	var panel := hud.get("scoreboard_panel") as Control
	button.pressed.emit()
	await _wait_ticks(1)
	_check(not bool(panel.visible), "touch button closes the table")
	button.pressed.emit()
	await _wait_ticks(1)
	_check(bool(panel.visible), "touch button opens the table")


func _row_count() -> int:
	var rows := hud.get("scoreboard_rows") as VBoxContainer
	if rows == null:
		return 0
	var count := 0
	for child in rows.get_children():
		if child is PanelContainer:
			count += 1
	return count


func _has_team_headers() -> bool:
	var texts := _label_texts(hud.get("scoreboard_panel"))
	return texts.has("СВЕТ") and texts.has("ТЬМА")


func _report_buttons() -> Array:
	var out: Array = []
	for button in _buttons(hud.get("scoreboard_panel")):
		if String(button.name) == "Report":
			out.append(button)
	return out


func _find_button(root: Node, text: String) -> Button:
	if root == null:
		return null
	for button in _buttons(root):
		if button.text == text:
			return button
	return null


func _buttons(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for child in root.get_children():
		if child is Button:
			out.append(child)
		out.append_array(_buttons(child))
	return out


func _label_texts(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for child in root.get_children():
		if child is Label:
			out.append((child as Label).text)
		out.append_array(_label_texts(child))
	return out


func _send_tab() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_TAB
	down.physical_keycode = KEY_TAB
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = KEY_TAB
	up.physical_keycode = KEY_TAB
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _wait_ticks(count: int) -> void:
	# One HUD slow tick is 0.1 s; give the table a few of them.
	for i in count * 8:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var error := image.save_png(path)
	if error != OK:
		_check(false, "screenshot %s saved (%s)" % [name, error_string(error)])
	else:
		print("SHOT ", name, " ", image.get_size(), " ", path)
	_check(image.get_size() == target, "screenshot %s is %dx%d (%s)" % [name, target.x, target.y, image.get_size()])


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
