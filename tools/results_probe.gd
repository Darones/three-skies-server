extends Node3D

# Снимает экран результатов боя: вкладка «Статистика» и вкладка «Игроки».
#
# Запуск:
#   godot --path . res://tools/ResultsProbe.tscn -- --layout=1440x734
#   godot --path . res://tools/ResultsProbe.tscn -- --layout=844x390 --mobile
#
# Скин охотницы в капюшоне надевается только в пробнике: сохранение игрока
# (loadout.cfg) не трогаем. С --save-docs картинки кладутся в docs/.

const DOC_SCREENSHOTS := {
	1440: "qa-results-skin-1440x734.png",
	844: "qa-results-skin-844x390.png",
}
const PROFILE_PATHS := ["user://meta_save.cfg", "user://stats.cfg", "user://loadout.cfg"]

var failures := 0
var _profile_backup: Dictionary = {}


func _ready() -> void:
	var target := Vector2i(1440, 734)
	var mobile_override := false
	var save_docs := false
	var class_index := int(HeroUnit.Cls.FAIRY)
	var skin_id := 2
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			var parts := arg.trim_prefix("--layout=").split("x")
			if parts.size() == 2:
				target = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("--class="):
			var names := {"warrior": 0, "mage": 1, "fairy": 2}
			class_index = int(names.get(arg.trim_prefix("--class="), class_index))
		elif arg.begins_with("--skin="):
			skin_id = clampi(int(arg.trim_prefix("--skin=")), 0, 2)
		elif arg == "--mobile" or arg == "--touch":
			mobile_override = true
		elif arg == "--save-docs":
			save_docs = true
	var mobile := mobile_override or target.x < 700
	if mobile:
		DeviceProfile.mobile_ui = true
		DeviceProfile.touch_controls = true
	get_tree().root.content_scale_size = target
	DisplayServer.window_set_size(target)
	for i in 3:
		await get_tree().process_frame
	_snapshot_profile()

	# A rewarded adapter is present, so the x2 button is part of the shot:
	# that button is what used to steal the last row of the table.
	var stub: PlatformAdapter = preload("res://tools/ad_stub.gd").new()
	Platform.adapter = stub
	Platform.platform_id = "vk"
	AdManager.begin_results()

	# Local-only profile: no profile request, no writes to loadout.cfg.
	MetaProgression.player_id = 0
	MetaProgression.player_nickname = "Даронес"
	MetaProgression.nickname_custom = true
	MetaProgression.char_levels = {"warrior": 7, "mage": 5, "fairy": 4}
	MetaProgression.equipped_skins = {"warrior": 0, "mage": 0, "fairy": 0}
	MetaProgression.equipped_skins[["warrior", "mage", "fairy"][class_index]] = skin_id

	get_tree().set_meta("last_match_won", true)
	get_tree().set_meta("last_match_score", [3, 1])
	get_tree().set_meta("last_match_team", 0)
	get_tree().set_meta("last_match_place", 1)
	get_tree().set_meta("last_match_is_mvp", true)
	get_tree().set_meta("selected_class", class_index)
	get_tree().set_meta("last_match_stats", {
		"p_kills": 4, "p_deaths": 2, "p_damage": 3200, "p_crystals": 3, "p_shells_destroyed": 1,
		"p_coins_collected": 42, "p_gold_earned": 1850, "p_gold_spent": 900,
	})
	get_tree().set_meta("last_match_players", [
		{"name": "Даронес", "team": 0, "kills": 4, "deaths": 2, "damage": 3200, "crystals": 3, "is_player": true},
		{"name": "Тёмный Лис", "team": 0, "kills": 2, "deaths": 3, "damage": 1800, "crystals": 1, "is_player": false},
		{"name": "Искра", "team": 0, "kills": 1, "deaths": 4, "damage": 900, "crystals": 0, "is_player": false},
		{"name": "Северный Ветер", "team": 1, "kills": 3, "deaths": 2, "damage": 2400, "crystals": 1, "is_player": false},
		{"name": "Белый Ворон", "team": 1, "kills": 2, "deaths": 3, "damage": 1500, "crystals": 0, "is_player": false},
		{"name": "Пепел", "team": 1, "kills": 0, "deaths": 5, "damage": 600, "crystals": 0, "is_player": false},
	])

	var packed := load("res://scenes/ResultsScreen.tscn") as PackedScene
	var scene := packed.instantiate()
	add_child(scene)
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var portrait := scene.find_child("HeroPortrait", true, false) as TextureRect
	var legendary := skin_id != 0
	_check(portrait != null and portrait.texture != null, "portrait has a texture")
	if portrait != null and portrait.texture != null:
		var path := portrait.texture.resource_path
		if legendary:
			_check(path.ends_with("_legend.webp"), "legendary portrait uses the shop card (%s)" % path)
			_check(portrait.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
				"shop card is shown whole, not cropped")
		else:
			_check(path.contains("keyart"), "ordinary class keeps its key art (%s)" % path)
	var badge := scene.find_child("LegendBadge", true, false)
	# The owner removed the tiny gold «ЛЕГЕНДА» caption: the skin card itself
	# carries the look. The probe now guards the removal — no badge node and no
	# caption text anywhere on the screen, for legendary and ordinary skins.
	_check(badge == null, "no LegendBadge node under the portrait")
	var captions := _legend_caption_labels(scene)
	_check(captions.is_empty(), "no «ЛЕГЕНДА» caption text on the results screen")

	# Bot names arrive already prefixed from game/server. The table row must not
	# add a second "БОТ · " ("БОТ · БОТ 1234") and must still prefix bare names.
	var callsign_row := scene.call("_make_player_row",
		{"name": "БОТ 1234", "team": 0, "is_bot": true, "damage": 10}, 0) as Control
	var callsign_labels := _all_labels(callsign_row)
	var callsign_name := callsign_labels[0].text if not callsign_labels.is_empty() else ""
	_check(callsign_name.count("БОТ") == 1,
		"bot callsign keeps a single БОТ in the results table (%s)" % callsign_name)
	var bare_row := scene.call("_make_player_row",
		{"name": "Тест", "team": 0, "is_bot": true, "damage": 10}, 0) as Control
	var bare_labels := _all_labels(bare_row)
	var bare_name := bare_labels[0].text if not bare_labels.is_empty() else ""
	_check(bare_name == "БОТ · Тест",
		"unprefixed bot still gets the results prefix (%s)" % bare_name)

	var lobby_button := scene.find_child("MenuButton", true, false) as Button
	_check(lobby_button != null and lobby_button.visible, "lobby button exists")
	if lobby_button != null:
		var portrait_panel := scene.find_child("PortraitPanel", true, false) as Control
		_check(portrait_panel != null
			and lobby_button.get_global_rect().position.x < portrait_panel.get_global_rect().end.x
			and lobby_button.get_global_rect().position.y > portrait_panel.get_global_rect().position.y,
			"lobby button sits under the portrait in the left column")

	scene.call("_switch_result_tab", true)
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var players_scroll := scene.get("players_scroll") as ScrollContainer
	_check(players_scroll != null and players_scroll.visible, "players tab is open")
	if players_scroll != null:
		var body := players_scroll.get_node_or_null("PlayersMargin/PlayersContent") as Control
		var fits := body != null and body.get_combined_minimum_size().y <= players_scroll.size.y + 0.5
		if mobile:
			print("NOTE mobile table fits=%s mode=%d" % [fits, players_scroll.vertical_scroll_mode])
		else:
			_check(fits, "all six players fit without scrolling")
			_check(players_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
				"desktop players table has no vertical scroll")

	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	image.save_png("user://ui_shots/results_players_%dx%d.png" % [target.x, target.y])
	scene.call("_switch_result_tab", false)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		"user://ui_shots/results_stats_%dx%d.png" % [target.x, target.y])

	if save_docs:
		var doc_name: String = DOC_SCREENSHOTS.get(target.x, "")
		if doc_name.is_empty():
			doc_name = "qa-results-skin-%dx%d.png" % [target.x, target.y]
		var doc_path := ProjectSettings.globalize_path("res://docs/%s" % doc_name)
		DirAccess.make_dir_recursive_absolute(doc_path.get_base_dir())
		image.save_png(doc_path)
		print("SAVED ", doc_path)

	print("RESULTS_PROBE_FAILURES=%d" % failures)
	_restore_profile()
	print("RESULTS_PROBE_DONE")
	get_tree().quit(1 if failures > 0 else 0)


## The results screen records a match and awards XP on _ready. The probe must
## not leave that in the player's profile: keep the save files as they were.
func _snapshot_profile() -> void:
	_profile_backup.clear()
	for path in PROFILE_PATHS:
		if FileAccess.file_exists(path):
			_profile_backup[path] = FileAccess.get_file_as_bytes(path)


func _restore_profile() -> void:
	for path in PROFILE_PATHS:
		if not _profile_backup.has(path):
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_profile_backup[path])
			file.close()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


## The caption is gone from the game (owner: "its almost invisible"). Match the
## exact caption only: "ЛЕГЕНДАРНОЕ" is a weapon rarity and must not count.
func _legend_caption_labels(node: Node) -> Array[Label]:
	var found: Array[Label] = []
	for label in _all_labels(node):
		if _is_legend_caption(label.text):
			found.append(label)
	return found


func _all_labels(node: Node) -> Array[Label]:
	var labels: Array[Label] = []
	if node is Label:
		labels.append(node as Label)
	for child in node.get_children():
		labels.append_array(_all_labels(child))
	return labels


func _is_legend_caption(text: String) -> bool:
	return text.replace("◆", " ").strip_edges().to_upper() == "ЛЕГЕНДА"
