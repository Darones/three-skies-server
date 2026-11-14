extends Control

const CHARACTER_ART := [
	"res://ui/portraits/warrior_portrait.png",
	"res://ui/portraits/mage_portrait.png",
	"res://ui/portraits/fairy_portrait.png",
]
const CHARACTER_CLASS_NAMES := ["Воин", "Маг", "Фея"]
const CHARACTER_KEYS := ["warrior", "mage", "fairy"]
const REPLAY_SCENE := "res://scenes/LoadingScreen.tscn"
const MENU_SCENE := "res://scenes/Lobby.tscn"
const GOLD := Color(0.94, 0.78, 0.43)
const PALE := Color(0.9, 0.91, 0.95)

const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const SHARD_ICON: Texture2D = preload("res://ui/icons/sky_shard.png")
const VICTORY_SOUND: AudioStream = preload("res://audio/sfx/misc_start_kenney_hit_11.ogg")
const DEFEAT_SOUND: AudioStream = preload("res://audio/sfx/fairy_death_scream.wav")

var font: FontFile
var selected_class := 0
var player_team := 0
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
var stats_scroll: ScrollContainer
var players_scroll: ScrollContainer
var stats_tab_button: Button
var players_tab_button: Button
var ad_button_pulse_tween: Tween
var victory_player: AudioStreamPlayer


func _build_players_table(parent: VBoxContainer) -> void:
	var players: Array = get_tree().get_meta("last_match_players", [])
	if players.is_empty():
		var empty_label := _make_label("Нет данных о игроках", 16, Color(0.65, 0.68, 0.76))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		parent.add_child(empty_label)
		return

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.add_child(_table_cell("ИГРОК", 12, Color(0.55, 0.58, 0.66), 0.0, HORIZONTAL_ALIGNMENT_LEFT))
	header.add_child(_table_cell("У/С", 12, Color(0.55, 0.58, 0.66), 58.0, HORIZONTAL_ALIGNMENT_CENTER))
	header.add_child(_table_cell("УРОН", 12, Color(0.55, 0.58, 0.66), 74.0, HORIZONTAL_ALIGNMENT_RIGHT))
	header.add_child(_table_cell("ОСК.", 12, Color(0.55, 0.58, 0.66), 52.0, HORIZONTAL_ALIGNMENT_RIGHT))
	parent.add_child(header)
	parent.add_child(_thin_divider())

	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("damage", 0)) > int(b.get("damage", 0))
	)
	var best_damage := int(players[0].get("damage", 0))
	for team in [0, 1]:
		var team_label := _make_label("СВЕТ" if team == 0 else "ТЬМА", 12, GOLD if team == player_team else Color(0.55, 0.6, 0.7))
		team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		parent.add_child(team_label)
		for entry in players:
			if int(entry.get("team", 0)) != team:
				continue
			parent.add_child(_make_player_row(entry, best_damage))


func _make_player_row(entry: Dictionary, best_damage: int) -> Control:
	var is_self := bool(entry.get("is_player", false))
	var row_panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.94, 0.78, 0.43, 0.12) if is_self else Color(0.0, 0.0, 0.0, 0.0)
	style.set_corner_radius_all(5)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	row_panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row_panel.add_child(row)

	var damage := int(entry.get("damage", 0))
	var name_text := String(entry.get("name", "?"))
	if damage > 0 and damage == best_damage:
		name_text = "★ " + name_text
	var name_cell := _table_cell(name_text, 13, GOLD if is_self else PALE, 0.0, HORIZONTAL_ALIGNMENT_LEFT)
	name_cell.clip_text = true
	row.add_child(name_cell)
	row.add_child(_table_cell("%d/%d" % [int(entry.get("kills", 0)), int(entry.get("deaths", 0))], 13, Color(0.8, 0.85, 0.95), 58.0, HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(_table_cell(str(damage), 13, Color(1.0, 0.8, 0.5), 74.0, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_table_cell(str(int(entry.get("crystals", 0))), 13, Color(0.43, 0.84, 1.0), 52.0, HORIZONTAL_ALIGNMENT_RIGHT))
	return row_panel


func _table_cell(text: String, font_size: int, color: Color, width: float, align: int) -> Label:
	var label := _make_label(text, font_size, color)
	label.horizontal_alignment = align
	if width <= 0.0:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		label.custom_minimum_size = Vector2(width, 0.0)
	return label


func _thin_divider() -> ColorRect:
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.color = Color(0.6, 0.62, 0.69, 0.18)
	return divider


func _make_tab_button(text: String, active: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 38.0)
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", GOLD if active else Color(0.6, 0.63, 0.71))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.78))
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _tab_style(active))
	button.add_theme_stylebox_override("hover", _tab_style(active))
	button.add_theme_stylebox_override("pressed", _tab_style(active))
	return button


func _tab_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.13, 0.08, 0.9) if active else Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = GOLD if active else Color(0.42, 0.45, 0.52, 0.55)
	style.border_width_bottom = 2
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _switch_result_tab(show_players: bool) -> void:
	if players_scroll == null or stats_scroll == null:
		return
	players_scroll.visible = show_players
	stats_scroll.visible = not show_players
	_apply_tab_state(stats_tab_button, not show_players)
	_apply_tab_state(players_tab_button, show_players)


func _apply_tab_state(button: Button, active: bool) -> void:
	if button == null:
		return
	button.add_theme_color_override("font_color", GOLD if active else Color(0.6, 0.63, 0.71))
	button.add_theme_stylebox_override("normal", _tab_style(active))
	button.add_theme_stylebox_override("hover", _tab_style(active))
	button.add_theme_stylebox_override("pressed", _tab_style(active))


func _animate_rewards() -> void:
	if shards_reward_label == null or xp_reward_label == null:
		return
	var shard_tween := create_tween()
	shard_tween.tween_method(func(value: float) -> void:
		if is_instance_valid(shards_reward_label):
			shards_reward_label.text = "Получено: %d" % int(round(value))
	, 0.0, float(final_shards), 0.9)
	var xp_tween := create_tween()
	xp_tween.tween_method(func(value: float) -> void:
		if is_instance_valid(xp_reward_label):
			xp_reward_label.text = "Получено: %d опыта" % int(round(value))
	, 0.0, float(final_xp), 1.2)


func _ready() -> void:
	font = UI_FONT
	if not AdManager.rewarded_ad_completed.is_connected(_on_rewarded_ad_completed):
		AdManager.rewarded_ad_completed.connect(_on_rewarded_ad_completed)
	selected_class = clampi(int(get_tree().get_meta("selected_class", 0)), 0, 2)
	player_team = clampi(int(get_tree().get_meta("last_match_team", get_tree().get_meta("selected_team", 0))), 0, 1)
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
	MetaProgression.record_match_result(player_won, player_place, match_stats, final_xp, final_shards)
	_grant_match_reward_to_server(final_shards)
	if not rewards_committed:
		MetaProgression.add_character_xp(CHARACTER_KEYS[selected_class], final_xp)
		rewards_committed = true
	_build_screen()
	_animate_rewards()
	if player_won:
		_play_victory_celebration()
	else:
		_play_defeat_stinger()


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

	var placement_text := "ВЫ ЛУЧШИЙ ИГРОК МАТЧА!" if player_is_mvp else "ВАШЕ МЕСТО: %d" % player_place
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
	content.anchor_bottom = 0.755
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
	portrait.custom_minimum_size = Vector2(0.0, 220.0)
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.clip_contents = true
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_child(portrait)

	var hero_name := _make_label(_get_player_character_name(), 24, PALE)
	hero_name.name = "HeroName"
	portrait_content.add_child(hero_name)
	var hero_level := int(MetaProgression.char_levels.get(CHARACTER_KEYS[selected_class], 1))
	var skin_label := _make_label("Уровень %d" % hero_level, 16, Color(0.72, 0.74, 0.8))
	skin_label.name = "HeroSkin"
	portrait_content.add_child(skin_label)

	var stats_panel := _make_panel(Color(0.3, 0.32, 0.38, 0.9))
	stats_panel.name = "StatisticsPanel"
	stats_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(stats_panel)
	var panel_box := VBoxContainer.new()
	panel_box.name = "StatsPanelBox"
	panel_box.add_theme_constant_override("separation", 8)
	stats_panel.add_child(panel_box)

	var tab_row := HBoxContainer.new()
	tab_row.name = "ResultTabs"
	tab_row.add_theme_constant_override("separation", 4)
	panel_box.add_child(tab_row)
	stats_tab_button = _make_tab_button("СТАТИСТИКА", true)
	stats_tab_button.pressed.connect(_switch_result_tab.bind(false))
	tab_row.add_child(stats_tab_button)
	players_tab_button = _make_tab_button("ИГРОКИ", false)
	players_tab_button.pressed.connect(_switch_result_tab.bind(true))
	tab_row.add_child(players_tab_button)

	stats_scroll = ScrollContainer.new()
	stats_scroll.name = "StatsScroll"
	stats_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_box.add_child(stats_scroll)
	var stats_content := VBoxContainer.new()
	stats_content.name = "StatsContent"
	stats_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_content.add_theme_constant_override("separation", 5)
	stats_scroll.add_child(stats_content)
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	stats_content.add_child(divider)

	var shards_row := HBoxContainer.new()
	shards_row.name = "ShardRewardRow"
	shards_row.add_theme_constant_override("separation", 5)
	shards_reward_label = _make_label("Получено: %d" % final_shards, 17, Color(0.43, 0.84, 1.0))
	shards_reward_label.name = "ShardReward"
	shards_reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	shards_row.add_child(shards_reward_label)
	shards_row.add_child(_shard_icon(18))
	stats_content.add_child(shards_row)
	xp_reward_label = _make_label("Получено: %d опыта" % final_xp, 17, Color(0.62, 0.86, 1.0))
	xp_reward_label.name = "XPReward"
	xp_reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stats_content.add_child(xp_reward_label)

	stats_content.add_child(_make_stat_row("Убийства", str(int(match_stats.get("p_kills", 0)))))
	stats_content.add_child(_make_stat_row("Смерти", str(int(match_stats.get("p_deaths", 0)))))
	stats_content.add_child(_make_stat_row("Нанесенный урон", str(int(round(float(match_stats.get("p_damage", 0.0)))))))
	stats_content.add_child(_make_stat_row("Всего золота", str(int(match_stats.get("p_gold_earned", 0)))))

	double_reward_button = _make_button("", true)
	double_reward_button.name = "DoubleRewardsButton"
	double_reward_button.custom_minimum_size = Vector2(0.0, 40.0)
	double_reward_button.add_theme_font_size_override("font_size", 16)
	double_reward_button.add_theme_color_override("font_color", Color(0.18, 0.11, 0.02))
	double_reward_button.add_theme_color_override("font_hover_color", Color(0.12, 0.075, 0.01))
	double_reward_button.add_theme_color_override("font_pressed_color", Color(0.12, 0.075, 0.01))
	double_reward_button.add_theme_stylebox_override("normal", _ad_reward_button_style(false))
	double_reward_button.add_theme_stylebox_override("hover", _ad_reward_button_style(true))
	double_reward_button.add_theme_stylebox_override("pressed", _ad_reward_button_style(true))
	double_reward_button.pressed.connect(_double_rewards_for_ad)
	stats_content.add_child(double_reward_button)

	players_scroll = ScrollContainer.new()
	players_scroll.name = "PlayersScroll"
	players_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	players_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	players_scroll.visible = false
	panel_box.add_child(players_scroll)
	var players_body := VBoxContainer.new()
	players_body.name = "PlayersContent"
	players_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_body.add_theme_constant_override("separation", 3)
	players_scroll.add_child(players_body)
	_build_players_table(players_body)
	_refresh_reward_ui()
	call_deferred("_start_ad_button_pulse")


func _get_player_character_name() -> String:
	var faction := "Света" if player_team == 0 else "Тьмы"
	var hero := "%s %s" % [CHARACTER_CLASS_NAMES[selected_class], faction]
	var nickname := MetaProgression.player_nickname.strip_edges()
	if nickname.is_empty():
		return hero
	return "%s\n%s" % [nickname, hero]


func _make_stat_row(label_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 32.0)
	row.add_theme_constant_override("separation", 12)
	var name_label := _make_label(label_text, 19, PALE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value_label := _make_label(value_text, 22, GOLD)
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
	button_row.anchor_left = 0.235
	button_row.anchor_top = 0.81
	button_row.anchor_right = 0.765
	button_row.anchor_bottom = 0.94
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 24)
	add_child(button_row)
	var retry_button := _make_button("ИГРАТЬ СНОВА", true)
	retry_button.name = "ReplayButton"
	retry_button.custom_minimum_size = Vector2(220.0, 54.0)
	retry_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	retry_button.pressed.connect(_open_replay)
	button_row.add_child(retry_button)
	var menu_button := _make_button("В ЛОББИ", false)
	menu_button.name = "MenuButton"
	menu_button.custom_minimum_size = Vector2(180.0, 54.0)
	menu_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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


func _shard_icon(icon_size: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = SHARD_ICON
	icon.custom_minimum_size = Vector2(icon_size * 0.7, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


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
	button.custom_minimum_size = Vector2(210.0, 54.0)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 17)
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
	_change_scene(MENU_SCENE)


func _grant_match_reward_to_server(amount: int) -> void:
	if amount <= 0:
		return
	MetaProgression.grant_match_reward(amount)


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
	var previous_shards := final_shards
	var previous_xp := final_xp
	final_xp *= 2
	final_shards *= 2
	MetaProgression.add_character_xp(CHARACTER_KEYS[selected_class], final_xp - previous_xp)
	MetaProgression.add_reward_delta(final_xp - previous_xp, final_shards - previous_shards)
	_grant_match_reward_to_server(final_shards - previous_shards)
	rewards_doubled = true
	_refresh_reward_ui()
	if ad_button_pulse_tween != null and ad_button_pulse_tween.is_running():
		ad_button_pulse_tween.kill()
		double_reward_button.scale = Vector2.ONE


func _refresh_reward_ui() -> void:
	if shards_reward_label != null:
		shards_reward_label.text = "Получено: %d" % final_shards
	if xp_reward_label != null:
		xp_reward_label.text = "Получено: %d опыта" % final_xp
	if double_reward_button == null:
		return
	if rewards_doubled:
		double_reward_button.text = "Награды удвоены"
		double_reward_button.disabled = true
	else:
		double_reward_button.text = "▶ Реклама: награды ×2"
		double_reward_button.disabled = false


func _ad_reward_button_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.72, 0.12) if not hovered else Color(1.0, 0.84, 0.32)
	style.border_color = Color(1.0, 0.9, 0.48)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style

func _start_ad_button_pulse() -> void:
	await get_tree().process_frame
	if double_reward_button == null or rewards_doubled:
		return
	double_reward_button.pivot_offset = double_reward_button.size * 0.5
	ad_button_pulse_tween = create_tween().set_loops()
	ad_button_pulse_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ad_button_pulse_tween.tween_property(double_reward_button, 'scale', Vector2(1.03, 1.03), 0.65)
	ad_button_pulse_tween.tween_property(double_reward_button, 'scale', Vector2.ONE, 0.65)

func _play_victory_celebration() -> void:
	victory_player = AudioStreamPlayer.new()
	victory_player.name = "VictoryFanfare"
	victory_player.stream = VICTORY_SOUND
	victory_player.volume_db = -6.0
	victory_player.bus = "Master"
	victory_player.max_polyphony = 1
	add_child(victory_player)
	victory_player.play()
	_spawn_victory_confetti()


func _play_defeat_stinger() -> void:
	victory_player = AudioStreamPlayer.new()
	victory_player.name = "DefeatStinger"
	victory_player.stream = DEFEAT_SOUND
	victory_player.volume_db = -8.0
	victory_player.bus = "Master"
	victory_player.max_polyphony = 1
	add_child(victory_player)
	victory_player.play()

func _spawn_victory_confetti() -> void:
	var particles := CPUParticles2D.new()
	particles.name = 'VictoryConfetti'
	particles.z_index = 5
	particles.amount = 110
	particles.lifetime = 4.0
	particles.one_shot = true
	particles.explosiveness = 0.35
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var viewport_size := get_viewport_rect().size
	particles.emission_rect_extents = Vector2(viewport_size.x * 0.5 + 12.0, 10.0)
	particles.position = Vector2(viewport_size.x * 0.5, -8.0)
	particles.direction = Vector2(0.0, 1.0)
	particles.spread = 18.0
	particles.initial_velocity_min = 35.0
	particles.initial_velocity_max = 105.0
	particles.gravity = Vector2(0.0, 95.0)
	particles.damping_min = 2.0
	particles.damping_max = 7.0
	particles.scale_amount_min = 0.4
	particles.scale_amount_max = 1.0
	particles.color = Color(1.0, 0.76, 0.22, 0.95)
	particles.texture = _make_confetti_texture()
	particles.emitting = true
	add_child(particles)

func _make_confetti_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 16
	texture.height = 16
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture

func _change_scene(scene_path: String) -> void:
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Failed to open %s: %s" % [scene_path, error_string(error)])
