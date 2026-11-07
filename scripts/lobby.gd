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
const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const LOBBY_LOGO: Texture2D = preload("res://ui/logo.png")

var selected_class := 0
var slot_classes: Array[int] = [HeroUnit.Cls.MAGE, HeroUnit.Cls.WARRIOR, HeroUnit.Cls.FAIRY]
var card_images: Array[TextureRect] = []
var card_names: Array[Label] = []
var cards: Array[Control] = []
var avatar: TextureRect
var profile_name_label: Label
var profile_level_label: Label
var experience_bar: ProgressBar
var font: FontFile
var shard_shop_overlay: ColorRect
var shop_panel: PanelContainer
var info_dialog: AcceptDialog
var shard_amount_label: Label
var lobby_logo: TextureRect
var wing_buttons: Dictionary = {}
var wing_cards: Array[PanelContainer] = []


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and lobby_logo != null:
		_layout_lobby_logo()


func _ready() -> void:
	randomize()
	font = UI_FONT
	selected_class = _load_selection()
	get_tree().set_meta("selected_class", selected_class)
	_build_background()
	_build_header()
	_build_player_profile()
	_build_shard_shop_button()
	_build_hero_cards()
	_build_actions()
	_build_shard_shop()
	_refresh_wing_shop()
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

	var top_rule := ColorRect.new()
	top_rule.name = "TopAccent"
	top_rule.anchor_left = 0.36
	top_rule.anchor_top = 0.235
	top_rule.anchor_right = 0.64
	top_rule.anchor_bottom = 0.237
	top_rule.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.48)
	top_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_rule)


func _build_header() -> void:
	lobby_logo = TextureRect.new()
	lobby_logo.name = "LobbyLogo"
	lobby_logo.texture = LOBBY_LOGO
	lobby_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lobby_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lobby_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lobby_logo.anchor_left = 0.5
	lobby_logo.anchor_right = 0.5
	lobby_logo.anchor_top = 0.0
	lobby_logo.anchor_bottom = 0.0
	add_child(lobby_logo)
	_layout_lobby_logo()


func _layout_lobby_logo() -> void:
	if lobby_logo == null or lobby_logo.texture == null:
		return
	var viewport_size := get_viewport_rect().size
	var card_top := viewport_size.y * 0.5 - 178.0
	var available_height := maxf(0.0, card_top - 16.0)
	var aspect_ratio := lobby_logo.texture.get_size().x / maxf(1.0, lobby_logo.texture.get_size().y)
	var display_height := minf(available_height, minf(200.0, viewport_size.y * 0.44))
	var display_width := minf(500.0, minf(viewport_size.x * 0.9, display_height * aspect_ratio))
	display_height = display_width / aspect_ratio
	lobby_logo.offset_left = -display_width * 0.5
	lobby_logo.offset_top = 8.0
	lobby_logo.offset_right = display_width * 0.5
	lobby_logo.offset_bottom = 8.0 + display_height


func _build_player_profile() -> void:
	var profile_button := Button.new()
	profile_button.name = "PlayerProfile"
	profile_button.anchor_left = 0.02
	profile_button.anchor_top = 0.025
	profile_button.anchor_right = 0.29
	profile_button.anchor_bottom = 0.16
	profile_button.focus_mode = Control.FOCUS_NONE
	profile_button.add_theme_stylebox_override("normal", _action_style(false, false))
	profile_button.add_theme_stylebox_override("hover", _action_style(false, true))
	profile_button.add_theme_stylebox_override("pressed", _action_style(false, true))
	profile_button.pressed.connect(_show_info.bind("Меню Игрока (В разработке)"))
	add_child(profile_button)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 13)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	profile_button.add_child(row)

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
	profile_name_label = _make_label("Игрок", 18, PALE)
	profile_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(profile_name_label)
	profile_level_label = _make_label("Уровень 1", 13, Color(0.7, 0.75, 0.84))
	profile_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(profile_level_label)
	experience_bar = ProgressBar.new()
	experience_bar.name = "ExperienceBar"
	experience_bar.custom_minimum_size = Vector2(0, 10)
	experience_bar.min_value = 0
	experience_bar.max_value = 100
	experience_bar.value = 0
	experience_bar.show_percentage = false
	var experience_bg := StyleBoxFlat.new()
	experience_bg.bg_color = Color(0.08, 0.09, 0.13)
	experience_bg.set_corner_radius_all(5)
	var experience_fill := StyleBoxFlat.new()
	experience_fill.bg_color = Color(0.46, 0.74, 1.0)
	experience_fill.set_corner_radius_all(5)
	experience_bar.add_theme_stylebox_override("background", experience_bg)
	experience_bar.add_theme_stylebox_override("fill", experience_fill)
	info.add_child(experience_bar)


func _build_shard_shop_button() -> void:
	var button := Button.new()
	button.name = "ShardShopButton"
	button.anchor_left = 0.77
	button.anchor_top = 0.025
	button.anchor_right = 0.98
	button.anchor_bottom = 0.14
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _action_style(false, false))
	button.add_theme_stylebox_override("hover", _action_style(false, true))
	button.add_theme_stylebox_override("pressed", _action_style(false, true))
	button.pressed.connect(_open_shard_shop)
	add_child(button)

	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 0)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	shard_amount_label = _make_label("Осколки: %d" % MetaProgression.sky_shards, 17, Color(0.43, 0.84, 1.0))
	content.add_child(shard_amount_label)
	content.add_child(_make_label("Магазин", 12, Color(0.72, 0.77, 0.86)))


func _build_shard_shop() -> void:
	shard_shop_overlay = ColorRect.new()
	shard_shop_overlay.name = "ShardShopOverlay"
	shard_shop_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shard_shop_overlay.color = Color(0.005, 0.008, 0.018, 0.84)
	shard_shop_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	shard_shop_overlay.visible = false
	shard_shop_overlay.z_index = 20
	add_child(shard_shop_overlay)

	shop_panel = PanelContainer.new()
	shop_panel.name = "ShardShopPanel"
	shop_panel.anchor_left = 0.11
	shop_panel.anchor_top = 0.09
	shop_panel.anchor_right = 0.89
	shop_panel.anchor_bottom = 0.91
	shop_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.78, 0.62, 0.32), Color(0.035, 0.045, 0.07, 0.98)))
	shard_shop_overlay.add_child(shop_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	shop_panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	layout.add_child(header)
	var title := _make_label("Магазин осколков неба", 24, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(title)
	var shard_button := _make_action_button("Купить осколки небес", false)
	shard_button.custom_minimum_size = Vector2(250, 44)
	shard_button.add_theme_font_size_override("font_size", 16)
	shard_button.pressed.connect(_show_info.bind("Покупка осколков будет доступна позже."))
	header.add_child(shard_button)
	var close_button := _make_action_button("×", false)
	close_button.custom_minimum_size = Vector2(44, 44)
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.pressed.connect(_close_shard_shop)
	header.add_child(close_button)

	layout.add_child(_make_label("Крылья", 16, PALE))

	var grid := GridContainer.new()
	grid.name = "WingGrid"
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	layout.add_child(grid)
	_build_wing_card(grid, 1, "Белые крылья", "Ур. 1", 50, Color(0.87, 0.91, 1.0))
	_build_wing_card(grid, 2, "Черные крылья", "Ур. 2", 500, Color(0.16, 0.18, 0.24))
	_build_wing_card(grid, 3, "Багровые крылья", "Ур. 3", 1500, Color(0.62, 0.12, 0.2))
	_build_wing_card(grid, 4, "Золотые крылья", "Ур. 4", 3000, Color(0.95, 0.68, 0.18))

	info_dialog = AcceptDialog.new()
	info_dialog.title = "Осколки неба"
	info_dialog.dialog_text = ""
	add_child(info_dialog)


func _build_wing_card(grid: GridContainer, wing_id: int, wing_name: String, level: String, price: int, swatch_color: Color) -> void:
	var card := PanelContainer.new()
	card.name = "WingCard%d" % wing_id
	card.custom_minimum_size = Vector2(0, 190)
	card.add_theme_stylebox_override("panel", _panel_style(Color(0.38, 0.46, 0.62, 0.8), Color(0.055, 0.07, 0.105, 0.98)))
	grid.add_child(card)
	wing_cards.append(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	card.add_child(content)
	var preview_frame := CenterContainer.new()
	preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(preview_frame)
	var preview := ColorRect.new()
	preview.name = "WingPlaceholder"
	preview.custom_minimum_size = Vector2(78, 78)
	preview.color = swatch_color
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_frame.add_child(preview)
	content.add_child(_make_label("%s (%s)" % [wing_name, level], 17, PALE))

	var price_row := HBoxContainer.new()
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	price_row.add_theme_constant_override("separation", 6)
	content.add_child(price_row)
	price_row.add_child(_make_label("◆", 16, Color(0.43, 0.84, 1.0)))
	price_row.add_child(_make_label("%d осколков" % price, 14, Color(0.76, 0.82, 0.92)))

	var buy_button := _make_action_button("Купить", false)
	buy_button.name = "WingButton%d" % wing_id
	buy_button.custom_minimum_size = Vector2(0, 38)
	buy_button.add_theme_font_size_override("font_size", 15)
	buy_button.pressed.connect(_on_wing_button_pressed.bind(wing_id, price))
	content.add_child(buy_button)
	wing_buttons[wing_id] = buy_button


func _open_shard_shop() -> void:
	shard_shop_overlay.visible = true


func _close_shard_shop() -> void:
	shard_shop_overlay.visible = false


func _show_info(message: String) -> void:
	if info_dialog == null:
		return
	info_dialog.dialog_text = message
	info_dialog.popup_centered()


func _on_wing_button_pressed(wing_id: int, price: int) -> void:
	if wing_id in MetaProgression.unlocked_wings:
		if MetaProgression.equip_wing(wing_id):
			_refresh_wing_shop()
		return
	if MetaProgression.buy_wing(wing_id, price):
		_refresh_wing_shop()
	else:
		_show_info("Недостаточно осколков для покупки.")


func _refresh_wing_shop() -> void:
	if shard_amount_label != null:
		shard_amount_label.text = "Осколки: %d" % MetaProgression.sky_shards
	for wing_id in range(1, 5):
		if not wing_buttons.has(wing_id) or wing_cards.size() < wing_id:
			continue
		var button := wing_buttons[wing_id] as Button
		var card := wing_cards[wing_id - 1]
		var is_unlocked: bool = wing_id in MetaProgression.unlocked_wings
		var is_equipped: bool = MetaProgression.equipped_wing == wing_id
		button.text = "Надето" if is_equipped else ("Надеть" if is_unlocked else "Купить")
		button.disabled = is_equipped
		card.add_theme_stylebox_override("panel", _wing_card_style(is_equipped))


func _wing_card_style(is_equipped: bool) -> StyleBoxFlat:
	if is_equipped:
		var selected_style := _panel_style(Color(1.0, 0.82, 0.42, 1.0), Color(0.15, 0.115, 0.05, 0.98))
		selected_style.set_border_width_all(3)
		return selected_style
	return _panel_style(Color(0.38, 0.46, 0.62, 0.8), Color(0.055, 0.07, 0.105, 0.98))


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
	var play_button := _make_action_button("В БОЙ", true)
	play_button.name = "PlayButton"
	play_button.anchor_left = 0.5
	play_button.anchor_top = 1.0
	play_button.anchor_right = 0.5
	play_button.anchor_bottom = 1.0
	play_button.offset_left = -140.0
	play_button.offset_top = -82.0
	play_button.offset_right = 140.0
	play_button.offset_bottom = -26.0
	play_button.custom_minimum_size = Vector2(280.0, 56.0)
	play_button.pressed.connect(_start_battle)
	add_child(play_button)


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
	_refresh_player_profile()


func _refresh_player_profile() -> void:
	var character_key: String = ['warrior', 'mage', 'fairy'][selected_class]
	var character_level := int(MetaProgression.char_levels.get(character_key, 1))
	var character_xp := int(MetaProgression.char_xps.get(character_key, 0))
	profile_name_label.text = HERO_NAMES[selected_class]
	profile_level_label.text = 'Уровень %d' % character_level
	profile_name_label.add_theme_color_override('font_color', PALE)
	profile_level_label.add_theme_color_override('font_color', Color(0.7, 0.75, 0.84))
	profile_level_label.add_theme_color_override('font_shadow_color', Color(0.0, 0.0, 0.0, 0.7))
	profile_level_label.add_theme_constant_override('shadow_offset_x', 1)
	profile_level_label.add_theme_constant_override('shadow_offset_y', 2)
	profile_level_label.scale = Vector2.ONE
	experience_bar.max_value = character_level * 100
	experience_bar.value = character_xp
	if MetaProgression.consume_level_up_for(character_key):
		profile_level_label.add_theme_color_override('font_color', GOLD)
		profile_level_label.add_theme_color_override('font_shadow_color', Color(1.0, 0.68, 0.12, 0.95))
		profile_level_label.add_theme_constant_override('shadow_offset_x', 0)
		profile_level_label.add_theme_constant_override('shadow_offset_y', 0)
		var level_up_tween := create_tween()
		level_up_tween.tween_property(profile_level_label, 'scale', Vector2(1.16, 1.16), 0.16)
		level_up_tween.tween_property(profile_level_label, 'scale', Vector2.ONE, 0.3)


func _on_side_card_pressed(slot: int) -> void:
	selected_class = slot_classes[slot]
	_save_selection()
	_refresh_selection()


func _start_battle() -> void:
	_save_selection()
	get_tree().set_meta("selected_class", selected_class)
	get_tree().set_meta("selected_team", randi_range(0, 1))
	var error := get_tree().change_scene_to_file("res://scenes/LoadingScreen.tscn")
	if error != OK:
		push_error("Не удалось открыть экран загрузки: %s" % error_string(error))


func _make_action_button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(190, 54)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 20)
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
