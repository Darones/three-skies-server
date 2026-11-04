extends CanvasLayer

var game: Node
var font: SystemFont

var score_label: Label
var timer_label: Label
var shell_timer_label: Label
var respawn_label: Label
var announce_label: Label
var ability_buttons: Array[Button] = []
var ability_cd_labels: Array[Label] = []
var ability_name_labels: Array[Label] = []
var select_panel: Control
var end_panel: Control
var end_title: Label
var end_score: Label
var ability_row: HBoxContainer
var announce_tween: Tween

const GOLD := Color(0.96, 0.82, 0.52)
const PALE := Color(0.86, 0.9, 1.0)
const DARK_BG := Color(0.05, 0.05, 0.09, 0.78)


func _ready() -> void:
	layer = 10
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Georgia", "Palatino Linotype", "Times New Roman"])
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_top(root)
	_build_abilities(root)
	_build_announcement(root)
	_build_select(root)
	_build_end(root)


func _panel_style(border: Color, fill := DARK_BG) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_top(root: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "MatchInfo"
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -360.0
	box.offset_top = 20.0
	box.offset_right = -20.0
	box.offset_bottom = 112.0
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)

	score_label = _make_label("Свет 0 : 0 Тьма", 24, Color.WHITE)
	var semibold_font := SystemFont.new()
	semibold_font.font_names = font.font_names
	semibold_font.font_weight = 600
	score_label.add_theme_font_override("font", semibold_font)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(score_label)

	timer_label = _make_label("05:00", 20, Color.WHITE)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(timer_label)

	shell_timer_label = _make_label("Оболочка: 00:08", 16, Color(0.66, 0.68, 0.72))
	shell_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(shell_timer_label)

	respawn_label = _make_label("", 16, Color(1.0, 0.38, 0.28))
	respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	respawn_label.visible = false
	box.add_child(respawn_label)


func _build_abilities(root: Control) -> void:
	var row := HBoxContainer.new()
	ability_row = row
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	row.anchor_left = 1.0
	row.anchor_top = 1.0
	row.anchor_right = 1.0
	row.anchor_bottom = 1.0
	row.offset_left = -296.0
	row.offset_top = -104.0
	row.offset_right = -20.0
	row.offset_bottom = -20.0
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(row)

	for i in 3:
		var button := Button.new()
		button.custom_minimum_size = Vector2(84, 84)
		button.clip_contents = true
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", _ability_style(i, false))
		button.add_theme_stylebox_override("hover", _ability_style(i, true))
		button.add_theme_stylebox_override("pressed", _ability_style(i, true))
		button.pressed.connect(_on_ability_pressed.bind(i))
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 0)
		button.add_child(box)
		var key := _make_label(str(i + 1) + " / " + ["A", "B", "X"][i], 14, Color.WHITE)
		box.add_child(key)
		var name_label := _make_label("", 10, PALE)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		
		name_label.custom_minimum_size = Vector2(70, 28)
		name_label.clip_text = true
		box.add_child(name_label)
		var cd := _make_label("", 11, Color(0.7, 0.9, 1.0))
		box.add_child(cd)
		row.add_child(button)
		ability_buttons.append(button)
		ability_cd_labels.append(cd)
		ability_name_labels.append(name_label)

func _ability_style(index: int, hovered: bool) -> StyleBoxFlat:
	var accents := [Color(0.22, 0.82, 0.42), Color(0.91, 0.28, 0.31), Color(0.2, 0.55, 0.96)]
	var accent: Color = accents[index]
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.r, accent.g, accent.b, 0.38 if not hovered else 0.62)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.82 if not hovered else 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(42)
	style.content_margin_left = 2.0
	style.content_margin_right = 2.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style

func _build_announcement(root: Control) -> void:
	announce_label = _make_label("", 18, GOLD)
	announce_label.anchor_left = 0.0
	announce_label.anchor_right = 1.0
	announce_label.anchor_top = 0.0
	announce_label.anchor_bottom = 0.0
	announce_label.offset_left = 80.0
	announce_label.offset_right = -80.0
	announce_label.offset_top = 100.0
	announce_label.offset_bottom = 140.0
	announce_label.modulate.a = 0.0
	announce_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(announce_label)


func _build_select(root: Control) -> void:
	select_panel = Control.new()
	select_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	select_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(select_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.07, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	select_panel.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -330.0
	box.offset_right = 330.0
	box.offset_top = -210.0
	box.offset_bottom = 170.0
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	select_panel.add_child(box)

	var title := _make_label("ОСКОЛКИ НЕБА", 56, GOLD)
	box.add_child(title)
	var subtitle := _make_label("Выбери героя света", 22, Color(0.85, 0.9, 1.0))
	box.add_child(subtitle)

	var classes := ["Воин — врывается и оглушает", "Маг — лечит и держит лозами", "Фея — бьёт издалека и оглушает"]
	for i in 3:
		var button := Button.new()
		button.custom_minimum_size = Vector2(640, 62)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", _panel_style(Color(0.9, 0.8, 0.55, 0.55)))
		button.add_theme_stylebox_override("hover", _panel_style(Color(1.0, 0.9, 0.65, 0.95), Color(0.1, 0.08, 0.14, 0.9)))
		button.add_theme_stylebox_override("pressed", _panel_style(Color(1.0, 0.95, 0.8, 1.0), Color(0.14, 0.11, 0.18, 0.95)))
		var label := _make_label(str(i + 1) + ".  " + classes[i], 22, PALE)
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		button.add_child(label)
		button.pressed.connect(_on_class_pressed.bind(i))
		box.add_child(button)

	var hint := _make_label("WASD — движение · 1 2 3 — способности · цель: 3 осколка", 17, Color(0.75, 0.8, 0.9))
	box.add_child(hint)


func _build_end(root: Control) -> void:
	end_panel = Control.new()
	end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.visible = false
	root.add_child(end_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.68)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -320.0
	box.offset_right = 320.0
	box.offset_top = -140.0
	box.offset_bottom = 120.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	end_panel.add_child(box)
	end_title = _make_label("", 64, GOLD)
	box.add_child(end_title)
	end_score = _make_label("", 30, PALE)
	box.add_child(end_score)
	var hint := _make_label("R или клик — новый бой", 20, Color(0.8, 0.85, 0.95))
	box.add_child(hint)


func _on_ability_pressed(index: int) -> void:
	if game != null and game.player != null:
		game.player.use_ability(index)


func _on_class_pressed(index: int) -> void:
	if game == null:
		return
	var classes := [HeroUnit.Cls.WARRIOR, HeroUnit.Cls.MAGE, HeroUnit.Cls.FAIRY]
	game.start_match(classes[index])


func hide_class_select() -> void:
	if select_panel != null:
		select_panel.visible = false


func show_announcement(text: String, color: Color, duration: float) -> void:
	if announce_label == null:
		return
	announce_label.text = text
	announce_label.add_theme_color_override("font_color", color)
	if announce_tween != null and announce_tween.is_valid():
		announce_tween.kill()
	announce_tween = create_tween()
	announce_label.modulate.a = 0.0
	announce_tween.tween_property(announce_label, "modulate:a", 1.0, 0.2)
	announce_tween.tween_interval(duration)
	announce_tween.tween_property(announce_label, "modulate:a", 0.0, 0.7)


func _process(_delta: float) -> void:
	if game == null:
		return
	var match_time_left: float = maxf(0.0, game.match_time)
	var match_minutes := floori(match_time_left / 60.0)
	var match_seconds := int(match_time_left) % 60
	timer_label.text = "%02d:%02d" % [match_minutes, match_seconds]
	if game.sudden_death:
		timer_label.text = "РЕШАЮЩИЙ"
	score_label.text = "Свет %d : %d Тьма" % [game.score[0], game.score[1]]
	var shell_time_left: float = game.shell_window if game.shell_phase == "active" else game.shell_timer
	shell_time_left = maxf(0.0, shell_time_left)
	var shell_minutes := floori(shell_time_left / 60.0)
	var shell_seconds := int(shell_time_left) % 60
	shell_timer_label.text = "Оболочка: %02d:%02d" % [shell_minutes, shell_seconds]
	if ability_row != null:
		ability_row.visible = game.state != "select"

	if game.player != null:
		var p = game.player
		respawn_label.visible = p.dead
		if p.dead:
			respawn_label.text = "Возрождение: %dс" % int(ceil(maxf(0.0, p.respawn_timer)))
		else:
			respawn_label.text = ""
		for i in 3:
			var data: Dictionary = HeroUnit.CLASS_DATA[p.hero_class]["abilities"][i]
			ability_name_labels[i].text = str(data["name"])
			var cd: float = p.ability_cds[i]
			ability_cd_labels[i].text = "готово" if cd <= 0.01 else "%.1f с" % cd
			ability_buttons[i].modulate = Color(1, 1, 1, 1) if cd <= 0.01 else Color(0.6, 0.62, 0.7, 1)
	else:
		respawn_label.visible = false

	if game.state == "over":
		end_panel.visible = true
		end_title.text = game.result_text
		end_title.add_theme_color_override("font_color", Color(0.85, 1.0, 0.7) if game.player_won else Color(1.0, 0.55, 0.5))
		end_score.text = "Свет %d : %d Тьма" % [game.score[0], game.score[1]]
