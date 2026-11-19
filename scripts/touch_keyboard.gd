extends Control

## In-game soft keyboard for web/VK webviews where the native keyboard
## does not appear. Supports Russian and English layouts and digits.

const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const GOLD := Color(0.94, 0.78, 0.43)
const PALE := Color(0.9, 0.91, 0.95)

signal submitted(text: String)
signal closed

var target: Control = null
var max_length := 64
var layout := "ru"
var shifted := false
var symbols := false
var panel: PanelContainer
var title_label: Label
var display_label: Label
var rows_box: VBoxContainer
var layout_button: Button
var shift_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 500
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func open(p_target: Control, p_title: String, p_max_length: int = 64) -> void:
	target = p_target
	max_length = p_max_length
	title_label.text = p_title
	visible = true
	_refresh()
	_refresh_display()
	move_to_front()


func close() -> void:
	visible = false
	target = null
	closed.emit()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.005, 0.008, 0.018, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	panel = PanelContainer.new()
	panel.name = "TouchKeyboardPanel"
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_top = -300.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	content.add_child(header)
	title_label = _make_label("ВВОД ТЕКСТА", 18, GOLD)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	layout_button = _make_key("РУ", Vector2(58, 36), 16)
	layout_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	layout_button.pressed.connect(_toggle_layout)
	header.add_child(layout_button)
	var symbols_button := _make_key("123", Vector2(62, 36), 16)
	symbols_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	symbols_button.pressed.connect(_toggle_symbols)
	header.add_child(symbols_button)
	var done_button := _make_key("Готово", Vector2(92, 36), 16)
	done_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done_button.add_theme_color_override("font_color", GOLD)
	done_button.pressed.connect(_on_done)
	header.add_child(done_button)

	display_label = _make_label("", 20, PALE)
	display_label.custom_minimum_size = Vector2(0, 36)
	display_label.clip_text = true
	display_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	display_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	display_label.add_theme_stylebox_override("normal", _display_style())
	content.add_child(display_label)

	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 5)
	rows_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(rows_box)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.03, 0.05, 0.98)
	style.border_color = Color(0.78, 0.62, 0.32, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	return style


func _display_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.018, 0.03, 0.96)
	style.border_color = Color(0.32, 0.38, 0.5, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	return style


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_key(text: String, min_size: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0 if min_size.x <= 0 else min_size.x, min_size.y)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_override("font", UI_FONT)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", PALE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _key_style(false))
	button.add_theme_stylebox_override("hover", _key_style(true))
	button.add_theme_stylebox_override("pressed", _key_style(true))
	return button


func _key_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.2, 0.98) if not hovered else Color(0.2, 0.23, 0.32, 1.0)
	style.border_color = Color(0.55, 0.62, 0.76, 0.9) if not hovered else Color(1.0, 0.88, 0.55, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style


func _refresh() -> void:
	if rows_box == null:
		return
	for child in rows_box.get_children():
		rows_box.remove_child(child)
		child.queue_free()
	layout_button.text = "РУ" if layout == "ru" else "EN"
	if symbols:
		_add_rows([
			["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
			["-", "_", ".", ",", "!", "Shift", "@", "#", "%", "+"],
			["/", ":", ";", "(", ")", "\"", "'", "*", "=", "&"],
		])
	else:
		if layout == "ru":
			_add_rows([
				["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ъ"],
				["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
				["я", "ч", "с", "м", "и", "т", "ь", "б", "ю", "ё"],
			])
		else:
			_add_rows([
				["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
				["a", "s", "d", "f", "g", "h", "j", "k", "l"],
				["z", "x", "c", "v", "b", "n", "m"],
			])
	var special := HBoxContainer.new()
	special.add_theme_constant_override("separation", 5)
	rows_box.add_child(special)
	shift_button = _make_key("Shift", Vector2(58, 40), 20)
	shift_button.pressed.connect(_toggle_shift)
	special.add_child(shift_button)
	var space := _make_key("Пробел", Vector2(0, 40), 16)
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	space.pressed.connect(_insert_text.bind(" "))
	special.add_child(space)
	var backspace := _make_key("Back", Vector2(64, 40), 20)
	backspace.pressed.connect(_backspace)
	special.add_child(backspace)


func _add_rows(rows: Array) -> void:
	for row_data in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		rows_box.add_child(row)
		for key_text in row_data:
			var label := String(key_text)
			if shifted:
				label = label.to_upper()
			var key := _make_key(label, Vector2(0, 40), 18)
			key.pressed.connect(_insert_text.bind(label))
			row.add_child(key)


func _toggle_layout() -> void:
	layout = "en" if layout == "ru" else "ru"
	symbols = false
	_refresh()
	_refresh_display()


func _toggle_symbols() -> void:
	symbols = not symbols
	_refresh()
	_refresh_display()


func _toggle_shift() -> void:
	shifted = not shifted
	_refresh()
	_refresh_display()


func _insert_text(text: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	var value := text
	if shifted and not symbols:
		value = value.to_upper()
	if target is LineEdit:
		var edit := target as LineEdit
		var current := edit.text
		if max_length > 0 and current.length() + value.length() > max_length:
			value = value.substr(0, maxi(0, max_length - current.length()))
		if value.is_empty():
			return
		var caret := clampi(edit.caret_column, 0, current.length())
		edit.text = current.substr(0, caret) + value + current.substr(caret)
		edit.caret_column = caret + value.length()
		edit.grab_focus()
	elif target is TextEdit:
		(target as TextEdit).insert_text_at_caret(value)
	_refresh_display()
	if shifted:
		shifted = false
		_refresh()


func _backspace() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target is LineEdit:
		var edit := target as LineEdit
		var current := edit.text
		var caret := clampi(edit.caret_column, 0, current.length())
		if caret <= 0:
			return
		edit.text = current.substr(0, caret - 1) + current.substr(caret)
		edit.caret_column = caret - 1
		edit.grab_focus()
	elif target is TextEdit:
		(target as TextEdit).delete_char_at_caret()
	_refresh_display()


func _refresh_display() -> void:
	if display_label == null:
		return
	var text := ""
	if target != null and is_instance_valid(target):
		text = String(target.get("text"))
	if text.is_empty():
		text = "…"
	display_label.text = text


func _on_done() -> void:
	var text := ""
	if target != null and is_instance_valid(target):
		text = String(target.get("text"))
	submitted.emit(text)
	close()
