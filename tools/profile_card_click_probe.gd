extends Node3D

## Проба кликабельности карточки профиля в лобби (28.11.2026).
##
## Сцена-обёртка (рядом): tools/ProfileCardClickProbe.tscn
##
## Запуск:
##   godot_console --path . tools/ProfileCardClickProbe.tscn
##   godot_console --path . tools/ProfileCardClickProbe.tscn -- --layout=1440x734
##
## Проверяет:
##   1. статику: profile_button (узел PlayerProfile) — Button с
##      mouse_filter STOP/PASS, его rect покрывает иконку, имя, уровень,
##      XP-бар и XP-строку, а у ВСЕХ детей карточки mouse_filter == IGNORE
##      (иначе ребёнок съедает клик и до кнопки он не доходит);
##   2. функцию: настоящий клик (InputEventMouseButton press+release через
##      get_viewport().push_input) по центру иконки, имени, уровня, XP-бара
##      и по пустой правой части карточки открывает player_menu_overlay
##      (узел PlayerMenuOverlay, панель PlayerMenuPanel);
##   3. клик в 20 px левее / правее / выше / ниже карточки меню НЕ открывает.
##
## Итог: PROFILE_CLICK_PASS / PROFILE_CLICK_FAIL + счётчик проверок.
## Скриншот: user://ui_shots/profile_click_1440.png

const SHOT_DIR := "user://ui_shots"

var _pass := 0
var _fail := 0
var _target := Vector2i(1440, 734)

var _lobby: Control
var _card: Button
var _overlay: ColorRect
var _panel: PanelContainer

var _avatar_frame: Control
var _avatar: Control
var _name_holder: Control
var _name_label: Control
var _level_label: Control
var _xp_bar: Control
var _xp_row: Control
var _xp_label: Control


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			var parts := arg.trim_prefix("--layout=").split("x")
			if parts.size() == 2:
				_target = Vector2i(int(parts[0]), int(parts[1]))
	DeviceProfile.mobile_ui = _target.x < 500
	DeviceProfile.touch_controls = DeviceProfile.mobile_ui
	get_tree().root.content_scale_size = _target
	DisplayServer.window_set_size(_target)
	for i in 3:
		await get_tree().process_frame

	# Проба не должна зависеть от сети: локальный недоступный адрес отвечает
	# сразу, а поздние profile_updated не перетирают фикстуры.
	NetworkClient.api_base_url = "http://127.0.0.1:9"
	var packed := load("res://scenes/Lobby.tscn") as PackedScene
	if packed == null:
		print("PROFILE_CLICK_FAIL lobby scene missing")
		get_tree().quit(1)
		return
	_lobby = packed.instantiate() as Control
	add_child(_lobby)
	for i in 10:
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	for signal_name in ["profile_updated", "profile_failed"]:
		var method := "_on_profile_updated" if signal_name == "profile_updated" else "_on_profile_failed"
		var callback := Callable(_lobby, method)
		if MetaProgression.is_connected(signal_name, callback):
			MetaProgression.disconnect(signal_name, callback)
	_lobby.call("_layout_lobby_layout")
	_hide_welcome()
	for i in 3:
		await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout

	_card = _lobby.get("profile_button") as Button
	_overlay = _lobby.get("player_menu_overlay") as ColorRect
	_panel = _lobby.get("player_menu_panel") as PanelContainer
	var view := get_viewport().get_visible_rect().size
	print(
		"PROFILE_CLICK layout=%dx%d view=%.0fx%.0f mobile=%s" % [
			_target.x, _target.y, view.x, view.y, str(DeviceProfile.mobile_ui),
		]
	)
	_check(_card != null, "profile_button (PlayerProfile) найден")
	_check(_overlay != null, "player_menu_overlay (PlayerMenuOverlay) найден")
	_check(_panel != null, "player_menu_panel (PlayerMenuPanel) найден")
	if _card == null or _overlay == null:
		_finish()
		return

	_resolve_parts()
	_check_static_card()
	await _check_inside_clicks()
	await _check_outside_clicks()
	await _save_shot(_shot_name())
	_finish()


## Прячет приветственный оверлей: он z=200 и перекрывает всё лобби, включая
## карточку профиля.
func _hide_welcome() -> void:
	var welcome := _lobby.get("welcome_overlay") as Node
	if welcome == null:
		return
	if welcome.has_method("hide_overlay"):
		welcome.call("hide_overlay")
	if welcome is CanvasItem:
		(welcome as CanvasItem).visible = false


func _resolve_parts() -> void:
	_avatar_frame = _card.find_child("AvatarFrame", true, false) as Control
	_avatar = _lobby.get("avatar") as Control
	_name_holder = _card.find_child("ProfileNameHolder", true, false) as Control
	_name_label = _lobby.get("profile_name_label") as Control
	_level_label = _lobby.get("profile_level_label") as Control
	_xp_bar = _lobby.get("experience_bar") as Control
	_xp_label = _lobby.get("profile_xp_label") as Control
	if _xp_label != null:
		_xp_row = _xp_label.get_parent() as Control


# ---------------------------------------------------------------------------
# 1. Статика карточки


func _check_static_card() -> void:
	var card_rect := _card.get_global_rect()
	print(
		"PROFILE_CLICK card=%s filter=%s rect=%s visible=%s" % [
			_card.name, _filter_name(_card.mouse_filter), str(card_rect),
			str(_card.is_visible_in_tree()),
		]
	)
	print(
		"PROFILE_CLICK overlay=%s panel=%s overlay_visible=%s" % [
			_overlay.name, _panel.name if _panel != null else "<null>",
			str(_overlay.visible),
		]
	)
	_check(_card.name == "PlayerProfile", "карточка = узел PlayerProfile")
	_check(_card.is_visible_in_tree(), "карточка видна в дереве")
	_check(
		_card.mouse_filter == Control.MOUSE_FILTER_STOP
			or _card.mouse_filter == Control.MOUSE_FILTER_PASS,
		"profile_button ловит мышь (mouse_filter=%s)" % _filter_name(_card.mouse_filter)
	)
	_check(
		_card.mouse_filter == Control.MOUSE_FILTER_STOP,
		"profile_button именно STOP, не PASS (%s)" % _filter_name(_card.mouse_filter)
	)
	_check(not _card.disabled, "profile_button не disabled")
	_check(
		_card.pressed.is_connected(Callable(_lobby, "_open_player_menu")),
		"pressed карточки подключён к _open_player_menu"
	)
	_check(_overlay.name == "PlayerMenuOverlay", "окно меню = узел PlayerMenuOverlay")
	_check(_panel != null and _panel.name == "PlayerMenuPanel", "панель меню = узел PlayerMenuPanel")
	_check(not _overlay.visible, "меню закрыто на старте")
	_check(card_rect.size.x > 0.0 and card_rect.size.y > 0.0, "у карточки непустой rect")

	# Кнопка должна физически покрывать все элементы карточки: иначе часть
	# карточки лежит вне кнопки и клик по ней уходит в пустоту.
	var parts := [
		["иконку (AvatarFrame)", _avatar_frame],
		["аватар (PlayerAvatar)", _avatar],
		["держатель имени (ProfileNameHolder)", _name_holder],
		["имя (ProfileName)", _name_label],
		["уровень", _level_label],
		["XP-бар (ExperienceBar)", _xp_bar],
		["XP-строку", _xp_row],
		["XP-текст", _xp_label],
	]
	for entry in parts:
		var node := entry[1] as Control
		var label := String(entry[0])
		if node == null:
			_check(false, "карточка покрывает %s — узел не найден" % label)
			continue
		var rect := node.get_global_rect()
		_check(
			card_rect.grow(0.5).encloses(rect),
			"карточка покрывает %s (rect=%s)" % [label, str(rect)]
		)

	# Главное: все дети карточки обязаны пропускать мышь к кнопке.
	var descendants := _collect_controls(_card)
	var offenders: Array[String] = []
	for node in descendants:
		var child_name := _relative_name(node)
		print("PROFILE_CLICK child %s filter=%s" % [child_name, _filter_name(node.mouse_filter)])
		if node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			offenders.append("%s=%s" % [child_name, _filter_name(node.mouse_filter)])
	_check(descendants.size() >= 8, "детей карточки найдено %d (ожидается >= 8)" % descendants.size())
	var detail := ""
	if not offenders.is_empty():
		detail = " — съедают клик: %s" % ", ".join(PackedStringArray(offenders))
	_check(
		offenders.is_empty(),
		"все %d детей карточки MOUSE_FILTER_IGNORE%s" % [descendants.size(), detail]
	)


# ---------------------------------------------------------------------------
# 2. Клики внутри карточки


func _check_inside_clicks() -> void:
	var card_rect := _card.get_global_rect()
	var mid := card_rect.get_center()
	var points: Array = [
		["иконка", _center(_avatar_frame)],
		["имя", _center(_name_label)],
		["уровень", _center(_level_label)],
		["XP-бар", _center(_xp_bar)],
		# Правое поле карточки: 4 px от правого края, между контентом и рамкой.
		["пустая область справа", Vector2(card_rect.end.x - 4.0, mid.y)],
	]
	if _xp_row != null and _xp_row.visible:
		var xp_rect := _xp_row.get_global_rect()
		points.append([
			"пустая область справа в XP-строке",
			Vector2(xp_rect.end.x - 10.0, xp_rect.get_center().y),
		])
	for entry in points:
		var label := String(entry[0])
		var point: Vector2 = entry[1]
		await _close_menu()
		_check(card_rect.has_point(point), "%s: точка клика внутри карточки %s" % [label, str(point)])
		var blocker := _hit_child(point)
		print(
			"PROFILE_CLICK inside %s at %s blocker=%s" % [
				label, str(point), str(blocker.get_path()) if blocker != null else "<button>",
			]
		)
		_push_click(point)
		await _settle()
		var opened := _overlay.visible
		print("PROFILE_CLICK inside %s menu=%s" % [label, str(opened)])
		_check(opened, "клик по «%s» %s открывает меню" % [label, str(point)])
	await _close_menu()


# ---------------------------------------------------------------------------
# 3. Клики вне карточки


func _check_outside_clicks() -> void:
	var card_rect := _card.get_global_rect()
	var mid := card_rect.get_center()
	var above := Vector2(mid.x, card_rect.position.y - 20.0)
	var points: Array = [
		["левее на 20 px", Vector2(card_rect.position.x - 20.0, mid.y)],
		["правее на 20 px", Vector2(card_rect.end.x + 20.0, mid.y)],
		["выше на 20 px", above],
		["ниже на 20 px", Vector2(mid.x, card_rect.end.y + 20.0)],
	]
	# Карточка стоит на y=18, поэтому «на 20 px выше» = y=-2, за пределами окна.
	# Дополнительно бьём в точку выше карточки, но внутри окна: она не должна
	# открывать меню так же, как и вылет за край.
	if above.y < 0.0:
		points.append(["выше карточки, внутри окна", Vector2(mid.x, card_rect.position.y * 0.5)])

	for entry in points:
		var label := String(entry[0])
		var point: Vector2 = entry[1]
		await _close_menu()
		_check(not card_rect.has_point(point), "%s: точка клика вне карточки %s" % [label, str(point)])
		_push_click(point)
		await _settle()
		var opened := _overlay.visible
		print("PROFILE_CLICK outside %s at %s menu=%s" % [label, str(point), str(opened)])
		_check(not opened, "клик «%s» %s НЕ открывает меню" % [label, str(point)])
	await _close_menu()


# ---------------------------------------------------------------------------
# Ввод: настоящий клик мышью через вьюпорт (press + release).


## Клик настоящими mouse-событиями. push_input(..., true) — координаты уже в
## canvas-пространстве вьюпорта (его же отдаёт Control.get_global_rect()),
## поэтому клик не зависит от масштаба окна (тот же приём в touch_scroll_probe).
func _push_click(point: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	press.global_position = point
	get_viewport().push_input(press, true)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = point
	release.global_position = point
	get_viewport().push_input(release, true)


func _settle() -> void:
	for i in 2:
		await get_tree().process_frame


func _close_menu() -> void:
	if _overlay != null and _overlay.visible:
		_lobby.call("_close_player_menu")
	for i in 2:
		await get_tree().process_frame


# ---------------------------------------------------------------------------
# Утилиты


func _collect_controls(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	for child in root.get_children():
		if child is Control:
			out.append(child)
			out.append_array(_collect_controls(child))
	return out


## Кто съест клик в точке, кроме самой кнопки: идём от самого глубокого
## видимого ребёнка карточки вверх по Control-цепочке до первого STOP
## (PASS, как и в Godot, пробрасывает событие родителю). null = дойдёт до кнопки.
func _hit_child(point: Vector2) -> Control:
	var walk := _topmost_at(point)
	while walk != null and walk != _card:
		if walk.mouse_filter == Control.MOUSE_FILTER_STOP:
			return walk
		walk = walk.get_parent_control()
	return null


func _topmost_at(point: Vector2) -> Control:
	var best: Control = null
	var best_depth := -1
	for node in _collect_controls(_card):
		if node.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if not node.is_visible_in_tree() or not node.get_global_rect().has_point(point):
			continue
		var depth := 0
		var walk: Node = node
		while walk != null and walk != _card:
			depth += 1
			walk = walk.get_parent()
		if depth >= best_depth:
			best_depth = depth
			best = node
	return best


func _relative_name(node: Node) -> String:
	if _card == null:
		return str(node.name)
	return str(_card.get_path_to(node))


func _center(control: Control) -> Vector2:
	if control == null:
		return Vector2.ZERO
	return control.get_global_rect().get_center()


func _filter_name(value: int) -> String:
	match value:
		Control.MOUSE_FILTER_STOP:
			return "STOP"
		Control.MOUSE_FILTER_PASS:
			return "PASS"
		Control.MOUSE_FILTER_IGNORE:
			return "IGNORE"
	return "UNKNOWN(%d)" % value


func _shot_name() -> String:
	if _target == Vector2i(1440, 734):
		return "profile_click_1440"
	return "profile_click_%dx%d" % [_target.x, _target.y]


func _save_shot(file_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, file_name]
	image.save_png(path)
	print("PROFILE_CLICK shot=", path, " -> ", ProjectSettings.globalize_path(path))


func _check(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("PROFILE_CLICK PASS ", label)
	else:
		_fail += 1
		print("PROFILE_CLICK FAIL ", label)


func _finish() -> void:
	print("PROFILE_CLICK checks pass=%d fail=%d" % [_pass, _fail])
	print("PROFILE_CLICK_%s" % ("PASS" if _fail == 0 else "FAIL"))
	print("PROFILE_CLICK_DIR=", ProjectSettings.globalize_path(SHOT_DIR))
	get_tree().quit(0 if _fail == 0 else 1)
