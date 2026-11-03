extends CanvasLayer

var game: Node
var font: SystemFont

var score_label: Label
var timer_label: Label
var objective_label: Label
var announce_label: Label
var class_label: Label
var carry_label: Label
var health_bar: ProgressBar
var ability_buttons: Array[Button] = []
var ability_cd_labels: Array[Label] = []
var ability_name_labels: Array[Label] = []
var select_panel: Control
var end_panel: Control
var end_title: Label
var end_score: Label
var player_panel: PanelContainer
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
	_build_player_panel(root)
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
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.96, 0.82, 0.52, 0.55)))
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -190.0
	panel.offset_right = 190.0
	panel.offset_top = 14.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	score_label = _make_label("СВЕТ  0 : 0  ТЬМА", 26, GOLD)
	box.add_child(score_label)
	timer_label = _make_label("05:00", 40, PALE)
	box.add_child(timer_label)
	objective_label = _make_label("", 19, Color(0.82, 0.88, 1.0))
	box.add_child(objective_label)


func _build_player_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	player_panel = panel
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.6, 0.85, 1.0, 0.5)))
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 20.0
	panel.offset_top = -130.0
	panel.offset_right = 330.0
	panel.offset_bottom = -20.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	class_label = _make_label("", 24, GOLD)
	class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(class_label)

	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(280, 18)
	health_bar.show_percentage = false
	health_bar.max_value = 100.0
	health_bar.value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.06, 0.1, 0.9)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.4, 0.92, 0.6)
	fill.set_corner_radius_all(4)
	health_bar.add_theme_stylebox_override("background", bg)
	health_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(health_bar)

	carry_label = _make_label("", 18, Color(0.72, 0.95, 1.0))
	carry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(carry_label)


func _build_abilities(root: Control) -> void:
	var row := HBoxContainer.new()
	ability_row = row
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	row.anchor_left = 1.0
	row.anchor_top = 1.0
	row.anchor_right = 1.0
	row.anchor_bottom = 1.0
	row.offset_left = -466.0
	row.offset_top = -128.0
	row.offset_right = -20.0
	row.offset_bottom = -20.0
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(row)

	for i in 3:
		var button := Button.new()
		button.custom_minimum_size = Vector2(142, 96)
		button.clip_contents = true
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", _panel_style(Color(0.65, 0.8, 1.0, 0.45)))
		button.add_theme_stylebox_override("hover", _panel_style(Color(0.9, 0.85, 0.6, 0.8)))
		button.add_theme_stylebox_override("pressed", _panel_style(Color(1.0, 0.9, 0.6, 0.95)))
		button.pressed.connect(_on_ability_pressed.bind(i))
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 2)
		button.add_child(box)
		var key := _make_label(str(i + 1), 20, GOLD)
		box.add_child(key)
		var name_label := _make_label("", 15, PALE)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.custom_minimum_size = Vector2(118, 34)
		name_label.clip_text = true
		box.add_child(name_label)
		var cd := _make_label("", 16, Color(0.7, 0.9, 1.0))
		box.add_child(cd)
		row.add_child(button)
		ability_buttons.append(button)
		ability_cd_labels.append(cd)
		ability_name_labels.append(name_label)


func _build_announcement(root: Control) -> void:
	announce_label = _make_label("", 40, GOLD)
	announce_label.set_anchors_preset(Control.PRESET_CENTER)
	announce_label.anchor_left = 0.0
	announce_label.anchor_right = 1.0
	announce_label.anchor_top = 0.18
	announce_label.anchor_bottom = 0.18
	announce_label.offset_top = 90.0
	announce_label.offset_bottom = 150.0
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
	var t: float = maxf(0.0, game.match_time)
	var minutes := int(t) / 60
	var seconds := int(t) % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]
	if game.sudden_death:
		timer_label.text = "РЕШАЮЩИЙ"
	score_label.text = "СВЕТ  %d : %d  ТЬМА" % [game.score[0], game.score[1]]
	objective_label.text = game.objective_text()
	var playing: bool = game.state != "select"
	if player_panel != null:
		player_panel.visible = playing
	if ability_row != null:
		ability_row.visible = playing

	if game.player != null:
		var p = game.player
		class_label.text = "Ты: " + str(HeroUnit.CLASS_DATA[p.hero_class]["title"])
		health_bar.max_value = p.max_health
		health_bar.value = p.health
		if p.dead:
			carry_label.text = "Возрождение через %.0f с" % maxf(0.0, p.respawn_timer)
		elif p.carrying:
			carry_label.text = "Осколок у тебя — скорость вдвое ниже"
		elif p.stun_timer > 0.0:
			carry_label.text = "Оглушён"
		else:
			carry_label.text = ""
		for i in 3:
			var data: Dictionary = HeroUnit.CLASS_DATA[p.hero_class]["abilities"][i]
			ability_name_labels[i].text = str(data["name"])
			var cd: float = p.ability_cds[i]
			ability_cd_labels[i].text = "готово" if cd <= 0.01 else "%.1f с" % cd
			ability_buttons[i].modulate = Color(1, 1, 1, 1) if cd <= 0.01 else Color(0.6, 0.62, 0.7, 1)

	if game.state == "over":
		end_panel.visible = true
		end_title.text = game.result_text
		end_title.add_theme_color_override("font_color", Color(0.85, 1.0, 0.7) if game.player_won else Color(1.0, 0.55, 0.5))
		end_score.text = "Свет %d : %d Тьма" % [game.score[0], game.score[1]]
