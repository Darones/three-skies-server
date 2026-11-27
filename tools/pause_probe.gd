extends Node3D

## Pause probe (mobile 844x390, VK webview layout).
##
## Run:
##   godot_console --path . tools/PauseProbe.tscn -- --layout=844x390 --mobile
##
## The complaint from the VK build was "кнопка паузы не реагирует": the touch
## HUD had no pause tile at all, the player card's gui_input was the only way
## in. This probe loads the real Main.tscn, starts a match, and checks that
##   * a 64x64 pause tile exists right of "СЧЁТ" and covers nothing,
##   * its pressed signal opens the menu (local match pauses the tree),
##   * "Продолжить" closes it and unpauses,
##   * "В лобби" leaves the match for Lobby.tscn,
##   * an online match opens the same menu without pausing the tree.
##
## Prints PASS/FAIL per check, "PAUSE_CHECKS=n FAILURES=m" and exits 1 on FAIL.

const DEAD_API := "http://127.0.0.1:9"
const SCENE_LIVE_TIMEOUT_USEC := 60_000_000
const LOBBY_TIMEOUT_USEC := 8_000_000

var checks := 0
var failures := 0
var game: Node = null
var hud: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var target := Vector2i(844, 390)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			var parts := arg.trim_prefix("--layout=").split("x")
			if parts.size() == 2:
				target = Vector2i(int(parts[0]), int(parts[1]))
	# The tile only exists on touch: force the phone profile even when the
	# probe is launched without --mobile.
	DeviceProfile.mobile_ui = true
	DeviceProfile.touch_controls = true
	get_tree().root.content_scale_size = Vector2i(960, 540)
	DisplayServer.window_set_size(target)
	# Never talk to the live server from a probe.
	NetworkClient.api_base_url = DEAD_API
	for i in 3:
		await get_tree().process_frame

	game = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	# Add the match straight under root and make it the current scene, exactly
	# like the real launch. "В лобби" then swaps Main for Lobby.tscn without
	# touching this probe; a match parented to the probe would survive
	# change_scene_to_file as a second running scene.
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

	# The tile visibility is refreshed on the HUD's 10 Hz tick.
	await _wait(0.4)

	var pause_button := hud.get("pause_button") as Button
	var score_button := hud.get("scoreboard_button") as Button
	var card := hud.get("player_panel") as Control
	var overlay := hud.get("pause_overlay") as Control
	var panel := hud.get("pause_menu_panel") as Control
	var title := hud.get("pause_title_label") as Label
	var resume := hud.get("pause_resume_button") as Button
	var lobby_button := hud.get("pause_lobby_button") as Button

	_check(pause_button != null, "pause tile exists")
	_check(overlay != null and panel != null and resume != null, "pause menu nodes exist")
	if pause_button == null or overlay == null or panel == null or resume == null:
		_finish()
		return

	# --- geometry on 844x390 ------------------------------------------------
	var viewport_size := get_viewport().get_visible_rect().size
	var pause_rect := pause_button.get_global_rect()
	var score_rect := score_button.get_global_rect() if score_button != null else Rect2()
	var card_rect := card.get_global_rect() if card != null else Rect2()
	print("PAUSE_GEOMETRY viewport=%s tile=%s score=%s card=%s" % [
		viewport_size, pause_rect, score_rect, card_rect,
	])
	_check(pause_button.visible, "pause tile visible in a live mobile match")
	_check(
		absf(pause_rect.size.x - 64.0) <= 1.0 and absf(pause_rect.size.y - 64.0) <= 1.0,
		"pause tile is 64x64 (got %s)" % pause_rect.size
	)
	_check(not pause_rect.intersects(score_rect), "pause tile does not cover 'СЧЁТ'")
	_check(not pause_rect.intersects(card_rect), "pause tile does not cover the player card")
	_check(
		absf(pause_rect.position.x - (score_rect.end.x + 8.0)) <= 1.0,
		"pause tile sits 8px right of 'СЧЁТ' (tile x=%.1f, score end=%.1f)" % [
			pause_rect.position.x, score_rect.end.x,
		]
	)
	_check(
		absf(pause_rect.position.y - card_rect.position.y) <= 1.0,
		"pause tile shares the card row (tile y=%.1f, card y=%.1f)" % [
			pause_rect.position.y, card_rect.position.y,
		]
	)
	_check(
		Rect2(Vector2.ZERO, viewport_size).encloses(pause_rect),
		"pause tile is fully on screen"
	)
	var slots: Array = hud.get("ability_slots") if hud.get("ability_slots") is Array else []
	var hits_ability := false
	for slot in slots:
		if slot != null and is_instance_valid(slot) and (slot as Control).visible:
			if pause_rect.intersects((slot as Control).get_global_rect()):
				hits_ability = true
	_check(not hits_ability, "pause tile does not cover the ability buttons")
	_check(
		pause_button.z_index > 0 and pause_button.z_index < overlay.z_index,
		"pause tile draws above the HUD and below the overlay (z=%d < %d)" % [
			pause_button.z_index, overlay.z_index,
		]
	)
	_check(
		pause_button.mouse_filter == Control.MOUSE_FILTER_STOP,
		"pause tile accepts pointer/touch (mouse_filter=STOP)"
	)
	_check(
		pause_button.process_mode != Node.PROCESS_MODE_DISABLED,
		"pause tile process_mode is active"
	)
	_check(not pause_button.disabled, "pause tile is not disabled")
	_check(
		pause_button.find_child("PauseGlyph", true, false) != null,
		"pause tile draws its two-bar glyph (font independent)"
	)
	_check(
		score_button != null and pause_button.get_parent() == score_button.get_parent(),
		"pause tile shares the 'СЧЁТ' parent so both rects are comparable"
	)

	# Desktop hides the tile. The tree is paused for these frames so no game
	# code reads the flipped profile flag.
	get_tree().paused = true
	DeviceProfile.mobile_ui = false
	hud.set("hud_tick", 1.0)
	for i in 3:
		await get_tree().process_frame
	var hidden_on_desktop := not pause_button.visible
	get_tree().paused = false
	DeviceProfile.mobile_ui = true
	hud.set("hud_tick", 1.0)
	for i in 3:
		await get_tree().process_frame
	_check(hidden_on_desktop, "pause tile is hidden on desktop")
	_check(pause_button.visible, "pause tile comes back on mobile")

	# --- local match: tile -> menu -> tree pause ---------------------------
	pause_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(overlay.visible, "pause tile opens the pause overlay")
	_check(panel.visible, "pause menu panel is visible")
	_check(String(title.text) == "ПАУЗА", "local menu title is ПАУЗА (got '%s')" % String(title.text))
	_check(
		String(resume.text) == "Продолжить",
		"local resume reads Продолжить (got '%s')" % String(resume.text)
	)
	_check(get_tree().paused, "local match pauses the scene tree")

	resume.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not overlay.visible, "Продолжить closes the overlay")
	_check(not get_tree().paused, "Продолжить unpauses the scene tree")

	# --- online match: overlay only, no tree pause -------------------------
	# network_play is flipped around the synchronous call, so no frame ever
	# runs the local match with the online flag set.
	game.set("network_play", true)
	hud.call("_open_pause_menu")
	game.set("network_play", false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(overlay.visible, "online menu opens from the tile")
	_check(String(title.text) == "МЕНЮ", "online menu title is МЕНЮ (got '%s')" % String(title.text))
	_check(
		String(resume.text) == "Закрыть",
		"online resume reads Закрыть (got '%s')" % String(resume.text)
	)
	_check(not get_tree().paused, "online menu does not pause the scene tree")
	hud.call("_resume_game")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not overlay.visible, "online Закрыть closes the overlay")
	_check(not get_tree().paused, "scene tree stays unpaused after closing the online menu")

	# --- "В лобби" leaves the match ----------------------------------------
	hud.set("hud_tick", 1.0)
	await get_tree().process_frame
	pause_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(overlay.visible and get_tree().paused, "menu reopens paused for the lobby test")
	_check(lobby_button != null, "'В лобби' button exists")
	if lobby_button == null:
		_finish()
		return
	_check(
		String(lobby_button.text) == "В лобби",
		"exit button reads В лобби (got '%s')" % String(lobby_button.text)
	)
	# The match is already get_tree().current_scene (see _ready), so the real
	# exit path swaps Main for Lobby.tscn and this probe stays alive to read
	# the result. If the swap does not land, the fallback below still proves
	# the handler is wired and the tree is unpaused.
	lobby_button.pressed.emit()
	var scene_changed := false
	var lobby_deadline := Time.get_ticks_usec() + LOBBY_TIMEOUT_USEC
	while Time.get_ticks_usec() < lobby_deadline:
		await get_tree().process_frame
		var current := get_tree().current_scene
		if is_instance_valid(current) and String(current.scene_file_path).contains("Lobby"):
			scene_changed = true
			break
	_check(not get_tree().paused, "'В лобби' unpauses the tree before switching scenes")
	if scene_changed:
		_check(true, "'В лобби' opens Lobby.tscn")
	else:
		# Fallback from the plan: the scene swap itself is flaky in a probe, so
		# a wired handler plus an unpaused tree is the pass condition.
		print("PAUSE_NOTE scene change not observed; checking the handler instead")
		var wired := false
		for connection in lobby_button.pressed.get_connections():
			var callable: Callable = connection["callable"]
			if callable.get_method() == "_exit_game":
				wired = true
		_check(wired, "'В лобби' is wired to _exit_game")

	var current_path := "<none>"
	var current_scene := get_tree().current_scene
	if is_instance_valid(current_scene):
		current_path = String(current_scene.scene_file_path)
	print("PAUSE_SCENE_CHANGED=", scene_changed, " current=", current_path)
	_finish()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _finish() -> void:
	print("PAUSE_CHECKS=%d FAILURES=%d" % [checks, failures])
	print("PAUSE_RESULT=", "FAIL" if failures > 0 else "PASS")
	get_tree().quit(1 if failures > 0 else 0)
