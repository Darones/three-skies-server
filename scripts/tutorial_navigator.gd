extends Control

const EDGE_MARGIN := 84.0
const ARROW_LENGTH := 26.0
const ARROW_WIDTH := 15.0

var game: Node
var pulse := 0.0


func configure(game_instance: Node) -> void:
	game = game_instance
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	pulse += delta
	var active := game != null and bool(game.get("tutorial_target_active"))
	if visible != active:
		visible = active
	if active:
		queue_redraw()


func _draw() -> void:
	if game == null:
		return
	var camera: Camera3D = game.get("camera")
	if camera == null or not is_instance_valid(camera):
		return
	var world: Vector3 = game.get("tutorial_target_position")
	var screen := camera.unproject_position(world)
	var viewport_size := get_viewport_rect().size
	var center := viewport_size * 0.5
	var direction := screen - center
	if camera.is_position_behind(world):
		direction = Vector2.DOWN
	elif direction.length() < 1.0:
		direction = Vector2.UP
	direction = direction.normalized()

	var radius := minf(viewport_size.x, viewport_size.y) * 0.5 - EDGE_MARGIN
	var anchor := center + direction * radius
	var color: Color = game.get("tutorial_target_color")
	var blink := 0.55 + 0.45 * (0.5 + 0.5 * sin(pulse * 5.0))

	var side := direction.orthogonal() * ARROW_WIDTH
	var tip := anchor + direction * ARROW_LENGTH
	var base := anchor - direction * (ARROW_LENGTH * 0.45)
	draw_colored_polygon(
		PackedVector2Array([tip, base + side, base - side]),
		Color(color.r, color.g, color.b, blink)
	)
	draw_arc(anchor, ARROW_LENGTH + 16.0, 0.0, TAU, 32, Color(color.r, color.g, color.b, blink * 0.35), 2.0, true)
