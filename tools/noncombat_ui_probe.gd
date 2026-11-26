extends Node3D

## Non-combat UI polish probe.
##
## Run with the real layouts:
##   godot_console --path . tools/NonCombatUiProbe.tscn -- --layout=844x390 --mobile
##   godot_console --path . tools/NonCombatUiProbe.tscn -- --layout=1440x734
##
## Mobile uses the real game canvas (DeviceProfile.MOBILE_CONTENT_SCALE =
## 960x540) with a 844x390 window, which gives the true 1168x540 logical
## viewport. Desktop uses 1440x734.
##
## Saves frames to user://ui_shots/polish_<screen>_<tag>.png and prints a
## short geometry report (out-of-screen controls, clipped labels) to make
## layout regressions visible without opening every image.

const LAYOUT_DIR := "user://ui_shots"

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

	_seed_returning_player()
	lobby = (load("res://scenes/Lobby.tscn") as PackedScene).instantiate() as Control
	add_child(lobby)
	for i in 20:
		await get_tree().process_frame
	MetaProgression.profile_loaded = true
	lobby.call("_refresh_shop")
	lobby.call("_refresh_player_menu")

	await _capture_lobby()
	await _capture_inventory()
	await _capture_nickname()
	await _capture_rename_confirm()
	await _capture_report()
	await _capture_shop()
	await _capture_settings()
	await _capture_rules()

	print("NONCOMBAT_UI_FAILURES=%d" % failures)
	print("NONCOMBAT_UI_DIR=", ProjectSettings.globalize_path(LAYOUT_DIR))
	get_tree().quit(1 if failures > 0 else 0)


func _seed_returning_player() -> void:
	# A returning player with enough goods to fill every list. The API points
	# at a closed local port so the probe never touches the live server and
	# never creates a profile.
	NetworkClient.api_base_url = "http://127.0.0.1:9"
	MetaProgression.player_id = 424242
	MetaProgression.player_nickname = "Александр77"
	MetaProgression.nickname_custom = true
	MetaProgression.profile_loaded = true
	MetaProgression.sky_shards = 195321
	MetaProgression.account_level = 7
	MetaProgression.matches_played = 128
	MetaProgression.char_levels = {"warrior": 7, "mage": 5, "fairy": 4}
	MetaProgression.char_xps = {"warrior": 650, "mage": 210, "fairy": 0}
	MetaProgression.unlocked_weapons.assign([1, 2, 3, 4, 5, 6, 7, 8, 9, 101, 102])
	MetaProgression.equipped_weapons = {"warrior": 4, "mage": 3, "fairy": 2}
	MetaProgression.equipped_skins = {"warrior": 1, "mage": 0, "fairy": 0}
	MetaProgression.stats_all = {
		"matches": 128, "wins": 77, "kills": 12345, "deaths": 3210,
		"damage": 1234567, "shells": 89, "crystals": 45,
		"xp": 9876543, "shards": 54321,
	}
	MetaProgression.stats_session = {
		"matches": 3, "wins": 2, "kills": 41, "deaths": 9,
		"damage": 98765, "shells": 4, "crystals": 2, "xp": 4321, "shards": 120,
	}
	MetaProgression.stats_last = {
		"won": true, "place": 1, "kills": 12, "deaths": 4,
		"damage": 45678, "shells": 2, "crystals": 1, "xp": 2310, "shards": 75,
	}


func _capture_lobby() -> void:
	for i in 6:
		await get_tree().process_frame
	await _shot("lobby")
	_check_visible_tree(lobby, "lobby")


func _capture_inventory() -> void:
	lobby.call("_open_player_menu")
	for i in 8:
		await get_tree().process_frame
	await _shot("inventory")
	_check_visible_tree(lobby.get("player_menu_panel") as Control, "inventory")
	var inventory_scroll := (lobby.get("player_menu_panel") as Control).find_child("InventoryScroll", true, false) as ScrollContainer
	if inventory_scroll != null:
		inventory_scroll.scroll_vertical = 100000
		for i in 5:
			await get_tree().process_frame
		await _shot("inventory_bottom")
		inventory_scroll.scroll_vertical = 0


func _capture_nickname() -> void:
	lobby.call("_open_nickname_popup")
	for i in 4:
		await get_tree().process_frame
	# The on-screen keyboard is an overlay by design; hide it to inspect the
	# popup itself, then restore the normal state.
	var keyboard := lobby.get_node_or_null("TouchKeyboard")
	if keyboard != null:
		keyboard.call("close")
	for i in 3:
		await get_tree().process_frame
	await _shot("nickname")
	_check_visible_tree(lobby.get("nickname_popup_overlay") as Control, "nickname")
	lobby.call("_close_nickname_popup")


func _capture_rename_confirm() -> void:
	lobby.call("_open_rename_confirm", "Александр77")
	for i in 4:
		await get_tree().process_frame
	await _shot("rename_confirm")
	_check_visible_tree(lobby.get("rename_confirm_overlay") as Control, "rename_confirm")
	lobby.call("_close_rename_confirm")


func _capture_report() -> void:
	lobby.call("_open_report_form")
	for i in 4:
		await get_tree().process_frame
	var keyboard := lobby.get_node_or_null("TouchKeyboard")
	if keyboard != null:
		keyboard.call("close")
	for i in 3:
		await get_tree().process_frame
	await _shot("report")
	_check_visible_tree(lobby.get("report_overlay") as Control, "report")
	lobby.call("_close_report_form")
	lobby.call("_close_player_menu")


func _capture_shop() -> void:
	lobby.call("_open_shard_shop")
	lobby.call("_select_shop_hero", 0)
	for i in 6:
		await get_tree().process_frame
	await _shot("shop_fairy")
	_check_visible_tree(lobby.get("shop_panel") as Control, "shop_fairy")
	lobby.call("_change_shop_page", 1)
	for i in 5:
		await get_tree().process_frame
	await _shot("shop_fairy_p2")
	_check_visible_tree(lobby.get("shop_panel") as Control, "shop_fairy_p2")
	lobby.call("_select_shop_hero", 2)
	for i in 5:
		await get_tree().process_frame
	await _shot("shop_warrior")
	_check_visible_tree(lobby.get("shop_panel") as Control, "shop_warrior")
	lobby.call("_change_shop_page", 1)
	for i in 5:
		await get_tree().process_frame
	await _shot("shop_warrior_p2")
	lobby.call("_select_shop_hero", 1)
	for i in 5:
		await get_tree().process_frame
	await _shot("shop_mage")
	_check_visible_tree(lobby.get("shop_panel") as Control, "shop_mage")
	lobby.call("_open_topup_panel")
	for i in 5:
		await get_tree().process_frame
	await _shot("topup_standalone")
	_check_visible_tree(lobby.get("topup_panel") as Control, "topup_standalone")
	# Reveal the real purchase rows for the VK/OK look (standalone hides them).
	_show_topup_purchase_rows()
	for i in 4:
		await get_tree().process_frame
	lobby.call("_fit_topup_panel")
	for i in 2:
		await get_tree().process_frame
	await _shot("topup_full")
	_check_visible_tree(lobby.get("topup_panel") as Control, "topup_full")
	lobby.call("_close_topup_panel")
	lobby.call("_close_shard_shop")


func _show_topup_purchase_rows() -> void:
	var top := lobby.get("topup_panel") as Control
	if top == null:
		return
	for property in ["shards_slider", "amount_row", "price_label", "pay_button"]:
		var control := top.get(property) as Control
		if control != null:
			control.visible = true
	var hint := top.get("hint_label") as Label
	if hint != null:
		hint.text = "Сколько нужно?"
	top.call("_update_display")


func _capture_settings() -> void:
	lobby.call("_open_settings")
	var settings := lobby.get("settings_panel") as Control
	for i in 8:
		await get_tree().process_frame
	await _shot("settings")
	_check_visible_tree(settings, "settings")
	var settings_scroll := settings.find_child("SettingsScroll", true, false) as ScrollContainer
	if settings_scroll != null:
		settings_scroll.scroll_vertical = 100000
		for i in 5:
			await get_tree().process_frame
		await _shot("settings_bottom")
		settings_scroll.scroll_vertical = 0
	settings.call("_open_credits")
	for i in 5:
		await get_tree().process_frame
	await _shot("credits")
	_check_visible_tree(settings.get("credits_overlay") as Control, "credits")
	settings.call("_close_credits")
	lobby.call("_close_settings")


func _capture_rules() -> void:
	lobby.call("_open_rules")
	var panel := lobby.get("rules_panel") as Control
	for i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	await _shot("rules")
	_check_visible_tree(panel, "rules")
	var rules_scroll := panel.find_child("RulesScroll", true, false) as ScrollContainer
	if rules_scroll != null:
		rules_scroll.scroll_vertical = 100000
		for i in 5:
			await get_tree().process_frame
		await _shot("rules_bottom")
		rules_scroll.scroll_vertical = 0
	lobby.call("_close_rules")


func _shot(screen: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(LAYOUT_DIR)
	var image := get_viewport().get_texture().get_image()
	var path := "%s/polish_%s_%s.png" % [LAYOUT_DIR, screen, tag]
	var error := image.save_png(path)
	if error != OK:
		failures += 1
		print("SHOT_FAIL ", screen, " ", error)
	else:
		print("SHOT ", screen, " ", image.get_size(), " ", path)


func _check_visible_tree(root: Control, screen: String) -> void:
	if root == null:
		return
	var view := get_viewport().get_visible_rect().size
	var controls: Array[Control] = []
	_collect_controls(root, controls)
	for control in controls:
		if not control.is_visible_in_tree():
			continue
		# Content inside a ScrollContainer is intentionally clipped at the
		# viewport edge; only the scroll frame itself must stay on screen.
		if _inside_scroll(control):
			continue
		if control is Label or control is Button:
			var rect := control.get_global_rect()
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue
			if rect.position.x < -1.0 or rect.position.y < -1.0 \
				or rect.end.x > view.x + 1.0 or rect.end.y > view.y + 1.0:
				print("OUTSIDE %s %s %s rect=%s view=%s" % [
					screen, control.get_class(), control.name, rect, view])
				failures += 1
		if control is Label:
			var label := control as Label
			if label.text.is_empty() or label.clip_text or label.autowrap_mode != TextServer.AUTOWRAP_OFF:
				continue
			var min_width := label.get_minimum_size().x
			if min_width > label.size.x + 2.0:
				print("CLIPPED %s label=%s text=%s min=%.1f size=%.1f" % [
					screen, label.name, label.text.substr(0, 24), min_width, label.size.x])
				failures += 1


func _collect_controls(node: Node, out: Array[Control]) -> void:
	if node is Control:
		out.append(node as Control)
	for child in node.get_children():
		_collect_controls(child, out)


func _inside_scroll(control: Control) -> bool:
	var node := control.get_parent()
	while node != null:
		if node is ScrollContainer:
			return true
		node = node.get_parent()
	return false
