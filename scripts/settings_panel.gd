extends Control

signal back_requested

const SETTINGS_PATH := "user://game_settings.cfg"
const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const CONTROL_BINDINGS := [
	{"action": "move_forward", "label": "Движение вперёд"},
	{"action": "move_back", "label": "Движение назад"},
	{"action": "move_left", "label": "Движение влево"},
	{"action": "move_right", "label": "Движение вправо"},
	{"action": "ability_1", "label": "Навык 1"},
	{"action": "ability_2", "label": "Навык 2"},
	{"action": "ability_3", "label": "Навык 3"},
]

var mobile_layout := false
var volume_slider: HSlider
var vibration_toggle: CheckButton
var current_volume := 1.0
var listening_action := ""
var binding_buttons: Dictionary = {}
var status_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mobile_layout = OS.has_feature("mobile")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_panel()
	_load_settings()


func _build_panel() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.005, 0.008, 0.018, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	if mobile_layout:
		panel.anchor_left = 0.04
		panel.anchor_top = 0.06
		panel.anchor_right = 0.96
		panel.anchor_bottom = 0.94
	else:
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.anchor_left = 0.5
		panel.anchor_top = 0.5
		panel.anchor_right = 0.5
		panel.anchor_bottom = 0.5
		panel.offset_left = -320.0
		panel.offset_top = -325.0
		panel.offset_right = 320.0
		panel.offset_bottom = 325.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.045, 0.07, 0.99)
	panel_style.border_color = Color(0.78, 0.62, 0.32)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel_style.content_margin_left = 18.0
	panel_style.content_margin_right = 18.0
	panel_style.content_margin_top = 14.0
	panel_style.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	panel.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := _make_label("НАСТРОЙКИ", 28, Color(0.95, 0.76, 0.38))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(title)
	var back_button := _make_button("←", false)
	back_button.custom_minimum_size = Vector2(48.0, 42.0)
	back_button.add_theme_font_size_override("font_size", 22)
	back_button.pressed.connect(_on_back_pressed)
	header.add_child(back_button)

	layout.add_child(_make_label("ЗВУК", 17, Color(0.9, 0.92, 0.98)))
	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 12)
	layout.add_child(volume_row)
	var volume_label := _make_label("Общая громкость", 15, Color(0.76, 0.8, 0.89))
	volume_label.custom_minimum_size = Vector2(160.0, 36.0)
	volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	volume_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	volume_row.add_child(volume_label)
	volume_slider = HSlider.new()
	volume_slider.name = "MasterVolume"
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.01
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.custom_minimum_size = Vector2(100.0, 36.0)
	volume_slider.value_changed.connect(_on_volume_changed)
	volume_row.add_child(volume_slider)

	if mobile_layout:
		vibration_toggle = CheckButton.new()
		vibration_toggle.name = "VibrationToggle"
		vibration_toggle.text = "Вибрация"
		vibration_toggle.add_theme_font_override("font", UI_FONT)
		vibration_toggle.add_theme_font_size_override("font_size", 16)
		vibration_toggle.toggled.connect(_on_vibration_toggled)
		layout.add_child(vibration_toggle)
	else:
		layout.add_child(_make_label("УПРАВЛЕНИЕ · нажмите кнопку и задайте новую клавишу", 15, Color(0.9, 0.92, 0.98)))
		for binding in CONTROL_BINDINGS:
			_build_binding_row(layout, String(binding["action"]), String(binding["label"]))

	status_label = _make_label("", 13, Color(0.76, 0.8, 0.89))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	layout.add_child(status_label)
	var close_button := _make_button("Назад", true)
	close_button.custom_minimum_size = Vector2(0.0, 46.0)
	close_button.pressed.connect(_on_back_pressed)
	layout.add_child(close_button)


func _build_binding_row(parent: VBoxContainer, action: String, label_text: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 34.0)
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var label := _make_label(label_text, 14, Color(0.76, 0.8, 0.89))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var button := _make_button("", false)
	button.name = "Binding_" + action
	button.custom_minimum_size = Vector2(170.0, 34.0)
	button.pressed.connect(_begin_rebind.bind(action))
	row.add_child(button)
	binding_buttons[action] = button
	_update_binding_button(action)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", UI_FONT)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color(0.95, 0.76, 0.38) if primary else Color(0.9, 0.92, 0.98))
	button.add_theme_stylebox_override("normal", _button_style(primary, false))
	button.add_theme_stylebox_override("hover", _button_style(primary, true))
	button.add_theme_stylebox_override("pressed", _button_style(primary, true))
	return button


func _button_style(primary: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.14, 0.08, 0.94) if primary else Color(0.07, 0.09, 0.13, 0.93)
	style.border_color = Color(0.95, 0.76, 0.38) if primary else Color(0.46, 0.54, 0.69, 0.82)
	if hovered:
		style.bg_color = Color(0.27, 0.21, 0.11, 1.0) if primary else Color(0.12, 0.16, 0.22, 1.0)
		style.border_color = Color(1.0, 0.88, 0.58) if primary else Color(0.76, 0.84, 0.98)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style


func _load_settings() -> void:
	var config := ConfigFile.new()
	var has_settings := config.load(SETTINGS_PATH) == OK
	var saved_volume := float(config.get_value("audio", "master_volume", 1.0)) if has_settings else 1.0
	current_volume = clampf(saved_volume, 0.0, 1.0)
	volume_slider.set_value_no_signal(clampf(saved_volume, 0.0, 1.0))
	_apply_volume(saved_volume)
	if vibration_toggle != null:
		vibration_toggle.set_pressed_no_signal(bool(config.get_value("mobile", "vibration", true)) if has_settings else true)
	if not mobile_layout and has_settings:
		for binding in CONTROL_BINDINGS:
			var action := String(binding["action"])
			if config.has_section_key("controls", action):
				_apply_binding(action, int(config.get_value("controls", action)))
		for binding in CONTROL_BINDINGS:
			_update_binding_button(String(binding["action"]))


func _save_value(section: String, key: String, value: Variant) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(section, key, value)
	config.save(SETTINGS_PATH)


func _on_volume_changed(value: float) -> void:
	current_volume = value
	_apply_volume(value)


func _apply_volume(value: float) -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_volume_db(master_bus, linear_to_db(maxf(value, 0.0001)))
		AudioServer.set_bus_mute(master_bus, value <= 0.001)


func _on_vibration_toggled(enabled: bool) -> void:
	_save_value("mobile", "vibration", enabled)
	if enabled:
		Input.vibrate_handheld(35)


func _begin_rebind(action: String) -> void:
	listening_action = action
	status_label.text = "Нажмите клавишу для действия… Esc — отмена"
	_update_binding_button(action)


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE:
		if listening_action.is_empty():
			_on_back_pressed()
		else:
			listening_action = ""
			status_label.text = ""
			_update_all_binding_buttons()
		get_viewport().set_input_as_handled()
		return
	if listening_action.is_empty():
		return
	var key_code := int(key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode)
	if key_code == 0:
		return
	var action := listening_action
	listening_action = ""
	_apply_binding(action, key_code)
	_save_value("controls", action, key_code)
	status_label.text = "Управление сохранено."
	_update_all_binding_buttons()
	get_viewport().set_input_as_handled()


func _apply_binding(action: String, key_code: int) -> void:
	if not InputMap.has_action(action):
		return
	var key_event := InputEventKey.new()
	key_event.physical_keycode = key_code as Key
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, key_event)


func _update_binding_button(action: String) -> void:
	var button := binding_buttons.get(action) as Button
	if button == null:
		return
	if listening_action == action:
		button.text = "Нажмите клавишу…"
		return
	var key_code := 0
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			key_code = int(key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode)
			break
	button.text = OS.get_keycode_string(key_code) if key_code != 0 else "Не назначено"


func _update_all_binding_buttons() -> void:
	for binding in CONTROL_BINDINGS:
		_update_binding_button(String(binding["action"]))


func _on_back_pressed() -> void:
	listening_action = ""
	_save_value("audio", "master_volume", current_volume)
	back_requested.emit()


static func vibration_is_enabled() -> bool:
	if not OS.has_feature("mobile"):
		return false
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return true
	return bool(config.get_value("mobile", "vibration", true))


static func vibrate_if_enabled(duration_ms: int = 35) -> void:
	if vibration_is_enabled():
		Input.vibrate_handheld(duration_ms)
