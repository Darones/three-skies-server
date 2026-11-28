extends Control

## Ежедневные задания: одна панель, два режима.
##
## INLINE  — стол в лобби вместо старой плашки «НОВИЧОК» (desktop 1440x734).
## OVERLAY — полноэкранный оверлей (z = 42) с затемняющим backdrop:
##           телефон 844x390 (панель 812, масштаб от 844x390),
##           desktop — панель 776 px (730..812) по центру группы карточек.
##
## Панель не ходит в сеть. Она рисует снимок автозагрузки DailyQuests и
## отправляет намерения (замена / недельная награда) наружу сигналами.
## Контракт клиента (то, что читает refresh_from_source):
##   snapshot() -> Dictionary  либо свойства
##   quests: Array   [{slot, template_id, title, metric, target, progress,
##                     reward_shards, reward_xp, completed}]
##   week: Array|Dictionary [{date, label, full|completed_count, today}]
##   rerolls: Dictionary {free_available, paid_left, paid_max, cost}
##   summary: Dictionary {completed, total,
##                        week: {active_days, required, tier, claimable,
##                               claimed, reward_kind, reward_name,
##                               reward_owned, compensation}}
## Сигнал обновления: quests_updated (или daily_updated/updated).

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

const GOLD := Color(0.95, 0.76, 0.38)
const PALE := Color(0.92, 0.94, 0.99)
const MUTED := Color(0.66, 0.72, 0.83)
const DIM_TEXT := Color(0.72, 0.78, 0.88)
const COMPLETE := Color(0.58, 0.9, 0.64)
const WARN := Color(1.0, 0.55, 0.45)

# Высоты из спецификации: [0 заданий, 1, 2, 3].
const DESKTOP_HEIGHTS := [48.0, 154.0, 200.0, 246.0]
const MOBILE_HEIGHTS := [136.0, 234.0, 286.0, 338.0]
const DESKTOP_WIDTH := 380.0
const DESKTOP_HEADER := 48.0
const MOBILE_HEADER := 136.0
const DESKTOP_ROW := 42.0
const MOBILE_ROW := 52.0
const DESKTOP_FOOTER := 40.0
const MOBILE_FOOTER := 46.0
const DESKTOP_ROW_GAP := 4.0
const TWEEN_TIME := 0.18
const MAX_ROWS := 3

const MOBILE_PANEL_WIDTH := 812.0
const MOBILE_REFERENCE := Vector2(844.0, 390.0)
const MOBILE_MARGIN := 16.0

# Desktop-оверлей: 730..812 по спецификации, панель не прижимается к краям.
const DESKTOP_PANEL_WIDTH := 776.0
const DESKTOP_PANEL_MIN_WIDTH := 730.0
const DESKTOP_PANEL_MAX_WIDTH := 812.0
const DESKTOP_EDGE_MARGIN := 24.0
# Допуск сравнения геометрии: повторный layout с тем же результатом не делаем.
const LAYOUT_EPSILON := 0.5
# Затемнение под панелью: карточки героев остаются видны, но одинаково.
const BACKDROP_ALPHA_DESKTOP := 0.62
const BACKDROP_ALPHA_MOBILE := 0.88

const WEEK_LETTERS := ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
const WEEK_REQUIRED := 7

const WEEKLY_REWARD_SHARDS := 300

# Подписи MVP-шаблонов: сервер может прислать только template_id.
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
## Desktop overlay: centered fixed-width panel (no 844-design scaling).
var desktop_overlay := false
## Desktop overlay: X-центр панели. -1 = центр экрана. Лобби передаёт центр
## группы карточек героев: она смещена вправо из-за левой колонки (стол
## ежедневок/кнопки), и панель по центру экрана резала только левую карточку.
var desktop_center_x := -1.0

var data: Dictionary = {}
var quests: Array = []
var week_days: Array = []
var rerolls: Variant = {}
var summary: Dictionary = {}

var panel: Panel
var content: Control
var header: Control
var rows_layer: Control
var footer: Control

var title_label: Label
var subtitle_label: Label
var count_label: Label
var reroll_line_label: Label
var close_button: Button

var row_nodes: Array[Control] = []
var week_chips: Array[Panel] = []
var week_chip_labels: Array[Label] = []
var week_label: Label
var status_label: Label
var status_icon: TextureRect
var claim_button: Button

var _tween: Tween
var _tween_target := -1.0
var _built := false

# Идемпотентность раскладки: без этих флагов ресайз панели мог снова вызвать
# раскладку, а та — снова панель (warning и зависание пробы).
var _placing_panel := false
var _laying_out := false
var _placement_queued := false
var _layout_queued := false
var _layout_dirty := true
var _last_layout_size := Vector2(-1.0, -1.0)


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
	_queue_layout()


func set_mode(value: int) -> void:
	mode = value


## Лобби знает центр группы карточек героев: панель встаёт по нему, чтобы
## резать обе боковые карточки одинаково (-1 = центр экрана).
## Метод только запоминает центр и (если панель готова) откладывает перенос:
## раскладка не запускается отсюда и не может рекурсивно вернуться в лобби.
func set_desktop_center_x(value: float) -> void:
	if not desktop_overlay:
		return
	if desktop_center_x > 0.0 and absf(value - desktop_center_x) <= LAYOUT_EPSILON:
		return
	desktop_center_x = value
	if not _built or panel == null or not is_inside_tree():
		return
	_queue_placement()


func is_overlay_open() -> bool:
	return mode == Mode.OVERLAY and visible


func panel_height_for(count: int) -> float:
	var table: Array = MOBILE_HEIGHTS if mode == Mode.OVERLAY else DESKTOP_HEIGHTS
	return _scale(float(table[clampi(count, 0, MAX_ROWS)]))


func open_overlay() -> void:
	if mode != Mode.OVERLAY:
		return
	if desktop_overlay:
		_place_desktop_panel()
	visible = true
	refresh_from_source()
	_layout_content()
	_apply_height(true)


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
	if collected.has("daily") and collected["daily"] is Dictionary:
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
# Сборка


func _build_dim() -> void:
	var dim := ColorRect.new()
	dim.name = "DailyQuestsDim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Полноэкранное затемнение: все карточки героев уходят на один уровень,
	# поэтому ни одна не выглядит «отдельной» рядом с панелью.
	dim.color = Color(
		0.005, 0.008, 0.018,
		BACKDROP_ALPHA_DESKTOP if desktop_overlay else BACKDROP_ALPHA_MOBILE
	)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)


func _build_panel() -> void:
	panel = Panel.new()
	panel.name = "DailyQuestsPanel"
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.clip_contents = true
	if mode == Mode.OVERLAY:
		panel.anchor_top = 0.5
		panel.anchor_bottom = 0.5
		if desktop_overlay:
			_place_desktop_panel()
		else:
			panel.anchor_left = MOBILE_MARGIN / MOBILE_REFERENCE.x
			panel.anchor_right = (MOBILE_REFERENCE.x - MOBILE_MARGIN) / MOBILE_REFERENCE.x
			panel.offset_left = 0.0
			panel.offset_right = 0.0
		var half_height := _scale(MOBILE_HEIGHTS[0]) * 0.5
		panel.offset_top = -half_height
		panel.offset_bottom = half_height
		# Не прямой вызов: ресайз панели только ставит раскладку в очередь.
		panel.resized.connect(_queue_layout)
	else:
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.resized.connect(_queue_layout)
	add_child(panel)


## Inline-таблица: прозрачная кнопка на всю площадь открывает меню.
func _build_open_button() -> void:
	var open_button := Button.new()
	open_button.name = "DailyQuestsOpenButton"
	open_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	open_button.focus_mode = Control.FOCUS_NONE
	open_button.mouse_filter = Control.MOUSE_FILTER_STOP
	open_button.tooltip_text = "Открыть ежедневные задания"
	for style_name in ["normal", "hover", "pressed", "focus"]:
		open_button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	open_button.pressed.connect(func() -> void: open_requested.emit())
	open_button.z_index = 10
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

	title_label = _make_label("ЗАДАНИЯ", 20, GOLD)
	title_label.name = "DailyQuestsTitle"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title_label)

	count_label = _make_label("0/3", 16, DIM_TEXT)
	count_label.name = "DailyQuestsCount"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(count_label)

	subtitle_label = _make_label("", 16, PALE)
	subtitle_label.name = "DailyQuestsSubtitle"
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	subtitle_label.clip_text = true
	subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(subtitle_label)

	reroll_line_label = _make_label("", 16, MUTED)
	reroll_line_label.name = "DailyQuestsRerolls"
	reroll_line_label.add_theme_font_size_override("font_size", 16)
	reroll_line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	reroll_line_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	reroll_line_label.clip_text = true
	reroll_line_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(reroll_line_label)

	close_button = _make_button("×", 22, false, "DailyQuestsClose")
	close_button.visible = mode == Mode.OVERLAY
	close_button.pressed.connect(close_overlay)
	header.add_child(close_button)

	rows_layer = Control.new()
	rows_layer.name = "DailyQuestsRows"
	rows_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(rows_layer)

	footer = Control.new()
	footer.name = "DailyQuestsFooter"
	footer.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(footer)

	week_label = _make_label("Неделя: 0/7 полных дней", 12, MUTED)
	week_label.name = "DailyQuestsWeek"
	week_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	week_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	week_label.clip_text = true
	week_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(week_label)

	status_label = _make_label("", 11, DIM_TEXT)
	status_label.name = "DailyQuestsRewardStatus"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.clip_text = true
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(status_label)

	status_icon = TextureRect.new()
	status_icon.name = "DailyQuestsRewardShard"
	status_icon.texture = SHARD_ICON
	status_icon.custom_minimum_size = Vector2(16.0, 16.0)
	status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	status_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(status_icon)

	claim_button = _make_button("0/7", 13, true, "DailyQuestsClaim")
	claim_button.pressed.connect(_on_claim_pressed)
	footer.add_child(claim_button)

	for i in WEEK_REQUIRED:
		var chip := Panel.new()
		chip.name = "DailyQuestsDay%d" % i
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		footer.add_child(chip)
		var letter := _make_label(WEEK_LETTERS[i], 12, MUTED)
		letter.name = "DailyQuestsDayLabel%d" % i
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		chip.add_child(letter)
		week_chips.append(chip)
		week_chip_labels.append(letter)


func _connect_source() -> void:
	var source := _source()
	if source == null:
		return
	for signal_name in ["quests_updated", "daily_updated", "updated"]:
		if source.has_signal(signal_name):
			if not source.is_connected(signal_name, Callable(self, "refresh_from_source")):
				source.connect(signal_name, Callable(self, "refresh_from_source"))
			break


# ---------------------------------------------------------------------------
# Строки заданий


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
		var quest: Dictionary = (source as Dictionary).duplicate(true)
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
	_layout_dirty = true
	for row in row_nodes:
		if is_instance_valid(row):
			if row.get_parent() != null:
				row.get_parent().remove_child(row)
			row.queue_free()
	row_nodes.clear()
	for index in quests.size():
		var row := _make_quest_row(index, quests[index] as Dictionary)
		rows_layer.add_child(row)
		row_nodes.append(row)
	rows_layer.visible = not row_nodes.is_empty()


func _make_quest_row(index: int, quest: Dictionary) -> Control:
	var row := Panel.new()
	row.name = "DailyQuestsRow%d" % index
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var completed := bool(quest.get("completed", false))
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.055, 0.068, 0.1, 0.62)
	row_style.border_color = Color(COMPLETE.r, COMPLETE.g, COMPLETE.b, 0.35) if completed else Color(0.35, 0.42, 0.55, 0.28)
	row_style.set_border_width_all(1)
	row_style.set_corner_radius_all(8)
	row_style.content_margin_left = 0.0
	row_style.content_margin_right = 0.0
	row_style.content_margin_top = 0.0
	row_style.content_margin_bottom = 0.0
	row.add_theme_stylebox_override("panel", row_style)

	var title := _make_label(String(quest["title"]), 18, COMPLETE if completed else PALE)
	title.name = "DailyQuestsRowTitle%d" % index
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(title)

	var bar := ProgressBar.new()
	bar.name = "DailyQuestsRowBar%d" % index
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = float(quest["target"])
	bar.value = float(quest["progress"])
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.09, 0.11, 0.16)
	bar_bg.set_corner_radius_all(2)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = COMPLETE if completed else GOLD
	bar_fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bar_bg)
	bar.add_theme_stylebox_override("fill", bar_fill)
	row.add_child(bar)

	var reward_shards := int(quest.get("reward_shards", 0))
	var overlay := mode == Mode.OVERLAY
	var meta_text := ""
	if completed:
		meta_text = ("Готово · %s" % _reward_text(reward_shards)) if overlay else "Готово"
	else:
		meta_text = "%d/%d" % [int(quest["progress"]), int(quest["target"])]
		if overlay:
			meta_text += " · %s" % _reward_text(reward_shards)
	var meta := _make_label(meta_text, 16, COMPLETE if completed else DIM_TEXT)
	meta.name = "DailyQuestsRowMeta%d" % index
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	meta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	meta.clip_text = true
	meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(meta)

	if overlay:
		var state := _reroll_state()
		var slot_state := _slot_reroll_state(int(quest["slot"]))
		if not slot_state.is_empty() and not completed:
			_apply_slot_state(state, slot_state)
		var reroll := _make_reroll_button(state, index)
		reroll.visible = not completed
		if not completed:
			reroll.pressed.connect(_on_reroll_pressed.bind(int(quest["slot"])))
		row.add_child(reroll)
		row.set_meta("reroll_button", reroll)
	else:
		_add_inline_reward(row, index, quest)
	return row


## Inline-таблица: награда справа — иконка осколка 16 px + число.
func _add_inline_reward(row: Control, index: int, quest: Dictionary) -> void:
	var box := HBoxContainer.new()
	box.name = "DailyQuestsReward%d" % index
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.name = "DailyQuestsRewardIcon%d" % index
	icon.texture = SHARD_ICON
	icon.custom_minimum_size = Vector2(16.0, 16.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var amount := _make_label("%d" % int(quest.get("reward_shards", 0)), 16, GOLD)
	amount.name = "DailyQuestsRewardLabel%d" % index
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(amount)
	row.add_child(box)


## Кнопка замены: явный текст «Заменить» вместо иконки.
## Точный размер подбирает _layout_row (по ширине текста и месту в строке).
func _make_reroll_button(state: Dictionary, index: int) -> Button:
	var mobile := mode == Mode.OVERLAY
	var caption := String(state.get("full_text", "Заменить"))
	var button := _make_button(caption, 15, false, "DailyQuestsReroll%d" % index)
	button.disabled = not bool(state.get("available", false))
	button.tooltip_text = String(state.get("hint", ""))
	button.clip_text = true
	button.set_meta("full_text", caption)
	button.set_meta("compact_text", String(state.get("compact_text", caption)))
	button.set_meta("paid_icon", bool(state.get("icon", false)))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.58))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.9, 0.58))
	button.add_theme_constant_override("h_separation", int(round(4.0 * _scale(1.0))))
	button.add_theme_constant_override("icon_max_width", int(round((16.0 if mobile else 12.0) * _scale(1.0))))
	button.add_theme_stylebox_override("normal", _reroll_style(false, false))
	button.add_theme_stylebox_override("hover", _reroll_style(true, false))
	button.add_theme_stylebox_override("pressed", _reroll_style(true, false))
	button.add_theme_stylebox_override("disabled", _reroll_style(false, true))
	if bool(state.get("icon", false)):
		button.icon = SHARD_ICON
	return button


# ---------------------------------------------------------------------------
# Тексты


func _refresh_texts() -> void:
	_layout_dirty = true
	var total := total_count()
	var completed := completed_count()
	var mobile := mode == Mode.OVERLAY

	title_label.text = "ЗАДАНИЯ" if quests.is_empty() else "ЗАДАНИЯ · %d/%d" % [completed, total]
	count_label.visible = false
	count_label.text = "%d/%d" % [completed, total]

	if quests.is_empty():
		subtitle_label.text = "Заданий пока нет"
	elif completed >= total:
		subtitle_label.text = "День закрыт: %d/%d" % [completed, total]
	else:
		var remaining := maxi(1, total - completed)
		subtitle_label.text = "Осталось %d %s" % [
			remaining, _plural(remaining, "задание", "задания", "заданий")
		]

	reroll_line_label.visible = mobile
	reroll_line_label.text = "1 замена в день бесплатно · ещё 2 — по 1 осколку"

	_refresh_week(completed, total)


func _reroll_line() -> String:
	var state := _reroll_state()
	var free_left := 1 if bool(state["free"]) else 0
	var paid_left := int(state["paid_left"])
	if free_left <= 0 and paid_left <= 0:
		return "Замены на сегодня закончились"
	if free_left > 0 and paid_left > 0:
		return "Замены: 1 бесплатная + %d по 1 осколку" % paid_left
	if free_left > 0:
		return "Замены: 1 бесплатная"
	return "Замены: %d %s по 1 осколку" % [
		paid_left, _plural(paid_left, "платная", "платные", "платных")
	]


func _refresh_week(completed: int, total: int) -> void:
	var week := _week_summary()
	var has_day_data := false
	for raw_day in week_days:
		if not (raw_day as Dictionary).is_empty():
			has_day_data = true
			break
	var fallback_full := clampi(int(week.get("active_days", 0)), 0, WEEK_REQUIRED)
	var full_days := 0
	for i in week_chips.size():
		var day: Dictionary = {}
		if i < week_days.size():
			day = week_days[i] as Dictionary
		var is_full := _week_day_is_full(day) if has_day_data else i < fallback_full
		if is_full:
			full_days += 1
		var chip := week_chips[i]
		var letter := week_chip_labels[i]
		var today := _week_day_is_today(day, i) if has_day_data else i == _today_index()
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(4)
		if is_full:
			style.bg_color = GOLD
			style.border_color = Color(1.0, 0.9, 0.55)
		else:
			style.bg_color = Color(0.08, 0.1, 0.14, 0.9)
			style.border_color = GOLD if today else Color(0.36, 0.42, 0.54, 0.75)
		style.set_border_width_all(1 if today or not is_full else 0)
		style.content_margin_left = 0.0
		style.content_margin_right = 0.0
		style.content_margin_top = 0.0
		style.content_margin_bottom = 0.0
		chip.add_theme_stylebox_override("panel", style)
		letter.add_theme_color_override("font_color", Color(0.14, 0.1, 0.03) if is_full else MUTED)

	# Точки и заявка считаются только по полным дням (все 3 задания).
	var claimable := full_days >= WEEK_REQUIRED
	if not has_day_data and bool(week.get("claimable", false)):
		claimable = fallback_full >= WEEK_REQUIRED
	var claimed := bool(week.get("claimed", false))
	var reward_text := ""
	if full_days >= WEEK_REQUIRED:
		reward_text = "За 7/7 дней — %d осколков" % WEEKLY_REWARD_SHARDS
	else:
		var left_days := WEEK_REQUIRED - full_days
		reward_text = "Осталось %d %s до %d осколков" % [
			left_days,
			_plural(left_days, "полный день", "полных дня", "полных дней"),
			WEEKLY_REWARD_SHARDS,
		]
	if claimed:
		claim_button.text = "Получено"
		claim_button.disabled = true
	elif claimable:
		claim_button.text = "Забрать %d осколков" % WEEKLY_REWARD_SHARDS
		claim_button.disabled = false
	else:
		claim_button.text = "%d/%d" % [full_days, WEEK_REQUIRED]
		claim_button.disabled = true
	_style_claim_button(claimable and not claimed)
	week_label.text = "Неделя: %d/%d полных дней" % [full_days, WEEK_REQUIRED]
	week_label.tooltip_text = reward_text
	status_label.text = reward_text
	status_label.tooltip_text = reward_text
	claim_button.tooltip_text = reward_text


func _week_summary() -> Dictionary:
	var week: Dictionary = {}
	if summary.get("week") is Dictionary:
		week = (summary["week"] as Dictionary).duplicate(true)
	elif summary.get("weekly") is Dictionary:
		week = (summary["weekly"] as Dictionary).duplicate(true)
	if not week.has("active_days"):
		var full := 0
		for raw_day in week_days:
			if _week_day_is_full(raw_day as Dictionary):
				full += 1
		week["active_days"] = full
	if not week.has("required"):
		week["required"] = WEEK_REQUIRED
	if not week.has("claimable"):
		week["claimable"] = int(week["active_days"]) >= WEEK_REQUIRED
	return week


func _free_reroll_state(paid_left: int) -> Dictionary:
	return {
		"available": true, "free": true, "paid_left": paid_left, "cost": 0, "icon": false,
		"full_text": "Заменить", "compact_text": "Заменить",
		"hint": "Заменить задание. Бесплатно — 1 раз в день",
	}


func _paid_reroll_state(paid_left: int, cost: int) -> Dictionary:
	var price := maxi(1, cost)
	return {
		"available": true, "free": false, "paid_left": paid_left, "cost": price, "icon": true,
		"full_text": "Заменить · %d" % price, "compact_text": "Заменить",
		"hint": "Заменить задание за %d %s" % [
			price, _plural(price, "осколок", "осколка", "осколков")
		],
	}


func _blocked_reroll_state(caption: String, hint: String) -> Dictionary:
	return {
		"available": false, "free": false, "paid_left": 0, "cost": 0, "icon": false,
		"full_text": caption, "compact_text": caption, "hint": hint,
	}


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
		return _blocked_reroll_state("Нет замен", "Замены на сегодня закончились")
	if not free_available:
		return _paid_reroll_state(paid_left, cost)
	return _free_reroll_state(paid_left)


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


## DailyQuests.reroll_state() знает про already completed / pending / shards.
## Пока автозагрузка не загрузила /quests (или в пробе), работает общий счётчик.
func _apply_slot_state(state: Dictionary, slot_state: Dictionary) -> void:
	var available := bool(slot_state.get("enabled", false))
	var reason := String(slot_state.get("reason", ""))
	state["available"] = available
	if available:
		var free := bool(slot_state.get("free", false))
		state["free"] = free
		var paid_left := int(state.get("paid_left", 0))
		if free:
			state.merge(_free_reroll_state(paid_left), true)
		else:
			state.merge(_paid_reroll_state(paid_left, int(slot_state.get("cost", 1))), true)
		return
	state["free"] = false
	match reason:
		"pending":
			state.merge(_blocked_reroll_state(
				"Замена идёт", "Замена отправлена — ждём ответ сервера"
			), true)
		"completed":
			state.merge(_blocked_reroll_state(
				"Замена использована", "Выполненное задание не меняется"
			), true)
		"shards":
			var price := maxi(1, int(slot_state.get("cost", 1)))
			state.merge(_blocked_reroll_state(
				"Нет осколков",
				"Не хватает осколков: замена стоит %d %s" % [
					price, _plural(price, "осколок", "осколка", "осколков")
				]
			), true)
		"busy":
			state.merge(_blocked_reroll_state(
				"Замена идёт", "Сначала дождитесь ответа на другую замену"
			), true)
		_:
			state.merge(_blocked_reroll_state(
				"Нет замен", "Замены на сегодня закончились"
			), true)


# ---------------------------------------------------------------------------
# Состояние недели


func _week_day_is_full(day: Dictionary) -> bool:
	if day.is_empty():
		return false
	if day.has("full"):
		return bool(day["full"])
	if day.has("all_done"):
		return bool(day["all_done"])
	if day.has("completed_count"):
		return int(day["completed_count"]) >= total_count()
	if day.has("completed_all"):
		return bool(day["completed_all"])
	return false


func _week_day_is_today(day: Dictionary, fallback_index: int) -> bool:
	if day.has("today"):
		return bool(day["today"])
	if day.has("is_today"):
		return bool(day["is_today"])
	var index := int(day.get("index", -1))
	if index < 0:
		index = _today_index()
	return index == fallback_index


func _today_index() -> int:
	# Time.weekday: 0 = воскресенье; неделя начинается с понедельника.
	return (int(Time.get_datetime_dict_from_system().get("weekday", 1)) + 6) % 7


# ---------------------------------------------------------------------------
# Раскладка


## Desktop-панель: ширина 730..812 (776), X-центр либо центр экрана, либо
## центр группы карточек, но всегда с полем 24 px от краёв экрана.
## Высоту задаёт _set_height по числу заданий.
## Идемпотентно: если anchors и offsets уже такие — панель не трогаем,
## значит `resized` не стреляет и раскладка не перезапускается.
func _place_desktop_panel() -> void:
	if _placing_panel:
		return
	if panel == null or mode != Mode.OVERLAY or not desktop_overlay:
		return
	if not is_inside_tree():
		return
	var viewport_width := get_viewport_rect().size.x
	if viewport_width <= 0.0:
		return
	var width := clampf(DESKTOP_PANEL_WIDTH, DESKTOP_PANEL_MIN_WIDTH, DESKTOP_PANEL_MAX_WIDTH)
	width = minf(width, maxf(200.0, viewport_width - DESKTOP_EDGE_MARGIN * 2.0))
	var center := desktop_center_x
	if center <= 0.0:
		center = viewport_width * 0.5
	var max_left := maxf(DESKTOP_EDGE_MARGIN, viewport_width - DESKTOP_EDGE_MARGIN - width)
	var left := clampf(center - width * 0.5, DESKTOP_EDGE_MARGIN, max_left)
	var right := left + width
	if is_equal_approx(panel.anchor_left, 0.0) and is_equal_approx(panel.anchor_right, 0.0) \
			and absf(panel.offset_left - left) <= LAYOUT_EPSILON \
			and absf(panel.offset_right - right) <= LAYOUT_EPSILON:
		return
	_placing_panel = true
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.offset_left = left
	panel.offset_right = right
	_placing_panel = false


## Перенос панели — только отложенно и только один раз на кадр.
func _queue_placement() -> void:
	if _placement_queued:
		return
	_placement_queued = true
	call_deferred("_flush_placement")


func _flush_placement() -> void:
	_placement_queued = false
	_place_desktop_panel()


## Раскладка содержимого — тоже отложенно и один раз на кадр:
## обработчик `resized` больше не заходит в неё повторно.
func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	call_deferred("_flush_layout")


func _flush_layout() -> void:
	_layout_queued = false
	_layout_content()


func _layout_content() -> void:
	if _laying_out:
		return
	if not _built or panel == null or content == null:
		return
	if header == null or footer == null or title_label == null or close_button == null:
		return
	var panel_size := panel.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		return
	# Ничего не поменялось с прошлого прохода — выходим, не трогая детей.
	if not _layout_dirty and _last_layout_size.is_equal_approx(panel_size):
		return
	_laying_out = true
	var mobile := mode == Mode.OVERLAY
	var scale := _scale(1.0)
	var width := panel_size.x
	var height := panel_size.y
	var pad := (14.0 if mobile else 10.0) * scale
	var header_h := (MOBILE_HEADER if mobile else DESKTOP_HEADER) * scale
	var footer_h := (MOBILE_FOOTER if mobile else DESKTOP_FOOTER) * scale
	var row_h := (MOBILE_ROW if mobile else DESKTOP_ROW) * scale
	var row_gap := 0.0 if mobile else DESKTOP_ROW_GAP * scale

	# `content` растянут PRESET_FULL_RECT и сам следует за панелью: size/position
	# здесь не пишем — у него неравные противоположные anchors, и такая запись
	# давала warning «size overridden after _ready()».

	header.position = Vector2.ZERO
	header.size = Vector2(width, header_h)

	var close_size := 40.0 * scale
	var close_gap := 8.0 * scale
	if mobile:
		close_button.visible = true
		close_button.position = Vector2(width - pad - close_size, 16.0 * scale)
		close_button.size = Vector2(close_size, close_size)
		var title_right := width - pad - close_size - close_gap
		title_label.position = Vector2(pad, 18.0 * scale)
		title_label.size = Vector2(maxf(0.0, title_right - pad), 28.0 * scale)
		count_label.position = Vector2(width - pad - close_size - close_gap - 56.0 * scale, 20.0 * scale)
		count_label.size = Vector2(56.0 * scale, 24.0 * scale)
		subtitle_label.position = Vector2(pad, 50.0 * scale)
		subtitle_label.size = Vector2(width - pad * 2.0, 24.0 * scale)
		reroll_line_label.position = Vector2(pad, 78.0 * scale)
		reroll_line_label.size = Vector2(width - pad * 2.0, 24.0 * scale)
	else:
		close_button.visible = false
		title_label.position = Vector2(pad, 3.0)
		title_label.size = Vector2(maxf(0.0, width - pad * 2.0), 24.0)
		count_label.position = Vector2(width - pad - 46.0, 4.0)
		count_label.size = Vector2(46.0, 22.0)
		subtitle_label.position = Vector2(pad, 25.0)
		subtitle_label.size = Vector2(width - pad * 2.0, 20.0)
		reroll_line_label.visible = false

	rows_layer.position = Vector2(0.0, header_h)
	rows_layer.size = Vector2(width, maxf(0.0, height - header_h - footer_h))
	var row_width := width - pad * 2.0
	for i in row_nodes.size():
		var row := row_nodes[i]
		row.position = Vector2(pad, float(i) * (row_h + row_gap))
		row.size = Vector2(row_width, row_h)
		_layout_row(row, row_width, row_h, mobile, scale)

	footer.position = Vector2(0.0, maxf(header_h, height - footer_h))
	footer.size = Vector2(width, footer_h)
	_layout_footer(width, footer_h, pad, mobile, scale)
	footer.visible = not quests.is_empty() and height >= header_h + footer_h - 0.5
	_last_layout_size = panel_size
	_layout_dirty = false
	_laying_out = false


func _layout_row(row: Control, width: float, height: float, mobile: bool, scale: float) -> void:
	var title: Label = null
	var meta: Label = null
	var bar: ProgressBar = null
	var reroll: Button = null
	var reward: Control = null
	for child in row.get_children():
		if child is Label:
			if String(child.name).begins_with("DailyQuestsRowTitle"):
				title = child as Label
			elif String(child.name).begins_with("DailyQuestsRowMeta"):
				meta = child as Label
		elif child is ProgressBar:
			bar = child as ProgressBar
		elif child is Button:
			reroll = child as Button
		elif child is HBoxContainer and String(child.name).begins_with("DailyQuestsReward"):
			reward = child as Control
	var inner_right := width - 10.0 * scale
	if reroll != null and reroll.visible:
		# Высота: desktop 30, mobile 42 — с полями внутри строки 42/52.
		var button_h := minf(
			(42.0 if mobile else 30.0) * scale,
			maxf(18.0 * scale, height - 6.0 * scale)
		)
		var font_size := reroll.get_theme_font_size("font_size")
		var full_text := String(reroll.get_meta("full_text", reroll.text))
		var compact_text := String(reroll.get_meta("compact_text", full_text))
		var paid_icon := bool(reroll.get_meta("paid_icon", false))
		reroll.icon = SHARD_ICON if paid_icon else null
		var icon_w := 0.0
		if reroll.icon != null:
			icon_w = (16.0 if mobile else 12.0) * scale + 4.0 * scale
		var pad_x := 6.0 * scale
		# Сколько места нужно названию и награде — кнопка не должна их перекрыть.
		var side_need := 0.0
		if title != null:
			side_need = maxf(side_need, _text_width(title.text, title.get_theme_font_size("font_size")))
		if meta != null:
			side_need = maxf(side_need, _text_width(meta.text, meta.get_theme_font_size("font_size")))
		var reserved := clampf(
			side_need + 14.0 * scale,
			(140.0 if mobile else 110.0) * scale,
			(360.0 if mobile else 220.0) * scale
		)
		var max_w := maxf(76.0 * scale, inner_right - 10.0 * scale - reserved)
		var caption := full_text
		var want := _text_width(full_text, font_size) + pad_x * 2.0 + icon_w
		if want > max_w and compact_text != full_text:
			# Не влезла цена — «Заменить» без числа, цена остаётся в tooltip.
			caption = compact_text
			want = _text_width(compact_text, font_size) + pad_x * 2.0 + icon_w
		if want > max_w and icon_w > 0.0:
			# Совсем тесно: убираем иконку, цена остаётся в tooltip.
			reroll.icon = null
			icon_w = 0.0
			want = _text_width(caption, font_size) + pad_x * 2.0
		reroll.text = caption
		var button_w := minf(max_w, maxf(76.0 * scale, want))
		reroll.position = Vector2(inner_right - button_w, (height - button_h) * 0.5)
		reroll.size = Vector2(button_w, button_h)
		inner_right -= button_w + 8.0 * scale
	if reward != null and reward.visible:
		var reward_w := 64.0 * scale
		var reward_h := 20.0 * scale
		reward.position = Vector2(inner_right - reward_w, (height - reward_h) * 0.5)
		reward.size = Vector2(reward_w, reward_h)
		inner_right -= reward_w + 8.0 * scale
	var text_width := maxf(20.0, inner_right - 10.0 * scale)
	if title != null:
		title.position = Vector2(10.0 * scale, 0.0)
		title.size = Vector2(text_width, (21.0 if not mobile else 25.0) * scale)
	if bar != null:
		bar.position = Vector2(10.0 * scale, (21.0 if not mobile else 25.0) * scale)
		bar.size = Vector2(text_width, 4.0 * scale)
	if meta != null:
		var meta_top := (25.0 if not mobile else 29.0) * scale
		meta.position = Vector2(10.0 * scale, meta_top)
		meta.size = Vector2(text_width, maxf(4.0, height - meta_top))
		meta.vertical_alignment = VERTICAL_ALIGNMENT_TOP


func _layout_footer(width: float, height: float, pad: float, mobile: bool, scale: float) -> void:
	var row_a := (22.0 if mobile else 18.0) * scale
	var row_b := (22.0 if mobile else 20.0) * scale
	var gap := 2.0 * scale
	var chip_w := (44.0 if mobile else 18.0) * scale
	var chip_gap := (4.0 if mobile else 2.0) * scale
	for i in week_chips.size():
		var chip := week_chips[i]
		chip.position = Vector2(pad + float(i) * (chip_w + chip_gap), 0.0)
		chip.size = Vector2(chip_w, row_a)
	var chips_end := pad + float(WEEK_REQUIRED) * chip_w + float(WEEK_REQUIRED - 1) * chip_gap
	# Row A: дни недели слева, «Неделя: N/7 полных дней» справа.
	week_label.position = Vector2(chips_end + 8.0 * scale, 0.0)
	week_label.size = Vector2(maxf(40.0, width - pad - chips_end - 8.0 * scale), row_a)
	# Row B: иконка осколка + текст награды слева, кнопка «Забрать» справа.
	var claim_w := (180.0 if mobile else 150.0) * scale
	claim_button.position = Vector2(width - pad - claim_w, row_a + gap)
	claim_button.size = Vector2(claim_w, row_b)
	var icon_size := 16.0 * scale
	status_icon.position = Vector2(pad, row_a + gap + (row_b - icon_size) * 0.5)
	status_icon.size = Vector2(icon_size, icon_size)
	status_icon.visible = not quests.is_empty()
	status_label.position = Vector2(pad + icon_size + 6.0 * scale, row_a + gap)
	status_label.size = Vector2(
		maxf(40.0, width - pad * 2.0 - claim_w - 8.0 * scale - icon_size - 6.0 * scale),
		row_b
	)
	week_label.visible = not week_chips.is_empty()
	footer.visible = not quests.is_empty()


func _apply_height(animate: bool) -> void:
	_set_height(quests.size(), animate)
	_layout_content()


func _set_height(count: int, animate: bool) -> void:
	if mode == Mode.OVERLAY:
		if panel == null:
			return
		var target := panel_height_for(count)
		var top := -target * 0.5
		var bottom := target * 0.5
		if animate and is_inside_tree() and visible:
			# Тот же tween уже едет к этой высоте — второй не запускаем.
			if _tween != null and _tween.is_valid() \
					and absf(_tween_target - target) <= LAYOUT_EPSILON:
				return
			# Высота уже такая — не перезапускаем tween (иначе ресайз панели
			# идёт каждый кадр и снова ставит раскладку в очередь).
			if absf(panel.offset_top - top) <= LAYOUT_EPSILON \
					and absf(panel.offset_bottom - bottom) <= LAYOUT_EPSILON \
					and (_tween == null or not _tween.is_valid()):
				_tween_target = target
				return
			if _tween != null and _tween.is_valid():
				_tween.kill()
			_tween = create_tween()
			_tween_target = target
			_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_tween.set_parallel(true)
			_tween.tween_property(panel, "offset_top", top, TWEEN_TIME)
			_tween.tween_property(panel, "offset_bottom", bottom, TWEEN_TIME)
		else:
			_tween_target = target
			if _tween != null and _tween.is_valid():
				_tween.kill()
			if absf(panel.offset_top - top) <= LAYOUT_EPSILON \
					and absf(panel.offset_bottom - bottom) <= LAYOUT_EPSILON:
				return
			panel.offset_top = top
			panel.offset_bottom = bottom
	else:
		var target := panel_height_for(count)
		var bottom := offset_top + target
		if animate and is_inside_tree():
			if _tween != null and _tween.is_valid() \
					and absf(_tween_target - target) <= LAYOUT_EPSILON:
				return
			if absf(offset_bottom - bottom) <= LAYOUT_EPSILON \
					and (_tween == null or not _tween.is_valid()):
				_tween_target = target
				return
			if _tween != null and _tween.is_valid():
				_tween.kill()
			_tween = create_tween()
			_tween_target = target
			_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_tween.tween_property(self, "offset_bottom", bottom, TWEEN_TIME)
		else:
			_tween_target = target
			if _tween != null and _tween.is_valid():
				_tween.kill()
			if absf(offset_bottom - bottom) <= LAYOUT_EPSILON:
				return
			offset_bottom = bottom


func _scale(value: float) -> float:
	if mode != Mode.OVERLAY:
		return value
	if desktop_overlay:
		return value
	var viewport_size := get_viewport_rect().size
	if viewport_size.y <= 0.0:
		return value
	var factor := minf(
		viewport_size.x / MOBILE_REFERENCE.x,
		viewport_size.y / MOBILE_REFERENCE.y
	)
	return value * factor


# ---------------------------------------------------------------------------
# Ввод


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
	# Недельная награда — только осколки, предмет не запрашиваем.
	weekly_claim_requested.emit(0)


func _source() -> Node:
	return get_node_or_null("/root/DailyQuests")


# ---------------------------------------------------------------------------
# Оформление


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", _fs(size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.65))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_button(text: String, size: int, primary: bool, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", UI_FONT)
	button.add_theme_font_size_override("font_size", _fs(size))
	button.add_theme_color_override("font_color", Color(0.15, 0.1, 0.02) if primary else GOLD)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", _button_style(primary, false, false))
	button.add_theme_stylebox_override("hover", _button_style(primary, true, false))
	button.add_theme_stylebox_override("pressed", _button_style(primary, true, false))
	button.add_theme_stylebox_override("disabled", _button_style(primary, false, true))
	return button


func _style_claim_button(active: bool) -> void:
	claim_button.add_theme_stylebox_override("normal", _button_style(true, false, not active))
	claim_button.add_theme_stylebox_override("hover", _button_style(true, true, not active))
	claim_button.add_theme_stylebox_override("pressed", _button_style(true, true, not active))


func _button_style(primary: bool, hovered: bool, disabled: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if disabled:
		style.bg_color = Color(0.09, 0.11, 0.16, 0.9)
		style.border_color = Color(0.34, 0.4, 0.5, 0.75)
	elif primary:
		style.bg_color = Color(1.0, 0.8, 0.22) if not hovered else Color(1.0, 0.9, 0.42)
		style.border_color = Color(1.0, 0.94, 0.62)
	else:
		style.bg_color = Color(0.1, 0.13, 0.19, 0.95) if not hovered else Color(0.16, 0.2, 0.28, 1.0)
		style.border_color = GOLD if not hovered else Color(1.0, 0.88, 0.58)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


func _reroll_style(hovered: bool, disabled: bool) -> StyleBoxFlat:
	# Спокойная кнопка в стиле панели: тёмный фон, тонкая золотая рамка.
	var style := StyleBoxFlat.new()
	if disabled:
		style.bg_color = Color(0.075, 0.09, 0.13, 0.85)
		style.border_color = Color(0.34, 0.4, 0.5, 0.55)
	else:
		style.bg_color = Color(0.1, 0.13, 0.19, 0.95) if not hovered else Color(0.17, 0.21, 0.29, 1.0)
		style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.8) if not hovered else Color(1.0, 0.88, 0.58)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.065, 0.96)
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.85)
	style.set_border_width_all(2 if mode == Mode.OVERLAY else 1)
	style.set_corner_radius_all(14 if mode == Mode.OVERLAY else 10)
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 16 if mode == Mode.OVERLAY else 6
	style.shadow_offset = Vector2(0.0, 4.0 if mode == Mode.OVERLAY else 2.0)
	return style


func _reward_text(shards: int) -> String:
	return "+%d %s" % [shards, _plural(shards, "осколок", "осколка", "осколков")]


func _fs(size: int) -> int:
	if mode == Mode.OVERLAY:
		return maxi(size, 18)
	return size


## Ширина строки в пикселях тем же шрифтом, что и кнопки панели.
func _text_width(text: String, font_size: int) -> float:
	if text.is_empty():
		return 0.0
	return UI_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x


static func _plural(count: int, one: String, few: String, many: String) -> String:
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
		# Внутри обработчика ресайза не меняем ни anchors, ни size — только
		# ставим в очередь: так ресайз не может рекурсивно вызвать сам себя.
		if mode == Mode.OVERLAY and desktop_overlay:
			_queue_placement()
		_queue_layout()
