extends CanvasLayer

signal tutorial_skip_requested

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

## Tiny table glyph above the mobile "СЧЁТ" caption: three rows, each a name
## cell and a score bar, drawn in gold so the button reads as a player table.
class ScoreboardGlyph extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(26.0, 17.0)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var width := maxf(22.0, size.x)
		var cell := Color(0.97, 0.84, 0.55, 0.98)
		var row := Color(0.88, 0.71, 0.36, 0.82)
		for index in 3:
			var y := 1.0 + float(index) * 5.5
			draw_rect(Rect2(1.0, y, 3.5, 3.5), cell)
			draw_rect(Rect2(7.0, y, width - 8.0, 3.5), row)

var game: Node
var kill_feed_box: VBoxContainer = null
var team_icons: Dictionary = {}
var carrier_panel: VBoxContainer = null
var carrier_label: Label = null
var carrier_bar: ProgressBar = null
const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const SETTINGS_PANEL_SCRIPT := preload("res://scripts/settings_panel.gd")
const RULES_PANEL_SCRIPT := preload("res://scripts/rules_panel.gd")
const SkinCatalog = preload("res://scripts/skin_catalog.gd")
const HERO_PORTRAITS := {
	HeroUnit.Cls.WARRIOR: preload("res://assets/ui/heroes/warrior_face.webp"),
	HeroUnit.Cls.MAGE: preload("res://assets/ui/heroes/mage_face.webp"),
	HeroUnit.Cls.FAIRY: preload("res://assets/ui/heroes/archer_face.webp"),
}
const ABILITY_SHORT_LABELS := {
	HeroUnit.Cls.WARRIOR: ["СТАН", "КРИТ", "УЛЬТА"],
	HeroUnit.Cls.MAGE: ["СТАН", "ХИЛ", "УЛЬТА"],
	HeroUnit.Cls.FAIRY: ["СТАН", "КРИТ", "БАФ"],
}

# Временный отладочный оверлей производительности. Выключить после тестов.
const PERF_MONITOR_ENABLED := false



var font: FontFile

var score_label: Label
var timer_label: Label
var shell_timer_label: Label
var gold_label: Label
var player_panel: PanelContainer
var player_avatar: TextureRect
var player_team_label: Label
var player_name_label: Label
var player_team_icon: TextureRect
var player_hp_bar: ProgressBar
var player_hp_label: Label
var player_panel_class := -1
var player_panel_skin := -1
var player_panel_team := -1
var player_name_font_size := -1
var announce_label: Label
var center_respawn_label: Label
var stun_badge: PanelContainer
var stun_badge_label: Label
var ability_buttons: Array[Button] = []
var icon_class := -1
var ability_wipes: Array[AbilityCooldownWipe] = []
var ability_wipe_progress: Array[float] = [-1.0, -1.0, -1.0]
var ability_ready: Array[bool] = []
var ability_name_labels: Array[Label] = []
var ability_key_labels: Array[Label] = []
var select_panel: Control
var end_panel: Control
var end_title: Label
var end_score: Label
var shop_panel: PanelContainer
var shop_scroll: ScrollContainer
var shop_hint_label: Label
var shop_highlight: Panel
var tutorial_shop_item := ""
var focus_panel: Panel
var focus_target: Control
var focus_manual_rect := Rect2()
var focus_use_manual := false
var minimap_control: Control
var shop_dim: ColorRect
var shop_buttons: Dictionary = {}
var ability_row: Control
var ability_slots: Array[Control] = []
var match_info_box: Control = null
var touch_joystick: Control
var announce_tween: Tween
var pause_title_label: Label
var pause_resume_button: Button
var pause_overlay: Control
var pause_menu_panel: Control
var pause_settings_panel: Control
var pause_rules_panel: Control
# Battle scoreboard: Tab on desktop, a tile right of the player card on touch.
var scoreboard_button: Button
var scoreboard_button_label: Label
var scoreboard_panel: PanelContainer
var scoreboard_scroll: ScrollContainer
var scoreboard_rows: VBoxContainer
var scoreboard_score_label: Label
var scoreboard_hint_label: Label
var scoreboard_report_overlay: ColorRect
var scoreboard_report_target_label: Label
var scoreboard_report_reason: OptionButton
var scoreboard_report_status: Label
var scoreboard_report_submit: Button
var scoreboard_report_target := ""
var scoreboard_refresh_tick := 0.0
var tutorial_overlay: ColorRect
var tutorial_title: Label
var tutorial_body: Label
var tutorial_primary_button: Button
var tutorial_secondary_button: Button
var tutorial_card_panel: PanelContainer
var tutorial_card_box: VBoxContainer
var tutorial_card_modal := false
var tutorial_hint: Label
var tutorial_side_hint: Label
var tutorial_primary_action := Callable()
var tutorial_secondary_action := Callable()
var tutorial_ability_index := -1
var tutorial_press_label: Label
var tutorial_skip_button: Button
var fade_overlay: ColorRect
var tutorial_pulse := 0.0
var tutorial_style_pulse := -1.0
var hud_tick := 0.0
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
const HEARTBEAT_SOUND: AudioStream = preload("res://assets/audio/Soundza_Game_SFX_Pack/hits_impacts/deep_sub_impact.mp3")
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
	_apply_safe_area(root)

	_build_top(root)
	_build_stun_badge(root)
	_build_kill_feed(root)
	_build_carrier_panel(root)
	_build_abilities(root)
	if _uses_touch_controls():
		_build_touch_joystick(root)
	_build_announcement(root)
	_build_respawn_label(root)
	var mini_map := preload("res://scripts/minimap.gd").new() as Control
	mini_map.name = "MiniMap"
	mini_map.call("configure", game)
	root.add_child(mini_map)
	minimap_control = mini_map
	_build_select(root)
	_build_end(root)
	_build_shop(root)
	_build_pause_menu(root)
	_build_scoreboard(root)
	_build_focus_panel(root)
	if not NetworkClient.report_completed.is_connected(_on_scoreboard_report_completed):
		NetworkClient.report_completed.connect(_on_scoreboard_report_completed)
	var navigator := preload("res://scripts/tutorial_navigator.gd").new() as Control
	navigator.name = "TutorialNavigator"
	navigator.z_index = 50
	root.add_child(navigator)
	navigator.call("configure", game)
	_build_low_health_overlay(root)
	_build_tutorial_ui(root)
	if PERF_MONITOR_ENABLED:
		var perf := preload("res://scripts/perf_monitor.gd").new() as Control
		perf.name = "PerfMonitor"
		root.add_child(perf)
		perf.call("configure", game)
	_register_ui_layout()


func _register_ui_layout() -> void:
	if not DeviceProfile.mobile_ui:
		return
	UiLayout.register("hud.match_info", match_info_box, "Счёт и таймер", "battle")
	UiLayout.register("hud.player_card", player_panel, "Карточка игрока", "battle")
	UiLayout.register("hud.kill_feed", kill_feed_box, "Лента убийств", "battle")
	UiLayout.register("hud.minimap", minimap_control, "Миникарта", "battle")
	for index in ability_slots.size():
		UiLayout.register(
			"hud.ability_%d" % (index + 1),
			ability_slots[index],
			"Скилл %d" % (index + 1),
			"battle"
		)
	if touch_joystick != null:
		UiLayout.register("hud.joystick", touch_joystick, "Джойстик", "battle")


func _apply_safe_area(root: Control) -> void:
	if not (OS.has_feature("mobile") or OS.has_feature("web")):
		return
	var screen_size := Vector2(DisplayServer.window_get_size())
	if screen_size.x <= 0.0 or screen_size.y <= 0.0:
		return
	var safe := DisplayServer.get_display_safe_area()
	var viewport_size := get_viewport().get_visible_rect().size
	var ratio := viewport_size / screen_size
	var left := float(safe.position.x) * ratio.x
	var top := float(safe.position.y) * ratio.y
	var right := float(screen_size.x - safe.end.x) * ratio.x
	var bottom := float(screen_size.y - safe.end.y) * ratio.y
	if left + right + top + bottom <= 0.0:
		return
	root.offset_left = left
	root.offset_top = top
	root.offset_right = -right
	root.offset_bottom = -bottom


func _build_touch_joystick(root: Control) -> void:
	var joystick := preload("res://scripts/touch_joystick.gd").new() as Control
	joystick.name = "TouchJoystick"
	joystick.anchor_left = 0.02
	joystick.anchor_top = 1.0
	joystick.anchor_right = 0.02
	joystick.anchor_bottom = 1.0
	joystick.offset_left = 0.0
	joystick.offset_top = -240.0
	joystick.offset_right = 240.0
	joystick.offset_bottom = 0.0
	joystick.mouse_filter = Control.MOUSE_FILTER_STOP
	touch_joystick = joystick
	root.add_child(joystick)


func _build_low_health_overlay(root: Control) -> void:
	low_health_overlay = ColorRect.new()
	low_health_overlay.name = "LowHealthVignette"
	low_health_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	low_health_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Behind the HUD: the red vignette must not tint the HP bars and buttons.
	low_health_overlay.z_index = -10
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
	tutorial_overlay.color = Color(0.015, 0.02, 0.04, 0.0)
	tutorial_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_overlay.z_index = 100
	tutorial_overlay.visible = false
	root.add_child(tutorial_overlay)

	# Stage cards are notifications in the left column, under the player card.
	# The panel never blocks input: the match keeps running behind it.
	var panel := PanelContainer.new()
	panel.name = "TutorialDialog"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.78, 0.62, 0.32), Color(0.035, 0.045, 0.07, 0.98)))
	tutorial_overlay.add_child(panel)
	tutorial_card_panel = panel
	var layout := VBoxContainer.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 6)
	panel.add_child(layout)
	tutorial_card_box = layout
	tutorial_title = _make_label("", 24, GOLD)
	tutorial_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tutorial_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(tutorial_title)
	tutorial_body = _make_label("", 16, PALE)
	tutorial_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	tutorial_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	layout.add_child(tutorial_body)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_BEGIN
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_theme_constant_override("separation", 8)
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

	tutorial_side_hint = _make_label("", 15, Color(0.95, 0.93, 0.86))
	tutorial_side_hint.name = "TutorialSideHint"
	tutorial_side_hint.anchor_left = 0.02
	tutorial_side_hint.anchor_right = 0.28
	tutorial_side_hint.anchor_top = 0.0
	tutorial_side_hint.anchor_bottom = 0.0
	tutorial_side_hint.offset_left = 0.0
	tutorial_side_hint.offset_right = 0.0
	tutorial_side_hint.offset_top = 104.0
	tutorial_side_hint.offset_bottom = 214.0
	tutorial_side_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_side_hint.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	tutorial_side_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tutorial_side_hint.add_theme_stylebox_override("normal", _panel_style(Color(0.78, 0.62, 0.32, 0.9), Color(0.035, 0.045, 0.07, 0.92)))
	tutorial_side_hint.add_theme_font_size_override("font_size", _fs(15))
	tutorial_side_hint.visible = false
	tutorial_side_hint.z_index = 40
	tutorial_side_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tutorial_side_hint)

	tutorial_press_label = _make_label("", 18, Color(1.0, 0.92, 0.55))
	tutorial_press_label.name = "TutorialPressHint"
	tutorial_press_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_press_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial_press_label.add_theme_stylebox_override("normal", _panel_style(Color(1.0, 0.9, 0.5, 0.9), Color(0.03, 0.04, 0.07, 0.9)))
	tutorial_press_label.z_index = 45
	tutorial_press_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_press_label.visible = false
	root.add_child(tutorial_press_label)

	tutorial_skip_button = _pause_action_button("Пропустить обучение", false)
	tutorial_skip_button.name = "TutorialSkipButton"
	tutorial_skip_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tutorial_skip_button.anchor_left = 1.0
	tutorial_skip_button.anchor_right = 1.0
	tutorial_skip_button.offset_left = -292.0
	tutorial_skip_button.offset_top = 18.0
	tutorial_skip_button.offset_right = -18.0
	tutorial_skip_button.offset_bottom = 66.0
	tutorial_skip_button.custom_minimum_size = Vector2(274.0, 48.0)
	tutorial_skip_button.add_theme_font_size_override("font_size", _fs(16))
	tutorial_skip_button.z_index = 110
	tutorial_skip_button.visible = false
	tutorial_skip_button.pressed.connect(func() -> void: tutorial_skip_requested.emit())
	root.add_child(tutorial_skip_button)

	fade_overlay = ColorRect.new()
	fade_overlay.name = "TutorialFade"
	fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_overlay.color = Color(0.0, 0.0, 0.0, 1.0)
	fade_overlay.modulate.a = 0.0
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	fade_overlay.z_index = 200
	fade_overlay.visible = false
	root.add_child(fade_overlay)

	if not get_viewport().size_changed.is_connected(_on_tutorial_viewport_resized):
		get_viewport().size_changed.connect(_on_tutorial_viewport_resized)


func fade_teleport(action: Callable, duration := 0.25) -> void:
	if fade_overlay == null or not is_instance_valid(fade_overlay):
		action.call()
		return
	fade_overlay.visible = true
	fade_overlay.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 1.0, duration * 0.5)
	tween.tween_callback(action)
	tween.tween_property(fade_overlay, "modulate:a", 0.0, duration * 0.5)
	tween.tween_callback(func() -> void: fade_overlay.visible = false)


func set_tutorial_skip_visible(value: bool) -> void:
	if tutorial_skip_button != null and is_instance_valid(tutorial_skip_button):
		tutorial_skip_button.visible = value
		if value:
			_layout_tutorial_skip_button()
			_refresh_skip_layout_after_show()


func _refresh_skip_layout_after_show() -> void:
	# The match-info VBox has not laid out its hidden score/timer children on
	# the first frame of the match, so the gold line rect is still provisional.
	# Reposition after two frames, when the rect is final.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if tutorial_skip_button != null and is_instance_valid(tutorial_skip_button) and tutorial_skip_button.visible:
		_layout_tutorial_skip_button()


func _layout_tutorial_skip_button() -> void:
	# The top-right match info keeps "Золото" on the first visible line in the
	# tutorial (score and timer are hidden). Put the skip plate just under it
	# instead of on top of it: on desktop the old rect covered the gold line
	# completely, on mobile it clipped the last pixels at the screen edge.
	if tutorial_skip_button == null or not is_instance_valid(tutorial_skip_button):
		return
	var viewport_size := _hud_viewport_size()
	var width := minf(274.0, maxf(180.0, viewport_size.x - 36.0))
	var top := 18.0
	if gold_label != null and is_instance_valid(gold_label) and gold_label.is_visible_in_tree():
		var origin := Vector2.ZERO
		var hud_root := get_child(0) as Control if get_child_count() > 0 else null
		if hud_root != null:
			origin = hud_root.global_position
		top = maxf(top, gold_label.get_global_rect().end.y - origin.y + 6.0)
	tutorial_skip_button.anchor_left = 1.0
	tutorial_skip_button.anchor_top = 0.0
	tutorial_skip_button.anchor_right = 1.0
	tutorial_skip_button.anchor_bottom = 0.0
	tutorial_skip_button.offset_left = -width - 18.0
	tutorial_skip_button.offset_top = top
	tutorial_skip_button.offset_right = -18.0
	tutorial_skip_button.offset_bottom = top + 48.0
	tutorial_skip_button.custom_minimum_size = Vector2(width, 48.0)


func show_tutorial_card(title_text: String, body_text: String, button_text: String, action: Callable) -> void:
	_set_tutorial_card_content(title_text, body_text, button_text, action)
	# Notice card: left column, no action button, input passes through.
	_layout_tutorial_card(false)


func show_tutorial_victory(title_text: String, body_text: String, lobby_action: Callable, repeat_action: Callable) -> void:
	_set_tutorial_card_content(title_text, body_text, "В лобби", lobby_action)
	set_tutorial_skip_visible(false)
	tutorial_secondary_action = repeat_action
	tutorial_secondary_button.text = "Пройти ещё раз"
	tutorial_secondary_button.visible = true
	# A real choice: centred, blocking, with buttons.
	_layout_tutorial_card(true)


func show_tutorial_choice(title_text: String, body_text: String, primary_text: String, primary_action: Callable, secondary_text: String, secondary_action: Callable) -> void:
	_set_tutorial_card_content(title_text, body_text, primary_text, primary_action)
	tutorial_secondary_action = secondary_action
	tutorial_secondary_button.text = secondary_text
	tutorial_secondary_button.visible = true
	_layout_tutorial_card(true)


func _set_tutorial_card_content(title_text: String, body_text: String, button_text: String, action: Callable) -> void:
	tutorial_title.text = title_text
	tutorial_body.text = body_text
	tutorial_primary_button.text = button_text
	tutorial_primary_action = action
	# An empty button text means "notification": nothing to press, the next
	# stage starts on its own (see tutorial_controller._auto_advance).
	tutorial_primary_button.visible = not button_text.is_empty() and action.is_valid()
	tutorial_secondary_action = Callable()
	tutorial_secondary_button.visible = false
	tutorial_overlay.visible = true
	tutorial_hint.visible = false
	if tutorial_side_hint != null:
		tutorial_side_hint.visible = false


func _hud_viewport_size() -> Vector2:
	var size := get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		size = Vector2(960.0, 540.0)
	return size


func _layout_tutorial_card(modal: bool) -> void:
	if tutorial_card_panel == null or not is_instance_valid(tutorial_card_panel):
		return
	tutorial_card_modal = modal
	var viewport_size := _hud_viewport_size()
	if modal:
		# "Пропустить обучение?" and the victory screen keep their buttons and
		# block the field: these are real choices, not stage notifications.
		tutorial_overlay.color = Color(0.015, 0.02, 0.04, 0.55)
		tutorial_card_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		tutorial_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tutorial_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tutorial_title.add_theme_font_size_override("font_size", _fs(26))
		tutorial_body.add_theme_font_size_override("font_size", _fs(16))
		var width := minf(660.0, viewport_size.x - 40.0)
		var height := minf(_tutorial_card_height(width), viewport_size.y - 40.0)
		tutorial_card_panel.anchor_left = 0.5
		tutorial_card_panel.anchor_top = 0.5
		tutorial_card_panel.anchor_right = 0.5
		tutorial_card_panel.anchor_bottom = 0.5
		tutorial_card_panel.offset_left = -width * 0.5
		tutorial_card_panel.offset_top = -height * 0.5
		tutorial_card_panel.offset_right = width * 0.5
		tutorial_card_panel.offset_bottom = height * 0.5
		return
	# Notice card: left edge under the player card (owner: "сюда перенеси"),
	# never over the avatar card or the left thumb joystick.
	tutorial_overlay.color = Color(0.015, 0.02, 0.04, 0.0)
	tutorial_card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tutorial_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tutorial_title.add_theme_font_size_override("font_size", _fs(24))
	tutorial_body.add_theme_font_size_override("font_size", _fs(16))
	var left := 20.0
	var top := 104.0
	var width := minf(380.0, viewport_size.x - 40.0)
	if player_panel != null and is_instance_valid(player_panel) and player_panel.visible:
		left = maxf(16.0, player_panel.position.x)
		top = player_panel.position.y + player_panel.size.y + 10.0
		width = clampf(player_panel.size.x, 280.0, viewport_size.x - left - 20.0)
	var bottom_limit := viewport_size.y - 16.0
	if touch_joystick != null and is_instance_valid(touch_joystick) and touch_joystick.visible:
		# Same parent (the HUD root), so `position` and `size` are comparable.
		bottom_limit = minf(bottom_limit, touch_joystick.position.y - 8.0)
	var max_height := maxf(96.0, bottom_limit - top)
	var height := minf(_tutorial_card_height(width), max_height)
	tutorial_card_panel.anchor_left = 0.0
	tutorial_card_panel.anchor_top = 0.0
	tutorial_card_panel.anchor_right = 0.0
	tutorial_card_panel.anchor_bottom = 0.0
	tutorial_card_panel.offset_left = left
	tutorial_card_panel.offset_top = top
	tutorial_card_panel.offset_right = left + width
	tutorial_card_panel.offset_bottom = top + height


func _tutorial_card_height(width: float) -> float:
	# PanelContainer does not shrink to an autowrapped Label, so the height is
	# measured from the current texts instead of guessed.
	var inner := maxf(120.0, width - 28.0)
	var title_height := 0.0
	if not tutorial_title.text.is_empty():
		title_height = tutorial_title.get_theme_font("font").get_multiline_string_size(
			tutorial_title.text,
			HORIZONTAL_ALIGNMENT_LEFT,
			inner,
			tutorial_title.get_theme_font_size("font_size")
		).y
	var body_height := 0.0
	if not tutorial_body.text.is_empty():
		body_height = tutorial_body.get_theme_font("font").get_multiline_string_size(
			tutorial_body.text,
			HORIZONTAL_ALIGNMENT_LEFT,
			inner,
			tutorial_body.get_theme_font_size("font_size")
		).y
	var actions_height := 0.0
	if tutorial_primary_button.visible:
		actions_height = tutorial_primary_button.get_combined_minimum_size().y + 6.0
	if tutorial_secondary_button.visible:
		actions_height = maxf(actions_height, tutorial_secondary_button.get_combined_minimum_size().y + 6.0)
	return 16.0 + title_height + 6.0 + body_height + actions_height + 4.0


func hide_tutorial_card() -> void:
	tutorial_overlay.visible = false
	tutorial_primary_action = Callable()
	tutorial_secondary_action = Callable()


func minimap_ping(world_position: Vector3, color: Color = Color(1.0, 0.82, 0.32), duration := 2.0) -> void:
	if minimap_control != null and is_instance_valid(minimap_control):
		minimap_control.call("ping", world_position, color, duration)


func show_tutorial_hint(text: String) -> void:
	# Owner: every tutorial message lives in the top strip. The shop keeps its
	# own label hidden so nothing is written twice.
	if shop_hint_label != null:
		shop_hint_label.visible = false
	_layout_tutorial_hint(false)
	tutorial_hint.text = text
	tutorial_hint.visible = not text.is_empty()


func show_tutorial_side_hint(text: String) -> void:
	# The left plate is gone (owner: the strip is the only hint). The label is
	# still laid out but never shown, so older probes keep a valid rect.
	if tutorial_side_hint == null:
		return
	tutorial_side_hint.text = text
	_layout_tutorial_side_hint()
	tutorial_side_hint.visible = false
	show_tutorial_hint(text)


func hide_tutorial_side_hint() -> void:
	if tutorial_side_hint != null:
		tutorial_side_hint.visible = false


func _layout_tutorial_hint(_shop_open: bool) -> void:
	if tutorial_hint == null:
		return
	_layout_tutorial_skip_button()
	var viewport_size := tutorial_hint.get_parent_area_size()
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	# The always-on strip lives at the very top, between the player card and
	# the skip button. It must never cover either corner.
	var left := 12.0
	var right := viewport_size.x - 12.0
	if player_panel != null and is_instance_valid(player_panel):
		left = player_panel.position.x + player_panel.size.x + 12.0
	if tutorial_skip_button != null and is_instance_valid(tutorial_skip_button):
		right = tutorial_skip_button.position.x - 12.0
	var top := 18.0
	var height := 48.0
	# Very narrow phones leave no room between the avatar and "Пропустить".
	# In that case drop the strip just below the top row and use full width.
	if right - left < 220.0:
		left = 12.0
		right = viewport_size.x - 12.0
		top = 102.0
		height = 48.0
	tutorial_hint.anchor_left = 0.0
	tutorial_hint.anchor_right = 0.0
	tutorial_hint.anchor_top = 0.0
	tutorial_hint.anchor_bottom = 0.0
	tutorial_hint.offset_left = left
	tutorial_hint.offset_right = right
	tutorial_hint.offset_top = top
	tutorial_hint.offset_bottom = top + height
	# Keep the project's mobile minimum (18) instead of shrinking to 13:
	# the strip grows downwards when the text needs a second line.
	tutorial_hint.add_theme_font_size_override("font_size", _fs(18))
	tutorial_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _layout_tutorial_side_hint() -> void:
	if tutorial_side_hint == null or player_panel == null or not is_instance_valid(player_panel):
		return
	# The fountain/shop hint sits exactly under the player card: same left
	# edge, same width, never wider than the avatar + nickname card.
	var left := player_panel.position.x
	var width := player_panel.size.x
	var top := player_panel.position.y + player_panel.size.y + 8.0
	tutorial_side_hint.anchor_left = 0.0
	tutorial_side_hint.anchor_right = 0.0
	tutorial_side_hint.anchor_top = 0.0
	tutorial_side_hint.anchor_bottom = 0.0
	tutorial_side_hint.offset_left = left
	tutorial_side_hint.offset_right = left + width
	tutorial_side_hint.offset_top = top
	tutorial_side_hint.offset_bottom = top + 76.0
	tutorial_side_hint.add_theme_font_size_override("font_size", _fs(15))
	tutorial_side_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _on_tutorial_viewport_resized() -> void:
	call_deferred("_refresh_tutorial_layout_after_resize")


func _refresh_tutorial_layout_after_resize() -> void:
	# UiLayout re-applies its own overrides deferred as well; wait two frames
	# so the player card has its final rect before pinning the hints to it.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if shop_panel != null and is_instance_valid(shop_panel) and shop_panel.visible:
		_layout_shop_panel()
	_layout_tutorial_hint(false)
	if tutorial_overlay != null and is_instance_valid(tutorial_overlay) and tutorial_overlay.visible:
		_layout_tutorial_card(tutorial_card_modal)
	if tutorial_side_hint != null and tutorial_side_hint.visible:
		_layout_tutorial_side_hint()


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


## The player card keeps its dark plate but no border: the team is already
## shown by the icon and the word on the name row, and the extra frame read
## as a second box around the portrait. Tight vertical padding lets the 52px
## portrait fit the 61px phone card authored in ui_layout.json.
func _player_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.035, 0.05, 0.3)
	style.border_color = Color(0.0, 0.0, 0.0, 0.0)
	style.set_border_width_all(0)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", _fs(size))
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
	carrier_label.add_theme_font_size_override("font_size", _fs(15))
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
	# 0% — момент подбора у алтаря, 100% — база
	var max_dist := 28.0
	carrier_bar.value = clampf(100.0 * (1.0 - dist / max_dist), 0.0, 100.0)
	carrier_label.text = "%s несёт осколок" % String(carrier_hero.get("display_name"))


func _build_kill_feed(root: Control) -> void:
	kill_feed_box = VBoxContainer.new()
	kill_feed_box.name = "KillFeed"
	kill_feed_box.anchor_left = 0.02
	kill_feed_box.anchor_right = 0.30
	kill_feed_box.anchor_top = 0.24
	kill_feed_box.anchor_bottom = 0.45
	kill_feed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	kill_feed_box.add_theme_constant_override("separation", 2)
	kill_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(kill_feed_box)


func show_kill_feed(killer: String, victim: String, killer_team: int = 0, victim_team: int = 1) -> void:
	if kill_feed_box == null or not is_instance_valid(kill_feed_box):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_team_icon_control(killer_team))
	row.add_child(_make_feed_name(killer, killer_team))
	row.add_child(_make_feed_name("x", -1))
	row.add_child(_team_icon_control(victim_team))
	row.add_child(_make_feed_name(victim, victim_team))
	kill_feed_box.add_child(row)
	while kill_feed_box.get_child_count() > 5:
		var oldest := kill_feed_box.get_child(0)
		kill_feed_box.remove_child(oldest)
		oldest.queue_free()
	var tween := row.create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(row, "modulate:a", 0.0, 0.6)
	tween.tween_callback(row.queue_free)


func _team_icon_control(team: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = _team_icon(team)
	icon.custom_minimum_size = Vector2(17, 17)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _team_icon(team: int) -> Texture2D:
	var key := "light" if team == 0 else "dark"
	if team_icons.has(key):
		return team_icons[key] as Texture2D
	if team == 1:
		# Proper faction icon for the Dark side instead of the placeholder cross.
		var dark_path := "res://assets/ui/teams/dark_team.png"
		if ResourceLoader.exists(dark_path):
			var dark_texture := load(dark_path) as Texture2D
			if dark_texture != null:
				team_icons[key] = dark_texture
				return dark_texture
	var fill := Color(0.97, 0.91, 0.69) if team == 0 else Color(0.08, 0.085, 0.12)
	var outline := Color(0.04, 0.04, 0.06) if team == 0 else Color(0.95, 0.95, 0.97)
	var texture := _build_cross_texture(fill, outline)
	team_icons[key] = texture
	return texture


func _build_cross_texture(fill: Color, outline: Color) -> ImageTexture:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var scale := float(size) / 24.0
	var border := 1.8
	for y in range(size):
		for x in range(size):
			var px := (float(x) + 0.5) / scale
			var py := (float(y) + 0.5) / scale
			if _cross_hit(px, py, 0.0):
				image.set_pixel(x, y, fill)
			elif _cross_hit(px, py, border):
				image.set_pixel(x, y, outline)
	return ImageTexture.create_from_image(image)


func _cross_hit(px: float, py: float, grow: float) -> bool:
	var vertical := px >= 9.0 - grow and px <= 15.0 + grow and py >= 2.0 - grow and py <= 22.0 + grow
	var horizontal := px >= 2.0 - grow and px <= 22.0 + grow and py >= 9.0 - grow and py <= 15.0 + grow
	return vertical or horizontal


func _make_feed_name(text: String, team: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", _fs(15))
	var color := Color(0.82, 0.74, 0.6)
	if team == 0:
		color = Color(1.0, 0.9, 0.7)
	elif team == 1:
		color = Color(0.8, 0.85, 0.97)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _build_top(root: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "MatchInfo"
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -380.0 if _mobile_ui() else -360.0
	box.offset_top = 20.0
	box.offset_right = -74.0 if _mobile_ui() else -20.0
	box.offset_bottom = 142.0
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	match_info_box = box

	score_label = _make_label("Свет — 0:0 — Тьма", 24, Color.WHITE)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(score_label)

	gold_label = _make_label("Золото: 0", 18, GOLD)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# The tutorial has no gold counter: it sat right under the skip button and
	# made the escape hatch harder to hit.
	gold_label.visible = game == null or not bool(game.get("tutorial_mode"))
	box.add_child(gold_label)

	timer_label = _make_label("10:00", 20, Color.WHITE)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(timer_label)

	shell_timer_label = _make_label("Оболочка: 02:00", 16, Color(0.66, 0.68, 0.72))
	shell_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(shell_timer_label)
	shell_timer_label.visible = false

	_build_player_panel(root)
	_build_scoreboard_button(root)


func _build_focus_panel(root: Control) -> void:
	focus_panel = Panel.new()
	focus_panel.name = "TutorialFocus"
	focus_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_panel.z_index = 60
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.9, 0.4, 0.06)
	style.border_color = Color(1.0, 0.9, 0.4, 0.95)
	style.set_border_width_all(3)
	style.set_corner_radius_all(9)
	focus_panel.add_theme_stylebox_override("panel", style)
	focus_panel.visible = false
	root.add_child(focus_panel)


func set_focus_target(target: Control) -> void:
	focus_target = target
	focus_use_manual = false
	if focus_panel == null:
		return
	if target == null or not is_instance_valid(target):
		focus_panel.visible = false


func show_ui_highlight(kind: String, text: String) -> void:
	focus_use_manual = false
	var target: Control = null
	match kind:
		"minimap":
			target = minimap_control
		"skills":
			# The mobile ability row is a full-screen layout helper; highlight
			# the actual buttons instead of the whole screen.
			if not ability_slots.is_empty():
				var union := ability_slots[0].get_global_rect()
				for slot in ability_slots:
					if slot != null and is_instance_valid(slot):
						union = union.merge(slot.get_global_rect())
				focus_manual_rect = union
				focus_use_manual = true
			else:
				target = ability_row
		"avatar":
			target = player_panel
	if focus_use_manual:
		focus_target = null
		if focus_panel != null:
			focus_panel.visible = true
	else:
		set_focus_target(target)
	show_tutorial_hint(text)


func hide_ui_highlight() -> void:
	focus_use_manual = false
	set_focus_target(null)
	if focus_panel != null:
		focus_panel.visible = false


func set_tutorial_shop_item(item_id: String) -> void:
	tutorial_shop_item = item_id
	if item_id.is_empty():
		focus_use_manual = false
		set_focus_target(null)
		return
	var button := shop_buttons.get(item_id) as Control
	if button != null and shop_scroll != null:
		shop_scroll.call_deferred("ensure_control_visible", button)


func _update_focus_panel() -> void:
	if focus_panel == null:
		return
	if tutorial_shop_item != "" and shop_panel != null and shop_panel.visible:
		var button := shop_buttons.get(tutorial_shop_item) as Control
		if button != null and is_instance_valid(button):
			focus_target = button
	if focus_target == null or not is_instance_valid(focus_target) or not focus_target.is_visible_in_tree():
		if not focus_use_manual:
			focus_panel.visible = false
			return
	var rect: Rect2
	if focus_use_manual:
		rect = focus_manual_rect
	else:
		rect = focus_target.get_global_rect()
	var hud_root := get_child(0) as Control if get_child_count() > 0 else null
	var origin := hud_root.global_position if hud_root != null else Vector2.ZERO
	focus_panel.position = rect.position - origin + Vector2(-5.0, -5.0)
	focus_panel.size = rect.size + Vector2(10.0, 10.0)
	focus_panel.visible = true
	focus_panel.modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006))


func _score_button_style(border: Color, fill: Color, glow: Color, glow_size: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	# A soft outer glow instead of a flat plate: gold at rest, brighter on
	# hover/press, drawn outside the 64x64 rect without moving it.
	style.shadow_color = glow
	style.shadow_size = glow_size
	style.shadow_offset = Vector2(0.0, 2.0)
	style.content_margin_left = 2.0
	style.content_margin_right = 2.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style


func _build_scoreboard_button(root: Control) -> void:
	scoreboard_button = Button.new()
	scoreboard_button.name = "ScoreboardButton"
	# The visible caption is a child Label so the table glyph can sit above
	# it; the Button itself stays a plain click target in the same spot.
	scoreboard_button.text = ""
	scoreboard_button.tooltip_text = "Счёт и игроки"
	scoreboard_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# Above the tutorial cards (100) but below the skip button (110), so the
	# table never steals the tutorial's escape hatch.
	scoreboard_button.z_index = 105
	scoreboard_button.visible = false
	scoreboard_button.focus_mode = Control.FOCUS_NONE
	scoreboard_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	scoreboard_button.add_theme_stylebox_override(
		"normal",
		_score_button_style(
			Color(0.80, 0.64, 0.33, 0.92),
			Color(0.045, 0.065, 0.105, 0.96),
			Color(0.86, 0.68, 0.29, 0.26),
			5
		)
	)
	scoreboard_button.add_theme_stylebox_override(
		"hover",
		_score_button_style(
			Color(1.0, 0.86, 0.52, 1.0),
			Color(0.075, 0.105, 0.165, 0.98),
			Color(0.98, 0.80, 0.40, 0.48),
			7
		)
	)
	scoreboard_button.add_theme_stylebox_override(
		"pressed",
		_score_button_style(
			Color(1.0, 0.90, 0.62, 1.0),
			Color(0.19, 0.145, 0.065, 0.98),
			Color(1.0, 0.82, 0.42, 0.40),
			4
		)
	)
	scoreboard_button.pressed.connect(_toggle_scoreboard)
	root.add_child(scoreboard_button)

	var content := VBoxContainer.new()
	content.name = "ScoreboardButtonContent"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", -1)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard_button.add_child(content)

	var glyph := ScoreboardGlyph.new()
	glyph.name = "ScoreboardGlyph"
	content.add_child(glyph)

	scoreboard_button_label = _make_label("СЧЁТ", 16, GOLD)
	scoreboard_button_label.name = "ScoreboardButtonLabel"
	scoreboard_button_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_button_label.add_theme_font_size_override("font_size", _fs(16))
	scoreboard_button_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(scoreboard_button_label)


## The in-battle table mirrors the results screen, but stays a compact card
## under the player card so the fight remains visible behind it.
func _build_scoreboard(root: Control) -> void:
	scoreboard_panel = PanelContainer.new()
	scoreboard_panel.name = "BattleScoreboard"
	# Below the tutorial cards (100): a stage card must stay readable and
	# clickable while the table is open. Above the regular HUD.
	scoreboard_panel.z_index = 99
	scoreboard_panel.visible = false
	scoreboard_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	scoreboard_panel.add_theme_stylebox_override("panel", _panel_style(GOLD, Color(0.02, 0.03, 0.05, 0.97)))
	root.add_child(scoreboard_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	scoreboard_panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	layout.add_child(header)
	var title := _make_label("СПИСОК ИГРОКОВ", 17, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	scoreboard_score_label = _make_label("Свет 0 : 0 Тьма", 14, PALE)
	scoreboard_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scoreboard_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(scoreboard_score_label)
	var close_button := _pause_action_button("×", false)
	close_button.name = "ScoreboardClose"
	close_button.custom_minimum_size = Vector2(42, 34)
	close_button.add_theme_font_size_override("font_size", _fs(20))
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.pressed.connect(_close_scoreboard)
	header.add_child(close_button)

	var divider := ColorRect.new()
	divider.color = Color(0.78, 0.65, 0.4, 0.35)
	divider.custom_minimum_size = Vector2(0, 1)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(divider)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 4)
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(columns)
	columns.add_child(_make_scoreboard_cell("ИГРОК", 12, Color(0.55, 0.58, 0.66), 0.0, HORIZONTAL_ALIGNMENT_LEFT, true))
	columns.add_child(_make_scoreboard_cell("", 12, Color(0.55, 0.58, 0.66), 34.0, HORIZONTAL_ALIGNMENT_CENTER))
	columns.add_child(_make_scoreboard_cell("У/С", 12, Color(0.55, 0.58, 0.66), 58.0, HORIZONTAL_ALIGNMENT_CENTER))
	columns.add_child(_make_scoreboard_cell("ОСК.", 12, Color(0.55, 0.58, 0.66), 48.0, HORIZONTAL_ALIGNMENT_RIGHT))
	columns.add_child(_make_scoreboard_cell("СЧЁТ", 12, Color(0.55, 0.58, 0.66), 54.0, HORIZONTAL_ALIGNMENT_RIGHT))

	scoreboard_scroll = ScrollContainer.new()
	scoreboard_scroll.name = "ScoreboardScroll"
	scoreboard_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scoreboard_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scoreboard_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	layout.add_child(scoreboard_scroll)

	scoreboard_rows = VBoxContainer.new()
	scoreboard_rows.name = "ScoreboardRows"
	scoreboard_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scoreboard_rows.add_theme_constant_override("separation", 2)
	scoreboard_scroll.add_child(scoreboard_rows)

	scoreboard_hint_label = _make_label("", 12, Color(0.56, 0.62, 0.74))
	scoreboard_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	layout.add_child(scoreboard_hint_label)

	_build_scoreboard_report(root)


func _build_scoreboard_report(root: Control) -> void:
	scoreboard_report_overlay = ColorRect.new()
	scoreboard_report_overlay.name = "ScoreboardReportOverlay"
	scoreboard_report_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scoreboard_report_overlay.color = Color(0.005, 0.008, 0.018, 0.82)
	scoreboard_report_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	scoreboard_report_overlay.visible = false
	scoreboard_report_overlay.z_index = 180
	root.add_child(scoreboard_report_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard_report_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "ScoreboardReportPanel"
	panel.custom_minimum_size = Vector2(340 if _mobile_ui() else 430, 0)
	panel.add_theme_stylebox_override("panel", _panel_style(GOLD, Color(0.035, 0.045, 0.07, 0.99)))
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	var title := _make_label("ПОЖАЛОВАТЬСЯ", 20, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	content.add_child(title)
	scoreboard_report_target_label = _make_label("", 15, PALE)
	scoreboard_report_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	content.add_child(scoreboard_report_target_label)
	scoreboard_report_reason = OptionButton.new()
	scoreboard_report_reason.name = "ScoreboardReportReason"
	scoreboard_report_reason.custom_minimum_size = Vector2(0, 42)
	scoreboard_report_reason.add_theme_font_override("font", font)
	scoreboard_report_reason.add_theme_font_size_override("font_size", _fs(15))
	scoreboard_report_reason.add_item("Оскорбительный ник")
	scoreboard_report_reason.add_item("Читы / нечестная игра")
	scoreboard_report_reason.add_item("Другое")
	content.add_child(scoreboard_report_reason)
	scoreboard_report_status = _make_label("", 13, PALE)
	scoreboard_report_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	scoreboard_report_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scoreboard_report_status.custom_minimum_size = Vector2(300 if _mobile_ui() else 390, 0)
	content.add_child(scoreboard_report_status)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(buttons)
	scoreboard_report_submit = _pause_action_button("Отправить", true)
	scoreboard_report_submit.name = "ScoreboardReportSubmit"
	scoreboard_report_submit.custom_minimum_size = Vector2(170, 44)
	scoreboard_report_submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scoreboard_report_submit.pressed.connect(_submit_scoreboard_report)
	buttons.add_child(scoreboard_report_submit)
	var cancel := _pause_action_button("Отмена", false)
	cancel.custom_minimum_size = Vector2(150, 44)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_close_scoreboard_report)
	buttons.add_child(cancel)


func _toggle_scoreboard() -> void:
	if scoreboard_panel == null or game == null or game.state != "live":
		return
	# The tutorial has no table: the top strip already names the training
	# bots, and the panel covered the hint the stage needed.
	if bool(game.get("tutorial_mode")):
		return
	if scoreboard_panel.visible:
		_close_scoreboard()
	else:
		_open_scoreboard()


func _open_scoreboard() -> void:
	if scoreboard_panel == null or game == null or game.state != "live":
		return
	if bool(game.get("tutorial_mode")):
		return
	scoreboard_refresh_tick = 0.0
	scoreboard_panel.visible = true
	scoreboard_hint_label.text = "Нажмите «СЧЁТ» ещё раз" if _mobile_ui() else "Tab — закрыть"
	_update_scoreboard_layout()
	_refresh_scoreboard()


func _close_scoreboard() -> void:
	if scoreboard_panel != null:
		scoreboard_panel.visible = false
	_close_scoreboard_report()


func _update_scoreboard_layout() -> void:
	if scoreboard_panel == null or player_panel == null:
		return
	var viewport_size := _hud_viewport_size()
	var width := minf(620.0, maxf(340.0, viewport_size.x - player_panel.position.x - 20.0))
	scoreboard_panel.custom_minimum_size.x = width
	scoreboard_panel.position = Vector2(
		player_panel.position.x,
		player_panel.position.y + player_panel.size.y + 8.0
	)
	if scoreboard_scroll != null and scoreboard_rows != null:
		# On a phone six rows do not fit under the card: the rows scroll and
		# the panel stays above the ability bar instead of running off screen.
		var content_height := scoreboard_rows.get_combined_minimum_size().y
		var max_height := maxf(96.0, viewport_size.y - scoreboard_panel.position.y - 150.0)
		scoreboard_scroll.custom_minimum_size.y = minf(content_height, max_height)
	scoreboard_panel.reset_size()
	if scoreboard_button != null and is_instance_valid(scoreboard_button):
		# The touch table button lives in the slot right after the player card:
		# x follows the card so it survives the baked phone layout and any
		# viewport change, y matches the card top. The 64px tile only slides in
		# when the screen is too narrow to keep it on screen.
		var gap := 8.0
		var button_x := player_panel.position.x + player_panel.size.x + gap
		button_x = minf(button_x, maxf(0.0, viewport_size.x - 64.0 - 6.0))
		scoreboard_button.position = Vector2(button_x, player_panel.position.y)
		scoreboard_button.size = Vector2(64.0, 64.0)
		if _mobile_ui() and announce_label != null and is_instance_valid(announce_label):
			# Keep every combat announcement clear of the card/button band even
			# when the baked layout moves the card down the screen. The 96px
			# floor preserves the approved top-centre position on 844x390.
			var announce_top := maxf(
				96.0,
				scoreboard_button.position.y + scoreboard_button.size.y + 12.0
			)
			if not is_equal_approx(announce_label.offset_top, announce_top):
				announce_label.offset_top = announce_top
				announce_label.offset_bottom = announce_top + 60.0


func _refresh_scoreboard() -> void:
	if scoreboard_panel == null or scoreboard_rows == null or game == null:
		return
	var keep_scroll := 0
	if scoreboard_scroll != null:
		keep_scroll = scoreboard_scroll.scroll_vertical
	for child in scoreboard_rows.get_children():
		scoreboard_rows.remove_child(child)
		child.queue_free()
	if scoreboard_score_label != null:
		scoreboard_score_label.text = "Свет %d : %d Тьма" % [int(game.score[0]), int(game.score[1])]
	var entries := _scoreboard_entries()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("team", 0)) != int(b.get("team", 0)):
			return int(a.get("team", 0)) < int(b.get("team", 0))
		return int(a.get("score", 0)) > int(b.get("score", 0))
	)
	var current_team := -1
	for entry in entries:
		var team := int(entry.get("team", 0))
		if team != current_team:
			current_team = team
			var team_label := _make_label("СВЕТ" if team == 0 else "ТЬМА", 12, Color(0.55, 0.85, 1.0) if team == 0 else Color(0.8, 0.58, 0.96))
			team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			scoreboard_rows.add_child(team_label)
		scoreboard_rows.add_child(_make_scoreboard_row(entry))
	scoreboard_panel.reset_size()
	_update_scoreboard_layout()
	if scoreboard_scroll != null:
		scoreboard_scroll.set_deferred("scroll_vertical", keep_scroll)


func _scoreboard_entries() -> Array:
	var entries: Array = []
	var heroes: Array = game.get("heroes") if game.get("heroes") is Array else []
	for hero in heroes:
		if hero == null or not is_instance_valid(hero):
			continue
		var is_self := bool(hero.is_player)
		var hero_name := String(hero.display_name).strip_edges()
		if hero_name.is_empty():
			hero_name = "Игрок"
		entries.append({
			"name": hero_name,
			"team": int(hero.team),
			"kills": int(hero.match_kills),
			"deaths": int(hero.match_deaths),
			"damage": int(hero.match_damage_dealt),
			"crystals": int(hero.match_crystals),
			"shells": int(hero.match_shells),
			"coins": int(hero.match_coins_collected),
			"gold": int(hero.match_gold_spent),
			"score": _scoreboard_points(
				int(hero.match_kills), float(hero.match_damage_dealt), int(hero.match_shells),
				int(hero.match_crystals), int(hero.match_coins_collected), int(hero.match_gold_spent)
			),
			"is_self": is_self,
			"is_bot": not is_self,
			"reportable": false,
		})
	var remotes: Dictionary = game.get("remote_players") if game.get("remote_players") is Dictionary else {}
	for remote in remotes.values():
		if remote == null or not is_instance_valid(remote):
			continue
		var remote_name := String(remote.display_name).strip_edges()
		if remote_name.is_empty():
			remote_name = "Игрок"
		var remote_bot := bool(remote.is_bot)
		entries.append({
			"name": remote_name,
			"team": int(remote.team),
			"kills": int(remote.match_kills),
			"deaths": int(remote.match_deaths),
			"damage": int(remote.match_damage_dealt),
			"crystals": int(remote.match_crystals),
			"shells": int(remote.match_shells),
			"coins": 0,
			"gold": 0,
			"score": _scoreboard_points(
				int(remote.match_kills), float(remote.match_damage_dealt), int(remote.match_shells),
				int(remote.match_crystals), 0, 0
			),
			"is_self": false,
			"is_bot": remote_bot,
			"reportable": not remote_bot and _scoreboard_name_reportable(remote_name),
		})
	return entries


func _scoreboard_points(kills: int, damage: float, shells: int, crystals: int, coins: int, gold: int) -> int:
	var points := float(kills) * 3.0 + damage / 100.0 + float(shells) * 2.0
	points += float(crystals) * 3.0 + float(coins) * 0.1 + float(gold) * 0.02
	return int(round(points))


func _scoreboard_name_reportable(nickname: String) -> bool:
	var clean := nickname.strip_edges()
	if clean.length() < 3 or clean.length() > 12:
		return false
	if clean == "Игрок":
		return false
	return clean != String(MetaProgression.player_nickname).strip_edges()


func _make_scoreboard_cell(text: String, font_size: int, color: Color, width: float, align: int, expand := false) -> Label:
	var label := _make_label(text, font_size, color)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	else:
		label.custom_minimum_size = Vector2(width, 0)
	return label


func _make_scoreboard_row(entry: Dictionary) -> Control:
	var is_self := bool(entry.get("is_self", false))
	var row_panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.94, 0.78, 0.43, 0.14) if is_self else Color(0.0, 0.0, 0.0, 0.0)
	style.set_corner_radius_all(5)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	row_panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row_panel.add_child(row)

	var name_text := String(entry.get("name", "Игрок"))
	if bool(entry.get("is_bot", false)):
		name_text = "БОТ · " + name_text
	if is_self:
		name_text = "* " + name_text
	row.add_child(_make_scoreboard_cell(name_text, 13, GOLD if is_self else PALE, 0.0, HORIZONTAL_ALIGNMENT_LEFT, true))

	if bool(entry.get("reportable", false)):
		var report_button := Button.new()
		report_button.name = "Report"
		report_button.text = "!"
		report_button.tooltip_text = "Пожаловаться на " + String(entry.get("name", ""))
		report_button.custom_minimum_size = Vector2(34, 26)
		report_button.focus_mode = Control.FOCUS_NONE
		report_button.add_theme_font_override("font", font)
		report_button.add_theme_font_size_override("font_size", _fs(14))
		report_button.add_theme_color_override("font_color", Color(1.0, 0.72, 0.55))
		report_button.add_theme_stylebox_override("normal", _panel_style(Color(0.62, 0.3, 0.24, 0.55), Color(0.12, 0.05, 0.05, 0.75)))
		report_button.add_theme_stylebox_override("hover", _panel_style(Color(1.0, 0.55, 0.4), Color(0.22, 0.08, 0.06, 0.95)))
		report_button.add_theme_stylebox_override("pressed", _panel_style(Color(1.0, 0.7, 0.5), Color(0.28, 0.1, 0.07, 1.0)))
		report_button.pressed.connect(_open_scoreboard_report.bind(String(entry.get("name", ""))))
		row.add_child(report_button)
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(34, 26)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(spacer)

	row.add_child(_make_scoreboard_cell("%d/%d" % [int(entry.get("kills", 0)), int(entry.get("deaths", 0))], 13, Color(0.8, 0.85, 0.95), 58.0, HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(_make_scoreboard_cell(str(int(entry.get("crystals", 0))), 13, Color(0.43, 0.84, 1.0), 48.0, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_make_scoreboard_cell(str(int(entry.get("score", 0))), 13, Color(1.0, 0.82, 0.5), 54.0, HORIZONTAL_ALIGNMENT_RIGHT))
	return row_panel


func _open_scoreboard_report(nickname: String) -> void:
	if scoreboard_report_overlay == null or not _scoreboard_name_reportable(nickname):
		return
	scoreboard_report_target = nickname.strip_edges()
	scoreboard_report_target_label.text = "Игрок: " + scoreboard_report_target
	scoreboard_report_status.text = ""
	scoreboard_report_status.add_theme_color_override("font_color", PALE)
	scoreboard_report_submit.disabled = false
	scoreboard_report_reason.select(0)
	scoreboard_report_overlay.visible = true


func _close_scoreboard_report() -> void:
	if scoreboard_report_overlay != null:
		scoreboard_report_overlay.visible = false
	scoreboard_report_target = ""


func _submit_scoreboard_report() -> void:
	if scoreboard_report_target.is_empty() or scoreboard_report_submit == null:
		return
	if MetaProgression.player_id <= 0:
		scoreboard_report_status.text = "Нужен вход в аккаунт."
		scoreboard_report_status.add_theme_color_override("font_color", Color(1.0, 0.48, 0.42))
		return
	var reason := scoreboard_report_reason.get_item_text(scoreboard_report_reason.selected)
	scoreboard_report_submit.disabled = true
	scoreboard_report_status.text = "Отправляем жалобу..."
	scoreboard_report_status.add_theme_color_override("font_color", Color(0.76, 0.8, 0.89))
	NetworkClient.report_player(MetaProgression.player_id, scoreboard_report_target, reason)


func _on_scoreboard_report_completed(success: bool, error: String) -> void:
	if scoreboard_report_submit != null:
		scoreboard_report_submit.disabled = false
	if scoreboard_report_status == null:
		return
	if success:
		scoreboard_report_status.text = "Жалоба отправлена. Спасибо!"
		scoreboard_report_status.add_theme_color_override("font_color", Color(0.58, 0.9, 0.64))
	else:
		scoreboard_report_status.text = "Не удалось: %s" % _localize_scoreboard_report_error(error)
		scoreboard_report_status.add_theme_color_override("font_color", Color(1.0, 0.48, 0.42))


func _localize_scoreboard_report_error(error: String) -> String:
	match error:
		"Too many reports":
			return "слишком много жалоб, попробуй позже."
		"Player not found":
			return "профиль не найден."
		"Нет связи с сервером":
			return "сервер недоступен, попробуй позже."
		_:
			return error


func _build_pause_menu(root: Control) -> void:
	pause_overlay = Control.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	# Above the tutorial cards (100) and the skip button (110): the pause menu
	# must stay reachable while a stage card is on screen.
	pause_overlay.z_index = 150
	pause_overlay.visible = false
	pause_overlay.gui_input.connect(_on_pause_overlay_input)
	root.add_child(pause_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.005, 0.008, 0.018, 0.78)
	# The overlay itself blocks the field; the dim only has to dim.
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "PauseMenuPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -210.0
	panel.offset_top = -180.0
	panel.offset_right = 210.0
	panel.offset_bottom = 180.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.78, 0.62, 0.32), Color(0.035, 0.045, 0.07, 0.99)))
	pause_overlay.add_child(panel)
	pause_menu_panel = panel

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	panel.add_child(layout)
	var title := _make_label("ПАУЗА", 34, GOLD)
	pause_title_label = title
	layout.add_child(title)
	var resume_button := _pause_action_button("Продолжить", true)
	pause_resume_button = resume_button
	resume_button.pressed.connect(_resume_game)
	layout.add_child(resume_button)
	var rules_button := _pause_action_button("Правила", false)
	rules_button.pressed.connect(_open_pause_rules)
	layout.add_child(rules_button)
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

	pause_rules_panel = RULES_PANEL_SCRIPT.new() as Control
	pause_rules_panel.name = "PauseRulesPanel"
	pause_rules_panel.visible = false
	pause_rules_panel.z_index = 11
	pause_rules_panel.connect("back_requested", _on_pause_rules_back)
	pause_overlay.add_child(pause_rules_panel)


func _pause_action_button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(300.0, 50.0)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", _fs(20))
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


func _on_avatar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_toggle_pause_menu()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_toggle_pause_menu()


func _on_pause_overlay_input(event: InputEvent) -> void:
	# The player card is one big toggle: tapping it while the menu is open
	# closes the menu again. The overlay covers the card, so the tap lands here.
	if pause_menu_panel == null or not pause_menu_panel.visible:
		return
	if player_panel == null or not is_instance_valid(player_panel) or not player_panel.visible:
		return
	var local := Vector2.INF
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		local = mouse.position
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not touch.pressed:
			return
		local = touch.position
	else:
		return
	if player_panel.get_global_rect().has_point(local + pause_overlay.global_position):
		_resume_game()


func _open_pause_menu() -> void:
	_close_scoreboard()
	if game == null or game.state != "live":
		return
	var online := bool(game.get("network_play"))
	pause_overlay.visible = true
	pause_menu_panel.visible = true
	pause_settings_panel.visible = false
	if pause_rules_panel != null:
		pause_rules_panel.visible = false
	if pause_title_label != null:
		pause_title_label.text = "МЕНЮ" if online else "ПАУЗА"
	if pause_resume_button != null:
		pause_resume_button.text = "Закрыть" if online else "Продолжить"
	# In online matches the server keeps running; pausing would freeze this
	# client only and desync it. The avatar menu is an overlay, not a pause.
	get_tree().paused = not online
	Haptics.vibrate(35)


func _resume_game() -> void:
	pause_overlay.visible = false
	pause_settings_panel.visible = false
	if pause_rules_panel != null:
		pause_rules_panel.visible = false
	get_tree().paused = false


func _open_pause_settings() -> void:
	pause_menu_panel.visible = false
	pause_settings_panel.visible = true
	if pause_rules_panel != null:
		pause_rules_panel.visible = false


func _on_pause_settings_back() -> void:
	pause_settings_panel.visible = false
	pause_menu_panel.visible = true


func _open_pause_rules() -> void:
	pause_menu_panel.visible = false
	pause_settings_panel.visible = false
	pause_rules_panel.visible = true


func _on_pause_rules_back() -> void:
	pause_rules_panel.visible = false
	pause_menu_panel.visible = true


func _exit_game() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_TAB and key_event.physical_keycode != KEY_TAB:
		return
	# Tab closes the report dialog first: it sits on top of the table.
	if scoreboard_report_overlay != null and scoreboard_report_overlay.visible:
		_close_scoreboard_report()
		get_viewport().set_input_as_handled()
		return
	if game == null or game.state != "live":
		return
	# No player table in the tutorial: Tab must not cover the stage hint.
	if bool(game.get("tutorial_mode")):
		get_viewport().set_input_as_handled()
		return
	if pause_overlay != null and pause_overlay.visible:
		return
	_toggle_scoreboard()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or (key_event.keycode != KEY_ESCAPE and key_event.physical_keycode != KEY_ESCAPE):
		return
	if pause_rules_panel != null and pause_rules_panel.visible:
		_on_pause_rules_back()
	elif pause_settings_panel != null and pause_settings_panel.visible:
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
	player_panel.offset_right = 390.0
	player_panel.offset_bottom = 94.0
	# Owner: the whole player card opens the pause menu.
	player_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	player_panel.gui_input.connect(_on_avatar_input)
	player_panel.add_theme_stylebox_override("panel", _player_card_style())
	root.add_child(player_panel)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_panel.add_child(content)

	# Compact 2D portrait on the left: the lobby avatar image (hero face or
	# the equipped skin) instead of the old 3D viewport, so every phone shows
	# the same picture without a second render target.
	var portrait_frame := PanelContainer.new()
	portrait_frame.name = "PlayerAvatarFrame"
	portrait_frame.custom_minimum_size = Vector2(52.0, 52.0)
	portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	portrait_frame.clip_contents = true
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = Color(0.02, 0.025, 0.04, 0.95)
	portrait_style.set_border_width_all(0)
	portrait_style.set_corner_radius_all(6)
	portrait_frame.add_theme_stylebox_override("panel", portrait_style)
	portrait_frame.gui_input.connect(_on_avatar_input)
	content.add_child(portrait_frame)

	player_avatar = TextureRect.new()
	player_avatar.name = "PlayerAvatar"
	player_avatar.custom_minimum_size = Vector2(52.0, 52.0)
	player_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Cover, never stretch: a wide key-art card is cropped to the square
	# instead of squashing the face.
	player_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	player_avatar.clip_contents = true
	player_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_child(player_avatar)

	# The card carries the nickname, the side (icon + word) and HP.
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	details.add_theme_constant_override("separation", 2)
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(details)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(name_row)
	player_name_label = _make_label("Игрок", 15, Color(0.97, 0.91, 0.79))
	player_name_label.clip_text = true
	player_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	player_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	player_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(player_name_label)
	player_team_icon = TextureRect.new()
	player_team_icon.custom_minimum_size = Vector2(18, 18)
	player_team_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	player_team_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	player_team_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(player_team_icon)
	player_team_label = _make_label("Свет", 13, Color(0.55, 0.85, 1.0))
	player_team_label.custom_minimum_size = Vector2(40, 0)
	player_team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	player_team_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(player_team_label)

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
	var is_mobile := _mobile_ui()
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
		var slot: Control
		if is_mobile:
			# A plain Control gives the editor full freedom to move and
			# resize each skill; the button fills it edge to edge.
			slot = Control.new()
			slot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			slot.offset_left = slot_offsets[i].x
			slot.offset_top = slot_offsets[i].y
			slot.offset_right = slot_offsets[i].x + 88.0
			slot.offset_bottom = slot_offsets[i].y + 88.0
			slot.custom_minimum_size = Vector2(88.0, 88.0)
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			slot = VBoxContainer.new()
			slot.custom_minimum_size = Vector2(84.0, 106.0)
			slot.add_theme_constant_override("separation", 2)
			slot.alignment = BoxContainer.ALIGNMENT_CENTER
		var button := Button.new()
		button.text = ""
		if is_mobile:
			button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			button.custom_minimum_size = Vector2.ZERO
		else:
			button.custom_minimum_size = Vector2(84.0, 84.0)
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
		if not is_mobile:
			slot.add_child(name_label)
		row.add_child(slot)
		ability_slots.append(slot)
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
	style.set_corner_radius_all(14 if _mobile_ui() else 12)
	style.content_margin_left = 2.0
	style.content_margin_right = 2.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style


func _set_ability_ready(index: int, is_ready: bool) -> void:
	if ability_ready[index] == is_ready:
		return
	ability_ready[index] = is_ready
	_refresh_ability_button_style(index)


func _refresh_ability_icons(cls: int) -> void:
	if cls < 0 or cls >= ABILITY_ICONS.size():
		return
	ability_wipe_progress = [-1.0, -1.0, -1.0]
	for index in ability_buttons.size():
		var icon_rect := ability_buttons[index].get_node_or_null("AbilityIcon") as TextureRect
		if icon_rect != null:
			icon_rect.texture = ABILITY_ICONS[cls][index]
		if index < ability_name_labels.size():
			ability_name_labels[index].text = str(ABILITY_SHORT_LABELS[cls][index])
		if index < ability_key_labels.size() and _mobile_ui():
			ability_key_labels[index].text = str(index + 1)


func _refresh_ability_button_style(index: int) -> void:
	if index < 0 or index >= ability_buttons.size():
		return
	for style_name in ["normal", "hover", "pressed"]:
		var style := _ability_style(ability_ready[index], style_name != "normal")
		if index == tutorial_ability_index:
			style.border_color = Color(1.0, 0.9, 0.48, 0.35 + 0.65 * tutorial_pulse)
			style.set_border_width_all(5)
		ability_buttons[index].add_theme_stylebox_override(style_name, style)
	var icon := ability_buttons[index].get_node_or_null("AbilityIcon") as TextureRect
	if icon != null:
		# Gray while the skill is on cooldown, full color when ready.
		icon.modulate = Color(1.0, 1.0, 1.0, 1.0) if ability_ready[index] else Color(0.35, 0.36, 0.4, 1.0)


func set_tutorial_ability(index: int) -> void:
	if tutorial_ability_index == index:
		return
	tutorial_style_pulse = -1.0
	var previous := tutorial_ability_index
	tutorial_ability_index = index
	_refresh_ability_button_style(previous)
	_refresh_ability_button_style(tutorial_ability_index)
	show_tutorial_press_hint(index)


func show_tutorial_press_hint(index: int) -> void:
	if tutorial_press_label == null:
		return
	if index < 0 or index >= ability_buttons.size():
		tutorial_press_label.visible = false
		return
	# The highlighted skill shows its own number on both layouts, so the plate
	# names the same key; "Num 3" made the text too wide and was cut at the edge.
	tutorial_press_label.text = "НАЖМИ %d" % [index + 1]
	tutorial_press_label.visible = true


func _update_tutorial_press_hint() -> void:
	if tutorial_press_label == null:
		return
	var index := tutorial_ability_index
	if index < 0 or index >= ability_buttons.size() or not tutorial_press_label.visible:
		tutorial_press_label.visible = false
		return
	var button := ability_buttons[index]
	if not button.is_visible_in_tree():
		tutorial_press_label.visible = false
		return
	tutorial_pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	if absf(tutorial_pulse - tutorial_style_pulse) >= 0.08:
		tutorial_style_pulse = tutorial_pulse
		# Rebuilding three StyleBoxFlat every frame is heavy; step the border
		# pulse instead.
		_refresh_ability_button_style(index)
	tutorial_press_label.modulate.a = 0.55 + 0.45 * tutorial_pulse
	var width := maxf(150.0, button.size.x + 40.0)
	tutorial_press_label.size = Vector2(width, 30.0)
	var hint_x := button.global_position.x + (button.size.x - width) * 0.5
	var screen_width := get_viewport().get_visible_rect().size.x
	# Keep the plate inside the screen when the highlighted skill sits on the
	# right edge of the ability bar.
	hint_x = clampf(hint_x, 8.0, maxf(8.0, screen_width - width - 8.0))
	tutorial_press_label.global_position = Vector2(hint_x, button.global_position.y - 38.0)


func _build_announcement(root: Control) -> void:
	announce_label = _make_label("", 18, GOLD)
	# Combat messages sit at the very top centre, between the player card and
	# the match info; the old full-width strip at y=100 covered the fight.
	announce_label.anchor_left = 0.34
	announce_label.anchor_right = 0.66
	announce_label.anchor_top = 0.0
	announce_label.anchor_bottom = 0.0
	announce_label.offset_left = 0.0
	announce_label.offset_right = 0.0
	announce_label.offset_top = 4.0
	announce_label.offset_bottom = 64.0
	if _mobile_ui():
		# The touch "СЧЁТ" button sits right after the player card, so combat
		# announcements start below the card/button band. The slow tick
		# re-anchors this offset when the card moves.
		announce_label.offset_top = 96.0
		announce_label.offset_bottom = 156.0
	announce_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	announce_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	announce_label.modulate.a = 0.0
	announce_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(announce_label)


func _build_respawn_label(root: Control) -> void:
	center_respawn_label = _make_label("Возрождение", 34, Color(1.0, 0.86, 0.55))
	center_respawn_label.anchor_left = 0.5
	center_respawn_label.anchor_top = 0.5
	center_respawn_label.anchor_right = 0.5
	center_respawn_label.anchor_bottom = 0.5
	center_respawn_label.offset_left = -260.0
	center_respawn_label.offset_top = -44.0
	center_respawn_label.offset_right = 260.0
	center_respawn_label.offset_bottom = 44.0
	center_respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_respawn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_respawn_label.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.02, 0.95))
	center_respawn_label.add_theme_constant_override("outline_size", 8)
	center_respawn_label.modulate.a = 0.0
	center_respawn_label.visible = false
	center_respawn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center_respawn_label)


func _build_select(root: Control) -> void:
	select_panel = Control.new()
	select_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	select_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The lobby already chose a class; the old in-battle selection screen is
	# gone. Direct Main.tscn runs without that meta keep the fallback panel.
	select_panel.visible = not get_tree().has_meta("selected_class")
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

	var title := _make_label("НЕБЕСНЫЕ ОСКОЛКИ", 56, GOLD)
	box.add_child(title)
	var subtitle := _make_label("Выбери героя света", 22, Color(0.85, 0.9, 1.0))
	box.add_child(subtitle)

	var classes := ["Воин — врывается и оглушает", "Маг — лечит и держит лозами", "Охотница — бьёт издалека и оглушает"]
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
	return DeviceProfile.touch_controls


func _mobile_ui() -> bool:
	return DeviceProfile.mobile_ui


func _build_shop(root: Control) -> void:
	shop_dim = ColorRect.new()
	shop_dim.name = "ShopDim"
	shop_dim.color = Color(0.02, 0.02, 0.05, 0.68)
	shop_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop_dim.visible = false
	shop_dim.z_index = 20
	root.add_child(shop_dim)

	shop_panel = PanelContainer.new()
	shop_panel.name = "ShopPanel"
	shop_panel.anchor_left = 0.5
	shop_panel.anchor_top = 0.5
	shop_panel.anchor_right = 0.5
	shop_panel.anchor_bottom = 0.5
	shop_panel.offset_left = -400.0
	shop_panel.offset_top = -260.0
	shop_panel.offset_right = 400.0
	shop_panel.offset_bottom = 260.0
	shop_panel.custom_minimum_size = Vector2.ZERO
	shop_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.68, 0.53, 0.29, 0.95), Color(0.035, 0.04, 0.065, 0.94)))
	shop_panel.visible = false
	shop_panel.z_index = 21
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
	close_button.add_theme_font_size_override("font_size", _fs(24))
	close_button.add_theme_color_override("font_color", PALE)
	close_button.add_theme_color_override("font_hover_color", Color.WHITE)
	close_button.add_theme_stylebox_override("normal", _panel_style(Color(0.62, 0.49, 0.29, 0.75), Color(0.07, 0.075, 0.11, 0.9)))
	close_button.add_theme_stylebox_override("hover", _panel_style(Color(0.95, 0.36, 0.3, 1.0), Color(0.2, 0.07, 0.07, 0.98)))
	close_button.add_theme_stylebox_override("pressed", _panel_style(Color(1.0, 0.55, 0.42, 1.0), Color(0.25, 0.09, 0.08, 1.0)))
	close_button.pressed.connect(_on_shop_close_pressed)
	header.add_child(close_button)

	var subtitle := _make_label("Улучшения до конца боя · по одной покупке каждого предмета", 14, PALE)
	layout.add_child(subtitle)
	shop_hint_label = _make_label("", 16, GOLD)
	shop_hint_label.name = "ShopTutorialHint"
	shop_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shop_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_hint_label.add_theme_stylebox_override("normal", _panel_style(Color(0.95, 0.78, 0.4, 0.9), Color(0.08, 0.07, 0.04, 0.95)))
	shop_hint_label.visible = false
	layout.add_child(shop_hint_label)

	var scroll := ScrollContainer.new()
	scroll.name = "ShopScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	layout.add_child(scroll)
	shop_scroll = scroll

	var grid_center := CenterContainer.new()
	grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_center)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.custom_minimum_size = Vector2(760.0, 0.0)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	grid_center.add_child(grid)

	for item in game.get_shop_items():
		var item_id := String(item["id"])
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 120.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.clip_contents = true
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
		icon.texture = custom_texture
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
	var team_short := "Свет" if player.team == 0 else "Тьма"
	# The card shows the nickname and the side only: the class word was cut to
	# an ellipsis on a 960-wide phone card. The portrait carries the class and
	# the equipped skin instead of a caption.
	player_name_label.text = nickname
	var name_font_size := 16 if _mobile_ui() else 15
	if player_name_font_size != name_font_size:
		player_name_font_size = name_font_size
		player_name_label.add_theme_font_size_override("font_size", name_font_size)
	if player_team_label != null:
		player_team_label.visible = true
		player_team_label.text = team_short
	# Reload the avatar only when the hero or the equipped skin changes.
	var skin_id := MetaProgression.get_equipped_skin(["warrior", "mage", "fairy"][player.hero_class])
	if player_panel_class != player.hero_class or player_panel_skin != skin_id:
		player_panel_class = player.hero_class
		player_panel_skin = skin_id
		if player_avatar != null:
			var portrait_source := _player_portrait_texture(player.hero_class)
			if portrait_source != null:
				player_avatar.texture = portrait_source
	if player_panel_team != player.team:
		player_panel_team = player.team
		if player_team_icon != null:
			player_team_icon.texture = _team_icon(player.team)
		if player_team_label != null:
			player_team_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0) if player.team == 0 else Color(0.78, 0.62, 1.0))
	# The kill feed is authored just below the player card. A scaled feed top
	# (75px on a 960-wide canvas) lands under a taller card; keep an 8px gap.
	if _mobile_ui() and kill_feed_box != null and is_instance_valid(kill_feed_box) and kill_feed_box.size.y > 0.0:
		var feed_top := player_panel.position.y + player_panel.size.y + 8.0
		if kill_feed_box.position.y < feed_top:
			var feed_height := kill_feed_box.size.y
			kill_feed_box.offset_top = feed_top
			kill_feed_box.offset_bottom = feed_top + feed_height


func _player_portrait_texture(hero_class: int) -> Texture2D:
	var skin_id := MetaProgression.get_equipped_skin(["warrior", "mage", "fairy"][hero_class])
	var skin := SkinCatalog.get_item(skin_id)
	if not skin.is_empty():
		# Legendary skins have full key art on `card`; the plain skins only
		# carry a square `icon`, the same picture the lobby avatar uses.
		var path := String(skin.get("icon", ""))
		if not String(skin.get("tier", "")).is_empty():
			var card_path := String(skin.get("card", ""))
			if not card_path.is_empty():
				path = card_path
		if not path.is_empty() and ResourceLoader.exists(path):
			var texture := load(path) as Texture2D
			if texture != null:
				return texture
	if HERO_PORTRAITS.has(hero_class):
		return HERO_PORTRAITS[hero_class] as Texture2D
	return null


func _update_player_health() -> void:
	# HP is the one value that must never lag: the bar above the hero is
	# redrawn every frame, so a 10 Hz player card showed a different health
	# during every burst. The slower panel refresh still owns the nickname,
	# portrait and team, but health is read live in _process.
	if player_hp_bar == null or player_hp_label == null or game == null:
		return
	var player := game.player as HeroUnit
	if player == null or not is_instance_valid(player) or game.state == "select":
		player_panel.visible = false
		return
	player_panel.visible = true
	var hp_max := maxf(1.0, player.max_health)
	var hp_value := clampf(player.health, 0.0, hp_max)
	if not is_equal_approx(player_hp_bar.max_value, hp_max):
		player_hp_bar.max_value = hp_max
	if not is_equal_approx(player_hp_bar.value, hp_value):
		player_hp_bar.value = hp_value
	var hp_text := "%d / %d" % [roundi(player.health), roundi(player.max_health)]
	if player_hp_label.text != hp_text:
		player_hp_label.text = hp_text


func set_shop_open(open: bool) -> void:
	if shop_panel == null:
		return
	_layout_shop_panel()
	shop_panel.visible = open
	if shop_dim != null:
		shop_dim.visible = open
	_layout_tutorial_hint(open)
	if open:
		update_shop()
	else:
		tutorial_shop_item = ""
		if shop_hint_label != null:
			shop_hint_label.visible = false
		set_focus_target(null)


func _layout_shop_panel() -> void:
	# The in-battle shop is a modal over a 960x540 phone canvas. In the
	# tutorial the top strip and the skip plate stay above it, so the mobile
	# shop is pinned below that row instead of under it; the header used to be
	# hidden behind "Собирай 15 монет" / "Пропустить обучение".
	if shop_panel == null or not is_instance_valid(shop_panel):
		return
	var viewport_size := _hud_viewport_size()
	var mobile := _mobile_ui()
	var tutorial_bar := (
		mobile
		and game != null
		and bool(game.get("tutorial_mode"))
		and tutorial_skip_button != null
		and tutorial_skip_button.visible
	)
	shop_panel.anchor_left = 0.5
	shop_panel.anchor_right = 0.5
	var half_width := minf(400.0, maxf(280.0, (viewport_size.x - 24.0) * 0.5))
	shop_panel.offset_left = -half_width
	shop_panel.offset_right = half_width
	if tutorial_bar:
		var top := 84.0
		if tutorial_hint != null and is_instance_valid(tutorial_hint) and tutorial_hint.visible:
			var origin := Vector2.ZERO
			var hud_root := get_child(0) as Control if get_child_count() > 0 else null
			if hud_root != null:
				origin = hud_root.global_position
			top = maxf(top, tutorial_hint.get_global_rect().end.y - origin.y + 6.0)
		top = minf(top, viewport_size.y - 310.0)
		var height := minf(520.0, maxf(300.0, viewport_size.y - top - 10.0))
		shop_panel.anchor_top = 0.0
		shop_panel.anchor_bottom = 0.0
		shop_panel.offset_top = top
		shop_panel.offset_bottom = top + height
		return
	shop_panel.anchor_top = 0.5
	shop_panel.anchor_bottom = 0.5
	shop_panel.offset_top = -260.0
	shop_panel.offset_bottom = 260.0


func update_gold() -> void:
	if gold_label != null and game != null:
		gold_label.text = "Золото: %d" % game.gold
		gold_label.visible = not bool(game.get("tutorial_mode"))


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
	if game != null and bool(game.get("tutorial_mode")):
		# Owner: in the tutorial everything is written in the top strip only,
		# so a message that is also the strip hint is never drawn twice.
		if _tutorial_announcement_duplicates_hint(text):
			return
		show_tutorial_hint(text)
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


func _tutorial_announcement_duplicates_hint(text: String) -> bool:
	# The shard message exists twice in the code base: the tutorial strip
	# ("Неси Осколок на свою базу") and game.gd's match announce ("Осколок у
	# тебя! Неси на базу"). Keep the strip, drop the second line.
	if tutorial_hint == null or not tutorial_hint.visible or tutorial_hint.text.is_empty():
		return false
	var message := text.to_lower().replace(" ", "")
	var hint := tutorial_hint.text.to_lower().replace(" ", "")
	if message == hint:
		return true
	return (
		message.contains("осколок") and message.contains("баз")
		and hint.contains("осколок") and hint.contains("баз")
	)


func _build_stun_badge(root: Control) -> void:
	stun_badge = PanelContainer.new()
	stun_badge.name = "StunBadge"
	stun_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stun_badge.anchor_left = 0.5
	stun_badge.anchor_right = 0.5
	stun_badge.anchor_top = 0.0
	stun_badge.anchor_bottom = 0.0
	stun_badge.offset_left = -155.0
	stun_badge.offset_right = 155.0
	stun_badge.offset_top = 96.0
	stun_badge.offset_bottom = 152.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.34, 0.05, 0.04, 0.93)
	style.border_color = Color(1.0, 0.78, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	stun_badge.add_theme_stylebox_override("panel", style)
	root.add_child(stun_badge)
	stun_badge_label = Label.new()
	stun_badge_label.text = "ОГЛУШЕНИЕ"
	stun_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stun_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stun_badge_label.add_theme_font_override("font", UI_FONT)
	stun_badge_label.add_theme_font_size_override("font_size", 24)
	stun_badge_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	stun_badge.add_child(stun_badge_label)
	stun_badge.visible = false


func _process(_delta: float) -> void:
	_update_low_health_vignette(_delta)
	_update_tutorial_press_hint()
	_update_focus_panel()
	if game == null:
		return
	_update_player_health()
	if stun_badge != null:
		var stunned_player = game.player
		var is_stunned: bool = (
			stunned_player != null
			and is_instance_valid(stunned_player)
			and not stunned_player.dead
			and float(stunned_player.stun_timer) > 0.05
			and game.state == "live"
		)
		stun_badge.visible = is_stunned
		if is_stunned and stun_badge_label.text != "ОГЛУШЕНИЕ":
			stun_badge_label.text = "ОГЛУШЕНИЕ"
	if touch_joystick != null:
		touch_joystick.visible = game.state != "select"
	if game.player != null and is_instance_valid(game.player) and game.player.hero_class != icon_class:
		icon_class = game.player.hero_class
		_refresh_ability_icons(icon_class)
	hud_tick += _delta
	var slow_ui := hud_tick >= 0.1
	if slow_ui:
		hud_tick = 0.0
		update_gold()
		_update_player_panel()
		if scoreboard_button != null:
			scoreboard_button.visible = (
				_mobile_ui()
				and game.state == "live"
				and not bool(game.get("tutorial_mode"))
			)
		if bool(game.get("tutorial_mode")) and scoreboard_panel != null and scoreboard_panel.visible:
			_close_scoreboard()
		_update_scoreboard_layout()
		scoreboard_refresh_tick += 0.1
		if scoreboard_panel != null and scoreboard_panel.visible:
			if game.state != "live":
				_close_scoreboard()
			elif scoreboard_refresh_tick >= 0.4:
				# Do not rebuild rows under a click or under the report dialog.
				if scoreboard_report_overlay == null or not scoreboard_report_overlay.visible:
					scoreboard_refresh_tick = 0.0
					_refresh_scoreboard()
		if center_respawn_label != null:
			var is_respawning: bool = game.state == "live" and game.player != null and is_instance_valid(game.player) and game.player.dead
			center_respawn_label.visible = is_respawning
			if is_respawning:
				center_respawn_label.text = "Возрождение\n%d" % int(ceil(maxf(0.0, float(game.player.respawn_timer))))
				center_respawn_label.modulate.a = 1.0
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
		gold_label.visible = not game.tutorial_mode
		var shell_time_left: float = game.shell_window if game.shell_phase == "active" else game.shell_timer
		shell_time_left = maxf(0.0, shell_time_left)
		var shell_minutes := floori(shell_time_left / 60.0)
		var shell_seconds := int(shell_time_left) % 60
		shell_timer_label.text = "Оболочка: %02d:%02d" % [shell_minutes, shell_seconds]
	if ability_row != null:
		ability_row.visible = game.state != "select"

	if game.player != null and is_instance_valid(game.player):
		var p = game.player
		for i in 3:
			var data: Dictionary = HeroUnit.CLASS_DATA[p.hero_class]["abilities"][i]
			var cd: float = p.ability_cds[i]
			var cooldown_length := maxf(0.001, float(data["cd"]) * (1.0 - p.cooldown_reduction))
			var progress := 1.0 if cd <= 0.01 else clampf(1.0 - cd / cooldown_length, 0.0, 1.0)
			# Updating the shader parameter and queueing a redraw every frame for
			# three buttons cost more than the whole HUD; only change on movement.
			if absf(progress - ability_wipe_progress[i]) > 0.01:
				ability_wipe_progress[i] = progress
				ability_wipes[i].set_progress(progress)
			_set_ability_ready(i, cd <= 0.01)
	else:
		if center_respawn_label != null:
			center_respawn_label.visible = false

	if game.state == "over":
		end_panel.visible = true
		end_title.text = game.result_text
		end_title.add_theme_color_override("font_color", Color(0.85, 1.0, 0.7) if game.player_won else Color(1.0, 0.55, 0.5))
		end_score.text = "Свет — %d:%d — Тьма" % [game.score[0], game.score[1]]


func _fs(size: int) -> int:
	if DeviceProfile.mobile_ui:
		return maxi(size, 18)
	return size
