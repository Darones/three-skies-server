extends Control

const HERO_ART := [
	"res://ui/portraits/warrior_portrait.png",
	"res://ui/portraits/mage_portrait.png",
	"res://ui/portraits/fairy_portrait.png",
]
const HERO_NAMES := ["Воин", "Маг", "Фея"]
const CLASS_FRAME_COLORS := {
	0: Color(0.95, 0.78, 0.36),
	1: Color(0.45, 0.78, 1.0),
	2: Color(0.55, 0.9, 0.5),
}
const SKILL_ICONS := [
	[
		preload("res://assets/ui/icon/128/002.png"),
		preload("res://assets/ui/icon/128/004.png"),
		preload("res://assets/ui/icon/128/012.png"),
	],
	[
		preload("res://assets/ui/icon/128/011.png"),
		preload("res://assets/ui/icon/128/008.png"),
		preload("res://assets/ui/icon/128/007.png"),
	],
	[
		preload("res://assets/ui/icon/128/001.png"),
		preload("res://assets/ui/icon/128/010.png"),
		preload("res://assets/ui/icon/128/005.png"),
	],
]
const SKILL_DESCRIPTIONS := [
	[
		"Рывок к цели и удар.",
		"Усиливает следующий удар.",
		"Урон и страх вокруг себя.",
	],
	[
		"Обездвиживает цель.",
		"Лечит союзников рядом.",
		"Молнии бьют по области.",
	],
	[
		"Стрела оглушает цель.",
		"Заряженный выстрел с критом.",
		"Бафф команде, взрыв и замедление.",
	],
]
const SAVE_PATH := "user://lobby.cfg"
const TUTORIAL_SAVE_PATH := "user://tutorial.cfg"
const GOLD := Color(0.95, 0.76, 0.38)
const PALE := Color(0.9, 0.92, 0.98)
const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const LOBBY_LOGO: Texture2D = preload("res://ui/logo.png")
const UI_CLICK_SOUND: AudioStream = preload("res://assets/audio/Soundza_Game_SFX_Pack/ui_menu/menu_selection_click.wav")
const SHARD_TOPUP_SCENE := preload("res://scenes/ShardTopupPanel.tscn")
const SHARD_ICON: Texture2D = preload("res://ui/icons/sky_shard.png")
const NICKNAME_CHANGE_COST := 100
const SHOP_WING_ICON: Texture2D = preload("res://assets/ui/generated_wing_shop_icon/img-6adcd384-a1c6-4d03-ab8f-2885c6220fd5-1794244737264-0_1794244737264_rm3v6na1.webp")
const SHOP_STAFF_ICON: Texture2D = preload("res://ui/icons/weapon_staff.png")
const SHOP_BOW_ICON: Texture2D = preload("res://ui/icons/weapon_bow.png")
const SHOP_SWORD_ICON: Texture2D = preload("res://ui/icons/weapon_sword.png")

var selected_class := 0
var slot_classes: Array[int] = [HeroUnit.Cls.MAGE, HeroUnit.Cls.WARRIOR, HeroUnit.Cls.FAIRY]
var card_images: Array[TextureRect] = []
var card_names: Array[Label] = []
var card_footers: Array[Panel] = []
var card_portrait_materials: Array[ShaderMaterial] = []
var cards: Array[Control] = []
var avatar: TextureRect
var profile_name_label: Label
var profile_level_label: Label
var experience_bar: ProgressBar
var font: FontFile
var shard_shop_overlay: ColorRect
var shop_panel: PanelContainer
var topup_panel: PanelContainer
var info_dialog: AcceptDialog
var shard_amount_label: Label
var play_button: Button
var settings_panel: Control
var player_menu_overlay: ColorRect
var nickname_line_edit: LineEdit
var nickname_status_label: Label
var nickname_cost_label: Label
var menu_shard_label: Label
var rename_confirm_overlay: ColorRect
var rename_confirm_label: Label
var pending_rename_nickname := ""
var nickname_input_synced := ""
var report_overlay: ColorRect
var report_nickname_edit: LineEdit
var report_reason_option: OptionButton
var report_status_label: Label
var report_submit_button: Button
var menu_hero_portrait: TextureRect
var menu_hero_name_label: Label
var menu_level_label: Label
var menu_xp_bar: ProgressBar
var menu_xp_remaining_label: Label
var menu_next_reward_label: Label
var lobby_logo: TextureRect
var wing_buttons: Dictionary = {}
var wing_cards: Array[PanelContainer] = []
var weapon_buttons: Dictionary = {}
var weapon_cards: Dictionary = {}
var weapon_status_labels: Array[Label] = []
var ui_click_player: AudioStreamPlayer
var tutorial_button: Button
var pending_nickname := ""
var guest_attempts := 0
var skills_info_box: VBoxContainer
var stats_box: VBoxContainer
var stats_tab := "all"
var stats_tab_buttons: Dictionary = {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and lobby_logo != null:
		_layout_lobby_logo()


func _ready() -> void:
	randomize()
	font = UI_FONT
	if MetaProgression.player_nickname.is_empty():
		MetaProgression.player_nickname = _load_player_nickname()
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
	_build_rename_confirm()
	_build_report_form()
	_refresh_wing_shop()
	_refresh_weapon_shop()
	_refresh_selection()
	if not MetaProgression.purchase_updated.is_connected(_on_purchase_updated):
		MetaProgression.purchase_updated.connect(_on_purchase_updated)
	if not MetaProgression.profile_updated.is_connected(_on_profile_updated):
		MetaProgression.profile_updated.connect(_on_profile_updated)
	if not NetworkClient.registration_completed.is_connected(_on_registration_completed):
		NetworkClient.registration_completed.connect(_on_registration_completed)
	if not NetworkManager.connection_succeeded.is_connected(_on_network_connected):
		NetworkManager.connection_succeeded.connect(_on_network_connected)
	if not NetworkManager.connection_failed.is_connected(_on_network_failed):
		NetworkManager.connection_failed.connect(_on_network_failed)
	if not NetworkManager.match_started.is_connected(_on_network_match_started):
		NetworkManager.match_started.connect(_on_network_match_started)
	if not NetworkManager.disconnected.is_connected(_on_network_disconnected):
		NetworkManager.disconnected.connect(_on_network_disconnected)
	if not NetworkClient.rename_completed.is_connected(_on_rename_completed):
		NetworkClient.rename_completed.connect(_on_rename_completed)
	if not NetworkClient.report_completed.is_connected(_on_report_completed):
		NetworkClient.report_completed.connect(_on_report_completed)
	if MetaProgression.player_id <= 0:
		var saved_player_id := _load_player_id()
		if saved_player_id > 0:
			MetaProgression.load_profile(saved_player_id)
		elif not MetaProgression.player_nickname.is_empty():
			MetaProgression.register_player(MetaProgression.player_nickname)
		else:
			MetaProgression.player_nickname = _generate_guest_nickname()
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
	config.load(SAVE_PATH)
	config.set_value("profile", "selected_class", selected_class)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_error("Не удалось сохранить выбор героя: %s" % error_string(error))
	get_tree().set_meta("selected_class", selected_class)


func _build_background() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.035, 0.075, 0.135))
	gradient.set_color(1, Color(0.006, 0.01, 0.022))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 8
	texture.height = 256
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	var background := TextureRect.new()
	background.name = "LobbyBackground"
	background.texture = texture
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var glow_gradient := Gradient.new()
	glow_gradient.set_color(0, Color(0.16, 0.36, 0.58, 0.5))
	glow_gradient.set_color(1, Color(0.16, 0.36, 0.58, 0.0))
	var glow_texture := GradientTexture2D.new()
	glow_texture.gradient = glow_gradient
	glow_texture.width = 512
	glow_texture.height = 512
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(0.5, 0.0)
	var glow := TextureRect.new()
	glow.name = "LobbyGlow"
	glow.texture = glow_texture
	glow.anchor_left = 0.5
	glow.anchor_right = 0.5
	glow.anchor_top = 0.5
	glow.anchor_bottom = 0.5
	glow.offset_left = -520.0
	glow.offset_right = 520.0
	glow.offset_top = -360.0
	glow.offset_bottom = 360.0
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

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
	var card_top := viewport_size.y * 0.5 - 173.0
	var available_height := maxf(0.0, card_top - 16.0)
	var aspect_ratio := lobby_logo.texture.get_size().x / maxf(1.0, lobby_logo.texture.get_size().y)
	var display_height := minf(available_height, minf(200.0, viewport_size.y * 0.44))
	var display_width := minf(500.0, minf(viewport_size.x * 0.9, display_height * aspect_ratio))
	display_height = display_width / aspect_ratio
	lobby_logo.visible = true
	lobby_logo.anchor_left = 0.5
	lobby_logo.anchor_right = 0.5
	lobby_logo.anchor_top = 0.0
	lobby_logo.anchor_bottom = 0.0
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
	profile_name_label = _make_label("Игрок", 24, PALE)
	profile_name_label.add_theme_font_size_override("font_size", 24)
	profile_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	profile_name_label.clip_text = true
	info.add_child(profile_name_label)
	profile_level_label = _make_label("Уровень 1", 16, Color(0.7, 0.75, 0.84))
	profile_level_label.add_theme_font_size_override("font_size", 16)
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
	shard_button.name = "TopupButton"
	shard_button.custom_minimum_size = Vector2(250, 44)
	shard_button.add_theme_font_size_override("font_size", 16)
	shard_button.pressed.connect(_open_topup_panel)
	header.add_child(shard_button)
	var close_button := _make_action_button("×", false)
	close_button.custom_minimum_size = Vector2(44, 44)
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.pressed.connect(_close_shard_shop)
	header.add_child(close_button)

	layout.add_child(_make_label("Крылья и оружие", 16, PALE))

	var grid := GridContainer.new()
	grid.name = "WingGrid"
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	layout.add_child(grid)
	_build_wing_card(grid, 1, "Белые крылья", "Ур. 1", 50)
	_build_weapon_placeholder(grid, "Посох", 0, 0, SHOP_STAFF_ICON)
	_build_weapon_placeholder(grid, "Лук", 0, 0, SHOP_BOW_ICON)
	_build_weapon_placeholder(grid, "Меч", 1, 500, SHOP_SWORD_ICON)

	_build_topup_panel()

	info_dialog = AcceptDialog.new()
	info_dialog.title = "Осколки неба"
	info_dialog.dialog_text = ""
	add_child(info_dialog)


func _build_wing_card(grid: GridContainer, wing_id: int, wing_name: String, level: String, price: int) -> void:
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
	var preview := TextureRect.new()
	preview.name = "WingIcon"
	preview.texture = SHOP_WING_ICON
	preview.custom_minimum_size = Vector2(84, 84)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview_material := ShaderMaterial.new()
	preview_material.shader = preload("res://shaders/ability_icon_mask.gdshader")
	preview_material.set_shader_parameter("corner_radius", 0.5)
	preview.material = preview_material
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


func _build_weapon_placeholder(grid: GridContainer, weapon_name: String, weapon_id: int = 0, price: int = 0, icon_texture: Texture2D = null) -> void:
	var card := PanelContainer.new()
	card.name = "WeaponPlaceholder%d" % grid.get_child_count()
	card.custom_minimum_size = Vector2(0, 190)
	card.add_theme_stylebox_override("panel", _panel_style(Color(0.38, 0.46, 0.62, 0.8), Color(0.055, 0.07, 0.105, 0.98)))
	grid.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	card.add_child(content)
	var placeholder_frame := CenterContainer.new()
	placeholder_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(placeholder_frame)
	var icon := TextureRect.new()
	icon.name = "WeaponIcon"
	icon.texture = icon_texture
	icon.custom_minimum_size = Vector2(84, 84)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	placeholder_frame.add_child(icon)
	content.add_child(_make_label(weapon_name, 18, PALE))
	if weapon_id > 0:
		content.add_child(_make_label("Легендарный меч", 12, Color(0.7, 0.76, 0.86)))
		content.add_child(_make_label("◆ %d осколков" % price, 14, Color(0.76, 0.82, 0.92)))
		var buy_button := _make_action_button("Купить", false)
		buy_button.name = "WeaponButton%d" % weapon_id
		buy_button.custom_minimum_size = Vector2(0, 38)
		buy_button.add_theme_font_size_override("font_size", 15)
		buy_button.pressed.connect(_on_weapon_button_pressed.bind(weapon_id, price))
		content.add_child(buy_button)
		weapon_buttons[weapon_id] = buy_button
		weapon_cards[weapon_id] = card
	else:
		content.add_child(_make_label("Скоро в продаже", 12, Color(0.7, 0.76, 0.86)))


func _build_topup_panel() -> void:
	topup_panel = SHARD_TOPUP_SCENE.instantiate() as PanelContainer
	topup_panel.name = "ShardTopupPanel"
	topup_panel.visible = false
	topup_panel.z_index = 2
	topup_panel.set_anchors_preset(Control.PRESET_CENTER)
	topup_panel.offset_left = -250.0
	topup_panel.offset_right = 250.0
	topup_panel.offset_top = -180.0
	topup_panel.offset_bottom = 180.0
	shard_shop_overlay.add_child(topup_panel)


func _open_topup_panel() -> void:
	if topup_panel != null:
		topup_panel.visible = true


func _close_topup_panel() -> void:
	if topup_panel != null:
		topup_panel.visible = false


func _open_shard_shop() -> void:
	shard_shop_overlay.visible = true
	_close_topup_panel()


func _close_shard_shop() -> void:
	_close_topup_panel()
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
		elif not MetaProgression.profile_loaded:
			MetaProgression.load_profile(MetaProgression.player_id)
			_show_info("Загружаем профиль и баланс с сервера.")
		elif MetaProgression.pending_purchase_type != "":
			_show_info("Покупка уже обрабатывается.")
		else:
			_show_info("Покупку не удалось отправить.")


func _refresh_wing_shop() -> void:
	if shard_amount_label != null:
		shard_amount_label.text = "Осколки: %d" % MetaProgression.sky_shards
	for wing_id in range(1, 2):
		if not wing_buttons.has(wing_id) or wing_cards.size() < wing_id:
			continue
		var button := wing_buttons[wing_id] as Button
		var card := wing_cards[wing_id - 1]
		var is_unlocked: bool = wing_id in MetaProgression.unlocked_wings
		var is_pending: bool = MetaProgression.is_purchase_pending("wing", wing_id)
		button.text = "Покупка..." if is_pending else ("Куплено" if is_unlocked else "Купить")
		button.disabled = is_unlocked or is_pending
		card.add_theme_stylebox_override("panel", _wing_card_style(is_unlocked))


func _on_weapon_button_pressed(weapon_id: int, price: int) -> void:
	if weapon_id in MetaProgression.unlocked_weapons:
		return
	if MetaProgression.buy_weapon(weapon_id, price):
		_refresh_weapon_shop()
	else:
		if MetaProgression.player_id <= 0:
			_show_info("Сначала сохраните никнейм и дождитесь регистрации профиля.")
		elif not MetaProgression.profile_loaded:
			MetaProgression.load_profile(MetaProgression.player_id)
			_show_info("Загружаем профиль и баланс с сервера.")
		elif MetaProgression.pending_purchase_type != "":
			_show_info("Покупка уже обрабатывается.")
		else:
			_show_info("Покупку не удалось отправить.")


func _refresh_weapon_shop() -> void:
	for weapon_id in weapon_buttons.keys():
		var button := weapon_buttons[weapon_id] as Button
		var card := weapon_cards[weapon_id] as PanelContainer
		var is_unlocked: bool = weapon_id in MetaProgression.unlocked_weapons
		var is_pending: bool = MetaProgression.is_purchase_pending("weapon", weapon_id)
		button.text = "Покупка..." if is_pending else ("Куплено" if is_unlocked else "Купить")
		button.disabled = is_unlocked or is_pending
		card.add_theme_stylebox_override("panel", _wing_card_style(is_unlocked))
	for index in range(weapon_status_labels.size()):
		weapon_status_labels[index].text = "Куплено" if index == 0 and 1 in MetaProgression.unlocked_weapons else ("Скоро" if index > 0 else "В магазине")


func _on_purchase_updated(success: bool, _purchase_type: String, _item_id: int, _new_shards: int) -> void:
	_refresh_wing_shop()
	_refresh_weapon_shop()
	_refresh_player_menu()
	if not success:
		_show_info("Сервер не подтвердил покупку. Проверь баланс и подключение.")


func _on_profile_updated() -> void:
	if MetaProgression.player_id > 0 and not MetaProgression.player_nickname.is_empty():
		_save_player_id(MetaProgression.player_id)
	_refresh_wing_shop()
	_refresh_weapon_shop()
	_refresh_player_profile()
	_refresh_player_menu()


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
	player_menu_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var report_button := _make_action_button("Пожаловаться", false)
	report_button.name = "ReportPlayerButton"
	report_button.custom_minimum_size = Vector2(150, 44)
	report_button.add_theme_font_size_override("font_size", 14)
	report_button.pressed.connect(_open_report_form)
	header.add_child(report_button)
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
	var nickname_row := HBoxContainer.new()
	nickname_row.add_theme_constant_override("separation", 6)
	profile_content.add_child(nickname_row)
	nickname_line_edit = LineEdit.new()
	nickname_line_edit.name = "NicknameInput"
	nickname_line_edit.placeholder_text = "Никнейм (3–12 символов)"
	nickname_line_edit.max_length = 12
	nickname_line_edit.text = MetaProgression.player_nickname
	nickname_input_synced = MetaProgression.player_nickname
	nickname_line_edit.custom_minimum_size = Vector2(0, 42)
	nickname_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nickname_line_edit.mouse_filter = Control.MOUSE_FILTER_STOP
	nickname_line_edit.focus_mode = Control.FOCUS_ALL
	nickname_line_edit.caret_blink = true
	nickname_line_edit.add_theme_font_override("font", font)
	nickname_row.add_child(nickname_line_edit)
	var save_nickname_button := _make_action_button("✓", true)
	save_nickname_button.name = "NicknameCheck"
	save_nickname_button.custom_minimum_size = Vector2(42, 42)
	save_nickname_button.add_theme_font_size_override("font_size", 22)
	save_nickname_button.tooltip_text = "Сохранить ник"
	save_nickname_button.pressed.connect(_save_player_nickname)
	nickname_row.add_child(save_nickname_button)
	nickname_status_label = _make_label("", 15, Color(0.58, 0.9, 0.64))
	nickname_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	profile_content.add_child(nickname_status_label)
	var nickname_cost_row := HBoxContainer.new()
	nickname_cost_row.add_theme_constant_override("separation", 6)
	profile_content.add_child(nickname_cost_row)
	nickname_cost_row.add_child(_shard_icon(22))
	nickname_cost_label = _make_label("Первый ник — бесплатно", 14, Color(0.76, 0.8, 0.89))
	nickname_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nickname_cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nickname_cost_row.add_child(nickname_cost_label)
	menu_shard_label = _make_label("Баланс: 0", 14, Color(0.43, 0.84, 1.0))
	menu_shard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nickname_cost_row.add_child(menu_shard_label)
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
	menu_xp_remaining_label = _make_label("До следующего уровня: 1000 XP", 16, Color(0.76, 0.8, 0.89))
	menu_xp_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	profile_content.add_child(menu_xp_remaining_label)
	menu_next_reward_label = _make_label("Награда: 75 осколков", 16, Color(0.43, 0.84, 1.0))
	menu_next_reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	profile_content.add_child(menu_next_reward_label)
	var skills_title := _make_label("СКИЛЛЫ", 16, GOLD)
	skills_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	profile_content.add_child(skills_title)
	skills_info_box = VBoxContainer.new()
	skills_info_box.name = "SkillInfoBox"
	skills_info_box.add_theme_constant_override("separation", 4)
	profile_content.add_child(skills_info_box)
	var stats_title := _make_label("СТАТИСТИКА", 16, GOLD)
	stats_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	profile_content.add_child(stats_title)
	var stats_tabs := HBoxContainer.new()
	stats_tabs.add_theme_constant_override("separation", 4)
	profile_content.add_child(stats_tabs)
	var tab_defs := [["all", "Всё время"], ["last", "Последний бой"], ["session", "Сессия"]]
	for tab_def in tab_defs:
		var tab_button := _make_action_button(String(tab_def[1]), false)
		tab_button.custom_minimum_size = Vector2(0, 28)
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_button.add_theme_font_size_override("font_size", 13)
		tab_button.pressed.connect(_set_stats_tab.bind(String(tab_def[0])))
		stats_tabs.add_child(tab_button)
		stats_tab_buttons[String(tab_def[0])] = tab_button
	stats_box = VBoxContainer.new()
	stats_box.name = "PlayerStats"
	stats_box.add_theme_constant_override("separation", 2)
	profile_content.add_child(stats_box)

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
	menu_hero_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var portrait_material := ShaderMaterial.new()
	portrait_material.shader = preload("res://shaders/ability_icon_mask.gdshader")
	portrait_material.set_shader_parameter("corner_radius", 0.05)
	menu_hero_portrait.material = portrait_material
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
	var inventory_tab := _make_action_button("ИНВЕНТАРЬ", true)
	inventory_tab.custom_minimum_size = Vector2(0, 42)
	inventory_tab.disabled = true
	wardrobe_content.add_child(inventory_tab)
	var inventory_grid := GridContainer.new()
	inventory_grid.name = "LegendaryWeaponInventory"
	inventory_grid.columns = 2
	inventory_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_grid.add_theme_constant_override("h_separation", 8)
	inventory_grid.add_theme_constant_override("v_separation", 8)
	wardrobe_content.add_child(inventory_grid)
	var weapon_names := ["Легендарный меч", "Легендарный посох", "Легендарный лук"]
	var weapon_colors := [Color(0.78, 0.29, 0.22), Color(0.33, 0.54, 0.86), Color(0.38, 0.7, 0.48)]
	for weapon_index in range(weapon_names.size()):
		var weapon_card := PanelContainer.new()
		weapon_card.name = "LegendaryWeapon%d" % (weapon_index + 1)
		weapon_card.custom_minimum_size = Vector2(110, 154)
		weapon_card.add_theme_stylebox_override("panel", _panel_style(Color(0.34, 0.37, 0.44), Color(0.065, 0.072, 0.09, 0.92)))
		inventory_grid.add_child(weapon_card)
		var weapon_content := VBoxContainer.new()
		weapon_content.add_theme_constant_override("separation", 5)
		weapon_card.add_child(weapon_content)
		var weapon_icon := ColorRect.new()
		weapon_icon.name = "WeaponPlaceholder%d" % (weapon_index + 1)
		weapon_icon.custom_minimum_size = Vector2(0, 52)
		weapon_icon.color = weapon_colors[weapon_index]
		weapon_icon.modulate.a = 0.5
		weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		weapon_content.add_child(weapon_icon)
		weapon_content.add_child(_make_label(weapon_names[weapon_index], 12, PALE))
		var status := _make_label("В магазине" if weapon_index == 0 else "Скоро", 12, Color(0.62, 0.65, 0.72))
		weapon_content.add_child(status)
		weapon_status_labels.append(status)
	_refresh_player_menu()


func _open_player_menu() -> void:
	_refresh_player_menu()
	player_menu_overlay.visible = true
	nickname_line_edit.editable = true
	nickname_line_edit.grab_focus()
	nickname_line_edit.call_deferred("grab_focus")
	if MetaProgression.player_id <= 0:
		_retry_registration()


func _retry_registration() -> void:
	if MetaProgression.player_id > 0:
		return
	if MetaProgression.player_nickname.is_empty():
		MetaProgression.player_nickname = _generate_guest_nickname()
	MetaProgression.register_player(MetaProgression.player_nickname)


func _generate_guest_nickname() -> String:
	return "Игрок %04d" % randi_range(1000, 9999)


func _close_player_menu() -> void:
	player_menu_overlay.visible = false


func _save_player_nickname() -> void:
	var nickname := nickname_line_edit.text.strip_edges()
	if nickname.length() < 3 or nickname.length() > 12:
		nickname_status_label.text = "Введите от 3 до 12 символов."
		nickname_status_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.42))
		return
	if ProfanityFilter.contains(nickname):
		nickname_status_label.text = "Ник содержит недопустимые слова."
		nickname_status_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.42))
		return
	if nickname == MetaProgression.player_nickname:
		nickname_status_label.text = "Ник не изменился."
		nickname_status_label.add_theme_color_override("font_color", Color(0.76, 0.8, 0.89))
		return
	if MetaProgression.player_id <= 0:
		pending_nickname = nickname
		MetaProgression.register_player(nickname)
		nickname_status_label.text = "Регистрируем профиль на сервере..."
		nickname_status_label.add_theme_color_override("font_color", Color(0.58, 0.9, 0.64))
		return
	if MetaProgression.nickname_custom and MetaProgression.sky_shards < NICKNAME_CHANGE_COST:
		nickname_status_label.text = "Не хватает: %d" % NICKNAME_CHANGE_COST
		nickname_status_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.42))
		MetaProgression.load_profile(MetaProgression.player_id)
		return
	if MetaProgression.nickname_custom:
		_open_rename_confirm(nickname)
		return
	_perform_rename(nickname)


func _perform_rename(nickname: String) -> void:
	NetworkClient.rename_player(MetaProgression.player_id, nickname)
	nickname_status_label.text = "Сохраняем ник на сервере..."
	nickname_status_label.add_theme_color_override("font_color", Color(0.58, 0.9, 0.64))


func _on_rename_completed(success: bool, nickname: String, error: String, charged: bool, cost: int, new_shards: int) -> void:
	if not is_inside_tree():
		return
	if success:
		MetaProgression.player_nickname = nickname
		MetaProgression.nickname_custom = true
		if charged:
			MetaProgression.sky_shards = maxi(0, new_shards)
		_save_player_id(MetaProgression.player_id)
		nickname_line_edit.text = nickname
		nickname_input_synced = nickname
		if charged:
			nickname_status_label.text = "Ник изменён. Списано %d." % cost
		else:
			nickname_status_label.text = "Ник сохранён."
		nickname_status_label.add_theme_color_override("font_color", Color(0.58, 0.9, 0.64))
		_refresh_player_profile()
		_refresh_player_menu()
		_refresh_wing_shop()
	else:
		if error == "Not enough shards":
			nickname_status_label.text = "Не хватает: %d" % NICKNAME_CHANGE_COST
			MetaProgression.load_profile(MetaProgression.player_id)
		else:
			nickname_status_label.text = "Не удалось: %s" % _localize_nickname_error(error)
		nickname_status_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.42))


func _localize_nickname_error(error: String) -> String:
	match error:
		"Nickname already taken":
			return "этот ник уже занят, выбери другой."
		"Nickname must be 3 to 12 characters":
			return "ник должен быть от 3 до 12 символов."
		"Nickname contains forbidden words":
			return "ник содержит недопустимые слова."
		"Player not found":
			return "профиль не найден, перезапусти игру."
		"Not enough shards":
			return "не хватает %d на смену ника." % NICKNAME_CHANGE_COST
		"Нет связи с сервером":
			return "сервер недоступен, попробуй позже."
		_:
			return error


func _load_player_id() -> int:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return 0
	return maxi(0, int(config.get_value("profile", "player_id", 0)))


func _load_player_nickname() -> String:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return ""
	return String(config.get_value("profile", "nickname", ""))


func _save_player_id(player_id: int) -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("profile", "player_id", player_id)
	config.set_value("profile", "nickname", MetaProgression.player_nickname)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_error("Не удалось сохранить ID профиля: %s" % error_string(error))


func _on_registration_completed(success: bool, registered_player_id: int) -> void:
	if success and registered_player_id > 0:
		if not pending_nickname.is_empty():
			MetaProgression.player_nickname = pending_nickname
			pending_nickname = ""
		_save_player_id(registered_player_id)
		if nickname_line_edit != null:
			nickname_line_edit.text = MetaProgression.player_nickname
		if nickname_status_label != null:
			nickname_status_label.text = "Профиль подключён."
			nickname_status_label.add_theme_color_override("font_color", Color(0.58, 0.9, 0.64))
		return
	if nickname_status_label == null:
		return
	if pending_nickname.is_empty() and MetaProgression.player_nickname.begins_with("Игрок ") and guest_attempts < 3:
		guest_attempts += 1
		MetaProgression.player_nickname = _generate_guest_nickname()
		MetaProgression.register_player(MetaProgression.player_nickname)
		nickname_status_label.text = "Пробуем другой временный ник..."
		nickname_status_label.add_theme_color_override("font_color", Color(0.76, 0.8, 0.89))
		return
	nickname_status_label.text = "Регистрация не удалась: сервер недоступен или ник занят."
	nickname_status_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.42))


func _build_rename_confirm() -> void:
	rename_confirm_overlay = ColorRect.new()
	rename_confirm_overlay.name = "RenameConfirmOverlay"
	rename_confirm_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rename_confirm_overlay.color = Color(0.005, 0.008, 0.018, 0.78)
	rename_confirm_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	rename_confirm_overlay.visible = false
	rename_confirm_overlay.z_index = 40
	add_child(rename_confirm_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rename_confirm_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "RenameConfirmPanel"
	panel.custom_minimum_size = Vector2(400, 0)
	panel.add_theme_stylebox_override("panel", _panel_style(GOLD, Color(0.035, 0.045, 0.07, 0.99)))
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	var title := _make_label("СМЕНА НИКА", 22, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	content.add_child(title)
	rename_confirm_label = _make_label("", 17, PALE)
	rename_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rename_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(rename_confirm_label)
	var cost_row := HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", 8)
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(cost_row)
	cost_row.add_child(_shard_icon(30))
	var cost_label := _make_label(str(NICKNAME_CHANGE_COST), 22, Color(0.43, 0.84, 1.0))
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cost_row.add_child(cost_label)
	var warning := _make_label("Спишутся сразу после подтверждения.", 13, Color(0.7, 0.74, 0.82))
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(warning)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(buttons)
	var cancel_button := _make_action_button("Отмена", false)
	cancel_button.custom_minimum_size = Vector2(150, 46)
	cancel_button.add_theme_font_size_override("font_size", 17)
	cancel_button.pressed.connect(_close_rename_confirm)
	buttons.add_child(cancel_button)
	var confirm_button := _make_action_button("Сменить", true)
	confirm_button.custom_minimum_size = Vector2(150, 46)
	confirm_button.add_theme_font_size_override("font_size", 17)
	confirm_button.pressed.connect(_confirm_rename)
	buttons.add_child(confirm_button)


func _open_rename_confirm(nickname: String) -> void:
	pending_rename_nickname = nickname
	rename_confirm_label.text = "Новый ник: «%s»" % nickname
	rename_confirm_overlay.visible = true


func _close_rename_confirm() -> void:
	pending_rename_nickname = ""
	if rename_confirm_overlay != null:
		rename_confirm_overlay.visible = false


func _confirm_rename() -> void:
	var nickname := pending_rename_nickname
	_close_rename_confirm()
	if not nickname.is_empty():
		_perform_rename(nickname)


func _build_report_form() -> void:
	report_overlay = ColorRect.new()
	report_overlay.name = "ReportFormOverlay"
	report_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	report_overlay.color = Color(0.005, 0.008, 0.018, 0.82)
	report_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	report_overlay.visible = false
	report_overlay.z_index = 45
	add_child(report_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	report_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "ReportFormPanel"
	panel.custom_minimum_size = Vector2(460, 0)
	panel.add_theme_stylebox_override("panel", _panel_style(GOLD, Color(0.035, 0.045, 0.07, 0.99)))
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := _make_label("ПОЖАЛОВАТЬСЯ", 22, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := _make_action_button("×", false)
	close_button.custom_minimum_size = Vector2(42, 40)
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.pressed.connect(_close_report_form)
	header.add_child(close_button)
	var nickname_label := _make_label("Ник игрока", 15, PALE)
	nickname_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	content.add_child(nickname_label)
	report_nickname_edit = LineEdit.new()
	report_nickname_edit.name = "ReportNickname"
	report_nickname_edit.placeholder_text = "Ник (3–12 символов)"
	report_nickname_edit.max_length = 12
	report_nickname_edit.custom_minimum_size = Vector2(0, 42)
	report_nickname_edit.add_theme_font_override("font", font)
	content.add_child(report_nickname_edit)
	var reason_label := _make_label("Причина", 15, PALE)
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	content.add_child(reason_label)
	report_reason_option = OptionButton.new()
	report_reason_option.name = "ReportReason"
	report_reason_option.custom_minimum_size = Vector2(0, 42)
	report_reason_option.add_theme_font_override("font", font)
	report_reason_option.add_theme_font_size_override("font_size", 15)
	report_reason_option.add_item("Оскорбительный ник")
	report_reason_option.add_item("Читы / нечестная игра")
	report_reason_option.add_item("Другое")
	content.add_child(report_reason_option)
	report_status_label = _make_label("", 14, Color(0.76, 0.8, 0.89))
	report_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	report_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(report_status_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	content.add_child(buttons)
	var cancel_button := _make_action_button("Отмена", false)
	cancel_button.custom_minimum_size = Vector2(150, 46)
	cancel_button.add_theme_font_size_override("font_size", 17)
	cancel_button.pressed.connect(_close_report_form)
	buttons.add_child(cancel_button)
	report_submit_button = _make_action_button("Отправить", true)
	report_submit_button.name = "ReportSubmit"
	report_submit_button.custom_minimum_size = Vector2(150, 46)
	report_submit_button.add_theme_font_size_override("font_size", 17)
	report_submit_button.pressed.connect(_submit_report)
	buttons.add_child(report_submit_button)


func _open_report_form() -> void:
	report_nickname_edit.text = ""
	report_reason_option.select(0)
	report_status_label.text = ""
	report_status_label.add_theme_color_override("font_color", Color(0.76, 0.8, 0.89))
	report_submit_button.disabled = false
	report_overlay.visible = true
	report_nickname_edit.grab_focus()


func _close_report_form() -> void:
	if report_overlay != null:
		report_overlay.visible = false


func _submit_report() -> void:
	var nickname := report_nickname_edit.text.strip_edges()
	if nickname.length() < 3 or nickname.length() > 12:
		report_status_label.text = "Введите ник от 3 до 12 символов."
		report_status_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.42))
		return
	if nickname == MetaProgression.player_nickname:
		report_status_label.text = "Нельзя пожаловаться на себя."
		report_status_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.42))
		return
	var reason := report_reason_option.get_item_text(report_reason_option.selected)
	report_status_label.text = "Отправляем жалобу..."
	report_status_label.add_theme_color_override("font_color", Color(0.76, 0.8, 0.89))
	report_submit_button.disabled = true
	NetworkClient.report_player(MetaProgression.player_id, nickname, reason)


func _on_report_completed(success: bool, error: String) -> void:
	if report_submit_button != null:
		report_submit_button.disabled = false
	if report_status_label == null:
		return
	if success:
		report_status_label.text = "Жалоба отправлена. Спасибо!"
		report_status_label.add_theme_color_override("font_color", Color(0.58, 0.9, 0.64))
	else:
		report_status_label.text = "Не удалось: %s" % _localize_report_error(error)
		report_status_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.42))


func _localize_report_error(error: String) -> String:
	match error:
		"Too many reports":
			return "слишком много жалоб, попробуй позже."
		"Player not found":
			return "профиль не найден."
		"Нет связи с сервером":
			return "сервер недоступен, попробуй позже."
		_:
			return error


func _refresh_player_menu() -> void:
	if menu_hero_portrait == null:
		return
	if nickname_line_edit != null:
		var current_input := nickname_line_edit.text.strip_edges()
		if not nickname_line_edit.has_focus() or current_input == nickname_input_synced:
			nickname_line_edit.text = MetaProgression.player_nickname
		nickname_input_synced = MetaProgression.player_nickname
	if nickname_cost_label != null:
		if MetaProgression.nickname_custom:
			nickname_cost_label.text = "Смена ника — %d" % NICKNAME_CHANGE_COST
			nickname_cost_label.add_theme_color_override("font_color", Color(0.95, 0.76, 0.38))
		else:
			nickname_cost_label.text = "Первый ник — бесплатно"
			nickname_cost_label.add_theme_color_override("font_color", Color(0.58, 0.9, 0.64))
	if menu_shard_label != null:
		menu_shard_label.text = "Баланс: %d" % MetaProgression.sky_shards
	var character_key: String = ["warrior", "mage", "fairy"][selected_class]
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
	_refresh_skill_info()
	_refresh_stats()


func _refresh_skill_info() -> void:
	if skills_info_box == null:
		return
	for child in skills_info_box.get_children():
		skills_info_box.remove_child(child)
		child.queue_free()
	var abilities: Array = HeroUnit.CLASS_DATA[selected_class]["abilities"]
	var descriptions: Array = SKILL_DESCRIPTIONS[selected_class]
	for index in range(abilities.size()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var icon := TextureRect.new()
		icon.texture = SKILL_ICONS[selected_class][index]
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var text_box := VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_box.add_theme_constant_override("separation", 0)
		var title := _make_label("%s · %d с" % [String(abilities[index]["name"]), int(abilities[index]["cd"])], 16, PALE)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.clip_text = true
		text_box.add_child(title)
		var description := _make_label(String(descriptions[index]), 14, Color(0.72, 0.76, 0.86))
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_box.add_child(description)
		row.add_child(text_box)
		skills_info_box.add_child(row)


func _set_stats_tab(tab: String) -> void:
	stats_tab = tab
	_refresh_stats()


func _refresh_stats() -> void:
	if stats_box == null:
		return
	for key in stats_tab_buttons:
		var tab_button: Button = stats_tab_buttons[key]
		tab_button.add_theme_color_override("font_color", GOLD if key == stats_tab else PALE)
	for child in stats_box.get_children():
		stats_box.remove_child(child)
		child.queue_free()
	var stats := MetaProgression.stats_for(stats_tab)
	var rows := [
		["Урон", str(int(stats.get("damage", 0)))],
		["Убийства", str(int(stats.get("kills", 0)))],
		["Опыт", str(int(stats.get("xp", 0)))],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	for row in rows:
		var key_label := _make_label(String(row[0]), 16, Color(0.7, 0.75, 0.84))
		key_label.custom_minimum_size = Vector2(150, 24)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(key_label)
		var value_label := _make_label(String(row[1]), 16, PALE)
		value_label.custom_minimum_size = Vector2(80, 24)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value_label)
	stats_box.add_child(grid)


func _cycle_selected_hero(direction: int) -> void:
	selected_class = wrapi(selected_class + direction, 0, HERO_NAMES.size())
	_save_selection()
	_refresh_selection()


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
	var card_width := 330.0 if is_center else 210.0
	var card_height := 502.0 if is_center else 333.0
	var footer_height := 52.0 if is_center else 44.0
	var frame_color: Color = CLASS_FRAME_COLORS.get(slot_classes[slot], GOLD)
	card.custom_minimum_size = Vector2(card_width, card_height)
	if is_center:
		card.offset_left = -165.0
		card.offset_top = -165.0
		card.offset_right = 165.0
		card.offset_bottom = 337.0
		card.z_index = 2
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		var side_offset := -392.0 if slot == 0 else 182.0
		card.offset_left = side_offset
		card.offset_top = -160.0
		card.offset_right = side_offset + 210.0
		card.offset_bottom = 173.0
		card.z_index = 1
	card.add_theme_stylebox_override("normal", _card_style(is_center, false, frame_color))
	card.add_theme_stylebox_override("hover", _card_style(is_center, not is_center, frame_color))
	card.add_theme_stylebox_override("pressed", _card_style(is_center, not is_center, frame_color))
	add_child(card)

	var inset := 8.0
	var image := TextureRect.new()
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.offset_left = 0.0
	image.offset_top = 0.0
	image.offset_right = 0.0
	image.offset_bottom = -(footer_height + inset)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait_material := ShaderMaterial.new()
	portrait_material.shader = preload("res://shaders/card_portrait.gdshader")
	portrait_material.set_shader_parameter("rect_size", Vector2(card_width, card_height - footer_height - inset))
	portrait_material.set_shader_parameter("corner_px", 16.0 if is_center else 12.0)
	image.material = portrait_material
	card.add_child(image)

	var footer := Panel.new()
	footer.name = "HeroFooter%d" % slot
	footer.anchor_left = 0.0
	footer.anchor_top = 1.0
	footer.anchor_right = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_left = inset
	footer.offset_top = -(inset + footer_height)
	footer.offset_right = -inset
	footer.offset_bottom = -inset
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_theme_stylebox_override("panel", _card_footer_style(frame_color))
	card.add_child(footer)

	var name_label := _make_label("", 23 if is_center else 17, PALE)
	name_label.name = "HeroName%d" % slot
	name_label.anchor_left = 0.0
	name_label.anchor_top = 0.0
	name_label.anchor_right = 1.0
	name_label.anchor_bottom = 1.0
	name_label.offset_left = 4.0
	name_label.offset_right = -4.0
	name_label.offset_top = 2.0
	name_label.offset_bottom = -2.0
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(name_label)

	var frame := Panel.new()
	frame.name = "CardFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.z_index = 3
	frame.add_theme_stylebox_override("panel", _card_frame_style(frame_color, is_center))
	card.add_child(frame)

	cards.append(card)
	card_images.append(image)
	card_names.append(name_label)
	card_footers.append(footer)
	card_portrait_materials.append(portrait_material)


func _build_actions() -> void:
	play_button = _make_action_button("В БОЙ", true)
	play_button.name = "PlayButton"
	play_button.anchor_left = 1.0
	play_button.anchor_top = 1.0
	play_button.anchor_right = 1.0
	play_button.anchor_bottom = 1.0
	play_button.offset_left = -345.0
	play_button.offset_top = -180.0
	play_button.offset_right = -45.0
	play_button.offset_bottom = -108.0
	play_button.custom_minimum_size = Vector2(300.0, 72.0)
	play_button.add_theme_font_size_override("font_size", 26)
	play_button.pressed.connect(_start_network_battle)
	add_child(play_button)

	tutorial_button = _make_action_button("ОБУЧЕНИЕ", false)
	tutorial_button.name = "TutorialButton"
	tutorial_button.anchor_left = 1.0
	tutorial_button.anchor_top = 1.0
	tutorial_button.anchor_right = 1.0
	tutorial_button.anchor_bottom = 1.0
	tutorial_button.offset_left = -345.0
	tutorial_button.offset_top = -100.0
	tutorial_button.offset_right = -45.0
	tutorial_button.offset_bottom = -28.0
	tutorial_button.custom_minimum_size = Vector2(300.0, 72.0)
	tutorial_button.add_theme_font_size_override("font_size", 22)
	tutorial_button.pressed.connect(_start_tutorial)
	add_child(tutorial_button)
	_refresh_tutorial_button()

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
		var frame_color: Color = CLASS_FRAME_COLORS.get(hero_class, GOLD)
		var texture := load(HERO_ART[hero_class]) as Texture2D
		card_images[slot].texture = texture
		card_names[slot].text = HERO_NAMES[hero_class]
		for style_name in ["normal", "hover", "pressed"]:
			cards[slot].add_theme_stylebox_override(style_name, _card_style(slot == 1, style_name != "normal", frame_color))
		card_footers[slot].add_theme_stylebox_override("panel", _card_footer_style(frame_color))
		var frame := cards[slot].get_node_or_null("CardFrame") as Panel
		if frame != null:
			frame.add_theme_stylebox_override("panel", _card_frame_style(frame_color, slot == 1))
		if slot == 1:
			card_images[slot].modulate = Color.WHITE
			card_names[slot].add_theme_color_override("font_color", GOLD)
		else:
			card_images[slot].modulate = Color(0.62, 0.65, 0.72, 1.0)
			card_names[slot].add_theme_color_override("font_color", Color(0.72, 0.75, 0.82))
	var avatar_source := load(HERO_ART[selected_class]) as Texture2D
	if avatar_source != null:
		var avatar_atlas := AtlasTexture.new()
		avatar_atlas.atlas = avatar_source
		avatar_atlas.region = Rect2(0.0, 0.0, avatar_source.get_width(), avatar_source.get_height() * 0.42)
		avatar.texture = avatar_atlas
	_refresh_player_profile()
	_refresh_player_menu()


func _refresh_player_profile() -> void:
	if profile_name_label == null or profile_level_label == null:
		return
	var character_key: String = ['warrior', 'mage', 'fairy'][selected_class]
	var character_level := int(MetaProgression.char_levels.get(character_key, 1))
	var character_xp := int(MetaProgression.char_xps.get(character_key, 0))
	var nickname := MetaProgression.player_nickname.strip_edges()
	if nickname.is_empty():
		nickname = "Игрок"
	profile_name_label.text = nickname
	profile_level_label.text = '%s · Уровень %d' % [HERO_NAMES[selected_class], character_level]
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


func _start_network_battle() -> void:
	if NetworkManager.is_connecting():
		return
	_save_selection()
	get_tree().set_meta("tutorial_mode", false)
	get_tree().set_meta("network_play", true)
	get_tree().set_meta("selected_class", selected_class)
	get_tree().set_meta("selected_team", 0)
	var error := get_tree().change_scene_to_file("res://scenes/LoadingScreen.tscn")
	if error != OK:
		get_tree().set_meta("network_play", false)
		_show_info("Не удалось открыть экран поиска.")


func _on_network_connected() -> void:
	if not is_inside_tree():
		return
	_set_play_status("ПОИСК ИГРЫ...", true)


func _on_network_match_started(room_id: int, _host_id: int, players: Array) -> void:
	if not is_inside_tree():
		return
	get_tree().set_meta("network_play", true)
	get_tree().set_meta("tutorial_mode", false)
	get_tree().set_meta("selected_class", NetworkManager.local_class)
	get_tree().set_meta("selected_team", NetworkManager.assigned_team)
	get_tree().set_meta("network_host", NetworkManager.is_host)
	get_tree().set_meta("network_room_id", room_id)
	get_tree().set_meta("network_match_players", players)
	if play_button != null:
		_set_play_status("МАТЧ НАЙДЕН", true)
	var error := get_tree().change_scene_to_file("res://scenes/Main.tscn")
	if error != OK:
		get_tree().set_meta("network_play", false)
		_reset_network_button()
		_show_info("Не удалось открыть арену.")


func _on_network_failed(reason: String) -> void:
	if not is_inside_tree():
		return
	get_tree().set_meta("network_play", false)
	_reset_network_button()
	_show_info("Не удалось подключиться к серверу: %s" % reason)


func _on_network_disconnected() -> void:
	_reset_network_button()


func _reset_network_button() -> void:
	_set_play_status("В БОЙ", false)


func _set_play_status(text: String, disabled: bool) -> void:
	if play_button == null or not is_instance_valid(play_button):
		return
	play_button.text = text
	play_button.disabled = disabled


func _start_battle() -> void:
	_save_selection()
	if NetworkManager.is_connecting() or NetworkManager.is_server_connected():
		NetworkManager.disconnect_from_server(false)
	get_tree().set_meta("tutorial_mode", false)
	get_tree().set_meta("network_play", false)
	_record_normal_battle_started()
	get_tree().set_meta("selected_class", selected_class)
	var selected_team := randi_range(0, 1)
	get_tree().set_meta("selected_team", selected_team)
	var error := get_tree().change_scene_to_file("res://scenes/LoadingScreen.tscn")
	if error != OK:
		push_error("Не удалось открыть экран загрузки: %s" % error_string(error))


func _start_tutorial() -> void:
	if tutorial_button == null or tutorial_button.disabled:
		return
	_save_selection()
	if NetworkManager.is_connecting() or NetworkManager.is_server_connected():
		NetworkManager.disconnect_from_server(false)
	get_tree().set_meta("selected_class", selected_class)
	get_tree().set_meta("selected_team", 0)
	get_tree().set_meta("tutorial_mode", true)
	get_tree().set_meta("network_play", false)
	var error := get_tree().change_scene_to_file("res://scenes/Main.tscn")
	if error != OK:
		push_error("Не удалось запустить обучение: %s" % error_string(error))


func _tutorial_config() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(TUTORIAL_SAVE_PATH)
	return config


func _tutorial_battles_used() -> int:
	return maxi(0, int(_tutorial_config().get_value("tutorial", "battles_used", 0)))


func _tutorial_completed() -> bool:
	return bool(_tutorial_config().get_value("tutorial", "completed", false))


func _record_normal_battle_started() -> void:
	var config := _tutorial_config()
	config.set_value("tutorial", "battles_used", _tutorial_battles_used() + 1)
	var error := config.save(TUTORIAL_SAVE_PATH)
	if error != OK:
		push_error("Не удалось сохранить число боёв до обучения: %s" % error_string(error))
	_refresh_tutorial_button()


func _refresh_tutorial_button() -> void:
	if tutorial_button == null:
		return
	tutorial_button.text = "ОБУЧЕНИЕ"
	tutorial_button.disabled = false


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


func _card_style(is_center: bool, hovered: bool, frame_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.06, 0.09, 0.95) if is_center else Color(0.035, 0.045, 0.07, 0.85)
	if hovered and not is_center:
		style.bg_color = Color(0.075, 0.09, 0.13, 0.97)
	style.border_color = Color(frame_color.r, frame_color.g, frame_color.b, 1.0 if is_center else 0.5)
	if hovered and not is_center:
		style.border_color = frame_color
	style.set_border_width_all(0)
	style.set_corner_radius_all(16 if is_center else 12)
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


func _card_frame_style(frame_color: Color, is_center: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = frame_color
	style.set_border_width_all(3 if is_center else 2)
	style.set_corner_radius_all(16 if is_center else 12)
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


func _card_footer_style(frame_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.028, 0.05, 0.96)
	style.border_color = Color(frame_color.r, frame_color.g, frame_color.b, 0.9)
	style.border_width_top = 2
	style.set_corner_radius_all(10)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
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


func _shard_icon(icon_size: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = SHARD_ICON
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


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
