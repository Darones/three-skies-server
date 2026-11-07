extends Control

const CHARACTER_ART := [
	"res://assets/characters/warrior_light.png",
	"res://assets/characters/mage_dark.png",
	"res://assets/characters/fairy.png",
]
const CHARACTER_NAMES := ["Воин Света", "Маг Тьмы", "Фея поддержки"]
const CHARACTER_KEYS := ["warrior", "mage", "fairy"]
const REPLAY_SCENE := "res://scenes/LoadingScreen.tscn"
const MENU_SCENE := "res://scenes/Lobby.tscn"
const GOLD := Color(0.94, 0.78, 0.43)
const PALE := Color(0.9, 0.91, 0.95)

const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")

var font: FontFile
var selected_class := 0
var player_won := true
var score: Array = [0, 0]
var match_stats: Dictionary = {}
var player_place := 4
var player_is_mvp := false
var final_shards := 0
var final_xp := 0
var rewards_doubled := false
var rewards_committed := false
var ad_in_progress := false
var double_reward_button: Button
var shards_reward_label: Label
var xp_reward_label: Label


func _ready() -> void:
	font = UI_FONT
	if not AdManager.rewarded_ad_completed.is_connected(_on_rewarded_ad_completed):
		AdManager.rewarded_ad_completed.connect(_on_rewarded_ad_completed)
	selected_class = clampi(int(get_tree().get_meta("selected_class", 0)), 0, 2)
	player_won = bool(get_tree().get_meta("last_match_won", true))
	score = get_tree().get_meta("last_match_score", [0, 0])
	match_stats = get_tree().get_meta("last_match_stats", {})
	player_place = maxi(1, int(get_tree().get_meta("last_match_place", 4)))
	player_is_mvp = bool(get_tree().get_meta("last_match_is_mvp", false))
	if player_is_mvp:
		player_place = 1
	var kills := int(match_stats.get("p_kills", 0))
	var shells_destroyed := int(match_stats.get("p_shells_destroyed", 0))
	var crystals_delivered := int(match_stats.get("p_crystals", 0))
	final_shards = 5 if player_won and player_is_mvp else 3 if player_won or player_is_mvp else 1
	final_xp = kills * 10 + shells_destroyed * 25 + crystals_delivered * 25 + (50 if player_won else 20)
	_build_screen()


func _build_screen() -> void:
	_build_background()
	_build_header()
	_build_content()
	_build_buttons()


func _build_background() -> void:
	var background := ColorRect.new()
	background.name = "DarkGradient"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
void fragment() {
	float vertical = UV.y;
	float center_glow = exp(-abs(UV.y - 0.18) * 10.0) * (1.0 - abs(UV.x - 0.5));
	vec3 top_color = vec3(0.045, 0.05, 0.075);
	vec3 bottom_color = vec3(0.008, 0.01, 0.02);
	vec3 color = mix(top_color, bottom_color, vertical) + vec3(0.12, 0.085, 0.035) * center_glow;
	COLOR = vec4(color, 1.0);
}"""
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	background.material = shader_material
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var top_rule := ColorRect.new()
	top_rule.name = "GoldRule"
	top_rule.anchor_left = 0.12
	top_rule.anchor_top = 0.247
	top_rule.anchor_right = 0.88
	top_rule.anchor_bottom = 0.249
	top_rule.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55)
	top_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_rule)


func _build_header() -> void:
	var title_color := GOLD if player_won else Color(0.9, 0.3, 0.29)
	var title := _make_label("ПОБЕДА" if player_won else "ПОРАЖЕНИЕ", 68, title_color)
	title.name = "ResultTitle"
	title.anchor_left = 0.08
	title.anchor_top = 0.035
	title.anchor_right = 0.92
	title.anchor_bottom = 0.145
	add_child(title)

	var subtitle_text := "ИТОГИ МАТЧА  ·  СВЕТ %d : %d ТЬМА" % [int(score[0]), int(score[1])]
	var subtitle := _make_label(subtitle_text, 17, Color(0.76, 0.78, 0.84))
	subtitle.name = "MatchSummary"
	subtitle.anchor_left = 0.08
	subtitle.anchor_top = 0.137
	subtitle.anchor_right = 0.92
	subtitle.anchor_bottom = 0.18
	add_child(subtitle)

	var placement_text := "ВЫ MVP!" if player_is_mvp else "ВАШЕ МЕСТО: %d" % player_place
	var placement := _make_label(placement_text, 29, GOLD if player_is_mvp else PALE)
	placement.name = "PlayerPlacement"
	placement.anchor_left = 0.08
	placement.anchor_top = 0.184
	placement.anchor_right = 0.92
	placement.anchor_bottom = 0.238
	add_child(placement)


func _build_content() -> void:
	var content := HBoxContainer.new()
	content.name = "ResultsContent"
	content.anchor_left = 0.12
	content.anchor_top = 0.27
	content.anchor_right = 0.88
	content.anchor_bottom = 0.765
	content.add_theme_constant_override("separation", 30)
	add_child(content)

	var portrait_panel := _make_panel(Color(0.43, 0.39, 0.3, 0.9))
	portrait_panel.name = "PortraitPanel"
	portrait_panel.custom_minimum_size = Vector2(350.0, 0.0)
	portrait_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(portrait_panel)
	var portrait_content := VBoxContainer.new()
	portrait_content.add_theme_constant_override("separation", 10)
	portrait_panel.add_child(portrait_content)

	var portrait_frame := PanelContainer.new()
	portrait_frame.name = "PortraitFrame"
	portrait_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_frame.add_theme_stylebox_override("panel", _panel_style(Color(0.19, 0.21, 0.27), Color(0.01, 0.015, 0.025)))
	portrait_content.add_child(portrait_frame)
	var portrait := TextureRect.new()
	portrait.name = "HeroPortrait"
	portrait.texture = load(CHARACTER_ART[selected_class]) as Texture2D
	portrait.custom_minimum_size = Vector2(0.0, 260.0)
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.clip_contents = true
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_child(portrait)

	var hero_name := _make_label(CHARACTER_NAMES[selected_class], 24, PALE)
	hero_name.name = "HeroName"
	portrait_content.add_child(hero_name)
	var skin_label := _make_label("УРОВЕНЬ: 1    ·    СТАНДАРТНЫЙ", 16, Color(0.72, 0.74, 0.8))
	skin_label.name = "HeroSkin"
	portrait_content.add_child(skin_label)

	var stats_panel := _make_panel(Color(0.3, 0.32, 0.38, 0.9))
	stats_panel.name = "StatisticsPanel"
	stats_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(stats_panel)
	var stats_content := VBoxContainer.new()
	stats_content.add_theme_constant_override("separation", 5)
	stats_panel.add_child(stats_content)
	var stats_title := _make_label("СТАТИСТИКА", 27, GOLD)
	stats_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stats_content.add_child(stats_title)
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	stats_content.add_child(divider)

	shards_reward_label = _make_label("Получено: %d осколков" % final_shards, 18, Color(0.43, 0.84, 1.0))
	shards_reward_label.name = "ShardReward"
	shards_reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stats_content.add_child(shards_reward_label)
	xp_reward_label = _make_label("Получено: %d опыта" % final_xp, 18, Color(0.62, 0.86, 1.0))
	xp_reward_label.name = "XPReward"
	xp_reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stats_content.add_child(xp_reward_label)

	stats_content.add_child(_make_stat_row("Убийства", str(int(match_stats.get("p_kills", 0)))))
	stats_content.add_child(_make_stat_row("Смерти", str(int(match_stats.get("p_deaths", 0)))))
	stats_content.add_child(_make_stat_row("Собранные монеты", str(int(match_stats.get("p_coins_collected", 0)))))

	double_reward_button = _make_button("", false)
	double_reward_button.name = "DoubleRewardsButton"
	double_reward_button.custom_minimum_size = Vector2(0.0, 46.0)
	double_reward_button.add_theme_font_size_override("font_size", 13)
	double_reward_button.pressed.connect(_double_rewards_for_ad)
	stats_content.add_child(double_reward_button)
	_refresh_reward_ui()


func _make_stat_row(label_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 38.0)
	row.add_theme_constant_override("separation", 12)
	var name_label := _make_label(label_text, 21, PALE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value_label := _make_label(value_text, 25, GOLD)
	value_label.custom_minimum_size = Vector2(64.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	var wrapper := VBoxContainer.new()
	wrapper.add_child(row)
	var separator := ColorRect.new()
	separator.custom_minimum_size = Vector2(0.0, 1.0)
	separator.color = Color(0.6, 0.62, 0.69, 0.16)
	wrapper.add_child(separator)
	return wrapper


func _build_buttons() -> void:
	var button_row := HBoxContainer.new()
	button_row.name = "ActionButtons"
	button_row.anchor_left = 0.24
	button_row.anchor_top = 0.825
	button_row.anchor_right = 0.76
	button_row.anchor_bottom = 0.94
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 20)
	add_child(button_row)
	var retry_button := _make_button("ИГРАТЬ СНОВА", true)
	retry_button.name = "ReplayButton"
	retry_button.pressed.connect(_open_replay)
	button_row.add_child(retry_button)
	var menu_button := _make_button("В ЛОББИ", false)
	menu_button.name = "MenuButton"
	menu_button.pressed.connect(_open_menu)
	button_row.add_child(menu_button)


func _make_panel(border_color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(border_color, Color(0.025, 0.03, 0.05, 0.88)))
	return panel


func _panel_style(border_color: Color, fill_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(11)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 15.0
	style.content_margin_bottom = 15.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0.0, 4.0)
	return style


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.72))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(230.0, 62.0)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", GOLD if primary else PALE)
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.78))
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _button_style(primary, false))
	button.add_theme_stylebox_override("hover", _button_style(primary, true))
	button.add_theme_stylebox_override("pressed", _button_style(primary, true))
	return button


func _button_style(primary: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.13, 0.08, 0.98) if primary else Color(0.055, 0.065, 0.09, 0.98)
	style.border_color = GOLD if primary else Color(0.46, 0.49, 0.57)
	if hovered:
		style.bg_color = Color(0.24, 0.19, 0.11, 1.0) if primary else Color(0.1, 0.12, 0.17, 1.0)
		style.border_color = Color(1.0, 0.88, 0.59) if primary else Color(0.76, 0.8, 0.89)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _open_replay() -> void:
	_change_scene(REPLAY_SCENE)


func _open_menu() -> void:
	if not rewards_committed:
		MetaProgression.add_shards(final_shards)
		MetaProgression.add_character_xp(CHARACTER_KEYS[selected_class], final_xp)
		rewards_committed = true
	_change_scene(MENU_SCENE)


func _double_rewards_for_ad() -> void:
	if rewards_doubled or ad_in_progress or double_reward_button == null:
		return
	ad_in_progress = true
	double_reward_button.disabled = true
	double_reward_button.text = "Реклама..."
	await AdManager.show_rewarded_ad()


func _on_rewarded_ad_completed() -> void:
	if not ad_in_progress or rewards_doubled:
		return
	ad_in_progress = false
	final_shards *= 2
	final_xp *= 2
	rewards_doubled = true
	_refresh_reward_ui()


func _refresh_reward_ui() -> void:
	if shards_reward_label != null:
		shards_reward_label.text = "Получено: %d осколков" % final_shards
	if xp_reward_label != null:
		xp_reward_label.text = "Получено: %d опыта" % final_xp
	if double_reward_button == null:
		return
	if rewards_doubled:
		double_reward_button.text = "Награды удвоены"
		double_reward_button.disabled = true
	else:
		double_reward_button.text = "Смотреть рекламу (x2: %d осколков, %d XP)" % [final_shards * 2, final_xp * 2]
		double_reward_button.disabled = false


func _change_scene(scene_path: String) -> void:
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Failed to open %s: %s" % [scene_path, error_string(error)])
