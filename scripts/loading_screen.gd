extends Control

const BG: Texture2D = preload('res://assets/ui/loading_bg.png')
const LOGO: Texture2D = preload('res://ui/logo.png')
const WARRIOR: Texture2D = preload('res://assets/ui/heroes/warrior_face.webp')
const MAGE: Texture2D = preload('res://assets/ui/heroes/mage_face.webp')
const FAIRY: Texture2D = preload('res://assets/ui/heroes/archer_face.webp')
const MATCH_PATH := 'res://scenes/Main.tscn'
const WARMUP_FLOW_SCRIPT := preload('res://scripts/warmup_flow.gd')
## The battle warmup runs inside the match-search window. If the match is
## found earlier the transition waits for it, but never longer than this:
## after the budget the match starts without the warmup (game.gd falls back
## to its own first-frame warmup). WarmupFlow paces itself to ~21 s and stops
## at 28 s, so this budget is the real ceiling.
const WARMUP_BUDGET_SECONDS := 30.0
## Tutorial loading screen: a broken warmup must never leave the player here.
## WarmupFlow stops itself at 28 s; this is only the backstop for a stalled
## frame loop.
const TUTORIAL_WARMUP_TIMEOUT_SECONDS := 32.0
const SEARCH_SECONDS := 15.0
# Клиент ждёт сервер; сервер стартует комнату через 30 секунд после
# последнего вошедшего игрока, поэтому обратный отсчёт тоже 30.
const NETWORK_WAIT_SECONDS := 30.0
const SLOTS_PER_TEAM := 3
const SIMULATED_TARGET := 4
const FONT: FontFile = preload('res://assets/fonts/Philosopher-Regular.ttf')
const BATTLE_AUDIO := preload('res://scripts/audio_preloader.gd')
## How long the preloaded battle assets stay referenced after the match opens.
## Main._ready and start_match spawn the fighters in the first ~1.5 s; after
## that the match scene holds its own references and the extra ones only cost
## RAM. The keeper drops them on its own, so a cancelled match cannot leak.
const BATTLE_ASSET_KEEP_SECONDS := 8.0
var team_slots: Array = [[], []]
class SpinnerRing extends Control:
	func _ready() -> void:
		custom_minimum_size = Vector2(26.0, 26.0)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pivot_offset = Vector2(13.0, 13.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var center := size * 0.5
		draw_arc(center, 9.0, 0.0, TAU * 0.72, 28, Color(0.62, 0.65, 0.72), 2.5, true)
		draw_circle(center + Vector2(9.0, 0.0), 2.5, Color(0.85, 0.75, 0.45))


var searching_spinners: Array[Control] = []
var progress_bar: ProgressBar
var search_label: Label
var connection_hint: Label
var tip_label: Label
var tip_caption_label: Label
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
var wait_seconds_left := NETWORK_WAIT_SECONDS
var wait_countdown_active := false
# Battle warmup (WarmupFlow) state. The full arena/fighters/weapons/VFX pass
# runs while the search screen is visible, instead of at the start of Main.
var warmup_flow: Node = null
var warmup_active := false
var warmup_failed := false
var warmup_started_ms := 0
var warmup_budget_seconds := WARMUP_BUDGET_SECONDS
var warmup_panel: PanelContainer
var warmup_percent_label: Label
var warmup_stage_label: Label
var match_load_requested := false
# Tutorial loading mode: owned by the tutorial (lobby sets tutorial_mode +
# warmup_pending), no match search, no network — warmup then Main.
var tutorial_mode := false
var tutorial_warmup_token := 0
var welcome_card: WelcomeOverlay
var title_label: Label
var versus_label: Label
## Holds the warmup's loaded resources through the scene switch (see
## BattleAssetKeeper). One keeper per transition.
var asset_keeper: Node = null


## Lives on the SceneTree root, so it survives `change_scene_to_packed`.
## ResourceLoader's cache is weak: a resource is dropped as soon as nothing
## references it, and the loading screen (and the warmup flow) are freed by the
## scene change. Without this the match re-read the fighter models from the pack
## in one ~320 ms spawn frame and the battle audio in its first frame.
class BattleAssetKeeper extends Node:
	var held: Array = []
	var keep_seconds := 8.0
	var started_ms := 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		started_ms = Time.get_ticks_msec()

	func _process(_delta: float) -> void:
		if Time.get_ticks_msec() - started_ms < int(keep_seconds * 1000.0):
			return
		held.clear()
		queue_free()

	func held_count() -> int:
		return held.size()

func _ready() -> void:
	randomize()
	network_flow = bool(get_tree().get_meta('network_play', false))
	tutorial_mode = bool(get_tree().get_meta('tutorial_mode', true))
	_build_screen()
	if tutorial_mode:
		if bool(get_tree().get_meta('warmup_pending', false)):
			_start_tutorial_warmup()
		else:
			# Direct tutorial entry without the tutorial loading flow (probes,
			# editor previews): keep the plain prefetch, never the search.
			_start_match_scene_loading()
			_add_vfx_preloader()
		return
	# WarmupFlow loads Main.tscn itself; a parallel threaded preload would be
	# a second full load of the same scene. Main is taken from the cache after
	# the warmup ends (see _start_match_scene_loading).
	_start_battle_warmup()
	if network_flow:
		_start_network_flow()
	else:
		_use_bot_fallback()
	search_label.text = 'Поиск игроков...'
	tip_label.text = TIPS[0]


func _add_vfx_preloader() -> void:
	# Only the direct tutorial entry (no tutorial warmup) takes this path:
	# WarmupFlow runs its own VFX pass, so a second preloader would duplicate
	# the whole VFX/character warmup.
	if warmup_flow != null or warmup_active or find_child('VfxPreloader', true, false) != null:
		return
	var preloader := preload('res://scripts/vfx_preloader.gd').new()
	preloader.name = 'VfxPreloader'
	add_child(preloader)


func _start_battle_warmup() -> void:
	warmup_active = true
	warmup_started_ms = Time.get_ticks_msec()
	_build_warmup_status()
	warmup_flow = WARMUP_FLOW_SCRIPT.new()
	if warmup_flow == null or not warmup_flow.has_method('start'):
		warmup_active = false
		warmup_failed = true
		_start_match_scene_loading()
		return
	warmup_flow.name = 'WarmupFlow'
	add_child(warmup_flow)
	warmup_flow.progress_changed.connect(_on_battle_warmup_progress)
	warmup_flow.finished.connect(_on_battle_warmup_finished)
	warmup_flow.start()


func _build_warmup_status() -> void:
	warmup_panel = PanelContainer.new()
	warmup_panel.name = 'BattleWarmupStatus'
	# Hug the content in the free top-right corner: no overlap with the logo
	# (ends at 0.64) or the team panels; compact on a phone.
	warmup_panel.anchor_left = 0.975
	warmup_panel.anchor_right = 0.975
	warmup_panel.anchor_top = 0.02
	warmup_panel.anchor_bottom = 0.02
	warmup_panel.offset_left = 0.0
	warmup_panel.offset_right = 0.0
	warmup_panel.offset_top = 0.0
	warmup_panel.offset_bottom = 0.0
	warmup_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	warmup_panel.grow_vertical = Control.GROW_DIRECTION_END
	warmup_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warmup_panel.add_theme_stylebox_override('panel', _warmup_style())
	add_child(warmup_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override('separation', 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	warmup_panel.add_child(column)
	warmup_percent_label = _make_label('Прогрев боя: 0%', 13, Color(1.0, 0.88, 0.6))
	warmup_percent_label.name = 'WarmupPercent'
	warmup_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(warmup_percent_label)
	warmup_stage_label = _make_label('Подготовка', 11, Color(0.8, 0.85, 0.95))
	warmup_stage_label.name = 'WarmupStage'
	warmup_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(warmup_stage_label)


func _on_battle_warmup_progress(percent: float, _elapsed: float, stage: String) -> void:
	if not is_instance_valid(warmup_percent_label):
		return
	warmup_percent_label.text = 'Прогрев боя: %d%%' % int(round(percent))
	warmup_stage_label.text = stage


func _on_battle_warmup_finished() -> void:
	if not warmup_active:
		return
	warmup_active = false
	var report: Dictionary = {}
	if warmup_flow != null and is_instance_valid(warmup_flow):
		report = warmup_flow.get('report') as Dictionary
		# Keep what the flow loaded: Main and the warmup instance are freed by
		# the scene change, and the loader cache is weak (see BattleAssetKeeper).
		_keep_battle_assets(warmup_flow.get('retained_resources'))
		warmup_flow.queue_free()
		warmup_flow = null
	warmup_failed = bool(report.get('failed', false))
	if warmup_failed:
		_mark_warmup_status('Прогрев боя: пропущен', 'Загружаем бой')
	else:
		# Main.tscn will skip its own expensive re-warm: everything the first
		# frame needs is hot in the resource/shader cache.
		get_tree().set_meta('battle_prewarmed', true)
		_mark_warmup_status('Прогрев боя: 100%', 'Готово')
	_start_match_scene_loading()


func _mark_warmup_status(percent_text: String, stage_text: String) -> void:
	if not is_instance_valid(warmup_percent_label):
		return
	warmup_percent_label.text = percent_text
	warmup_stage_label.text = stage_text


func _cancel_battle_warmup() -> void:
	warmup_active = false
	if warmup_flow != null and is_instance_valid(warmup_flow):
		# Whatever the flow already loaded is still worth keeping: the match is
		# opened right after a cancelled warmup on purpose.
		_keep_battle_assets(warmup_flow.get('retained_resources'))
		warmup_flow.queue_free()
		warmup_flow = null
	if is_instance_valid(warmup_panel):
		warmup_panel.visible = false


## Hands resources the warmup loaded to a node on the SceneTree root that
## outlives this screen. ResourceLoader's cache is a weak cache: the loading
## screen and the warmup flow are freed by `change_scene_to_packed`, so without
## this the match re-reads the fighter models (one ~320 ms frame: 118 + 93 + 86
## ms for the three classes) and the battle audio from the pack.
func _keep_battle_assets(resources: Variant) -> void:
	if not (resources is Array) or (resources as Array).is_empty():
		return
	# A/B hook for tools/BattleStartE2EProbe.tscn: the pre-fix behaviour, where
	# the loader cache drops everything with the loading screen.
	if OS.get_cmdline_user_args().has('--no-keep-battle-assets'):
		return
	var list: Array = resources as Array
	if asset_keeper != null and is_instance_valid(asset_keeper):
		var held: Array = asset_keeper.get('held') as Array
		for resource in list:
			if resource != null:
				held.append(resource)
		return
	var keeper := BattleAssetKeeper.new()
	keeper.name = 'BattleAssetKeeper'
	keeper.keep_seconds = BATTLE_ASSET_KEEP_SECONDS
	keeper.held = list.duplicate()
	get_tree().root.add_child(keeper)
	asset_keeper = keeper
	print('[LoadingScreen] battle assets kept=%d keep=%.0fs' % [keeper.held_count(), keeper.keep_seconds])


## Tutorial: the lesson has its own loading screen, opened by lobby.gd right
## after "Играть". No network search and no bot fallback here — only the real
## battle warmup, then Main.tscn (game.gd starts the lesson from the meta).
func _start_tutorial_warmup() -> void:
	_show_tutorial_card()
	warmup_active = true
	warmup_started_ms = Time.get_ticks_msec()
	warmup_flow = WARMUP_FLOW_SCRIPT.new()
	if warmup_flow == null or not warmup_flow.has_method('start'):
		warmup_active = false
		_open_tutorial_main()
		return
	warmup_flow.name = 'WarmupFlow'
	add_child(warmup_flow)
	warmup_flow.progress_changed.connect(_on_tutorial_warmup_progress)
	warmup_flow.finished.connect(_on_tutorial_warmup_finished)
	warmup_flow.start()
	# Hard watchdog: a driver hiccup must never leave the player on a frozen
	# loading screen. The normal flow finishes in ~20-22 s; the warmup itself
	# stops at 28 s, so this only catches a stalled frame loop.
	tutorial_warmup_token += 1
	var token := tutorial_warmup_token
	get_tree().create_timer(TUTORIAL_WARMUP_TIMEOUT_SECONDS).timeout.connect(func() -> void:
		if not is_inside_tree() or not warmup_active or token != tutorial_warmup_token:
			return
		_cancel_battle_warmup()
		_open_tutorial_main()
	)


## The lesson loads on the newcomer Welcome card: same key art, logo and legal
## line. Only the Play button is replaced by the warmup progress, which keeps
## the exact match-search bar position (same anchors as progress_bar).
func _show_tutorial_card() -> void:
	welcome_card = WelcomeOverlay.new()
	welcome_card.name = 'TutorialWelcomeCard'
	# Bigger logo for the lesson only: the Welcome card keeps its own size.
	# The height cap keeps it above the title on short phone canvases.
	welcome_card.logo_scale = 2.4 if DeviceProfile.mobile_ui else 2.0
	welcome_card.logo_max_height_ratio = 0.60
	add_child(welcome_card)
	welcome_card.show_warming()
	# The search-screen bar is the progress line; the card's own block would
	# duplicate it in the Play button slot.
	welcome_card.warmup_box.visible = false
	welcome_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := get_node_or_null('LoadingBackground') as Control
	if background != null:
		background.visible = false
	var logo := get_node_or_null('GameLogo') as Control
	if logo != null:
		logo.visible = false
	if title_label != null:
		title_label.visible = false
	for panel_name in ['LightTeamPanel', 'DarkTeamPanel']:
		var panel := find_child(panel_name, true, false) as Control
		if panel != null:
			panel.visible = false
	if versus_label != null:
		versus_label.visible = false
	if tip_caption_label != null:
		tip_caption_label.visible = false
	if tip_label != null:
		tip_label.visible = false
	# The Welcome card sets z_index 200; keep the progress block above it.
	for node in [search_label, found_count_label, progress_bar, connection_hint]:
		node.z_index = 201
	search_label.text = 'ЗАГРУЗКА ОБУЧЕНИЯ'
	search_label.add_theme_color_override('font_color', Color(1.0, 0.84, 0.53))
	# The percentage, stage and time share one line under the bar.
	found_count_label.text = ''
	found_count_label.visible = false
	connection_hint.text = '0% · Загрузка арены · 0.0 с'
	progress_bar.value = 0.0


func _on_tutorial_warmup_progress(percent: float, elapsed: float, stage: String) -> void:
	progress_bar.value = clampf(percent, 0.0, 100.0)
	var stage_text := stage.strip_edges()
	if stage_text.is_empty():
		stage_text = 'Подготовка'
	connection_hint.text = '%d%% · %s · %.1f с' % [
		int(round(percent)), stage_text, maxf(0.0, elapsed)
	]


func _on_tutorial_warmup_finished() -> void:
	if not warmup_active:
		return
	warmup_active = false
	tutorial_warmup_token += 1
	var report: Dictionary = {}
	if warmup_flow != null and is_instance_valid(warmup_flow):
		report = warmup_flow.get('report') as Dictionary
		_keep_battle_assets(warmup_flow.get('retained_resources'))
		warmup_flow.queue_free()
		warmup_flow = null
	warmup_failed = bool(report.get('failed', false))
	if warmup_failed:
		# A broken warmup must not trap the player here: Main opens without it
		# and game.gd runs its own tutorial warmup.
		connection_hint.text = 'Открываем обучение'
	else:
		# game.gd skips its own expensive tutorial warmup.
		get_tree().set_meta('battle_prewarmed', true)
		progress_bar.value = 100.0
		connection_hint.text = '100% · Готово'
	_open_tutorial_main()


func _open_tutorial_main() -> void:
	warmup_active = false
	get_tree().set_meta('warmup_pending', false)
	# No parallel preload was started: WarmupFlow already loaded Main.tscn,
	# so this opens from the warm resource cache.
	var error := get_tree().change_scene_to_file(MATCH_PATH)
	if error != OK:
		push_error('Could not open the tutorial scene: %s' % error_string(error))


## Waits for the warmup before switching to Main, but only up to the budget.
## Called after the match is found; the search screen keeps showing progress.
func _wait_for_battle_warmup() -> void:
	if not warmup_active:
		return
	if is_instance_valid(warmup_stage_label):
		warmup_stage_label.text = 'Матч найден · догреваем бой'
	while warmup_active:
		if not is_inside_tree():
			return
		if Time.get_ticks_msec() - warmup_started_ms > int(warmup_budget_seconds * 1000.0):
			# Do not hang the player on a warmup that is too slow: start the
			# match now and let game.gd do its own first-frame warmup.
			_cancel_battle_warmup()
			_start_match_scene_loading()
			return
		await get_tree().process_frame


func _start_network_flow() -> void:
	no_network = false
	fill_with_bots = true
	wait_seconds_left = NETWORK_WAIT_SECONDS
	# The countdown starts only when the server sends the lobby state, so it
	# is always the real time until the match starts.
	wait_countdown_active = false
	connection_hint.text = '\u041f\u043e\u0434\u043a\u043b\u044e\u0447\u0430\u0435\u043c\u0441\u044f \u043a \u0441\u0435\u0440\u0432\u0435\u0440\u0443...'
	if not NetworkManager.connection_succeeded.is_connected(_on_network_connected):
		NetworkManager.connection_succeeded.connect(_on_network_connected)
	if not NetworkManager.connection_failed.is_connected(_on_network_failed):
		NetworkManager.connection_failed.connect(_on_network_failed)
	if not NetworkManager.remote_player_joined.is_connected(_on_network_player_joined):
		NetworkManager.remote_player_joined.connect(_on_network_player_joined)
	if not NetworkManager.match_started.is_connected(_on_network_match_started):
		NetworkManager.match_started.connect(_on_network_match_started)
	if not NetworkManager.lobby_state_received.is_connected(_on_lobby_state):
		NetworkManager.lobby_state_received.connect(_on_lobby_state)
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
	if not network_player_slots.has(-1):
		for slot_index in range(SLOTS_PER_TEAM):
			if team_slots[0][slot_index]['state'] == 'searching':
				var local_class := clampi(int(get_tree().get_meta('selected_class', 0)), 0, 2)
				var local_name := MetaProgression.player_nickname
				if local_name.is_empty():
					local_name = 'Игрок'
				_set_slot_entry(0, slot_index, local_name, local_class, false)
				network_player_slots[-1] = true
				break


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
	# Сервер перезапускает таймер ботов на каждом входе — держим
	# обратный отсчёт синхронным, иначе он врёт игроку.
	wait_seconds_left = NETWORK_WAIT_SECONDS
	wait_countdown_active = true


func _on_lobby_state(players: Array, starts_in_ms: int) -> void:
	if transition_started:
		return
	_fill_lobby_slots(players)
	network_player_slots.clear()
	wait_seconds_left = maxf(0.0, float(starts_in_ms) / 1000.0)
	wait_countdown_active = true
	if starts_in_ms <= 0:
		search_label.text = 'Бой начинается...'
	else:
		search_label.text = 'Бой начнётся через %d сек' % int(ceil(wait_seconds_left))


func _fill_lobby_slots(players: Array) -> void:
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


func _on_network_match_started(room_id: int, _host_id: int, players: Array) -> void:
	if transition_started:
		return
	transition_started = true
	wait_countdown_active = false
	network_player_slots.clear()
	_fill_lobby_slots(players)
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
	wait_countdown_active = false
	# The player stays on the error screen; do not keep the hidden arena and
	# viewport alive behind it.
	_cancel_battle_warmup()
	search_label.text = '\u0421\u0435\u0440\u0432\u0435\u0440 \u043d\u0435\u0434\u043e\u0441\u0442\u0443\u043f\u0435\u043d'
	connection_hint.text = '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0438\u0442\u044c\u0441\u044f: %s' % reason
	for spinner in searching_spinners:
		if is_instance_valid(spinner):
			spinner.visible = false
	# The back button occupies the bottom tip area; the tip would otherwise
	# be drawn underneath it. Hide the optional tip rows on the failure state.
	if tip_caption_label != null:
		tip_caption_label.visible = false
	if tip_label != null:
		tip_label.visible = false
	_add_back_button()


func _add_back_button() -> void:
	if back_button != null:
		return
	back_button = Button.new()
	back_button.text = '\u0412 \u041b\u041e\u0411\u0411\u0418'
	back_button.custom_minimum_size = Vector2(220, 56)
	back_button.anchor_left = 0.5
	back_button.anchor_right = 0.5
	var back_anchor_y := 0.91 if DeviceProfile.mobile_ui else 0.94
	back_button.anchor_top = back_anchor_y
	back_button.anchor_bottom = back_anchor_y
	back_button.offset_left = -110.0
	back_button.offset_right = 110.0
	back_button.offset_top = -28.0
	back_button.offset_bottom = 28.0
	back_button.add_theme_font_override('font', FONT)
	back_button.add_theme_font_size_override('font_size', _fs(20))
	back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file('res://scenes/Lobby.tscn'))
	add_child(back_button)

func _process(delta: float) -> void:
	if transition_started:
		return
	if tutorial_mode:
		# Tutorial loading: only WarmupFlow drives this screen — no search,
		# no countdown, no bot slots.
		_poll_match_scene_load()
		return
	if network_flow and wait_countdown_active:
		wait_seconds_left = maxf(0.0, wait_seconds_left - delta)
		var seconds_left := int(ceil(wait_seconds_left))
		if seconds_left > 0:
			search_label.text = 'Бой начнётся через %d сек' % seconds_left
		else:
			search_label.text = 'Бой начинается...'
			wait_countdown_active = false
	tip_timer += delta
	if tip_timer >= 10.0:
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
	if match_load_requested or match_scene != null or load_failed:
		return
	match_load_requested = true
	_prefetch_battle_audio()
	# WarmupFlow has already loaded Main.tscn once. If it is still in the
	# resource cache, take that PackedScene instead of reading the scene a
	# second time; otherwise load it now, sequentially — never in parallel
	# with the warmup. Only a warmup that failed before its first step leaves
	# the cache cold.
	if ResourceLoader.has_cached(MATCH_PATH):
		match_scene = load(MATCH_PATH) as PackedScene
		if match_scene == null:
			load_failed = true
		return
	var request_error := ResourceLoader.load_threaded_request(MATCH_PATH)
	if request_error != OK and request_error != ERR_BUSY:
		load_failed = true
	_poll_match_scene_load()

## Battle audio for the paths that skip WarmupFlow (direct tutorial entry,
## probes, editor previews). The warmup stage preloads and keeps the same list
## itself; here it is only requested, which already takes the read off the
## match's first frame.
func _prefetch_battle_audio() -> void:
	if warmup_flow != null or warmup_active:
		return
	for path in BATTLE_AUDIO.stream_paths():
		ResourceLoader.load_threaded_request(String(path))

func _poll_match_scene_load() -> void:
	# Nothing to poll until a threaded request exists: asking for the status
	# of a path that was never requested returns THREAD_LOAD_INVALID_RESOURCE
	# and would mark the load as failed.
	if not match_load_requested or match_scene != null or load_failed:
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
	slot['name'].text = '\u0418\u0433\u0440\u043e\u043a %04d' % player_number
	slot['portrait'].texture = _class_portrait(class_index)
	slot['portrait'].visible = true
	slot['spinner'].visible = false
	slot['panel'].add_theme_stylebox_override('panel', _slot_style(team_index, true))

func _set_slot_entry(team_index: int, slot_index: int, player_name: String, class_index: int, is_bot: bool) -> void:
	var slot: Dictionary = team_slots[team_index][slot_index]
	slot['state'] = 'bot' if is_bot else 'player'
	# Bot names already arrive as "БОТ 1234" from game/server: never stack a
	# second prefix ("БОТ · БОТ 1234"). Mirrors hero.gd.
	var slot_name := player_name
	if is_bot and not _has_bot_prefix(slot_name):
		slot_name = 'БОТ · ' + player_name
	slot['name'].text = slot_name
	slot['portrait'].texture = _class_portrait(class_index)
	slot['portrait'].visible = true
	slot['spinner'].visible = false
	slot['panel'].add_theme_stylebox_override('panel', _slot_style(team_index, not is_bot))


func _has_bot_prefix(name_text: String) -> bool:
	var upper := name_text.strip_edges().to_upper()
	return upper.begins_with('БОТ') or upper.begins_with('BOT')


func _class_portrait(index: int) -> Texture2D:
	match index:
		0: return WARRIOR
		1: return MAGE
		_: return FAIRY

func _class_name(index: int) -> String:
	match index:
		0: return '\u0412\u043e\u0438\u043d'
		1: return '\u041c\u0430\u0433'
		_: return '\u041e\u0445\u043e\u0442\u043d\u0438\u0446\u0430'

func _fill_open_slots_with_bots() -> void:
	for team_index in range(2):
		for slot_index in range(SLOTS_PER_TEAM):
			var slot: Dictionary = team_slots[team_index][slot_index]
			if slot['state'] != 'searching':
				continue
			var class_index := randi_range(0, 2)
			slot['state'] = 'bot'
			slot['name'].text = '\u0411\u041e\u0422 · \u0418\u0433\u0440\u043e\u043a %04d' % randi_range(1000, 9999)
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
	# The match is already found; do not start it on a cold renderer. The
	# wait is bounded by warmup_budget_seconds so a slow device never hangs.
	await _wait_for_battle_warmup()
	if not is_inside_tree():
		return
	_start_match_scene_loading()
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
	var mobile := DeviceProfile.mobile_ui
	var title := _make_label('\u041f\u041e\u0418\u0421\u041a \u041c\u0410\u0422\u0427\u0410', 25, Color(1.0, 0.84, 0.53))
	title.anchor_left = 0.28
	title.anchor_right = 0.72
	title.anchor_top = 0.205
	title.anchor_bottom = 0.26
	add_child(title)
	title_label = title
	_build_team_panel(0)
	_build_team_panel(1)
	var versus := _make_label('VS', 34, Color(1.0, 0.82, 0.42))
	versus.name = 'VersusLabel'
	versus.anchor_left = 0.43
	versus.anchor_right = 0.57
	versus.anchor_top = 0.43
	versus.anchor_bottom = 0.53
	add_child(versus)
	versus_label = versus
	search_label = _make_label('\u041f\u043e\u0438\u0441\u043a \u0438\u0433\u0440\u043e\u043a\u043e\u0432...', 22 if mobile else 26, Color(1.0, 0.9, 0.7))
	search_label.anchor_left = 0.12
	search_label.anchor_right = 0.88
	# On the phone the old 13-15 px bands were shorter than the clamped
	# 18 px font: "Игроки найдены" was drawn on top of the progress bar and
	# the tip was pinned to the screen edge. Keep every row taller than its
	# line height and leave a real gutter before the bottom edge.
	search_label.anchor_top = 0.655 if mobile else 0.76
	search_label.anchor_bottom = 0.704 if mobile else 0.80
	add_child(search_label)
	found_count_label = _make_label('', 13 if mobile else 15, Color(0.88, 0.9, 0.98))
	found_count_label.anchor_left = 0.12
	found_count_label.anchor_right = 0.88
	found_count_label.anchor_top = 0.708 if mobile else 0.80
	found_count_label.anchor_bottom = 0.752 if mobile else 0.835
	add_child(found_count_label)
	progress_bar = ProgressBar.new()
	progress_bar.name = 'MatchProgress'
	progress_bar.anchor_left = 0.12
	progress_bar.anchor_right = 0.88
	progress_bar.anchor_top = 0.76 if mobile else 0.835
	progress_bar.anchor_bottom = 0.788 if mobile else 0.87
	progress_bar.max_value = 100.0
	progress_bar.show_percentage = false
	progress_bar.add_theme_stylebox_override('background', _progress_style(Color(0.025, 0.04, 0.075, 0.92), Color(0.72, 0.79, 0.9)))
	progress_bar.add_theme_stylebox_override('fill', _progress_style(Color(0.9, 0.7, 0.34), Color(1.0, 0.87, 0.58)))
	add_child(progress_bar)
	connection_hint = _make_label('\u041e\u0436\u0438\u0434\u0430\u043d\u0438\u0435 \u0438\u0433\u0440\u043e\u043a\u043e\u0432', 13 if mobile else 14, Color(0.78, 0.83, 0.93))
	connection_hint.anchor_left = 0.12
	connection_hint.anchor_right = 0.88
	connection_hint.anchor_top = 0.795 if mobile else 0.87
	connection_hint.anchor_bottom = 0.836 if mobile else 0.90
	add_child(connection_hint)
	var caption := _make_label('\u041f\u041e\u041b\u0415\u0417\u041d\u042b\u0419 \u0421\u041e\u0412\u0415\u0422', 13 if mobile else 14, Color(1.0, 0.8, 0.42))
	caption.anchor_left = 0.12
	caption.anchor_right = 0.88
	caption.anchor_top = 0.842 if mobile else 0.903
	caption.anchor_bottom = 0.881 if mobile else 0.925
	add_child(caption)
	tip_caption_label = caption
	tip_label = _make_label(TIPS[0], 13 if mobile else 15, Color(0.96, 0.97, 1.0))
	tip_label.anchor_left = 0.08
	tip_label.anchor_right = 0.92
	tip_label.anchor_top = 0.888 if mobile else 0.925
	tip_label.anchor_bottom = 0.988 if mobile else 0.962
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(tip_label)
	_update_search_progress()

func _build_team_panel(team_index: int) -> void:
	var panel := PanelContainer.new()
	panel.name = 'LightTeamPanel' if team_index == 0 else 'DarkTeamPanel'
	panel.anchor_left = 0.035 if team_index == 0 else 0.665
	panel.anchor_right = 0.395 if team_index == 0 else 0.965
	panel.anchor_top = 0.24 if DeviceProfile.mobile_ui else 0.29
	panel.anchor_bottom = 0.64 if DeviceProfile.mobile_ui else 0.735
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
	panel.custom_minimum_size = Vector2(0.0, 48.0 if DeviceProfile.mobile_ui else 86.0)
	panel.add_theme_stylebox_override('panel', _slot_style(team_index, false))
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override('separation', 8)
	panel.add_child(row)
	var portrait := TextureRect.new()
	portrait.name = 'ClassIcon'
	portrait.custom_minimum_size = Vector2(40.0 if DeviceProfile.mobile_ui else 72.0, 40.0 if DeviceProfile.mobile_ui else 72.0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.visible = false
	row.add_child(portrait)
	var slot_name := _make_label('\u041e\u0436\u0438\u0434\u0430\u043d\u0438\u0435...', 15, Color(0.76, 0.78, 0.84))
	slot_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(slot_name)
	var spinner := SpinnerRing.new()
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

func _warmup_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.06, 0.72)
	style.border_color = Color(0.9, 0.7, 0.34, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override('font', FONT)
	label.add_theme_font_size_override('font_size', _fs(font_size))
	label.add_theme_color_override('font_color', color)
	label.add_theme_color_override('font_shadow_color', Color(0.01, 0.01, 0.02, 0.8))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
const TIPS := [
	'\u0411\u0435\u0439\u0442\u0435 \u041e\u0431\u043e\u043b\u043e\u0447\u043a\u0443 \u0432\u043c\u0435\u0441\u0442\u0435! \u0427\u0435\u043c \u0431\u043e\u043b\u044c\u0448\u0435 \u0441\u043e\u044e\u0437\u043d\u0438\u043a\u043e\u0432 \u0440\u044f\u0434\u043e\u043c, \u0442\u0435\u043c \u043c\u0435\u043d\u044c\u0448\u0435 \u0443\u0440\u043e\u043d\u0430 \u043e\u0442 \u043c\u043e\u043b\u043d\u0438\u0439 \u043f\u043e\u043b\u0443\u0447\u0430\u0435\u0442 \u043a\u0430\u0436\u0434\u044b\u0439.',
	'\u041d\u043e\u0441\u0438\u043b\u044c\u0449\u0438\u043a \u041a\u0440\u0438\u0441\u0442\u0430\u043b\u043b\u0430 \u0434\u0432\u0438\u0433\u0430\u0435\u0442\u0441\u044f \u0432\u0434\u0432\u043e\u0435 \u043c\u0435\u0434\u043b\u0435\u043d\u043d\u0435\u0435. \u041f\u0440\u0438\u043a\u0440\u044b\u0432\u0430\u0439\u0442\u0435 \u0435\u0433\u043e!',
	'\u041e\u0445\u043e\u0442\u043d\u0438\u0446\u0430 \u0445\u0440\u0443\u043f\u043a\u0430\u044f, \u043d\u043e \u043d\u0430\u043d\u043e\u0441\u0438\u0442 \u043e\u0433\u0440\u043e\u043c\u043d\u044b\u0439 \u0443\u0440\u043e\u043d \u0441 \u0434\u0438\u0441\u0442\u0430\u043d\u0446\u0438\u0438. \u0412\u043e\u0438\u043d \u0434\u043e\u043b\u0436\u0435\u043d \u0437\u0430\u0449\u0438\u0449\u0430\u0442\u044c \u0435\u0451.',
	'\u0415\u0441\u043b\u0438 \u043d\u043e\u0441\u0438\u043b\u044c\u0449\u0438\u043a \u041a\u0440\u0438\u0441\u0442\u0430\u043b\u043b\u0430 \u043f\u043e\u0433\u0438\u0431\u043d\u0435\u0442, \u041a\u0440\u0438\u0441\u0442\u0430\u043b\u043b \u0443\u043f\u0430\u0434\u0435\u0442 \u043d\u0430 \u0437\u0435\u043c\u043b\u044e. \u0421\u043a\u043e\u0440\u0435\u0435 \u043f\u043e\u0434\u0431\u0435\u0440\u0438\u0442\u0435 \u0435\u0433\u043e!',
]



func _fs(size: int) -> int:
	if DeviceProfile.mobile_ui:
		return maxi(size, 18)
	return size
