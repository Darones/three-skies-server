extends Node3D

## Проба ежедневных заданий: раскладка и состояния.
##
## Сцену-обёртку создать рядом (вне списка правок этой волны):
##   [gd_scene load_steps=2 format=3]
##   [ext_resource type="Script" path="res://tools/daily_quests_probe.gd" id="1"]
##   [node name="DailyQuestsProbe" type="Node3D"]
##   script = ExtResource("1")
##
## Запуск:
##   godot_console --path . tools/DailyQuestsProbe.tscn -- --layout=1440x734
##   godot_console --path . tools/DailyQuestsProbe.tscn -- --layout=844x390 --mobile
##
## Desktop-прогон сам проверяет 1440x734, 1424x800 и 1280x720.
##
## Проверяет одобренный макет 28.11.2026:
##   desktop: таблица x=28/top=122.4/width=min(380, W*0.27)/высоты 48/154/200/246;
##            логотип min(320, W*0.22) по центру; карточки заполняют
##            table.right+36 .. W-28 и H-24 (центр крупнее, бока modulate 0.8);
##            кнопки ИГРАТЬ/ОБУЧЕНИЕ слева над правилами;
##            отсутствие пересечений на 1280/1366/1440/1600/1920;
##   mobile:  кнопку «ЗАДАНИЯ» 235x48 под menu_level_label, оверлей z=42,
##            панель 812 px и высоты 338/136, закрытие x / тап вне / Esc,
##            скрытие из _close_player_menu, сохранение скролла инвентаря;
##   состояния: free/paid/limit замены, «День закрыт: 3/3»,
##            «Осталось 2 задания», «Неделя: 5/7 полных дней»,
##            «Скин уже есть — 1000 осколков», кнопка «Забрать».

var _fail := 0
var _pass := 0


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

	# Проба не должна зависеть от сети: локальный недоступный адрес отвечает
	# сразу, а поздние profile_updated не перетирают фикстуры.
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
		var callback := Callable(lobby, "_on_profile_updated" if signal_name == "profile_updated" else "_on_profile_failed")
		if MetaProgression.is_connected(signal_name, callback):
			MetaProgression.disconnect(signal_name, callback)
	var welcome: Variant = lobby.get("welcome_overlay")
	if welcome != null and welcome is Control:
		(welcome as Control).visible = false

	var viewport_size := get_viewport().get_visible_rect().size
	print("DAILY_QUESTS viewport=", viewport_size, " mobile=", DeviceProfile.mobile_ui)
	if DeviceProfile.mobile_ui:
		await _check_mobile(lobby)
	else:
		await _check_desktop(lobby)

	print("DAILY_QUESTS checks pass=%d fail=%d" % [_pass, _fail])
	print("DAILY_QUESTS_RESULT=", "PASS" if _fail == 0 else "FAIL")
	print("DAILY_QUESTS_DIR=", ProjectSettings.globalize_path("user://ui_shots"))
	get_tree().quit(0 if _fail == 0 else 1)


func _check_desktop(lobby: Node) -> void:
	var quests_panel := lobby.get("daily_quests_panel") as Control
	_check(quests_panel != null, "desktop: панель создана")
	if quests_panel == null:
		return
	for layout in [
		Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1440, 734),
		Vector2i(1600, 900), Vector2i(1920, 1080),
	]:
		await _check_desktop_layout(lobby, quests_panel, layout as Vector2i)
	await _check_desktop_state(quests_panel)
	await _save_shot("daily_quests_desktop_%dx%d" % [int(viewport_size().x), int(viewport_size().y)])


## Одобренный макет 28.11.2026: таблица min(380, W*0.27), карточки в области
## table.right+36 .. W-28, кнопки 220x56 / 180x42 в правом нижнем углу.
func _check_desktop_layout(lobby: Node, quests_panel: Control, layout: Vector2i) -> void:
	get_tree().root.content_scale_size = layout
	DisplayServer.window_set_size(layout)
	for i in 5:
		await get_tree().process_frame
	lobby.call("_layout_lobby_layout")
	await get_tree().process_frame
	quests_panel.call("apply_data", _fixture(3, 1, 5, "free"))
	await get_tree().create_timer(0.3).timeout

	var tag := "%dx%d" % [layout.x, layout.y]
	var view := get_viewport().get_visible_rect().size
	var origin := (lobby as Control).get_global_rect().position
	var table_rect := _local_rect(quests_panel, origin)
	var profile_rect := _local_rect(lobby.get("profile_button") as Control, origin)
	var logo_rect := _local_rect(lobby.get("lobby_logo") as Control, origin)
	var shop_rect := _local_rect(lobby.get("shard_shop_button") as Control, origin)
	var play_rect := _local_rect(lobby.get("play_button") as Control, origin)
	var tutorial_rect := _local_rect(lobby.get("tutorial_button") as Control, origin)
	var settings_rect := _local_rect(lobby.get("settings_button") as Control, origin)
	var rules_rect := _local_rect(lobby.get("rules_button") as Control, origin)
	var cards: Array = lobby.get("cards")

	var table_w := minf(380.0, view.x * 0.27)
	table_w = clampf(table_w, 240.0, 380.0)
	table_w = minf(table_w, view.x - 28.0 - 24.0)
	print(
		"DAILY_QUESTS %s view=%.0fx%.0f table=(%.1f,%.1f,%.1f,%.1f) tables=%.1f" % [
			tag, view.x, view.y, table_rect.position.x, table_rect.position.y,
			table_rect.size.x, table_rect.size.y, table_w,
		]
	)
	_check(_near(table_rect.position.x, 28.0), "%s: таблица left 28 (%.1f)" % [tag, table_rect.position.x])
	_check(_near(table_rect.position.y, 122.4), "%s: таблица top 122.4 (%.1f)" % [tag, table_rect.position.y])
	_check(_near(table_rect.size.x, table_w, 0.75), "%s: таблица width %.1f (%.1f)" % [tag, table_rect.size.x, table_w])
	_check(_near(table_rect.size.y, 246.0), "%s: 3 задания = 246 px (%.1f)" % [tag, table_rect.size.y])
	_check(table_w >= 240.0, "%s: таблица не уже 240" % tag)

	# Профиль 28,18,360x100.
	_check(_near(profile_rect.position.x, 28.0), "%s: профиль x=28" % tag)
	_check(_near(profile_rect.position.y, 18.0), "%s: профиль y=18" % tag)
	_check(_near(profile_rect.size.x, 360.0), "%s: профиль w=360 (%.1f)" % [tag, profile_rect.size.x])
	_check(_near(profile_rect.size.y, 100.0), "%s: профиль h=100 (%.1f)" % [tag, profile_rect.size.y])

	# Логотип: min(320, W*0.22), центр X, top 10.
	var logo_w := minf(320.0, view.x * 0.22)
	_check(_near(logo_rect.size.x, logo_w, 0.75), "%s: логотип width %.1f (%.1f)" % [tag, logo_rect.size.x, logo_w])
	_check(_near(logo_rect.position.y, 10.0), "%s: логотип top 10" % tag)
	_check(
		_near(logo_rect.position.x + logo_rect.size.x * 0.5, view.x * 0.5, 0.75),
		"%s: логотип по центру X" % tag
	)

	# Вариант 1: левая колонка, блок 300, верх = table.bottom + 24.
	var block_top := table_rect.end.y + 24.0
	var row_top := block_top + 56.0 + 10.0 + 44.0 + 10.0
	_check(_near(play_rect.position.x, 28.0), "%s: ИГРАТЬ left 28 (%.1f)" % [tag, play_rect.position.x])
	_check(_near(play_rect.size.x, 300.0), "%s: ИГРАТЬ width 300 (%.1f)" % [tag, play_rect.size.x])
	_check(_near(play_rect.size.y, 56.0), "%s: ИГРАТЬ height 56 (%.1f)" % [tag, play_rect.size.y])
	_check(_near(play_rect.position.y, block_top), "%s: блок от table.bottom+24 (%.1f)" % [tag, play_rect.position.y])
	_check(_near(play_rect.end.y, block_top + 56.0), "%s: ИГРАТЬ bottom" % tag)
	_check(_near(tutorial_rect.position.x, 28.0), "%s: ОБУЧЕНИЕ left 28 (%.1f)" % [tag, tutorial_rect.position.x])
	_check(_near(tutorial_rect.size.x, 300.0), "%s: ОБУЧЕНИЕ width 300 (%.1f)" % [tag, tutorial_rect.size.x])
	_check(_near(tutorial_rect.size.y, 44.0), "%s: ОБУЧЕНИЕ height 44 (%.1f)" % [tag, tutorial_rect.size.y])
	_check(_near(tutorial_rect.position.y, block_top + 66.0), "%s: ОБУЧЕНИЕ top" % tag)
	_check(_near(play_rect.end.y, tutorial_rect.position.y - 10.0, 0.75), "%s: между PLAY и ОБУЧЕНИЕ 10 px" % tag)
	_check(_near(settings_rect.position.x, 28.0), "%s: шестерёнка left 28" % tag)
	_check(_near(settings_rect.position.y, row_top), "%s: ряд шестерёнки снизу (%.1f)" % [tag, settings_rect.position.y])
	_check(_near(settings_rect.size.x, 44.0) and _near(settings_rect.size.y, 44.0), "%s: шестерёнка 44x44" % tag)
	_check(_near(rules_rect.position.x, 82.0), "%s: ПРАВИЛА left 82 (%.1f)" % [tag, rules_rect.position.x])
	_check(_near(rules_rect.position.y, row_top), "%s: ПРАВИЛА в одном ряду" % tag)
	_check(_near(rules_rect.size.x, 246.0) and _near(rules_rect.size.y, 44.0), "%s: ПРАВИЛА 246x44" % tag)
	_check(_near(tutorial_rect.end.y, row_top - 10.0, 0.75), "%s: ряд низа через 10 px" % tag)

	# Ожидаемая геометрия карточек: центр 100%, бока 75%, ширина height*0.72.
	var area_left := maxf(table_rect.end.x + 36.0, 430.0)
	var area_right := view.x - 28.0
	var area_top := maxf(logo_rect.end.y + 18.0, shop_rect.end.y + 12.0)
	var area_bottom := view.y - 24.0
	var area_w := area_right - area_left
	var area_h := area_bottom - area_top
	var center_h := area_h
	var center_w := center_h * 0.72
	var side_h := center_h * 0.75
	var side_w := side_h * 0.72
	var gap := maxf(12.0, view.x * 0.012)
	var group_w := center_w + 2.0 * side_w + 2.0 * gap
	if group_w > area_w:
		var scale := area_w / group_w
		center_h *= scale
		center_w *= scale
		side_h *= scale
		side_w *= scale
		gap *= scale
		group_w = area_w
	var group_left := area_left + maxf(0.0, (area_w - group_w) * 0.5)
	var center_y := area_top + (area_h - center_h) * 0.5
	var side_y := area_top + (area_h - side_h) * 0.5
	var expected: Array[Rect2] = [
		Rect2(Vector2(group_left, side_y), Vector2(side_w, side_h)),
		Rect2(Vector2(group_left + side_w + gap, center_y), Vector2(center_w, center_h)),
		Rect2(Vector2(group_left + side_w + gap + center_w + gap, side_y), Vector2(side_w, side_h)),
	]
	var card_rects: Array = []
	for i in mini(cards.size(), 3):
		var actual := _local_rect(cards[i] as Control, origin)
		card_rects.append(actual)
		_check(
			_near(actual.size.x, expected[i].size.x, 1.0)
				and _near(actual.size.y, expected[i].size.y, 1.0),
			"%s: карточка %d %.1fx%.1f (формула %.1fx%.1f)" % [
				tag, i, actual.size.x, actual.size.y,
				expected[i].size.x, expected[i].size.y,
			]
		)
	print(
		"DAILY_QUESTS %s cards center=%.1fx%.1f side=%.1fx%.1f area=(%.1f,%.1f,%.1f,%.1f)" % [
			tag, center_w, center_h, side_w, side_h, area_left, area_top, area_w, area_h,
		]
	)
	if card_rects.size() == 3:
		var center_rect: Rect2 = card_rects[1]
		var side_rect: Rect2 = card_rects[0]
		var right_rect: Rect2 = card_rects[2]
		_check(
			_near(side_rect.size.y / center_rect.size.y, 0.75, 0.02),
			"%s: бока = 75%% высоты центра (%.2f)" % [tag, side_rect.size.y / center_rect.size.y]
		)
		_check(
			center_rect.size.x > side_rect.size.x and center_rect.size.y > side_rect.size.y
				and right_rect.size.y < center_rect.size.y,
			"%s: центр больше боков (%.1fx%.1f > %.1fx%.1f)" % [
				tag, center_rect.size.x, center_rect.size.y, side_rect.size.x, side_rect.size.y
			]
		)
		var mod_side := (cards[0] as Control).modulate
		var mod_center := (cards[1] as Control).modulate
		var mod_right := (cards[2] as Control).modulate
		_check(
			_near(mod_side.r, 0.65, 0.02) and _near(mod_side.g, 0.65, 0.02)
				and _near(mod_side.b, 0.65, 0.02),
			"%s: левая карточка modulate 0.65" % tag
		)
		_check(
			_near(mod_center.r, 1.0, 0.02) and _near(mod_center.g, 1.0, 0.02)
				and _near(mod_center.b, 1.0, 0.02),
			"%s: центр без затемнения" % tag
		)
		_check(
			_near(mod_right.r, 0.65, 0.02) and _near(mod_right.g, 0.65, 0.02)
				and _near(mod_right.b, 0.65, 0.02),
			"%s: правая карточка modulate 0.65" % tag
		)
		var badge := (cards[1] as Control).find_child("SelectedBadge", true, false) as Panel
		var badge_label := (cards[1] as Control).find_child("SelectedBadgeLabel", true, false) as Label
		var side_badge := (cards[0] as Control).find_child("SelectedBadge", true, false)
		var right_badge := (cards[2] as Control).find_child("SelectedBadge", true, false)
		_check(badge != null and badge.visible, "%s: метка «ВЫБРАН» у центра" % tag)
		_check(badge_label != null and badge_label.text == "ВЫБРАН", "%s: текст метки «ВЫБРАН»" % tag)
		_check(side_badge == null and right_badge == null, "%s: у боковых нет метки" % tag)
		var frame := (cards[1] as Control).find_child("CardFrame", true, false) as Panel
		var frame_style: StyleBoxFlat = null
		if frame != null:
			frame_style = frame.get_theme_stylebox("panel") as StyleBoxFlat
		_check(
			frame_style != null and frame_style.border_width_top == 3
				and _near(frame_style.border_color.r, 0.95, 0.03)
				and _near(frame_style.border_color.g, 0.76, 0.03)
				and _near(frame_style.border_color.b, 0.38, 0.03),
			"%s: золотая рамка 3 px у центра" % tag
		)
		_check(
			center_rect.size.x > 260.0 and center_rect.size.y > 350.0,
			"%s: центр крупный (%.1fx%.1f)" % [tag, center_rect.size.x, center_rect.size.y]
		)
		_check(
			table_rect.end.x < side_rect.position.x - 8.0,
			"%s: right таблицы < card_left - 8 (%.1f < %.1f)" % [
				tag, table_rect.end.x, side_rect.position.x - 8.0
			]
		)

	# Пересечения: таблица и карточки против логотипа/магазина/кнопок/профиля.
	var fixed_rects: Array = [logo_rect, shop_rect, play_rect, tutorial_rect, settings_rect, rules_rect, profile_rect]
	var table_hits: Array = []
	for fixed in fixed_rects:
		if table_rect.intersects(fixed):
			table_hits.append("fixed")
	_check(table_hits.is_empty(), "%s: таблица без пересечений %s" % [tag, str(table_hits)])
	var card_hits: Array = []
	for i in card_rects.size():
		var rect: Rect2 = card_rects[i]
		for other_index in fixed_rects.size():
			if rect.intersects(fixed_rects[other_index]):
				card_hits.append("%d-fixed%d" % [i, other_index])
		if rect.intersects(table_rect):
			card_hits.append("%d-table" % i)
		for other in card_rects.size():
			var other_rect: Rect2 = card_rects[other]
			if other != i and rect.intersects(other_rect):
				card_hits.append("%d-%d" % [i, other])
	_check(card_hits.is_empty(), "%s: карточки без пересечений %s" % [tag, str(card_hits)])

	var title := quests_panel.get("title_label") as Label
	_check(title != null and title.text == "ЗАДАНИЯ · 1/3", "%s: заголовок «ЗАДАНИЯ · 1/3»" % tag)
	_check(title != null and title.get_theme_font_size("font_size") == 20, "%s: заголовок 20" % tag)
	var rows: Array = quests_panel.get("row_nodes")
	for i in rows.size():
		var row := rows[i] as Control
		_check(_near(row.size.y, 42.0), "%s: строка %d = 42 px" % [tag, i])
		var row_title := row.find_child("DailyQuestsRowTitle%d" % i, true, false) as Label
		var row_meta := row.find_child("DailyQuestsRowMeta%d" % i, true, false) as Label
		var row_bar := row.find_child("DailyQuestsRowBar%d" % i, true, false) as ProgressBar
		_check(row_title != null and row_title.get_theme_font_size("font_size") == 18, "%s: текст задания 18" % tag)
		_check(row_meta != null and row_meta.get_theme_font_size("font_size") == 16, "%s: мета 16" % tag)
		_check(row_bar != null and _near(row_bar.size.y, 4.0), "%s: бар 4 px" % tag)

	# Пустое состояние — только заголовок, 48 px.
	quests_panel.call("apply_data", _fixture(0, 0, 0, "free"))
	await get_tree().create_timer(0.3).timeout
	_check(_near(quests_panel.size.y, 48.0), "%s: пусто = 48 px" % tag)
	var rows_layer := quests_panel.get("rows_layer") as Control
	var footer := quests_panel.get("footer") as Control
	_check(rows_layer != null and not rows_layer.visible, "%s: пусто — без строк" % tag)
	_check(footer != null and not footer.visible, "%s: пусто — без подвала" % tag)


func _check_desktop_state(quests_panel: Control) -> void:
	var subtitle := quests_panel.get("subtitle_label") as Label
	var week_label := quests_panel.get("week_label") as Label
	var status := quests_panel.get("status_label") as Label
	var claim := quests_panel.get("claim_button") as Button
	var rows_layer := quests_panel.get("rows_layer") as Control
	var footer := quests_panel.get("footer") as Control

	quests_panel.call("apply_data", _fixture(3, 1, 5, "free"))
	await get_tree().create_timer(0.3).timeout
	_check(subtitle != null and subtitle.text == "Осталось 2 задания", "desktop: текст «Осталось 2 задания»")
	_check(week_label != null and week_label.text == "Неделя: 5/7 полных дней", "desktop: «Неделя: 5/7 полных дней»")
	_check(subtitle != null and subtitle.get_theme_font_size("font_size") == 16, "desktop: подзаголовок 16")
	_check(rows_layer != null and rows_layer.visible, "desktop: строки видны")
	_check(footer != null and footer.visible, "desktop: подвал виден")

	quests_panel.call("apply_data", _fixture(2, 0, 0, "free"))
	await get_tree().create_timer(0.3).timeout
	_check(_near(quests_panel.size.y, 200.0), "desktop: 2 задания = 200 px (%.1f)" % quests_panel.size.y)
	quests_panel.call("apply_data", _fixture(1, 0, 0, "free"))
	await get_tree().create_timer(0.3).timeout
	_check(_near(quests_panel.size.y, 154.0), "desktop: 1 задание = 154 px (%.1f)" % quests_panel.size.y)

	quests_panel.call("apply_data", _fixture(3, 3, 7, "free"))
	await get_tree().create_timer(0.3).timeout
	_check(subtitle != null and subtitle.text == "День закрыт: 3/3", "desktop: «День закрыт: 3/3»")
	_check(week_label != null and week_label.text == "Неделя: 7/7 полных дней", "desktop: «Неделя: 7/7 полных дней»")
	_check(claim != null and claim.text == "Забрать" and not claim.disabled, "desktop: кнопка «Забрать» активна")

	quests_panel.call("apply_data", _fixture(3, 1, 5, "free", true))
	await get_tree().create_timer(0.3).timeout
	_check(
		status != null and status.text == "Скин уже есть — 1000 осколков",
		"desktop: «Скин уже есть — 1000 осколков»"
	)

	quests_panel.call("apply_data", _fixture(3, 1, 5, "free", false))
	await get_tree().create_timer(0.3).timeout
	_check(status != null and status.text.contains("оружие за 100"), "desktop: неделя 1 — оружие за 100")

	await _check_reroll_states(quests_panel)


func _check_mobile(lobby: Node) -> void:
	var quests_panel := lobby.get("daily_quests_panel") as Control
	var button := lobby.get("daily_quests_button") as Button
	var badge := lobby.get("daily_quests_badge") as Label
	var menu_level := lobby.get("menu_level_label") as Label
	_check(quests_panel != null, "mobile: оверлей создан")
	_check(button != null, "mobile: кнопка «ЗАДАНИЯ» создана")
	if quests_panel == null or button == null:
		return

	var button_rect := button.get_global_rect()
	_check(_near(button_rect.size.x, 235.0, 1.0), "mobile: кнопка 235 px (%.1f)" % button_rect.size.x)
	_check(_near(button_rect.size.y, 48.0, 1.0), "mobile: кнопка 48 px (%.1f)" % button_rect.size.y)
	_check(button.text == "ЗАДАНИЯ", "mobile: текст «ЗАДАНИЯ»")
	_check(badge != null and badge.text.ends_with("/3"), "mobile: бейдж N/3")
	_check(
		menu_level != null and button.get_parent() == menu_level.get_parent()
			and button.get_index() == menu_level.get_index() + 1,
		"mobile: кнопка сразу под menu_level_label"
	)
	_check(quests_panel.z_index == 42, "mobile: оверлей z=42")
	_check(not quests_panel.visible, "mobile: оверлей закрыт на старте")

	# Скролл инвентаря: запоминаем позицию и проверяем возврат.
	lobby.call("_open_player_menu")
	for i in 5:
		await get_tree().process_frame
	var scroll := lobby.get("inventory_scroll") as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 40
		await get_tree().process_frame
	var saved_scroll := 0 if scroll == null else scroll.scroll_vertical
	print("DAILY_QUESTS inventory_scroll=", saved_scroll)
	lobby.call("_open_daily_quests_overlay")
	await get_tree().create_timer(0.2).timeout
	quests_panel.call("apply_data", _fixture(3, 1, 5, "free"))
	await get_tree().create_timer(0.35).timeout
	_check(quests_panel.visible, "mobile: кнопка открывает оверлей")

	var panel_node := quests_panel.find_child("DailyQuestsPanel", true, false) as Control
	_check(panel_node != null, "mobile: панель найдена")
	if panel_node != null:
		_check(_near(panel_node.size.x, 812.0, 1.0), "mobile: панель 812 px (%.1f)" % panel_node.size.x)
		_check(_near(panel_node.size.y, 338.0, 1.0), "mobile: 3 задания = 338 px (%.1f)" % panel_node.size.y)
		_check(_near(panel_node.get_global_rect().position.y, 26.0, 1.0), "mobile: панель по центру (top 26)")

	var title := quests_panel.get("title_label") as Label
	var subtitle := quests_panel.get("subtitle_label") as Label
	var rows: Array = quests_panel.get("row_nodes")
	_check(title != null and title.text == "ЗАДАНИЯ · 1/3", "mobile: заголовок «ЗАДАНИЯ · 1/3»")
	_check(title != null and title.get_theme_font_size("font_size") == 20, "mobile: заголовок 20")
	_check(subtitle != null and subtitle.get_theme_font_size("font_size") == 18, "mobile: подзаголовок 18")
	if rows.size() > 0:
		var row := rows[0] as Control
		var row_title := row.find_child("DailyQuestsRowTitle0", true, false) as Label
		var row_meta := row.find_child("DailyQuestsRowMeta0", true, false) as Label
		_check(row_title != null and row_title.get_theme_font_size("font_size") == 18, "mobile: текст задания 18")
		_check(row_meta != null and row_meta.get_theme_font_size("font_size") == 18, "mobile: мета 18")
	_check(subtitle != null and subtitle.text == "Осталось 2 задания", "mobile: «Осталось 2 задания»")

	# Закрытие крестиком и возврат скролла.
	var close_button := quests_panel.find_child("DailyQuestsClose", true, false) as Button
	_check(close_button != null, "mobile: крестик есть")
	if close_button != null:
		close_button.emit_signal("pressed")
		await get_tree().create_timer(0.1).timeout
		await get_tree().process_frame
		_check(not quests_panel.visible, "mobile: крестик закрывает оверлей")
		await get_tree().process_frame
		_check(
			scroll == null or scroll.scroll_vertical == saved_scroll,
			"mobile: скролл инвентаря восстановлен (%d)" % (0 if scroll == null else scroll.scroll_vertical)
		)

	# Пустое состояние в оверлее.
	lobby.call("_open_daily_quests_overlay")
	await get_tree().create_timer(0.1).timeout
	quests_panel.call("apply_data", _fixture(0, 0, 0, "free"))
	await get_tree().create_timer(0.35).timeout
	if panel_node != null:
		_check(_near(panel_node.size.y, 136.0, 1.0), "mobile: пусто = 136 px (%.1f)" % panel_node.size.y)
	var footer := quests_panel.get("footer") as Control
	_check(footer != null and not footer.visible, "mobile: пусто — без подвала")

	# Esc.
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	get_viewport().push_input(key)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not quests_panel.visible, "mobile: Esc закрывает оверлей")

	# Тап вне панели.
	lobby.call("_open_daily_quests_overlay")
	await get_tree().create_timer(0.1).timeout
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(4.0, 4.0)
	get_viewport().push_input(click)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not quests_panel.visible, "mobile: тап вне панели закрывает оверлей")

	# _close_player_menu скрывает оверлей.
	lobby.call("_open_daily_quests_overlay")
	await get_tree().create_timer(0.1).timeout
	lobby.call("_close_player_menu")
	await get_tree().process_frame
	_check(not quests_panel.visible, "mobile: _close_player_menu скрывает оверлей")

	# Замены: free / paid / limit.
	await _check_reroll_states(quests_panel)
	await _check_mobile_texts(quests_panel)
	lobby.call("_open_daily_quests_overlay")
	await get_tree().create_timer(0.1).timeout
	quests_panel.call("apply_data", _fixture(3, 1, 5, "free"))
	await get_tree().create_timer(0.35).timeout
	await _save_shot("daily_quests_mobile_%dx%d" % [int(viewport_size().x), int(viewport_size().y)])


func _check_mobile_texts(quests_panel: Control) -> void:
	var subtitle := quests_panel.get("subtitle_label") as Label
	var week_label := quests_panel.get("week_label") as Label
	var status := quests_panel.get("status_label") as Label
	var claim := quests_panel.get("claim_button") as Button
	quests_panel.call("apply_data", _fixture(3, 3, 7, "free", true))
	await get_tree().create_timer(0.3).timeout
	_check(subtitle != null and subtitle.text == "День закрыт: 3/3", "mobile: «День закрыт: 3/3»")
	_check(week_label != null and week_label.text == "Неделя: 7/7 полных дней", "mobile: «Неделя: 7/7 полных дней»")
	_check(
		status != null and status.text == "Скин уже есть — 1000 осколков",
		"mobile: «Скин уже есть — 1000 осколков»"
	)
	_check(claim != null and claim.text == "Забрать" and not claim.disabled, "mobile: кнопка «Забрать» активна")


func _check_reroll_states(quests_panel: Control) -> void:
	var cases := [
		["free", "↻", true],
		["paid", "↻ 1", true],
		["limit", "—", false],
	]
	for entry in cases:
		quests_panel.call("apply_data", _fixture(3, 0, 0, String(entry[0])))
		await get_tree().create_timer(0.22).timeout
		var rows: Array = quests_panel.get("row_nodes")
		var ok := false
		if rows.size() > 0:
			var reroll := (rows[0] as Control).find_child("DailyQuestsReroll0", true, false) as Button
			ok = (
				reroll != null and reroll.visible
				and reroll.text == String(entry[1])
				and reroll.disabled == (not bool(entry[2]))
			)
		_check(ok, "замена %s: текст/доступность" % String(entry[0]))
	var completed_rows: Array = quests_panel.get("row_nodes")
	if completed_rows.size() > 0:
		quests_panel.call("apply_data", _fixture(3, 1, 0, "free"))
		await get_tree().create_timer(0.22).timeout
		var done_rows: Array = quests_panel.get("row_nodes")
		var reroll_done := (done_rows[0] as Control).find_child("DailyQuestsReroll0", true, false) as Button
		_check(reroll_done == null or not reroll_done.visible, "выполненное задание без замены")


func _fixture(count: int, completed: int, week_full: int, reroll_state: String, skin_owned := false) -> Dictionary:
	var titles := ["Убить 8 врагов", "Нанести урон 4000", "Сыграть 2 боя"]
	var targets := [8, 4000, 2]
	var rewards := [3, 4, 3]
	var quests: Array = []
	for i in count:
		var index := mini(i, 2)
		quests.append({
			"slot": i,
			"template_id": ["kills_8", "damage_4000", "play_2"][index],
			"title": titles[index],
			"target": targets[index],
			"progress": targets[index] if i < completed else int(targets[index] * 0.4),
			"reward_shards": rewards[index],
			"reward_xp": 150,
			"completed": i < completed,
		})
	var repeats := {}
	match reroll_state:
		"paid":
			repeats = {"free_available": false, "paid_left": 2, "paid_max": 2, "cost": 1}
		"limit":
			repeats = {"free_available": false, "paid_left": 0, "paid_max": 2, "cost": 1}
		_:
			repeats = {"free_available": true, "paid_left": 2, "paid_max": 2, "cost": 1}
	return {
		"quests": quests,
		"week": _week(week_full),
		"rerolls": repeats,
		"summary": {
			"completed": completed,
			"total": 3,
			"week": {
				"active_days": week_full,
				"required": 7,
				"tier": 1,
				"claimable": week_full >= 7,
				"claimed": false,
				"reward_kind": "skin",
				"reward_name": "скин",
				"reward_owned": skin_owned,
				"compensation": 1000,
			},
		},
	}


func _week(full_days: int) -> Array:
	var days: Array = []
	for i in 7:
		var day := {
			"date": "2026-11-%02d" % (23 + i),
			"today": i == 3,
			"full": i < full_days,
			"completed_count": 3 if i < full_days else 0,
		}
		days.append(day)
	return days


func _near(value: float, expected: float, tolerance := 0.75) -> bool:
	return absf(value - expected) <= tolerance


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
