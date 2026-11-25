extends Node

## Runtime UI layout registry.
##
## The web editor (ui_editor.html) sends rects for named controls in the
## 844x390 design space.  The rects are stored in ui_layout.json (baked into
## the build) and applied on every launch, so one hand-tuned layout works on
## every phone.  While the editor is open the same rects also live in
## localStorage for instant preview.

const REFERENCE_WIDTH := 844.0
const REFERENCE_HEIGHT := 390.0
const WEB_REFERENCE_WIDTH := 1280.0
const WEB_REFERENCE_HEIGHT := 720.0
const LAYOUT_PATH := "res://ui_layout.json"
const WEB_LAYOUT_PATH := "res://ui_layout_web.json"
const STORAGE_KEY := "three_skies_ui_layout"
const WEB_STORAGE_KEY := "three_skies_ui_layout_web"

var editor_mode := false
var web_mode := false
var _entries: Dictionary = {}
var _overrides: Dictionary = {}
var _js_installed := false
var _js_set_cb = null
var _js_reset_cb = null
var _refresh_queued := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	editor_mode = DeviceProfile.edit_mode
	web_mode = not DeviceProfile.mobile_ui
	_load_baked_layout()
	if editor_mode:
		_load_storage_layout()
		call_deferred("_install_js_api")
	if not get_viewport().size_changed.is_connected(_on_viewport_resized):
		get_viewport().size_changed.connect(_on_viewport_resized)


func register(id: String, control: Control, label: String, group := "lobby") -> void:
	if control == null or not is_instance_valid(control):
		return
	var entry: Dictionary = {
		"control": control,
		"label": label,
		"group": group,
		"parent": control.get_parent_control(),
		"parent_base_rect": Rect2(),
		"anchors": [
			control.anchor_left,
			control.anchor_top,
			control.anchor_right,
			control.anchor_bottom,
		],
		"offsets": [
			control.offset_left,
			control.offset_top,
			control.offset_right,
			control.offset_bottom,
		],
		"min_size": control.custom_minimum_size,
		"base_rect": Rect2(),
		"rect": Rect2(),
	}
	_entries[id] = entry
	_capture(id)


func has_override(id: String) -> bool:
	return _overrides.has(id)


func refresh_geometry() -> void:
	# Hidden screens (inventory, shop) have no size until they are opened.
	# Recapture their defaults right after the editor opens them.
	for id in _entries:
		var entry: Dictionary = _entries[id]
		var control: Control = entry["control"]
		if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
			continue
		var rect := _design_rect(control)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var parent: Control = entry["parent"]
		if parent != null and is_instance_valid(parent):
			entry["parent_base_rect"] = _design_rect(parent)
		else:
			entry["parent_base_rect"] = Rect2(Vector2.ZERO, Vector2(REFERENCE_WIDTH, REFERENCE_HEIGHT))
		if not _overrides.has(id):
			entry["base_rect"] = rect
			entry["rect"] = rect
		else:
			_apply(id, _overrides[id])
	_queue_js_refresh()


func _capture(id: String) -> void:
	await get_tree().process_frame
	if not _entries.has(id):
		return
	var entry: Dictionary = _entries[id]
	var control: Control = entry["control"]
	if control == null or not is_instance_valid(control):
		return
	if (entry["base_rect"] as Rect2).size.x <= 0.0:
		entry["base_rect"] = _design_rect(control)
	var parent: Control = entry["parent"]
	if parent != null and is_instance_valid(parent):
		entry["parent_base_rect"] = _design_rect(parent)
	else:
		entry["parent_base_rect"] = Rect2(Vector2.ZERO, Vector2(REFERENCE_WIDTH, REFERENCE_HEIGHT))
	if _overrides.has(id):
		_apply(id, _overrides[id])
	else:
		entry["rect"] = entry["base_rect"]
	_queue_js_refresh()


func _on_viewport_resized() -> void:
	call_deferred("_reapply_all")


func _reapply_all() -> void:
	for id in _entries:
		if _overrides.has(id):
			_apply(String(id), _overrides[id])
	_queue_js_refresh()


func _design_rect(control: Control) -> Rect2:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.y <= 0.0:
		return Rect2()
	if web_mode:
		var web_scale := minf(
			viewport_size.x / WEB_REFERENCE_WIDTH,
			viewport_size.y / WEB_REFERENCE_HEIGHT
		)
		if web_scale <= 0.0:
			return Rect2()
		var web_rect := control.get_global_rect()
		return Rect2(web_rect.position / web_scale, web_rect.size / web_scale)
	var scale := minf(viewport_size.x / REFERENCE_WIDTH, viewport_size.y / REFERENCE_HEIGHT)
	var rect := control.get_global_rect()
	return Rect2(rect.position / scale, rect.size / scale)


func _apply(id: String, rect: Rect2) -> void:
	if web_mode:
		_apply_web(id, rect)
		return
	if not _entries.has(id):
		return
	var entry: Dictionary = _entries[id]
	var control: Control = entry["control"]
	if control == null or not is_instance_valid(control):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.y <= 0.0:
		return
	var design_scale := minf(viewport_size.x / REFERENCE_WIDTH, viewport_size.y / REFERENCE_HEIGHT)
	# The layout is authored in the 844x390 design space. Classify and offset
	# against that space, not against the real viewport: on a long iPhone
	# screen (2.3:1) the viewport is wider than the reference, and elements
	# meant for the right edge fell into the "center" third and were anchored
	# to the middle of the screen.
	var design_width := REFERENCE_WIDTH
	var design_height := REFERENCE_HEIGHT
	var left := rect.position.x
	var top := rect.position.y
	var right := left + rect.size.x
	var bottom := top + rect.size.y
	var center_x := (left + right) * 0.5
	var center_y := (top + bottom) * 0.5

	if center_x < design_width / 3.0:
		control.anchor_left = 0.0
		control.anchor_right = 0.0
		control.offset_left = left * design_scale
		control.offset_right = right * design_scale
	elif center_x > design_width * 2.0 / 3.0:
		control.anchor_left = 1.0
		control.anchor_right = 1.0
		control.offset_left = (left - design_width) * design_scale
		control.offset_right = (right - design_width) * design_scale
	else:
		control.anchor_left = 0.5
		control.anchor_right = 0.5
		control.offset_left = (left - design_width * 0.5) * design_scale
		control.offset_right = (right - design_width * 0.5) * design_scale

	if center_y < design_height / 3.0:
		control.anchor_top = 0.0
		control.anchor_bottom = 0.0
		control.offset_top = top * design_scale
		control.offset_bottom = bottom * design_scale
	elif center_y > design_height * 2.0 / 3.0:
		control.anchor_top = 1.0
		control.anchor_bottom = 1.0
		control.offset_top = (top - design_height) * design_scale
		control.offset_bottom = (bottom - design_height) * design_scale
	else:
		control.anchor_top = 0.5
		control.anchor_bottom = 0.5
		control.offset_top = (top - design_height * 0.5) * design_scale
		control.offset_bottom = (bottom - design_height * 0.5) * design_scale

	# Controls that live in a list or had a size hint must be allowed to
	# shrink to the hand-picked rect.
	control.custom_minimum_size = rect.size * design_scale
	entry["rect"] = rect


func _apply_web(id: String, rect: Rect2) -> void:
	if not _entries.has(id):
		return
	var entry: Dictionary = _entries[id]
	var control: Control = entry["control"]
	if control == null or not is_instance_valid(control):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.y <= 0.0:
		return
	var scale := minf(
		viewport_size.x / WEB_REFERENCE_WIDTH,
		viewport_size.y / WEB_REFERENCE_HEIGHT
	)
	if scale <= 0.0:
		return
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = rect.position.x * scale
	control.offset_top = rect.position.y * scale
	control.offset_right = (rect.position.x + rect.size.x) * scale
	control.offset_bottom = (rect.position.y + rect.size.y) * scale
	control.custom_minimum_size = rect.size * scale
	entry["rect"] = rect


func _restore(id: String) -> void:
	if not _entries.has(id):
		return
	var entry: Dictionary = _entries[id]
	var control: Control = entry["control"]
	if control == null or not is_instance_valid(control):
		return
	var anchors: Array = entry["anchors"]
	var offsets: Array = entry["offsets"]
	control.anchor_left = anchors[0]
	control.anchor_top = anchors[1]
	control.anchor_right = anchors[2]
	control.anchor_bottom = anchors[3]
	control.offset_left = offsets[0]
	control.offset_top = offsets[1]
	control.offset_right = offsets[2]
	control.offset_bottom = offsets[3]
	control.custom_minimum_size = entry["min_size"]
	if (entry["base_rect"] as Rect2).size.x <= 0.0 or (entry["base_rect"] as Rect2).size.y <= 0.0:
		entry["base_rect"] = _design_rect(control)
	entry["rect"] = entry["base_rect"]


func _load_baked_layout() -> void:
	var path := WEB_LAYOUT_PATH if web_mode else LAYOUT_PATH
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_merge_layout(parsed)


func _load_storage_layout() -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	var bridge := Engine.get_singleton("JavaScriptBridge")
	var storage_key := WEB_STORAGE_KEY if web_mode else STORAGE_KEY
	var raw: Variant = bridge.call(
		"eval",
		"localStorage.getItem(%s)" % JSON.stringify(storage_key),
		true
	)
	if raw is String and not (raw as String).is_empty():
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			_merge_layout(parsed)


func _merge_layout(data: Dictionary) -> void:
	var elements: Variant = data.get("elements", {})
	if not (elements is Dictionary):
		return
	for raw_id in elements:
		var rect := _parse_rect(elements[raw_id])
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			_overrides[String(raw_id)] = rect


func _parse_rect(value: Variant) -> Rect2:
	if value is Dictionary:
		return Rect2(
			float(value.get("x", 0.0)),
			float(value.get("y", 0.0)),
			float(value.get("w", 0.0)),
			float(value.get("h", 0.0))
		)
	if value is Array and (value as Array).size() >= 4:
		var values: Array = value
		return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	return Rect2()


func _serialize_elements() -> Dictionary:
	var elements: Dictionary = {}
	for raw_id in _overrides:
		var rect: Rect2 = _overrides[raw_id]
		elements[String(raw_id)] = {
			"x": snappedf(rect.position.x, 0.1),
			"y": snappedf(rect.position.y, 0.1),
			"w": snappedf(rect.size.x, 0.1),
			"h": snappedf(rect.size.y, 0.1),
		}
	return elements


func _save_storage_layout() -> void:
	if not editor_mode or not OS.has_feature("web"):
		return
	if not Engine.has_singleton("JavaScriptBridge"):
		return
	var bridge := Engine.get_singleton("JavaScriptBridge")
	var payload := {
		"version": 1,
		"reference": {"width": REFERENCE_WIDTH, "height": REFERENCE_HEIGHT},
		"elements": _serialize_elements(),
	}
	var text := JSON.stringify(payload)
	var storage_key := WEB_STORAGE_KEY if web_mode else STORAGE_KEY
	bridge.call(
		"eval",
		"localStorage.setItem(%s, %s);" % [JSON.stringify(storage_key), JSON.stringify(text)],
		true
	)


func _install_js_api() -> void:
	if not editor_mode:
		return
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	var bridge := Engine.get_singleton("JavaScriptBridge")
	var window = bridge.call("get_interface", "window")
	if window == null:
		return
	_js_set_cb = bridge.call("create_callback", Callable(self, "_on_js_set_rect"))
	_js_reset_cb = bridge.call("create_callback", Callable(self, "_on_js_reset_rect"))
	# JavaScriptObject properties are assigned directly; .set() is forwarded
	# to JavaScript as a method call and fails on window.
	window.__uiSetRect = _js_set_cb
	window.__uiReset = _js_reset_cb
	window.__uiLayoutReady = false
	_js_installed = true
	_queue_js_refresh()


func _on_js_set_rect(args: Array) -> String:
	if args.size() < 5:
		return ""
	var id := String(args[0])
	var rect := Rect2(float(args[1]), float(args[2]), float(args[3]), float(args[4]))
	if rect.size.x < 1.0:
		rect.size.x = 1.0
	if rect.size.y < 1.0:
		rect.size.y = 1.0
	_overrides[id] = rect
	if _entries.has(id):
		_apply(id, rect)
	_queue_js_refresh()
	return _rect_json(rect)


func _on_js_reset_rect(args: Array) -> String:
	if args.is_empty():
		return ""
	var id := String(args[0])
	_overrides.erase(id)
	_restore(id)
	_queue_js_refresh()
	if _entries.has(id):
		var entry: Dictionary = _entries[id]
		return _rect_json(entry["base_rect"] as Rect2)
	return ""


func _rect_json(rect: Rect2) -> String:
	return JSON.stringify({
		"x": snappedf(rect.position.x, 0.1),
		"y": snappedf(rect.position.y, 0.1),
		"w": snappedf(rect.size.x, 0.1),
		"h": snappedf(rect.size.y, 0.1),
	})


func _queue_js_refresh() -> void:
	if not editor_mode or not _js_installed or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh_js")


func _refresh_js() -> void:
	_refresh_queued = false
	if not editor_mode or not _js_installed:
		return
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	var list: Array = []
	for raw_id in _entries.keys():
		var id := String(raw_id)
		var entry: Dictionary = _entries[id]
		var control: Control = entry["control"]
		if control == null or not is_instance_valid(control):
			_entries.erase(id)
			continue
		var rect: Rect2 = entry["rect"]
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			rect = entry["base_rect"]
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			rect = _design_rect(control)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		list.append({
			"id": id,
			"label": entry["label"],
			"group": entry["group"],
			"rect": {
				"x": snappedf(rect.position.x, 0.1),
				"y": snappedf(rect.position.y, 0.1),
				"w": snappedf(rect.size.x, 0.1),
				"h": snappedf(rect.size.y, 0.1),
			},
		})
	list.sort_custom(func(a, b): return String(a["label"]) < String(b["label"]))
	var bridge := Engine.get_singleton("JavaScriptBridge")
	bridge.call(
		"eval",
		"window.__uiLayoutElements = %s; window.__uiLayoutReady = true;" % JSON.stringify(list),
		true
	)
	# The editor also needs the full baked layout so a downloaded file keeps
	# the already tuned lobby/battle screens.
	var all_elements := _serialize_elements()
	bridge.call(
		"eval",
		"window.__uiLayoutAll = %s;" % JSON.stringify(all_elements),
		true
	)
