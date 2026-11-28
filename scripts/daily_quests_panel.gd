extends Control

## Ежедневные задания — вариант A (Quest cards).
##
## INLINE  — компактный премиум-список в лобби (380/345 px), без кнопок замены.
## OVERLAY — окно 812x338: 3 карточки 248x172, кольца прогресса, футер недели.
##
## Панель рисует состояние DailyQuests и отправляет намерения сигналами.
## Контракт источника: quests/week/rerolls/summary или snapshot(), сигнал
## quests_updated; замена → request_reroll/reroll, неделя → request_weekly_claim.

signal reroll_requested(slot: int)
signal weekly_claim_requested(item_id: int)
signal open_requested
signal closed
signal data_changed(completed: int, total: int)

enum Mode { INLINE, OVERLAY }

const MODE_INLINE := 0
const MODE_OVERLAY := 1

const UI_FONT: FontFile = preload("res://assets/fonts/Philosopher-Regular.ttf")
const SHARD_ICON: Texture2D = preload("res://ui/icons/sky_shard.png")

const GOLD := Color(0.94, 0.75, 0.31)
const PALE := Color(0.914, 0.937, 0.984)
const MUTED := Color(0.576, 0.639, 0.745)
const SUCCESS := Color(0.561, 0.89, 0.651)
const CARD_A := Color(0.071, 0.165, 0.255)
const CARD_B := Color(0.035, 0.075, 0.122)
const KILLS := Color(0.886, 0.439, 0.369)
const DAMAGE := Color(0.941, 0.592, 0.306)
const SHOP := Color(0.498, 0.78, 1.0)
const DONE := Color(0.561, 0.89, 0.651)

const INLINE_HEIGHTS := [48.0, 154.0, 200.0, 246.0]
const OVERLAY_HEIGHT := 338.0
const OVERLAY_EMPTY_HEIGHT := 136.0
const OVERLAY_WIDTH := 812.0
const WEEK_REQUIRED := 7
const WEEKLY_REWARD_SHARDS := 300
const MAX_ROWS := 3
const TWEEN_TIME := 0.18
const RING_TIME := 0.5

const RING_SHADER_CODE := """
shader_type canvas_item;
uniform float progress = 0.0;
uniform vec4 ring_color : source_color = vec4(0.94, 0.75, 0.31, 1.0);
uniform vec4 track_color : source_color = vec4(1.0, 1.0, 1.0, 0.13);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0 || r < 0.74) {
		discard;
	}
	float angle = atan(p.y, p.x);
	float t = (angle + 3.14159265) / 6.2831853;
	COLOR = t <= progress ? ring_color : track_color;
}
"""

const WEEK_LETTERS := ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

const TEMPLATE_TITLES := {
	"kills_8": "Убить 8 врагов",
	"kills_12": "Убить 12 врагов",
	"triple_kill": "3 убийства за бой",
	"damage_4000": "Нанести урон 4000",
	"damage_7000": "Нанести урон 7000",
	"shells_2": "Разрушить 2 снаряда",
	"crystal_2": "Доставить 2 кристалла",
	"crystal_3": "Доставить 3 кристалла",
	"play_2": "Сыграть 2 боя",
	"play_3": "Сыграть 3 боя",
	"win_1": "Победить",
	"win_2": "Победить 2 раза",
	"fast_win": "Победа за 7 мин",
	"fast_win_2": "2 быстрые победы",
	"buy_2": "Купить 2 усиления",
	"buy_3": "Купить 3 усиления",
	"survive_win": "Выжить и победить",
}

var mode: int = Mode.INLINE
var desktop_overlay := false

var data: Dictionary = {}
var quests: Array = []
var week_days: Array = []
var rerolls: Variant = {}
var summary: Dictionary = {}

var panel: Panel
var content: Control
var header: Control
var title_label: Label
var timer_label: Label
var count_label: Label
var count_pill: Panel
var close_button: Button
var explanation_label: Label
var rows_layer: Control
var footer: Control

var row_nodes: Array[Control] = []
var card_nodes: Array[Control] = []
var ring_materials: Array[ShaderMaterial] = []
var week_diamonds: Array[Label] = []
var week_label: Label
var status_label: Label
var reward_chip: Panel
var reward_amount_label: Label
var reward_sub_label: Label
var status_icon: TextureRect
var claim_button: Button
var open_button: Button

var _tween: Tween
var _built := false


func _ready() -> void:
	if _built:
		return
	_built = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	if mode == Mode.OVERLAY:
		z_index = 42
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		visible = false
		_build_dim()
	else:
		mouse_filter = Control.MOUSE_FILTER_PASS
	_build_panel()
	_build_content()
	if mode == Mode.INLINE:
		_build_open_button()
	_set_height(0, false)
	_connect_source()
	call_deferred("_layout_content")


func is_overlay_open() -> bool:
	return mode == Mode.OVERLAY and visible


func panel_height_for(count: int) -> float:
	if mode == Mode.OVERLAY:
		return OVERLAY_EMPTY_HEIGHT if count <= 0 else OVERLAY_HEIGHT
	return float(INLINE_HEIGHTS[clampi(count, 0, MAX_ROWS)])


func open_overlay() -> void:
	if mode != Mode.OVERLAY:
		return
	visible = true
	refresh_from_source()
	_layout_content()
	_apply_height(true)
	panel.pivot_offset = panel.size * 0.5
	panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	panel.scale = Vector2(0.97, 0.97)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.12)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_CUBIC)


func close_overlay() -> void:
	if mode != Mode.OVERLAY or not visible:
		return
	visible = false
	closed.emit()


func refresh_from_source() -> void:
	var source := _source()
	if source == null:
		apply_data({})
		return
	var payload: Variant = null
	if source.has_method("snapshot"):
		payload = source.call("snapshot")
	if payload is Dictionary:
		apply_data(payload)
		return
	var collected: Dictionary = {}
	for key in ["quests", "week", "rerolls", "summary", "daily"]:
		var value: Variant = source.get(key)
		if value != null:
			collected[key] = value
	if collected.get("daily") is Dictionary:
		var daily := collected["daily"] as Dictionary
		for key in ["quests", "week", "rerolls", "summary"]:
			if not collected.has(key) and daily.has(key):
				collected[key] = daily[key]
	apply_data(collected)


func apply_data(raw: Dictionary) -> void:
	data = raw.duplicate(true) if raw != null else {}
	quests = _normalize_quests(data.get("quests", []))
	week_days = _normalize_week(data.get("week", data.get("week_days", [])))
	rerolls = data.get("rerolls", {})
	summary = {}
	if data.get("summary") is Dictionary:
		summary = (data.get("summary") as Dictionary).duplicate(true)
	if data.get("week") is Dictionary:
		var week_raw := data["week"] as Dictionary
		if not summary.has("week") and week_raw.has("tier"):
			summary["week"] = week_raw
	_rebuild_rows()
	_refresh_texts()
	_layout_content()
	_apply_height(true)
	data_changed.emit(completed_count(), total_count())


func total_count() -> int:
	var total := int(summary.get("total", MAX_ROWS))
	if total <= 0:
		total = MAX_ROWS
	return total


func completed_count() -> int:
	if summary.has("completed"):
		return clampi(int(summary["completed"]), 0, total_count())
	var done := 0
	for quest in quests:
		if bool(quest.get("completed", false)):
			done += 1
	return clampi(done, 0, total_count())


# ---------------------------------------------------------------------------
# Построение


func _build_dim() -> void:
	var dim := ColorRect.new()
	dim.name = "DailyQuestsDim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.005, 0.008, 0.018, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)


func _build_panel() -> void:
	panel = Panel.new()
	panel.name = "DailyQuestsPanel"
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.clip_contents = true
	if mode == Mode.OVERLAY:
		var width := minf(OVERLAY_WIDTH, get_viewport_rect().size.x - 32.0)
		panel.anchor_left = 0.5
		panel.anchor_right = 0.5
		panel.anchor_top = 0.5
		panel.anchor_bottom = 0.5
		panel.offset_left = -width * 0.5
		panel.offset_right = width * 0.5
		panel.offset_top = -OVERLAY_EMPTY_HEIGHT * 0.5
		panel.offset_bottom = OVERLAY_EMPTY_HEIGHT * 0.5
		panel.resized.connect(_layout_content)
	else:
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.resized.connect(_layout_content)
	add_child(panel)


func _build_open_button() -> void:
	open_button = Button.new()
	open_button.name = "DailyQuestsOpenButton"
	open_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	open_button.focus_mode = Control.FOCUS_NONE
	open_button.mouse_filter = Control.MOUSE_FILTER_STOP
	open_button.tooltip_text = "Открыть ежедневные задания"
	for style_name in ["normal", "hover", "pressed", "focus"]:
		open_button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	open_button.pressed.connect(func() -> void: open_requested.emit())
	open_button.z_index = 20
	add_child(open_button)


func _build_content() -> void:
	content = Control.new()
	content.name = "DailyQuestsContent"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(content)

	header = Control.new()
	header.name = "DailyQuestsHeader"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(header)

	var diamond := _make_label("◆", 18 if mode == Mode.OVERLAY else 12, GOLD)
	diamond.name = "DailyQuestsDiamond"
	header.add_child(diamond)

	title_label = _make_label("ЕЖЕДНЕВНЫЕ ЗАДАНИЯ", 24 if mode == Mode.OVERLAY else 14, GOLD)
	title_label.name = "DailyQuestsTitle"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title_label)

	timer_label = _make_label("обновление через —", 16 if mode == Mode.OVERLAY else 11, MUTED)
	timer_label.name = "DailyQuestsTimer"
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(timer_label)

	count_label = _make_label("0/3", 13, GOLD)
	count_label.name = "DailyQuestsCount"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(count_label)
	count_pill = Panel.new()
	count_pill.name = "DailyQuestsPill"
	count_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = Color(0.08, 0.13, 0.2, 0.95)
	pill_style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55)
	pill_style.set_border_width_all(1)
	pill_style.set_corner_radius_all(13)
	count_pill.add_theme_stylebox_override("panel", pill_style)
	header.add_child(count_pill)
	header.move_child(count_pill, count_label.get_index())

	explanation_label = _make_label(
		"1 замена в день бесплатно · ещё 2 — по 1 осколку", 14, MUTED
	)
	explanation_label.name = "DailyQuestsExplanation"
	explanation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	explanation_label.visible = mode == Mode.OVERLAY
	header.add_child(explanation_label)

	close_button = _make_button("×", 20, false, "DailyQuestsClose")
	close_button.visible = mode == Mode.OVERLAY
	close_button.pressed.connect(close_overlay)
	header.add_child(close_button)

	rows_layer = Control.new()
	rows_layer.name = "DailyQuestsRows"
	rows_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(rows_layer)

	footer = Control.new()
	footer.name = "DailyQuestsFooter"
	footer.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(footer)
	_build_footer()


func _build_footer() -> void:
	for i in WEEK_REQUIRED:
		var diamond := _make_label("◆", 18 if mode == Mode.OVERLAY else 12, MUTED)
		diamond.name = "DailyQuestsDay%d" % i
		diamond.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		diamond.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		footer.add_child(diamond)
		week_diamonds.append(diamond)

	week_label = _make_label("0/7 полных дней", 14 if mode == Mode.OVERLAY else 11, PALE)
	week_label.name = "DailyQuestsWeek"
	week_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	footer.add_child(week_label)

	status_label = _make_label("", 12 if mode == Mode.OVERLAY else 9, MUTED)
	status_label.name = "DailyQuestsWeeklyStatus"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.clip_text = true
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(status_label)

	reward_chip = Panel.new()
	reward_chip.name = "DailyQuestsRewardChip"
	reward_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(0.05, 0.09, 0.14, 0.95)
	chip_style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.45)
	chip_style.set_border_width_all(1)
	chip_style.set_corner_radius_all(10)
	reward_chip.add_theme_stylebox_override("panel", chip_style)
	footer.add_child(reward_chip)

	status_icon = TextureRect.new()
	status_icon.name = "DailyQuestsRewardShard"
	status_icon.texture = SHARD_ICON
	status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	status_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reward_chip.add_child(status_icon)

	reward_amount_label = _make_label("300", 20 if mode == Mode.OVERLAY else 12, GOLD)
	reward_amount_label.name = "DailyQuestsRewardAmount"
	reward_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	reward_chip.add_child(reward_amount_label)

	reward_sub_label = _make_label("за 7/7 дней", 10 if mode == Mode.OVERLAY else 8, MUTED)
	reward_sub_label.name = "DailyQuestsRewardSub"
	reward_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	reward_sub_label.visible = mode == Mode.OVERLAY
	reward_chip.add_child(reward_sub_label)

	claim_button = _make_button("Забрать 300", 14 if mode == Mode.OVERLAY else 10, true, "DailyQuestsClaim")
	claim_button.pressed.connect(_on_claim_pressed)
	footer.add_child(claim_button)


# ---------------------------------------------------------------------------
# Строки / карточки


func _normalize_quests(raw: Variant) -> Array:
	var result: Array = []
	if not (raw is Array):
		return result
	var list := raw as Array
	for index in list.size():
		if result.size() >= MAX_ROWS:
			break
		var source: Variant = list[index]
		if not (source is Dictionary):
			continue
		var quest := (source as Dictionary).duplicate(true)
		var template_id := String(quest.get("template_id", ""))
		if String(quest.get("title", "")).is_empty():
			quest["title"] = String(TEMPLATE_TITLES.get(template_id, "Задание"))
		quest["slot"] = int(quest.get("slot", index))
		quest["target"] = maxi(1, int(quest.get("target", 1)))
		quest["progress"] = clampi(int(quest.get("progress", 0)), 0, int(quest["target"]))
		quest["completed"] = bool(quest.get("completed", int(quest["progress"]) >= int(quest["target"])))
		result.append(quest)
	return result


func _normalize_week(raw: Variant) -> Array:
	var source: Array = []
	if raw is Array:
		source = raw as Array
	elif raw is Dictionary:
		var day_list: Variant = raw.get("days", raw.get("week", []))
		if day_list is Array:
			source = day_list
	var result: Array = []
	for i in WEEK_REQUIRED:
		var day: Dictionary = {}
		if i < source.size() and source[i] is Dictionary:
			day = (source[i] as Dictionary).duplicate(true)
		result.append(day)
	return result


func _rebuild_rows() -> void:
	for node in row_nodes:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	row_nodes.clear()
	for node in card_nodes:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	card_nodes.clear()
	ring_materials.clear()
	if mode == Mode.INLINE:
		for index in quests.size():
			var row := _make_inline_row(index, quests[index] as Dictionary)
			rows_layer.add_child(row)
			row_nodes.append(row)
	else:
		for index in quests.size():
			var card := _make_card(index, quests[index] as Dictionary)
			rows_layer.add_child(card)
			card_nodes.append(card)
	rows_layer.visible = not (row_nodes.is_empty() and card_nodes.is_empty())


func _make_inline_row(index: int, quest: Dictionary) -> Control:
	var completed := bool(quest.get("completed", false))
	var accent := _quest_accent(quest)
	var row := Panel.new()
	row.name = "DailyQuestsRow%d" % index
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.095, 0.145, 0.92)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	row.add_theme_stylebox_override("panel", style)

	var icon := _make_medallion(28.0, accent, quest)
	icon.name = "DailyQuestsIcon%d" % index
	row.add_child(icon)

	var title := _make_label(String(quest["title"]), 14, DONE if completed else PALE)
	title.name = "DailyQuestsRowTitle%d" % index
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(title)

	var bar := ProgressBar.new()
	bar.name = "DailyQuestsRowBar%d" % index
	bar.min_value = 0.0
	bar.max_value = float(quest["target"])
	bar.value = float(quest["progress"])
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.08, 0.11, 0.16, 0.95)
	bar_bg.set_corner_radius_all(2)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = DONE if completed else accent
	bar_fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bar_bg)
	bar.add_theme_stylebox_override("fill", bar_fill)
	row.add_child(bar)

	var progress := _make_label(
		"%d/%d" % [int(quest["progress"]), int(quest["target"])], 10,
		DONE if completed else MUTED
	)
	progress.name = "DailyQuestsProgress%d" % index
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(progress)

	var shard := TextureRect.new()
	shard.name = "DailyQuestsRewardIcon%d" % index
	shard.texture = SHARD_ICON
	shard.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shard.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(shard)
	var amount := _make_label(
		"✓" if completed else "%d" % int(quest.get("reward_shards", 0)), 10,
		DONE if completed else GOLD
	)
	amount.name = "DailyQuestsReward%d" % index
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(amount)
	return row


func _make_card(index: int, quest: Dictionary) -> Control:
	var completed := bool(quest.get("completed", false))
	var accent := DONE if completed else _quest_accent(quest)
	var card := Panel.new()
	card.name = "DailyQuestsCard%d" % index
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.04, 0.08, 0.125, 0.96)
	card_style.border_color = Color(accent.r, accent.g, accent.b, 0.28)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(14)
	card_style.content_margin_left = 0.0
	card_style.content_margin_right = 0.0
	card_style.content_margin_top = 0.0
	card_style.content_margin_bottom = 0.0
	card.add_theme_stylebox_override("panel", card_style)

	var gradient := TextureRect.new()
	gradient.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gradient.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gradient.stretch_mode = TextureRect.STRETCH_SCALE
	gradient.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := GradientTexture2D.new()
	texture.gradient = Gradient.new()
	(texture.gradient as Gradient).set_color(0, CARD_A)
	(texture.gradient as Gradient).set_color(1, CARD_B)
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	gradient.texture = texture
	card.add_child(gradient)

	var accent_bar := ColorRect.new()
	accent_bar.name = "DailyQuestsAccent%d" % index
	accent_bar.color = accent
	accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(accent_bar)

	var sheen := ColorRect.new()
	sheen.color = Color(1.0, 1.0, 1.0, 0.32)
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(sheen)

	var icon := _make_medallion(40.0, accent, quest)
	icon.name = "DailyQuestsIcon%d" % index
	card.add_child(icon)

	var title := _make_label(String(quest["title"]), 19, DONE if completed else PALE)
	title.name = "DailyQuestsCardTitle%d" % index
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	card.add_child(title)

	var reroll := _make_button("↻", 16, false, "DailyQuestsReroll%d" % index)
	reroll.visible = not completed
	reroll.tooltip_text = "Заменить задание"
	var state := _reroll_state()
	var slot_state := _slot_reroll_state(int(quest["slot"]))
	if not slot_state.is_empty() and not completed:
		_apply_slot_state(state, slot_state)
	reroll.disabled = not bool(state.get("available", false))
	reroll.tooltip_text = String(state.get("hint", "Заменить задание"))
	if not completed:
		reroll.pressed.connect(_on_reroll_pressed.bind(int(quest["slot"])))
	card.add_child(reroll)

	var ring := ColorRect.new()
	ring.name = "DailyQuestsRing%d" % index
	ring.color = Color.WHITE
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring_material := ShaderMaterial.new()
	var ring_shader := Shader.new()
	ring_shader.code = RING_SHADER_CODE
	ring_material.shader = ring_shader
	ring_material.set_shader_parameter("ring_color", accent)
	ring_material.set_shader_parameter("progress", 0.0)
	ring.material = ring_material
	card.add_child(ring)
	ring_materials.append(ring_material)

	var ratio := float(quest["progress"]) / maxf(1.0, float(quest["target"]))
	var percent := _make_label("%d%%" % int(round(ratio * 100.0)), 14, PALE)
	percent.name = "DailyQuestsPercent%d" % index
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(percent)

	var check := _make_label("✓", 26, DONE)
	check.name = "DailyQuestsCheck%d" % index
	check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	check.visible = completed
	card.add_child(check)

	var progress := _make_label(
		"%d из %d" % [int(quest["progress"]), int(quest["target"])], 14, PALE
	)
	progress.name = "DailyQuestsProgress%d" % index
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(progress)

	var remaining := _make_label(
		"награда зачислена" if completed else "осталось %d" % maxi(
			0, int(quest["target"]) - int(quest["progress"])
		),
		12, DONE if completed else MUTED
	)
	remaining.name = "DailyQuestsRemaining%d" % index
	remaining.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	remaining.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(remaining)

	var chip := Panel.new()
	chip.name = "DailyQuestsRewardChip%d" % index
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(0.05, 0.09, 0.14, 0.95)
	chip_style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.4)
	chip_style.set_border_width_all(1)
	chip_style.set_corner_radius_all(9)
	chip.add_theme_stylebox_override("panel", chip_style)
	card.add_child(chip)

	var chip_icon := TextureRect.new()
	chip_icon.name = "DailyQuestsRewardIcon%d" % index
	chip_icon.texture = SHARD_ICON
	chip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chip_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(chip_icon)
	var chip_label := _make_label("%d" % int(quest.get("reward_shards", 0)), 16, GOLD)
	chip_label.name = "DailyQuestsReward%d" % index
	chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(chip_label)

	if completed:
		ring_material.set_shader_parameter("progress", 1.0)
	elif visible:
		var target_progress := clampf(ratio, 0.0, 1.0)
		var tween := create_tween()
		tween.tween_method(
			func(value: float) -> void:
				ring_material.set_shader_parameter("progress", value),
			0.0, target_progress, RING_TIME
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return card


func _make_medallion(size: float, accent: Color, quest: Dictionary) -> Panel:
	var medallion := Panel.new()
	medallion.custom_minimum_size = Vector2(size, size)
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.1, 0.98)
	style.border_color = accent
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(size * 0.5))
	medallion.add_theme_stylebox_override("panel", style)
	var icon := TextureRect.new()
	icon.name = "MedallionIcon"
	icon.texture = load(_quest_icon(quest)) as Texture2D
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = size * 0.2
	icon.offset_top = size * 0.2
	icon.offset_right = -size * 0.2
	icon.offset_bottom = -size * 0.2
	medallion.add_child(icon)
	return medallion


# ---------------------------------------------------------------------------
# Тексты


func _refresh_texts() -> void:
	var total := total_count()
	var done := completed_count()
	var overlay := mode == Mode.OVERLAY
	title_label.text = "ЕЖЕДНЕВНЫЕ ЗАДАНИЯ"
	timer_label.visible = overlay
	timer_label.text = _timer_text()
	count_label.text = "%d/%d" % [done, total]
	explanation_label.visible = overlay
	_refresh_week(done, total)


func _refresh_week(done: int, total: int) -> void:
	var full_days := 0
	for i in week_days.size():
		var day := week_days[i] as Dictionary
		var is_full := _week_day_is_full(day)
		if is_full:
			full_days += 1
		var is_today := _week_day_is_today(day, i)
		var diamond := week_diamonds[i]
		diamond.add_theme_color_override("font_color", GOLD if is_full else MUTED)
		diamond.modulate = Color(1.0, 1.0, 1.0, 1.0 if is_full else 0.55)
		if is_today:
			diamond.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	week_label.text = "%d/%d полных дней" % [full_days, WEEK_REQUIRED]
	var claimable := full_days >= WEEK_REQUIRED
	var claimed := bool(_week_summary().get("claimed", false))
	var reward_text := ""
	if full_days >= WEEK_REQUIRED:
		reward_text = "За 7/7 дней — %d осколков" % WEEKLY_REWARD_SHARDS
		reward_sub_label.text = "за 7/7 дней"
	else:
		var left_days := WEEK_REQUIRED - full_days
		reward_text = "Осталось %d %s до %d осколков" % [
			left_days,
			_plural(left_days, "полный день", "полных дня", "полных дней"),
			WEEKLY_REWARD_SHARDS,
		]
		reward_sub_label.text = "Осталось %d дн." % left_days
	status_label.text = reward_text
	status_label.tooltip_text = reward_text
	week_label.tooltip_text = reward_text
	reward_amount_label.text = str(WEEKLY_REWARD_SHARDS)
	reward_chip.tooltip_text = reward_text
	if claimed:
		claim_button.text = "Получено"
		claim_button.disabled = true
	elif claimable:
		claim_button.text = "Забрать %d" % WEEKLY_REWARD_SHARDS
		claim_button.disabled = false
	else:
		claim_button.text = "%d/%d" % [full_days, WEEK_REQUIRED]
		claim_button.disabled = true


func _timer_text() -> String:
	var source := _source()
	if source != null and source.has_method("time_left_text"):
		var left := String(source.call("time_left_text")).strip_edges()
		if not left.is_empty():
			return "обновление через %s" % left
	return "обновление через —"


# ---------------------------------------------------------------------------
# Раскладка


func _layout_content() -> void:
	if not _built or panel == null or content == null:
		return
	if header == null or footer == null or title_label == null:
		return
	var panel_size := panel.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		return
	var overlay := mode == Mode.OVERLAY
	var width := panel_size.x
	var height := panel_size.y
	content.position = Vector2.ZERO
	content.size = panel_size
	var pad := 22.0 if overlay else 8.0
	var header_h := 88.0 if overlay else 34.0
	var footer_h := 46.0 if overlay else 50.0

	header.position = Vector2.ZERO
	header.size = Vector2(width, header_h)
	if overlay:
		title_label.add_theme_font_size_override("font_size", 24)
		title_label.position = Vector2(44.0, 14.0)
		title_label.size = Vector2(520.0, 30.0)
		timer_label.position = Vector2(44.0, 48.0)
		timer_label.size = Vector2(420.0, 22.0)
		explanation_label.position = Vector2(44.0, 68.0)
		explanation_label.size = Vector2(540.0, 20.0)
		count_label.position = Vector2(610.0, 20.0)
		count_label.size = Vector2(60.0, 26.0)
		count_pill.position = count_label.position
		count_pill.size = count_label.size
		close_button.position = Vector2(width - 52.0, 20.0)
		close_button.size = Vector2(30.0, 30.0)
		_set_child_rect(header, "DailyQuestsDiamond", Rect2(22.0, 22.0, 18.0, 24.0))
	else:
		title_label.add_theme_font_size_override("font_size", 14)
		title_label.position = Vector2(26.0, 4.0)
		title_label.size = Vector2(width - 88.0, 26.0)
		count_label.position = Vector2(width - 54.0, 8.0)
		count_label.size = Vector2(40.0, 18.0)
		count_pill.position = count_label.position
		count_pill.size = count_label.size
		_set_child_rect(header, "DailyQuestsDiamond", Rect2(8.0, 8.0, 14.0, 18.0))

	if overlay:
		rows_layer.position = Vector2(0.0, 98.0)
		rows_layer.size = Vector2(width, 172.0)
		for i in card_nodes.size():
			var card := card_nodes[i] as Control
			card.position = Vector2(22.0 + float(i) * 260.0, 0.0)
			card.size = Vector2(248.0, 172.0)
			_layout_card(card, i)
	else:
		rows_layer.position = Vector2(0.0, header_h)
		rows_layer.size = Vector2(width, maxf(0.0, height - header_h - footer_h))
		for i in row_nodes.size():
			var row := row_nodes[i] as Control
			row.position = Vector2(pad, float(i) * 50.0)
			row.size = Vector2(width - pad * 2.0, 50.0)
			_layout_inline_row(row, i, width - pad * 2.0)

	footer.position = Vector2(0.0, maxf(header_h, height - footer_h - (10.0 if overlay else 0.0)))
	footer.size = Vector2(width, footer_h)
	_layout_footer(width, footer_h, pad, overlay)
	footer.visible = not quests.is_empty()
	rows_layer.visible = not card_nodes.is_empty() or not row_nodes.is_empty()


func _layout_card(card: Control, index: int) -> void:
	var w := card.size.x
	_set_child_rect(card, "DailyQuestsAccent%d" % index, Rect2(0.0, 14.0, 3.0, card.size.y - 28.0))
	_set_child_rect(card, "DailyQuestsIcon%d" % index, Rect2(16.0, 16.0, 40.0, 40.0))
	_set_child_rect(card, "DailyQuestsCardTitle%d" % index, Rect2(66.0, 12.0, 130.0, 48.0))
	_set_child_rect(card, "DailyQuestsReroll%d" % index, Rect2(w - 46.0, 12.0, 34.0, 34.0))
	_set_child_rect(card, "DailyQuestsRing%d" % index, Rect2(16.0, 94.0, 54.0, 54.0))
	_set_child_rect(card, "DailyQuestsPercent%d" % index, Rect2(16.0, 94.0, 54.0, 54.0))
	_set_child_rect(card, "DailyQuestsCheck%d" % index, Rect2(16.0, 94.0, 54.0, 54.0))
	_set_child_rect(card, "DailyQuestsProgress%d" % index, Rect2(80.0, 88.0, 150.0, 22.0))
	_set_child_rect(card, "DailyQuestsRemaining%d" % index, Rect2(80.0, 110.0, 150.0, 18.0))
	_set_child_rect(card, "DailyQuestsRewardChip%d" % index, Rect2(80.0, 132.0, 92.0, 30.0))
	var chip := card.get_node_or_null("DailyQuestsRewardChip%d" % index) as Control
	if chip != null:
		_set_child_rect(chip, "DailyQuestsRewardIcon%d" % index, Rect2(10.0, 5.0, 20.0, 20.0))
		_set_child_rect(chip, "DailyQuestsReward%d" % index, Rect2(36.0, 0.0, 50.0, 30.0))
	# Тонкий блик сверху.
	var sheen := card.get_child(2) as Control
	if sheen != null:
		sheen.position = Vector2(2.0, 1.0)
		sheen.size = Vector2(w - 4.0, 1.0)


func _layout_inline_row(row: Control, index: int, width: float) -> void:
	_set_child_rect(row, "DailyQuestsIcon%d" % index, Rect2(6.0, 11.0, 28.0, 28.0))
	_set_child_rect(row, "DailyQuestsRowTitle%d" % index, Rect2(42.0, 3.0, width - 140.0, 22.0))
	_set_child_rect(row, "DailyQuestsRowBar%d" % index, Rect2(42.0, 27.0, width - 140.0, 4.0))
	_set_child_rect(row, "DailyQuestsProgress%d" % index, Rect2(width - 92.0, 24.0, 38.0, 14.0))
	_set_child_rect(row, "DailyQuestsRewardIcon%d" % index, Rect2(width - 50.0, 20.0, 12.0, 14.0))
	_set_child_rect(row, "DailyQuestsReward%d" % index, Rect2(width - 35.0, 18.0, 30.0, 18.0))


func _layout_footer(width: float, height: float, pad: float, overlay: bool) -> void:
	var diamond_x := 22.0 if overlay else 8.0
	var diamond_step := 29.0 if overlay else 16.0
	var diamond_size := Vector2(18.0, 22.0) if overlay else Vector2(11.0, 14.0)
	for i in week_diamonds.size():
		var diamond := week_diamonds[i]
		diamond.position = Vector2(diamond_x + float(i) * diamond_step, 14.0 if overlay else 8.0)
		diamond.size = diamond_size
	if overlay:
		week_label.position = Vector2(232.0, 2.0)
		week_label.size = Vector2(190.0, 20.0)
		status_label.position = Vector2(232.0, 22.0)
		status_label.size = Vector2(190.0, 18.0)
		reward_chip.position = Vector2(430.0, 0.0)
		reward_chip.size = Vector2(176.0, 44.0)
		_set_child_rect(reward_chip, "DailyQuestsRewardShard", Rect2(12.0, 12.0, 20.0, 20.0))
		_set_child_rect(reward_chip, "DailyQuestsRewardAmount", Rect2(40.0, 4.0, 70.0, 26.0))
		_set_child_rect(reward_chip, "DailyQuestsRewardSub", Rect2(40.0, 26.0, 120.0, 14.0))
		claim_button.position = Vector2(614.0, 2.0)
		claim_button.size = Vector2(176.0, 40.0)
		claim_button.add_theme_font_size_override("font_size", 14)
	else:
		week_label.position = Vector2(124.0, 6.0)
		week_label.size = Vector2(86.0, 18.0)
		status_label.visible = false
		reward_chip.position = Vector2(214.0, 8.0)
		reward_chip.size = Vector2(62.0, 30.0)
		_set_child_rect(reward_chip, "DailyQuestsRewardShard", Rect2(6.0, 7.0, 12.0, 16.0))
		_set_child_rect(reward_chip, "DailyQuestsRewardAmount", Rect2(24.0, 4.0, 34.0, 20.0))
		_set_child_rect(reward_chip, "DailyQuestsRewardSub", Rect2(0.0, 0.0, 0.0, 0.0))
		claim_button.position = Vector2(width - 96.0, 8.0)
		claim_button.size = Vector2(88.0, 30.0)
		claim_button.add_theme_font_size_override("font_size", 10)
	status_label.visible = overlay


func _apply_height(animate: bool) -> void:
	_set_height(quests.size(), animate)
	_layout_content()


func _set_height(count: int, animate: bool) -> void:
	var target := panel_height_for(count)
	if mode == Mode.OVERLAY:
		if panel == null:
			return
		var top := -target * 0.5
		var bottom := target * 0.5
		if animate and is_inside_tree() and visible:
			if _tween != null and _tween.is_valid():
				_tween.kill()
			_tween = create_tween()
			_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_tween.set_parallel(true)
			_tween.tween_property(panel, "offset_top", top, TWEEN_TIME)
			_tween.tween_property(panel, "offset_bottom", bottom, TWEEN_TIME)
		else:
			panel.offset_top = top
			panel.offset_bottom = bottom
	else:
		var bottom := offset_top + target
		if animate and is_inside_tree():
			if _tween != null and _tween.is_valid():
				_tween.kill()
			_tween = create_tween()
			_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_tween.tween_property(self, "offset_bottom", bottom, TWEEN_TIME)
		else:
			offset_bottom = bottom


# ---------------------------------------------------------------------------
# Ввод / источник


func _input(event: InputEvent) -> void:
	if mode != Mode.OVERLAY or not visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close_overlay()


func _on_dim_input(event: InputEvent) -> void:
	if mode != Mode.OVERLAY or not visible:
		return
	var pressed := false
	var position := Vector2.ZERO
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		pressed = mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
		position = mouse.position
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		pressed = touch.pressed
		position = touch.position
	if not pressed:
		return
	var global_position := get_global_rect().position + position
	if not panel.get_global_rect().has_point(global_position):
		close_overlay()


func _on_reroll_pressed(slot: int) -> void:
	reroll_requested.emit(slot)


func _on_claim_pressed() -> void:
	weekly_claim_requested.emit(0)


func _connect_source() -> void:
	var source := _source()
	if source == null:
		return
	for signal_name in ["quests_updated", "daily_updated", "updated"]:
		if source.has_signal(signal_name):
			if not source.is_connected(signal_name, Callable(self, "refresh_from_source")):
				source.connect(signal_name, Callable(self, "refresh_from_source"))
			break


func _source() -> Node:
	return get_node_or_null("/root/DailyQuests")


# ---------------------------------------------------------------------------
# Данные


func _week_summary() -> Dictionary:
	var week: Dictionary = {}
	if summary.get("week") is Dictionary:
		week = (summary["week"] as Dictionary).duplicate(true)
	elif summary.get("weekly") is Dictionary:
		week = (summary["weekly"] as Dictionary).duplicate(true)
	if not week.has("active_days"):
		var full := 0
		for day in week_days:
			if _week_day_is_full(day as Dictionary):
				full += 1
		week["active_days"] = full
	if not week.has("required"):
		week["required"] = WEEK_REQUIRED
	if not week.has("claimable"):
		week["claimable"] = int(week["active_days"]) >= WEEK_REQUIRED
	return week


func _week_day_is_full(day: Dictionary) -> bool:
	if day.is_empty():
		return false
	if day.has("full"):
		return bool(day["full"])
	if day.has("all_done"):
		return bool(day["all_done"])
	if day.has("completed_count"):
		return int(day["completed_count"]) >= total_count()
	if day.has("closed"):
		return bool(day["closed"])
	return false


func _week_day_is_today(day: Dictionary, fallback_index: int) -> bool:
	if day.has("today"):
		return bool(day["today"])
	if day.has("is_today"):
		return bool(day["is_today"])
	var index := int(day.get("index", -1))
	if index < 0:
		index = (int(Time.get_datetime_dict_from_system().get("weekday", 1)) + 6) % 7
	return index == fallback_index


func _reroll_state() -> Dictionary:
	var free_available := true
	var paid_left := 0
	var cost := 1
	if rerolls is Dictionary:
		var dict := rerolls as Dictionary
		if dict.has("free_available"):
			free_available = bool(dict["free_available"])
		elif dict.has("free_used"):
			free_available = not bool(dict["free_used"])
		elif dict.has("free"):
			free_available = bool(dict["free"])
		var paid_max := int(dict.get("paid_max", dict.get("limit", 2)))
		if dict.has("paid_left"):
			paid_left = int(dict["paid_left"])
		elif dict.has("paid_used"):
			paid_left = maxi(0, paid_max - int(dict["paid_used"]))
		else:
			paid_left = paid_max
		cost = int(dict.get("cost", 1))
	elif rerolls is int:
		var left := int(rerolls)
		free_available = left > 0
		paid_left = maxi(0, left - 1) if free_available else left
	if not free_available and paid_left <= 0:
		return {"available": false, "hint": "Замены на сегодня закончились"}
	if not free_available:
		return {"available": true, "hint": "Замена за %d осколок" % cost}
	return {"available": true, "hint": "Бесплатная замена — 1 раз в день"}


func _slot_reroll_state(slot: int) -> Dictionary:
	var source := _source()
	if source == null or not source.has_method("reroll_state"):
		return {}
	if not bool(source.get("loaded")):
		return {}
	var state: Variant = source.call("reroll_state", slot)
	if state is Dictionary:
		return state as Dictionary
	return {}


func _apply_slot_state(state: Dictionary, slot_state: Dictionary) -> void:
	var available := bool(slot_state.get("enabled", false))
	var reason := String(slot_state.get("reason", ""))
	state["available"] = available
	if available:
		state["hint"] = "Бесплатная замена — 1 раз в день" if bool(
			slot_state.get("free", false)
		) else "Замена за %d осколок" % maxi(1, int(slot_state.get("cost", 1)))
		return
	match reason:
		"pending":
			state["hint"] = "Замена отправлена"
		"shards":
			state["hint"] = "Не хватает осколков"
		_:
			state["hint"] = "Замены на сегодня закончились"


# ---------------------------------------------------------------------------
# Иконки / стили


func _quest_accent(quest: Dictionary) -> Color:
	var metric := String(quest.get("metric", ""))
	var template := String(quest.get("template_id", ""))
	if metric == "kills" or template.begins_with("kills") or template == "triple_kill":
		return KILLS
	if metric == "damage" or template.begins_with("damage"):
		return DAMAGE
	if metric == "shop_items_one" or metric.begins_with("shop") or template.begins_with("buy"):
		return SHOP
	return GOLD


func _quest_icon(quest: Dictionary) -> String:
	var metric := String(quest.get("metric", ""))
	var template := String(quest.get("template_id", ""))
	if metric == "kills" or template.begins_with("kills") or template == "triple_kill":
		return "res://ui/icons/gear_1h_sword.png"
	if metric == "damage":
		return "res://assets/ui/shop/power_glove.webp"
	if metric == "shop_items_one" or template.begins_with("buy"):
		return "res://assets/ui/shop/cleansing_charm.webp"
	if metric == "crystals" or metric == "shells":
		return "res://ui/icons/sky_shard.png"
	return "res://ui/icons/gear_staff.png"


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.045, 0.08, 0.98)
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.75)
	style.set_border_width_all(1 if mode == Mode.INLINE else 2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 6 if mode == Mode.INLINE else 18
	style.shadow_offset = Vector2(0.0, 2.0)
	return style


func _make_button(text: String, size: int, primary: bool, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", UI_FONT)
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_color", Color(0.14, 0.1, 0.03) if primary else GOLD)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", _button_style(primary, false, false))
	button.add_theme_stylebox_override("hover", _button_style(primary, true, false))
	button.add_theme_stylebox_override("pressed", _button_style(primary, true, false))
	button.add_theme_stylebox_override("disabled", _button_style(primary, false, true))
	return button


func _button_style(primary: bool, hovered: bool, disabled: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if disabled:
		style.bg_color = Color(0.08, 0.1, 0.14, 0.95)
		style.border_color = Color(0.34, 0.4, 0.5, 0.8)
	elif primary:
		style.bg_color = Color(1.0, 0.78, 0.2) if not hovered else Color(1.0, 0.88, 0.4)
		style.border_color = Color(1.0, 0.92, 0.6)
	else:
		style.bg_color = Color(0.08, 0.12, 0.18, 0.98) if not hovered else Color(0.13, 0.18, 0.25, 1.0)
		style.border_color = GOLD
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	return style


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _set_child_rect(parent: Node, child_name: String, rect: Rect2) -> void:
	var child := parent.get_node_or_null(child_name) as Control
	if child == null:
		return
	child.position = rect.position
	child.size = rect.size


func _plural(count: int, one: String, few: String, many: String) -> String:
	var mod100 := count % 100
	if mod100 >= 11 and mod100 <= 14:
		return many
	match count % 10:
		1:
			return one
		2, 3, 4:
			return few
		_:
			return many


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout_content()
