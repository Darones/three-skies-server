extends Control

const HERO_ART := [
	"res://ui/portraits/warrior_portrait.png",
	"res://ui/portraits/mage_portrait.png",
	"res://ui/portraits/fairy_portrait.png",
]
const HERO_NAMES := ["Воин", "Маг", "Фея"]
const SAVE_PATH := "user://lobby.cfg"
const GOLD := Color(0.95, 0.76, 0.38)
const PALE := Color(0.9, 0.92, 0.98)
const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const LOBBY_LOGO: Texture2D = preload("res://ui/logo.png")
const UI_CLICK_SOUND: AudioStream = preload("res://assets/audio/Soundza_Game_SFX_Pack/ui_menu/menu_selection_click.wav")

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
var settings_panel: Control
var player_menu_overlay: ColorRect
var nickname_line_edit: LineEdit
var nickname_status_label: Label
var menu_hero_portrait: TextureRect
var menu_hero_name_label: Label
var menu_level_label: Label
var menu_xp_bar: ProgressBar
var menu_xp_remaining_label: Label
var menu_next_reward_label: Label
var wing_slot_cards: Array[PanelContainer] = []
var wing_slot_status_labels: Array[Label] = []
var wing_slot_equip_buttons: Array[Button] = []
var lobby_logo: TextureRect
var wing_buttons: Dictionary = {}
var wing_cards: Array[PanelContainer] = []
var ui_click_player: AudioStreamPlayer


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
	_build_player_menu()
	_refresh_wing_shop()
	_refresh_selection()
	if not MetaProgression.wing_purchase_updated.is_connected(_on_wing_purchase_updated):
		MetaProgression.wing_purchase_updated.connect(_on_wing_purchase_updated)
	if not NetworkClient.registration_completed.is_connected(_on_registration_completed):
		NetworkClient.registration_completed.connect(_on_registration_completed)
	if MetaProgression.player_id <= 0 and not MetaProgression.player_nickname.is_empty():
		MetaProgression.register_player(MetaProgression.player_nickname)
	_setup_ui_click_sound()
	_wire_ui_click_sounds(self)


func _setup_ui_click_sound() -> void:
	var tree_root := get_tree().root
	ui_click_player = tree_root.get_node_or_null("LobbyUIClickPlayer") as AudioStreamPlayer
	if ui_click_player != null:
		return
	ui_click_player = AudioStreamPlayer.new()
	ui_click_player.name = "LobbyUIClickPlayer"
	ui_click_player.stream = UI_CLICK_SOUND
	ui_click_player.bus = "Master"
	ui_click_player.volume_db = -12.0
	ui_click_player.max_polyphony = 1
	ui_click_player.process_mode = Node.PROCESS_MODE_ALWAYS
	tree_root.call_deferred("add_child", ui_click_player)


func _wire_ui_click_sounds(node: Node) -> void:
	for child in node.get_children():
		var button := child as Button
		if button != null and not button.button_down.is_connected(_play_ui_click):
			button.button_down.connect(_play_ui_click)
		_wire_ui_click_sounds(child)


func _play_ui_click() -> void:
	if ui_click_player != null and not ui_click_player.is_playing():
		ui_click_player.play()


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
	profile_button.pressed.connect(_open_player_menu)
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
	profile_name_label.add_theme_font_size_override("font_size", 27)
	profile_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(profile_name_label)
	profile_level_label = _make_label("Уровень 1", 13, Color(0.7, 0.75, 0.84))
	profile_level_label.add_theme_font_size_override("font_size", 27)
	profile_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(profile_level_label)
	experience_bar = ProgressBar.new()
	experience_bar.name = "ExperienceBar"
	experience_bar.custom_minimum_size = Vector2(0, 10)
	experience_bar.min_value = 0
	experience_bar.max_value = 1000
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
	shard_amount_label.add_theme_font_size_override("font_size", 27)
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
	var title := _make_label("Магазин небесных осколков", 24, GOLD)
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
		return
	if MetaProgression.buy_wing(wing_id, price):
		_refresh_wing_shop()
	else:
		if MetaProgression.player_id <= 0:
			_show_info("Сначала сохраните никнейм и дождитесь регистрации профиля.")
		elif MetaProgression.pending_wing_id > 0:
			_show_info("Покупка уже обрабатывается.")
		else:
			_show_info("Покупку не удалось отправить.")


func _refresh_wing_shop() -> void:
	if shard_amount_label != null:
		shard_amount_label.text = "Осколки: %d" % MetaProgression.sky_shards
	for wing_id in range(1, 5):
		if not wing_buttons.has(wing_id) or wing_cards.size() < wing_id:
			continue
		var button := wing_buttons[wing_id] as Button
		var card := wing_cards[wing_id - 1]
		var is_unlocked: bool = wing_id in MetaProgression.unlocked_wings
		var is_pending: bool = MetaProgression.pending_wing_id == wing_id
		button.text = "Покупка..." if is_pending else ("Куплено" if is_unlocked else "Купить")
		button.disabled = is_unlocked or is_pending
		card.add_theme_stylebox_override("panel", _wing_card_style(is_unlocked))


func _on_wing_purchase_updated(success: bool, _wing_id: int, _new_shards: int) -> void:
	_refresh_wing_shop()
	_refresh_player_menu()
	if not success:
		_show_info("Сервер не подтвердил покупку. Проверь баланс и подключение.")


func _wing_card_style(is_owned: bool) -> StyleBoxFlat:
	if is_owned:
		var selected_style := _panel_style(Color(1.0, 0.82, 0.42, 1.0), Color(0.15, 0.115, 0.05, 0.98))
		selected_style.set_border_width_all(3)
		return selected_style
	return _panel_style(Color(0.38, 0.46, 0.62, 0.8), Color(0.055, 0.07, 0.105, 0.98))


func _build_player_menu() -> void:
	player_menu_overlay = ColorRect.new()
	player_menu_overlay.name = "PlayerMenuOverlay"
	player_menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player_menu_overlay.color = Color(0.005, 0.008, 0.018, 0.86)
	player_menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	player_menu_overlay.visible = false
	player_menu_overlay.z_index = 30
	add_child(player_menu_overlay)

	var panel := PanelContainer.new()
	panel.name = "PlayerMenuPanel"
	panel.anchor_left = 0.045
	panel.anchor_top = 0.07
	panel.anchor_right = 0.955
	panel.anchor_bottom = 0.93
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.78, 0.62, 0.32), Color(0.035, 0.045, 0.07, 0.99)))
	player_menu_overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := _make_label("МЕНЮ ИГРОКА", 25, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := _make_action_button("×", false)
	close_button.custom_minimum_size = Vector2(46, 44)
	close_button.add_theme_font_size_override("font_size", 25)
	close_button.pressed.connect(_close_player_menu)
	header.add_child(close_button)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	layout.add_child(columns)

	var profile_panel := PanelContainer.new()
	profile_panel.name = "PlayerMenuProfile"
	profile_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	profile_panel.custom_minimum_size = Vector2(260, 0)
	profile_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.4, 0.48, 0.63, 0.8), Color(0.045, 0.055, 0.085, 0.97)))
	columns.add_child(profile_panel)
	var profile_content := VBoxContainer.new()
	profile_content.add_theme_constant_override("separation", 9)
	profile_panel.add_child(profile_content)
	var profile_title := _make_label("ПРОФИЛЬ", 19, GOLD)
	profile_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	profile_content.add_child(profile_title)
	nickname_line_edit = LineEdit.new()
	nickname_line_edit.name = "NicknameInput"
	nickname_line_edit.placeholder_text = "Никнейм (3–12 символов)"
	nickname_line_edit.max_length = 12
	nickname_line_edit.text = MetaProgression.player_nickname
	nickname_line_edit.custom_minimum_size = Vector2(0, 42)
	nickname_line_edit.add_theme_font_override("font", font)
	profile_content.add_child(nickname_line_edit)
	var save_nickname_button := _make_action_button("Сохранить", true)
	save_nickname_button.custom_minimum_size = Vector2(0, 42)
	save_nickname_button.pressed.connect(_save_player_nickname)
	profile_content.add_child(save_nickname_button)
	nickname_status_label = _make_label("", 13, Color(0.58, 0.9, 0.64))
	nickname_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	profile_content.add_child(nickname_status_label)
	var profile_divider := ColorRect.new()
	profile_divider.custom_minimum_size = Vector2(0, 1)
	profile_divider.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.32)
	profile_content.add_child(profile_divider)
	menu_level_label = _make_label("Уровень 1", 19, PALE)
	menu_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	profile_content.add_child(menu_level_label)
	menu_xp_bar = ProgressBar.new()
	menu_xp_bar.name = "PlayerMenuExperienceBar"
	menu_xp_bar.custom_minimum_size = Vector2(0, 12)
	menu_xp_bar.min_value = 0
	menu_xp_bar.max_value = 1000
	menu_xp_bar.show_percentage = false
	var xp_background := StyleBoxFlat.new()
	xp_background.bg_color = Color(0.08, 0.09, 0.13)
	xp_background.set_corner_radius_all(5)
	var xp_fill := StyleBoxFlat.new()
	xp_fill.bg_color = Color(0.46, 0.74, 1.0)
	xp_fill.set_corner_radius_all(5)
	menu_xp_bar.add_theme_stylebox_override("background", xp_background)
	menu_xp_bar.add_theme_stylebox_override("fill", xp_fill)
	profile_content.add_child(menu_xp_bar)
	menu_xp_remaining_label = _make_label("До следующего уровня: 1000 XP", 14, Color(0.76, 0.8, 0.89))
	menu_xp_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	profile_content.add_child(menu_xp_remaining_label)
	menu_next_reward_label = _make_label("Награда: 75 осколков", 14, Color(0.43, 0.84, 1.0))
	menu_next_reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	profile_content.add_child(menu_next_reward_label)

	var hero_panel := PanelContainer.new()
	hero_panel.name = "PlayerMenuHero"
	hero_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_panel.custom_minimum_size = Vector2(280, 0)
	hero_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.57, 0.48, 0.31, 0.8), Color(0.025, 0.032, 0.05, 0.98)))
	columns.add_child(hero_panel)
	var hero_content := VBoxContainer.new()
	hero_content.add_theme_constant_override("separation", 8)
	hero_panel.add_child(hero_content)
	var hero_selector := HBoxContainer.new()
	hero_selector.name = "HeroSelector"
	hero_selector.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_selector.add_theme_constant_override("separation", 8)
	hero_content.add_child(hero_selector)
	var previous_hero_button := _make_action_button("◀", false)
	previous_hero_button.name = "PreviousHeroButton"
	previous_hero_button.custom_minimum_size = Vector2(46, 40)
	previous_hero_button.add_theme_font_size_override("font_size", 19)
	previous_hero_button.pressed.connect(_cycle_selected_hero.bind(-1))
	hero_selector.add_child(previous_hero_button)
	menu_hero_name_label = _make_label("Воин", 20, PALE)
	menu_hero_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_selector.add_child(menu_hero_name_label)
	var next_hero_button := _make_action_button("▶", false)
	next_hero_button.name = "NextHeroButton"
	next_hero_button.custom_minimum_size = Vector2(46, 40)
	next_hero_button.add_theme_font_size_override("font_size", 19)
	next_hero_button.pressed.connect(_cycle_selected_hero.bind(1))
	hero_selector.add_child(next_hero_button)
	var portrait_frame := PanelContainer.new()
	portrait_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_frame.add_theme_stylebox_override("panel", _panel_style(Color(0.24, 0.27, 0.34), Color(0.01, 0.014, 0.025)))
	hero_content.add_child(portrait_frame)
	menu_hero_portrait = TextureRect.new()
	menu_hero_portrait.name = "SelectedHeroPortrait"
	menu_hero_portrait.custom_minimum_size = Vector2(0, 280)
	menu_hero_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu_hero_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	menu_hero_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	menu_hero_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_child(menu_hero_portrait)

	var wardrobe_panel := PanelContainer.new()
	wardrobe_panel.name = "PlayerMenuWardrobe"
	wardrobe_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wardrobe_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wardrobe_panel.custom_minimum_size = Vector2(280, 0)
	wardrobe_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.4, 0.48, 0.63, 0.8), Color(0.045, 0.055, 0.085, 0.97)))
	columns.add_child(wardrobe_panel)
	var wardrobe_content := VBoxContainer.new()
	wardrobe_content.add_theme_constant_override("separation", 9)
	wardrobe_panel.add_child(wardrobe_content)
	var wings_tab := _make_action_button("КРЫЛЬЯ", true)
	wings_tab.custom_minimum_size = Vector2(0, 42)
	wings_tab.disabled = true
	wardrobe_content.add_child(wings_tab)
	var wing_grid := GridContainer.new()
	wing_grid.name = "WingInventoryGrid"
	wing_grid.columns = 2
	wing_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wing_grid.add_theme_constant_override("h_separation", 8)
	wing_grid.add_theme_constant_override("v_separation", 8)
	wardrobe_content.add_child(wing_grid)
	var wing_names := ["Белые крылья", "Черные крылья", "Багровые крылья", "Золотые крылья"]
	var wing_colors := [Color(0.86, 0.9, 1.0), Color(0.18, 0.2, 0.27), Color(0.66, 0.16, 0.23), Color(0.98, 0.72, 0.18)]
	for wing_index in range(4):
		var wing_card := PanelContainer.new()
		wing_card.name = "OwnedWing%d" % (wing_index + 1)
		wing_card.custom_minimum_size = Vector2(110, 154)
		wing_card.add_theme_stylebox_override("panel", _panel_style(Color(0.34, 0.37, 0.44), Color(0.065, 0.072, 0.09, 0.92)))
		wing_grid.add_child(wing_card)
		wing_slot_cards.append(wing_card)
		var wing_content := VBoxContainer.new()
		wing_content.add_theme_constant_override("separation", 3)
		wing_card.add_child(wing_content)
		var wing_icon := ColorRect.new()
		wing_icon.name = "WingColor%d" % (wing_index + 1)
		wing_icon.custom_minimum_size = Vector2(0, 48)
		wing_icon.color = wing_colors[wing_index]
		wing_icon.modulate.a = 0.35
		wing_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wing_content.add_child(wing_icon)
		wing_content.add_child(_make_label(wing_names[wing_index], 12, PALE))
		wing_content.add_child(_make_label("Ур. %d" % (wing_index + 1), 14, PALE))
		var status := _make_label("🔒 Закрыто", 12, Color(0.62, 0.65, 0.72))
		wing_content.add_child(status)
		wing_slot_status_labels.append(status)
		var equip_button := _make_action_button("Надеть", false)
		equip_button.name = "EquipWing%d" % (wing_index + 1)
		equip_button.custom_minimum_size = Vector2(0, 30)
		equip_button.add_theme_font_size_override("font_size", 13)
		equip_button.pressed.connect(_on_wardrobe_wing_pressed.bind(wing_index + 1))
		wing_content.add_child(equip_button)
		wing_slot_equip_buttons.append(equip_button)
	_refresh_player_menu()


func _open_player_menu() -> void:
	_refresh_player_menu()
	player_menu_overlay.visible = true


func _close_player_menu() -> void:
	player_menu_overlay.visible = false


func _save_player_nickname() -> void:
	var nickname := nickname_line_edit.text.strip_edges()
	if nickname.length() < 3 or nickname.length() > 12:
		nickname_status_label.text = "Введите от 3 до 12 символов."
		nickname_status_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.42))
		return
	MetaProgression.player_nickname = nickname
	MetaProgression.save_game()
	if MetaProgression.player_id <= 0:
		MetaProgression.register_player(nickname)
	nickname_line_edit.text = nickname
	nickname_status_label.text = "Сохраняем профиль на сервере..." if MetaProgression.player_id <= 0 else "Никнейм сохранен."
	nickname_status_label.add_theme_color_override("font_color", Color(0.58, 0.9, 0.64))


func _on_registration_completed(success: bool, registered_player_id: int) -> void:
	if nickname_status_label == null:
		return
	if success and registered_player_id > 0:
		nickname_status_label.text = "Профиль подключен."
		nickname_status_label.add_theme_color_override("font_color", Color(0.58, 0.9, 0.64))
	else:
		nickname_status_label.text = "Регистрация не удалась: сервер недоступен или ник занят."
		nickname_status_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.42))


func _refresh_player_menu() -> void:
	if menu_hero_portrait == null:
		return
	var character_key: String = ["warrior", "mage", "fairy"][selected_class]
	var character_equipped_wing := MetaProgression.get_equipped_wing(character_key)
	var character_level := int(MetaProgression.char_levels.get(character_key, 1))
	var character_xp := int(MetaProgression.char_xps.get(character_key, 0))
	menu_hero_name_label.text = HERO_NAMES[selected_class]
	menu_hero_portrait.texture = load(HERO_ART[selected_class]) as Texture2D
	menu_level_label.text = "Уровень %d — %s" % [character_level, HERO_NAMES[selected_class]]
	var max_xp := MetaProgression.get_xp_for_next_level(character_key)
	menu_xp_bar.max_value = max_xp
	menu_xp_bar.value = character_xp
	if character_level >= MetaProgression.MAX_CHARACTER_LEVEL:
		menu_xp_remaining_label.text = "До следующего уровня: максимальный уровень"
		menu_next_reward_label.text = "Награда: —"
	else:
		menu_xp_remaining_label.text = "До следующего уровня: %d XP" % maxi(0, max_xp - character_xp)
		menu_next_reward_label.text = "Награда: %d осколков" % MetaProgression.get_shard_reward_for_level(character_level + 1)
	for wing_index in range(wing_slot_cards.size()):
		var wing_id := wing_index + 1
		var unlocked := wing_id in MetaProgression.unlocked_wings
		var status := wing_slot_status_labels[wing_index]
		var card := wing_slot_cards[wing_index]
		var icon := card.find_child("WingColor%d" % wing_id, true, false) as ColorRect
		var is_equipped := character_equipped_wing == wing_id
		status.text = "Надето" if is_equipped else ("Куплено" if unlocked else "🔒 Закрыто")
		status.add_theme_color_override("font_color", Color(0.95, 0.8, 0.42) if unlocked else Color(0.62, 0.65, 0.72))
		if icon != null:
			icon.modulate.a = 1.0 if unlocked else 0.35
		card.add_theme_stylebox_override("panel", _panel_style(Color(0.83, 0.67, 0.34) if unlocked else Color(0.34, 0.37, 0.44), Color(0.14, 0.11, 0.06, 0.98) if unlocked else Color(0.065, 0.072, 0.09, 0.92)))
		var equip_button := wing_slot_equip_buttons[wing_index]
		equip_button.visible = unlocked
		equip_button.text = "Снять" if is_equipped else "Надеть"


func _cycle_selected_hero(direction: int) -> void:
	selected_class = wrapi(selected_class + direction, 0, HERO_NAMES.size())
	_save_selection()
	_refresh_selection()


func _on_wardrobe_wing_pressed(wing_id: int) -> void:
	var character_key: String = ["warrior", "mage", "fairy"][selected_class]
	var equipped_wing_id := MetaProgression.get_equipped_wing(character_key)
	var target_wing_id := 0 if equipped_wing_id == wing_id else wing_id
	if MetaProgression.equip_wing(target_wing_id, character_key):
		_refresh_player_menu()


func _build_hero_cards() -> void:
	_build_hero_card(0, false)
	_build_hero_card(1, true)
	_build_hero_card(2, false)


func _build_hero_card(slot: int, is_center: bool) -> void:
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.clip_contents = true
	if not is_center:
		card.pressed.connect(_on_side_card_pressed.bind(slot))

	card.name = "HeroCard%d" % slot
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.anchor_left = 0.5
	card.anchor_top = 0.5
	card.anchor_right = 0.5
	card.anchor_bottom = 0.5
	var card_width := 300.0 if is_center else 192.0
	var card_height := 400.0 if is_center else 256.0
	card.custom_minimum_size = Vector2(card_width, card_height)
	if is_center:
		card.offset_left = -150.0
		card.offset_top = -154.0
		card.offset_right = 150.0
		card.offset_bottom = 246.0
		card.z_index = 2
	else:
		var side_offset := -352.0 if slot == 0 else 160.0
		card.offset_left = side_offset
		card.offset_top = -108.0
		card.offset_right = side_offset + 192.0
		card.offset_bottom = 148.0
		card.z_index = 1
	if is_center:
		card.add_theme_stylebox_override("normal", _card_style(true, false))
		card.add_theme_stylebox_override("hover", _card_style(true, false))
		card.add_theme_stylebox_override("pressed", _card_style(true, false))
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		card.add_theme_stylebox_override("normal", _card_style(false, false))
		card.add_theme_stylebox_override("hover", _card_style(false, true))
		card.add_theme_stylebox_override("pressed", _card_style(false, true))
	add_child(card)

	var image := TextureRect.new()
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(image)

	var title_backing := ColorRect.new()
	title_backing.color = Color(0.02, 0.028, 0.05, 0.84)
	title_backing.anchor_top = 1.0
	title_backing.anchor_right = 1.0
	title_backing.anchor_bottom = 1.0
	title_backing.offset_left = 2.0
	title_backing.offset_top = -46.0 if is_center else -38.0
	title_backing.offset_right = -2.0
	title_backing.offset_bottom = -2.0
	title_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(title_backing)

	var name_label := _make_label("", 27 if is_center else 19, PALE)
	name_label.name = "HeroName%d" % slot
	name_label.anchor_top = 1.0
	name_label.anchor_right = 1.0
	name_label.anchor_bottom = 1.0
	name_label.offset_left = 8.0
	name_label.offset_top = -44.0 if is_center else -36.0
	name_label.offset_right = -8.0
	name_label.offset_bottom = -4.0
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_label)
	cards.append(card)
	card_images.append(image)
	card_names.append(name_label)


func _build_actions() -> void:
	var play_button := _make_action_button("В БОЙ", true)
	play_button.name = "PlayButton"
	play_button.anchor_left = 1.0
	play_button.anchor_top = 1.0
	play_button.anchor_right = 1.0
	play_button.anchor_bottom = 1.0
	play_button.offset_left = -325.0
	play_button.offset_top = -101.0
	play_button.offset_right = -45.0
	play_button.offset_bottom = -45.0
	play_button.custom_minimum_size = Vector2(280.0, 56.0)
	play_button.pressed.connect(_start_battle)
	add_child(play_button)

	var settings_button := _make_action_button("", false)
	settings_button.name = "SettingsButton"
	settings_button.anchor_left = 0.0
	settings_button.anchor_top = 1.0
	settings_button.anchor_right = 0.0
	settings_button.anchor_bottom = 1.0
	settings_button.offset_left = 45.0
	settings_button.offset_top = -109.0
	settings_button.offset_right = 109.0
	settings_button.offset_bottom = -45.0
	settings_button.custom_minimum_size = Vector2(64.0, 64.0)
	settings_button.add_theme_stylebox_override("normal", _gear_button_style(false))
	settings_button.add_theme_stylebox_override("hover", _gear_button_style(true))
	settings_button.add_theme_stylebox_override("pressed", _gear_button_style(true))
	settings_button.pressed.connect(_open_settings)
	var gear_icon := Label.new()
	gear_icon.name = "GearIcon"
	gear_icon.text = "⚙"
	gear_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gear_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gear_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gear_icon.add_theme_font_override("font", font)
	gear_icon.add_theme_font_size_override("font_size", 28)
	gear_icon.add_theme_color_override("font_color", PALE)
	gear_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_button.add_child(gear_icon)
	add_child(settings_button)

	settings_panel = preload("res://scripts/settings_panel.gd").new() as Control
	settings_panel.name = "LobbySettingsPanel"
	settings_panel.visible = false
	settings_panel.z_index = 100
	settings_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	settings_panel.connect("back_requested", _close_settings)
	add_child(settings_panel)


func _gear_button_style(hovered: bool) -> StyleBoxFlat:
	var style := _action_style(false, hovered)
	style.set_corner_radius_all(32)
	return style


func _open_settings() -> void:
	settings_panel.visible = true


func _close_settings() -> void:
	settings_panel.visible = false


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
	_refresh_player_menu()


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
	experience_bar.max_value = MetaProgression.get_xp_for_next_level(character_key)
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
	var selected_team := randi_range(0, 1)
	get_tree().set_meta("selected_team", selected_team)
	var connection_error: Error = NetworkClient.connect_and_join(selected_class)
	get_tree().set_meta("matchmaking_no_network", connection_error != OK)
	get_tree().set_meta("matchmaking_message", "Сервер недоступен, игра с ботами" if connection_error != OK else "")
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
