extends Control

const MAP_ART := "res://assets/concept/01_temple_ruins.png"
const LOAD_DURATION := 3.0
const TIPS := [
	"Бейте Оболочку вместе! Чем больше союзников рядом, тем меньше урона от молний получает каждый.",
	"Носильщик Кристалла двигается вдвое медленнее. Прикрывайте его!",
	"Фея хрупкая, но наносит огромный урон с дистанции. Воин должен защищать её.",
	"Если носильщик Кристалла погибнет, Кристалл упадет на землю. Скорее подберите его!",
]

var progress_bar: ProgressBar
var tip_label: Label
var loading_started := false
var match_transition_started := false

func _ready() -> void:
	_build_screen()
	tip_label.text = TIPS.pick_random()
	NetworkClient.match_started.connect(_on_match_started)
	var loading_tween := create_tween()
	loading_tween.set_trans(Tween.TRANS_CUBIC)
	loading_tween.set_ease(Tween.EASE_IN_OUT)
	loading_tween.tween_property(progress_bar, "value", 100.0, LOAD_DURATION)
	loading_started = true
	await loading_tween.finished
	if is_inside_tree():
		_open_match_scene()

func _on_match_started() -> void:
	_open_match_scene()

func _open_match_scene() -> void:
	if match_transition_started:
		return
	match_transition_started = true
	var result := get_tree().change_scene_to_file("res://scenes/Main.tscn")
	if result != OK:
		match_transition_started = false
		push_error("Could not open the match scene: %s" % error_string(result))

func _build_screen() -> void:
	var artwork := TextureRect.new()
	artwork.name = "MapArtwork"
	artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	artwork.texture = load(MAP_ART) as Texture2D
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(artwork)

	var shade := ColorRect.new()
	shade.name = "ScreenDimmer"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.4)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var logo := _make_label("ОСКОЛКИ НЕБА", 42, Color(1.0, 0.84, 0.56, 1.0))
	logo.name = "Logo"
	logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	logo.anchor_top = 0.045
	logo.anchor_bottom = 0.15
	add_child(logo)

	var tip_panel := PanelContainer.new()
	tip_panel.name = "TipPanel"
	tip_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tip_panel.anchor_left = 0.1
	tip_panel.anchor_top = 0.56
	tip_panel.anchor_right = 0.9
	tip_panel.anchor_bottom = 0.84
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.018, 0.024, 0.045, 0.82)
	panel_style.border_color = Color(0.82, 0.67, 0.38, 0.72)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(12)
	panel_style.content_margin_left = 26.0
	panel_style.content_margin_right = 26.0
	panel_style.content_margin_top = 18.0
	panel_style.content_margin_bottom = 18.0
	tip_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(tip_panel)

	var content := VBoxContainer.new()
	content.name = "TipContent"
	content.add_theme_constant_override("separation", 10)
	tip_panel.add_child(content)
	content.add_child(_make_label("СОВЕТ", 24, Color(1.0, 0.78, 0.36, 1.0)))
	tip_label = _make_label("", 19, Color(0.97, 0.97, 1.0, 1.0))
	tip_label.name = "TipText"
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(tip_label)

	progress_bar = ProgressBar.new()
	progress_bar.name = "LoadingProgress"
	progress_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	progress_bar.anchor_left = 0.14
	progress_bar.anchor_top = 0.925
	progress_bar.anchor_right = 0.86
	progress_bar.anchor_bottom = 0.96
	progress_bar.custom_minimum_size = Vector2(0, 17)
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = false
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.035, 0.045, 0.07, 0.94)
	track.border_color = Color(0.75, 0.78, 0.86, 0.65)
	track.set_border_width_all(1)
	track.set_corner_radius_all(7)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.91, 0.71, 0.38, 1.0)
	fill.set_corner_radius_all(7)
	progress_bar.add_theme_stylebox_override("background", track)
	progress_bar.add_theme_stylebox_override("fill", fill)
	add_child(progress_bar)

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.01, 0.01, 0.02, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
