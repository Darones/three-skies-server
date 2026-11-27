extends CanvasLayer

## Screen-space nicknames above heroes and remote players, each with its own
## health bar.
##
## Every name is one 2D Label inside this shared CanvasLayer. Each frame the
## label projects its world anchor through Camera3D.unproject_position() and
## moves to that point, so the nickname is drawn by the canvas pipeline at full
## resolution. The old Label3D names went through the 3D pipeline: phones render
## 3D at DeviceProfile.quality_render_scale() (0.5 on low), which blurred the
## text into an unreadable smudge. Canvas text ignores scaling_3d_scale, so a
## name stays sharp at any quality.
##
## The layer sits on index 0: above the 3D world, below the HUD (CanvasLayer 1)
## so panels and menus still cover names. It is created lazily by the first
## hero/remote and lives with the current scene.
##
## Positioning reads Node3D.get_global_transform_interpolated(): heroes move in
## _physics_process while this label is drawn in _process, so the raw
## global_position snapped the text to the last physics tick and the name
## jittered whenever a frame did not match a tick. The interpolated transform is
## exactly the pose the renderer draws this frame, so no extra smoothing (and no
## extra lag) is needed. The final screen point is rounded to whole pixels:
## sub-pixel text positions resample the glyphs and shimmer while running.
##
## Only the positioning is handled here. Text, colour, bar value and visibility
## stay owned by the hero: `name_label.visible` keeps meaning "the player is
## allowed to see this nickname and its bar" (bush stealth, fog, preview mode),
## exactly like the old label. Being off-screen moves the label away but does not
## touch `visible`.

const LAYER_NAME := "WorldNameLayer"
const LAYER_INDEX := 0

static var _shared: CanvasLayer = null


## One nickname block. It is a plain Label, so callers keep using text, visible,
## font and theme colour overrides just like the old Label3D.
class NameTag extends Label:
	const FONT: FontFile = preload("res://assets/fonts/Philosopher-Bold.ttf")
	const FONT_SIZE_DESKTOP := 20
	const FONT_SIZE_MOBILE := 19
	const OUTLINE_SIZE := 4
	# A fixed box centred on the projected head point. It keeps the text centred
	# without re-measuring the label every frame; the box has no background.
	const TEXT_BOX := Vector2(320.0, 30.0)
	# Parked far outside the viewport instead of visible = false, so `visible`
	# stays the owner's decision only.
	const OFF_SCREEN := Vector2(-4000.0, -4000.0)
	# The HP bar is a child of this label: a dark back plus a coloured fill,
	# centred under the text with a constant pixel gap. Being a child means it is
	# covered, hidden and parked together with the nickname and can never drift
	# away from it. Sizes are fixed, the fill width carries the ratio.
	const BAR_SIZE := Vector2(96.0, 7.0)
	const BAR_GAP := 2.0
	const BAR_BACK_COLOR := Color(0.02, 0.03, 0.05, 0.78)
	const BAR_FILL_COLOR := Color(0.36, 0.95, 0.52, 1.0)

	var anchor: Node3D = null
	var world_offset := Vector3(0.0, 2.78, 0.0)
	var camera: Camera3D = null
	var bar_back: ColorRect = null
	var bar_fill: ColorRect = null
	var health_ratio := 1.0
	var health_color := BAR_FILL_COLOR
	var health_shown := true
	# Last unclamped projection, kept for probes that compare the drawn position
	# with the exact head point of the same frame.
	var last_projected_point := Vector2.ZERO

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		autowrap_mode = TextServer.AUTOWRAP_OFF
		clip_text = false
		size = TEXT_BOX
		add_theme_font_override("font", FONT)
		add_theme_font_size_override(
			"font_size",
			FONT_SIZE_MOBILE if DeviceProfile.mobile_ui else FONT_SIZE_DESKTOP
		)
		# A hard black contour plus a soft drop shadow: readable over the bright
		# sky, dark cliffs and the fog plane, and still crisp at 1x.
		add_theme_constant_override("outline_size", OUTLINE_SIZE)
		add_theme_color_override("font_outline_color", Color(0.015, 0.02, 0.035, 1.0))
		add_theme_constant_override("shadow_offset_x", 0)
		add_theme_constant_override("shadow_offset_y", 2)
		add_theme_constant_override("shadow_outline_size", 2)
		add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
		_build_health_bar()
		if anchor != null and is_instance_valid(anchor) and not anchor.tree_exiting.is_connected(queue_free):
			anchor.tree_exiting.connect(queue_free, CONNECT_ONE_SHOT)
		set_process(true)

	func _process(_delta: float) -> void:
		if anchor == null or not is_instance_valid(anchor) or not anchor.is_inside_tree():
			queue_free()
			return
		var cam := camera
		if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree():
			cam = get_viewport().get_camera_3d()
			camera = cam
		if cam == null:
			position = OFF_SCREEN
			return
		var world := _interpolated_anchor_position() + world_offset
		if cam.is_position_behind(world):
			position = OFF_SCREEN
			return
		var screen := cam.unproject_position(world)
		last_projected_point = screen
		var view := get_viewport_rect().size
		if view.x <= 1.0 or view.y <= 1.0:
			position = OFF_SCREEN
			return
		# Keep labels that point past the edge out of the corners: unproject
		# returns a valid point even for objects outside the frustum.
		if screen.x < -TEXT_BOX.x or screen.y < -TEXT_BOX.y \
				or screen.x > view.x + TEXT_BOX.x or screen.y > view.y + TEXT_BOX.y:
			position = OFF_SCREEN
			return
		# Whole pixels: the text and the bar stay on the same grid every frame.
		position = Vector2(
			roundf(screen.x - size.x * 0.5),
			roundf(screen.y - size.y)
		)

	## World position the renderer draws this frame. `anchor` is a Node3D, but the
	## caller may hand over a plain Node in tests: then fall back to the offset
	## only instead of failing.
	func _interpolated_anchor_position() -> Vector3:
		var node: Node = anchor
		if node == null or not is_instance_valid(node):
			return Vector3.ZERO
		if node is Node3D:
			var spatial := node as Node3D
			if spatial.has_method("get_global_transform_interpolated"):
				return spatial.get_global_transform_interpolated().origin
			return spatial.global_position
		return Vector3.ZERO

	func _build_health_bar() -> void:
		bar_back = ColorRect.new()
		bar_back.name = "HealthBarBack"
		bar_back.color = BAR_BACK_COLOR
		bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar_back)
		# Anchored to the bottom edge of the text box: offsets are measured from
		# that anchor, so the gap under the text stays a fixed 2 px whatever the
		# nickname width is. (Control.position is in parent coordinates, so it
		# must not be used here: with anchor_top = 1 it would place the bar over
		# the text.) The size comes from the offsets: 96 x 7.
		bar_back.anchor_left = 0.5
		bar_back.anchor_right = 0.5
		bar_back.anchor_top = 1.0
		bar_back.anchor_bottom = 1.0
		bar_back.offset_left = -BAR_SIZE.x * 0.5
		bar_back.offset_right = BAR_SIZE.x * 0.5
		bar_back.offset_top = BAR_GAP
		bar_back.offset_bottom = BAR_GAP + BAR_SIZE.y

		bar_fill = ColorRect.new()
		bar_fill.name = "HealthBarFill"
		bar_fill.color = health_color
		bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_back.add_child(bar_fill)
		bar_fill.position = Vector2.ZERO
		bar_fill.size = Vector2(BAR_SIZE.x * health_ratio, BAR_SIZE.y)
		bar_back.visible = health_shown

	## ratio: 0..1 of the remaining health. color: same source as the nickname
	## colour (self/ally green, enemy red).
	func set_health(ratio: float, color: Color) -> void:
		health_ratio = clampf(ratio, 0.0, 1.0)
		health_color = color
		_apply_health_fill()

	## The bar follows the nickname, but a dead or occluded hero has no bar.
	func set_health_visible(shown: bool) -> void:
		health_shown = shown
		if bar_back != null and is_instance_valid(bar_back):
			bar_back.visible = shown

	func _apply_health_fill() -> void:
		if bar_fill == null or not is_instance_valid(bar_fill):
			return
		var width := BAR_SIZE.x
		if bar_back != null and is_instance_valid(bar_back) and bar_back.size.x > 1.0:
			width = bar_back.size.x
		bar_fill.color = health_color
		# Fill width == ratio: probes read the ratio back from this width.
		bar_fill.size = Vector2(width * health_ratio, BAR_SIZE.y)


## Returns a ready nickname Label for `anchor` (a HeroUnit or RemotePlayer).
## Never returns null: if no layer can be created the label just stays detached.
static func create_label(anchor: Node3D, height := 2.78, camera: Camera3D = null) -> Label:
	var tag := NameTag.new()
	tag.anchor = anchor
	tag.world_offset = Vector3(0.0, height, 0.0)
	tag.camera = camera
	var layer := _ensure_layer(anchor)
	if layer != null:
		layer.add_child(tag)
	return tag


static func _ensure_layer(context: Node) -> CanvasLayer:
	if _shared != null and is_instance_valid(_shared) and _shared.is_inside_tree():
		return _shared
	_shared = null
	if context == null or not context.is_inside_tree():
		return null
	var tree := context.get_tree()
	if tree == null:
		return null
	var host: Node = tree.current_scene
	if host == null or not host.is_inside_tree():
		host = tree.root
	if host == null:
		return null
	var layer := CanvasLayer.new()
	layer.name = LAYER_NAME
	layer.layer = LAYER_INDEX
	layer.follow_viewport_enabled = false
	host.add_child(layer)
	_shared = layer
	return layer
