extends Node3D

## Shop/skin QA probe (26.11.2026).
##
## Checks the enlarged shop cards and the 2D skin card in the lobby avatar, and
## guards that the removed gold ЛЕГЕНДА caption stays gone. Prints geometry for
## every card and saves frames:
##   godot_console --path . tools/ShopSkinProbe.tscn -- --layout=1440x734
##   godot_console --path . tools/ShopSkinProbe.tscn -- --layout=844x390 --mobile

const OUT_DIR := "user://ui_shots"

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

	NetworkClient.api_base_url = "http://127.0.0.1:9"
	MetaProgression.player_id = 424242
	MetaProgression.player_nickname = "Александр77"
	MetaProgression.nickname_custom = true
	MetaProgression.profile_loaded = true
	MetaProgression.sky_shards = 195321
	MetaProgression.matches_played = 128
	MetaProgression.novice = false
	MetaProgression.char_levels = {"warrior": 7, "mage": 5, "fairy": 4}
	MetaProgression.unlocked_weapons.assign([1, 2, 3, 4, 5, 6, 7, 8, 9, 101, 102])
	MetaProgression.equipped_weapons = {"warrior": 4, "mage": 3, "fairy": 2}
	# Fairy wears the hunter skin so the lobby avatar must show its card; the
	# gold ЛЕГЕНДА caption was removed and must not come back.
	MetaProgression.equipped_skins = {"warrior": 1, "mage": 0, "fairy": 2}

	lobby = (load("res://scenes/Lobby.tscn") as PackedScene).instantiate() as Control
	add_child(lobby)
	for i in 20:
		await get_tree().process_frame
	lobby.set("selected_class", 2)
	lobby.call("_refresh_selection")
	MetaProgression.profile_loaded = true
	for i in 5:
		await get_tree().process_frame

	_check_lobby_avatar()
	await _shot("qa_shop_skins_lobby_" + tag)

	lobby.call("_open_shard_shop")
	for i in 4:
		await get_tree().process_frame
	for hero_index in [0, 1, 2]:
		lobby.call("_select_shop_hero", hero_index)
		for i in 4:
			await get_tree().process_frame
		_report_cards(hero_index)
		await _shot("qa_shop_cards_h%d_%s" % [hero_index, tag])

	print("SHOP_SKIN_FAILURES=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check_lobby_avatar() -> void:
	var avatar := lobby.get("avatar") as TextureRect
	_check(avatar != null and avatar.texture != null, "lobby avatar has a texture")
	if avatar != null:
		var tex := avatar.texture
		print("AVATAR rect=", avatar.get_global_rect(), " tex=", tex.get_size(),
			" path=", tex.resource_path)
		_check(tex.resource_path.contains("ui/skins/"),
			"lobby avatar uses the SkinCatalog card, not the icon")
		var frame := avatar.get_parent().get_parent() as Control
		print("AVATAR_FRAME rect=", frame.get_global_rect() if frame != null else Rect2())
		if frame != null:
			var rect := frame.get_global_rect()
			var area := avatar.get_parent_control().get_global_rect()
			_check(rect.encloses(area), "skin card fits inside the avatar plate")
		# The card art alone marks a legendary skin now: the caption lived in
		# the avatar stack, so the check runs even if the plate layout changes.
		_check(_legend_caption_labels(avatar.get_parent()).is_empty(),
			"no ЛЕГЕНДА caption on the lobby avatar")


func _report_cards(hero_index: int) -> void:
	var panel := lobby.get("shop_panel") as Control
	var row := lobby.get("shop_cards_row") as Control
	print("--- hero tab ", hero_index, " ---")
	print("PANEL rect=", panel.get_global_rect())
	print("ROW rect=", row.get_global_rect(), " children=", row.get_child_count())
	var index := 0
	for child in row.get_children():
		if not (child is PanelContainer):
			continue
		var card := child as Control
		var image := card.find_child("ShopCardImage", true, false) as Control
		var preview: TextureRect = null
		var image_rect := Rect2()
		var tex_size := Vector2.ZERO
		if image != null:
			image_rect = image.get_global_rect()
			for node in image.get_children():
				if node is TextureRect:
					preview = node as TextureRect
					break
			if preview != null and preview.texture != null:
				tex_size = preview.texture.get_size()
		print("CARD", index, " name=", card.name, " rect=", card.get_global_rect(),
			" image=", image_rect, " tex=", tex_size)
		var card_rect := card.get_global_rect()
		_check(panel.get_global_rect().encloses(card_rect),
			"card %d stays inside the shop panel" % index)
		if image != null:
			_check(card_rect.encloses(image_rect),
				"card %d image stays inside the card" % index)
			_check(image_rect.size.x >= 0.82 * card_rect.size.x,
				"card %d image uses at least 82%% of the card width" % index)
		# No «ЛЕГЕНДА» tag on the art, and the skin line stays a plain "Скин".
		_check(_legend_caption_labels(card).is_empty(),
			"card %d has no ЛЕГЕНДА caption" % index)
		for label in _all_labels(card):
			var text := label.text.strip_edges()
			if text.begins_with("Скин"):
				_check(not text.to_lower().contains("легенд"),
					"card %d skin line names no tier" % index)
		index += 1
	_check(index == 3, "three cards per row on tab %d" % hero_index)


func _all_labels(node: Node) -> Array[Label]:
	var labels: Array[Label] = []
	if node is Label:
		labels.append(node as Label)
	for child in node.get_children():
		labels.append_array(_all_labels(child))
	return labels


## The caption is gone from the game (owner: "its almost invisible"). Match the
## exact caption only: "ЛЕГЕНДАРНОЕ" is a weapon rarity and must not count.
func _legend_caption_labels(node: Node) -> Array[Label]:
	var found: Array[Label] = []
	for label in _all_labels(node):
		if _is_legend_caption(label.text):
			found.append(label)
	return found


func _is_legend_caption(text: String) -> bool:
	return text.replace("◆", " ").strip_edges().to_upper() == "ЛЕГЕНДА"


func _shot(screen_name: String) -> void:
	for i in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, screen_name]
	var error := image.save_png(path)
	if error != OK:
		failures += 1
		print("SHOT_FAIL ", screen_name, " ", error)
	else:
		print("SHOT ", screen_name, " ", image.get_size(), " ", path)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
