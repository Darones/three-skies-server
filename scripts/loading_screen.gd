extends Control

const MAP_ART := "res://assets/concept/01_temple_ruins.png"
const GAME_LOGO: Texture2D = preload("res://ui/logo.png")
const COUNTDOWN_SECONDS := 1
const TUTORIAL_FONT: FontFile = preload("res://assets/fonts/Philosopher-Regular.ttf")
const TUTORIAL_TEXT := "Цель игры: вместе победите Оболочку, подберите Осколок и донесите его до базы. Первыми доставьте три Осколка.\n\nВоин — врывается в бой и оглушает врагов.\nМаг — лечит союзников и удерживает врагов лозами.\nФея — атакует издалека и оглушает."
const TIPS := [
	"Бейте Оболочку вместе! Чем больше союзников рядом, тем меньше урона от молний получает каждый.",
	"Носильщик Кристалла двигается вдвое медленнее. Прикрывайте его!",
	"Фея хрупкая, но наносит огромный урон с дистанции. Воин должен защищать её.",
	"Если носильщик Кристалла погибнет, Кристалл упадет на землю. Скорее подберите его!",
]

var progress_bar: ProgressBar
var tip_label: Label
var countdown_label: Label
var tutorial_label: Label
var waiting_layer: CanvasLayer
var players: Array = []
var is_1v1 := false
var fill_with_bots := false
var no_network := false
var match_transition_started := false

func _ready() -> void:
	_build_screen()
	tip_label.text = TIPS.pick_random()
	get_node("TipPanel").visible = false
	NetworkClient.match_started.connect(_on_match_started)
	NetworkClient.players_list.connect(_on_players_list)
	NetworkClient.connection_failed.connect(_on_connection_failed)
	no_network = bool(get_tree().get_meta("matchmaking_no_network", false))
	if no_network:
		_on_connection_failed()
	else:
		_run_countdown()

func _on_match_started() -> void:
	if players.size() == 2:
		is_1v1 = true
		fill_with_bots = false
	else:
		fill_with_bots = true
	_open_match_scene()


func _on_players_list(found_players: Array) -> void:
	players = found_players.duplicate()
	if players.size() == 2:
		is_1v1 = true
		fill_with_bots = false
		_open_match_scene()


func _on_connection_failed() -> void:
	if match_transition_started:
		return
	no_network = true
	fill_with_bots = true
	countdown_label.text = "Сервер недоступен. Игра с ботами."
	await get_tree().create_timer(1.0).timeout
	_open_match_scene()


func _run_countdown() -> void:
	for remaining in range(COUNTDOWN_SECONDS, -1, -1):
		if match_transition_started:
			return
		countdown_label.text = "Бой начнётся через: %d…" % remaining
		progress_bar.value = float(COUNTDOWN_SECONDS - remaining) * 100.0 / float(COUNTDOWN_SECONDS)
		if remaining == 0:
			fill_with_bots = true
			_open_match_scene()
			return
		await get_tree().create_timer(1.0).timeout

func _open_match_scene() -> void:
	if match_transition_started:
		return
	match_transition_started = true
	get_tree().set_meta("is_1v1", is_1v1)
	get_tree().set_meta("fill_with_bots", fill_with_bots or not is_1v1)
	get_tree().set_meta("match_players", players)
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

	var logo := TextureRect.new()
	logo.name = "GameLogo"
	logo.texture = GAME_LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.anchor_left = 0.2
	logo.anchor_top = 0.025
	logo.anchor_right = 0.8
	logo.anchor_bottom = 0.155
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)

	var loading_title := _make_label("ФОНОВАЯ ЗАГРУЗКА ПЕРЕД БОЕМ", 20, Color(1.0, 0.84, 0.56, 1.0))
	loading_title.name = "LoadingTitle"
	loading_title.anchor_left = 0.08
	loading_title.anchor_top = 0.16
	loading_title.anchor_right = 0.92
	loading_title.anchor_bottom = 0.205
	add_child(loading_title)

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
	_build_waiting_card()


func _build_waiting_card() -> void:
	waiting_layer = CanvasLayer.new()
	waiting_layer.name = "WaitingOverlay"
	waiting_layer.layer = 100
	add_child(waiting_layer)
	var overlay_root := Control.new()
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	waiting_layer.add_child(overlay_root)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.005, 0.008, 0.018, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_root.add_child(dim)
	var card := PanelContainer.new()
	card.name = "WaitingCard"
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.anchor_left = 0.5
	card.anchor_top = 0.5
	card.anchor_right = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -250.0
	card.offset_top = -220.0
	card.offset_right = 250.0
	card.offset_bottom = 220.0
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.025, 0.035, 0.06, 0.96)
	card_style.border_color = Color(0.82, 0.67, 0.38, 0.9)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(12)
	card_style.content_margin_left = 24.0
	card_style.content_margin_right = 24.0
	card_style.content_margin_top = 20.0
	card_style.content_margin_bottom = 20.0
	card.add_theme_stylebox_override("panel", card_style)
	overlay_root.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	card.add_child(content)
	content.add_child(_make_label("Ожидание игроков", 30, Color(1.0, 0.84, 0.56, 1.0)))
	countdown_label = _make_label("Бой начнётся через: %d…" % COUNTDOWN_SECONDS, 20, Color(0.97, 0.97, 1.0, 1.0))
	countdown_label.name = "CountdownText"
	content.add_child(countdown_label)
	tutorial_label = _make_label(TUTORIAL_TEXT, 19, Color(0.97, 0.97, 1.0, 1.0))
	tutorial_label.name = "TutorialText"
	tutorial_label.add_theme_font_override("font", TUTORIAL_FONT)
	tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(tutorial_label)
	content.add_child(_make_label("Полезный совет", 17, Color(1.0, 0.78, 0.36, 1.0)))
	tip_label = _make_label("", 17, Color(0.97, 0.97, 1.0, 1.0))
	tip_label.name = "TipText"
	tip_label.add_theme_font_override("font", TUTORIAL_FONT)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(tip_label)

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


