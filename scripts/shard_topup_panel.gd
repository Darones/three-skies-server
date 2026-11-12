extends PanelContainer

const GOLD := Color(0.95, 0.76, 0.38)
const PALE := Color(0.9, 0.92, 0.98)
const MUTED := Color(0.72, 0.77, 0.86)
const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const SHARD_ICON: Texture2D = preload("res://ui/icons/sky_shard.png")

const MIN_SHARDS := 100
const MAX_SHARDS := 10000
const SHARD_STEP := 100

# Заглушка: позже здесь будет реальная проверка площадки (например, из URL).
var is_ok = false:
	set(value):
		is_ok = value
		_update_display()

var shards_slider: HSlider
var amount_label: Label
var price_label: Label
var pay_button: Button


func _ready() -> void:
	_build()
	_update_display()


func _build() -> void:
	custom_minimum_size = Vector2(480, 0)
	add_theme_stylebox_override("panel", _panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	layout.add_child(header)

	var title := _make_label("ПОПОЛНЕНИЕ БАЛАНСА", 26, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(title)

	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "×"
	close_button.custom_minimum_size = Vector2(42, 42)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_font_override("font", UI_FONT)
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.add_theme_color_override("font_color", PALE)
	close_button.add_theme_color_override("font_hover_color", Color.WHITE)
	close_button.add_theme_stylebox_override("normal", _secondary_button_style(false))
	close_button.add_theme_stylebox_override("hover", _secondary_button_style(true))
	close_button.add_theme_stylebox_override("pressed", _secondary_button_style(true))
	close_button.pressed.connect(_on_close_pressed)
	header.add_child(close_button)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1)
	divider.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	layout.add_child(divider)

	var hint := _make_label("Сколько нужно?", 15, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	layout.add_child(hint)

	amount_label = _make_label("", 24, PALE)
	amount_label.name = "AmountLabel"
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var amount_row := HBoxContainer.new()
	amount_row.add_theme_constant_override("separation", 6)
	amount_row.add_child(amount_label)
	amount_row.add_child(_shard_icon(22))
	layout.add_child(amount_row)

	shards_slider = HSlider.new()
	shards_slider.name = "ShardsSlider"
	shards_slider.min_value = MIN_SHARDS
	shards_slider.max_value = MAX_SHARDS
	shards_slider.step = SHARD_STEP
	shards_slider.value = MIN_SHARDS
	shards_slider.custom_minimum_size = Vector2(0, 34)
	shards_slider.focus_mode = Control.FOCUS_NONE
	shards_slider.add_theme_stylebox_override("slider", _slider_style(Color(0.08, 0.1, 0.15)))
	shards_slider.add_theme_stylebox_override("grabber_area", _slider_style(Color(0.43, 0.74, 1.0, 0.82)))
	shards_slider.add_theme_stylebox_override("grabber_area_highlight", _slider_style(Color(0.62, 0.84, 1.0, 0.95)))
	shards_slider.value_changed.connect(_on_shards_changed)
	layout.add_child(shards_slider)

	price_label = _make_label("", 18, Color(0.43, 0.84, 1.0))
	price_label.name = "PriceLabel"
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	layout.add_child(price_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	layout.add_child(spacer)

	pay_button = Button.new()
	pay_button.name = "PayButton"
	pay_button.custom_minimum_size = Vector2(0, 54)
	pay_button.focus_mode = Control.FOCUS_NONE
	pay_button.add_theme_font_override("font", UI_FONT)
	pay_button.add_theme_font_size_override("font_size", 21)
	pay_button.add_theme_color_override("font_color", Color(0.18, 0.11, 0.02))
	pay_button.add_theme_color_override("font_hover_color", Color(0.12, 0.075, 0.01))
	pay_button.add_theme_color_override("font_pressed_color", Color(0.12, 0.075, 0.01))
	pay_button.add_theme_stylebox_override("normal", _pay_button_style(false))
	pay_button.add_theme_stylebox_override("hover", _pay_button_style(true))
	pay_button.add_theme_stylebox_override("pressed", _pay_button_style(true))
	pay_button.pressed.connect(_on_pay_pressed)
	layout.add_child(pay_button)


func _update_display() -> void:
	if shards_slider == null or amount_label == null or price_label == null or pay_button == null:
		return
	var shards := int(shards_slider.value)
	var price := int(shards / 100.0)
	amount_label.text = str(shards)
	price_label.text = "Стоимость: %d %s" % [price, _price_currency_name()]
	pay_button.text = "Оплатить %s" % _payment_currency_name()


func _on_shards_changed(_value: float) -> void:
	_update_display()


func _on_pay_pressed() -> void:
	var shards := int(shards_slider.value)
	var price := int(shards / 100.0)
	print("[MOCK] Оплата %s на %d осколков. Стоимость: %d %s." % [
		_payment_currency_name(),
		shards,
		price,
		_price_currency_name(),
	])


func _on_close_pressed() -> void:
	visible = false


func _price_currency_name() -> String:
	return "ОКов" if is_ok else "Голосов"


func _payment_currency_name() -> String:
	return "ОКами" if is_ok else "Голосами"


func _shard_icon(icon_size: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = SHARD_ICON
	icon.custom_minimum_size = Vector2(icon_size * 0.7, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.72))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


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


func _slider_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _pay_button_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.78, 0.25) if not hovered else Color(1.0, 0.86, 0.42)
	style.border_color = Color(1.0, 0.9, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _secondary_button_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.13, 0.93) if not hovered else Color(0.12, 0.16, 0.22, 1.0)
	style.border_color = Color(0.46, 0.54, 0.69, 0.82) if not hovered else Color(0.76, 0.84, 0.98)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	return style
