extends Control

# Виртуальный джойстик для телефона: пишет в те же действия, что и WASD.

const DEADZONE := 0.22
const BASE_RADIUS := 82.0
const KNOB_RADIUS := 34.0

var active_touch := -1
var knob_offset := Vector2.ZERO
var pressed_actions: Array[String] = []
var touch_device := false


func _ready() -> void:
	touch_device = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and active_touch < 0:
			active_touch = touch.index
			_update_knob(touch.position)
		elif not touch.pressed and touch.index == active_touch:
			active_touch = -1
			_reset()
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == active_touch:
			_update_knob(drag.position)
		return
	if touch_device:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				active_touch = 0
				_update_knob(mouse.position)
			else:
				active_touch = -1
				_reset()
		return
	if event is InputEventMouseMotion and active_touch == 0:
		_update_knob((event as InputEventMouseMotion).position)


func _center() -> Vector2:
	return size * 0.5


func _update_knob(position: Vector2) -> void:
	var offset := position - _center()
	if offset.length() > BASE_RADIUS:
		offset = offset.normalized() * BASE_RADIUS
	knob_offset = offset
	var direction := offset / BASE_RADIUS
	_set_action("move_left", direction.x < -DEADZONE)
	_set_action("move_right", direction.x > DEADZONE)
	_set_action("move_forward", direction.y < -DEADZONE)
	_set_action("move_back", direction.y > DEADZONE)
	queue_redraw()


func _set_action(action: String, active: bool) -> void:
	if active:
		if action not in pressed_actions:
			Input.action_press(action)
			pressed_actions.append(action)
	elif action in pressed_actions:
		Input.action_release(action)
		pressed_actions.erase(action)


func _reset() -> void:
	knob_offset = Vector2.ZERO
	for action in pressed_actions:
		Input.action_release(action)
	pressed_actions.clear()
	queue_redraw()


func _draw() -> void:
	var center := _center()
	draw_circle(center, BASE_RADIUS + 12.0, Color(0.03, 0.045, 0.07, 0.5))
	draw_circle(center, BASE_RADIUS, Color(0.08, 0.1, 0.15, 0.32))
	draw_arc(center, BASE_RADIUS + 12.0, 0.0, TAU, 64, Color(0.9, 0.78, 0.5, 0.55), 2.0)
	draw_arc(center, BASE_RADIUS, 0.0, TAU, 64, Color(0.9, 0.78, 0.5, 0.22), 1.0)
	var knob := center + knob_offset
	draw_circle(knob, KNOB_RADIUS, Color(0.9, 0.78, 0.5, 0.5))
	draw_arc(knob, KNOB_RADIUS, 0.0, TAU, 48, Color(1.0, 0.9, 0.62, 0.9), 2.0)
