extends Control

const CHARACTER_ART := [
	"res://assets/ui/heroes/warrior_keyart.webp",
	"res://assets/ui/heroes/mage_keyart.webp",
	"res://assets/ui/heroes/archer_keyart.webp",
]
const CHARACTER_CLASS_NAMES := ["Воин", "Маг", "Охотница"]
const CHARACTER_KEYS := ["warrior", "mage", "fairy"]
const SkinCatalog = preload("res://scripts/skin_catalog.gd")
const REPLAY_SCENE := "res://scenes/LoadingScreen.tscn"
const MENU_SCENE := "res://scenes/Lobby.tscn"
const GOLD := Color(0.94, 0.78, 0.43)
const PALE := Color(0.9, 0.91, 0.95)

const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const UI_FONT_BOLD := preload("res://assets/fonts/Philosopher-Bold.ttf")
const SHARD_ICON: Texture2D = preload("res://ui/icons/sky_shard.png")
const VICTORY_SOUND: AudioStream = preload("res://audio/sfx/misc_start_kenney_hit_11.ogg")
const DEFEAT_SOUND: AudioStream = preload("res://audio/sfx/fairy_death_scream.mp3")
const TOUCH_SCROLL := preload("res://scripts/touch_scroll.gd")

var font: FontFile
var selected_class := 0
var player_team := 0
var player_won := true
var match_aborted := false
var score: Array = [0, 0]
var match_stats: Dictionary = {}
var player_place := 4
var player_is_mvp := false
var final_shards := 0
var final_xp := 0
var rewards_doubled := false
var rewards_committed := false
var server_match := false
# x2 (rewarded ad) bookkeeping. The bonus is a second, separately idempotent
# server payout for a match whose base reward must already be claimed. It is
# held until the base answer arrives, so the bonus can never be rejected as
# «Reward already claimed» while the screen still claims success.
var reward_room := 0
var base_reward_settled := false
var base_reward_ok := false
var pending_bonus := false
var ad_in_progress := false
var leaving_results := false
var replay_button: Button
var menu_button: Button
var double_reward_button: Button
var ad_error_label: Label
var ad_error_tween: Tween
var last_ad_error_msec := -30000
var shards_reward_label: Label
var xp_reward_label: Label
var stats_scroll: ScrollContainer
var players_scroll: ScrollContainer
var left_column: VBoxContainer
var portrait_panel: PanelContainer
var stats_tab_button: Button
var players_tab_button: Button
var ad_button_pulse_tween: Tween
var victory_player: AudioStreamPlayer
var reward_banner: Label
var reward_banner_tween: Tween
var entry_leveled_up := false
var entry_level := 1


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
	# Desktop has the room: taller rows read better and fill the panel.
	var row_pad := 5.0 if DeviceProfile.mobile_ui else 9.0
	style.content_margin_top = row_pad
	style.content_margin_bottom = row_pad
	row_panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row_panel.add_child(row)

	var damage := int(entry.get("damage", 0))
	var name_text := String(entry.get("name", ">"))
	if bool(entry.get("is_bot", false)):
		name_text = "БОТ · " + name_text
	if damage > 0 and damage == best_damage:
		name_text = "* " + name_text
	var name_cell := _table_cell(name_text, 14, GOLD if is_self else PALE, 0.0, HORIZONTAL_ALIGNMENT_LEFT)
	name_cell.clip_text = true
	row.add_child(name_cell)
	row.add_child(_table_cell("%d/%d" % [int(entry.get("kills", 0)), int(entry.get("deaths", 0))], 14, Color(0.8, 0.85, 0.95), 58.0, HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(_table_cell(str(damage), 14, Color(1.0, 0.8, 0.5), 74.0, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_table_cell(str(int(entry.get("crystals", 0))), 14, Color(0.43, 0.84, 1.0), 52.0, HORIZONTAL_ALIGNMENT_RIGHT))
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
	button.add_theme_font_size_override("font_size", _fs(18))
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
	_schedule_players_fit()


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
			shards_reward_label.text = str(int(round(value)))
	, 0.0, float(final_shards), 0.9)
	var xp_tween := create_tween()
	xp_tween.tween_method(func(value: float) -> void:
		if is_instance_valid(xp_reward_label):
			xp_reward_label.text = str(int(round(value)))
	, 0.0, float(final_xp), 1.2)


func _ready() -> void:
	font = UI_FONT
	AdManager.begin_results()
	# Refresh server-owned matches_played/novice/last_interstitial_at before
	# the player can press «В лобби»; the timing rules use those fields.
	if MetaProgression.player_id > 0:
		MetaProgression.load_profile(MetaProgression.player_id)
	if not AdManager.rewarded_ad_completed.is_connected(_on_rewarded_ad_completed):
		AdManager.rewarded_ad_completed.connect(_on_rewarded_ad_completed)
	selected_class = clampi(int(get_tree().get_meta("selected_class", 0)), 0, 2)
	player_team = clampi(int(get_tree().get_meta("last_match_team", get_tree().get_meta("selected_team", 0))), 0, 1)
	var has_match := get_tree().has_meta("last_match_score") and get_tree().has_meta("last_match_stats")
	player_won = bool(get_tree().get_meta("last_match_won", true)) if has_match else false
	match_aborted = bool(get_tree().get_meta("last_match_aborted", false))
	score = get_tree().get_meta("last_match_score", [0, 0])
	match_stats = get_tree().get_meta("last_match_stats", {})
	player_place = maxi(1, int(get_tree().get_meta("last_match_place", 4)))
	player_is_mvp = bool(get_tree().get_meta("last_match_is_mvp", false))
	if player_is_mvp:
		player_place = 1
	var match_room := int(get_tree().get_meta("last_match_room", 0))
	server_match = has_match and not match_aborted and match_room > 0
	reward_room = match_room
	# Listen before the base reward is sent: its answer decides when the x2
	# bonus may go out (see _on_rewarded_ad_completed). Connected for every
	# match — the payout itself is what decides, not the screen flags.
	if not NetworkClient.match_reward_settled.is_connected(_on_results_reward_settled):
		NetworkClient.match_reward_settled.connect(_on_results_reward_settled)
	var kills := int(match_stats.get("p_kills", 0))
	var shells_destroyed := int(match_stats.get("p_shells_destroyed", 0))
	var crystals_delivered := int(match_stats.get("p_crystals", 0))
	var character_key: String = str(CHARACTER_KEYS[selected_class])
	if has_match and match_aborted:
		# An interrupted match gives no rewards: no shards, no XP and no level
		# up. Otherwise leaving a losing match would be more profitable than
		# finishing it. The match is not counted as a win/loss either.
		final_shards = 0
		final_xp = 0
		entry_level = int(MetaProgression.char_levels.get(character_key, 1))
		entry_leveled_up = false
		rewards_committed = true
	elif has_match:
		final_shards = 5 if player_won and player_is_mvp else 3 if player_won or player_is_mvp else 1
		final_xp = kills * 10 + shells_destroyed * 25 + crystals_delivered * 25 + (50 if player_won else 20)
		MetaProgression.record_match_result(player_won, player_place, match_stats, final_xp, final_shards)
		if not rewards_committed:
			if server_match:
				# XP and the match payout are applied by the server atomically.
				_grant_match_reward_to_server(final_shards, false, final_xp, character_key)
			else:
				var level_before := int(MetaProgression.char_levels.get(character_key, 1))
				MetaProgression.add_character_xp(character_key, final_xp)
				entry_level = int(MetaProgression.char_levels.get(character_key, level_before))
				entry_leveled_up = entry_level > level_before
				_grant_match_reward_to_server(final_shards)
			rewards_committed = true
	else:
		final_shards = 0
		final_xp = 0
	_build_screen()
	_build_reward_banner()
	if not resized.is_connected(_on_results_resized):
		resized.connect(_on_results_resized)
	_schedule_players_fit()
	_animate_rewards()
	if match_aborted:
		_play_defeat_stinger()
	elif player_won:
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
	var mobile := DeviceProfile.mobile_ui
	var title_text := "МАТЧ ПРЕРВАН" if match_aborted else ("ПОБЕДА" if player_won else "ПОРАЖЕНИЕ")
	var title_color := Color(0.92, 0.66, 0.3) if match_aborted else (GOLD if player_won else Color(0.9, 0.3, 0.29))
	var title := _make_label(title_text, 34 if mobile else 68, title_color)
	title.name = "ResultTitle"
	title.anchor_left = 0.08
	title.anchor_top = 0.0 if mobile else 0.035
	title.anchor_right = 0.92
	title.anchor_bottom = 0.112 if mobile else 0.145
	add_child(title)

	var subtitle_text := "ИТОГИ МАТЧА  ·  СВЕТ %d : %d ТЬМА" % [int(score[0]), int(score[1])]
	var end_reason := String(get_tree().get_meta("last_match_reason", "")).strip_edges()
	if not end_reason.is_empty():
		subtitle_text += "  ·  " + end_reason
	var subtitle := _make_label(subtitle_text, 16 if mobile else 17, Color(0.76, 0.78, 0.84))
	subtitle.name = "MatchSummary"
	subtitle.anchor_left = 0.08
	subtitle.anchor_top = 0.112 if mobile else 0.145
	subtitle.anchor_right = 0.92
	subtitle.anchor_bottom = 0.17 if mobile else 0.188
	add_child(subtitle)

	var placement_text := "МАТЧ НЕ ЗАСЧИТАН" if match_aborted else ("ВЫ ЛУЧШИЙ ИГРОК МАТЧА!" if player_is_mvp else "ВАШЕ МЕСТО: %d" % player_place)
	var placement_color := Color(0.72, 0.78, 0.88) if match_aborted else (GOLD if player_is_mvp else PALE)
	var placement := _make_label(placement_text, 22 if mobile else 29, placement_color)
	placement.name = "PlayerPlacement"
	placement.anchor_left = 0.08
	placement.anchor_top = 0.172 if mobile else 0.192
	placement.anchor_right = 0.92
	placement.anchor_bottom = 0.238 if mobile else 0.246
	add_child(placement)


func _build_content() -> void:
	var mobile := DeviceProfile.mobile_ui
	var content := HBoxContainer.new()
	content.name = "ResultsContent"
	content.anchor_left = 0.05 if mobile else 0.12
	content.anchor_top = 0.242 if mobile else 0.27
	content.anchor_right = 0.95 if mobile else 0.88
	# The lobby button now lives at the bottom of the left column, so the
	# content can use the strip it used to reserve for the button. That extra
	# height is what lets the players table show a full 3v3 without scrolling.
	content.anchor_bottom = 0.945 if mobile else 0.94
	content.add_theme_constant_override("separation", 16 if mobile else 30)
	add_child(content)

	# Left column: portrait above, «В лобби» below it.
	left_column = VBoxContainer.new()
	left_column.name = "ResultsLeftColumn"
	left_column.custom_minimum_size = Vector2(280.0 if mobile else 350.0, 0.0)
	left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.add_theme_constant_override("separation", 6 if mobile else 14)
	content.add_child(left_column)

	portrait_panel = _make_panel(Color(0.43, 0.39, 0.3, 0.9))
	portrait_panel.name = "PortraitPanel"
	portrait_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.add_child(portrait_panel)
	var portrait_content := VBoxContainer.new()
	portrait_content.name = "PortraitContent"
	portrait_content.add_theme_constant_override("separation", 4 if mobile else 10)
	portrait_panel.add_child(portrait_content)

	var portrait_frame := PanelContainer.new()
	portrait_frame.name = "PortraitFrame"
	portrait_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_frame.add_theme_stylebox_override("panel", _panel_style(Color(0.19, 0.21, 0.27), Color(0.01, 0.015, 0.025)))
	portrait_content.add_child(portrait_frame)
	var portrait := TextureRect.new()
	portrait.name = "HeroPortrait"
	var results_skin := SkinCatalog.get_item(MetaProgression.get_equipped_skin(CHARACTER_KEYS[selected_class]))
	var legendary_skin := _is_legendary_skin(results_skin)
	var portrait_path := String(CHARACTER_ART[selected_class])
	var showing_shop_card := false
	if not results_skin.is_empty():
		# A legendary skin shows the same 2D card as the shop, not the tiny
		# icon or the 3D render: the card is the art the player bought.
		var skin_paths: Array[String] = []
		if legendary_skin:
			skin_paths.append(String(results_skin.get("card", "")))
		skin_paths.append(String(results_skin.get("icon", "")))
		for path in skin_paths:
			if path.is_empty():
				continue
			if load(path) is Texture2D:
				portrait_path = path
				showing_shop_card = legendary_skin and path == String(results_skin.get("card", ""))
				break
	var portrait_source := load(portrait_path) as Texture2D
	if portrait_source != null:
		# Full 2D key art: the old atlas cropped only the top 70% and used
		# a 3D-render portrait, which read as a model rather than game art.
		portrait.texture = portrait_source
	portrait.custom_minimum_size = Vector2(0.0, 70.0 if mobile else 200.0)
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# The shop card is a 3:4 poster: show all of it instead of cropping the
	# hunter's hood / the barbarian's helmet off the top.
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if showing_shop_card else TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.clip_contents = true
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_child(portrait)

	if legendary_skin:
		portrait_content.add_child(_make_legend_badge())

	var hero_name := _make_label(_get_player_character_name(), 18 if mobile else 24, PALE)
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

	stats_scroll = TOUCH_SCROLL.new()
	stats_scroll.name = "StatsScroll"
	stats_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_box.add_child(stats_scroll)
	# The vertical scrollbar draws over the content on the right edge; keep
	# the numbers clear of it.
	var stats_margin := MarginContainer.new()
	stats_margin.name = "StatsMargin"
	stats_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_margin.add_theme_constant_override("margin_right", 18)
	stats_scroll.add_child(stats_margin)
	var stats_content := VBoxContainer.new()
	stats_content.name = "StatsContent"
	stats_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_content.add_theme_constant_override("separation", 5)
	stats_margin.add_child(stats_content)
	var reward_line := HBoxContainer.new()
	reward_line.name = "RewardLine"
	reward_line.add_theme_constant_override("separation", 4)
	reward_line.add_child(_make_label("Получено осколков", 16, Color(0.43, 0.84, 1.0)))
	shards_reward_label = _make_bold_label(str(final_shards), 22, Color(0.43, 0.84, 1.0))
	shards_reward_label.name = "ShardReward"
	shards_reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	reward_line.add_child(shards_reward_label)
	reward_line.add_child(_shard_icon(18))
	reward_line.add_child(_make_label("  ·  ", 18, Color(0.6, 0.64, 0.72)))
	reward_line.add_child(_make_label("Получено опыта", 16, Color(0.62, 0.86, 1.0)))
	xp_reward_label = _make_bold_label(str(final_xp), 22, Color(0.62, 0.86, 1.0))
	xp_reward_label.name = "XPReward"
	xp_reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	reward_line.add_child(xp_reward_label)
	if match_aborted:
		reward_line.visible = false
		var no_rewards := _make_label("Награды не начислены", 18, Color(0.78, 0.8, 0.86))
		no_rewards.name = "NoRewards"
		panel_box.add_child(no_rewards)
	else:
		panel_box.add_child(reward_line)
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	panel_box.add_child(divider)

	stats_content.add_child(_make_stat_row("Убийства", str(int(match_stats.get("p_kills", 0)))))
	stats_content.add_child(_make_stat_row("Смерти", str(int(match_stats.get("p_deaths", 0)))))
	stats_content.add_child(_make_stat_row("Нанесенный урон", str(int(round(float(match_stats.get("p_damage", 0.0)))))))
	stats_content.add_child(_make_stat_row("Всего золота", str(int(match_stats.get("p_gold_earned", 0)))))

	double_reward_button = _make_button("", true)
	double_reward_button.name = "DoubleRewardsButton"
	double_reward_button.custom_minimum_size = Vector2(300.0 if DeviceProfile.mobile_ui else 420.0, 40.0)
	double_reward_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	double_reward_button.add_theme_font_size_override("font_size", _fs(16))
	double_reward_button.add_theme_color_override("font_color", Color(0.18, 0.11, 0.02))
	double_reward_button.add_theme_color_override("font_hover_color", Color(0.12, 0.075, 0.01))
	double_reward_button.add_theme_color_override("font_pressed_color", Color(0.12, 0.075, 0.01))
	double_reward_button.add_theme_stylebox_override("normal", _ad_reward_button_style(false))
	double_reward_button.add_theme_stylebox_override("hover", _ad_reward_button_style(true))
	double_reward_button.add_theme_stylebox_override("pressed", _ad_reward_button_style(true))
	double_reward_button.pressed.connect(_double_rewards_for_ad)
	panel_box.add_child(double_reward_button)
	ad_error_label = _make_label("", 13, Color(0.72, 0.76, 0.86, 0.9))
	ad_error_label.name = "AdErrorLabel"
	ad_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ad_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ad_error_label.visible = false
	panel_box.add_child(ad_error_label)
	# Rewards and the x2 button stay pinned above the scrollable stats list.
	# On an aborted match the reward row is replaced by "Награды не начислены"
	# and is not a child of panel_box; never move a foreign node.
	if reward_line.get_parent() == panel_box:
		panel_box.move_child(reward_line, 1)
	if divider.get_parent() == panel_box:
		panel_box.move_child(divider, 2)
	if double_reward_button.get_parent() == panel_box:
		panel_box.move_child(double_reward_button, 3)
	if ad_error_label.get_parent() == panel_box:
		panel_box.move_child(ad_error_label, 4)

	players_scroll = TOUCH_SCROLL.new()
	players_scroll.name = "PlayersScroll"
	players_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	players_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	players_scroll.visible = false
	panel_box.add_child(players_scroll)
	var players_margin := MarginContainer.new()
	players_margin.name = "PlayersMargin"
	players_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_margin.add_theme_constant_override("margin_right", 18)
	players_scroll.add_child(players_margin)
	var players_body := VBoxContainer.new()
	players_body.name = "PlayersContent"
	players_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_body.add_theme_constant_override("separation", 4)
	players_margin.add_child(players_body)
	_build_players_table(players_body)
	_refresh_reward_ui()
	call_deferred("_start_ad_button_pulse")


func _is_legendary_skin(item: Dictionary) -> bool:
	if item.is_empty():
		return false
	if String(item.get("tier", "")).to_lower().contains("легенд"):
		return true
	# The shop card exists only for the legendary skins, so it is a safe
	# fallback if the tier wording ever changes.
	return not String(item.get("card", "")).is_empty()


func _make_legend_badge() -> Control:
	var row := HBoxContainer.new()
	row.name = "LegendBadge"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_legend_rule())
	var label := _make_bold_label("ЛЕГЕНДА", 12, Color(GOLD.r, GOLD.g, GOLD.b, 0.95))
	label.name = "LegendLabel"
	row.add_child(label)
	row.add_child(_legend_rule())
	return row


func _legend_rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(26.0, 1.0)
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.45)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _on_results_resized() -> void:
	_schedule_players_fit()


func _schedule_players_fit() -> void:
	# Containers settle their sizes after this frame; wait for that before
	# deciding whether the table still needs a scrollbar.
	_refresh_players_fit()


func _refresh_players_fit() -> void:
	await get_tree().process_frame
	_update_players_scroll_mode()


func _update_players_scroll_mode() -> void:
	if players_scroll == null or not is_instance_valid(players_scroll):
		return
	if not players_scroll.visible or players_scroll.size.y <= 0.0:
		return
	var body := players_scroll.get_node_or_null("PlayersMargin/PlayersContent") as Control
	if body == null:
		return
	var content_height := body.get_combined_minimum_size().y
	var fits := content_height <= players_scroll.size.y + 0.5
	# On desktop a full 3v3 fits, so the table is simply a plain list with no
	# scrollbar. A phone in landscape can still overflow; scrolling stays
	# there only as the fallback.
	players_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if fits else ScrollContainer.SCROLL_MODE_AUTO


func _get_player_character_name() -> String:
	var faction := "Света" if player_team == 0 else "Тьмы"
	# A skin is cosmetic: the class in the results stays Воин/Маг/Охотница.
	var display_class: String = String(CHARACTER_CLASS_NAMES[selected_class])
	var hero := "%s %s" % [display_class, faction]
	var nickname := MetaProgression.player_nickname.strip_edges()
	if nickname.is_empty():
		return hero
	return "%s\n%s" % [nickname, hero]


func _make_bold_label(text: String, font_size: int, color: Color) -> Label:
	var label := _make_label(text, font_size, color)
	label.add_theme_font_override("font", UI_FONT_BOLD)
	return label


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
	var mobile := DeviceProfile.mobile_ui
	# Entering a new match is done from the lobby only; no "play again" shortcut
	# here so a finished/aborted match cannot chain straight into another one.
	var lobby_button := _make_button("В ЛОББИ", true)
	lobby_button.name = "MenuButton"
	lobby_button.custom_minimum_size = Vector2(0.0, 44.0 if mobile else 54.0)
	lobby_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lobby_button.pressed.connect(_open_menu)
	menu_button = lobby_button
	if left_column != null and is_instance_valid(left_column):
		# Directly under the portrait, in the left column: no longer floating
		# in the middle of the screen under the stats panel.
		left_column.add_child(lobby_button)
	else:
		lobby_button.custom_minimum_size = Vector2(220.0, 48.0 if mobile else 54.0)
		lobby_button.anchor_left = 0.05 if mobile else 0.12
		lobby_button.anchor_top = 0.87
		lobby_button.anchor_right = 0.12 if mobile else 0.35
		lobby_button.anchor_bottom = 0.95
		add_child(lobby_button)


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
	label.add_theme_font_size_override("font_size", _fs(font_size))
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
	button.add_theme_font_size_override("font_size", _fs(17))
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


func _can_show_results_interstitial() -> bool:
	# Ads belong to a real, finished online match. An interrupted match, a
	# tutorial or an offline fight must never end with an ad.
	if not server_match or match_aborted:
		return false
	return AdManager.can_show_interstitial_after_results()


func _open_replay() -> void:
	if leaving_results or ad_in_progress:
		return
	leaving_results = true
	if replay_button != null:
		replay_button.disabled = true
	if menu_button != null:
		menu_button.disabled = true
	_flush_pending_bonus_before_leaving()
	var show_interstitial := _can_show_results_interstitial()
	if show_interstitial:
		await AdManager.maybe_show_interstitial_after_results()
	_change_scene(REPLAY_SCENE)


func _open_menu() -> void:
	if leaving_results or ad_in_progress:
		return
	leaving_results = true
	if replay_button != null:
		replay_button.disabled = true
	if menu_button != null:
		menu_button.disabled = true
	_flush_pending_bonus_before_leaving()
	var show_interstitial := _can_show_results_interstitial()
	if show_interstitial:
		await AdManager.maybe_show_interstitial_after_results()
	_change_scene(MENU_SCENE)


func _grant_match_reward_to_server(amount: int, bonus := false, xp := 0, character := "") -> void:
	if amount <= 0:
		return
	MetaProgression.grant_match_reward(amount, bonus, xp, character)


func _double_rewards_for_ad() -> void:
	if rewards_doubled or ad_in_progress or double_reward_button == null:
		return
	if not Platform.is_rewarded_available():
		_refresh_reward_ui()
		return
	ad_in_progress = true
	double_reward_button.disabled = true
	double_reward_button.text = "Реклама..."
	var rewarded: bool = await AdManager.show_rewarded_ad()
	if not rewarded and not rewards_doubled:
		ad_in_progress = false
		_refresh_reward_ui()
		# The raw code/detail goes to the log only; the player sees a short,
		# quiet line under the button and can try again later.
		print("[Ads] results x2 failed error=%s detail=%s" % [
			Platform.get_last_ad_error(), Platform.get_last_ad_detail(),
		])
		_show_ad_error_hint()


func _show_ad_error_hint() -> void:
	if ad_error_label == null:
		return
	var now := Time.get_ticks_msec()
	if now - last_ad_error_msec < 30000:
		return
	last_ad_error_msec = now
	ad_error_label.text = "Реклама временно недоступна. Попробуйте позже."
	ad_error_label.visible = true
	if ad_error_tween != null and ad_error_tween.is_valid():
		ad_error_tween.kill()
	ad_error_tween = create_tween()
	ad_error_tween.tween_interval(3.5)
	ad_error_tween.tween_callback(func() -> void: ad_error_label.visible = false)


func _on_rewarded_ad_completed() -> void:
	if not ad_in_progress or rewards_doubled:
		return
	ad_in_progress = false
	if ad_error_label != null:
		ad_error_label.visible = false
	if ad_error_tween != null and ad_error_tween.is_valid():
		ad_error_tween.kill()
	var previous_shards := final_shards
	var previous_xp := final_xp
	final_xp *= 2
	final_shards *= 2
	var character_key: String = str(CHARACTER_KEYS[selected_class])
	if server_match:
		# The server owns the x2 payout and applies the stored base reward a
		# second time, exactly once per match (rewarded_bonus). The bonus is a
		# separate request that the server accepts only after the base reward
		# is stored: sending it while the base is still in flight was answered
		# with «Reward already claimed», so the banner said x2 while nothing
		# was paid. Hold the bonus until the base answer arrives.
		pending_bonus = true
		if base_reward_settled:
			_send_ad_bonus()
		else:
			print("[Ads] x2 waiting for the base reward room=%d" % _results_room_id())
	else:
		MetaProgression.add_character_xp(character_key, final_xp - previous_xp)
		_grant_match_reward_to_server(final_shards - previous_shards, true, final_xp - previous_xp, character_key)
	MetaProgression.add_reward_delta(final_xp - previous_xp, final_shards - previous_shards)
	rewards_doubled = true
	_refresh_reward_ui()
	_play_reward_fanfare()
	# The level-up banner is shown once, in the lobby. Showing it here, again
	# after the ad and again in the lobby was three notices for one level.
	_show_reward_banner("×2  НАГРАДЫ УДВОЕНЫ", 2.2)
	if ad_button_pulse_tween != null and ad_button_pulse_tween.is_running():
		ad_button_pulse_tween.kill()
		double_reward_button.scale = Vector2.ONE


func _results_room_id() -> int:
	if reward_room > 0:
		return reward_room
	return int(get_tree().get_meta("last_match_room", 0))


func _send_ad_bonus() -> void:
	if not pending_bonus:
		return
	pending_bonus = false
	var character_key: String = str(CHARACTER_KEYS[selected_class])
	# final_shards/final_xp are already doubled, and only here: the screen
	# doubles them once, in _on_rewarded_ad_completed, so the bonus is sent
	# exactly once with the exact doubled total.
	_grant_match_reward_to_server(final_shards, true, final_xp, character_key)
	print("[Ads] x2 bonus sent room=%d shards=%d xp=%d base_ok=%s" % [
		_results_room_id(), final_shards, final_xp, base_reward_ok,
	])


func _on_results_reward_settled(success: bool, payload: Dictionary, _code: int, error: String, _profile: Dictionary) -> void:
	var room_id := int(payload.get("room_id", 0))
	var own_room := _results_room_id()
	# Another match on a shared screen must not gate this one.
	if room_id > 0 and own_room > 0 and room_id != own_room:
		return
	if bool(payload.get("bonus", false)):
		if success:
			print("[Ads] x2 bonus confirmed room=%d" % room_id)
		else:
			# MetaProgression keeps a rejected bonus in its outbox and retries
			# it after the base reward, so the x2 is not lost here.
			print("[Ads] x2 bonus not confirmed room=%d error=%s (kept for retry)" % [room_id, error])
		return
	base_reward_settled = true
	base_reward_ok = success
	if not pending_bonus:
		return
	if success:
		_send_ad_bonus()
		return
	# The base answer is an error (network drop, server refuse). The bonus is
	# already owed to the player who watched the ad: send it now so
	# MetaProgression records it in the outbox and retries base then bonus in
	# the original order.
	print("[Ads] base reward failed room=%d error=%s; queuing the x2" % [room_id, error])
	_send_ad_bonus()


func _flush_pending_bonus_before_leaving() -> void:
	# Leaving the results before the base answer arrives must not drop the
	# bonus: MetaProgression keeps it queued behind the base reward.
	if pending_bonus:
		print("[Ads] leaving results with the x2 still waiting room=%d" % _results_room_id())
		_send_ad_bonus()


func _build_reward_banner() -> void:
	reward_banner = _make_label("", 42, GOLD)
	reward_banner.name = "RewardBanner"
	reward_banner.anchor_left = 0.5
	reward_banner.anchor_right = 0.5
	reward_banner.anchor_top = 0.5
	reward_banner.anchor_bottom = 0.5
	reward_banner.offset_left = -370.0
	reward_banner.offset_right = 370.0
	reward_banner.offset_top = -70.0
	reward_banner.offset_bottom = 30.0
	reward_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reward_banner.add_theme_font_override("font", UI_FONT_BOLD)
	reward_banner.add_theme_font_size_override("font_size", _fs(30))
	# The old position sat exactly on top of "ВЫ ЛУЧШИЙ ИГРОК МАТЧА!".
	# Move it to the middle and give it a solid dark plate.
	reward_banner.add_theme_stylebox_override("normal", _panel_style(GOLD, Color(0.015, 0.018, 0.03, 0.94)))
	reward_banner.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	reward_banner.add_theme_constant_override("shadow_offset_x", 3)
	reward_banner.add_theme_constant_override("shadow_offset_y", 3)
	reward_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reward_banner.z_index = 90
	reward_banner.visible = false
	add_child(reward_banner)


func _show_reward_banner(text: String, hold_seconds: float) -> void:
	if reward_banner == null or not is_instance_valid(reward_banner):
		return
	if reward_banner_tween != null and reward_banner_tween.is_running():
		reward_banner_tween.kill()
	reward_banner.text = text
	reward_banner.visible = true
	reward_banner.modulate.a = 0.0
	reward_banner.scale = Vector2(0.72, 0.72)
	reward_banner.pivot_offset = Vector2(370.0, 50.0)
	reward_banner_tween = create_tween()
	reward_banner_tween.tween_property(reward_banner, "modulate:a", 1.0, 0.16)
	reward_banner_tween.parallel().tween_property(reward_banner, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reward_banner_tween.tween_interval(maxf(0.4, hold_seconds))
	reward_banner_tween.tween_property(reward_banner, "modulate:a", 0.0, 0.35)
	reward_banner_tween.tween_callback(func() -> void:
		if reward_banner != null and is_instance_valid(reward_banner):
			reward_banner.visible = false
	)


func _play_reward_fanfare() -> void:
	var player := AudioStreamPlayer.new()
	player.name = "RewardFanfare"
	player.stream = VICTORY_SOUND
	player.volume_db = -1.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _play_level_up_chime() -> void:
	var player := AudioStreamPlayer.new()
	player.name = "LevelUpChime"
	player.stream = preload("res://assets/audio/Soundza_Game_SFX_Pack/jingles_stingers/level_up_chime.mp3")
	player.volume_db = -2.0
	player.pitch_scale = 1.04
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _refresh_reward_ui() -> void:
	if shards_reward_label != null:
		shards_reward_label.text = str(final_shards)
	if xp_reward_label != null:
		xp_reward_label.text = str(final_xp)
	if double_reward_button == null:
		return
	if match_aborted or not Platform.is_rewarded_available():
		# No real rewarded adapter: never promise an ad reward that cannot be
		# delivered. The consolation for an interrupted match stays fixed too.
		double_reward_button.visible = false
		if ad_error_label != null:
			ad_error_label.visible = false
		return
	double_reward_button.visible = true
	if rewards_doubled:
		double_reward_button.text = "Награды удвоены"
		double_reward_button.disabled = true
	else:
		double_reward_button.text = "Получить x2 за рекламу"
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
	if double_reward_button == null or rewards_doubled or not double_reward_button.visible:
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


func _fs(size: int) -> int:
	if DeviceProfile.mobile_ui:
		return maxi(size, 18)
	return size
