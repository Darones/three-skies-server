extends Control

signal back_requested

const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const SUPPORT_LINKS := preload("res://scripts/support_links.gd")
const GOLD := Color(0.95, 0.76, 0.38)
const PALE := Color(0.94, 0.95, 0.99)
const MUTED := Color(0.82, 0.85, 0.92)
const TAB_TITLES := ["ПРАВИЛА БОЯ", "ПРАВИЛА ИГРЫ", "МОДЕРАЦИЯ"]
const COMBAT_SECTIONS := [
	["ЦЕЛЬ",
		"Разбей Оболочку, забери Небесный осколок и донеси его на свою базу. Побеждает команда, которая первой доставит 3 осколка."],
	["УПРАВЛЕНИЕ",
		"WASD или джойстик — движение. Автоатака сама бьёт врага рядом. 1, 2 и 3 — навыки; на телефоне это кнопки справа."],
	["ОБОЛОЧКА И ОСКОЛОК",
		"Оболочка появляется на арене по расписанию. Разбей её, забери осколок и неси на базу. Носильщик виден всем, а осколок можно выбить."],
	["МАГАЗИН",
		"Золото боя собирается у Золотого колодца. В лавке покупаются улучшения до конца матча. Осколки — общая валюта для оружия и скинов."],
	["ПОБЕДА",
		"3 осколка или больше очков к концу времени. При равном счёте начинается sudden death: решает один осколок."],
	["БОТЫ",
		"В первых матчах и при нехватке игроков могут быть боты. Они помечены на экране загрузки и в итогах боя. Мы не выдаём их за живых игроков."],
]
const GAME_SECTIONS := [
	["НИК",
		"Ник — от 3 до 32 символов. Без мата и оскорблений, без выдачи себя за других игроков или администрацию игры, без рекламы и ссылок. За нарушение ник могут скрыть, а аккаунт — ограничить."],
	["АККАУНТ",
		"Играйте со своего аккаунта платформы. Один аккаунт — один игрок: передавать его другим нельзя. Прогресс хранится на сервере."],
	["ПЛАТЕЖИ",
		"Покупки проходят через платёжную систему платформы. Осколки начисляет сервер после подтверждения платежа, возвраты — по правилам платформы."],
	["ПОВЕДЕНИЕ",
		"Играйте честно: без читов, сговора и использования ошибок игры. Не оскорбляйте других игроков и не мешайте им играть."],
	["БОТЫ И ЧЕСТНОСТЬ",
		"Боты заменяют игроков, когда людей не хватает, и всегда помечены. Читы, сговор и намеренное использование ошибок ведут к блокировке."],
	["ДАННЫЕ И АККАУНТ",
		"Профиль и данные можно удалить в настройках. Политика конфиденциальности и соглашение открываются там же."],
	["ИЗМЕНЕНИЯ",
		"Правила могут обновляться. Актуальная версия всегда доступна на этом экране."],
]
const MODERATION_SECTIONS := [
	["ЖАЛОБЫ",
		"Кнопка «!» в бою и форма жалобы в лобби. В жалобу попадают ник, время и краткое описание."],
	["СРОК",
		"Каждую жалобу модератор рассматривает в течение 48 часов."],
	["МЕРЫ",
		"Предупреждение, затем скрытие ника, затем блокировка аккаунта. Мера зависит от нарушения и повторов."],
	["АПЕЛЛЯЦИЯ",
		"Если вы не согласны с решением, напишите в сообщество игры или на daroness@ya.ru: апелляцию рассмотрит модератор."],
]

var mobile_layout := false
var scroll: ScrollContainer
var scroll_fade: TextureRect
var tab_buttons: Array[Button] = []
var tab_pages: Array[VBoxContainer] = []
var tab_scrolls: Array[int] = [0, 0, 0]
var active_tab := 0
var support_hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mobile_layout = DeviceProfile.mobile_ui
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func open() -> void:
	visible = true
	for i in tab_scrolls.size():
		tab_scrolls[i] = 0
	_select_tab(0)
	if scroll != null:
		await get_tree().process_frame
		scroll.scroll_vertical = 0
		_update_scroll_fade()


func close() -> void:
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.005, 0.008, 0.018, 0.9)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "RulesPanel"
	if mobile_layout:
		panel.anchor_left = 0.04
		panel.anchor_top = 0.05
		panel.anchor_right = 0.96
		panel.anchor_bottom = 0.95
	else:
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.anchor_left = 0.5
		panel.anchor_top = 0.5
		panel.anchor_right = 0.5
		panel.anchor_bottom = 0.5
		panel.offset_left = -370.0
		panel.offset_top = -330.0
		panel.offset_right = 370.0
		panel.offset_bottom = 330.0
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var outer := MarginContainer.new()
	outer.name = "RulesMargin"
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("margin_left", 22)
	outer.add_theme_constant_override("margin_right", 22)
	outer.add_theme_constant_override("margin_top", 18)
	outer.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(outer)

	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 14 if mobile_layout else 12)
	outer.add_child(layout)

	var title_size := 38 if mobile_layout else 34
	var section_title_size := 27 if mobile_layout else 24
	var body_size := 24 if mobile_layout else 20
	var footer_size := 19 if mobile_layout else 17
	var button_size := 22 if mobile_layout else 20
	var tab_size := 21 if mobile_layout else 18

	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := _make_label("ПРАВИЛА", title_size, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(title)
	var close_button := _make_button("×", false)
	close_button.custom_minimum_size = Vector2(56.0, 50.0)
	close_button.add_theme_font_size_override("font_size", _fs(title_size - 6))
	close_button.pressed.connect(_on_back)
	header.add_child(close_button)

	_build_tabs(layout, tab_size)

	scroll = ScrollContainer.new()
	scroll.name = "RulesScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)

	var content_margin := MarginContainer.new()
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_theme_constant_override("margin_left", 2)
	# The vertical scrollbar draws over the right edge of the text, and the
	# 44 px fade covers the bottom of the scroll on a phone. Reserve both, so
	# the last line of every tab can be scrolled out from under them.
	content_margin.add_theme_constant_override("margin_right", 16 if mobile_layout else 6)
	content_margin.add_theme_constant_override("margin_top", 8)
	content_margin.add_theme_constant_override("margin_bottom", 50 if mobile_layout else 34)
	scroll.add_child(content_margin)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 0)
	content_margin.add_child(content)

	# One page per tab. Only the active page is visible, so the scrollbar
	# height follows the open tab and every tab keeps its own scroll offset.
	var pages: Array[VBoxContainer] = [
		_page(content, 0), _page(content, 1), _page(content, 2),
	]
	var page_sections: Array[Array] = [COMBAT_SECTIONS, GAME_SECTIONS, MODERATION_SECTIONS]
	for i in pages.size():
		_fill_page(pages[i], page_sections[i], section_title_size, body_size, i == 0)
	# The tutorial hint belongs to the combat tab; keeping it inside the page
	# frees 37 px of scroll height on an 844x390 landscape phone.
	var tutorial_hint := _make_label(
		"Обучение можно пройти заново кнопкой «Обучение» в лобби.", footer_size - 1, MUTED)
	tutorial_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pages[0].add_child(tutorial_hint)

	var footer := VBoxContainer.new()
	footer.name = "RulesFooter"
	footer.add_theme_constant_override("separation", 4)
	layout.add_child(footer)
	# Support and Back share one row: stacking them cost ~60 px of scroll
	# height on an 844x390 landscape phone, where the panel is 475 px tall.
	var actions := HBoxContainer.new()
	actions.name = "RulesActions"
	actions.add_theme_constant_override("separation", 10)
	footer.add_child(actions)
	var support_button := _make_button("Поддержка / Сообщество", false)
	support_button.name = "RulesSupportButton"
	support_button.custom_minimum_size = Vector2(0.0, 48.0)
	support_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	support_button.size_flags_stretch_ratio = 1.35
	support_button.add_theme_font_size_override("font_size", _fs(button_size - 3))
	support_button.pressed.connect(_open_support)
	actions.add_child(support_button)
	support_hint = _make_label("", footer_size - 2, MUTED)
	support_hint.name = "RulesSupportHint"
	support_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	support_hint.visible = false
	footer.add_child(support_hint)

	var back_button := _make_button("Назад", true)
	back_button.custom_minimum_size = Vector2(0.0, 48.0)
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.add_theme_font_size_override("font_size", _fs(button_size))
	back_button.pressed.connect(_on_back)
	actions.add_child(back_button)

	_build_scroll_fade()
	if scroll.get_v_scroll_bar() != null:
		scroll.get_v_scroll_bar().value_changed.connect(func(_value: float) -> void: _update_scroll_fade())
	scroll.resized.connect(_update_scroll_fade)
	_select_tab(0)
	call_deferred("_update_scroll_fade")


func _build_tabs(parent: VBoxContainer, tab_size: int) -> void:
	var tabs := HBoxContainer.new()
	tabs.name = "RulesTabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_theme_constant_override("separation", 8 if mobile_layout else 6)
	parent.add_child(tabs)
	for i in TAB_TITLES.size():
		var button := _make_button(String(TAB_TITLES[i]), false)
		button.name = "RulesTab%d" % i
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0.0, 46.0 if mobile_layout else 42.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", _fs(tab_size))
		button.pressed.connect(_on_tab_pressed.bind(i))
		tabs.add_child(button)
		tab_buttons.append(button)


func _page(parent: VBoxContainer, index: int) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = "RulesPage%d" % index
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 16 if mobile_layout else 14)
	page.visible = false
	parent.add_child(page)
	tab_pages.append(page)
	return page


func _fill_page(page: VBoxContainer, sections: Array, title_size: int, body_size: int, allow_columns: bool) -> void:
	if allow_columns and _use_two_columns():
		var columns := HBoxContainer.new()
		columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_theme_constant_override("separation", 30)
		page.add_child(columns)
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation", 16)
		columns.add_child(left)
		var right := VBoxContainer.new()
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.add_theme_constant_override("separation", 16)
		columns.add_child(right)
		for i in sections.size():
			var column: VBoxContainer = left if i < sections.size() / 2 else right
			column.add_child(_section(str(sections[i][0]), str(sections[i][1]), title_size, body_size))
		return
	for entry in sections:
		page.add_child(_section(str(entry[0]), str(entry[1]), title_size, body_size))


func _on_tab_pressed(index: int) -> void:
	_select_tab(index)


func _select_tab(index: int) -> void:
	if tab_pages.is_empty():
		return
	index = clampi(index, 0, tab_pages.size() - 1)
	if scroll != null:
		tab_scrolls[active_tab] = scroll.scroll_vertical
	for i in tab_pages.size():
		tab_pages[i].visible = i == index
		if i < tab_buttons.size():
			_apply_tab_state(tab_buttons[i], i == index)
	active_tab = index
	if scroll != null:
		# The new page changes the scrollbar range, so restore the saved
		# offset after the container has re-laid out.
		_restore_scroll.call_deferred(index)


func _restore_scroll(index: int) -> void:
	if scroll == null or index != active_tab:
		return
	scroll.scroll_vertical = tab_scrolls[index]
	_update_scroll_fade()


func _apply_tab_state(button: Button, active: bool) -> void:
	button.set_pressed_no_signal(active)
	button.add_theme_color_override("font_color", GOLD if active else MUTED)
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.88, 0.59) if active else PALE)
	button.add_theme_stylebox_override("normal", _tab_style(active, false))
	button.add_theme_stylebox_override("hover", _tab_style(active, true))
	button.add_theme_stylebox_override("pressed", _tab_style(active, true))


func _tab_style(active: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.19, 0.15, 0.08, 0.98) if active else Color(0.05, 0.06, 0.085, 0.98)
	style.border_color = GOLD if active else Color(0.42, 0.46, 0.55)
	if hovered:
		style.bg_color = Color(0.26, 0.2, 0.11, 1.0) if active else Color(0.1, 0.12, 0.17, 1.0)
		style.border_color = Color(1.0, 0.88, 0.59) if active else Color(0.74, 0.79, 0.89)
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _build_scroll_fade() -> void:
	# The scroll viewport cuts the last visible line in half at 844x390.
	# A short gradient makes that edge read as "scroll for more" instead of
	# as a broken glyph row. It sits above the scroll but below nothing else.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.035, 0.045, 0.07, 0.0))
	gradient.set_color(1, Color(0.035, 0.045, 0.07, 0.98))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 8
	texture.height = 64
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	scroll_fade = TextureRect.new()
	scroll_fade.name = "RulesScrollFade"
	scroll_fade.texture = texture
	scroll_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scroll_fade.stretch_mode = TextureRect.STRETCH_SCALE
	scroll_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_fade.visible = false
	add_child(scroll_fade)


func _update_scroll_fade() -> void:
	if scroll_fade == null or scroll == null or not scroll.is_inside_tree():
		return
	var bar := scroll.get_v_scroll_bar()
	if bar == null:
		scroll_fade.visible = false
		return
	var can_scroll_down := bar.visible and bar.max_value - bar.page > scroll.scroll_vertical + 1.0
	scroll_fade.visible = can_scroll_down
	if not can_scroll_down:
		return
	var fade_height := 44.0 if mobile_layout else 30.0
	var rect := scroll.get_global_rect()
	var base := get_global_rect().position
	scroll_fade.position = Vector2(rect.position.x - base.x, rect.end.y - base.y - fade_height)
	scroll_fade.size = Vector2(rect.size.x - 24.0, fade_height)


func _use_two_columns() -> bool:
	if not mobile_layout:
		return false
	var view := get_viewport_rect().size
	return view.x >= view.y * 1.5


func _section(title_text: String, body_text: String, title_size: int, body_size: int) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 5)
	section.add_child(_make_label(title_text, title_size, GOLD))
	var body := _make_label(body_text, body_size, PALE)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(body)
	return section


func _open_support() -> void:
	# Direct community link of the platform (VK or OK); e-mail is the fallback.
	var url := SUPPORT_LINKS.support_url()
	if support_hint != null:
		support_hint.text = "Если ссылка не открылась: %s" % url
		support_hint.visible = true
	SUPPORT_LINKS.open_url(url)


func _on_back() -> void:
	visible = false
	back_requested.emit()


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", _fs(font_size))
	label.add_theme_constant_override("line_spacing", 4)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", UI_FONT)
	button.add_theme_font_size_override("font_size", _fs(18))
	button.add_theme_color_override("font_color", GOLD if primary else PALE)
	button.add_theme_stylebox_override("normal", _button_style(primary, false))
	button.add_theme_stylebox_override("hover", _button_style(primary, true))
	button.add_theme_stylebox_override("pressed", _button_style(primary, true))
	return button


func _button_style(primary: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.13, 0.08, 0.98) if primary else Color(0.055, 0.065, 0.09, 0.98)
	style.border_color = GOLD if primary else Color(0.46, 0.49, 0.57)
	if hovered:
		style.bg_color = Color(0.24, 0.19, 0.11, 1.0) if primary else Color(0.1, 0.12, 0.17, 1.0)
		style.border_color = Color(1.0, 0.88, 0.59) if primary else Color(0.76, 0.8, 0.89)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.07, 0.99)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0.0, 6.0)
	return style


func _fs(size: int) -> int:
	if mobile_layout:
		return maxi(size, 15)
	return size
