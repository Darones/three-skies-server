extends Node3D

## Проба дизайна «Quest cards» (вариант A).
##
## godot_console --path . tools/DailyQuestsProbe.tscn -- --layout=1440x734
## godot_console --path . tools/DailyQuestsProbe.tscn -- --layout=844x390 --mobile

var _fail := 0
var _pass := 0

## Philosopher has no U+2713/U+2714/U+25C6/U+21BB and the web build has no
## fallback font: these render as tofu. Draw such marks instead.
const BANNED_GLYPHS := ["\u2713", "\u2714", "\u25C6", "\u21BB", "\u2717"]


func _ready() -> void:
	var target := Vector2i(1440, 734)
	var force_mobile := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			var parts := arg.trim_prefix("--layout=").split("x")
			if parts.size() == 2:
				target = Vector2i(int(parts[0]), int(parts[1]))
		elif arg == "--mobile":
			force_mobile = true
	if force_mobile or target.x < 500:
		DeviceProfile.mobile_ui = true
		DeviceProfile.touch_controls = true
	get_tree().root.content_scale_size = target
	DisplayServer.window_set_size(target)
	for i in 3:
		await get_tree().process_frame
	NetworkClient.api_base_url = "http://127.0.0.1:9"
	var scene := load("res://scenes/Lobby.tscn") as PackedScene
	if scene == null:
		print("DAILY_QUESTS_RESULT=FAIL lobby scene missing")
		get_tree().quit(1)
		return
	var lobby := scene.instantiate()
	add_child(lobby)
	for i in 10:
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	for signal_name in ["profile_updated", "profile_failed"]:
		var callback := Callable(
			lobby,
			"_on_profile_updated" if signal_name == "profile_updated" else "_on_profile_failed"
		)
		if MetaProgression.is_connected(signal_name, callback):
			MetaProgression.disconnect(signal_name, callback)
	var welcome: Variant = lobby.get("welcome_overlay")
	if welcome is Control:
		(welcome as Control).visible = false

	print("DAILY_QUESTS viewport=", viewport_size(), " mobile=", DeviceProfile.mobile_ui)
	if DeviceProfile.mobile_ui:
		await _check_mobile(lobby)
	else:
		await _check_desktop(lobby)

	print("DAILY_QUESTS checks pass=%d fail=%d" % [_pass, _fail])
	print("DAILY_QUESTS_RESULT=", "PASS" if _fail == 0 else "FAIL")
	print("DAILY_QUESTS_DIR=", ProjectSettings.globalize_path("user://ui_shots"))
	get_tree().quit(0 if _fail == 0 else 1)


func _check_desktop(lobby: Node) -> void:
	var inline := lobby.get("daily_quests_panel") as Control
	var overlay := lobby.get("daily_quests_overlay") as Control
	_check(inline != null and overlay != null, "desktop: inline и overlay созданы")
	if inline == null or overlay == null:
		return
	for layout in [Vector2i(1280, 720), Vector2i(1440, 734), Vector2i(1920, 1080)]:
		get_tree().root.content_scale_size = layout
		DisplayServer.window_set_size(layout)
		for i in 4:
			await get_tree().process_frame
		lobby.call("_layout_lobby_layout")
		inline.call("apply_data", _fixture(3, 1, 5, "free"))
		await get_tree().create_timer(0.3).timeout
		await _check_inline(lobby, inline, "%dx%d" % [layout.x, layout.y])
		_check_cards(lobby, "%dx%d" % [layout.x, layout.y])

	# Оверлей открывается кликом по таблице.
	var open_button := inline.find_child("DailyQuestsOpenButton", true, false) as Button
	_check(open_button != null, "desktop: прозрачная кнопка на таблице")
	if open_button != null:
		_check(
			_near(open_button.size.x, inline.size.x, 1.0)
				and _near(open_button.size.y, inline.size.y, 1.0),
			"desktop: кнопка покрывает всю таблицу"
		)
		open_button.emit_signal("pressed")
	await get_tree().create_timer(0.2).timeout
	_check(overlay.visible, "desktop: клик по таблице открыл меню")
	overlay.call("apply_data", _fixture(3, 1, 5, "free"))
	await get_tree().create_timer(0.55).timeout
	await _check_overlay(overlay, "1440x734", true)
	await _save_shot("daily_quests_overlay_premium_1440x734")

	var close_button := overlay.find_child("DailyQuestsClose", true, false) as Button
	if close_button != null:
		close_button.emit_signal("pressed")
		await get_tree().create_timer(0.1).timeout
		_check(not overlay.visible, "desktop: крестик закрывает меню")
	await _save_shot("daily_quests_desktop_%dx%d" % [int(viewport_size().x), int(viewport_size().y)])


func _check_inline(lobby: Node, inline: Control, tag: String) -> void:
	var view := get_viewport().get_visible_rect().size
	var origin := (lobby as Control).get_global_rect().position
	var rect := _local_rect(inline, origin)
	var profile := lobby.get("profile_button") as Control
	var play := lobby.get("play_button") as Control
	var profile_bottom := profile.get_global_rect().end.y - origin.y
	var play_top := play.get_global_rect().position.y - origin.y
	_check(_near(rect.position.x, 28.0), "%s: таблица left 28" % tag)
	_check(_near(rect.size.x, 300.0, 0.75), "%s: таблица width 300 (%.1f)" % [tag, rect.size.x])
	_check(_near(rect.end.x, 328.0, 0.75), "%s: правый край 328 (%.1f)" % [tag, rect.end.x])
	_check(_near(rect.size.y, 246.0), "%s: таблица height 246" % tag)
	var available_height := play_top - profile_bottom
	var gap := maxf(16.0, (available_height - rect.size.y) * 0.5)
	var expected_top := profile_bottom + gap
	_check(
		_near(rect.position.y, expected_top, 2.0),
		"%s: таблица по центру между профилем и ИГРАТЬ (%.1f vs %.1f)" % [
			tag, rect.position.y, expected_top
		]
	)
	_check(
		_near(rect.position.y - profile_bottom, play_top - rect.end.y, 2.0),
		"%s: отступы сверху/снизу равны" % tag
	)
	_check(
		rect.position.y >= profile_bottom + 16.0 - 0.75
			and rect.end.y <= play_top - 16.0 + 0.75,
		"%s: таблица не пересекает профиль/ИГРАТЬ" % tag
	)
	var open_button := inline.find_child("DailyQuestsOpenButton", true, false) as Button
	_check(
		open_button != null and _near(open_button.size.x, inline.size.x, 1.0)
			and _near(open_button.size.y, inline.size.y, 1.0),
		"%s: кнопка открытия покрывает таблицу" % tag
	)
	# 0/1/2/3 задания: высота меняется, низ остаётся над кнопками.
	for count in [0, 1, 2, 3]:
		inline.call("apply_data", _fixture(count, 0, 0, "free"))
		await get_tree().create_timer(0.32).timeout
		var current := _local_rect(inline, origin)
		var count_gap := maxf(16.0, (available_height - current.size.y) * 0.5)
		var exp_top := profile_bottom + count_gap
		_check(
			_near(current.position.y, exp_top, 2.0),
			"%s: %d задания — top по центру (%.1f vs %.1f)" % [
				tag, count, current.position.y, exp_top
			]
		)
		_check(
			_near(current.position.y - profile_bottom, play_top - current.end.y, 2.0),
			"%s: %d задания — равные отступы" % [tag, count]
		)
		_check(
			_near(current.end.x, 328.0, 0.75) and _near(current.size.x, 300.0, 0.75),
			"%s: %d задания — ширина 300" % [tag, count]
		)
		_check(
			current.end.y <= play_top - 16.0 + 1.0
				and current.position.y >= profile_bottom + 16.0 - 0.75,
			"%s: %d задания без пересечений" % [tag, count]
		)
	inline.call("apply_data", _fixture(3, 1, 5, "free"))
	await get_tree().create_timer(0.32).timeout
	var rows: Array = inline.get("row_nodes")
	_check(rows.size() == 3, "%s: 3 строки inline" % tag)
	_check(_banned_glyphs(inline).is_empty(),
		"%s: inline без текстовых галок %s" % [tag, str(_banned_glyphs(inline))])
	for i in rows.size():
		var row := rows[i] as Control
		_check(_near(row.size.y, 50.0), "%s: строка %d = 50 px" % [tag, i])
		_check(
			row.find_child("DailyQuestsReroll*", true, false) == null,
			"%s: в inline нет кнопки замены" % tag
		)
		_check(
			row.find_child("DailyQuestsIcon%d" % i, true, false) != null,
			"%s: медальон строки %d" % [tag, i]
		)
		_check(
			row.find_child("DailyQuestsRewardIcon%d" % i, true, false) != null
				and row.find_child("DailyQuestsReward%d" % i, true, false) != null,
			"%s: чип награды строки %d" % [tag, i]
		)

	# Inline-футер: 7 точек, X/7, 300; без кнопки «Забрать».
	var table_now := _local_rect(inline, origin)
	var footer := inline.find_child("DailyQuestsFooter", true, false) as Control
	_check(footer != null and footer.visible, "%s: inline футер виден" % tag)
	var footer_controls: Array = []
	var diamonds_ok := true
	for i in 7:
		var diamond := inline.find_child("DailyQuestsDay%d" % i, true, false) as Control
		if diamond == null or not diamond.visible or diamond.find_child("DiamondOuter", true, false) == null:
			diamonds_ok = false
			continue
		var dr := diamond.get_global_rect()
		var local_dr := Rect2(dr.position - origin, dr.size)
		if not table_now.encloses(local_dr):
			diamonds_ok = false
		footer_controls.append(local_dr)
	_check(diamonds_ok, "%s: 7 нарисованных ромбов внутри 300 px" % tag)
	var week_inline := inline.get("week_label") as Label
	_check(
		week_inline != null and week_inline.visible and week_inline.text.contains("/7"),
		"%s: inline X/7" % tag
	)
	var inline_chip := inline.find_child("DailyQuestsRewardChip", true, false) as Control
	_check(inline_chip != null and inline_chip.visible, "%s: inline чип 300" % tag)
	var inline_claim := inline.get("claim_button") as Button
	_check(inline_claim != null and not inline_claim.visible, "%s: «Забрать» в inline скрыт" % tag)
	if week_inline != null:
		var wr := week_inline.get_global_rect()
		footer_controls.append(Rect2(wr.position - origin, wr.size))
	if inline_chip != null:
		var cr := inline_chip.get_global_rect()
		footer_controls.append(Rect2(cr.position - origin, cr.size))
	var footer_hits: Array = []
	for a in footer_controls.size():
		var ra: Rect2 = footer_controls[a]
		if not table_now.encloses(ra):
			footer_hits.append("outside%d" % a)
		for b in footer_controls.size():
			if b > a and ra.intersects(footer_controls[b] as Rect2):
				footer_hits.append("%d-%d" % [a, b])
	_check(footer_hits.is_empty(), "%s: inline футер без наездов %s" % [tag, str(footer_hits)])

	# Нет пересечений с карточками/логотипом/кнопками.
	var blockers: Array = [lobby.get("lobby_logo"), lobby.get("play_button"),
		lobby.get("tutorial_button"), lobby.get("settings_button"), lobby.get("rules_button"),
		lobby.get("profile_button")]
	var cards: Array = lobby.get("cards")
	for card in cards:
		blockers.append(card)
	var hits: Array = []
	for blocker in blockers:
		if blocker is Control and (blocker as Control).visible and rect.intersects(
			(blocker as Control).get_global_rect()
		):
			hits.append(String((blocker as Control).name))
	_check(hits.is_empty(), "%s: inline без пересечений %s" % [tag, str(hits)])


func _check_cards(lobby: Node, tag: String) -> void:
	var view := get_viewport().get_visible_rect().size
	var origin := (lobby as Control).get_global_rect().position
	var table := lobby.get("daily_quests_panel") as Control
	var table_rect := _local_rect(table, origin)
	var cards: Array = lobby.get("cards")
	if cards.size() < 3:
		_check(false, "%s: карточки героев есть" % tag)
		return
	var rects: Array = []
	for i in 3:
		rects.append(_local_rect(cards[i] as Control, origin))
	var area_left := maxf(table_rect.end.x + 24.0, 352.0)
	var area_right := view.x - 28.0
	var area_w := area_right - area_left
	var group_left: float = (rects[0] as Rect2).position.x
	var group_right: float = (rects[2] as Rect2).end.x
	var group_w := group_right - group_left
	_check(_near(group_left, area_left, 1.0), "%s: карточки начинаются от области %.1f" % [tag, group_left])
	_check(group_w >= area_w * 0.98, "%s: карточки занимают область (%.1f/%.1f)" % [tag, group_w, area_w])
	_check(
		group_left - table_rect.end.x <= 36.0 + 0.75,
		"%s: зазор table→cards ≤36 (%.1f)" % [tag, group_left - table_rect.end.x]
	)
	if view.x >= 1400.0:
		_check(group_left < 457.0, "%s: левая карточка левее 457 (%.1f)" % [tag, group_left])
	var center: Rect2 = rects[1]
	var side: Rect2 = rects[0]
	_check(
		_near(side.size.y / center.size.y, 0.75, 0.02),
		"%s: бока 75%% центра" % tag
	)
	_check(
		center.size.x > side.size.x and center.size.y > side.size.y,
		"%s: центр больше боков" % tag
	)
	var fixed_rects: Array = [table_rect, lobby.get("profile_button"),
		lobby.get("lobby_logo"), lobby.get("shard_shop_button"),
		lobby.get("play_button"), lobby.get("tutorial_button"),
		lobby.get("settings_button"), lobby.get("rules_button")]
	var hits: Array = []
	for i in 3:
		var rect: Rect2 = rects[i]
		for blocker in fixed_rects:
			if blocker is Control and rect.intersects((blocker as Control).get_global_rect()):
				hits.append("%d-%s" % [i, String((blocker as Control).name)])
	_check(hits.is_empty(), "%s: карточки без пересечений %s" % [tag, str(hits)])


func _check_overlay(overlay: Control, tag: String, desktop: bool) -> void:
	var panel := overlay.find_child("DailyQuestsPanel", true, false) as Control
	_check(panel != null, "%s: панель найдена" % tag)
	if panel == null:
		return
	_check(_near(panel.size.x, 812.0, 1.0), "%s: панель 812 px (%.1f)" % [tag, panel.size.x])
	_check(_near(panel.size.y, 338.0, 1.0), "%s: панель 338 px (%.1f)" % [tag, panel.size.y])
	var screen := Rect2(Vector2.ZERO, viewport_size())
	_check(screen.encloses(panel.get_global_rect()), "%s: панель внутри экрана" % tag)
	var header_diamond := overlay.find_child("DailyQuestsDiamond", true, false) as Control
	var diamond_labels: Array = []
	if header_diamond != null:
		diamond_labels = header_diamond.find_children("*", "Label", true, false)
	_check(
		header_diamond != null and header_diamond.find_child("DiamondFill", true, false) != null
			and diamond_labels.is_empty(),
		"%s: золотой ромб нарисован без текстового глифа" % tag
	)

	var title := overlay.get("title_label") as Label
	var timer := overlay.get("timer_label") as Label
	var count := overlay.get("count_label") as Label
	var explanation := overlay.get("explanation_label") as Label
	_check(title != null and title.text == "ЕЖЕДНЕВНЫЕ ЗАДАНИЯ", "%s: заголовок" % tag)
	_check(title != null and title.get_theme_font_size("font_size") == 24, "%s: заголовок 24" % tag)
	_check(timer != null and timer.visible and timer.text.contains("обновление через"),
		"%s: таймер" % tag)
	_check(count != null and count.text == "1/3", "%s: пилюля 1/3" % tag)
	_check(
		explanation != null and explanation.text.contains("1 замена в день бесплатно")
			and explanation.text.contains("2") and explanation.text.contains("1 осколку"),
		"%s: пояснение замен" % tag
	)

	var cards: Array = overlay.get("card_nodes")
	_check(cards.size() == 3, "%s: 3 карточки" % tag)
	for i in cards.size():
		var card := cards[i] as Control
		_check(_near(card.size.x, 248.0, 1.0) and _near(card.size.y, 172.0, 1.0),
			"%s: карточка %d 248x172" % [tag, i])
		_check(_near(card.position.x, 22.0 + float(i) * 260.0, 1.0),
			"%s: карточка %d x" % [tag, i])
		_check(_near(card.position.y, 0.0, 1.0), "%s: карточка %d y" % [tag, i])
		_check(card.find_child("DailyQuestsIcon%d" % i, true, false) != null,
			"%s: медальон карточки %d" % [tag, i])
		_check(card.find_child("DailyQuestsRing%d" % i, true, false) != null,
			"%s: кольцо карточки %d" % [tag, i])
		_check(card.find_child("DailyQuestsRewardChip%d" % i, true, false) != null,
			"%s: чип награды карточки %d" % [tag, i])
		_check(card.find_child("DailyQuestsReroll%d" % i, true, false) != null,
			"%s: кнопка замены карточки %d" % [tag, i])
		var reroll := card.find_child("DailyQuestsReroll%d" % i, true, false) as Button
		_check(
			reroll != null and (reroll.text.contains("Заменить") or reroll.text.contains("Нет замен"))
				and not reroll.text.contains("↻") and not reroll.text.contains("◆"),
			"%s: понятный текст замены карточки %d" % [tag, i]
		)
	# Первая карточка выполнена (fixture 3,1).
	var check0 := cards[0].find_child("DailyQuestsCheck0", true, false) as Control
	var remaining0 := cards[0].find_child("DailyQuestsRemaining0", true, false) as Label
	_check(check0 != null and check0.visible, "%s: галочка выполненной карточки" % tag)
	_check(remaining0 != null and remaining0.text == "награда зачислена",
		"%s: «награда зачислена»" % tag)
	# Regression: the check mark must be drawn, never a typed glyph (the font
	# has no U+2713, and the web build has no fallback font).
	_check(check0 != null and not (check0 is Label) and check0.has_method("_draw"),
		"%s: галочка нарисована в _draw, не текст" % tag)
	var glyph_hits := _banned_glyphs(overlay)
	_check(glyph_hits.is_empty(), "%s: нет текстовых галок/ромбов/стрелок %s" % [tag, str(glyph_hits)])

	var diamonds := 0
	for i in 7:
		var diamond := overlay.find_child("DailyQuestsDay%d" % i, true, false) as Control
		if diamond != null and diamond.find_child("DiamondOuter", true, false) != null:
			diamonds += 1
	_check(diamonds == 7, "%s: 7 нарисованных ромбов" % tag)
	var week := overlay.get("week_label") as Label
	var status := overlay.get("status_label") as Label
	_check(week != null and week.text.contains("/7 полных дней"), "%s: X/7 полных дней" % tag)
	_check(status != null and status.text.contains("до 300 осколков"),
		"%s: остаток до 300" % tag)
	var claim := overlay.get("claim_button") as Button
	var chip := overlay.find_child("DailyQuestsRewardChip", true, false) as Control
	var sub := overlay.find_child("DailyQuestsRewardSub", true, false) as Label
	_check(claim != null and claim.text == "5/7", "%s: кнопка 5/7" % tag)
	if chip != null and panel != null:
		var panel_rect := panel.get_global_rect()
		var chip_rect := chip.get_global_rect()
		_check(
			_near(
				chip_rect.position.x + chip_rect.size.x * 0.5,
				panel_rect.position.x + panel_rect.size.x * 0.5,
				2.0
			),
			"%s: чип 300 по центру панели" % tag
		)
	if status != null and chip != null and claim != null:
		var sr := status.get_global_rect()
		_check(
			not sr.intersects(chip.get_global_rect())
				and sr.end.y <= chip.get_global_rect().position.y + 0.75,
			"%s: статус не пересекает чип 300" % tag
		)
		_check(not sr.intersects(claim.get_global_rect()),
			"%s: статус не пересекает кнопку" % tag)
	_check(sub == null or not sub.visible, "%s: в чипе нет дубля «Осталось»" % tag)

	# 7/7: текст ровно про 300 и кнопка «Забрать 300».
	overlay.call("apply_data", _fixture(3, 3, 7, "free"))
	await get_tree().create_timer(0.3).timeout
	_check(status != null and status.text == "За 7/7 дней — 300 осколков",
		"%s: «За 7/7 дней — 300 осколков»" % tag)
	_check(claim != null and claim.text == "Забрать 300" and not claim.disabled,
		"%s: «Забрать 300»" % tag)
	_check(claim != null and claim.visible, "%s: «Забрать 300» виден в overlay" % tag)
	var shard := overlay.find_child("DailyQuestsRewardShard", true, false) as TextureRect
	_check(shard != null and shard.texture != null, "%s: иконка осколка" % tag)
	for banned in ["1000", "3000", "5000", "оружие", "скин", "уже есть"]:
		_check(
			status == null or not status.text.to_lower().contains(banned),
			"%s: нет «%s»" % [tag, banned]
		)


func _check_mobile(lobby: Node) -> void:
	var overlay := lobby.get("daily_quests_panel") as Control
	var button := lobby.get("daily_quests_button") as Button
	_check(overlay != null and button != null, "mobile: кнопка и оверлей созданы")
	if overlay == null or button == null:
		return
	_check(button.text == "ЗАДАНИЯ", "mobile: кнопка ЗАДАНИЯ")
	lobby.call("_open_daily_quests_overlay")
	await get_tree().create_timer(0.2).timeout
	overlay.call("apply_data", _fixture(3, 1, 5, "free"))
	await get_tree().create_timer(0.55).timeout
	_check(overlay.visible, "mobile: оверлей открыт")
	await _check_overlay(overlay, "844x390", false)
	var close_button := overlay.find_child("DailyQuestsClose", true, false) as Button
	if close_button != null:
		close_button.emit_signal("pressed")
		await get_tree().create_timer(0.1).timeout
		_check(not overlay.visible, "mobile: × закрывает")
	lobby.call("_open_daily_quests_overlay")
	await get_tree().create_timer(0.1).timeout
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	get_viewport().push_input(key)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not overlay.visible, "mobile: Esc закрывает")
	await _save_shot("daily_quests_mobile_%dx%d" % [int(viewport_size().x), int(viewport_size().y)])


func _fixture(count: int, completed: int, week_full: int, reroll_state: String) -> Dictionary:
	var titles := ["Убить 8 врагов", "Нанести урон 4000", "Купить 2 усиления"]
	var metrics := ["kills", "damage", "shop_items_one"]
	var targets := [8, 4000, 2]
	var rewards := [3, 4, 3]
	var quests: Array = []
	for i in count:
		var index := mini(i, 2)
		quests.append({
			"slot": i,
			"template_id": ["kills_8", "damage_4000", "buy_2"][index],
			"title": titles[index],
			"metric": metrics[index],
			"target": targets[index],
			"progress": targets[index] if i < completed else int(targets[index] * 0.4),
			"reward_shards": rewards[index],
			"completed": i < completed,
		})
	var repeats := {"free_available": true, "paid_left": 2, "paid_max": 2, "cost": 1}
	if reroll_state == "paid":
		repeats = {"free_available": false, "paid_left": 2, "paid_max": 2, "cost": 1}
	elif reroll_state == "limit":
		repeats = {"free_available": false, "paid_left": 0, "paid_max": 2, "cost": 1}
	return {
		"quests": quests,
		"week": _week(week_full),
		"rerolls": repeats,
		"summary": {
			"completed": completed,
			"total": 3,
			"week": {"required": 7, "active_days": week_full, "claimable": week_full >= 7},
		},
	}


func _week(full_days: int) -> Array:
	var days: Array = []
	for i in 7:
		days.append({
			"date": "2026-11-%02d" % (23 + i),
			"today": i == 3,
			"full": i < full_days,
			"completed_count": 3 if i < full_days else 0,
		})
	return days


func _near(value: float, expected: float, tolerance := 0.75) -> bool:
	return absf(value - expected) <= tolerance


func _banned_glyphs(root: Node) -> Array:
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


func _local_rect(control: Control, origin: Vector2) -> Rect2:
	var rect := control.get_global_rect()
	return Rect2(rect.position - origin, rect.size)


func _check(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("DAILY_QUESTS PASS ", label)
	else:
		_fail += 1
		print("DAILY_QUESTS FAIL ", label)


func viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _save_shot(file_name: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://ui_shots/%s.png" % file_name)
	print("DAILY_QUESTS shot=", file_name)
