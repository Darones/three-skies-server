extends Control

const HERO_ART := [
	"res://assets/characters/warrior_light.png",
	"res://assets/characters/mage_dark.png",
	"res://assets/characters/fairy.png",
]
const HERO_NAMES := ["Воин", "Маг", "Фея"]
const SAVE_PATH := "user://lobby.cfg"
const GOLD := Color(0.95, 0.76, 0.38)
const PALE := Color(0.9, 0.92, 0.98)

var selected_class := 0
var slot_classes: Array[int] = [HeroUnit.Cls.MAGE, HeroUnit.Cls.WARRIOR, HeroUnit.Cls.FAIRY]
var card_images: Array[TextureRect] = []
var card_names: Array[Label] = []
var cards: Array[Control] = []
var avatar: TextureRect
var status_label: Label
var font: SystemFont


func _ready() -> void:
	randomize()
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Georgia", "Palatino Linotype", "Times New Roman"])
	selected_class = _load_selection()
	get_tree().set_meta("selected_class", selected_class)
	_build_background()
	_build_header()
	_build_player_profile()
	_build_currency_panel()
	_build_hero_cards()
	_build_actions()
	_refresh_selection()


func _load_selection() -> int:
	var config := ConfigFile.new()
	var error := config.load(SAVE_PATH)
	if error != OK:
		return HeroUnit.Cls.WARRIOR
	return clampi(int(config.get_value("profile", "selected_class", HeroUnit.Cls.WARRIOR)), 0, 2)


func _save_selection() -> void:
	var config := ConfigFile.new()
	config.set_value("profile", "selected_class", selected_class)
	config.save(SAVE_PATH)
	get_tree().set_meta("selected_class", selected_class)


func _build_background() -> void:
	var background := ColorRect.new()
	background.name = "LobbyBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.025, 0.035, 0.06)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var glow := ColorRect.new()
	glow.name = "CenterGlow"
	glow.anchor_left = 0.28
	glow.anchor_top = 0.16
	glow.anchor_right = 0.72
	glow.anchor_bottom = 0.9
	glow.color = Color(0.18, 0.15, 0.1, 0.16)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var top_rule := ColorRect.new()
	top_rule.name = "TopAccent"
	top_rule.anchor_left = 0.28
	top_rule.anchor_top = 0.13
	top_rule.anchor_right = 0.72
	top_rule.anchor_bottom = 0.132
	top_rule.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.48)
	top_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_rule)


func _build_header() -> void:
	var title := _make_label("ОСКОЛКИ НЕБА", 28, GOLD)
	title.name = "LobbyTitle"
	title.anchor_left = 0.34
	title.anchor_top = 0.035
	title.anchor_right = 0.66
	title.anchor_bottom = 0.11
	add_child(title)

	var subtitle := _make_label("Выберите героя", 15, Color(0.7, 0.75, 0.85))
	subtitle.name = "LobbySubtitle"
	subtitle.anchor_left = 0.36
	subtitle.anchor_top = 0.105
	subtitle.anchor_right = 0.64
	subtitle.anchor_bottom = 0.145
	add_child(subtitle)


func _build_player_profile() -> void:
	var panel := PanelContainer.new()
	panel.name = "PlayerProfile"
	panel.anchor_left = 0.02
	panel.anchor_top = 0.025
	panel.anchor_right = 0.29
	panel.anchor_bottom = 0.16
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.54, 0.65, 0.82, 0.62), Color(0.035, 0.05, 0.08, 0.88)))
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 13)
	panel.add_child(row)

	var avatar_frame := PanelContainer.new()
	avatar_frame.name = "AvatarFrame"
	avatar_frame.custom_minimum_size = Vector2(66, 66)
	avatar_frame.add_theme_stylebox_override("panel", _panel_style(GOLD, Color(0.08, 0.1, 0.15)))
	row.add_child(avatar_frame)
	avatar = TextureRect.new()
	avatar.name = "PlayerAvatar"
	avatar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_frame.add_child(avatar)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var player_name := _make_label("Игрок", 18, PALE)
	player_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(player_name)
	var level := _make_label("Уровень 1", 13, Color(0.7, 0.75, 0.84))
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(level)
	var experience := ProgressBar.new()
	experience.name = "ExperienceBar"
	experience.custom_minimum_size = Vector2(0, 10)
	experience.min_value = 0
	experience.max_value = 100
	experience.value = 0
	experience.show_percentage = false
	var experience_bg := StyleBoxFlat.new()
	experience_bg.bg_color = Color(0.08, 0.09, 0.13)
	experience_bg.set_corner_radius_all(5)
	var experience_fill := StyleBoxFlat.new()
	experience_fill.bg_color = Color(0.46, 0.74, 1.0)
	experience_fill.set_corner_radius_all(5)
	experience.add_theme_stylebox_override("background", experience_bg)
	experience.add_theme_stylebox_override("fill", experience_fill)
	info.add_child(experience)


func _build_currency_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "CurrencyPanel"
	panel.anchor_left = 0.77
	panel.anchor_top = 0.035
	panel.anchor_right = 0.98
	panel.anchor_bottom = 0.12
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.54, 0.65, 0.82, 0.62), Color(0.035, 0.05, 0.08, 0.88)))
	add_child(panel)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	panel.add_child(row)
	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 7)
	row.add_child(gold_row)
	gold_row.add_child(_make_label("●", 22, Color(1.0, 0.73, 0.22)))
	gold_row.add_child(_make_label("0", 17, PALE))
	var crystal_row := HBoxContainer.new()
	crystal_row.add_theme_constant_override("separation", 7)
	row.add_child(crystal_row)
	crystal_row.add_child(_make_label("◆", 20, Color(0.43, 0.84, 1.0)))
	crystal_row.add_child(_make_label("0", 17, PALE))


func _build_hero_cards() -> void:
	_build_hero_card(0, false)
	_build_hero_card(1, true)
	_build_hero_card(2, false)


func _build_hero_card(slot: int, is_center: bool) -> void:
	var card: Control
	if is_center:
		card = PanelContainer.new()
	else:
		card = Button.new()
		(card as Button).focus_mode = Control.FOCUS_NONE
		(card as Button).clip_contents = true
		(card as Button).pressed.connect(_on_side_card_pressed.bind(slot))

	card.name = "HeroCard%d" % slot
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.anchor_left = 0.5
	card.anchor_top = 0.5
	card.anchor_right = 0.5
	card.anchor_bottom = 0.5
	if is_center:
		card.offset_left = -175.0
		card.offset_top = -178.0
		card.offset_right = 175.0
		card.offset_bottom = 270.0
		card.z_index = 2
	else:
		var side_offset := -415.0 if slot == 0 else 185.0
		card.offset_left = side_offset
		card.offset_top = -145.0
		card.offset_right = side_offset + 230.0
		card.offset_bottom = 185.0
		card.z_index = 1
	if is_center:
		card.add_theme_stylebox_override("panel", _card_style(true, false))
	else:
		var side_button := card as Button
		side_button.add_theme_stylebox_override("normal", _card_style(false, false))
		side_button.add_theme_stylebox_override("hover", _card_style(false, true))
		side_button.add_theme_stylebox_override("pressed", _card_style(false, true))
	add_child(card)

	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 6)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(content)

	var image := TextureRect.new()
	image.custom_minimum_size = Vector2(0, 365 if is_center else 255)
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(image)
	var name_label := _make_label("", 27 if is_center else 19, PALE)
	name_label.name = "HeroName%d" % slot
	name_label.custom_minimum_size = Vector2(0, 34)
	content.add_child(name_label)
	cards.append(card)
	card_images.append(image)
	card_names.append(name_label)


func _build_actions() -> void:
	var action_panel := PanelContainer.new()
	action_panel.name = "LobbyActions"
	action_panel.anchor_left = 0.82
	action_panel.anchor_top = 0.69
	action_panel.anchor_right = 0.98
	action_panel.anchor_bottom = 0.98
	action_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.54, 0.65, 0.82, 0.5), Color(0.035, 0.05, 0.08, 0.86)))
	add_child(action_panel)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 9)
	action_panel.add_child(buttons)
	var play_button := _make_action_button("В БОЙ", true)
	play_button.name = "PlayButton"
	play_button.pressed.connect(_start_battle)
	buttons.add_child(play_button)
	var skins_button := _make_action_button("СКИНЫ", false)
	skins_button.pressed.connect(_show_coming_soon)
	buttons.add_child(skins_button)
	var quests_button := _make_action_button("ЗАДАНИЯ", false)
	quests_button.pressed.connect(_show_coming_soon)
	buttons.add_child(quests_button)

	status_label = _make_label("", 13, Color(0.82, 0.84, 0.91))
	status_label.anchor_left = 0.34
	status_label.anchor_top = 0.91
	status_label.anchor_right = 0.69
	status_label.anchor_bottom = 0.96
	add_child(status_label)


func _refresh_selection() -> void:
	var side_classes: Array[int] = []
	for hero_class in range(3):
		if hero_class != selected_class:
			side_classes.append(hero_class)
	slot_classes[0] = side_classes[0]
	slot_classes[1] = selected_class
	slot_classes[2] = side_classes[1]
	for slot in range(3):
		var hero_class: int = slot_classes[slot]
		card_images[slot].texture = load(HERO_ART[hero_class]) as Texture2D
		card_names[slot].text = HERO_NAMES[hero_class]
		if slot == 1:
			card_images[slot].modulate = Color.WHITE
			card_names[slot].add_theme_color_override("font_color", GOLD)
		else:
			card_images[slot].modulate = Color(0.46, 0.49, 0.56, 1.0)
			card_names[slot].add_theme_color_override("font_color", Color(0.62, 0.65, 0.72))
	avatar.texture = load(HERO_ART[selected_class]) as Texture2D


func _on_side_card_pressed(slot: int) -> void:
	selected_class = slot_classes[slot]
	_save_selection()
	_refresh_selection()
	status_label.text = "Выбран герой: " + HERO_NAMES[selected_class]


func _start_battle() -> void:
	_save_selection()
	get_tree().set_meta("selected_class", selected_class)
	get_tree().set_meta("selected_team", randi_range(0, 1))
	var error := get_tree().change_scene_to_file("res://scenes/LoadingScreen.tscn")
	if error != OK:
		push_error("Не удалось открыть экран загрузки: %s" % error_string(error))


func _show_coming_soon() -> void:
	status_label.text = "Этот раздел скоро появится"


func _make_action_button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(190, 54)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", GOLD if primary else PALE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _action_style(primary, false))
	button.add_theme_stylebox_override("hover", _action_style(primary, true))
	button.add_theme_stylebox_override("pressed", _action_style(primary, true))
	return button


func _action_style(primary: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.14, 0.08, 0.94) if primary else Color(0.07, 0.09, 0.13, 0.93)
	style.border_color = GOLD if primary else Color(0.46, 0.54, 0.69, 0.82)
	if hovered:
		style.bg_color = Color(0.27, 0.21, 0.11, 1.0) if primary else Color(0.12, 0.16, 0.22, 1.0)
		style.border_color = Color(1.0, 0.88, 0.58) if primary else Color(0.76, 0.84, 0.98)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _card_style(is_center: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.06, 0.09, 0.93) if is_center else Color(0.035, 0.045, 0.07, 0.78)
	style.border_color = GOLD if is_center else Color(0.43, 0.5, 0.65, 0.58)
	if hovered and not is_center:
		style.bg_color = Color(0.075, 0.09, 0.13, 0.95)
		style.border_color = Color(0.78, 0.85, 0.98, 0.9)
	style.set_border_width_all(2 if is_center else 1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 11.0
	style.content_margin_right = 11.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 9.0
	return style


func _panel_style(border_color: Color, fill_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label