extends CanvasLayer

## Screen-space nicknames above heroes and remote players.
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
## Only the positioning is handled here. Text, colour and visibility stay owned
## by the hero: `name_label.visible` keeps meaning "the player is allowed to see
## this nickname" (bush stealth, fog, preview mode), exactly like the old label.
## Being off-screen moves the label away but does not touch `visible`.

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

	var anchor: Node3D = null
	var world_offset := Vector3(0.0, 2.78, 0.0)
	var camera: Camera3D = null

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
		var world := anchor.global_position + world_offset
		if cam.is_position_behind(world):
			position = OFF_SCREEN
			return
		var screen := cam.unproject_position(world)
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
		position = Vector2(screen.x - size.x * 0.5, screen.y - size.y)


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
