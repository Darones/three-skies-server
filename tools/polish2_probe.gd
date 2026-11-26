extends Node3D

## Shared polish probe for the combat / tutorial / results screens.
## Run: godot_console --path . tools/Polish2Probe.tscn -- --layout=844x390 --mobile --mode=all
##      godot_console --path . tools/Polish2Probe.tscn -- --layout=1440x734 --mode=all
## Modes: all, tutorial, hud, results. Frames: user://ui_shots/polish2_*.

var failures := 0
var out_dir := "user://ui_shots"
var viewport_size := Vector2.ZERO
var tag := ""


func _ready() -> void:
	var target := Vector2i(1440, 734)
	var force_mobile := false
	var mode := "all"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			var parts := arg.trim_prefix("--layout=").split("x")
			if parts.size() == 2:
				target = Vector2i(int(parts[0]), int(parts[1]))
		elif arg == "--mobile":
			force_mobile = true
		elif arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
	if force_mobile or target.x < 500:
		DeviceProfile.mobile_ui = true
		DeviceProfile.touch_controls = true
	if force_mobile:
		get_tree().root.content_scale_size = Vector2i(960, 540)
	else:
		get_tree().root.content_scale_size = target
	DisplayServer.window_set_size(target)
	for i in 3:
		await get_tree().process_frame
	viewport_size = get_viewport().get_visible_rect().size
	tag = "%dx%d" % [int(viewport_size.x), int(viewport_size.y)]
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("POLISH2 viewport=", viewport_size, " mobile=", DeviceProfile.mobile_ui,
		" mode=", mode, " tag=", tag)

	if mode == "all" or mode == "tutorial":
		await _run_tutorial()
	if mode == "all" or mode == "hud":
		await _run_hud()
	if mode == "all" or mode == "results":
		await _run_results()

	print("POLISH2_FAILURES=%d" % failures)
	print("POLISH2_DIR=", ProjectSettings.globalize_path(out_dir))
	get_tree().quit(0 if failures == 0 else 1)


func _run_tutorial() -> void:
	get_tree().set_meta("tutorial_mode", true)
	get_tree().set_meta("selected_class", HeroUnit.Cls.WARRIOR)
	get_tree().set_meta("selected_team", 0)
	var game := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	for i in 12:
		await get_tree().process_frame
	if String(game.get("state")) == "select":
		await game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	for i in 240:
		await get_tree().process_frame
		if String(game.get("state")) == "live" and game.get("tutorial_controller") != null:
			break
	var hud: Node = game.get("hud")
	var tutorial: Node = game.get("tutorial_controller")
	if hud == null or tutorial == null:
		_fail("tutorial hud/controller exist")
		return
	await get_tree().create_timer(0.35).timeout

	await _capture("tutorial_%s_welcome" % tag)
	_audit("welcome", hud)
	# Stop the automatic UI tour before it re-highlights the minimap in the
	# middle of the later screenshots; the tour itself is driven manually below.
	tutorial.set("stage", "collect_coins")
	hud.call("hide_tutorial_card")
	hud.call("hide_ui_highlight")
	await get_tree().process_frame

	# UI tour: minimap, skills, avatar. Each highlight is separate so the
	# strip text and the focus frame can be checked on their own.
	for entry in [
		["minimap", "Это миникарта: на ней видно союзников, врагов и осколок."],
		["skills", "Это ваши скиллы — кнопки 1, 2 и 3 справа."],
		["avatar", "Это меню: звук и настройки. Пауза в онлайне недоступна."],
	]:
		hud.call("show_ui_highlight", String(entry[0]), String(entry[1]))
		await get_tree().create_timer(0.35).timeout
		await _capture("tutorial_%s_tour_%s" % [tag, entry[0]])
		_audit("tour_%s" % entry[0], hud)
	hud.call("hide_ui_highlight")
	hud.call("hide_tutorial_card")

	# Stage cards with the real bodies from tutorial_controller.
	hud.call(
		"show_tutorial_card",
		"Этап 2/3 · Пара",
		"Теперь с тобой союзный бот. Примени второй навык и победи двух врагов — так ты научишься менять цель и отходить на базу.",
		"",
		Callable()
	)
	await get_tree().create_timer(0.3).timeout
	await _capture("tutorial_%s_card_pair" % tag)
	_audit("card_pair", hud)
	hud.call(
		"show_tutorial_card",
		"Финал · Оболочка",
		"Разбей Оболочку, забери Осколок и донеси его на базу. В обучении она не атакует.",
		"",
		Callable()
	)
	await get_tree().create_timer(0.3).timeout
	await _capture("tutorial_%s_card_shell" % tag)
	_audit("card_shell", hud)
	hud.call("hide_tutorial_card")

	# "НАЖМИ N" above the third ability.
	hud.call("set_tutorial_ability", 2)
	await get_tree().create_timer(0.3).timeout
	await _capture("tutorial_%s_press_hint" % tag)
	_audit("press_hint", hud)
	hud.call("set_tutorial_ability", -1)

	hud.call("show_tutorial_hint", "Собери 15 монет")
	await get_tree().create_timer(0.2).timeout
	await _capture("tutorial_%s_fountain_hint" % tag)
	_audit("fountain_hint", hud)

	# In-battle shop panel with the real tutorial item highlighted.
	game.call("clear_tutorial_target")
	hud.call("set_tutorial_shop_item", "wind_boots")
	hud.call("set_shop_open", true)
	await get_tree().create_timer(0.35).timeout
	print("POLISH2_SHOP state=", game.get("state"), " game_shop=", game.get("shop_open"),
		" panel=", (hud.get("shop_panel") as Control).visible,
		" panel_rect=", (hud.get("shop_panel") as Control).get_global_rect())
	await _capture("tutorial_%s_shop" % tag)
	_audit("shop", hud)
	hud.call("set_shop_open", false)
	hud.call("set_tutorial_shop_item", "")
	await get_tree().process_frame

	# Pause menu.
	hud.call("_open_pause_menu")
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture("tutorial_%s_pause" % tag)
	_audit("pause", hud)
	hud.call("_resume_game")
	await get_tree().process_frame

	# Final tutorial plate (buttons visible).
	hud.call("show_tutorial_hint", "")
	hud.call(
		"show_tutorial_victory",
		"Обучение пройдено!",
		"Ты прошёл дуэль, пару, команду и Оболочку.\nДальше — матчи с новичками и лёгкими ботами: первые бои щадящие, награды и опыт начисляются.",
		Callable(self, "_noop"),
		Callable(self, "_noop")
	)
	await get_tree().create_timer(0.3).timeout
	await _capture("tutorial_%s_victory" % tag)
	_audit("victory", hud)

	# Skip confirmation (two buttons).
	hud.call(
		"show_tutorial_choice",
		"Пропустить обучение?",
		"Ты сможешь посмотреть правила в лобби. Обучение можно пройти позже кнопкой «Обучение».",
		"Продолжить",
		Callable(self, "_noop"),
		"Пропустить",
		Callable(self, "_noop")
	)
	await get_tree().create_timer(0.3).timeout
	await _capture("tutorial_%s_skip_choice" % tag)
	_audit("skip_choice", hud)

	game.queue_free()
	await get_tree().process_frame


func _run_hud() -> void:
	get_tree().set_meta("tutorial_mode", false)
	get_tree().set_meta("selected_class", HeroUnit.Cls.FAIRY)
	get_tree().set_meta("selected_team", 0)
	var game := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	for i in 12:
		await get_tree().process_frame
	if String(game.get("state")) == "select":
		await game.call("start_match", HeroUnit.Cls.FAIRY, 0)
	for i in 240:
		await get_tree().process_frame
		if String(game.get("state")) == "live":
			break
	var hud: Node = game.get("hud")
	if hud == null:
		_fail("hud exists")
		return
	await get_tree().create_timer(0.6).timeout
	# A busy kill feed with long names to prove rows stay inside the panel.
	var feed := [
		["Даронес", "Сумрачный Клинок", 0, 1],
		["Лунная Тень", "Северный Ветер", 0, 1],
		["Искра", "Белый Ворон", 0, 1],
		["Пепел", "Даронес", 1, 0],
		["Тёмный Лис", "Сумрачный Клинок", 0, 1],
	]
	for row in feed:
		hud.call("show_kill_feed", String(row[0]), String(row[1]), int(row[2]), int(row[3]))
	await get_tree().create_timer(0.4).timeout
	await _capture("hud_%s_combat" % tag)
	_audit("hud_combat", hud)

	hud.call("set_shop_open", true)
	await get_tree().create_timer(0.35).timeout
	print("POLISH2_HUD_SHOP state=", game.get("state"), " game_shop=", game.get("shop_open"),
		" panel=", (hud.get("shop_panel") as Control).visible,
		" panel_rect=", (hud.get("shop_panel") as Control).get_global_rect())
	await _capture("hud_%s_shop" % tag)
	_audit("hud_shop", hud)
	hud.call("set_shop_open", false)
	await get_tree().process_frame

	hud.call("_open_pause_menu")
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture("hud_%s_pause" % tag)
	_audit("hud_pause", hud)
	hud.call("_resume_game")
	await get_tree().process_frame

	game.queue_free()
	await get_tree().process_frame


func _run_results() -> void:
	await _results_case("victory", true, 1, true, false, false)
	await _results_case("defeat", false, 5, false, false, false)
	await _results_case("aborted", false, 4, false, true, false)
	await _results_case("banner", true, 1, true, false, true)


func _results_case(shot: String, won: bool, place: int, mvp: bool, aborted: bool, banner: bool) -> void:
	get_tree().set_meta("last_match_won", won)
	get_tree().set_meta("last_match_score", [3, 1] if won else [1, 3])
	get_tree().set_meta("last_match_team", 0)
	get_tree().set_meta("last_match_place", place)
	get_tree().set_meta("last_match_is_mvp", mvp)
	get_tree().set_meta("last_match_aborted", aborted)
	get_tree().set_meta("last_match_room", 0)
	get_tree().set_meta("last_match_reason", "Время вышло" if not aborted else "Игрок покинул матч")
	get_tree().set_meta("selected_class", HeroUnit.Cls.FAIRY)
	get_tree().set_meta("last_match_stats", {
		"p_kills": 4, "p_deaths": 2, "p_damage": 3200, "p_crystals": 3,
		"p_shells_destroyed": 1, "p_coins_collected": 42,
		"p_gold_earned": 1850, "p_gold_spent": 900,
	})
	get_tree().set_meta("last_match_players", [
		{"name": "Даронес", "team": 0, "kills": 4, "deaths": 2, "damage": 3200, "crystals": 3, "is_player": true},
		{"name": "Тёмный Лис", "team": 0, "kills": 2, "deaths": 3, "damage": 1800, "crystals": 1, "is_player": false},
		{"name": "Искра", "team": 0, "kills": 1, "deaths": 4, "damage": 900, "crystals": 0, "is_player": false},
		{"name": "Северный Ветер", "team": 1, "kills": 3, "deaths": 2, "damage": 2400, "crystals": 1, "is_player": false},
		{"name": "Белый Ворон", "team": 1, "kills": 2, "deaths": 3, "damage": 1500, "crystals": 0, "is_player": false},
		{"name": "Пепел", "team": 1, "kills": 0, "deaths": 5, "damage": 600, "crystals": 0, "is_player": false},
	])
	var scene := (load("res://scenes/ResultsScreen.tscn") as PackedScene).instantiate()
	add_child(scene)
	for i in 20:
		await get_tree().process_frame
	if banner:
		scene.call("_show_reward_banner", "×2  НАГРАДЫ УДВОЕНЫ", 5.0)
		await get_tree().create_timer(0.6).timeout
	await _capture("results_%s_%s" % [tag, shot])
	_audit_results(shot, scene)
	if shot == "victory" or shot == "banner":
		scene.call("_switch_result_tab", true)
		for i in 4:
			await get_tree().process_frame
		await _capture("results_%s_%s_players" % [tag, shot])
		_audit_results("%s_players" % shot, scene)
	if aborted:
		var no_rewards := scene.find_child("NoRewards", true, false) as Label
		_check(no_rewards != null and no_rewards.visible, "aborted: «Награды не начислены» visible")
		if no_rewards != null:
			_check(no_rewards.text == "Награды не начислены", "aborted: no-rewards text")
	var title := scene.find_child("ResultTitle", true, false) as Label
	if title != null:
		var expected := "МАТЧ ПРЕРВАН" if aborted else ("ПОБЕДА" if won else "ПОРАЖЕНИЕ")
		_check(title.text == expected, "results title %s" % expected)
		_check_inside("results title", title)
	var button_row := scene.find_child("ActionButtons", true, false) as Control
	if button_row != null:
		_check_inside("results buttons", button_row)
	var content := scene.find_child("ResultsContent", true, false) as Control
	if content != null:
		_check_inside("results content", content)
	scene.queue_free()
	await get_tree().process_frame


func _audit_results(shot: String, scene: Node) -> void:
	var title := scene.find_child("ResultTitle", true, false) as Control
	var subtitle := scene.find_child("MatchSummary", true, false) as Control
	var placement := scene.find_child("PlayerPlacement", true, false) as Control
	var content := scene.find_child("ResultsContent", true, false) as Control
	if content != null:
		print("RESULTS_RECTS ", shot, " title=", title.get_global_rect() if title != null else Rect2(),
			" subtitle=", subtitle.get_global_rect() if subtitle != null else Rect2(),
			" placement=", placement.get_global_rect() if placement != null else Rect2(),
			" content=", content.get_global_rect())
	if title != null and subtitle != null:
		_no_overlap("results %s title/subtitle" % shot, title, subtitle)
	if subtitle != null and placement != null:
		_no_overlap("results %s subtitle/placement" % shot, subtitle, placement)
	if shot.begins_with("banner"):
		var banner := scene.find_child("RewardBanner", true, false) as Control
		if banner != null:
			_check_inside("results banner", banner)
			if placement != null:
				_no_overlap("results banner/placement", banner, placement)


func _audit(name: String, hud: Node) -> void:
	var hint := hud.get("tutorial_hint") as Control
	var card := hud.get("tutorial_card_panel") as Control
	var player := hud.get("player_panel") as Control
	var skip := hud.get("tutorial_skip_button") as Control
	var press := hud.get("tutorial_press_label") as Control
	var match_info := hud.get("match_info_box") as Control
	var gold := hud.get("gold_label") as Control
	if name == "welcome":
		_measure_player(hud)
		print("SKIP_RECT gold=", gold.get_global_rect() if gold != null else Rect2(),
			" skip=", skip.get_global_rect() if skip != null else Rect2(),
			" hint=", hint.get_global_rect() if hint != null else Rect2())
	if name == "hud_combat":
		_measure_player(hud)
	if hint != null and hint.visible:
		_check_inside("%s hint" % name, hint)
		if player != null and player.visible:
			_no_overlap("%s hint/player" % name, hint, player)
		if skip != null and skip.visible:
			_no_overlap("%s hint/skip" % name, hint, skip)
	if card != null and card.visible:
		_check_inside("%s card" % name, card)
		if skip != null and skip.visible:
			_no_overlap("%s card/skip" % name, card, skip)
	if press != null and press.visible:
		_check_inside("%s press hint" % name, press)
	if skip != null and skip.visible and gold != null and gold.visible and match_info != null:
		_no_overlap("%s gold/skip" % name, gold, skip)
	# Ability plates and the minimap must stay inside the screen.
	var abilities: Array = hud.get("ability_slots")
	for index in abilities.size():
		var slot := abilities[index] as Control
		if slot != null and slot.is_visible_in_tree():
			_check_inside("%s ability %d" % [name, index + 1], slot)
	var minimap := hud.get("minimap_control") as Control
	if minimap != null and minimap.is_visible_in_tree():
		_check_inside("%s minimap" % name, minimap)


func _measure_player(hud: Node) -> void:
	var panel := hud.get("player_panel") as Control
	var name_label := hud.get("player_name_label") as Label
	var team_label := hud.get("player_team_label") as Label
	var icon := hud.get("player_team_icon") as Control
	var portrait := hud.get("player_portrait") as Control
	if panel == null or name_label == null:
		return
	# The battle card is nickname + side + HP only.
	_check(portrait == null, "player card has no portrait")
	_check(not name_label.text.contains("·"),
		"player name has no class suffix (%s)" % name_label.text)
	var name_row := name_label.get_parent() as Control
	print("PLAYER_CARD panel=", panel.get_global_rect(),
		" portrait=", portrait.get_global_rect() if portrait != null else Rect2(),
		" name_row=", name_row.get_global_rect(),
		" name_rect=", name_label.get_global_rect(),
		" name_min=", name_label.get_combined_minimum_size(),
		" text_w=", name_label.get_theme_font("font").get_string_size(
			name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			name_label.get_theme_font_size("font_size")).x,
		" team_rect=", team_label.get_global_rect() if team_label != null else Rect2(),
		" team_min=", team_label.get_combined_minimum_size() if team_label != null else Vector2.ZERO,
		" icon=", icon.get_global_rect() if icon != null else Rect2())
	var overflow := name_label.get_global_rect().end.x > panel.get_global_rect().end.x - 8.0
	_check(not overflow, "player name fits card (name_end=%.1f card_end=%.1f)" % [
		name_label.get_global_rect().end.x, panel.get_global_rect().end.x,
	])


func _capture(shot: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("polish2_%s.png" % shot))
	print("POLISH2_SHOT ", shot)


func _check_inside(label: String, control: Control) -> void:
	var rect := control.get_global_rect()
	var ok := (
		rect.position.x >= -2.0
		and rect.position.y >= -2.0
		and rect.end.x <= viewport_size.x + 2.0
		and rect.end.y <= viewport_size.y + 2.0
	)
	_check(ok, "%s inside screen rect=%s" % [label, rect])


func _no_overlap(label: String, first: Control, second: Control) -> void:
	var a := first.get_global_rect()
	var b := second.get_global_rect()
	var overlap := a.intersects(b)
	_check(not overlap, "%s overlap a=%s b=%s" % [label, a, b])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _fail(label: String) -> void:
	failures += 1
	print("FAIL: ", label)


func _noop() -> void:
	pass
