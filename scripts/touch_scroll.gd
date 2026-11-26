extends ScrollContainer

## Finger-drag scrolling for a ScrollContainer.
##
## A ScrollContainer scrolls with the wheel and with the scrollbar, but a
## finger drag over the content does nothing on a phone, so lists (inventory,
## match results) could only be moved by grabbing the thin scrollbar.
##
## This node catches InputEventScreenDrag inside its own rect and moves
## scroll_vertical 1:1 with the finger.
##
## With the default input_devices/pointing/emulate_mouse_from_touch a finger
## drag also produces mouse events, so the mouse path is off while that
## setting is on, and a drag that scrolled is marked handled: the list can
## never move twice for one finger. A real mouse drag (desktop, emulation off)
## works the same way and only starts after a few pixels, so a plain click
## still reaches buttons. A gesture that scrolled ends with the card under the
## finger muted, so scrolling never equips a weapon or opens a card.

## Pixels a finger must travel before the scroll starts; keeps taps crisp.
const DRAG_THRESHOLD := 4.0

@export var drag_scroll_enabled := true
@export var mouse_drag_scroll := true

var _touch_index := -1
var _touch_from_content := false
var _touch_origin := Vector2.ZERO
var _touch_dragging := false
var _mouse_from_content := false
var _mouse_origin := Vector2.ZERO
var _mouse_dragging := false
# Set when a scrolling touch ends, so the tap that finishes the gesture does
# not also press whatever card the finger happened to start on.
var _swallow_mouse_release := false
# The button the drag started on: its signals are muted until the gesture
# ends, so a scroll never equips or opens the card under the finger.
var _blocked_button: Node = null
var _blocked_button_at := 0
# Sub-pixel remainder of a drag so slow finger moves are not rounded away.
var _scroll_debt := 0.0


func _input(event: InputEvent) -> void:
	if not drag_scroll_enabled or not is_visible_in_tree():
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		_on_touch(touch)
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		_on_touch_drag(drag)
		return
	var button := event as InputEventMouseButton
	if button != null:
		_on_mouse_button(button)
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_on_mouse_motion(motion)


func is_drag_scrolling() -> bool:
	return _touch_dragging or _mouse_dragging


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_swallow_mouse_release = false
		# A second finger during an active drag is ignored; a press after a
		# release we never saw (a popup ate it) takes over cleanly.
		if _touch_index != -1 and _touch_dragging:
			return
		_touch_index = event.index
		_touch_origin = event.position
		_touch_dragging = false
		_scroll_debt = 0.0
		_touch_from_content = _starts_on_content(event.position)
	elif event.index == _touch_index:
		_touch_index = -1
		_touch_from_content = false
		_touch_dragging = false
		if _swallow_mouse_release:
			# The gesture scrolled: do not let its release activate the card
			# the finger started on (buttons act on touch release here).
			_swallow_mouse_release = false
			get_viewport().set_input_as_handled()


func _on_touch_drag(event: InputEventScreenDrag) -> void:
	if event.index != _touch_index or not _touch_from_content:
		return
	if not _touch_dragging:
		if absf(event.position.y - _touch_origin.y) < DRAG_THRESHOLD:
			return
		_touch_dragging = true
		_swallow_mouse_release = true
		_block_pressed_button()
		# The threshold pixels are part of the gesture, not dropped.
		_apply_drag(event.position.y - _touch_origin.y)
		return
	_apply_drag(event.relative.y)


func _on_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _swallow_mouse_release:
		_swallow_mouse_release = false
		if not event.pressed:
			# End of a finger scroll: the emulated click would open the card
			# the gesture started on.
			get_viewport().set_input_as_handled()
			return
	if not mouse_drag_scroll or _emulates_mouse_from_touch():
		return
	if event.pressed:
		_mouse_origin = event.position
		_mouse_dragging = false
		_scroll_debt = 0.0
		_mouse_from_content = _starts_on_content(event.position)
	else:
		_mouse_from_content = false
		_mouse_dragging = false


func _on_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _mouse_from_content:
		return
	if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_mouse_from_content = false
		_mouse_dragging = false
		return
	if not _mouse_dragging:
		if absf(event.position.y - _mouse_origin.y) < DRAG_THRESHOLD:
			return
		_mouse_dragging = true
		_swallow_mouse_release = true
		_block_pressed_button()
		_apply_drag(event.position.y - _mouse_origin.y)
		return
	_apply_drag(event.relative.y)


func _block_pressed_button() -> void:
	_restore_blocked_button()
	var node: Node = get_viewport().gui_get_hovered_control()
	while node != null and node != self and not (node is BaseButton):
		node = node.get_parent()
	if node is BaseButton and node.is_inside_tree():
		_blocked_button = node
		_blocked_button_at = Time.get_ticks_msec()
		_blocked_button.set_block_signals(true)


func _restore_blocked_button() -> void:
	if _blocked_button != null:
		if is_instance_valid(_blocked_button):
			_blocked_button.set_block_signals(false)
		_blocked_button = null


func _process(_delta: float) -> void:
	if _blocked_button == null:
		return
	# The release that ends the gesture normally restores the button; the
	# timer only covers a release a popup swallowed, so a card can never stay
	# deaf to taps.
	if (not _touch_dragging and _touch_index == -1 and not _mouse_dragging) \
			or Time.get_ticks_msec() - _blocked_button_at > 1500:
		_restore_blocked_button()


func _apply_drag(delta_y: float) -> void:
	if is_zero_approx(delta_y):
		return
	_scroll_debt += delta_y
	var step := int(_scroll_debt)
	if step == 0:
		return
	_scroll_debt -= float(step)
	var before := scroll_vertical
	scroll_vertical = before - step
	if scroll_vertical != before:
		# Stop whatever else could scroll the same drag (ScrollContainer's own
		# handling, a parent list) from applying it a second time.
		get_viewport().set_input_as_handled()


func _starts_on_content(point: Vector2) -> bool:
	if not get_global_rect().has_point(point):
		return false
	# A modal above the list (nickname popup, dim overlay) stops the touch
	# itself; it must not scroll the list it covers either.
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and hovered != self and not is_ancestor_of(hovered):
		return false
	return not _point_over_drag_control(point)


func _point_over_drag_control(point: Vector2) -> bool:
	# Sliders and text fields own their drag; scrolling under them would move
	# the list and the widget at the same time.
	var node: Node = get_viewport().gui_get_hovered_control()
	while node != null and node != self:
		if node is Slider or node is SpinBox or node is LineEdit or node is TextEdit:
			return true
		node = node.get_parent()
	return false


func _emulates_mouse_from_touch() -> bool:
	return bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true))
