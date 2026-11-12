extends Control

const BG: Texture2D = preload('res://assets/ui/loading_bg.png')
const LOGO: Texture2D = preload('res://ui/logo.png')
const WARRIOR: Texture2D = preload('res://ui/portraits/warrior_portrait.png')
const MAGE: Texture2D = preload('res://ui/portraits/mage_portrait.png')
const FAIRY: Texture2D = preload('res://ui/portraits/fairy_portrait.png')
const MATCH_PATH := 'res://scenes/Main.tscn'
const SEARCH_SECONDS := 15.0
const SLOTS_PER_TEAM := 3
const SIMULATED_TARGET := 4
const FONT: FontFile = preload('res://assets/fonts/Philosopher-Regular.ttf')
var team_slots: Array = [[], []]
var searching_spinners: Array[Label] = []
var progress_bar: ProgressBar
var search_label: Label
var connection_hint: Label
var tip_label: Label
var found_count_label: Label
var elapsed := 0.0
var next_player_time := 1.2
var simulated_players_added := 0
var tip_timer := 0.0
var tip_index := 0
var players: Array = []
var is_1v1 := false
var fill_with_bots := false
var no_network := false
var transition_started := false
var match_scene: PackedScene
var load_failed := false
var network_flow := false
var network_player_slots: Dictionary = {}
var back_button: Button

func _ready() -> void:
	randomize()
	network_flow = bool(get_tree().get_meta('network_play', false))
	_build_screen()
	_start_match_scene_loading()
	if network_flow:
		_start_network_flow()
	else:
		_use_bot_fallback()
	search_label.text = '\u041f\u043e\u0438\u0441\u043a \u0438\u0433\u0440\u043e\u043a\u043e\u0432...'
	tip_label.text = TIPS[0]


func _start_network_flow() -> void:
	no_network = false
	fill_with_bots = true
	connection_hint.text = '\u041f\u043e\u0434\u043a\u043b\u044e\u0447\u0430\u0435\u043c\u0441\u044f \u043a \u0441\u0435\u0440\u0432\u0435\u0440\u0443...'
	if not NetworkManager.connection_succeeded.is_connected(_on_network_connected):
		NetworkManager.connection_succeeded.connect(_on_network_connected)
	if not NetworkManager.connection_failed.is_connected(_on_network_failed):
		NetworkManager.connection_failed.connect(_on_network_failed)
	if not NetworkManager.remote_player_joined.is_connected(_on_network_player_joined):
		NetworkManager.remote_player_joined.connect(_on_network_player_joined)
	if not NetworkManager.match_started.is_connected(_on_network_match_started):
		NetworkManager.match_started.connect(_on_network_match_started)
	var hero_class := clampi(int(get_tree().get_meta('selected_class', 0)), 0, 2)
	var error := NetworkManager.connect_to_server(
		hero_class,
		0,
		MetaProgression.player_nickname,
		MetaProgression.player_id
	)
	if error != OK:
		_on_network_failed('Не удалось начать подключение')


func _on_network_connected() -> void:
	if transition_started:
		return
	connection_hint.text = '\u041f\u043e\u0438\u0441\u043a \u0438\u0433\u0440\u043e\u043a\u043e\u0432...'


func _on_network_player_joined(player_id: int, info: Dictionary) -> void:
	if transition_started or network_player_slots.has(player_id):
		return
	var team := clampi(int(info.get('team', 0)), 0, 1)
	var slot_index := -1
	for index in range(SLOTS_PER_TEAM):
		if team_slots[team][index]['state'] == 'searching':
			slot_index = index
			break
	if slot_index < 0:
		for other_team in range(2):
			for index in range(SLOTS_PER_TEAM):
				if team_slots[other_team][index]['state'] == 'searching':
					team = other_team
					slot_index = index
					break
			if slot_index >= 0:
				break
	if slot_index < 0:
		return
	var class_index := clampi(int(info.get('class', 0)), 0, 2)
	var player_name := String(info.get('name', 'Игрок'))
	_set_slot_entry(team, slot_index, player_name, class_index, false)
	network_player_slots[player_id] = true


func _on_network_match_started(room_id: int, _host_id: int, players: Array) -> void:
	if transition_started:
		return
	transition_started = true
	network_player_slots.clear()
	for team_index in range(2):
		for slot_index in range(SLOTS_PER_TEAM):
			var slot: Dictionary = team_slots[team_index][slot_index]
			slot['state'] = 'searching'
			slot['name'].text = ''
			slot['portrait'].visible = false
			slot['spinner'].visible = true
	var team_counts := [0, 0]
	for entry in players:
		if not entry is Dictionary:
			continue
		var team := clampi(int(entry.get('team', 0)), 0, 1)
		if team_counts[team] >= SLOTS_PER_TEAM:
			continue
		var slot_index: int = team_counts[team]
		team_counts[team] += 1
		var class_index := clampi(int(entry.get('class', 0)), 0, 2)
		var entry_name := String(entry.get('name', 'Игрок'))
		_set_slot_entry(team, slot_index, entry_name, class_index, bool(entry.get('bot', false)))
	_fill_open_slots_with_bots()
	progress_bar.value = 100.0
	found_count_label.text = '\u0421\u043e\u0441\u0442\u0430\u0432 \u0441\u043e\u0431\u0440\u0430\u043d: 6 / 6'
	search_label.text = '\u041c\u0430\u0442\u0447 \u043d\u0430\u0439\u0434\u0435\u043d!'
	connection_hint.text = '\u041a\u043e\u043c\u0430\u043d\u0434\u044b \u0433\u043e\u0442\u043e\u0432\u044b \u043a \u0431\u043e\u044e'
	get_tree().set_meta('network_play', true)
	get_tree().set_meta('tutorial_mode', false)
	get_tree().set_meta('selected_class', NetworkManager.local_class)
	get_tree().set_meta('selected_team', NetworkManager.assigned_team)
	get_tree().set_meta('network_host', NetworkManager.is_host)
	get_tree().set_meta('network_room_id', room_id)
	get_tree().set_meta('network_match_players', players)
	_transition_when_ready()


func _on_network_failed(reason: String) -> void:
	if transition_started:
		return
	transition_started = true
	search_label.text = '\u0421\u0435\u0440\u0432\u0435\u0440 \u043d\u0435\u0434\u043e\u0441\u0442\u0443\u043f\u0435\u043d'
	connection_hint.text = '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0438\u0442\u044c\u0441\u044f: %s' % reason
	for spinner in searching_spinners:
		if is_instance_valid(spinner):
			spinner.visible = false
	_add_back_button()


func _add_back_button() -> void:
	if back_button != null:
		return
	back_button = Button.new()
	back_button.text = '\u0412 \u041b\u041e\u0411\u0411\u0418'
	back_button.custom_minimum_size = Vector2(220, 56)
	back_button.anchor_left = 0.5
	back_button.anchor_right = 0.5
	back_button.anchor_top = 0.9
	back_button.anchor_bottom = 0.9
	back_button.offset_left = -110.0
	back_button.offset_right = 110.0
	back_button.offset_top = -28.0
	back_button.offset_bottom = 28.0
	back_button.add_theme_font_override('font', FONT)
	back_button.add_theme_font_size_override('font_size', 20)
	back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file('res://scenes/Lobby.tscn'))
	add_child(back_button)

func _process(delta: float) -> void:
	if transition_started:
		return
	tip_timer += delta
	if tip_timer >= 3.0:
		tip_timer = 0.0
		_advance_tip()
	for spinner in searching_spinners:
		if is_instance_valid(spinner) and spinner.visible:
			spinner.rotation += delta * 4.5
	if not network_flow:
		elapsed = minf(elapsed + delta, SEARCH_SECONDS)
		if elapsed >= next_player_time and simulated_players_added < SIMULATED_TARGET:
			_add_simulated_player()
			next_player_time = elapsed + randf_range(1.0, 2.0)
		if elapsed >= SEARCH_SECONDS:
			_complete_match_search()
	_update_search_progress()
	_poll_match_scene_load()

func _start_match_scene_loading() -> void:
	var request_error := ResourceLoader.load_threaded_request(MATCH_PATH)
	if request_error != OK and request_error != ERR_BUSY:
		load_failed = true
	_poll_match_scene_load()

func _poll_match_scene_load() -> void:
	if match_scene != null or load_failed:
		return
	var status := ResourceLoader.load_threaded_get_status(MATCH_PATH)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		match_scene = ResourceLoader.load_threaded_get(MATCH_PATH) as PackedScene
		if match_scene == null:
			load_failed = true
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		load_failed = true

func _use_bot_fallback() -> void:
	no_network = true
	fill_with_bots = true
	if connection_hint != null:
		connection_hint.text = '\u0421\u0435\u0440\u0432\u0435\u0440 \u043d\u0435 \u0438\u0441\u043f\u043e\u043b\u044c\u0437\u0443\u0435\u0442\u0441\u044f - \u0438\u0433\u0440\u0430 \u0441 \u0431\u043e\u0442\u0430\u043c\u0438'

func _add_simulated_player() -> void:
	var counts := [_team_player_count(0), _team_player_count(1)]
	var team_index := 0 if counts[0] < counts[1] else 1
	if counts[0] == counts[1]:
		team_index = randi_range(0, 1)
	var available: Array[int] = []
	for index in range(SLOTS_PER_TEAM):
		if team_slots[team_index][index]['state'] == 'searching':
			available.append(index)
	if available.is_empty():
		team_index = 1 - team_index
		for index in range(SLOTS_PER_TEAM):
			if team_slots[team_index][index]['state'] == 'searching':
				available.append(index)
	if available.is_empty():
		return
	var slot_index: int = available.pick_random()
	_set_slot_player(team_index, slot_index, simulated_players_added + 1, randi_range(0, 2))
	simulated_players_added += 1

func _team_player_count(team_index: int) -> int:
	var count := 0
	for slot in team_slots[team_index]:
		if slot['state'] == 'player':
			count += 1
	return count

func _set_slot_player(team_index: int, slot_index: int, player_number: int, class_index: int) -> void:
	var slot: Dictionary = team_slots[team_index][slot_index]
	slot['state'] = 'player'
	slot['name'].text = '\u0418\u0433\u0440\u043e\u043a %d' % player_number
	slot['portrait'].texture = _class_portrait(class_index)
	slot['portrait'].visible = true
	slot['spinner'].visible = false
	slot['panel'].add_theme_stylebox_override('panel', _slot_style(team_index, true))

func _set_slot_entry(team_index: int, slot_index: int, player_name: String, class_index: int, is_bot: bool) -> void:
	var slot: Dictionary = team_slots[team_index][slot_index]
	slot['state'] = 'bot' if is_bot else 'player'
	slot['name'].text = ('Бот - %s' % _class_name(class_index)) if is_bot else player_name
	slot['portrait'].texture = _class_portrait(class_index)
	slot['portrait'].visible = true
	slot['spinner'].visible = false
	slot['panel'].add_theme_stylebox_override('panel', _slot_style(team_index, not is_bot))


func _class_portrait(index: int) -> Texture2D:
	match index:
		0: return WARRIOR
		1: return MAGE
		_: return FAIRY

func _class_name(index: int) -> String:
	match index:
		0: return '\u0412\u043e\u0438\u043d'
		1: return '\u041c\u0430\u0433'
		_: return '\u0424\u0435\u044f'

func _fill_open_slots_with_bots() -> void:
	for team_index in range(2):
		for slot_index in range(SLOTS_PER_TEAM):
			var slot: Dictionary = team_slots[team_index][slot_index]
			if slot['state'] != 'searching':
				continue
			var class_index := randi_range(0, 2)
			slot['state'] = 'bot'
			slot['name'].text = '\u0411\u043e\u0442 - %s' % _class_name(class_index)
			slot['portrait'].texture = _class_portrait(class_index)
			slot['portrait'].visible = true
			slot['spinner'].visible = false
			slot['panel'].add_theme_stylebox_override('panel', _slot_style(team_index, false))

func _update_search_progress() -> void:
	var occupied := 0
	for team_index in range(2):
		for slot in team_slots[team_index]:
			if slot['state'] != 'searching':
				occupied += 1
	progress_bar.value = float(occupied) * 100.0 / 6.0
	found_count_label.text = '\u0418\u0433\u0440\u043e\u043a\u0438 \u043d\u0430\u0439\u0434\u0435\u043d\u044b: %d / 6' % occupied

func _complete_match_search() -> void:
	if transition_started:
		return
	transition_started = true
	_fill_open_slots_with_bots()
	progress_bar.value = 100.0
	found_count_label.text = '\u0421\u043e\u0441\u0442\u0430\u0432 \u0441\u043e\u0431\u0440\u0430\u043d: 6 / 6'
	search_label.text = '\u041c\u0430\u0442\u0447 \u043d\u0430\u0439\u0434\u0435\u043d!'
	connection_hint.text = '\u0418\u0433\u0440\u0430 \u0441 \u0431\u043e\u0442\u0430\u043c' if fill_with_bots or no_network else '\u041a\u043e\u043c\u0430\u043d\u0434\u044b \u0433\u043e\u0442\u043e\u0432\u044b \u043a \u0431\u043e\u044e'
	get_tree().set_meta('is_1v1', is_1v1)
	get_tree().set_meta('fill_with_bots', fill_with_bots or not is_1v1 or no_network)
	get_tree().set_meta('match_players', players)
	_transition_when_ready()

func _transition_when_ready() -> void:
	await get_tree().create_timer(1.1).timeout
	if not is_inside_tree():
		return
	while not load_failed and match_scene == null:
		_poll_match_scene_load()
		if match_scene == null and not load_failed:
			await get_tree().process_frame
	if match_scene != null:
		var result := get_tree().change_scene_to_packed(match_scene)
		if result != OK:
			push_error('Could not open match scene: %s' % error_string(result))
	else:
		var fallback_result := get_tree().change_scene_to_file(MATCH_PATH)
		if fallback_result != OK:
			push_error('Could not open match scene: %s' % error_string(fallback_result))

func _advance_tip() -> void:
	tip_index = (tip_index + 1) % TIPS.size()
	var tween := create_tween()
	tween.tween_property(tip_label, 'modulate:a', 0.0, 0.16)
	tween.tween_callback(func() -> void: tip_label.text = TIPS[tip_index])
	tween.tween_property(tip_label, 'modulate:a', 1.0, 0.2)

func _build_screen() -> void:
	var background := TextureRect.new()
	background.name = 'LoadingBackground'
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = BG
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.025, 0.055, 0.38)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var logo := TextureRect.new()
	logo.name = 'GameLogo'
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.anchor_left = 0.36
	logo.anchor_right = 0.64
	logo.anchor_top = 0.015
	logo.anchor_bottom = 0.205
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	var title := _make_label('\u041f\u041e\u0418\u0421\u041a \u041c\u0410\u0422\u0427\u0410', 25, Color(1.0, 0.84, 0.53))
	title.anchor_left = 0.28
	title.anchor_right = 0.72
	title.anchor_top = 0.205
	title.anchor_bottom = 0.26
	add_child(title)
	_build_team_panel(0)
	_build_team_panel(1)
	var versus := _make_label('VS', 34, Color(1.0, 0.82, 0.42))
	versus.anchor_left = 0.43
	versus.anchor_right = 0.57
	versus.anchor_top = 0.43
	versus.anchor_bottom = 0.53
	add_child(versus)
	search_label = _make_label('\u041f\u043e\u0438\u0441\u043a \u0438\u0433\u0440\u043e\u043a\u043e\u0432...', 23, Color(1.0, 0.9, 0.7))
	search_label.anchor_left = 0.12
	search_label.anchor_right = 0.88
	search_label.anchor_top = 0.765
	search_label.anchor_bottom = 0.81
	add_child(search_label)
	found_count_label = _make_label('', 15, Color(0.88, 0.9, 0.98))
	found_count_label.anchor_left = 0.12
	found_count_label.anchor_right = 0.88
	found_count_label.anchor_top = 0.81
	found_count_label.anchor_bottom = 0.845
	add_child(found_count_label)
	progress_bar = ProgressBar.new()
	progress_bar.name = 'MatchProgress'
	progress_bar.anchor_left = 0.12
	progress_bar.anchor_right = 0.88
	progress_bar.anchor_top = 0.85
	progress_bar.anchor_bottom = 0.89
	progress_bar.max_value = 100.0
	progress_bar.show_percentage = false
	progress_bar.add_theme_stylebox_override('background', _progress_style(Color(0.025, 0.04, 0.075, 0.92), Color(0.72, 0.79, 0.9)))
	progress_bar.add_theme_stylebox_override('fill', _progress_style(Color(0.9, 0.7, 0.34), Color(1.0, 0.87, 0.58)))
	add_child(progress_bar)
	connection_hint = _make_label('\u041e\u0436\u0438\u0434\u0430\u043d\u0438\u0435 \u0438\u0433\u0440\u043e\u043a\u043e\u0432', 14, Color(0.78, 0.83, 0.93))
	connection_hint.anchor_left = 0.12
	connection_hint.anchor_right = 0.88
	connection_hint.anchor_top = 0.89
	connection_hint.anchor_bottom = 0.925
	add_child(connection_hint)
	var caption := _make_label('\u041f\u041e\u041b\u0415\u0417\u041d\u042b\u0419 \u0421\u041e\u0412\u0415\u0422', 14, Color(1.0, 0.8, 0.42))
	caption.anchor_left = 0.12
	caption.anchor_right = 0.88
	caption.anchor_top = 0.93
	caption.anchor_bottom = 0.958
	add_child(caption)
	tip_label = _make_label(TIPS[0], 15, Color(0.96, 0.97, 1.0))
	tip_label.anchor_left = 0.08
	tip_label.anchor_right = 0.92
	tip_label.anchor_top = 0.958
	tip_label.anchor_bottom = 0.995
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(tip_label)
	_update_search_progress()

func _build_team_panel(team_index: int) -> void:
	var panel := PanelContainer.new()
	panel.name = 'LightTeamPanel' if team_index == 0 else 'DarkTeamPanel'
	panel.anchor_left = 0.035 if team_index == 0 else 0.665
	panel.anchor_right = 0.395 if team_index == 0 else 0.965
	panel.anchor_top = 0.29
	panel.anchor_bottom = 0.735
	panel.add_theme_stylebox_override('panel', _team_style(team_index))
	add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override('separation', 8)
	panel.add_child(layout)
	var heading_text := '\u041a\u041e\u041c\u0410\u041d\u0414\u0410 \u0421\u0412\u0415\u0422\u0410' if team_index == 0 else '\u041a\u041e\u041c\u0410\u041d\u0414\u0410 \u0422\u042c\u041c\u042b'
	layout.add_child(_make_label(heading_text, 20, Color.WHITE))
	team_slots[team_index] = []
	for slot_index in range(SLOTS_PER_TEAM):
		team_slots[team_index].append(_build_player_slot(team_index, slot_index, layout))

func _build_player_slot(team_index: int, slot_index: int, parent: VBoxContainer) -> Dictionary:
	var panel := PanelContainer.new()
	panel.name = 'PlayerSlot_%d' % (slot_index + 1)
	panel.custom_minimum_size = Vector2(0.0, 62.0)
	panel.add_theme_stylebox_override('panel', _slot_style(team_index, false))
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override('separation', 8)
	panel.add_child(row)
	var portrait := TextureRect.new()
	portrait.name = 'ClassIcon'
	portrait.custom_minimum_size = Vector2(42.0, 42.0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.visible = false
	row.add_child(portrait)
	var slot_name := _make_label('\u041e\u0436\u0438\u0434\u0430\u043d\u0438\u0435...', 15, Color(0.76, 0.78, 0.84))
	slot_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(slot_name)
	var spinner := _make_label('\u25cc', 20, Color(0.62, 0.65, 0.72))
	spinner.custom_minimum_size = Vector2(26.0, 26.0)
	spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	spinner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spinner.pivot_offset = Vector2(13.0, 13.0)
	row.add_child(spinner)
	searching_spinners.append(spinner)
	return {'panel': panel, 'portrait': portrait, 'name': slot_name, 'spinner': spinner, 'state': 'searching'}

func _team_style(team_index: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.025, 0.05, 0.72)
	style.border_color = Color(0.3, 0.62, 0.92, 0.85) if team_index == 0 else Color(0.64, 0.4, 0.86, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _slot_style(team_index: int, occupied: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.055, 0.085, 0.9) if occupied else Color(0.035, 0.04, 0.055, 0.82)
	style.border_color = Color(0.55, 0.58, 0.66, 0.52) if not occupied else (Color(0.43, 0.74, 1.0, 0.75) if team_index == 0 else Color(0.76, 0.52, 1.0, 0.75))
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style

func _progress_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override('font', FONT)
	label.add_theme_font_size_override('font_size', font_size)
	label.add_theme_color_override('font_color', color)
	label.add_theme_color_override('font_shadow_color', Color(0.01, 0.01, 0.02, 0.8))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
const TIPS := [
	'\u0411\u0435\u0439\u0442\u0435 \u041e\u0431\u043e\u043b\u043e\u0447\u043a\u0443 \u0432\u043c\u0435\u0441\u0442\u0435! \u0427\u0435\u043c \u0431\u043e\u043b\u044c\u0448\u0435 \u0441\u043e\u044e\u0437\u043d\u0438\u043a\u043e\u0432 \u0440\u044f\u0434\u043e\u043c, \u0442\u0435\u043c \u043c\u0435\u043d\u044c\u0448\u0435 \u0443\u0440\u043e\u043d\u0430 \u043e\u0442 \u043c\u043e\u043b\u043d\u0438\u0439 \u043f\u043e\u043b\u0443\u0447\u0430\u0435\u0442 \u043a\u0430\u0436\u0434\u044b\u0439.',
	'\u041d\u043e\u0441\u0438\u043b\u044c\u0449\u0438\u043a \u041a\u0440\u0438\u0441\u0442\u0430\u043b\u043b\u0430 \u0434\u0432\u0438\u0433\u0430\u0435\u0442\u0441\u044f \u0432\u0434\u0432\u043e\u0435 \u043c\u0435\u0434\u043b\u0435\u043d\u043d\u0435\u0435. \u041f\u0440\u0438\u043a\u0440\u044b\u0432\u0430\u0439\u0442\u0435 \u0435\u0433\u043e!',
	'\u0424\u0435\u044f \u0445\u0440\u0443\u043f\u043a\u0430\u044f, \u043d\u043e \u043d\u0430\u043d\u043e\u0441\u0438\u0442 \u043e\u0433\u0440\u043e\u043c\u043d\u044b\u0439 \u0443\u0440\u043e\u043d \u0441 \u0434\u0438\u0441\u0442\u0430\u043d\u0446\u0438\u0438. \u0412\u043e\u0438\u043d \u0434\u043e\u043b\u0436\u0435\u043d \u0437\u0430\u0449\u0438\u0449\u0430\u0442\u044c \u0435\u0451.',
	'\u0415\u0441\u043b\u0438 \u043d\u043e\u0441\u0438\u043b\u044c\u0449\u0438\u043a \u041a\u0440\u0438\u0441\u0442\u0430\u043b\u043b\u0430 \u043f\u043e\u0433\u0438\u0431\u043d\u0435\u0442, \u041a\u0440\u0438\u0441\u0442\u0430\u043b\u043b \u0443\u043f\u0430\u0434\u0435\u0442 \u043d\u0430 \u0437\u0435\u043c\u043b\u044e. \u0421\u043a\u043e\u0440\u0435\u0435 \u043f\u043e\u0434\u0431\u0435\u0440\u0438\u0442\u0435 \u0435\u0433\u043e!',
]
