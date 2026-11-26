class_name WelcomeOverlay
extends Control

## Full-screen first-launch card: key art, logo and one yellow Play button.
## The age badge and the consent line belong to the initial HTML loader only.
## It is a view only: lobby.gd decides when it is shown (loading / welcome /
## error) and what Play does, so the game flow after the card never changes.

signal play_pressed
signal retry_pressed

enum State { HIDDEN, LOADING, WELCOME, ERROR, WARMING }

const KEYART: Texture2D = preload("res://ui/welcome/welcome_keyart.webp")
const LOGO: Texture2D = preload("res://ui/logo.png")
const FONT: FontFile = preload("res://assets/fonts/Philosopher-Regular.ttf")
const FONT_BOLD: FontFile = preload("res://assets/fonts/Philosopher-Bold.ttf")
const LOGO_ASPECT := 1024.0 / 576.0

const LOADING_TEXT := "Загрузка профиля…"
const ERROR_TEXT := "Профиль не загрузился\nПроверьте соединение и попробуйте ещё раз."
const WARMUP_TITLE := "Прогрев боя…"
const WARMUP_STAGE_TEXT := "Подготовка…"

const PALE := Color(0.9, 0.92, 0.98)
const BACKDROP := Color(0.016, 0.024, 0.043)


var state: State = State.HIDDEN
var welcome_logo: TextureRect
var loading_logo: TextureRect
var play_button: Button
var loading_layer: CenterContainer
var loading_label: Label
var retry_button: Button
var warmup_box: VBoxContainer
var warmup_title: Label
var warmup_bar: ProgressBar
var warmup_row: HBoxContainer
var warmup_stage: Label
var warmup_elapsed: Label
var warmup_done := false
## Tutorial loading reuses this card with a larger logo. Defaults keep the
## newcomer Welcome card exactly as it was.
var logo_scale := 1.0
var logo_max_height_ratio := 0.26

var _safe: Control
var _keyart: TextureRect
var _top_shade: TextureRect
var _bottom_shade: TextureRect
var _bottom: VBoxContainer
var _play_styles: Dictionary = {}
var _safe_left := 0.0
var _safe_top := 0.0
var _safe_right := 0.0
var _safe_bottom := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	visible = false
	_build()
	_apply_state()
	call_deferred("_layout")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _safe != null:
		_layout()


func show_loading(message := LOADING_TEXT) -> void:
	if loading_label != null:
		loading_label.text = message
	state = State.LOADING
	visible = true
	_apply_state()


func show_welcome() -> void:
	state = State.WELCOME
	visible = true
	_apply_state()


func show_error(message := ERROR_TEXT) -> void:
	if loading_label != null:
		loading_label.text = message
	state = State.ERROR
	visible = true
	_apply_state()


## Play was pressed: keep the same card (key art, logo) and swap the yellow
## button for a progress line while WarmupFlow prepares the match.
func show_warming() -> void:
	warmup_done = false
	if warmup_bar != null:
		warmup_bar.value = 0.0
	if warmup_stage != null:
		warmup_stage.text = WARMUP_STAGE_TEXT
	if warmup_elapsed != null:
		warmup_elapsed.text = "0.0 с"
	state = State.WARMING
	visible = true
	_apply_state()


func set_warmup_progress(percent: float, elapsed: float, stage: String) -> void:
	if warmup_bar != null:
		warmup_bar.value = clampf(percent, 0.0, 100.0)
	if warmup_elapsed != null:
		warmup_elapsed.text = "%.1f с" % maxf(0.0, elapsed)
	if warmup_stage != null and not stage.strip_edges().is_empty():
		warmup_stage.text = stage


## Stays on the 100% frame: lobby.gd switches to Main.tscn right after, so
## hiding here would flash the bare lobby for a frame.
func finish_warming() -> void:
	warmup_done = true
	if warmup_bar != null:
		warmup_bar.value = 100.0
	if warmup_stage != null:
		warmup_stage.text = "Готово"
	_layout()


func is_warming() -> bool:
	return visible and state == State.WARMING


func hide_overlay() -> void:
	state = State.HIDDEN
	visible = false


func is_welcome_visible() -> bool:
	return visible and state == State.WELCOME


func state_name() -> String:
	match state:
		State.LOADING:
			return "loading"
		State.WELCOME:
			return "welcome"
		State.WARMING:
			return "warming"
		State.ERROR:
			return "error"
		_:
			return "hidden"


## The yellow Play look comes from lobby.gd so the card and the lobby button
## can never drift apart.
func apply_play_styles(
	normal: StyleBoxFlat,
	hover: StyleBoxFlat,
	pressed: StyleBoxFlat,
	disabled: StyleBoxFlat
) -> void:
	_play_styles = {
		"normal": normal,
		"hover": hover,
		"pressed": pressed,
		"disabled": disabled,
	}
	_apply_play_styles()


func _apply_play_styles() -> void:
	if play_button == null:
		return
	for style_name in _play_styles.keys():
		play_button.add_theme_stylebox_override(String(style_name), _play_styles[style_name])


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "WelcomeBackdrop"
	backdrop.color = BACKDROP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_keyart = TextureRect.new()
	_keyart.name = "WelcomeKeyart"
	_keyart.texture = KEYART
	_keyart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_keyart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_keyart.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_keyart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_keyart)

	_top_shade = _make_shade(true)
	add_child(_top_shade)
	_bottom_shade = _make_shade(false)
	add_child(_bottom_shade)

	_safe = Control.new()
	_safe.name = "WelcomeSafeArea"
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe)

	welcome_logo = TextureRect.new()
	welcome_logo.name = "WelcomeLogo"
	welcome_logo.texture = LOGO
	welcome_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	welcome_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	welcome_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(welcome_logo)

	_bottom = VBoxContainer.new()
	_bottom.name = "WelcomeBottom"
	_bottom.alignment = BoxContainer.ALIGNMENT_END
	_bottom.add_theme_constant_override("separation", 12)
	_bottom.anchor_left = 0.0
	_bottom.anchor_right = 1.0
	_bottom.anchor_top = 1.0
	_bottom.anchor_bottom = 1.0
	_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(_bottom)

	play_button = Button.new()
	play_button.name = "WelcomePlayButton"
	play_button.text = "ИГРАТЬ"
	play_button.focus_mode = Control.FOCUS_NONE
	play_button.add_theme_font_override("font", FONT)
	play_button.add_theme_color_override("font_color", Color(0.16, 0.1, 0.02))
	play_button.add_theme_color_override("font_hover_color", Color(0.1, 0.06, 0.01))
	play_button.add_theme_color_override("font_pressed_color", Color(0.1, 0.06, 0.01))
	play_button.add_theme_color_override("font_disabled_color", Color(0.2, 0.13, 0.03))
	play_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play_button.pressed.connect(func() -> void: play_pressed.emit())
	_bottom.add_child(play_button)

	warmup_box = VBoxContainer.new()
	warmup_box.name = "WelcomeWarmup"
	warmup_box.alignment = BoxContainer.ALIGNMENT_CENTER
	warmup_box.add_theme_constant_override("separation", 8)
	warmup_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(warmup_box)

	warmup_title = Label.new()
	warmup_title.name = "WelcomeWarmupTitle"
	warmup_title.text = WARMUP_TITLE
	warmup_title.add_theme_font_override("font", FONT_BOLD)
	warmup_title.add_theme_color_override("font_color", Color(1.0, 0.87, 0.62))
	warmup_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	warmup_title.add_theme_constant_override("shadow_offset_x", 1)
	warmup_title.add_theme_constant_override("shadow_offset_y", 1)
	warmup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warmup_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warmup_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warmup_box.add_child(warmup_title)

	warmup_bar = ProgressBar.new()
	warmup_bar.name = "WelcomeWarmupBar"
	warmup_bar.max_value = 100.0
	warmup_bar.value = 0.0
	warmup_bar.show_percentage = false
	warmup_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	warmup_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warmup_bar.add_theme_stylebox_override("background", _warmup_bar_style(false))
	warmup_bar.add_theme_stylebox_override("fill", _warmup_bar_style(true))
	warmup_box.add_child(warmup_bar)

	warmup_row = HBoxContainer.new()
	warmup_row.name = "WelcomeWarmupInfo"
	warmup_row.add_theme_constant_override("separation", 10)
	warmup_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	warmup_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warmup_box.add_child(warmup_row)

	warmup_stage = Label.new()
	warmup_stage.name = "WelcomeWarmupStage"
	warmup_stage.text = WARMUP_STAGE_TEXT
	warmup_stage.add_theme_font_override("font", FONT)
	warmup_stage.add_theme_color_override("font_color", PALE)
	warmup_stage.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	warmup_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	warmup_stage.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warmup_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warmup_stage.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	warmup_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warmup_row.add_child(warmup_stage)

	warmup_elapsed = Label.new()
	warmup_elapsed.name = "WelcomeWarmupElapsed"
	warmup_elapsed.text = "0.0 с"
	warmup_elapsed.add_theme_font_override("font", FONT)
	warmup_elapsed.add_theme_color_override("font_color", Color(1.0, 0.87, 0.62))
	warmup_elapsed.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	warmup_elapsed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	warmup_elapsed.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warmup_elapsed.size_flags_horizontal = Control.SIZE_SHRINK_END
	warmup_elapsed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warmup_row.add_child(warmup_elapsed)

	loading_layer = CenterContainer.new()
	loading_layer.name = "WelcomeLoadingLayer"
	loading_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(loading_layer)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 22)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_layer.add_child(column)

	loading_logo = TextureRect.new()
	loading_logo.name = "WelcomeLoadingLogo"
	loading_logo.texture = LOGO
	loading_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	loading_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	loading_logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	loading_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(loading_logo)

	loading_label = Label.new()
	loading_label.name = "WelcomeLoadingLabel"
	loading_label.text = LOADING_TEXT
	loading_label.add_theme_font_override("font", FONT)
	loading_label.add_theme_color_override("font_color", PALE)
	loading_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loading_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(loading_label)

	retry_button = Button.new()
	retry_button.name = "WelcomeRetryButton"
	retry_button.text = "Повторить"
	retry_button.focus_mode = Control.FOCUS_NONE
	retry_button.add_theme_font_override("font", FONT)
	retry_button.add_theme_color_override("font_color", PALE)
	retry_button.add_theme_color_override("font_hover_color", Color.WHITE)
	retry_button.add_theme_stylebox_override("normal", _secondary_style(false))
	retry_button.add_theme_stylebox_override("hover", _secondary_style(true))
	retry_button.add_theme_stylebox_override("pressed", _secondary_style(true))
	retry_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	retry_button.pressed.connect(func() -> void: retry_pressed.emit())
	column.add_child(retry_button)
	_apply_play_styles()


func _make_shade(top: bool) -> TextureRect:
	var gradient := Gradient.new()
	if top:
		gradient.set_color(0, Color(0.0, 0.0, 0.0, 0.8))
		gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	else:
		gradient.set_color(0, Color(0.01, 0.012, 0.02, 0.0))
		gradient.set_color(1, Color(0.01, 0.012, 0.02, 0.94))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 8
	texture.height = 128
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	if top:
		shade.name = "WelcomeTopShade"
		shade.anchor_top = 0.0
		shade.anchor_bottom = 0.26
	else:
		shade.name = "WelcomeBottomShade"
		shade.anchor_top = 0.54
		shade.anchor_bottom = 1.0
	return shade


func _secondary_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.16, 0.22, 1.0) if hovered else Color(0.07, 0.09, 0.13, 0.93)
	style.border_color = Color(0.76, 0.84, 0.98) if hovered else Color(0.46, 0.54, 0.69, 0.82)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _warmup_bar_style(fill: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if fill:
		style.bg_color = Color(0.95, 0.76, 0.38)
		style.set_corner_radius_all(6)
	else:
		style.bg_color = Color(0.03, 0.05, 0.09, 0.8)
		style.border_color = Color(0.56, 0.64, 0.8, 0.6)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


func _apply_state() -> void:
	var welcome := state == State.WELCOME
	var warming := state == State.WARMING
	var card := welcome or warming
	visible = state != State.HIDDEN
	_keyart.visible = card
	_top_shade.visible = card
	_bottom_shade.visible = card
	welcome_logo.visible = card
	_bottom.visible = card
	warmup_box.visible = warming
	loading_layer.visible = state == State.LOADING or state == State.ERROR
	retry_button.visible = state == State.ERROR
	play_button.visible = welcome
	play_button.disabled = not welcome
	play_button.mouse_filter = Control.MOUSE_FILTER_STOP if welcome else Control.MOUSE_FILTER_IGNORE
	if state == State.ERROR:
		loading_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.78))
	else:
		loading_label.add_theme_color_override("font_color", PALE)
	_layout()


func _layout() -> void:
	if _safe == null or size.x <= 0.0 or size.y <= 0.0:
		return
	_update_safe_area()
	var width := maxf(1.0, size.x - _safe_left - _safe_right)
	var height := maxf(1.0, size.y - _safe_top - _safe_bottom)
	var k := clampf(minf(width / 1280.0, height / 720.0), 0.6, 1.6)
	var pad_x := clampf(width * 0.05, 14.0, 140.0)
	var bottom_margin := clampf(height * 0.022, 8.0, 26.0)

	_bottom.offset_left = pad_x
	_bottom.offset_right = -pad_x
	_bottom.offset_top = -bottom_margin
	_bottom.offset_bottom = -bottom_margin
	_bottom.add_theme_constant_override("separation", clampi(int(round(12.0 * k)), 8, 18))

	var button_width := clampf(width * 0.32, 240.0, 480.0)
	var button_height := clampf(button_width * 0.19, 52.0, 86.0)
	play_button.custom_minimum_size = Vector2(button_width, button_height)
	play_button.add_theme_font_size_override(
		"font_size", clampi(int(round(button_height * 0.36)), 18, 34)
	)

	var bar_width := clampf(width * 0.42, 220.0, 520.0)
	if warmup_bar != null:
		warmup_bar.custom_minimum_size = Vector2(bar_width, clampf(7.0 * k, 10.0, 16.0))
		warmup_row.custom_minimum_size = Vector2(bar_width, 0.0)
		warmup_title.add_theme_font_size_override(
			"font_size", clampi(int(round(20.0 * k)), 16, 28)
		)
		var warmup_info_font := clampi(int(round(15.0 * k)), 13, 20)
		warmup_stage.add_theme_font_size_override("font_size", warmup_info_font)
		warmup_elapsed.add_theme_font_size_override("font_size", warmup_info_font)
		warmup_box.add_theme_constant_override("separation", clampi(int(round(8.0 * k)), 5, 13))

	var logo_top := clampf(height * 0.018, 6.0, 22.0)
	var logo_width := clampf(width * 0.22, 150.0, 300.0) * logo_scale
	var logo_height := logo_width / LOGO_ASPECT
	var logo_max_height := height * logo_max_height_ratio
	if logo_height > logo_max_height:
		logo_height = logo_max_height
		logo_width = logo_height * LOGO_ASPECT
	welcome_logo.anchor_left = 0.5
	welcome_logo.anchor_right = 0.5
	welcome_logo.anchor_top = 0.0
	welcome_logo.anchor_bottom = 0.0
	welcome_logo.offset_left = -logo_width * 0.5
	welcome_logo.offset_right = logo_width * 0.5
	welcome_logo.offset_top = logo_top
	welcome_logo.offset_bottom = logo_top + logo_height

	var loading_height := clampf(height * 0.16, 44.0, 130.0)
	var loading_width := loading_height * LOGO_ASPECT
	var loading_max_width := width * 0.6
	if loading_width > loading_max_width:
		loading_width = loading_max_width
		loading_height = loading_width / LOGO_ASPECT
	loading_logo.custom_minimum_size = Vector2(loading_width, loading_height)
	loading_label.custom_minimum_size = Vector2(minf(width * 0.8, 560.0), 0.0)
	loading_label.add_theme_font_size_override("font_size", clampi(int(round(20.0 * k)), 14, 26))
	retry_button.custom_minimum_size = Vector2(
		clampf(220.0 * k, 170.0, 240.0), clampf(48.0 * k, 40.0, 56.0)
	)
	retry_button.add_theme_font_size_override("font_size", clampi(int(round(16.0 * k)), 13, 20))


## Same safe-area maths as hud.gd: only phones and browsers have a notch.
func _update_safe_area() -> void:
	_safe_left = 0.0
	_safe_top = 0.0
	_safe_right = 0.0
	_safe_bottom = 0.0
	if OS.has_feature("mobile") or OS.has_feature("web"):
		var screen_size := Vector2(DisplayServer.window_get_size())
		if screen_size.x > 0.0 and screen_size.y > 0.0:
			var safe := DisplayServer.get_display_safe_area()
			var ratio := get_viewport_rect().size / screen_size
			_safe_left = maxf(0.0, float(safe.position.x) * ratio.x)
			_safe_top = maxf(0.0, float(safe.position.y) * ratio.y)
			_safe_right = maxf(0.0, float(screen_size.x - safe.end.x) * ratio.x)
			_safe_bottom = maxf(0.0, float(screen_size.y - safe.end.y) * ratio.y)
			# Never let a broken safe area squeeze the card into a strip.
			_safe_left = minf(_safe_left, size.x * 0.12)
			_safe_right = minf(_safe_right, size.x * 0.12)
			_safe_top = minf(_safe_top, size.y * 0.12)
			_safe_bottom = minf(_safe_bottom, size.y * 0.12)
	_safe.offset_left = _safe_left
	_safe.offset_top = _safe_top
	_safe.offset_right = -_safe_right
	_safe.offset_bottom = -_safe_bottom
