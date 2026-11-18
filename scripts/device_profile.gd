extends Node

## Device profiles and debug preview modes.
## Phone browsers and the --device=a56 preview use the mobile layout; desktop
## builds keep the original 1280x720 layout.

const A56_WINDOW_SIZE := Vector2i(1560, 720)
const MOBILE_CONTENT_SCALE := Vector2i(960, 540)
const MOBILE_CAMERA_DISTANCE := 12.0
const MOBILE_MIN_ZOOM := 9.5
const MOBILE_MAX_ZOOM := 32.0

var mobile_ui := false
var touch_controls := false
var device := ""
var camera_distance := 16.0
var min_zoom_distance := 12.0
var max_zoom_distance := 42.0

var _screenshot_path := ""
var _screenshot_delay := 6.0
var _capture_started := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--mobile" or arg == "--touch":
			mobile_ui = true
			touch_controls = true
		elif arg.begins_with("--device="):
			device = arg.trim_prefix("--device=")
		elif arg.begins_with("--screenshot="):
			_screenshot_path = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--screenshot-delay="):
			_screenshot_delay = maxf(0.5, float(arg.trim_prefix("--screenshot-delay=")))

	if OS.has_feature("mobile"):
		mobile_ui = true
		touch_controls = true
	elif OS.has_feature("web") and DisplayServer.is_touchscreen_available():
		mobile_ui = true
		touch_controls = true

	if device == "a56":
		mobile_ui = true
		touch_controls = true
		DisplayServer.window_set_size(A56_WINDOW_SIZE)

	if mobile_ui:
		get_tree().root.content_scale_size = MOBILE_CONTENT_SCALE
		camera_distance = MOBILE_CAMERA_DISTANCE
		min_zoom_distance = MOBILE_MIN_ZOOM
		max_zoom_distance = MOBILE_MAX_ZOOM

	if not _screenshot_path.is_empty():
		_start_screenshot()


func _start_screenshot() -> void:
	if _capture_started:
		return
	_capture_started = true
	await get_tree().create_timer(_screenshot_delay).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_screenshot_path)
	print("[DeviceProfile] screenshot %s error=%d size=%s" % [_screenshot_path, error, image.get_size()])
	get_tree().quit()
