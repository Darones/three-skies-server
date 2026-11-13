extends CanvasLayer

class AbilityCooldownWipe extends Control:
	var mask_material: ShaderMaterial

	func _init() -> void:
		mask_material = ShaderMaterial.new()
		mask_material.shader = preload("res://shaders/ability_cooldown_mask.gdshader")
		material = mask_material

	func set_progress(value: float) -> void:
		mask_material.set_shader_parameter("progress", clampf(value, 0.0, 1.0))
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)

var game: Node
var kill_feed_box: VBoxContainer = null
var carrier_panel: VBoxContainer = null
var carrier_label: Label = null
var carrier_bar: ProgressBar = null
const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const SETTINGS_PANEL_SCRIPT := preload("res://scripts/settings_panel.gd")
const HERO_PORTRAITS := {
	HeroUnit.Cls.WARRIOR: preload("res://ui/portraits/warrior_portrait.png"),
	HeroUnit.Cls.MAGE: preload("res://ui/portraits/mage_portrait.png"),
	HeroUnit.Cls.FAIRY: preload("res://ui/portraits/fairy_portrait.png"),
}

const ABILITY_SHORT_LABELS := {
	HeroUnit.Cls.WARRIOR: ["СТАН", "КРИТ", "УЛЬТА"],
	HeroUnit.Cls.MAGE: ["СТАН", "ХИЛ", "УЛЬТА"],
	HeroUnit.Cls.FAIRY: ["СТАН", "КРИТ", "БАФ"],
}



var font: FontFile

var score_label: Label
var timer_label: Label
var shell_timer_label: Label
var respawn_label: Label
var gold_label: Label
var player_panel: PanelContainer
var player_portrait: TextureRect
var player_name_label: Label
var player_hp_bar: ProgressBar
var player_hp_label: Label
var player_panel_class := -1
var player_panel_team := -1
var announce_label: Label
var ability_buttons: Array[Button] = []
var icon_class := -1
var ability_wipes: Array[AbilityCooldownWipe] = []
var ability_ready: Array[bool] = []
var ability_name_labels: Array[Label] = []
var ability_key_labels: Array[Label] = []
var select_panel: Control
var end_panel: Control
var end_title: Label
var end_score: Label
var shop_panel: PanelContainer
var shop_dim: ColorRect
var shop_buttons: Dictionary = {}
var ability_row: Control
var announce_tween: Tween
var pause_button: Button
var pause_overlay: Control
var pause_menu_panel: Control
var pause_settings_panel: Control
var tutorial_overlay: ColorRect
var tutorial_title: Label
var tutorial_body: Label
var tutorial_primary_button: Button
var tutorial_secondary_button: Button
var tutorial_hint: Label
var tutorial_primary_action := Callable()
var tutorial_secondary_action := Callable()
var tutorial_ability_index := -1
var low_health_overlay: ColorRect
var low_health_material: ShaderMaterial
var vignette_time := 0.0
var damage_flash := 0.0
var heartbeat_players: Array[AudioStreamPlayer] = []
var heartbeat_timer := 0.0
var heartbeat_second := -1.0

const GOLD := Color(0.96, 0.82, 0.52)
const PALE := Color(0.86, 0.9, 1.0)
const DARK_BG := Color(0.05, 0.05, 0.09, 0.78)
const SHOP_ICON_SHEET: Texture2D = preload("res://assets/shop_icons/e1689879_126a_4ed4_bbba_c3530a6fb655_asset-e1689879-1790940004841-0_1790940004843_4y4cl4qj.png")
const HEARTBEAT_SOUND: AudioStream = preload("res://assets/audio/Soundza_Game_SFX_Pack/hits_impacts/deep_sub_impact.wav")
const ABILITY_ICONS := [
	[
		preload("res://assets/ui/icon/128/004.png"),
		preload("res://assets/ui/icon/128/002.png"),
		preload("res://assets/ui/icon/128/009.png"),
	],
	[
		preload("res://assets/ui/icon/128/011.png"),
		preload("res://assets/ui/icon/128/008.png"),
		preload("res://assets/ui/icon/128/001.png"),
	],
	[
		preload("res://assets/ui/icon/128/003.png"),
		preload("res://assets/ui/icon/128/014.png"),
		preload("res://assets/ui/icon/128/005.png"),
	],
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	font = UI_FONT
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_top(root)
	_build_kill_feed(root)
	_build_carrier_panel(root)
	_build_abilities(root)
	_build_announcement(root)
	var mini_map := preload("res://scripts/minimap.gd").new() as Control
	mini_map.name = "MiniMap"
	mini_map.call("configure", game)
	root.add_child(mini_map)
	_build_select(root)
	_build_end(root)
	_build_shop(root)
	_build_pause_menu(root)
	var navigator := preload("res://scripts/tutorial_navigator.gd").new() as Control
	navigator.name = "TutorialNavigator"
	navigator.z_index = 50
	root.add_child(navigator)
	navigator.call("configure", game)
	_build_low_health_overlay(root)
	_build_tutorial_ui(root)


func _build_low_health_overlay(root: Control) -> void:
	low_health_overlay = ColorRect.new()
	low_health_overlay.name = "LowHealthVignette"
	low_health_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	low_health_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	low_health_overlay.z_index = 20
	low_health_material = ShaderMaterial.new()
	low_health_material.shader = preload("res://shaders/low_health_vignette.gdshader")
	low_health_overlay.material = low_health_material
	root.add_child(low_health_overlay)
	for index in 2:
		var heartbeat := AudioStreamPlayer.new()
		heartbeat.name = "Heartbeat%d" % index
		heartbeat.stream = HEARTBEAT_SOUND
		heartbeat.pitch_scale = 0.72
		heartbeat.volume_db = -20.0
		add_child(heartbeat)
		heartbeat_players.append(heartbeat)


func flash_damage(amount := 0.3) -> void:
	damage_flash = clampf(maxf(damage_flash, amount), 0.0, 1.0)


func _update_low_health_vignette(delta: float) -> void:
	if low_health_material == null:
		return
	vignette_time += delta
	damage_flash = maxf(0.0, damage_flash - delta * 2.6)
	var intensity := damage_flash
	var low_health := false
	var health_fraction := 1.0
	if game != null and game.state == "live" and game.player != null and is_instance_valid(game.player) and not game.player.dead:
		health_fraction = float(game.player.health) / maxf(1.0, float(game.player.max_health))
		if health_fraction < 0.35:
			low_health = true
			var pulse := 0.72 + 0.28 * sin(vignette_time * 5.2)
			intensity = maxf(intensity, clampf((0.35 - health_fraction) / 0.35, 0.0, 1.0) * pulse)
	if low_health:
		_update_heartbeat(delta, health_fraction)
	else:
		heartbeat_timer = 0.0
		heartbeat_second = -1.0
	low_health_material.set_shader_parameter("intensity", clampf(intensity, 0.0, 1.0))


func _update_heartbeat(delta: float, health_fraction: float) -> void:
	if heartbeat_players.size() < 2:
		return
	heartbeat_timer -= delta
	if heartbeat_second > 0.0:
		heartbeat_second -= delta
		if heartbeat_second <= 0.0:
			heartbeat_second = -1.0
			_play_heartbeat(1, health_fraction)
	if heartbeat_timer <= 0.0:
		heartbeat_timer = 1.15
		heartbeat_second = 0.17
		_play_heartbeat(0, health_fraction)


func _play_heartbeat(index: int, health_fraction: float) -> void:
	var heartbeat := heartbeat_players[index]
	heartbeat.volume_db = lerpf(-24.0, -12.0, clampf((0.35 - health_fraction) / 0.35, 0.0, 1.0))
	heartbeat.play()


func _build_tutorial_ui(root: Control) -> void:
	tutorial_overlay = ColorRect.new()
	tutorial_overlay.name = "TutorialDialogOverlay"
	tutorial_overlay.color = Color(0.015, 0.02, 0.04, 0.78)
	tutorial_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	tutorial_overlay.z_index = 100
	tutorial_overlay.visible = false
	root.add_child(tutorial_overlay)

	var panel := PanelContainer.new()
	panel.name = "TutorialDialog"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -360.0
	panel.offset_top = -180.0
	panel.offset_right = 360.0
	panel.offset_bottom = 180.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.78, 0.62, 0.32), Color(0.035, 0.045, 0.07, 0.98)))
	tutorial_overlay.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	panel.add_child(layout)
	tutorial_title = _make_label("", 38, GOLD)
	layout.add_child(tutorial_title)
	tutorial_body = _make_label("", 21, PALE)
	tutorial_body.custom_minimum_size = Vector2(620.0, 150.0)
	tutorial_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layout.add_child(tutorial_body)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	layout.add_child(actions)
	tutorial_primary_button = _pause_action_button("Продолжить", true)
	tutorial_primary_button.pressed.connect(_on_tutorial_primary_pressed)
	actions.add_child(tutorial_primary_button)
	tutorial_secondary_button = _pause_action_button("Пройти ещё раз", false)
	tutorial_secondary_button.visible = false
	tutorial_secondary_button.pressed.connect(_on_tutorial_secondary_pressed)
	actions.add_child(tutorial_secondary_button)

	tutorial_hint = _make_label("", 24, GOLD)
	tutorial_hint.anchor_left = 0.12
	tutorial_hint.anchor_right = 0.88
	tutorial_hint.anchor_top = 0.72
	tutorial_hint.anchor_bottom = 0.72
	tutorial_hint.offset_top = 0.0
	tutorial_hint.offset_bottom = 48.0
	tutorial_hint.add_theme_stylebox_override("normal", _panel_style(Color(0.78, 0.62, 0.32, 0.9), Color(0.035, 0.045, 0.07, 0.86)))
	tutorial_hint.visible = false
	tutorial_hint.z_index = 40
	tutorial_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tutorial_hint)


func show_tutorial_card(title_text: String, body_text: String, button_text: String, action: Callable) -> void:
	tutorial_title.text = title_text
	tutorial_body.text = body_text
	tutorial_primary_button.text = button_text
	tutorial_primary_action = action
	tutorial_secondary_action = Callable()
	tutorial_secondary_button.visible = false
	tutorial_overlay.visible = true
	tutorial_hint.visible = false


func show_tutorial_victory(title_text: String, body_text: String, lobby_action: Callable, repeat_action: Callable) -> void:
	show_tutorial_card(title_text, body_text, "В лобби", lobby_action)
	tutorial_secondary_action = repeat_action
	tutorial_secondary_button.text = "Пройти ещё раз"
	tutorial_secondary_button.visible = true


func hide_tutorial_card() -> void:
	tutorial_overlay.visible = false
	tutorial_primary_action = Callable()
	tutorial_secondary_action = Callable()


func show_tutorial_hint(text: String) -> void:
	_layout_tutorial_hint(shop_panel != null and shop_panel.visible)
	tutorial_hint.text = text
	tutorial_hint.visible = not text.is_empty()


func _layout_tutorial_hint(shop_open: bool) -> void:
	if tutorial_hint == null:
		return
	if shop_open:
		tutorial_hint.anchor_left = 0.012
		tutorial_hint.anchor_right = 0.21
		tutorial_hint.anchor_top = 0.28
		tutorial_hint.anchor_bottom = 0.72
		tutorial_hint.offset_left = 0.0
		tutorial_hint.offset_top = 0.0
		tutorial_hint.offset_right = 0.0
		tutorial_hint.offset_bottom = 0.0
		tutorial_hint.add_theme_font_size_override("font_size", 19)
		tutorial_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tutorial_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tutorial_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	else:
		tutorial_hint.anchor_left = 0.12
		tutorial_hint.anchor_right = 0.88
		tutorial_hint.anchor_top = 0.72
		tutorial_hint.anchor_bottom = 0.72
		tutorial_hint.offset_left = 0.0
		tutorial_hint.offset_top = 0.0
		tutorial_hint.offset_right = 0.0
		tutorial_hint.offset_bottom = 48.0
		tutorial_hint.add_theme_font_size_override("font_size", 24)
		tutorial_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
		tutorial_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tutorial_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _on_tutorial_primary_pressed() -> void:
	var action := tutorial_primary_action
	if action.is_valid():
		action.call()


func _on_tutorial_secondary_pressed() -> void:
	var action := tutorial_secondary_action
	if action.is_valid():
		action.call()


func _panel_style(border: Color, fill := DARK_BG) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_carrier_panel(root: Control) -> void:
	carrier_panel = VBoxContainer.new()
	carrier_panel.name = "CarrierPanel"
	carrier_panel.anchor_left = 0.33
	carrier_panel.anchor_right = 0.67
	carrier_panel.anchor_top = 0.085
	carrier_panel.anchor_bottom = 0.17
	carrier_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carrier_panel.visible = false
	root.add_child(carrier_panel)
	carrier_label = Label.new()
	carrier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	carrier_label.add_theme_font_override("font", UI_FONT)
	carrier_label.add_theme_font_size_override("font_size", 15)
	carrier_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	carrier_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	carrier_panel.add_child(carrier_label)
	carrier_bar = ProgressBar.new()
	carrier_bar.custom_minimum_size = Vector2(0, 8)
	carrier_bar.min_value = 0
	carrier_bar.max_value = 100
	carrier_bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.08, 0.09, 0.13)
	bar_bg.set_corner_radius_all(4)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(1.0, 0.78, 0.28)
	bar_fill.set_corner_radius_all(4)
	carrier_bar.add_theme_stylebox_override("background", bar_bg)
	carrier_bar.add_theme_stylebox_override("fill", bar_fill)
	carrier_panel.add_child(carrier_bar)


func _update_carrier_panel() -> void:
	if carrier_panel == null or not is_instance_valid(carrier_panel):
		return
	if game == null:
		carrier_panel.visible = false
		return
	var carrier_hero = game.carrier
	if carrier_hero == null or not is_instance_valid(carrier_hero) or not bool(carrier_hero.get("carrying")):
		carrier_panel.visible = false
		return
	carrier_panel.visible = not bool(game.get("tutorial_mode"))
	var base_z := 28.0 if int(carrier_hero.get("team")) == 0 else -28.0
	var dist := Vector2(carrier_hero.global_position.x, carrier_hero.global_position.z - base_z).length()
	carrier_bar.value = clampf(100.0 * (1.0 - dist / 70.0), 0.0, 100.0)
	carrier_label.text = "%s несёт осколок" % String(carrier_hero.get("display_name"))


func _build_kill_feed(root: Control) -> void:
	kill_feed_box = VBoxContainer.new()
	kill_feed_box.name = "KillFeed"
	kill_feed_box.anchor_left = 0.70
	kill_feed_box.anchor_right = 0.98
	kill_feed_box.anchor_top = 0.20
	kill_feed_box.anchor_bottom = 0.46
	kill_feed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	kill_feed_box.add_theme_constant_override("separation", 2)
	kill_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(kill_feed_box)


func show_kill_feed(killer: String, victim: String) -> void:
	if kill_feed_box == null or not is_instance_valid(kill_feed_box):
		return
	var label := Label.new()
	label.text = "%s  ⚔  %s" % [killer, victim]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	kill_feed_box.add_child(label)
	while kill_feed_box.get_child_count() > 5:
		var oldest := kill_feed_box.get_child(0)
		kill_feed_box.remove_child(oldest)
		oldest.queue_free()
	var tween := label.create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


func _build_top(root: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "MatchInfo"
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -380.0 if OS.has_feature("mobile") else -360.0
	box.offset_top = 20.0
	box.offset_right = -74.0 if OS.has_feature("mobile") else -20.0
	box.offset_bottom = 142.0
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)

	score_label = _make_label("Свет — 0:0 — Тьма", 24, Color.WHITE)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(score_label)

	gold_label = _make_label("Золото: 0", 18, GOLD)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(gold_label)

	timer_label = _make_label("10:00", 20, Color.WHITE)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(timer_label)

	shell_timer_label = _make_label("Оболочка: 02:00", 16, Color(0.66, 0.68, 0.72))
	shell_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(shell_timer_label)
	shell_timer_label.visible = false

	respawn_label = _make_label("", 32, Color(1.0, 0.38, 0.28))
	respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	respawn_label.visible = false
	box.add_child(respawn_label)
	_build_player_panel(root)
	if OS.has_feature("mobile"):
		pause_button = Button.new()
		pause_button.name = "MobilePauseButton"
		pause_button.text = "☰"
		pause_button.tooltip_text = "Пауза"
		pause_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		pause_button.offset_left = -64.0
		pause_button.offset_top = 20.0
		pause_button.offset_right = -20.0
		pause_button.offset_bottom = 64.0
		pause_button.focus_mode = Control.FOCUS_NONE
		pause_button.add_theme_font_override("font", font)
		pause_button.add_theme_font_size_override("font_size", 23)
		pause_button.add_theme_color_override("font_color", GOLD)
		pause_button.add_theme_stylebox_override("normal", _pause_button_style(false))
		pause_button.add_theme_stylebox_override("hover", _pause_button_style(true))
		pause_button.add_theme_stylebox_override("pressed", _pause_button_style(true))
		pause_button.pressed.connect(_toggle_pause_menu)
		root.add_child(pause_button)


func _pause_button_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.13, 0.93) if not hovered else Color(0.12, 0.16, 0.22, 1.0)
	style.border_color = Color(0.46, 0.54, 0.69, 0.9) if not hovered else Color(0.95, 0.76, 0.38)
	style.set_border_width_all(2)
	style.set_corner_radius_all(22)
	return style


func _build_pause_menu(root: Control) -> void:
	pause_overlay = Control.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.z_index = 50
	pause_overlay.visible = false
	root.add_child(pause_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.005, 0.008, 0.018, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "PauseMenuPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -210.0
	panel.offset_top = -145.0
	panel.offset_right = 210.0
	panel.offset_bottom = 145.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.78, 0.62, 0.32), Color(0.035, 0.045, 0.07, 0.99)))
	pause_overlay.add_child(panel)
	pause_menu_panel = panel

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	panel.add_child(layout)
	var title := _make_label("ПАУЗА", 34, GOLD)
	layout.add_child(title)
	var resume_button := _pause_action_button("Продолжить", true)
	resume_button.pressed.connect(_resume_game)
	layout.add_child(resume_button)
	var settings_button := _pause_action_button("Настройки", false)
	settings_button.pressed.connect(_open_pause_settings)
	layout.add_child(settings_button)
	var exit_button := _pause_action_button("Выйти из игры", false)
	exit_button.pressed.connect(_exit_game)
	layout.add_child(exit_button)

	pause_settings_panel = SETTINGS_PANEL_SCRIPT.new() as Control
	pause_settings_panel.name = "PauseSettingsPanel"
	pause_settings_panel.visible = false
	pause_settings_panel.z_index = 10
	pause_settings_panel.connect("back_requested", _on_pause_settings_back)
	pause_overlay.add_child(pause_settings_panel)


func _pause_action_button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(300.0, 50.0)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", GOLD if primary else PALE)
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.8, 0.65, 0.37, 0.72), Color(0.07, 0.09, 0.13, 0.93)))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.95, 0.76, 0.38), Color(0.12, 0.16, 0.22, 1.0)))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(1.0, 0.88, 0.58), Color(0.18, 0.14, 0.08, 1.0)))
	return button


func _toggle_pause_menu() -> void:
	if pause_overlay.visible:
		_resume_game()
	else:
		_open_pause_menu()


func _open_pause_menu() -> void:
	if game == null or game.state != "live":
		return
	pause_overlay.visible = true
	pause_menu_panel.visible = true
	pause_settings_panel.visible = false
	get_tree().paused = true
	Haptics.vibrate(35)


func _resume_game() -> void:
	pause_overlay.visible = false
	pause_settings_panel.visible = false
	get_tree().paused = false


func _open_pause_settings() -> void:
	pause_menu_panel.visible = false
	pause_settings_panel.visible = true


func _on_pause_settings_back() -> void:
	pause_settings_panel.visible = false
	pause_menu_panel.visible = true


func _exit_game() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or (key_event.keycode != KEY_ESCAPE and key_event.physical_keycode != KEY_ESCAPE):
		return
	if pause_settings_panel != null and pause_settings_panel.visible:
		_on_pause_settings_back()
	elif pause_overlay != null and pause_overlay.visible:
		_resume_game()
	elif game != null and game.state == "live":
		_open_pause_menu()
	get_viewport().set_input_as_handled()


func _build_player_panel(root: Control) -> void:
	player_panel = PanelContainer.new()
	player_panel.name = "PlayerStatus"
	player_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	player_panel.offset_left = 20.0
	player_panel.offset_top = 20.0
	player_panel.offset_right = 350.0
	player_panel.offset_bottom = 94.0
	player_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.76, 0.63, 0.36, 0.62), Color(0.035, 0.035, 0.05, 0.3)))
	root.add_child(player_panel)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_panel.add_child(content)

	var portrait_frame := PanelContainer.new()
	portrait_frame.custom_minimum_size = Vector2(60.0, 60.0)
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_theme_stylebox_override("panel", _panel_style(Color(0.92, 0.76, 0.42, 0.75), Color(0.06, 0.05, 0.05, 0.55)))
	content.add_child(portrait_frame)

	player_portrait = TextureRect.new()
	player_portrait.custom_minimum_size = Vector2(52.0, 52.0)
	player_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	player_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	player_portrait.clip_contents = true
	player_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_child(player_portrait)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	details.add_theme_constant_override("separation", 2)
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(details)

	player_name_label = _make_label("Игрок · Воин Света", 15, Color(0.97, 0.91, 0.79))
	player_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	details.add_child(player_name_label)

	var hp_container := Control.new()
	hp_container.custom_minimum_size = Vector2(0.0, 20.0)
	hp_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(hp_container)

	player_hp_bar = ProgressBar.new()
	player_hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player_hp_bar.min_value = 0.0
	player_hp_bar.max_value = 1.0
	player_hp_bar.value = 1.0
	player_hp_bar.show_percentage = false
	player_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hp_background := StyleBoxFlat.new()
	hp_background.bg_color = Color(0.025, 0.04, 0.035, 0.98)
	hp_background.border_color = Color(0.2, 0.25, 0.19, 0.95)
	hp_background.set_border_width_all(1)
	hp_background.set_corner_radius_all(7)
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.16, 0.79, 0.27, 1.0)
	hp_fill.set_corner_radius_all(6)
	player_hp_bar.add_theme_stylebox_override("background", hp_background)
	player_hp_bar.add_theme_stylebox_override("fill", hp_fill)
	hp_container.add_child(player_hp_bar)

	player_hp_label = _make_label("1050 / 1050", 12, Color.WHITE)
	player_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_container.add_child(player_hp_label)
	player_panel.visible = false


func _build_abilities(root: Control) -> void:
	var is_mobile := OS.has_feature("mobile")
	var row: Control
	if is_mobile:
		row = Control.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		row = HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		row.anchor_left = 1.0
		row.anchor_top = 1.0
		row.anchor_right = 1.0
		row.anchor_bottom = 1.0
		row.offset_left = -296.0
		row.offset_top = -128.0
		row.offset_right = -20.0
		row.offset_bottom = -20.0
		row.add_theme_constant_override("separation", 8)
		row.alignment = BoxContainer.ALIGNMENT_END
	ability_row = row
	root.add_child(row)

	var slot_offsets := [Vector2(-209.0, -150.0), Vector2(-128.0, -231.0), Vector2(-290.0, -231.0)]
	for i in 3:
		var slot := VBoxContainer.new()
		if is_mobile:
			slot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			slot.offset_left = slot_offsets[i].x
			slot.offset_top = slot_offsets[i].y
			slot.offset_right = slot_offsets[i].x + 88.0
			slot.offset_bottom = slot_offsets[i].y + 110.0
			slot.custom_minimum_size = Vector2(88.0, 110.0)
		else:
			slot.custom_minimum_size = Vector2(84.0, 106.0)
		slot.add_theme_constant_override("separation", 2)
		slot.alignment = BoxContainer.ALIGNMENT_CENTER
		var button := Button.new()
		button.text = ""
		button.custom_minimum_size = Vector2(88.0, 88.0) if is_mobile else Vector2(84.0, 84.0)
		button.clip_contents = true
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_override("font", font)
		button.add_theme_font_size_override("font_size", 16 if is_mobile else 28)
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_stylebox_override("normal", _ability_style(true, false))
		button.add_theme_stylebox_override("hover", _ability_style(true, true))
		button.add_theme_stylebox_override("pressed", _ability_style(true, true))
		button.pressed.connect(_on_ability_pressed.bind(i))
		var wipe := AbilityCooldownWipe.new()
		wipe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wipe.z_index = 1
		button.add_child(wipe)
		var icon_rect := TextureRect.new()
		icon_rect.name = "AbilityIcon"
		icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_rect.offset_left = 5.0
		icon_rect.offset_top = 5.0
		icon_rect.offset_right = -5.0
		icon_rect.offset_bottom = -5.0
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_rect.texture = ABILITY_ICONS[0][i]
		var icon_material := ShaderMaterial.new()
		icon_material.shader = preload("res://shaders/ability_icon_mask.gdshader")
		icon_rect.material = icon_material
		icon_rect.z_index = 0
		button.add_child(icon_rect)
		var key_label := _make_label(str(i + 1), 28, Color.WHITE)
		key_label.text = str(ABILITY_SHORT_LABELS[HeroUnit.Cls.WARRIOR][i]) if is_mobile else str(i + 1)
		key_label.add_theme_font_size_override("font_size", 24 if is_mobile else 28)
		key_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		key_label.offset_left = -54.0
		key_label.offset_top = -48.0
		key_label.offset_right = -5.0
		key_label.offset_bottom = -3.0
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		key_label.add_theme_color_override("font_color", Color(0.98, 0.9, 0.7))
		key_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
		key_label.z_index = 2
		key_label.visible = true
		button.add_child(key_label)
		var name_label := _make_label("", 13, PALE)
		name_label.custom_minimum_size = Vector2(84.0 if not is_mobile else 88.0, 20.0)
		name_label.clip_text = true
		name_label.visible = not is_mobile
		slot.add_child(button)
		slot.add_child(name_label)
		row.add_child(slot)
		ability_buttons.append(button)
		ability_wipes.append(wipe)
		ability_ready.append(true)
		ability_name_labels.append(name_label)
		ability_key_labels.append(key_label)

func _ability_style(_is_ready: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var base_color := Color(0.075, 0.09, 0.13)
	style.bg_color = base_color.lightened(0.12) if hovered else base_color
	style.border_color = Color(0.45, 0.55, 0.7, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14 if OS.has_feature("mobile") else 12)
	style.content_margin_left = 2.0
	style.content_margin_right = 2.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style


func _set_ability_ready(index: int, is_ready: bool) -> void:
	ability_ready[index] = is_ready
	_refresh_ability_button_style(index)


func _refresh_ability_icons(cls: int) -> void:
	if cls < 0 or cls >= ABILITY_ICONS.size():
		return
	for index in ability_buttons.size():
		var icon_rect := ability_buttons[index].get_node_or_null("AbilityIcon") as TextureRect
		if icon_rect != null:
			icon_rect.texture = ABILITY_ICONS[cls][index]


func _refresh_ability_button_style(index: int) -> void:
	if index < 0 or index >= ability_buttons.size():
		return
	for style_name in ["normal", "hover", "pressed"]:
		var style := _ability_style(ability_ready[index], style_name != "normal")
		if index == tutorial_ability_index:
			style.border_color = Color(1.0, 0.9, 0.48, 1.0)
			style.set_border_width_all(5)
		ability_buttons[index].add_theme_stylebox_override(style_name, style)


func set_tutorial_ability(index: int) -> void:
	if tutorial_ability_index == index:
		return
	var previous := tutorial_ability_index
	tutorial_ability_index = index
	_refresh_ability_button_style(previous)
	_refresh_ability_button_style(tutorial_ability_index)


func _build_announcement(root: Control) -> void:
	announce_label = _make_label("", 18, GOLD)
	announce_label.anchor_left = 0.0
	announce_label.anchor_right = 1.0
	announce_label.anchor_top = 0.0
	announce_label.anchor_bottom = 0.0
	announce_label.offset_left = 80.0
	announce_label.offset_right = -80.0
	announce_label.offset_top = 100.0
	announce_label.offset_bottom = 140.0
	announce_label.modulate.a = 0.0
	announce_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(announce_label)


func _build_select(root: Control) -> void:
	select_panel = Control.new()
	select_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	select_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(select_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.07, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	select_panel.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -330.0
	box.offset_right = 330.0
	box.offset_top = -210.0
	box.offset_bottom = 170.0
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	select_panel.add_child(box)

	var title := _make_label("ОСКОЛКИ НЕБА", 56, GOLD)
	box.add_child(title)
	var subtitle := _make_label("Выбери героя света", 22, Color(0.85, 0.9, 1.0))
	box.add_child(subtitle)

	var classes := ["Воин — врывается и оглушает", "Маг — лечит и держит лозами", "Фея — бьёт издалека и оглушает"]
	for i in 3:
		var button := Button.new()
		button.custom_minimum_size = Vector2(640, 62)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", _panel_style(Color(0.9, 0.8, 0.55, 0.55)))
		button.add_theme_stylebox_override("hover", _panel_style(Color(1.0, 0.9, 0.65, 0.95), Color(0.1, 0.08, 0.14, 0.9)))
		button.add_theme_stylebox_override("pressed", _panel_style(Color(1.0, 0.95, 0.8, 1.0), Color(0.14, 0.11, 0.18, 0.95)))
		var label := _make_label(str(i + 1) + ".  " + classes[i], 22, PALE)
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		button.add_child(label)
		button.pressed.connect(_on_class_pressed.bind(i))
		box.add_child(button)

	var controls_text := "Джойстик — движение · кнопки справа — способности · цель: 3 осколка" if _uses_touch_controls() else "WASD — движение · 1 2 3 — способности · цель: 3 осколка"
	var hint := _make_label(controls_text, 17, Color(0.75, 0.8, 0.9))
	box.add_child(hint)


func _uses_touch_controls() -> bool:
	return OS.has_feature("mobile") or (OS.has_feature("web") and DisplayServer.is_touchscreen_available())


func _build_shop(root: Control) -> void:
	shop_dim = ColorRect.new()
	shop_dim.name = "ShopDim"
	shop_dim.color = Color(0.02, 0.02, 0.05, 0.68)
	shop_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop_dim.visible = false
	root.add_child(shop_dim)

	shop_panel = PanelContainer.new()
	shop_panel.name = "ShopPanel"
	shop_panel.anchor_left = 0.5
	shop_panel.anchor_top = 0.5
	shop_panel.anchor_right = 0.5
	shop_panel.anchor_bottom = 0.5
	shop_panel.offset_left = -360.0
	shop_panel.offset_top = -245.0
	shop_panel.offset_right = 360.0
	shop_panel.offset_bottom = 245.0
	shop_panel.custom_minimum_size = Vector2.ZERO
	shop_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.68, 0.53, 0.29, 0.95), Color(0.035, 0.04, 0.065, 0.94)))
	shop_panel.visible = false
	root.add_child(shop_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 4)
	shop_panel.add_child(layout)

	var header := Control.new()
	header.custom_minimum_size = Vector2(0.0, 30.0)
	layout.add_child(header)
	var title := _make_label("МАГАЗИН", 28, GOLD)
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.tooltip_text = "Закрыть магазин"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.anchor_left = 1.0
	close_button.anchor_right = 1.0
	close_button.offset_left = -32.0
	close_button.offset_top = 0.0
	close_button.offset_right = 0.0
	close_button.offset_bottom = 30.0
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.add_theme_color_override("font_color", PALE)
	close_button.add_theme_color_override("font_hover_color", Color.WHITE)
	close_button.add_theme_stylebox_override("normal", _panel_style(Color(0.62, 0.49, 0.29, 0.75), Color(0.07, 0.075, 0.11, 0.9)))
	close_button.add_theme_stylebox_override("hover", _panel_style(Color(0.95, 0.36, 0.3, 1.0), Color(0.2, 0.07, 0.07, 0.98)))
	close_button.add_theme_stylebox_override("pressed", _panel_style(Color(1.0, 0.55, 0.42, 1.0), Color(0.25, 0.09, 0.08, 1.0)))
	close_button.pressed.connect(_on_shop_close_pressed)
	header.add_child(close_button)

	var subtitle := _make_label("Улучшения до конца боя · по одной покупке каждого предмета", 14, PALE)
	layout.add_child(subtitle)

	var grid_center := CenterContainer.new()
	grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(grid_center)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.custom_minimum_size = Vector2(640.0, 0.0)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	grid_center.add_child(grid)

	for item in game.get_shop_items():
		var item_id := String(item["id"])
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 122.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", _panel_style(Color(0.47, 0.55, 0.72, 0.8), Color(0.09, 0.105, 0.15, 0.96)))
		button.add_theme_stylebox_override("hover", _panel_style(Color(0.95, 0.77, 0.35, 1.0), Color(0.14, 0.13, 0.16, 0.98)))
		button.add_theme_stylebox_override("pressed", _panel_style(Color(1.0, 0.86, 0.48, 1.0), Color(0.2, 0.17, 0.12, 0.98)))
		button.add_theme_stylebox_override("disabled", _panel_style(Color(0.28, 0.3, 0.35, 0.6), Color(0.055, 0.06, 0.075, 0.8)))
		button.pressed.connect(_on_shop_item_pressed.bind(item_id))

		var content := HBoxContainer.new()
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 10.0
		content.offset_top = 5.0
		content.offset_right = -10.0
		content.offset_bottom = -5.0
		content.add_theme_constant_override("separation", 6)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(content)

		var icon_slot := CenterContainer.new()
		icon_slot.custom_minimum_size = Vector2(58.0, 58.0)
		icon_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(icon_slot)

		var icon := TextureRect.new()
		var custom_texture: Texture2D = game.get_shop_item_texture(item_id) if game != null else null
		icon.texture = custom_texture if custom_texture != null else _shop_icon(int(item["icon"]))
		icon.custom_minimum_size = Vector2(50.0, 50.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_slot.add_child(icon)

		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		details.add_theme_constant_override("separation", 0)
		details.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(details)
		var name_label := _make_label(String(item["name"]), 17, PALE)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.custom_minimum_size = Vector2(0.0, 22.0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		details.add_child(name_label)
		var effect_label := _make_label(String(item["effect"]), 15, Color(0.78, 0.92, 0.8))
		effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect_label.custom_minimum_size = Vector2(0.0, 20.0)
		effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		details.add_child(effect_label)
		var price_label := _make_label("%d Золота" % int(item["price"]), 15, GOLD)
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		details.add_child(price_label)

		grid.add_child(button)
		shop_buttons[item_id] = button
	update_shop()


func _shop_icon(index: int) -> Texture2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = SHOP_ICON_SHEET
	var stride := 256.0
	var inset := 50.0
	var cell_size := 206.0
	var column := index % 4
	var row := floori(float(index) / 4.0)
	atlas.region = Rect2(float(column) * stride + inset, float(row) * stride + inset, cell_size, cell_size)
	return atlas


func _update_player_panel() -> void:
	if player_panel == null or game == null:
		return
	var player := game.player as HeroUnit
	if player == null or game.state == "select":
		player_panel.visible = false
		return
	player_panel.visible = true
	var nickname := String(MetaProgression.player_nickname).strip_edges()
	if nickname.is_empty():
		nickname = "Игрок"
	var faction := "Света" if player.team == 0 else "Тьмы"
	player_name_label.text = "%s · %s %s" % [nickname, HeroUnit.CLASS_DATA[player.hero_class]["name"], faction]
	if player_panel_class != player.hero_class:
		player_panel_class = player.hero_class
		player_portrait.texture = HERO_PORTRAITS[player.hero_class]
	if player_panel_team != player.team:
		player_panel_team = player.team
		var border_color := Color(0.84, 0.68, 0.39, 0.95) if player.team == 0 else Color(0.58, 0.46, 0.78, 0.95)
		player_panel.add_theme_stylebox_override("panel", _panel_style(border_color, Color(0.035, 0.035, 0.05, 0.3)))
	player_hp_bar.max_value = maxf(1.0, player.max_health)
	player_hp_bar.value = clampf(player.health, 0.0, player_hp_bar.max_value)
	player_hp_label.text = "%d / %d" % [roundi(player.health), roundi(player.max_health)]


func set_shop_open(open: bool) -> void:
	if shop_panel == null:
		return
	shop_panel.visible = open
	if shop_dim != null:
		shop_dim.visible = open
	_layout_tutorial_hint(open)
	if open:
		update_shop()


func update_gold() -> void:
	if gold_label != null and game != null:
		gold_label.text = "Золото: %d" % game.gold


func update_shop() -> void:
	if game == null:
		return
	for item in game.get_shop_items():
		var item_id := String(item["id"])
		var button := shop_buttons.get(item_id) as Button
		if button == null:
			continue
		var purchased: bool = item_id in game.purchased_shop_items
		var affordable: bool = game.gold >= int(item["price"])
		var allowed: bool = game.is_shop_item_available(item_id)
		button.disabled = purchased or not affordable or not allowed
		if purchased:
			button.modulate = Color(0.5, 0.5, 0.55, 0.58)
		elif not affordable or not allowed:
			button.modulate = Color(0.65, 0.67, 0.72, 0.7)
		else:
			button.modulate = Color.WHITE


func _on_shop_item_pressed(item_id: String) -> void:
	if game != null:
		game.buy_item(item_id)


func _on_shop_close_pressed() -> void:
	if game != null and game.player != null:
		game.player.dismiss_shop()
	else:
		set_shop_open(false)


func _build_end(root: Control) -> void:
	end_panel = Control.new()
	end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.visible = false
	root.add_child(end_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.68)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -320.0
	box.offset_right = 320.0
	box.offset_top = -140.0
	box.offset_bottom = 120.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	end_panel.add_child(box)
	end_title = _make_label("", 64, GOLD)
	box.add_child(end_title)
	end_score = _make_label("", 30, PALE)
	box.add_child(end_score)


func _on_ability_pressed(index: int) -> void:
	if game != null and game.player != null:
		Haptics.vibrate(25)
		game.player.use_ability(index)


func _on_class_pressed(index: int) -> void:
	if game == null:
		return
	var classes := [HeroUnit.Cls.WARRIOR, HeroUnit.Cls.MAGE, HeroUnit.Cls.FAIRY]
	game.start_match(classes[index])


func hide_class_select() -> void:
	if select_panel != null:
		select_panel.visible = false


func show_announcement(text: String, color: Color, duration: float) -> void:
	if announce_label == null:
		return
	announce_label.text = text
	announce_label.add_theme_color_override("font_color", color)
	if announce_tween != null and announce_tween.is_valid():
		announce_tween.kill()
	announce_tween = create_tween()
	announce_label.modulate.a = 0.0
	announce_tween.tween_property(announce_label, "modulate:a", 1.0, 0.2)
	announce_tween.tween_interval(duration)
	announce_tween.tween_property(announce_label, "modulate:a", 0.0, 0.7)


func _process(_delta: float) -> void:
	_update_low_health_vignette(_delta)
	if game == null:
		return
	if game.player != null and is_instance_valid(game.player) and game.player.hero_class != icon_class:
		icon_class = game.player.hero_class
		_refresh_ability_icons(icon_class)
	if pause_button != null:
		pause_button.visible = game.state == "live"
	update_gold()
	_update_player_panel()
	var match_time_left: float = maxf(0.0, game.match_time)
	var match_minutes := floori(match_time_left / 60.0)
	var match_seconds := int(match_time_left) % 60
	timer_label.text = "%02d:%02d" % [match_minutes, match_seconds]
	if game.sudden_death:
		timer_label.text = "РЕШАЮЩИЙ"
	score_label.text = "Свет — %d:%d — Тьма" % [game.score[0], game.score[1]]
	_update_carrier_panel()
	score_label.visible = not game.tutorial_mode
	timer_label.visible = not game.tutorial_mode
	shell_timer_label.visible = not game.tutorial_mode
	var shell_time_left: float = game.shell_window if game.shell_phase == "active" else game.shell_timer
	shell_time_left = maxf(0.0, shell_time_left)
	var shell_minutes := floori(shell_time_left / 60.0)
	var shell_seconds := int(shell_time_left) % 60
	shell_timer_label.text = "Оболочка: %02d:%02d" % [shell_minutes, shell_seconds]
	if ability_row != null:
		ability_row.visible = game.state != "select"

	if game.player != null:
		var p = game.player
		respawn_label.visible = p.dead
		if p.dead:
			respawn_label.text = "Возрождение: %d" % int(ceil(maxf(0.0, p.respawn_timer)))
		else:
			respawn_label.text = ""
		for i in 3:
			var data: Dictionary = HeroUnit.CLASS_DATA[p.hero_class]["abilities"][i]
			ability_name_labels[i].text = str(ABILITY_SHORT_LABELS[p.hero_class][i])
			if OS.has_feature("mobile"):
				ability_key_labels[i].text = str(ABILITY_SHORT_LABELS[p.hero_class][i])
			var cd: float = p.ability_cds[i]
			var cooldown_length := maxf(0.001, float(data["cd"]) * (1.0 - p.cooldown_reduction))
			var progress := 1.0 if cd <= 0.01 else clampf(1.0 - cd / cooldown_length, 0.0, 1.0)
			ability_wipes[i].set_progress(progress)
			_set_ability_ready(i, cd <= 0.01)
	else:
		respawn_label.visible = false

	if game.state == "over":
		end_panel.visible = true
		end_title.text = game.result_text
		end_title.add_theme_color_override("font_color", Color(0.85, 1.0, 0.7) if game.player_won else Color(1.0, 0.55, 0.5))
		end_score.text = "Свет — %d:%d — Тьма" % [game.score[0], game.score[1]]
