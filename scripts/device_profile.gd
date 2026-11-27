extends Node

## Device profiles and debug preview modes.
## Phone browsers and the --device=a56 preview use the mobile layout; desktop
## builds keep the original 1280x720 layout.

const A56_WINDOW_SIZE := Vector2i(1560, 720)
const MOBILE_CONTENT_SCALE := Vector2i(960, 540)
const MOBILE_CAMERA_DISTANCE := 12.0
const MOBILE_MIN_ZOOM := 9.5
const MOBILE_MAX_ZOOM := 32.0

const SETTINGS_PATH := "user://settings.cfg"
const QUALITY_LOW := "low"
const QUALITY_MEDIUM := "medium"
const QUALITY_HIGH := "high"
const QUALITY_VALUES := [QUALITY_LOW, QUALITY_MEDIUM, QUALITY_HIGH]

const PHONE_PROBE_JS := "(function(){try{var ua=navigator.userAgent||'';var touch=(navigator.maxTouchPoints||0)>0;var coarse=false;try{coarse=!!(window.matchMedia&&window.matchMedia('(pointer: coarse)').matches);}catch(e){}var uaPhone=/Android|iPhone|iPad|iPod|Mobi|Windows Phone/i.test(ua);var narrow=(window.innerWidth||0)<=900;return uaPhone||narrow||(touch&&coarse);}catch(e){return false;}})()"

var mobile_ui := false
var is_vk := false
var touch_controls := false
var quality_override := ""
var graphics_quality := QUALITY_HIGH
var show_fps := false
var device := ""
var edit_mode := false
var auto_battle := false
var auto_tutorial := false
var edit_screen := ""
var profile_mode := false
var camera_distance := 16.0
var min_zoom_distance := 12.0
var max_zoom_distance := 42.0

var _screenshot_path := ""
var _web_phone := false
var _screenshot_delay := 6.0
var _capture_started := false
var _quality_saved := false
var _fps_label: Label
var _fps_timer := 0.0
var _base_msaa := -1
var _base_screen_aa := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_display_settings()
	var args := OS.get_cmdline_user_args()
	var url_search := ""
	for arg in args:
		if arg == "--mobile" or arg == "--touch":
			mobile_ui = true
			touch_controls = true
		elif arg == "--edit":
			edit_mode = true
			mobile_ui = true
			touch_controls = true
		elif arg == "--auto-battle":
			auto_battle = true
		elif arg == "--auto-tutorial":
			auto_tutorial = true
		elif arg == "--profile":
			profile_mode = true
		elif arg.begins_with("--view="):
			edit_screen = arg.trim_prefix("--view=")
		elif arg.begins_with("--device="):
			device = arg.trim_prefix("--device=")
		elif arg.begins_with("--screenshot="):
			_screenshot_path = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--screenshot-delay="):
			_screenshot_delay = maxf(0.5, float(arg.trim_prefix("--screenshot-delay=")))

	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var bridge := Engine.get_singleton("JavaScriptBridge")
		var search := str(bridge.call("eval", "window.location.search", true))
		url_search = search
		_web_phone = bool(bridge.call("eval", PHONE_PROBE_JS, true))
		var vk_probe: Variant = bridge.call(
			"eval",
			"(typeof window.vkBridge !== 'undefined') || /(^|[?&])vk_/.test(window.location.search)",
			true
		)
		is_vk = bool(vk_probe)
		if search.contains("mobile=1") or search.contains("touch=1"):
			mobile_ui = true
			touch_controls = true
		if search.contains("edit=1"):
			edit_mode = true
		if search.contains("autoplay=1"):
			auto_battle = true
		if search.contains("tutorial=1"):
			auto_tutorial = true
		if search.contains("profile=1"):
			profile_mode = true
		var view_pos := search.find("view=")
		if view_pos >= 0:
			var view_value := search.substr(view_pos + 5)
			var amp := view_value.find("&")
			if amp >= 0:
				view_value = view_value.substr(0, amp)
			edit_screen = view_value
		var quality_pos := search.find("q=")
		if quality_pos >= 0:
			var quality_value := search.substr(quality_pos + 2)
			var amp := quality_value.find("&")
			if amp >= 0:
				quality_value = quality_value.substr(0, amp)
			quality_override = quality_value

	var force_desktop := url_search.contains("mobile=0") or url_search.contains("desktop=1")
	if OS.has_feature("mobile"):
		mobile_ui = true
		touch_controls = true
	elif OS.has_feature("web") and not force_desktop and (
			_web_phone
			or OS.has_feature("web_android") or OS.has_feature("web_ios")
			or DisplayServer.is_touchscreen_available()):
		mobile_ui = true
		touch_controls = true

	print("[DeviceProfile] mobile_ui=%s web_phone=%s web_android=%s web_ios=%s touchscreen=%s" % [
		mobile_ui, _web_phone, OS.has_feature("web_android"),
		OS.has_feature("web_ios"), DisplayServer.is_touchscreen_available(),
	])

	if device == "a56":
		mobile_ui = true
		touch_controls = true
		DisplayServer.window_set_size(A56_WINDOW_SIZE)

	if mobile_ui:
		get_tree().root.content_scale_size = MOBILE_CONTENT_SCALE
		camera_distance = MOBILE_CAMERA_DISTANCE
		min_zoom_distance = MOBILE_MIN_ZOOM
		max_zoom_distance = MOBILE_MAX_ZOOM

	if not _quality_saved:
		# Phones start on low: less heat and a steadier frame rate. Desktop
		# keeps the full look. The player can change this in the settings.
		graphics_quality = QUALITY_LOW if mobile_ui else QUALITY_HIGH
	apply_graphics_quality()
	_setup_fps_overlay()

	if not _screenshot_path.is_empty():
		_start_screenshot()


func effective_quality() -> String:
	if quality_override == "full":
		return QUALITY_HIGH
	return graphics_quality


func quality_render_scale() -> float:
	if quality_override == "full" or quality_override == "noscale":
		return 1.0
	match graphics_quality:
		QUALITY_LOW:
			return 0.5
		QUALITY_MEDIUM:
			return 0.65 if mobile_ui else 0.85
		_:
			return 0.9 if mobile_ui else 1.0


func apply_graphics_quality() -> void:
	if get_tree() == null:
		return
	var viewport := get_tree().root
	if viewport == null:
		return
	if _base_msaa < 0:
		_base_msaa = viewport.msaa_3d
		_base_screen_aa = viewport.screen_space_aa
	viewport.scaling_3d_scale = quality_render_scale()
	if effective_quality() == QUALITY_HIGH:
		viewport.msaa_3d = _base_msaa
		viewport.screen_space_aa = _base_screen_aa
	else:
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED


func set_graphics_quality(value: String) -> void:
	if not QUALITY_VALUES.has(value):
		return
	graphics_quality = value
	_quality_saved = true
	apply_graphics_quality()
	_save_display_value("video", "quality", value)


func set_show_fps(enabled: bool) -> void:
	show_fps = enabled
	_save_display_value("video", "show_fps", enabled)
	if _fps_label != null:
		_fps_label.visible = enabled
		_fps_timer = 0.0


func _load_display_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	if config.has_section_key("video", "quality"):
		var value := String(config.get_value("video", "quality"))
		if QUALITY_VALUES.has(value):
			graphics_quality = value
			_quality_saved = true
	if config.has_section_key("video", "show_fps"):
		show_fps = bool(config.get_value("video", "show_fps"))


func _save_display_value(section: String, key: String, value: Variant) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(section, key, value)
	config.save(SETTINGS_PATH)


func _setup_fps_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FpsOverlay"
	layer.layer = 128
	add_child(layer)
	_fps_label = Label.new()
	_fps_label.name = "FpsLabel"
	_fps_label.anchor_left = 0.5
	_fps_label.anchor_right = 0.5
	_fps_label.offset_left = -80.0
	_fps_label.offset_right = 80.0
	_fps_label.offset_top = 4.0
	_fps_label.offset_bottom = 28.0
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps_label.add_theme_font_size_override("font_size", 15)
	_fps_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.75))
	_fps_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.visible = show_fps
	layer.add_child(_fps_label)


func _process(delta: float) -> void:
	if not show_fps or _fps_label == null:
		return
	_fps_timer += delta
	if _fps_timer < 0.5:
		return
	_fps_timer = 0.0
	var fps := Engine.get_frames_per_second()
	_fps_label.text = "%d FPS" % fps
	_fps_label.add_theme_color_override(
		"font_color",
		Color(0.55, 1.0, 0.6) if fps >= 50 else (Color(1.0, 0.85, 0.4) if fps >= 30 else Color(1.0, 0.45, 0.4))
	)


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
