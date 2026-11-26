extends Node3D

## Client moderation UI probe: ban card and warning card in the lobby.
##
## Run with the real layouts:
##   godot_console --path . tools/ModerationUiProbe.tscn -- --layout=844x390 --mobile
##   godot_console --path . tools/ModerationUiProbe.tscn -- --layout=1440x734
##
## The server state lives in NetworkClient; the probe sets the same fields and
## emits the same signals the server would. Frames go to
## user://ui_shots/moderation_<screen>_<tag>.png.

const LAYOUT_DIR := "user://ui_shots"
const WARN_AT := 1764115200
const WARN_AT_NEXT := 1764118800

var failures := 0
var tag := "desktop"
var mobile := false
var lobby: Control


func _ready() -> void:
	var target := Vector2i(1440, 734)
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
		get_tree().root.content_scale_size = target
	DisplayServer.window_set_size(target)
	tag = "mobile" if mobile else "desktop"
	for i in 3:
		await get_tree().process_frame

	_clear_warning_meta()
	_reset_moderation_state()
	var old_api: String = NetworkClient.api_base_url
	_seed_returning_player()
	lobby = (load("res://scenes/Lobby.tscn") as PackedScene).instantiate() as Control
	add_child(lobby)
	for i in 20:
		await get_tree().process_frame

	await _check_idle_state()
	await _check_ban_signal()
	await _check_ban_blocks_play()
	await _check_warning_flow()
	await _check_warning_once_across_refresh()
	await _check_unban_and_welcome()
	await _check_ban_at_ready()

	# Frames: the ban card and the warning card at the real layout.
	_set_ban(true, "Спам и оскорбления в чате")
	for i in 6:
		await get_tree().process_frame
	await _shot("ban")
	_set_ban(false, "")
	_set_warning(1, "Оскорбления в чате", WARN_AT)
	for i in 6:
		await get_tree().process_frame
	await _shot("warning")

	_reset_moderation_state()
	NetworkClient.api_base_url = old_api
	_clear_warning_meta()
	print("MODERATION_UI_FAILURES=%d" % failures)
	print("MODERATION_UI_DIR=", ProjectSettings.globalize_path(LAYOUT_DIR))
	get_tree().quit(1 if failures > 0 else 0)


func _check_idle_state() -> void:
	_check(lobby.get("moderation_ban_overlay") != null, "ban overlay exists")
	_check(lobby.get("moderation_warning_overlay") != null, "warning overlay exists")
	_check(not lobby.call("is_moderation_ban_visible"), "ban overlay starts hidden")
	_check(not lobby.call("is_moderation_warning_visible"), "warning overlay starts hidden")
	var ban := lobby.get("moderation_ban_overlay") as ColorRect
	var warning := lobby.get("moderation_warning_overlay") as ColorRect
	_check(ban != null and ban.z_index > 200, "ban overlay is above the welcome card")
	_check(warning != null and warning.z_index > 200 and warning.z_index < ban.z_index, "warning sits above welcome and below ban")
	if ban != null:
		_check(ban.mouse_filter == Control.MOUSE_FILTER_STOP, "ban overlay blocks clicks")
		var view := get_viewport().get_visible_rect().size
		_check(ban.get_global_rect().size.x >= view.x - 1.0 and ban.get_global_rect().size.y >= view.y - 1.0, "ban overlay covers the screen")
	var buttons := 0
	if ban != null:
		buttons = _count_buttons(ban)
	_check(buttons == 0, "ban overlay has no action buttons at all")
	var reason := lobby.get("moderation_ban_reason_label") as Label
	_check(reason != null and reason.autowrap_mode != TextServer.AUTOWRAP_OFF, "ban reason wraps on narrow screens")


func _check_ban_signal() -> void:
	_set_ban(true, "Спам в чате")
	_check(lobby.call("is_moderation_ban_visible"), "ban signal shows the full-screen card")
	var title := lobby.get("moderation_ban_overlay").find_child("BanTitle", true, false) as Label
	_check(title != null and title.text.contains("ДОСТУП ОГРАНИЧЕН"), "ban card title is the restriction notice")
	var reason := lobby.get("moderation_ban_reason_label") as Label
	_check(reason != null and reason.text.contains("Спам в чате"), "ban card shows the server reason")
	_check(reason != null and reason.text.contains("Причина"), "ban card labels the reason")
	# No Play/Tutorial/shop wording inside the card itself.
	var text := ""
	for label in _collect_labels(lobby.get("moderation_ban_overlay") as Node):
		text += label.text
	_check(not text.contains("ИГРАТЬ") and not text.contains("ОБУЧЕНИЕ") and not text.contains("МАГАЗИН"), "ban card offers no play or shop actions")
	_set_ban(false, "")
	_check(not lobby.call("is_moderation_ban_visible"), "unban signal hides the card")


func _check_ban_blocks_play() -> void:
	_set_ban(true, "")
	var reason := lobby.get("moderation_ban_reason_label") as Label
	_check(reason != null and reason.text.contains("ограничен"), "empty ban reason falls back to a safe notice")
	var play := lobby.get("play_button") as Button
	var ban := lobby.get("moderation_ban_overlay") as Control
	var covered := play != null and ban != null and ban.get_global_rect().encloses(play.get_global_rect())
	_check(covered, "ban card covers the Play button")
	# The guard must also hold if the button is pressed programmatically.
	var scene_before := get_tree().current_scene
	var info_before := (lobby.get("info_overlay") as Control).visible
	lobby.call("_on_play_pressed")
	await get_tree().process_frame
	_check(get_tree().current_scene == scene_before, "Play under ban does not change the scene")
	_check((lobby.get("info_overlay") as Control).visible == info_before, "Play under ban shows no profile popup")
	_check(bool(lobby.call("_account_is_banned")), "ban state stays set after a blocked Play")
	_set_ban(false, "")


func _check_warning_flow() -> void:
	_set_warning(1, "Оскорбления в чате", WARN_AT)
	_check(lobby.call("is_moderation_warning_visible"), "warning signal shows the card")
	var title := lobby.get("moderation_warning_overlay").find_child("WarningTitle", true, false) as Label
	_check(title != null and title.text.contains("ПРЕДУПРЕЖДЕНИЕ"), "warning card has its own title")
	var reason := lobby.get("moderation_warning_reason_label") as Label
	_check(reason != null and reason.text.contains("Оскорбления в чате"), "warning card shows the server reason")
	var ok := lobby.get("moderation_warning_ok_button") as Button
	_check(ok != null and ok.text == "Понятно", "warning card has the Понятно button")
	if ok != null:
		ok.pressed.emit()
	await get_tree().process_frame
	_check(not lobby.call("is_moderation_warning_visible"), "Понятно closes the warning")
	var play := lobby.get("play_button") as Button
	_check(play != null and not play.disabled, "lobby is playable again after closing the warning")

	# A new warning timestamp shows a new card.
	_set_warning(2, "Повторное нарушение", WARN_AT_NEXT)
	_check(lobby.call("is_moderation_warning_visible"), "a newer warning timestamp shows a new card")
	_check(reason != null and reason.text.contains("Повторное нарушение"), "new warning carries its own reason")
	lobby.call("_hide_moderation_warning")

	# count > 0 with at == 0: one generic card, no spam.
	_set_warning(3, "", 0)
	_check(lobby.call("is_moderation_warning_visible"), "generic warning with no timestamp shows")
	_check(lobby.call("is_moderation_warning_visible"), "generic warning stays until dismissed")
	lobby.call("_hide_moderation_warning")
	_set_warning(3, "", 0)
	_check(not lobby.call("is_moderation_warning_visible"), "generic warning does not repeat")
	_set_warning(0, "", 0)
	_check(not lobby.call("is_moderation_warning_visible"), "zero warnings show nothing")


func _check_warning_once_across_refresh() -> void:
	_clear_warning_meta()
	_set_warning(1, "Замечание модератора", WARN_AT)
	_check(lobby.call("is_moderation_warning_visible"), "first warning card appears")
	lobby.call("_hide_moderation_warning")
	# A profile refresh re-emits the same payload: must not reopen the card.
	_set_warning(1, "Замечание модератора", WARN_AT)
	_check(not lobby.call("is_moderation_warning_visible"), "same warning timestamp is shown only once")
	_set_warning(1, "Замечание модератора", WARN_AT_NEXT)
	_check(lobby.call("is_moderation_warning_visible"), "next warning timestamp shows once more")
	lobby.call("_hide_moderation_warning")


func _check_unban_and_welcome() -> void:
	# Welcome gating needs the real lobby scene root, exactly like production.
	var old_loaded: bool = MetaProgression.profile_loaded
	var old_seen: bool = MetaProgression.welcome_seen
	var old_completed: bool = MetaProgression.tutorial_completed
	var old_skipped: bool = MetaProgression.tutorial_skipped
	var old_matches: int = MetaProgression.matches_played
	MetaProgression.profile_loaded = true
	MetaProgression.welcome_seen = false
	MetaProgression.tutorial_completed = false
	MetaProgression.tutorial_skipped = false
	MetaProgression.matches_played = 0
	lobby.reparent(get_tree().root)
	await get_tree().process_frame
	lobby.call("_refresh_welcome_overlay")
	var welcome := lobby.get("welcome_overlay") as Control
	_check(welcome != null and bool(welcome.call("is_welcome_visible")), "new player sees the welcome card before a ban")

	_set_ban(true, "Нарушение правил")
	await get_tree().process_frame
	_check(not bool(welcome.call("is_welcome_visible")), "ban hides the welcome card")
	_check(lobby.call("is_moderation_ban_visible"), "ban card replaces the welcome card")
	# A profile refresh while banned must not bring Welcome back.
	lobby.call("_refresh_welcome_overlay")
	_check(not bool(welcome.call("is_welcome_visible")), "welcome stays hidden while banned")
	await _shot("ban_over_welcome")

	_set_ban(false, "")
	await get_tree().process_frame
	_check(not lobby.call("is_moderation_ban_visible"), "unban hides the ban card")
	_check(bool(welcome.call("is_welcome_visible")), "unban returns the welcome card for a new player")

	lobby.reparent(self)
	lobby.call("_refresh_welcome_overlay")
	if welcome != null:
		welcome.call("hide_overlay")
	MetaProgression.profile_loaded = old_loaded
	MetaProgression.welcome_seen = old_seen
	MetaProgression.tutorial_completed = old_completed
	MetaProgression.tutorial_skipped = old_skipped
	MetaProgression.matches_played = old_matches
	await get_tree().process_frame


func _check_ban_at_ready() -> void:
	_reset_moderation_state()
	NetworkClient.account_banned = true
	NetworkClient.account_ban_reason = "Ограничение при запуске"
	var fresh := (load("res://scenes/Lobby.tscn") as PackedScene).instantiate() as Control
	add_child(fresh)
	for i in 12:
		await get_tree().process_frame
	_check(fresh.call("is_moderation_ban_visible"), "already-banned account sees the card on lobby ready")
	var reason := fresh.get("moderation_ban_reason_label") as Label
	_check(reason != null and reason.text.contains("Ограничение при запуске"), "ready-time ban shows the stored reason")
	fresh.queue_free()
	_reset_moderation_state()
	await get_tree().process_frame


# --- helpers ---------------------------------------------------------------

func _set_ban(banned: bool, reason: String) -> void:
	NetworkClient.account_banned = banned
	NetworkClient.account_ban_reason = reason if banned else ""
	NetworkClient.account_ban_updated.emit(banned, NetworkClient.account_ban_reason)


func _set_warning(count: int, reason: String, at: int) -> void:
	NetworkClient.warning_count = count
	NetworkClient.last_warning_reason = reason
	NetworkClient.last_warning_at = at
	NetworkClient.warnings_updated.emit(count, reason, at)


func _reset_moderation_state() -> void:
	NetworkClient.account_banned = false
	NetworkClient.account_ban_reason = ""
	NetworkClient.warning_count = 0
	NetworkClient.last_warning_reason = ""
	NetworkClient.last_warning_at = 0


func _clear_warning_meta() -> void:
	for key in ["moderation_warning_seen_at", "moderation_generic_warning_shown"]:
		if get_tree().has_meta(key):
			get_tree().remove_meta(key)


func _seed_returning_player() -> void:
	NetworkClient.api_base_url = "http://127.0.0.1:9"
	MetaProgression.player_id = 424242
	MetaProgression.player_nickname = "Александр77"
	MetaProgression.profile_loaded = true
	MetaProgression.matches_played = 128
	MetaProgression.novice = false


func _count_buttons(root: Node) -> int:
	var count := 0
	for node in _collect(root):
		if node is Button:
			count += 1
	return count


func _collect_labels(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	for node in _collect(root):
		if node is Label:
			out.append(node as Label)
	return out


func _collect(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	for child in root.get_children():
		out.append_array(_collect(child))
	return out


func _shot(screen: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(LAYOUT_DIR)
	var image := get_viewport().get_texture().get_image()
	var path := "%s/moderation_%s_%s.png" % [LAYOUT_DIR, screen, tag]
	var error := image.save_png(path)
	if error != OK:
		failures += 1
		print("SHOT_FAIL ", screen, " ", error)
	else:
		print("SHOT ", screen, " ", image.get_size(), " ", path)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
