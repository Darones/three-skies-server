extends Control

signal back_requested

const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const GOLD := Color(0.95, 0.76, 0.38)
const PALE := Color(0.9, 0.92, 0.98)
const MUTED := Color(0.72, 0.77, 0.86)

var mobile_layout := false
var scroll: ScrollContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mobile_layout = DeviceProfile.mobile_ui
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func open() -> void:
	visible = true
	if scroll != null:
		await get_tree().process_frame
		scroll.scroll_vertical = 0


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

	scroll = ScrollContainer.new()
	scroll.name = "RulesScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	scroll.add_child(margin)

	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := _make_label("ПРАВИЛА БОЯ", 30, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(title)
	var close_button := _make_button("×", false)
	close_button.custom_minimum_size = Vector2(48.0, 42.0)
	close_button.add_theme_font_size_override("font_size", _fs(24))
	close_button.pressed.connect(_on_back)
	header.add_child(close_button)

	layout.add_child(_section(
		"ЦЕЛЬ",
		"Разбей Оболочку, забери Небесный осколок и донеси его на свою базу. Побеждает команда, которая первой доставит 3 осколка."
	))
	layout.add_child(_section(
		"УПРАВЛЕНИЕ",
		"WASD или джойстик — движение. Автоатака сама бьёт врага рядом. 1, 2 и 3 — навыки; на телефоне это кнопки справа."
	))
	layout.add_child(_section(
		"ОБОЛОЧКА И ОСКОЛОК",
		"Оболочка появляется на арене по расписанию. Разбей её, забери осколок и неси на базу. Носильщик виден всем, а осколок можно выбить."
	))
	layout.add_child(_section(
		"МАГАЗИН",
		"Золото боя собирается у фонтана. В лавке покупаются улучшения до конца матча. Осколки — общая валюта для оружия и скинов."
	))
	layout.add_child(_section(
		"ПОБЕДА",
		"3 осколка или больше очков к концу времени. При равном счёте начинается sudden death: решает один осколок."
	))
	layout.add_child(_section(
		"БОТЫ",
		"В первых матчах и при нехватке игроков могут быть боты. Они помечены на экране загрузки и в итогах боя. Мы не выдаём их за живых игроков и не пишем за них в чат."
	))

	var footer := _make_label("Обучение можно пройти заново кнопкой «Обучение» в лобби.", 14, MUTED)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(footer)
	var back_button := _make_button("Назад", true)
	back_button.custom_minimum_size = Vector2(0.0, 46.0)
	back_button.pressed.connect(_on_back)
	layout.add_child(back_button)


func _section(title_text: String, body_text: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 3)
	section.add_child(_make_label(title_text, 18, GOLD))
	var body := _make_label(body_text, 16, PALE)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(body)
	return section


func _on_back() -> void:
	visible = false
	back_requested.emit()


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", _fs(font_size))
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
