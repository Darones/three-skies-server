extends Control

signal back_requested

const SETTINGS_PATH := "user://settings.cfg"
const LEGACY_SETTINGS_PATH := "user://game_settings.cfg"
const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const CREDITS_SCRIPT = preload("res://credits/licenses.gd")
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
var credits_overlay: ColorRect
var reset_dialog: ConfirmationDialog


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

	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 10)
	scroll.add_child(layout)

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

	layout.add_child(_make_label("ИГРА", 17, Color(0.9, 0.92, 0.98)))
	var credits_button := _make_button("Авторы и лицензии", false)
	credits_button.name = "CreditsButton"
	credits_button.custom_minimum_size = Vector2(0.0, 42.0)
	credits_button.pressed.connect(_open_credits)
	layout.add_child(credits_button)
	var reset_button := _make_danger_button("Сбросить общий прогресс")
	reset_button.name = "ResetProgressButton"
	reset_button.custom_minimum_size = Vector2(0.0, 42.0)
	reset_button.pressed.connect(_confirm_reset_progress)
	layout.add_child(reset_button)
	var reset_hint := _make_label("Удалит сохранения, прогресс и кэш игры.", 13, Color(0.7, 0.74, 0.82))
	reset_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	layout.add_child(reset_hint)

	var show_haptics := mobile_layout and not OS.has_feature("web")
	if show_haptics:
		vibration_toggle = CheckButton.new()
		vibration_toggle.name = "VibrationToggle"
		vibration_toggle.text = "Вибрация"
		vibration_toggle.add_theme_font_override("font", UI_FONT)
		vibration_toggle.add_theme_font_size_override("font_size", 16)
		vibration_toggle.toggled.connect(_on_vibration_toggled)
		layout.add_child(vibration_toggle)
	elif not mobile_layout:
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


func _make_danger_button(text: String) -> Button:
	var button := _make_button(text, false)
	button.add_theme_color_override("font_color", Color(1.0, 0.56, 0.5))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.75, 0.7))
	button.add_theme_stylebox_override("normal", _danger_style(false))
	button.add_theme_stylebox_override("hover", _danger_style(true))
	button.add_theme_stylebox_override("pressed", _danger_style(true))
	return button


func _danger_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.05, 0.06, 0.95) if not hovered else Color(0.3, 0.08, 0.09, 1.0)
	style.border_color = Color(0.85, 0.28, 0.24, 1.0) if not hovered else Color(1.0, 0.45, 0.38, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style


func _text_edit_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.025, 0.04, 0.96)
	style.border_color = Color(0.3, 0.36, 0.48, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _open_credits() -> void:
	if credits_overlay == null:
		_build_credits_overlay()
	credits_overlay.visible = true


func _build_credits_overlay() -> void:
	credits_overlay = ColorRect.new()
	credits_overlay.name = "CreditsOverlay"
	credits_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	credits_overlay.color = Color(0.005, 0.008, 0.018, 0.92)
	credits_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	credits_overlay.z_index = 400
	add_child(credits_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	credits_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "CreditsPanel"
	panel.custom_minimum_size = Vector2(760, 600)
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
	center.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	panel.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := _make_label("АВТОРЫ И ЛИЦЕНЗИИ", 24, Color(0.95, 0.76, 0.38))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(title)
	var close_button := _make_button("×", false)
	close_button.custom_minimum_size = Vector2(44, 40)
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.pressed.connect(_close_credits)
	header.add_child(close_button)
	var text_edit := TextEdit.new()
	text_edit.name = "CreditsText"
	text_edit.text = CREDITS_SCRIPT.TEXT
	text_edit.editable = false
	text_edit.custom_minimum_size = Vector2(0, 460)
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.add_theme_font_override("font", UI_FONT)
	text_edit.add_theme_font_size_override("font_size", 15)
	text_edit.add_theme_color_override("font_color", Color(0.88, 0.9, 0.96))
	text_edit.add_theme_stylebox_override("normal", _text_edit_style())
	layout.add_child(text_edit)
	var close_bottom := _make_button("Закрыть", true)
	close_bottom.custom_minimum_size = Vector2(0.0, 44.0)
	close_bottom.pressed.connect(_close_credits)
	layout.add_child(close_bottom)


func _close_credits() -> void:
	if credits_overlay != null:
		credits_overlay.visible = false


func _confirm_reset_progress() -> void:
	if reset_dialog != null and is_instance_valid(reset_dialog):
		reset_dialog.queue_free()
	reset_dialog = ConfirmationDialog.new()
	reset_dialog.title = "Сбросить общий прогресс?"
	reset_dialog.dialog_text = "Вы потеряете всё, что успели накопить: уровни, осколки, покупки, статистику и ник. Это действие нельзя отменить."
	reset_dialog.get_ok_button().text = "Сбросить"
	reset_dialog.get_cancel_button().text = "Отмена"
	reset_dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reset_dialog.min_size = Vector2i(520, 0)
	reset_dialog.confirmed.connect(_reset_progress)
	add_child(reset_dialog)
	reset_dialog.popup_centered()


func _reset_progress() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		for file in ["lobby.cfg", "stats.cfg", "tutorial.cfg", "tutorial_done.cfg", "meta_save.cfg"]:
			if dir.file_exists(file):
				dir.remove(file)
	MetaProgression.reset_all()
	if OS.has_feature("web"):
		var script := """
		(function() {
			function reload() {
				var url = new URL(location.href);
				url.searchParams.set('reset', Date.now().toString());
				location.replace(url.toString());
			}
			var work = Promise.resolve();
			if ('caches' in window) {
				work = work.then(function() {
					return caches.keys().then(function(keys) {
						return Promise.all(keys.map(function(key) { return caches.delete(key); }));
					});
				});
			}
			if ('serviceWorker' in navigator) {
				work = work.then(function() {
					return navigator.serviceWorker.getRegistrations().then(function(registrations) {
						return Promise.all(registrations.map(function(registration) { return registration.unregister(); }));
					});
				});
			}
			work.then(reload).catch(reload);
		})();
		"""
		JavaScriptBridge.eval(script)
	else:
		get_tree().reload_current_scene()


func _load_settings() -> void:
	var config := _load_settings_config()
	var has_settings := not config.get_sections().is_empty()
	var saved_volume := float(config.get_value("audio", "master_volume", 1.0)) if has_settings else 1.0
	current_volume = clampf(saved_volume, 0.0, 1.0)
	volume_slider.set_value_no_signal(clampf(saved_volume, 0.0, 1.0))
	_apply_volume(saved_volume)
	if vibration_toggle != null:
		vibration_toggle.set_pressed_no_signal(Haptics.is_enabled())
	if not mobile_layout and has_settings:
		for binding in CONTROL_BINDINGS:
			var action := String(binding["action"])
			if config.has_section_key("controls", action):
				_apply_binding(action, int(config.get_value("controls", action)))
		for binding in CONTROL_BINDINGS:
			_update_binding_button(String(binding["action"]))


func _load_settings_config() -> ConfigFile:
	var config := ConfigFile.new()
	var has_settings := config.load(SETTINGS_PATH) == OK
	var legacy := ConfigFile.new()
	var has_legacy := legacy.load(LEGACY_SETTINGS_PATH) == OK
	if not has_settings and has_legacy:
		for section in legacy.get_sections():
			for key in legacy.get_section_keys(section):
				config.set_value(section, key, legacy.get_value(section, key))
		has_settings = true
	elif has_settings and has_legacy:
		for section in legacy.get_sections():
			for key in legacy.get_section_keys(section):
				if not config.has_section_key(section, key):
					config.set_value(section, key, legacy.get_value(section, key))
					has_settings = true
	if has_settings:
		config.save(SETTINGS_PATH)
	return config


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
	Haptics.set_enabled(enabled)
	if enabled:
		Haptics.vibrate(35)


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
		if credits_overlay != null and credits_overlay.visible:
			_close_credits()
			get_viewport().set_input_as_handled()
			return
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
